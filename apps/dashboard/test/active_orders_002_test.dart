import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/active_orders_repository.dart';
import 'package:restoflow_dashboard/src/data/demo_order_store.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/orders/active_orders_screen.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart';
import 'package:restoflow_dashboard/src/orders/orders_screen.dart';
import 'package:restoflow_dashboard/src/state/active_orders_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ACTIVE-ORDERS-002 — operational QUEUES, server-side SORT, and the refresh
/// simplification: the board opens on the work that is actually moving, the
/// served backlog lives in its own queue, sorting/paging are authoritative, and
/// the auto-refresh switch is gone (the board refreshes itself while visible).
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

final DateTime _now = DateTime.utc(2026, 7, 13, 14, 0);
DateTime _clock() => _now;

DemoOrder _order(
  String id, {
  required String status,
  required int minutesAgo,
  bool paid = false,
  int total = 1000,
}) => DemoOrder(
  daysAgo: 0,
  minutesAgo: minutesAgo,
  detail: OrderDetail(
    orderId: id,
    orderCode: '#$id',
    status: status,
    orderType: 'dine_in',
    currencyCode: 'ILS',
    subtotalMinor: total,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: total,
    createdAtLabel: '13:00',
    branchName: 'Downtown',
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

/// Production-shaped: a handful in progress, a big served backlog, terminal
/// orders that must never appear, and both paid and unpaid served examples.
List<DemoOrder> _fixtures() => [
  // in progress (4)
  _order('p-submitted', status: 'submitted', minutesAgo: 3),
  _order('p-accepted', status: 'accepted', minutesAgo: 8, paid: true),
  _order('p-preparing', status: 'preparing', minutesAgo: 15),
  _order('p-ready', status: 'ready', minutesAgo: 22, paid: true),
  // awaiting close (3)
  _order('s-paid', status: 'served', minutesAgo: 40, paid: true),
  _order('s-unpaid', status: 'served', minutesAgo: 55),
  _order('s-old', status: 'served', minutesAgo: 90, paid: true),
  // terminal — never on any queue
  _order('t-completed', status: 'completed', minutesAgo: 120, paid: true),
  _order('t-voided', status: 'voided', minutesAgo: 130),
  _order('t-cancelled', status: 'cancelled', minutesAgo: 140),
];

DemoOrderStore _store() => DemoOrderStore(_fixtures());

DemoActiveOrdersRepository _repo(DemoOrderStore store, {int limit = 100}) =>
    DemoActiveOrdersRepository(store: store, clock: _clock, limit: limit);

Widget _wrap(
  DemoOrderStore store, {
  String locale = 'en',
  int limit = 100,
  Duration? poll,
  Widget home = const Scaffold(body: OrdersScreen()),
}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: true),
    ),
    demoOrderStoreProvider.overrideWithValue(store),
    activeOrdersRepositoryProvider.overrideWithValue(
      _repo(store, limit: limit),
    ),
    activeOrdersClockProvider.overrideWithValue(_clock),
    // INJECTED scheduling — never a real 30-second wait.
    activeOrdersPollIntervalProvider.overrideWithValue(poll),
  ],
  child: MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: home,
  ),
);

