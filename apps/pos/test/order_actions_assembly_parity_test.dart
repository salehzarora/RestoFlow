import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_actions_assembly.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// POS-OPEN-ORDERS-STRIP-011 commit 1 — ACTION-ASSEMBLY PARITY.
///
/// The `resolveOrderActions` INPUT assembly moved from `RecentOrdersSheet`'s
/// build into the shared [PosOrderActionsAssembly]. These tests prove the move
/// changed nothing: a probe computes the assembly's verdict for every order in
/// the SAME provider scope the real sheet renders in, and each policy field is
/// checked 1:1 against the action key the sheet actually renders. A future
/// strip (or any third surface) consuming the same assembly therefore shows
/// exactly the actions this sheet shows.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

SubmittedOrderView _view(String number) => SubmittedOrderView(
  orderNumber: number,
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  orderId: 'oid-$number',
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: 4200,
      currencyCode: 'ILS',
    ),
  ],
);

CashPayment _payment(String number) => CashPayment(
  paymentId: 'pay-$number',
  orderNumber: number,
  deviceId: 'd1',
  localOperationId: 'op-$number',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 4200,
  tenderedMinor: 4200,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.now(),
);

Future<InMemoryRecentOrdersStore> _seededStore() async {
  final store = InMemoryRecentOrdersStore();
  final now = DateTime.now();
  await store.persist(kDemoSyncScope.key, [
    PosRecentOrder(order: _view('#U1'), submittedAt: now),
    PosRecentOrder(
      order: _view('#P1'),
      submittedAt: now.subtract(const Duration(minutes: 5)),
      payment: _payment('#P1'),
    ),
    // A VOIDED (terminal) order: every action must be withdrawn.
    PosRecentOrder(
      order: _view('#V1'),
      submittedAt: now.subtract(const Duration(minutes: 9)),
      voidedAt: now.subtract(const Duration(minutes: 1)),
      voidReason: 'test',
    ),
  ]);
  return store;
}

/// Captures the assembly's per-order verdicts on every build, in the SAME
/// ProviderScope as the sheet under test.
class _AssemblyProbe extends ConsumerWidget {
  const _AssemblyProbe({required this.captured});

  final Map<String, PosOrderActions> captured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(posRecentOrdersControllerProvider);
    final assembly = PosOrderActionsAssembly.watch(ref, orders);
    captured
      ..clear()
      ..addEntries(
        orders.map((o) => MapEntry(o.orderNumber, assembly.resolveFor(o))),
      );
    return const SizedBox.shrink();
  }
}

Widget _wrap(
  InMemoryRecentOrdersStore store,
  Map<String, PosOrderActions> captured,
) => ProviderScope(
  overrides: [
    posRecentOrdersStoreProvider.overrideWithValue(store),
    // The demo snapshot feed adopts the whole branch; emptied so the parity
    // check covers exactly the seeded fixtures.
    orderSnapshotRepositoryProvider.overrideWithValue(
      DemoOrderSnapshotRepository(),
    ),
    posSyncPollIntervalProvider.overrideWithValue(null),
  ],
  child: MaterialApp(
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: Scaffold(
      body: Column(
        children: [
          _AssemblyProbe(captured: captured),
          const Expanded(child: RecentOrdersSheet()),
        ],
      ),
    ),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Asserts every rendered action key matches the assembly's field for [code].
void _expectFieldKeyParity(
  WidgetTester tester,
  Map<String, PosOrderActions> captured,
  String code,
) {
  final actions = captured[code];
  expect(actions, isNotNull, reason: 'assembly resolved nothing for $code');
  final byField = <String, bool>{
    'recent-pay-$code': actions!.canPay,
    'recent-print-bill-$code': actions.canPrintBill,
    'recent-discount-$code': actions.canDiscount,
    'recent-cancel-$code': actions.canVoid,
    'recent-move-table-$code': actions.canMoveTable,
    'recent-add-items-$code': actions.canAddItems,
    'recent-reprint-$code': actions.canOpenReceipt,
    'recent-view-$code': actions.canOpenReceipt,
    'recent-complete-$code': actions.canComplete,
  };
  for (final entry in byField.entries) {
    expect(
      find.byKey(Key(entry.key)),
      entry.value ? findsOneWidget : findsNothing,
      reason:
          '$code: assembly says ${entry.value} but the sheet '
          '${entry.value ? "did not render" : "rendered"} ${entry.key}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P1. every action key the sheet renders matches the shared '
      'assembly verdict, for unpaid, paid and terminal orders', (tester) async {
    _tall(tester);
    final captured = <String, PosOrderActions>{};
    await tester.pumpWidget(_wrap(await _seededStore(), captured));
    await tester.pumpAndSettle();

    // The open section shows the unpaid order; parity there first.
    expect(find.byKey(const Key('recent-order-#U1')), findsOneWidget);
    _expectFieldKeyParity(tester, captured, '#U1');

    // All sections: paid and voided rows render too.
    await tester.tap(find.byKey(const Key('orders-section-all')));
    await tester.pumpAndSettle();
    for (final code in ['#U1', '#P1', '#V1']) {
      expect(
        find.byKey(Key('recent-order-$code')),
        findsOneWidget,
        reason: '$code row missing in ALL section',
      );
      _expectFieldKeyParity(tester, captured, code);
    }
  });

  testWidgets('P2. the assembly verdicts themselves pin the policy: unpaid '
      'is payable, paid opens the receipt, terminal is inert', (tester) async {
    _tall(tester);
    final captured = <String, PosOrderActions>{};
    await tester.pumpWidget(_wrap(await _seededStore(), captured));
    await tester.pumpAndSettle();

    final unpaid = captured['#U1']!;
    expect(unpaid.canPay, isTrue);
    expect(unpaid.canOpenReceipt, isFalse);

    final paid = captured['#P1']!;
    expect(paid.canPay, isFalse);
    expect(paid.canOpenReceipt, isTrue);

    final voided = captured['#V1']!;
    expect(voided.canPay, isFalse);
    expect(voided.canDiscount, isFalse);
    expect(voided.canVoid, isFalse);
    expect(voided.canAddItems, isFalse);
    expect(voided.canMoveTable, isFalse);
    expect(voided.canComplete, isFalse);
  });

  testWidgets('P3. the sheet still resolves the localized action labels '
      '(smoke: the extraction did not detach l10n)', (tester) async {
    _tall(tester);
    final l10n = await _en();
    final captured = <String, PosOrderActions>{};
    await tester.pumpWidget(_wrap(await _seededStore(), captured));
    await tester.pumpAndSettle();
    expect(find.text(l10n.posTakePayment), findsWidgets);
  });
}
