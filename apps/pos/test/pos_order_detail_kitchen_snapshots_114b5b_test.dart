import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show KitchenTicketPrintLabels, renderKitchenTicketBytes;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView, KdsTicketView;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show PosPrintBridge, posPrintBridgeProvider;
import 'package:restoflow_pos/src/print/print_document.dart' show PrintDocument;
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartLineView, SelectedModifier;
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_action_row.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KIOSK-PRINT-114B.5B — the POS detail parser decodes the ADDITIVE order-time
/// kitchen snapshots `pos_order_detail` now exposes, PER UNIT, and hands them
/// to the canonical kitchen path so a BRANCH-DISCOVERED manual reprint carries
/// the SAME whole-order counts as the POS direct / kiosk / drain tickets.
///
/// QUANTITY CONTRACT: the parser never multiplies by the line quantity. The
/// modifier meat is scaled by the modifier's own units into
/// `SubmittedLineView.kitchenMeats` (the established "already × modifier
/// units" contract of that field), and the shared aggregator applies the line
/// quantity exactly once: 2 × Classic 240g => 4 meat / 2 bun.
Map<String, Object?> _itemJson({
  int quantity = 2,
  int modifierQty = 1,
  Object? prep = const [
    {'name': 'Bun', 'quantity': 1, 'unit': 'pcs'},
  ],
  Object? meat = const {'quantity': 2, 'unit': 'meat'},
}) => {
  'order_item_id': 'oi-1',
  'menu_item_id': 'm-classic',
  'menu_item_name_snapshot': 'Classic Burger',
  'quantity': quantity,
  'unit_price_minor_snapshot': 4500,
  'line_discount_minor': 0,
  'line_total_minor': 4500 * quantity,
  'category_display_order_snapshot': 1,
  'item_display_order_snapshot': 1,
  'line_position': 1,
  'status': 'submitted',
  'notes': 'well done',
  'prep_snapshot': prep,
  'modifiers': [
    {
      'modifier_name_snapshot': 'Size',
      'option_name_snapshot': '240g',
      'price_minor_snapshot': 0,
      'quantity': modifierQty,
      'meat_snapshot': meat,
    },
  ],
};

PosOrderDetail _detail({
  int quantity = 2,
  int modifierQty = 1,
  Object? prep = const [
    {'name': 'Bun', 'quantity': 1, 'unit': 'pcs'},
  ],
  Object? meat = const {'quantity': 2, 'unit': 'meat'},
}) => PosOrderDetail(
  orderId: 'order-kiosk-1',
  orderCode: '#K10SK1',
  orderType: 'takeaway',
  status: 'served',
  revision: 3,
  currencyCode: 'ILS',
  subtotalMinor: 4500 * quantity,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 4500 * quantity,
  customerName: 'Saleh',
  items: [
    PosOrderDetailItem.fromJson(
      _itemJson(
        quantity: quantity,
        modifierQty: modifierQty,
        prep: prep,
        meat: meat,
      ),
    )!,
  ],
  rounds: const [],
);

KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket',
  dineIn: 'Dine-in',
  takeaway: 'Takeaway',
  tableLabel: 'Table',
  customerLabel: 'Customer',
  customerPhoneLabel: 'Phone',
  stationLabel: 'Station',
  noteLabel: 'Note',
  kitchenTotal: (count, unit) => 'Kitchen total: $count $unit',
  additionLabel: 'Addition',
  roundLabel: (n) => 'Round $n',
  restaurantNameFallback: 'RestoFlow',
);

KitchenCount? _count(KdsTicketView t, String label) =>
    t.kitchenCounts.where((c) => c.label == label).firstOrNull;