void _sized(WidgetTester tester, double width, [double height = 3000]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // ===== A. queue definitions (the canonical states, regrouped) ==============
  test('A1 the queues are a grouping OVER the canonical active states', () {
    expect(kInProgressStatuses, [
      'submitted',
      'accepted',
      'preparing',
      'ready',
    ]);
    expect(kAwaitingCloseStatuses, ['served']);
    // Every queue member is a canonical ACTIVE status — no new taxonomy.
    for (final s in [...kInProgressStatuses, ...kAwaitingCloseStatuses]) {
      expect(isActiveOrderStatus(s), isTrue, reason: s);
    }
    expect(ActiveOrderQueue.allActive.statuses, kActiveOrderStatuses);
    // Terminal states belong to no queue.
    for (final s in kTerminalOrderStatuses) {
      for (final q in ActiveOrderQueue.values) {
        expect(q.contains(s), isFalse, reason: '$s in ${q.wire}');
      }
    }
  });

  test(
    'A2 in_progress excludes served; awaiting_close is served ONLY',
    () async {
      final repo = _repo(_store());

      final prog = await repo.loadActive(
        const ActiveOrdersQuery(queue: ActiveOrderQueue.inProgress),
      );
      expect(prog.rows.map((r) => r.status).toSet(), {
        'submitted',
        'accepted',
        'preparing',
        'ready',
      });
      expect(prog.rows.any((r) => r.status == 'served'), isFalse);

      final wait = await repo.loadActive(
        const ActiveOrdersQuery(queue: ActiveOrderQueue.awaitingClose),
      );
      expect(wait.rows.length, 3);
      expect(wait.rows.every((r) => r.status == 'served'), isTrue);

      final all = await repo.loadActive(
        const ActiveOrdersQuery(queue: ActiveOrderQueue.allActive),
      );
      expect(all.rows.length, 7);
      // Terminal orders never appear in ANY queue.
      for (final snap in [prog, wait, all]) {
        expect(
          snap.rows.any((r) => kTerminalOrderStatuses.contains(r.status)),
          isFalse,
        );
      }
    },
  );

  test(
    'A3 an UNPAID served order belongs to awaiting_close (payment is separate)',
    () async {
      final wait = await _repo(_store()).loadActive(
        const ActiveOrdersQuery(queue: ActiveOrderQueue.awaitingClose),
      );
      final ids = wait.rows.map((r) => r.orderId).toList();
      expect(ids, contains('s-unpaid'));
      expect(ids, contains('s-paid'));
      expect(
        wait.rows
            .firstWhere((r) => r.orderId == 's-unpaid')
            .settlement
            .isSettled,
        isFalse,
      );
    },
  );

  // ===== B. sort + pagination (server-authoritative) =========================
  test(
    'B1 the DEFAULT is NEWEST first; oldest is an explicit option',
    () async {
      const q = ActiveOrdersQuery();
      expect(q.queue, ActiveOrderQueue.inProgress);
      expect(q.sort, ActiveOrdersSort.newest);

      final repo = _repo(_store());
      final newest = await repo.loadActive(
        const ActiveOrdersQuery(queue: ActiveOrderQueue.allActive),
      );
      expect(newest.rows.first.orderId, 'p-submitted'); // 3 min ago
      expect(newest.rows.last.orderId, 's-old'); // 90 min ago

      final oldest = await repo.loadActive(
        const ActiveOrdersQuery(
          queue: ActiveOrderQueue.allActive,
          sort: ActiveOrdersSort.oldest,
        ),
      );
      expect(oldest.rows.first.orderId, 's-old');
      expect(oldest.rows.last.orderId, 'p-submitted');
    },
  );

  test(
    'B2 paging is keyset, capped, and never re-sorted on the client',
    () async {
      final repo = _repo(_store(), limit: 3);
      const q = ActiveOrdersQuery(queue: ActiveOrderQueue.allActive);

      final p1 = await repo.loadActive(q);
      expect(p1.rows.length, 3);
      // `matching` is the FULL filtered count — never the loaded page.
      expect(p1.matching, 7);
      expect(p1.hasMore, isTrue);
      expect(p1.nextCursor, startsWith('newest|'));

      final p2 = await repo.loadActive(q, cursor: p1.nextCursor);
      final p3 = await repo.loadActive(q, cursor: p2.nextCursor);
      expect(p3.hasMore, isFalse);
      expect(p3.nextCursor, isNull);

      final seen = [
        ...p1.rows.map((r) => r.orderId),
        ...p2.rows.map((r) => r.orderId),
        ...p3.rows.map((r) => r.orderId),
      ];
      // No duplicate, no skipped row, and still in the SERVER's newest-first order.
      expect(seen.length, 7);
      expect(seen.toSet().length, 7);
      expect(seen.first, 'p-submitted');
      expect(seen.last, 's-old');
    },
  );

  test(
    'B3 a cursor from the OTHER sort is REJECTED (never mis-paged)',
    () async {
      final repo = _repo(_store(), limit: 3);
      final p1 = await repo.loadActive(
        const ActiveOrdersQuery(queue: ActiveOrderQueue.allActive),
      );
      expect(
        () => repo.loadActive(
          const ActiveOrdersQuery(
            queue: ActiveOrderQueue.allActive,
            sort: ActiveOrdersSort.oldest,
          ),
          cursor: p1.nextCursor,
        ),
        throwsA(isA<ActiveOrdersException>()),
      );
    },
  );

  test('B4 a stage filter outside the queue is dropped, never sent', () {
    const q = ActiveOrdersQuery(
      queue: ActiveOrderQueue.awaitingClose,
      stage: ActiveOrderStageFilter.served,
    );
    // Switching to In progress cannot keep a `served` stage filter — the server
    // would reject the contradiction (22023).
    final moved = q.copyWith(queue: ActiveOrderQueue.inProgress);
    expect(moved.stage, ActiveOrderStageFilter.all);
    // A stage that IS inside the new queue survives.
    final kept = const ActiveOrdersQuery(
      stage: ActiveOrderStageFilter.ready,
    ).copyWith(queue: ActiveOrderQueue.inProgress);
    expect(kept.stage, ActiveOrderStageFilter.ready);
  });

  // ===== C. the summary is scope-wide =======================================
  test(
    'C1 summary counts come from the FULL scope, not the loaded page',
    () async {
      final snap = await _repo(
        _store(),
        limit: 2,
      ).loadActive(const ActiveOrdersQuery(queue: ActiveOrderQueue.inProgress));
      expect(snap.rows.length, 2); // the page is capped...
      expect(snap.summary.total, 7); // ...but the counters are not
      expect(snap.summary.inProgress, 4);
      expect(snap.summary.awaitingClose, 3);
      expect(snap.summary.unpaid, 3); // p-submitted, p-preparing, s-unpaid
      expect(snap.summary.ofQueue(ActiveOrderQueue.awaitingClose), 3);
    },
  );

  // ===== D. the board UI ====================================================
  testWidgets('D1 Active opens on IN PROGRESS; served orders are not on it', (
    tester,
  ) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-order-card-p-ready')), findsOneWidget);
    expect(
      find.byKey(const Key('active-order-card-p-submitted')),
      findsOneWidget,
    );
    // The served backlog no longer buries the live work.
    expect(find.byKey(const Key('active-order-card-s-paid')), findsNothing);
    expect(find.byKey(const Key('active-order-card-s-unpaid')), findsNothing);
    expect(
      find.byKey(const Key('active-order-card-t-completed')),
      findsNothing,
    );
  });

  testWidgets('D2 the queue selector opens Awaiting close (served only)', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('active-queue-awaiting-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-order-card-s-paid')), findsOneWidget);
    expect(find.byKey(const Key('active-order-card-s-unpaid')), findsOneWidget);
    expect(find.byKey(const Key('active-order-card-p-ready')), findsNothing);
    // It explains what these orders ARE and how they leave the queue.
    expect(
      find.byKey(const Key('active-orders-awaiting-explainer')),
      findsOneWidget,
    );
    expect(find.text(l10n.ordersAwaitingCloseExplainer), findsOneWidget);
  });

  testWidgets('D3 the summary cards select their queue / filter', (
    tester,
  ) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    // Awaiting-close card -> the awaiting-close queue.
    await tester.tap(find.byKey(const Key('active-summary-awaiting-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-order-card-s-paid')), findsOneWidget);
    expect(find.byKey(const Key('active-order-card-p-ready')), findsNothing);

    // In-progress card -> back to the in-progress queue.
    await tester.tap(find.byKey(const Key('active-summary-in-progress')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-order-card-p-ready')), findsOneWidget);
    expect(find.byKey(const Key('active-order-card-s-paid')), findsNothing);

    // Unpaid card -> a PAYMENT filter across all active work (never a lifecycle
    // change): the unpaid served order and the unpaid in-progress ones show.
    await tester.tap(find.byKey(const Key('active-summary-unpaid')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-order-card-s-unpaid')), findsOneWidget);
    expect(
      find.byKey(const Key('active-order-card-p-preparing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('active-order-card-p-ready')),
      findsNothing,
    ); // paid
  });

  testWidgets('D4 sorting is a real control and resets pagination', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    // limit 2 so a "load more" exists to be reset.
    await tester.pumpWidget(_wrap(_store(), limit: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('active-queue-all')));
    await tester.pumpAndSettle();

    // Newest first by default.
    expect(
      find.byKey(const Key('active-order-card-p-submitted')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('active-order-card-s-old')), findsNothing);

    // Load a second page, then flip the sort — pagination must reset.
    await tester.tap(find.byKey(const Key('active-orders-load-more')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('active-order-card-p-preparing')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('active-orders-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.ordersSortOldest).last);
    await tester.pumpAndSettle();

    // Back to a single (first) page, now OLDEST first.
    expect(find.byKey(const Key('active-order-card-s-old')), findsOneWidget);
    expect(
      find.byKey(const Key('active-order-card-p-submitted')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('active-order-card-p-preparing')),
      findsNothing,
    );
  });

  testWidgets('D5 the truncation notice names the ACTUAL sort', (tester) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    await tester.pumpWidget(_wrap(_store(), limit: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('active-queue-all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-orders-truncated')), findsOneWidget);
    expect(find.text(l10n.ordersActiveTruncatedNewest(2, 7)), findsOneWidget);
    // It never claims everything is shown.
    expect(find.text(l10n.ordersActiveTruncatedOldest(2, 7)), findsNothing);

    await tester.tap(find.byKey(const Key('active-orders-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.ordersSortOldest).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.ordersActiveTruncatedOldest(2, 7)), findsOneWidget);
  });

  testWidgets('D6 queue-specific EMPTY states', (tester) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    // Only served orders exist -> In progress is empty.
    final store = DemoOrderStore([
      _order('s1', status: 'served', minutesAgo: 10, paid: true),
    ]);
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-orders-empty')), findsOneWidget);
    expect(find.text(l10n.ordersActiveEmptyInProgress), findsOneWidget);

    await tester.tap(find.byKey(const Key('active-queue-awaiting-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-orders-empty')), findsNothing);

    // Now the reverse: only in-progress work -> Awaiting close is empty.
    final store2 = DemoOrderStore([
      _order('p1', status: 'preparing', minutesAgo: 5),
    ]);
    await tester.pumpWidget(_wrap(store2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('active-queue-awaiting-close')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.ordersActiveEmptyAwaitingClose), findsOneWidget);
  });

  testWidgets('D7 a LARGE awaiting-close backlog is stated, never dramatized', (
    tester,
  ) async {
    _sized(tester, 1320);
    final store = DemoOrderStore([
      for (var i = 0; i < kAwaitingCloseBacklogNotice; i++)
        _order('s$i', status: 'served', minutesAgo: 30 + i, paid: true),
    ]);
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('active-queue-awaiting-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('active-orders-awaiting-backlog')),
      findsOneWidget,
    );
    // No bulk close, and no invented urgency/priority language.
    expect(find.textContaining('urgent'), findsNothing);
    expect(find.textContaining('Complete all'), findsNothing);
  });

  // ===== E. refresh simplification ==========================================
  testWidgets('E1 there is NO auto-refresh switch anywhere', (tester) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-orders-auto-refresh')), findsNothing);
    expect(find.byType(Switch), findsNothing);
    // The honest stamp stays; the board is never called "live" or "real-time".
    expect(find.byKey(const Key('active-orders-last-updated')), findsOneWidget);
    expect(find.textContaining('Live'), findsNothing);
    expect(find.textContaining('Real-time'), findsNothing);
  });

  testWidgets('E2 the board refreshes ITSELF while visible (fake time)', (
    tester,
  ) async {
    _sized(tester, 1320);
    final store = _store();
    // Injected 10s cadence + FAKE time — no real delay.
    await tester.pumpWidget(_wrap(store, poll: const Duration(seconds: 10)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-order-card-p-ready')), findsOneWidget);

    // An order is completed OUT OF BAND (as the POS/KDS would): the board picks
    // it up on its own, with no user action.
    expect(store.complete('s-paid'), isNull);
    await tester.tap(find.byKey(const Key('active-queue-awaiting-close')));
    await tester.pumpAndSettle();
    // (the queue change already re-read, so seed a second out-of-band change)
    expect(store.complete('s-old'), isNull);
    expect(find.byKey(const Key('active-order-card-s-old')), findsOneWidget);

    // Advance FAKE time past the interval — the poll fires.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-order-card-s-old')), findsNothing);
  });

  testWidgets('E3 polling STOPS on History and resumes on Active', (
    tester,
  ) async {
    _sized(tester, 1320);
    final store = _store();
    await tester.pumpWidget(_wrap(store, poll: const Duration(seconds: 10)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('orders-tab-history')));
    await tester.pumpAndSettle();
    expect(find.byType(OrderHistoryView), findsOneWidget);

    // While History is up, the active board is disposed: advancing fake time must
    // not fire any active-board work (and must leave no pending timer).
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveOrdersView), findsNothing);

    // Back to Active: it re-reads and shows the board again.
    await tester.tap(find.byKey(const Key('orders-tab-active')));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveOrdersView), findsOneWidget);
    expect(find.byKey(const Key('active-order-card-p-ready')), findsOneWidget);
  });

  testWidgets('E4 a failed refresh KEEPS the rows and says so', (tester) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    final store = _store();
    final repo = _FlakyRepo(_repo(store));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          demoOrderStoreProvider.overrideWithValue(store),
          activeOrdersRepositoryProvider.overrideWithValue(repo),
          activeOrdersClockProvider.overrideWithValue(_clock),
          activeOrdersPollIntervalProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(body: OrdersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-order-card-p-ready')), findsOneWidget);

    // The NEXT read fails — the rows must survive it.
    repo.failNext = true;
    await tester.tap(find.byKey(const Key('orders-refresh')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-order-card-p-ready')), findsOneWidget);
    expect(
      find.byKey(const Key('active-orders-refresh-failed')),
      findsOneWidget,
    );
    expect(find.text(l10n.ordersActiveRefreshFailed), findsOneWidget);
    // The whole board is NOT replaced by an error page.
    expect(find.byKey(const Key('active-orders-error')), findsNothing);
  });

  // ===== F. History stays a separate archive =================================
  testWidgets('F1 Active and History keep INDEPENDENT filter state', (
    tester,
  ) async {
    _sized(tester, 1320);
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    // Narrow the ACTIVE board to the awaiting-close queue.
    await tester.tap(find.byKey(const Key('active-queue-awaiting-close')));
    await tester.pumpAndSettle();

    // Go to History and change ITS range.
    await tester.tap(find.byKey(const Key('orders-tab-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('orders-range-yesterday')));
    await tester.pumpAndSettle();

    // Back to Active: the QUEUE is still awaiting-close (History did not reset it).
    await tester.tap(find.byKey(const Key('orders-tab-active')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('active-orders-awaiting-explainer')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('active-order-card-s-paid')), findsOneWidget);

    // And History still remembers ITS range.
    await tester.tap(find.byKey(const Key('orders-tab-history')));
    await tester.pumpAndSettle();
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const Key('orders-range-yesterday')),
    );
    expect(chip.selected, isTrue);
  });

  // ===== G. responsive + RTL/LTR + a11y =====================================
  for (final width in <double>[390, 700, 940, 1320]) {
    testWidgets('G1 no horizontal overflow at ${width}px', (tester) async {
      _sized(tester, width, 3400);
      await tester.pumpWidget(_wrap(_store()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The queue selector and the sort control are usable at every width.
      expect(
        find.byKey(const Key('active-queue-awaiting-close')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('active-orders-sort')), findsOneWidget);

      await tester.tap(find.byKey(const Key('active-queue-awaiting-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in <String>['ar', 'he', 'en']) {
    testWidgets('G2 the queues render in the right direction ($locale)', (
      tester,
    ) async {
      _sized(tester, 1320);
      final l10n = await _l(locale);
      await tester.pumpWidget(_wrap(_store(), locale: locale));
      await tester.pumpAndSettle();

      expect(find.text(l10n.ordersQueueInProgress), findsWidgets);
      expect(find.text(l10n.ordersQueueAwaitingClose), findsWidgets);
      expect(find.text(l10n.ordersActiveSubtitleV2), findsWidgets);

      final expected = locale == 'en' ? TextDirection.ltr : TextDirection.rtl;
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('active-queue-in-progress'))),
        ),
        expected,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('G3 the queue + sort controls are keyboard/semantics friendly', (
    tester,
  ) async {
    _sized(tester, 1320);
    final l10n = await _l('en');
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_store()));
    await tester.pumpAndSettle();

    // Each queue segment is a button that announces its SELECTED state (never
    // colour alone).
    expect(
      tester.getSemantics(find.byKey(const Key('active-queue-in-progress'))),
      matchesSemantics(
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        label: l10n.ordersQueueInProgress,
        hasTapAction: true,
        // Focusable AND focus-actionable: reachable and operable by keyboard.
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    // The manual refresh survives and carries a real semantic label (its tooltip
    // is what assistive tech announces).
    final refresh = find.byKey(const Key('orders-refresh'));
    expect(refresh, findsOneWidget);
    expect(tester.widget<IconButton>(refresh).tooltip, l10n.ordersRefresh);
    expect(find.byTooltip(l10n.ordersRefresh), findsOneWidget);
    handle.dispose();
  });
}

/// Fails the NEXT read on demand — for the "a failed refresh keeps the rows" path.
class _FlakyRepo implements ActiveOrdersRepository {
  _FlakyRepo(this._inner);

  final ActiveOrdersRepository _inner;
  bool failNext = false;

  @override
  Future<ActiveOrdersSnapshot> loadActive(
    ActiveOrdersQuery query, {
    String? cursor,
  }) async {
    if (failNext) {
      failNext = false;
      throw const ActiveOrdersException('boom');
    }
    return _inner.loadActive(query, cursor: cursor);
  }
}
