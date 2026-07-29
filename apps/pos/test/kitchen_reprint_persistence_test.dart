@TestOn('vm')
library;

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenCount, KitchenMeat, KitchenPrepComponent, OrderType;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show buildKdsTicketPrintDocument;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart'
    show CashPayment, PaymentMethod, PaymentStatus;
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/print/print_document.dart'
    show documentToHtml;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;
import 'package:shared_preferences/shared_preferences.dart';

/// PRINT-STARTUP-REPRINT-001 (Defect 2) — pins the DURABLE half of the contract:
/// the order-time kitchen snapshots survive a relaunch, an OLDER persisted
/// record degrades honestly instead of fabricating quantities, and the customer
/// receipt is untouched by any of it.

const _line = SubmittedLineView(
  name: 'Classic Burger',
  quantity: 1,
  lineTotalMinor: 7900,
  currencyCode: 'ILS',
  modifiers: ['Extra meat ×2', 'Ketchup ×2', 'Make it a meal'],
  note: 'no onions',
  categoryDisplayOrder: 1,
  itemDisplayOrder: 1,
  linePosition: 1,
  kitchenMeats: [KitchenMeat(quantity: 2, unit: 'قطع لحم')],
  prepComponents: [KitchenPrepComponent(name: 'خبز', quantity: 1)],
);

const _order = SubmittedOrderView(
  orderNumber: '#3F7A2C',
  orderType: OrderType.dineIn,
  tableLabel: 'T2',
  currencyCode: 'ILS',
  subtotalMinor: 7900,
  lines: [_line],
);

final _payment = CashPayment(
  paymentId: 'pay-1',
  orderNumber: '#3F7A2C',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 7900,
  tenderedMinor: 8000,
  changeMinor: 100,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.utc(2026, 7, 29, 10),
);

KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket preview',
  dineIn: 'Dine-in',
  takeaway: 'Takeaway',
  tableLabel: 'Table',
  customerLabel: 'Customer',
  customerPhoneLabel: 'Phone',
  stationLabel: 'Station',
  noteLabel: 'Note',
  kitchenTotal: (count, unit) => 'KCount $count $unit',
);

List<String> _texts(dynamic doc) => [
  for (final l in doc.lines) l.left ?? l.right ?? '',
];

/// A real round-trip through the shared_preferences-backed store.
Future<SubmittedOrderView> _roundTrip(SubmittedOrderView order) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final store = SharedPrefsRecentOrdersStore(prefs);
  await store.persist('device-1', [
    PosRecentOrder(order: order, submittedAt: DateTime.utc(2026, 7, 29, 9)),
  ]);
  // A fresh store over the same prefs — i.e. what a relaunch reads.
  final reloaded = await SharedPrefsRecentOrdersStore(prefs).load('device-1');
  return reloaded.single.order!;
}

