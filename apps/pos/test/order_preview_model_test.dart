import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/order_actions.dart' show PosPendingKind;
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_preview_model.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// ORDER-DETAIL-PREVIEW-001 — A/E/G. the preview MODEL.
///
/// The preview is a READ-ONLY window onto what the server already stored. Its
/// model therefore carries the order-time SNAPSHOTS and nothing else: it never
/// consults the live catalog, and it never invents a value it does not have.
/// An absent fact is absent, not zero.

const _paymentUuid = '0a911111-2222-4333-8444-555566667777';

PosOrderDetailItem _item({
  String name = 'Double Burger',
  int quantity = 2,
  int unitPriceMinor = 4200,
  int lineDiscountMinor = 0,
  int lineTotalMinor = 9000,
  List<PosOrderDetailModifier> modifiers = const [
    PosOrderDetailModifier(
      optionName: 'Cheese',
      priceMinor: 300,
      quantity: 2,
      modifierName: 'Extras',
    ),
  ],
  String? notes = 'no onion',
  String? serviceRoundId,
  int? roundNumber,
  int categoryDisplayOrder = 1,
  int itemDisplayOrder = 2,
  int linePosition = 1,
}) => PosOrderDetailItem(
  name: name,
  quantity: quantity,
  unitPriceMinor: unitPriceMinor,
  lineDiscountMinor: lineDiscountMinor,
  lineTotalMinor: lineTotalMinor,
  modifiers: modifiers,
  notes: notes,
  serviceRoundId: serviceRoundId,
  roundNumber: roundNumber,
  categoryDisplayOrder: categoryDisplayOrder,
  itemDisplayOrder: itemDisplayOrder,
  linePosition: linePosition,
);

PosOrderDetail _detail({
  String status = 'served',
  List<PosOrderDetailItem>? items,
  List<PosOrderDetailRound> rounds = const [],
  PosOrderDetailPayment? payment,
  String? tableLabel = 'T5',
  String? customerName = 'Dana',
  String? customerPhone = '0591234567',
  String orderType = 'dine_in',
  int subtotal = 9000,
  int discount = 0,
  int tax = 0,
  int grand = 9000,
}) => PosOrderDetail(
  orderId: 'o-1',
  orderCode: '#O00001',
  orderType: orderType,
  status: status,
  revision: 4,
  currencyCode: 'ILS',
  subtotalMinor: subtotal,
  discountTotalMinor: discount,
  taxTotalMinor: tax,
  grandTotalMinor: grand,
  tableLabel: tableLabel,
  customerName: customerName,
  customerPhone: customerPhone,
  receiptNumber: payment == null ? null : '42',
  items: items ?? [_item()],
  rounds: rounds,
  payment: payment,
);

PosOrderDetailPayment _payment() => PosOrderDetailPayment(
  paymentId: _paymentUuid,
  status: PaymentStatus.completed,
  method: PaymentMethod.card,
  amountMinor: 9000,
  tenderedMinor: 10000,
  changeMinor: 1000,
  paidAt: DateTime.utc(2026, 8, 6, 12, 30),
  receiptNumber: '42',
);

/// A local (this-device) cash payment record.
CashPayment _localPayment({
  int amountMinor = 9000,
  int tenderedMinor = 10000,
  int changeMinor = 1000,
}) => CashPayment(
  paymentId: 'local-pay-1',
  orderNumber: '#O00001',
  deviceId: 'dev-1',
  localOperationId: 'op-1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: amountMinor,
  tenderedMinor: tenderedMinor,
  changeMinor: changeMinor,
  currencyCode: 'ILS',
  receiptNumber: '7',
  paidAt: DateTime.utc(2026, 8, 6, 13),
  orderId: 'o-1',
);