void main() {
  group('P1. the detail parser decodes the snapshots PER UNIT', () {
    test('item prep_snapshot -> prepComponents (per unit, allowlisted)', () {
      final item = PosOrderDetailItem.fromJson(_itemJson())!;
      expect(item.quantity, 2);
      expect(item.prepComponents, [
        const KitchenPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
      ]);
      expect(item.modifiers.single.quantity, 1);
      expect(
        item.modifiers.single.meat,
        const KitchenMeat(quantity: 2, unit: 'meat'),
      );
    });

    test('submittedOrderViewFromDetail keeps prep per unit and scales meat by '
        'the MODIFIER units only', () {
      final view = submittedOrderViewFromDetail(_detail());
      final line = view.lines.single;
      expect(line.quantity, 2);
      expect(line.prepComponents.single.quantity, 1);
      expect(line.kitchenMeats.single.quantity, 2);
      expect(line.modifiers, ['240g']);
      expect(line.note, 'well done');
    });

    test('a classified meat snapshot keeps its order-time answer', () {
      final item = PosOrderDetailItem.fromJson(
        _itemJson(
          meat: const {
            'quantity': 2,
            'unit': 'meat',
            'classifier_option_id': 'opt-cheese',
            'classifier_option_name': 'Cheese',
            'classifier_selected': true,
          },
        ),
      )!;
      final meat = item.modifiers.single.meat!;
      expect(meat.classifierOptionName, 'Cheese');
      expect(meat.classifierSelected, isTrue);
    });
  });

  group('P2/P3. the canonical aggregation over the detail view', () {
    test('P2. owner fixture: 2 × Classic 240g => 4 meat / 2 bun', () {
      final ticket = kdsTicketViewFromSubmittedOrder(
        submittedOrderViewFromDetail(_detail()),
      );
      expect(_count(ticket, 'meat')?.quantity, 4);
      expect(_count(ticket, 'Bun pcs')?.quantity, 2);
    });

    test('P3. modifier qty 2 × line qty 2 × meat 2 => 8, NOT 16', () {
      final ticket = kdsTicketViewFromSubmittedOrder(
        submittedOrderViewFromDetail(_detail(quantity: 2, modifierQty: 2)),
      );
      expect(_count(ticket, 'meat')?.quantity, 8);
      expect(_count(ticket, 'Bun pcs')?.quantity, 2);
      expect(ticket.items.single.modifiers, ['240g ×2']);
    });

    test('quantity 1 => 2 meat / 1 bun', () {
      final ticket = kdsTicketViewFromSubmittedOrder(
        submittedOrderViewFromDetail(_detail(quantity: 1)),
      );
      expect(_count(ticket, 'meat')?.quantity, 2);
      expect(_count(ticket, 'Bun pcs')?.quantity, 1);
    });
  });

  group('P4. NULL / absent snapshots (historical orders)', () {
    test('JSON null and absent keys decode to EMPTY, never re-derived', () {
      final withNulls = PosOrderDetailItem.fromJson(
        _itemJson(prep: null, meat: null),
      )!;
      expect(withNulls.prepComponents, isEmpty);
      expect(withNulls.modifiers.single.meat, isNull);
      final json = _itemJson()
        ..remove('prep_snapshot')
        ..['modifiers'] = [
          {
            'option_name_snapshot': '240g',
            'price_minor_snapshot': 0,
            'quantity': 1,
          },
        ];
      final absent = PosOrderDetailItem.fromJson(json)!;
      expect(absent.prepComponents, isEmpty);
      expect(absent.modifiers.single.meat, isNull);
      final ticket = kdsTicketViewFromSubmittedOrder(
        submittedOrderViewFromDetail(_detail(prep: null, meat: null)),
      );
      expect(ticket.kitchenCounts, isEmpty);
      expect(ticket.items.single.name, 'Classic Burger');
    });

    test('malformed snapshots never fail the detail (money stays strict)', () {
      final item = PosOrderDetailItem.fromJson(
        _itemJson(prep: 'not-a-list', meat: 'not-a-map'),
      );
      expect(item, isNotNull);
      expect(item!.prepComponents, isEmpty);
      expect(item.modifiers.single.meat, isNull);
    });
  });

  group('§10 STRONG PARITY — detail-sourced == POS direct', () {
    KdsTicketView direct() => kdsTicketViewFromCartLines(
      orderCode: '#K10SK1',
      orderType: OrderType.takeaway,
      customerName: 'Saleh',
      prepByItemId: const {
        'm-classic': [
          KitchenPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
        ],
      },
      lines: const [
        CartLineView(
          lineId: 'l1',
          menuItemId: 'm-classic',
          name: 'Classic Burger',
          quantity: 2,
          unitPriceMinor: 4500,
          lineTotalMinor: 9000,
          currencyCode: 'ILS',
          note: 'well done',
          modifiers: [
            SelectedModifier(
              optionId: 'o-240',
              groupName: 'Size',
              optionName: '240g',
              priceDeltaMinor: 0,
              quantity: 1,
              kitchenMeat: KitchenMeat(quantity: 2, unit: 'meat'),
            ),
          ],
        ),
      ],
    );

    test('same kitchenCounts + same item/modifier structure', () {
      final fromDetail = kdsTicketViewFromSubmittedOrder(
        submittedOrderViewFromDetail(_detail()),
      );
      final fromCart = direct();
      expect(fromDetail.kitchenCounts, fromCart.kitchenCounts);
      // (Records holding Lists compare by identity — flatten for equality.)
      String shape(KdsItemView i) =>
          '${i.name}|${i.quantity}|${i.modifiers.join(',')}|${i.note}';
      expect(
        fromDetail.items.map(shape).toList(),
        fromCart.items.map(shape).toList(),
      );
    });

    test(
      'byte-identical canonical document, counts on top, money-free',
      () async {
        final bytesDetail = await renderKitchenTicketBytes(
          ticket: kdsTicketViewFromSubmittedOrder(
            submittedOrderViewFromDetail(_detail()),
          ),
          labels: _labels(),
        );
        final bytesDirect = await renderKitchenTicketBytes(
          ticket: direct(),
          labels: _labels(),
        );
        expect(bytesDetail, bytesDirect);
        final text = utf8.decode(bytesDetail, allowMalformed: true);
        expect(text, contains('Kitchen total: 4 meat'));
        expect(text, contains('Kitchen total: 2 Bun pcs'));
        expect(
          text.indexOf('Kitchen total: 4 meat'),
          lessThan(text.indexOf('Classic Burger')),
        );
        final lower = text.toLowerCase();
        for (final token in ['subtotal', 'grand total', '4500', '9000', '₪']) {
          expect(lower.contains(token), isFalse, reason: 'no "$token"');
        }
        expect(RegExp(r'\d+\.\d{2}').hasMatch(lower), isFalse);
      },
    );
  });

  group('§11 NOTICE — branch-discovered manual reprint through the widget', () {
    late AppLocalizations l10n;
    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    Future<_RecordingKitchen> pump(
      WidgetTester tester, {
      required PosOrderDetail detail,
    }) async {
      tester.view.physicalSize = const Size(1024, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final kitchen = _RecordingKitchen();
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posNativePrintingAvailableProvider.overrideWithValue(false),
          posPrintBridgeProvider.overrideWithValue(_RecordingBridge()),
          posKitchenReprintProvider.overrideWithValue(kitchen.seam),
          orderDetailRepositoryProvider.overrideWithValue(
            _FakeDetailRepo(detail),
          ),
        ],
      );
      addTearDown(container.dispose);
      final order = PosRecentOrder.discovered(_snapshot());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: OrderActionRow(
                  order: order,
                  l10n: AppLocalizations.of(ctx),
                  actions: resolveOrderActions(order),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recent-reprint-#K10SK1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reprint-choice-kitchen')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      return kitchen;
    }

    testWidgets('snapshots available => counts built, NO counts-unavailable '
        'notice', (tester) async {
      final kitchen = await pump(tester, detail: _detail());
      final printed = kitchen.orders.single;
      expect(
        kdsTicketViewFromSubmittedOrder(printed).kitchenCounts,
        isNotEmpty,
      );
      expect(find.text(l10n.posReprintKitchenCountsUnavailable), findsNothing);
    });

    testWidgets('snapshots NULL => prints anyway + the notice', (tester) async {
      final kitchen = await pump(
        tester,
        detail: _detail(prep: null, meat: null),
      );
      expect(kitchen.orders, hasLength(1));
      expect(
        find.text(l10n.posReprintKitchenCountsUnavailable),
        findsOneWidget,
      );
    });
  });
}