void main() {
  test('11. the kitchen snapshots SURVIVE persist + reload, so a reprint after '
      'a relaunch still aggregates the same counts', () async {
    final reloaded = await _roundTrip(_order);

    expect(reloaded.lines.single.kitchenMeats, [
      const KitchenMeat(quantity: 2, unit: 'قطع لحم'),
    ]);
    expect(reloaded.lines.single.prepComponents, [
      const KitchenPrepComponent(name: 'خبز', quantity: 1),
    ]);

    // What actually matters: the reprint built from the RELOADED record.
    final before = kdsTicketViewFromSubmittedOrder(_order);
    final after = kdsTicketViewFromSubmittedOrder(reloaded);
    expect(after.kitchenCounts, before.kitchenCounts);
    expect(after.kitchenCounts, [
      const KitchenCount(quantity: 2, label: 'قطع لحم'),
      const KitchenCount(quantity: 1, label: 'خبز'),
    ]);

    final doc = buildKdsTicketPrintDocument(ticket: after, labels: _labels());
    expect(_texts(doc), contains('KCount 2 قطع لحم'));
    expect(_texts(doc), contains('KCount 1 خبز'));
  });

  test(
    '12. an OLDER persisted record without the new fields decodes cleanly '
    'and degrades HONESTLY — no crash, no fabricated counts, no catalog read',
    () {
      // Exactly what _lineToJson produced BEFORE this change.
      final legacy = PosRecentOrder.fromJson(<String, Object?>{
        'submitted_at': '2026-07-20T09:00:00.000Z',
        'order': <String, Object?>{
          'order_number': '#OLD01',
          'order_type': 'dineIn',
          'currency_code': 'ILS',
          'subtotal_minor': 7900,
          'discount_total_minor': 0,
          'tax_total_minor': 0,
          'tax_rate_bp': 0,
          'lines': [
            <String, Object?>{
              'name': 'Classic Burger',
              'quantity': 1,
              'line_total_minor': 7900,
              'currency_code': 'ILS',
              'modifiers': ['Extra meat ×2', 'Ketchup ×2'],
              'note': 'no onions',
            },
          ],
        },
      });

      final line = legacy.order!.lines.single;
      expect(line.kitchenMeats, isEmpty);
      expect(line.prepComponents, isEmpty);

      final ticket = kdsTicketViewFromSubmittedOrder(legacy.order!);
      // The visible per-modifier text still prints from the STORED strings.
      expect(ticket.items.single.modifiers, ['Extra meat ×2', 'Ketchup ×2']);
      expect(ticket.items.single.note, 'no onions');
      // ...but nothing is invented.
      expect(
        ticket.kitchenCounts,
        isEmpty,
        reason: 'quantities are never parsed back out of the display strings',
      );

      final texts = _texts(
        buildKdsTicketPrintDocument(ticket: ticket, labels: _labels()),
      );
      expect(
        texts.where((t) => t.startsWith('KCount')),
        isEmpty,
        reason: 'the count section is honestly OMITTED, not guessed',
      );
      expect(texts, contains('+ Extra meat ×2'));
    },
  );

  test(
    '13. the CUSTOMER RECEIPT is unchanged by the kitchen snapshots',
    () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // The same order with and without the new fields must render an identical
      // receipt — the fields are kitchen-only and must never leak onto money.
      const withoutSnapshots = SubmittedOrderView(
        orderNumber: '#3F7A2C',
        orderType: OrderType.dineIn,
        tableLabel: 'T2',
        currencyCode: 'ILS',
        subtotalMinor: 7900,
        lines: [
          SubmittedLineView(
            name: 'Classic Burger',
            quantity: 1,
            lineTotalMinor: 7900,
            currencyCode: 'ILS',
            modifiers: ['Extra meat ×2', 'Ketchup ×2', 'Make it a meal'],
            note: 'no onions',
            categoryDisplayOrder: 1,
            itemDisplayOrder: 1,
            linePosition: 1,
          ),
        ],
      );

      final a = documentToHtml(buildReceiptDocument(l10n, _order, _payment));
      final b = documentToHtml(
        buildReceiptDocument(l10n, withoutSnapshots, _payment),
      );
      expect(
        b,
        a,
        reason: 'kitchen snapshots must not alter the receipt at all',
      );

      // And the receipt still shows the money it always did.
      expect(a, contains('79.00'));
      expect(a, contains('Extra meat ×2'));
    },
  );

  test('14. building a reprint ticket is PURE — repeated calls dispatch '
      'nothing and stay identical', () {
    final first = kdsTicketViewFromSubmittedOrder(_order);
    final second = kdsTicketViewFromSubmittedOrder(_order);
    expect(second.kitchenCounts, first.kitchenCounts);
    expect(
      _texts(buildKdsTicketPrintDocument(ticket: second, labels: _labels())),
      _texts(buildKdsTicketPrintDocument(ticket: first, labels: _labels())),
    );
  });

  test(
    '8. Arabic/Hebrew content rides through the reprint unchanged',
    () async {
      final reloaded = await _roundTrip(_order);
      final ticket = kdsTicketViewFromSubmittedOrder(reloaded);
      final texts = _texts(
        buildKdsTicketPrintDocument(ticket: ticket, labels: _labels()),
      );
      // RTL count labels survive JSON + the shared renderer byte-for-byte; the
      // ordering of the count block follows first-appearance, not locale.
      expect(texts, contains('KCount 2 قطع لحم'));
      expect(
        texts.indexOf('KCount 2 قطع لحم'),
        lessThan(texts.indexOf('KCount 1 خبز')),
      );
    },
  );
}