PosRecentOrder _local({
  PosSettlement settlement = PosSettlement.unpaid,
  String status = 'served',
  CashPayment? payment,
  DateTime? voidedAt,
}) => PosRecentOrder(
  order: SubmittedOrderView(
    orderNumber: '#O00001',
    orderType: OrderType.dineIn,
    tableLabel: 'T5',
    customerName: 'Dana',
    orderId: 'o-1',
    currencyCode: 'ILS',
    subtotalMinor: 9000,
    lines: const [
      SubmittedLineView(
        name: 'Double Burger',
        quantity: 2,
        lineTotalMinor: 9000,
        currencyCode: 'ILS',
        modifiers: ['Cheese ×2'],
        note: 'no onion',
      ),
    ],
  ),
  snapshot: PosOrderSnapshot(
    orderId: 'o-1',
    orderCode: '#O00001',
    revision: 4,
    status: status,
    settlement: settlement,
    subtotalMinor: 9000,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 9000,
    createdAt: DateTime.utc(2026, 8, 6, 12),
    updatedAt: DateTime.utc(2026, 8, 6, 12, 30),
    syncAt: DateTime.utc(2026, 8, 6, 12, 30),
    orderType: 'dine_in',
    tableLabel: 'T5',
    currencyCode: 'ILS',
  ),
  submittedAt: DateTime.utc(2026, 8, 6, 12),
  payment: payment,
  voidedAt: voidedAt,
);