final _at = DateTime.utc(2026, 8, 26, 12, 30);

PosOrderSnapshot _snapshot() => PosOrderSnapshot(
  orderId: 'order-kiosk-1',
  orderCode: '#K10SK1',
  revision: 3,
  status: 'served',
  settlement: PosSettlement.paid,
  subtotalMinor: 9000,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 9000,
  createdAt: _at,
  updatedAt: _at,
  syncAt: _at,
  orderType: 'takeaway',
  currencyCode: 'ILS',
);

class _FakeDetailRepo implements OrderDetailRepository {
  _FakeDetailRepo(this._detail);
  final PosOrderDetail _detail;
  @override
  Future<PosOrderDetail> fetch(String orderId) async => _detail;
}

class _RecordingBridge implements PosPrintBridge {
  final List<PrintDocument> documents = [];
  @override
  Future<pp.BridgeSubmitResult> submit(PrintDocument document) async {
    documents.add(document);
    return const pp.BridgeSubmitResult.sentToPrinter();
  }

  @override
  Future<pp.BridgeHealth> health() async => pp.BridgeHealth.connected;
}

class _RecordingKitchen {
  final List<SubmittedOrderView> orders = [];
  PosKitchenReprint get seam =>
      ({required container, required order, required labels}) async {
        orders.add(order);
        return PosKitchenPrintOutcome.printed;
      };
}
