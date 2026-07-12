import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/active_orders_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart'
    show AuditBranchOption;
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/orders/active_orders_screen.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart';
import 'package:restoflow_dashboard/src/orders/orders_screen.dart';
import 'package:restoflow_dashboard/src/state/active_orders_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ACTIVE-ORDERS-001 — the READ-ONLY active-orders operations centre:
/// canonical active/terminal classification, FIFO order, elapsed age (never
/// "late"), payment as a separate axis, summary, filters, freshness, states,
/// responsiveness, RTL/LTR, and the read-only guarantee.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

/// A FIXED clock — ages must never depend on the wall clock.
final DateTime _now = DateTime.utc(2026, 7, 12, 13, 38);
DateTime _clock() => _now;

DemoOrder _order(
  String id, {
  required String status,
  int minutesAgo = 5,
  bool paid = false,
  int total = 1000,
  String type = 'dine_in',
  String branchId = 'demo-branch-downtown',
  String branch = 'Downtown',
  String? customer,
  String? table,
}) => DemoOrder(
  daysAgo: 0,
  minutesAgo: minutesAgo,
  branchId: branchId,
  detail: OrderDetail(
    orderId: id,
    orderCode: '#$id',
    status: status,
    orderType: type,
    currencyCode: 'ILS',
    subtotalMinor: total,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: total,
    createdAtLabel: '13:00',
    branchName: branch,
    customerName: customer,
    tableLabel: table,
    items: [
      OrderDetailItem(name: 'Burger', quantity: 1, lineTotalMinor: total),
    ],
    payments: paid
        ? [
            OrderPayment(
              method: 'cash',
              status: 'completed',
              amountMinor: total,
            ),
          ]
        : const [],
  ),
);

/// One order at every canonical active stage + both terminal ones.
List<DemoOrder> _mixed() => [
  _order('t-completed', status: 'completed', minutesAgo: 90, paid: true),
  _order('t-voided', status: 'voided', minutesAgo: 80),
  _order('t-cancelled', status: 'cancelled', minutesAgo: 70),
  _order('t-draft', status: 'draft', minutesAgo: 60),
  _order('a-served', status: 'served', minutesAgo: 50, type: 'takeaway'),
  _order('a-ready', status: 'ready', minutesAgo: 40, paid: true, table: 'T1'),
  _order('a-preparing', status: 'preparing', minutesAgo: 30, customer: 'Layla'),
  _order('a-accepted', status: 'accepted', minutesAgo: 20, paid: true),
  _order('a-submitted', status: 'submitted', minutesAgo: 4),
];

Widget _wrap(
  ActiveOrdersRepository repo, {
  bool demo = true,
  String locale = 'en',
  Widget home = const Scaffold(body: ActiveOrdersView()),
}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(RuntimeConfig.test(isDemoMode: demo)),
    activeOrdersRepositoryProvider.overrideWithValue(repo),
    activeOrdersClockProvider.overrideWithValue(_clock),
    // The detail sheet loads through the history seam — point it at the same
    // dataset so opening an active row resolves.
    orderHistoryRepositoryProvider.overrideWithValue(
      DemoOrderHistoryRepository(orders: _mixed()),
    ),
  ],
  child: MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: home,
  ),
);