void main() {
  group('A1. authoritative mapping', () {
    test('carries the stored header, identity and totals verbatim', () {
      final model = OrderDetailPreviewModel.fromDetail(_detail());

      expect(model.source, OrderPreviewSource.authoritative);
      expect(model.isAuthoritative, isTrue);
      expect(model.orderId, 'o-1');
      expect(model.orderCode, '#O00001');
      expect(model.orderType, OrderType.dineIn);
      expect(model.tableLabel, 'T5');
      expect(model.customerName, 'Dana');
      expect(model.customerPhone, '0591234567');
      expect(model.status, 'served');
      expect(model.currencyCode, 'ILS');
      expect(model.subtotalMinor, 9000);
      expect(model.discountTotalMinor, 0);
      expect(model.taxTotalMinor, 0);
      expect(model.grandTotalMinor, 9000);
    });

    test('carries the stored ITEM snapshots, including unit price, discount, '
        'note and structured modifiers', () {
      final model = OrderDetailPreviewModel.fromDetail(_detail());
      final line = model.lines.single;

      expect(line.name, 'Double Burger');
      expect(line.quantity, 2);
      expect(line.unitPriceMinor, 4200);
      expect(line.lineTotalMinor, 9000);
      expect(line.lineDiscountMinor, 0);
      expect(line.note, 'no onion');
      expect(line.roundNumber, isNull);
      expect(line.isAddition, isFalse);

      final modifier = line.modifiers.single;
      expect(modifier.name, 'Cheese');
      expect(modifier.quantity, 2);
      expect(modifier.priceDeltaMinor, 300);
      expect(modifier.groupName, 'Extras');
    });

    test('an UNPAID order carries an amount due and NO payment block', () {
      final model = OrderDetailPreviewModel.fromDetail(_detail());

      expect(model.payment, isNull, reason: 'no completed payment exists');
      expect(model.isPaid, isFalse);
      expect(model.amountDueMinor, 9000);
    });

    test('a PAID order carries the authoritative payment facts and NO amount '
        'due', () {
      final model = OrderDetailPreviewModel.fromDetail(
        _detail(payment: _payment(), status: 'completed'),
      );

      expect(model.isPaid, isTrue);
      expect(model.amountDueMinor, isNull);
      final payment = model.payment!;
      expect(payment.method, PaymentMethod.card);
      expect(payment.amountMinor, 9000);
      expect(payment.tenderedMinor, 10000);
      expect(payment.changeMinor, 1000);
      expect(payment.receiptNumber, '42');
      expect(payment.paidAt, DateTime.utc(2026, 8, 6, 12, 30));
    });

    test('NOTHING is fabricated when the facts are absent', () {
      final model = OrderDetailPreviewModel.fromDetail(
        _detail(tableLabel: null, customerName: null, customerPhone: null),
      );
      expect(model.tableLabel, isNull);
      expect(model.customerName, isNull);
      expect(model.customerPhone, isNull);
      expect(model.payment, isNull);
      // Absent is absent - never a zero-valued payment that reads as "paid 0".
      expect(model.paidAt, isNull);
    });

    test('the pending kind and local timestamps are carried when supplied', () {
      final model = OrderDetailPreviewModel.fromDetail(
        _detail(),
        pendingKind: PosPendingKind.payment,
        createdAt: DateTime.utc(2026, 8, 6, 12),
        updatedAt: DateTime.utc(2026, 8, 6, 12, 30),
        settlement: PosSettlement.unpaid,
      );
      expect(model.pendingKind, PosPendingKind.payment);
      expect(model.createdAt, DateTime.utc(2026, 8, 6, 12));
      expect(model.updatedAt, DateTime.utc(2026, 8, 6, 12, 30));
      expect(model.settlement, PosSettlement.unpaid);
    });
  });

  group('A2. payment precedence', () {
    test('the AUTHORITATIVE payment wins over a local one', () {
      final model = OrderDetailPreviewModel.fromDetail(
        _detail(payment: _payment()),
        localPayment: _localPayment(
          amountMinor: 1,
          tenderedMinor: 1,
          changeMinor: 0,
        ),
      );
      expect(model.payment!.amountMinor, 9000);
      expect(model.payment!.method, PaymentMethod.card);
    });

    test('a LOCAL payment is used only when the server names none', () {
      final model = OrderDetailPreviewModel.fromDetail(
        _detail(),
        localPayment: _localPayment(),
      );
      expect(model.payment!.method, PaymentMethod.cash);
      expect(model.payment!.amountMinor, 9000);
      expect(model.isPaid, isTrue);
      expect(model.amountDueMinor, isNull);
    });
  });

  group('E. service rounds', () {
    test('original AND round items appear ONCE each, and only round lines are '
        'tagged', () {
      final model = OrderDetailPreviewModel.fromDetail(
        _detail(
          items: [
            _item(name: 'Double Burger', linePosition: 1),
            _item(
              name: 'Baklava',
              quantity: 1,
              unitPriceMinor: 1200,
              lineTotalMinor: 1200,
              modifiers: const [],
              notes: null,
              serviceRoundId: 'r-2',
              roundNumber: 2,
              linePosition: 2,
            ),
          ],
          rounds: const [
            PosOrderDetailRound(
              roundId: 'r-2',
              roundNumber: 2,
              status: 'submitted',
            ),
          ],
          grand: 10200,
          subtotal: 10200,
        ),
      );

      expect(model.lines, hasLength(2));
      expect(
        model.lines.where((l) => l.name == 'Double Burger'),
        hasLength(1),
        reason: 'the original item must never be duplicated by its rounds',
      );
      final original = model.lines.firstWhere((l) => l.name == 'Double Burger');
      final addition = model.lines.firstWhere((l) => l.name == 'Baklava');
      expect(original.isAddition, isFalse);
      expect(original.roundNumber, isNull);
      expect(addition.isAddition, isTrue);
      expect(addition.roundNumber, 2);
      // Totals come from the authoritative ORDER HEADER, never re-summed.
      expect(model.grandTotalMinor, 10200);
    });

    test('modifier quantities and price deltas survive on a round line', () {
      final model = OrderDetailPreviewModel.fromDetail(
        _detail(
          items: [
            _item(
              name: 'Baklava',
              serviceRoundId: 'r-2',
              roundNumber: 3,
              modifiers: const [
                PosOrderDetailModifier(
                  optionName: 'Pistachio',
                  priceMinor: 200,
                  quantity: 3,
                ),
              ],
            ),
          ],
        ),
      );
      final modifier = model.lines.single.modifiers.single;
      expect(modifier.name, 'Pistachio');
      expect(modifier.quantity, 3);
      expect(modifier.priceDeltaMinor, 200);
      expect(modifier.groupName, isNull);
    });
  });

  group('G. historical snapshots', () {
    test(
      'the model renders the STORED name and price, never a catalog value',
      () {
        // The stored snapshot says "Double Burger" at 4200. Whatever the live
        // menu now calls it, or charges, is irrelevant to a historical order.
        final model = OrderDetailPreviewModel.fromDetail(
          _detail(
            items: [
              _item(
                name: 'Double Burger',
                unitPriceMinor: 4200,
                lineTotalMinor: 8400,
                modifiers: const [],
                notes: null,
              ),
            ],
          ),
        );
        final line = model.lines.single;
        expect(line.name, 'Double Burger');
        expect(line.unitPriceMinor, 4200);
        expect(line.lineTotalMinor, 8400);
      },
    );

    test('the mapper is a PURE function of the detail — it takes no menu, no '
        'repository and no provider', () {
      // Constructing the model must not require any live catalog access at
      // all. This is enforced structurally: fromDetail's only required input
      // is the stored detail.
      final model = OrderDetailPreviewModel.fromDetail(_detail());
      expect(model.lines, isNotEmpty);
    });
  });

  group('A3. local fallback', () {
    test('is honestly labelled a LOCAL COPY, never authoritative', () {
      final model = OrderDetailPreviewModel.fromLocal(_local());
      expect(model.source, OrderPreviewSource.localCopy);
      expect(model.isAuthoritative, isFalse);
    });

    test('shows what it has: names, quantities, line totals, modifier display '
        'strings, notes, status and metadata', () {
      final model = OrderDetailPreviewModel.fromLocal(_local());
      expect(model.orderCode, '#O00001');
      expect(model.orderType, OrderType.dineIn);
      expect(model.tableLabel, 'T5');
      expect(model.customerName, 'Dana');
      expect(model.status, 'served');
      expect(model.settlement, PosSettlement.unpaid);
      expect(model.grandTotalMinor, 9000);

      final line = model.lines.single;
      expect(line.name, 'Double Burger');
      expect(line.quantity, 2);
      expect(line.lineTotalMinor, 9000);
      expect(line.note, 'no onion');
      expect(line.modifiers.single.name, 'Cheese ×2');
    });

    test(
      'OMITS what a local record cannot know, rather than fabricating it',
      () {
        final model = OrderDetailPreviewModel.fromLocal(_local());
        final line = model.lines.single;

        expect(
          line.unitPriceMinor,
          isNull,
          reason: 'a local line carries no stored unit price',
        );
        expect(
          line.modifiers.single.priceDeltaMinor,
          isNull,
          reason: 'a local modifier is a display string, not a priced snapshot',
        );
        expect(
          line.modifiers.single.quantity,
          isNull,
          reason: 'the local quantity rides inside the display string',
        );
        expect(
          line.roundNumber,
          isNull,
          reason: 'round metadata is not available locally',
        );
        expect(line.isAddition, isFalse);
        expect(model.customerPhone, isNull);
        expect(model.amountDueMinor, isNull, reason: 'not authoritative');
      },
    );

    test('a local COMPLETED payment is shown as a local payment block', () {
      final model = OrderDetailPreviewModel.fromLocal(
        _local(settlement: PosSettlement.paid, payment: _localPayment()),
      );
      expect(model.isPaid, isTrue);
      expect(model.payment!.method, PaymentMethod.cash);
      expect(model.payment!.amountMinor, 9000);
      expect(model.payment!.paidAt, DateTime.utc(2026, 8, 6, 13));
    });

    test('a VOIDED local order carries its void information', () {
      final model = OrderDetailPreviewModel.fromLocal(
        _local(status: 'voided', voidedAt: DateTime.utc(2026, 8, 6, 14)),
      );
      expect(model.status, 'voided');
      expect(model.voidedAt, DateTime.utc(2026, 8, 6, 14));
    });
  });
}