void _sized(WidgetTester tester, double width, [double height = 2400]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

DemoActiveOrdersRepository _repo({
  List<DemoOrder>? orders,
  String? failureMessage,
  int limit = 100,
}) => DemoActiveOrdersRepository(
  orders: orders ?? _mixed(),
  clock: _clock,
  failureMessage: failureMessage,
  limit: limit,
);

/// Holds the read open until [_gate] completes, so the LOADING state is real
/// (the demo repository otherwise resolves within a microtask).
class _GatedRepo implements ActiveOrdersRepository {
  _GatedRepo(this._inner, this._gate);

  final ActiveOrdersRepository _inner;
  final Future<void> _gate;

  @override
  Future<ActiveOrdersSnapshot> loadActive(ActiveOrdersQuery query) async {
    await _gate;
    return _inner.loadActive(query);
  }
}

void main() {
  // ===== A. canonical classification ========================================
  test('A1 the canonical active/terminal partition matches the state machine', () {
    expect(kActiveOrderStatuses, [
      'submitted',
      'accepted',
      'preparing',
      'ready',
      'served',
    ]);
    expect(kTerminalOrderStatuses, ['completed', 'cancelled', 'voided']);
    for (final s in kActiveOrderStatuses) {
      expect(isActiveOrderStatus(s), isTrue);
      expect(isTerminalOrderStatus(s), isFalse);
    }
    for (final s in kTerminalOrderStatuses) {
      expect(isTerminalOrderStatus(s), isTrue);
      expect(isActiveOrderStatus(s), isFalse);
    }
    // `draft` is a LOCAL-ONLY pre-state: never active, never terminal.
    expect(isActiveOrderStatus('draft'), isFalse);
  });

  test('A2 terminal orders are excluded and paid active orders are kept', () async {
    final snap = await _repo().loadActive(const ActiveOrdersQuery());
    final codes = snap.rows.map((r) => r.orderId).toList();
    expect(codes, isNot(contains('t-completed')));
    expect(codes, isNot(contains('t-voided')));
    expect(codes, isNot(contains('t-cancelled')));
    expect(codes, isNot(contains('t-draft')));
    // A PAID order stays active (payment is a separate axis — D-025).
    expect(codes, contains('a-ready'));
    expect(snap.rows.firstWhere((r) => r.orderId == 'a-ready').paid, isTrue);
    // A SERVED order stays active until the lifecycle closes it.
    expect(codes, contains('a-served'));
    expect(snap.rows.length, 5);
  });

  test('A3 rows are FIFO (oldest first)', () async {
    final snap = await _repo().loadActive(const ActiveOrdersQuery());
    expect(snap.rows.map((r) => r.orderId).toList(), [
      'a-served', // 50 min
      'a-ready', // 40
      'a-preparing', // 30
      'a-accepted', // 20
      'a-submitted', // 4
    ]);
  });

  test('A4 the summary covers the SCOPE, not the filters', () async {
    final repo = _repo();
    final all = await repo.loadActive(const ActiveOrdersQuery());
    expect(all.summary.total, 5);
    expect(all.summary.unpaid, 3); // served, preparing, submitted
    expect(all.summary.ready, 1);
    expect(all.summary.served, 1);

    // Narrowing the LIST leaves the scope counters untouched.
    final filtered = await repo.loadActive(
      const ActiveOrdersQuery(stage: ActiveOrderStageFilter.ready),
    );
    expect(filtered.rows.length, 1);
    expect(filtered.summary.total, 5);
    expect(filtered.summary.unpaid, 3);
  });

  test('A5 elapsed age is honest: clamped, and null when unknown', () {
    const known = OrderHistoryRow(
      orderId: 'x',
      orderCode: '#x',
      status: 'ready',
      orderType: 'dine_in',
      createdAtLabel: '',
      itemCount: 1,
      grandTotalMinor: 0,
      currencyCode: 'ILS',
      paid: false,
    );
    // No absolute timestamp -> NO age (never a fabricated "0 min").
    expect(openMinutes(known, _now), isNull);

    final row = OrderHistoryRow(
      orderId: 'y',
      orderCode: '#y',
      status: 'ready',
      orderType: 'dine_in',
      createdAtLabel: '',
      itemCount: 1,
      grandTotalMinor: 0,
      currencyCode: 'ILS',
      paid: false,
      createdAtUtc: _now.subtract(const Duration(minutes: 75)),
    );
    expect(openMinutes(row, _now), 75);
    // A future timestamp (device clock skew) clamps to 0, never negative.
    final skewed = OrderHistoryRow(
      orderId: 'z',
      orderCode: '#z',
      status: 'ready',
      orderType: 'dine_in',
      createdAtLabel: '',
      itemCount: 1,
      grandTotalMinor: 0,
      currencyCode: 'ILS',
      paid: false,
      createdAtUtc: _now.add(const Duration(minutes: 5)),
    );
    expect(openMinutes(skewed, _now), 0);
  });

  // ===== B. filters =========================================================
  test('B1 stage / payment / type / search / branch filters', () async {
    final repo = _repo(
      orders: [
        ..._mixed(),
        _order(
          'a-harbor',
          status: 'preparing',
          minutesAgo: 10,
          branchId: 'demo-branch-harbor',
          branch: 'Harbor',
        ),
      ],
    );
    Future<List<String>> ids(ActiveOrdersQuery q) async =>
        (await repo.loadActive(q)).rows.map((r) => r.orderId).toList();

    expect(
      await ids(const ActiveOrdersQuery(stage: ActiveOrderStageFilter.served)),
      ['a-served'],
    );
    // Still FIFO within the filter: 50, 30, 10, 4 minutes open.
    expect(await ids(const ActiveOrdersQuery(payment: PaymentFilter.unpaid)), [
      'a-served',
      'a-preparing',
      'a-harbor',
      'a-submitted',
    ]);
    expect(await ids(const ActiveOrdersQuery(payment: PaymentFilter.paid)), [
      'a-ready',
      'a-accepted',
    ]);
    expect(
      await ids(const ActiveOrdersQuery(orderType: OrderTypeFilter.takeaway)),
      ['a-served'],
    );
    expect(await ids(const ActiveOrdersQuery(search: 'Layla')), ['a-preparing']);
    expect(
      await ids(
        const ActiveOrdersQuery(
          branch: AuditBranchOption(
            branchId: 'demo-branch-harbor',
            restaurantId: 'demo-rest-1',
            label: 'Harbor',
          ),
        ),
      ),
      ['a-harbor'],
    );
  });

  test('B2 the page cap truncates HONESTLY', () async {
    final snap = await _repo(limit: 2).loadActive(const ActiveOrdersQuery());
    expect(snap.rows.length, 2);
    expect(snap.matching, 5);
    expect(snap.truncated, isTrue);
    // FIFO: the OLDEST survive the cap.
    expect(snap.rows.first.orderId, 'a-served');
  });

  // ===== C. the board UI ====================================================
  testWidgets('C1 the board renders the active rows, summary and demo banner', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    expect(find.text(l10n.ordersActiveDemoNotice), findsOneWidget);
    expect(find.byKey(const Key('active-order-card-a-served')), findsOneWidget);
    expect(
      find.byKey(const Key('active-order-card-a-submitted')),
      findsOneWidget,
    );
    // A terminal order NEVER reaches the board.
    expect(
      find.byKey(const Key('active-order-card-t-completed')),
      findsNothing,
    );
    expect(find.byKey(const Key('active-summary-total')), findsOneWidget);
    expect(find.byKey(const Key('active-summary-unpaid')), findsOneWidget);
  });

  testWidgets('C2 elapsed age renders; "late" is never claimed', (tester) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    // 50 min open -> "50 min"; 4 min -> "4 min".
    expect(find.text(l10n.ordersActiveAgeMinutes(50)), findsOneWidget);
    expect(find.text(l10n.ordersActiveAgeMinutes(4)), findsOneWidget);
    // The honest notice is on the surface. The ONLY place the word "late"
    // appears is that notice, saying lateness is NOT reported — there is no
    // late/overdue badge anywhere on a row.
    expect(find.byKey(const Key('active-orders-no-due-notice')), findsOneWidget);
    expect(find.text(l10n.ordersActiveNoDueTimeNotice), findsOneWidget);
    expect(find.textContaining('late'), findsOneWidget); // the notice, only
    expect(find.textContaining('Late'), findsNothing);
    expect(find.textContaining('Overdue'), findsNothing);
    expect(find.textContaining('overdue'), findsNothing);
  });

  testWidgets('C3 an age over an hour renders as hours + minutes', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(
      _wrap(_repo(orders: [_order('a-old', status: 'preparing', minutesAgo: 95)])),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.ordersActiveAgeHours(1, 35)), findsOneWidget);
  });

  testWidgets('C4 money uses the shared integer-minor formatter', (
    tester,
  ) async {
    _sized(tester, 1320);
    await tester.pumpWidget(
      _wrap(
        _repo(
          orders: [_order('a-m', status: 'ready', total: 8400, minutesAgo: 3)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('₪84.00'), findsOneWidget);
  });

  testWidgets('C5 status + payment are LABELLED, never colour alone', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    expect(find.text(l10n.ordersStatusServed), findsWidgets);
    expect(find.text(l10n.ordersStatusReady), findsWidgets);
    expect(find.text(l10n.ordersStatusPreparing), findsWidgets);
    expect(find.text(l10n.dashboardUnpaid), findsWidgets);
    expect(find.text(l10n.dashboardPaid), findsWidgets);
  });

  testWidgets('C6 the summary tiles filter the board', (tester) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('active-summary-ready')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-order-card-a-ready')), findsOneWidget);
    expect(find.byKey(const Key('active-order-card-a-served')), findsNothing);
  });

  testWidgets('C7 the stage dropdown filters the board', (tester) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('active-orders-stage-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.ordersStatusSubmitted).last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('active-order-card-a-submitted')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('active-order-card-a-ready')), findsNothing);
  });

  testWidgets('C8 search filters the board', (tester) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('active-orders-search-field')),
      'Layla',
    );
    await tester.tap(find.byKey(const Key('active-orders-search-apply')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('active-order-card-a-preparing')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('active-order-card-a-ready')), findsNothing);
  });

  // ===== D. states ==========================================================
  testWidgets('D1 empty state', (tester) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_repo(orders: const [])));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-orders-empty')), findsOneWidget);
    expect(find.text(l10n.ordersActiveEmpty), findsOneWidget);
  });

  testWidgets('D2 error state + retry', (tester) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_repo(failureMessage: 'boom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-orders-error')), findsOneWidget);
    expect(find.byKey(const Key('active-orders-retry')), findsOneWidget);

    // Retrying re-reads (and fails again — it never fabricates rows).
    await tester.tap(find.byKey(const Key('active-orders-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-orders-error')), findsOneWidget);
  });

  testWidgets('D3 loading state shows skeletons, not fabricated rows', (
    tester,
  ) async {
    _sized(tester, 1320);
    final gate = Completer<void>();
    await tester.pumpWidget(_wrap(_GatedRepo(_repo(), gate.future)));
    await tester.pump(); // the read is genuinely still in flight

    expect(find.byKey(const Key('active-orders-loading')), findsOneWidget);
    expect(find.byKey(const Key('active-order-card-a-ready')), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-orders-loading')), findsNothing);
    expect(find.byKey(const Key('active-order-card-a-ready')), findsOneWidget);
  });

  testWidgets('D4 a truncated board says so', (tester) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_repo(limit: 2)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-orders-truncated')), findsOneWidget);
  });

  // ===== E. freshness =======================================================
  testWidgets('E1 refresh re-reads and stamps "updated"; rows survive it', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(
      _wrap(_repo(), home: const Scaffold(body: OrdersScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-orders-last-updated')), findsOneWidget);
    expect(find.text(l10n.ordersActiveLastUpdated('13:38')), findsOneWidget);

    await tester.tap(find.byKey(const Key('orders-refresh')));
    await tester.pumpAndSettle();
    // The rows are still there after the refresh (never wiped to a spinner).
    expect(find.byKey(const Key('active-order-card-a-ready')), findsOneWidget);
  });

  testWidgets('E2 auto-refresh is OFF by default and is a visible toggle', (
    tester,
  ) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('active-orders-auto-refresh'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);

    // Turn it back off so no periodic timer outlives the test.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
  });

  // ===== F. read-only ========================================================
  testWidgets('F1 opening a row shows the READ-ONLY detail (no mutation)', (
    tester,
  ) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('active-order-card-a-ready')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('order-detail-sheet'));
    expect(sheet, findsOneWidget);
    expect(find.byKey(const Key('order-detail-content')), findsOneWidget);
    // The detail offers previews + copy only — no status/payment/void control.
    expect(
      find.descendant(
        of: sheet,
        matching: find.byKey(const Key('order-receipt-preview-button')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('F2 the board itself exposes NO mutating control', (tester) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    // None of the write vocabulary the POS/KDS own appears anywhere here:
    // no payment collection, no void/cancel, no mark-ready, no bump.
    for (final forbidden in <String>[
      l10n.posPayCash,
      l10n.posPayLaterAction,
      l10n.posCancelOrderAction,
      l10n.kdsReadyAction,
      l10n.kdsBumpAction,
    ]) {
      expect(find.text(forbidden), findsNothing);
    }
    // The only buttons are the read-only ones (search-apply + the toggle).
    expect(find.byType(ElevatedButton), findsNothing);
  });

  // ===== G. responsive + RTL/LTR ============================================
  for (final width in <double>[390, 700, 940, 1320]) {
    testWidgets('G1 the board has no horizontal overflow at ${width}px', (
      tester,
    ) async {
      _sized(tester, width, 2600);
      await tester.pumpWidget(_wrap(_repo()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('active-order-card-a-ready')), findsOneWidget);
    });
  }

  for (final locale in <String>['ar', 'he', 'en']) {
    testWidgets('G2 the board renders in the right direction ($locale)', (
      tester,
    ) async {
      _sized(tester, 1320);
      final l10n = await _l(locale);
      await tester.pumpWidget(_wrap(_repo(), locale: locale));
      await tester.pumpAndSettle();

      final expected = locale == 'en'
          ? TextDirection.ltr
          : TextDirection.rtl;
      final direction = Directionality.of(
        tester.element(find.byKey(const Key('active-order-card-a-ready'))),
      );
      expect(direction, expected);
      expect(find.text(l10n.ordersActiveNoDueTimeNotice), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('G3 a row is keyboard-focusable and activates the detail', (
    tester,
  ) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_repo()));
    await tester.pumpAndSettle();

    // The row IS the InkWell: focusable, and activatable by keyboard.
    final inkWell = tester.widget<InkWell>(
      find.byKey(const Key('active-order-card-a-ready')),
    );
    expect(inkWell.onTap, isNotNull);
    expect(inkWell.canRequestFocus, isTrue);
    expect(inkWell.excludeFromSemantics, isFalse);
  });

  // ===== H. the tabbed Orders area ==========================================
  testWidgets('H1 the Orders area lands on Active and switches to History', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(
      _wrap(_repo(), home: const Scaffold(body: OrdersScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActiveOrdersView), findsOneWidget);
    expect(find.text(l10n.ordersActiveTitle), findsWidgets);

    await tester.tap(find.byKey(const Key('orders-tab-history')));
    await tester.pumpAndSettle();

    expect(find.byType(OrderHistoryView), findsOneWidget);
    expect(find.byType(ActiveOrdersView), findsNothing);
    expect(find.text(l10n.ordersHistoryTitle), findsWidgets);

    await tester.tap(find.byKey(const Key('orders-tab-active')));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveOrdersView), findsOneWidget);
  });
}
