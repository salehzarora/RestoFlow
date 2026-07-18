import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/ready_notifications_store.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart'
    show kDemoSyncScope;
import 'package:restoflow_pos/src/state/ready_notifications_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/ready_alert_overlay.dart';
import 'package:restoflow_pos/src/widgets/ready_notification_bell.dart';
import 'package:restoflow_pos/src/widgets/ready_notifications_sheet.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// PSC-001A — the notification UI: bell/badge, alert overlay (individual,
/// grouped, reduced motion), the history sheet's states and rows, the
/// open-order focus reuse, and AR/HE RTL + EN LTR rendering.

String _uid(int n) =>
    '0a000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
String _oid(int n) =>
    '0b000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

PosReadyNotificationRecord _record(
  int n, {
  String type = 'initial_order',
  bool read = false,
  String status = 'ready',
}) => PosReadyNotificationRecord(
  workUnitType: type,
  workUnitId: _uid(n),
  orderId: _oid(n),
  orderCode: '#00000$n',
  roundNumber: type == 'service_round' ? 2 : null,
  orderType: 'dine_in',
  tableLabel: 'T$n',
  readyAt: DateTime.utc(2026, 7, 23, 10, n).toIso8601String(),
  workUnitStatus: status,
  parentOrderStatus: status == 'ready' ? 'preparing' : status,
  revision: 3,
  discoveredAt: DateTime.utc(2026, 7, 23, 10, n, 5).toIso8601String(),
  read: read,
  alerted: true,
);

/// A fixed-state stub controller: pure UI rendering without polling.
class _StubReadyController extends PosReadyNotificationsController {
  _StubReadyController(this.fixed);
  final PosReadyNotificationsState fixed;
  final List<String> readCalls = [];
  int dismissCalls = 0;
  int reconcileCalls = 0;
  int refreshCalls = 0;
  int markAllCalls = 0;
  bool markAllResult = true;

  @override
  PosReadyNotificationsState build() => fixed;

  @override
  void markRead(String identityKey) => readCalls.add(identityKey);

  @override
  Future<bool> markAllCurrentRead() async {
    markAllCalls++;
    return markAllResult;
  }

  @override
  void dismissAlert() {
    dismissCalls++;
    state = state.copyWith(clearActiveAlert: true);
  }

  @override
  Future<void> reconcileStatuses() async {
    reconcileCalls++;
  }

  /// Simulates a live state change (e.g. a new arrival) while UI is open.
  void setRecords(List<PosReadyNotificationRecord> records) =>
      state = state.copyWith(records: records);

  @override
  Future<void> refreshNow() async {
    refreshCalls++;
  }
}

Future<(_StubReadyController, ProviderContainer)> _pump(
  WidgetTester tester,
  Widget home, {
  PosReadyNotificationsState? readyState,
  Locale locale = const Locale('en'),
  bool disableAnimations = false,
  bool settle = true,
  List<PosRecentOrder> seededOrders = const [],
}) async {
  final stub = _StubReadyController(
    readyState ?? const PosReadyNotificationsState(initialized: true),
  );
  final store = InMemoryRecentOrdersStore();
  if (seededOrders.isNotEmpty) {
    await store.persist(kDemoSyncScope.key, seededOrders);
  }
  final container = ProviderContainer(
    overrides: [
      posReadyNotificationsControllerProvider.overrideWith(() => stub),
      posRecentOrdersStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return (stub, container);
}

PosRecentOrder _recentOrderWith({
  required int n,
  required String code,
  required int hoursAgo,
}) => PosRecentOrder.discovered(
  PosOrderSnapshot(
    orderId: _oid(n),
    orderCode: code,
    revision: 3,
    status: 'ready',
    settlement: PosSettlement.unpaid,
    subtotalMinor: 2500,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 2500,
    createdAt: DateTime.now().toUtc().subtract(Duration(hours: hoursAgo)),
    updatedAt: DateTime.now().toUtc().subtract(Duration(hours: hoursAgo)),
    syncAt: DateTime.now().toUtc().subtract(Duration(hours: hoursAgo)),
    orderType: 'dine_in',
    tableLabel: 'T$n',
    currencyCode: 'ILS',
  ),
);

PosRecentOrder _recentOrder(int n) => PosRecentOrder.discovered(
  PosOrderSnapshot(
    orderId: _oid(n),
    orderCode: '#00000$n',
    revision: 3,
    status: 'ready',
    settlement: PosSettlement.unpaid,
    subtotalMinor: 2500,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 2500,
    createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    updatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    syncAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    orderType: 'dine_in',
    tableLabel: 'T$n',
    currencyCode: 'ILS',
  ),
);

void main() {
  group('bell + badge', () {
    testWidgets('zero unread → no badge; unread → count; >99 → 99+; semantics '
        'carry the unread count', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          appBar: null,
          body: Center(child: ReadyNotificationBell()),
        ),
      );
      expect(find.byKey(const Key('ready-bell-button')), findsOneWidget);
      expect(find.byType(Badge), findsNothing);

      await _pump(
        tester,
        const Scaffold(body: Center(child: ReadyNotificationBell())),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1), _record(2), _record(3, read: true)],
        ),
      );
      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'^Ready notifications\. 2 Unread$')),
        findsOneWidget,
      );
      semantics.dispose();

      await _pump(
        tester,
        const Scaffold(body: Center(child: ReadyNotificationBell())),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [for (var i = 1; i <= 120; i++) _record(i)],
        ),
      );
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('TAPPING the bell marks all current notifications read FIRST '
        'and then opens the history sheet', (tester) async {
      final (stub, _) = await _pump(
        tester,
        const Scaffold(body: Center(child: ReadyNotificationBell())),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1), _record(2)],
        ),
      );
      await tester.tap(find.byKey(const Key('ready-bell-button')));
      await tester.pumpAndSettle();
      expect(stub.markAllCalls, 1);
      expect(
        find.byKey(const Key('ready-notifications-sheet')),
        findsOneWidget,
      );
    });

    testWidgets('a DOUBLE-TAP runs one mark-all and opens exactly ONE sheet', (
      tester,
    ) async {
      final (stub, _) = await _pump(
        tester,
        const Scaffold(body: Center(child: ReadyNotificationBell())),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1)],
        ),
      );
      await tester.tap(find.byKey(const Key('ready-bell-button')));
      await tester.tap(
        find.byKey(const Key('ready-bell-button')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(stub.markAllCalls, 1);
      expect(
        find.byKey(const Key('ready-notifications-sheet')),
        findsOneWidget,
      );
    });

    testWidgets('a FAILED mark-all still opens the sheet once — with the '
        'unread truth intact, nothing pretends to be read', (tester) async {
      final (stub, _) = await _pump(
        tester,
        const Scaffold(body: Center(child: ReadyNotificationBell())),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1), _record(2)],
        ),
      );
      stub.markAllResult = false;
      await tester.tap(find.byKey(const Key('ready-bell-button')));
      await tester.pumpAndSettle();
      expect(stub.markAllCalls, 1);
      expect(
        find.byKey(const Key('ready-notifications-sheet')),
        findsOneWidget,
      );
      // The sheet shows the honest unread rows (state untouched on failure).
      expect(
        find.byKey(Key('ready-unread-initial_order|${_uid(1)}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('ready-unread-initial_order|${_uid(2)}')),
        findsOneWidget,
      );
    });
  });

  group('alert overlay', () {
    Widget host() => const Scaffold(
      body: Stack(children: [SizedBox.expand(), ReadyAlertOverlay()]),
    );

    testWidgets('an INDIVIDUAL alert names the work, order and table; '
        'dismissing calls the controller and marks nothing read', (
      tester,
    ) async {
      final (stub, _) = await _pump(
        tester,
        host(),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1)],
          activeAlert: PosReadyAlert(id: 1, items: [_record(1)]),
        ),
      );
      expect(find.textContaining('Order ready'), findsOneWidget);
      expect(find.textContaining('#000001'), findsOneWidget);
      expect(find.textContaining('T1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ready-alert-dismiss')));
      await tester.pumpAndSettle();
      expect(stub.dismissCalls, 1);
      expect(stub.readCalls, isEmpty);
    });

    testWidgets('a ROUND alert says Addition ready — Round N', (tester) async {
      await _pump(
        tester,
        host(),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(2, type: 'service_round')],
          activeAlert: PosReadyAlert(
            id: 1,
            items: [_record(2, type: 'service_round')],
          ),
        ),
      );
      expect(find.textContaining('Addition ready — Round 2'), findsOneWidget);
    });

    testWidgets('a GROUPED alert says N orders ready', (tester) async {
      await _pump(
        tester,
        host(),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1), _record(2), _record(3)],
          activeAlert: PosReadyAlert(
            id: 1,
            items: [_record(1), _record(2), _record(3)],
          ),
        ),
      );
      expect(find.text('3 orders ready'), findsOneWidget);
    });

    testWidgets('REDUCED MOTION renders the card statically (no entrance '
        'animation); normal motion animates finitely', (tester) async {
      await _pump(
        tester,
        host(),
        disableAnimations: true,
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1)],
          activeAlert: PosReadyAlert(id: 1, items: [_record(1)]),
        ),
      );
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(find.byKey(const Key('ready-alert-open')), findsOneWidget);

      await _pump(
        tester,
        host(),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1)],
          activeAlert: PosReadyAlert(id: 1, items: [_record(1)]),
        ),
      );
      expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
      await tester.pumpAndSettle(); // the entrance is FINITE — it settles
    });

    testWidgets('Arabic renders the alert RTL', (tester) async {
      await _pump(
        tester,
        host(),
        locale: const Locale('ar'),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1)],
          activeAlert: PosReadyAlert(id: 1, items: [_record(1)]),
        ),
      );
      final direction = Directionality.of(
        tester.element(find.byKey(const Key('ready-alert-open'))),
      );
      expect(direction, TextDirection.rtl);
      expect(find.textContaining('الطلب جاهز'), findsOneWidget);
    });
  });

  group('history sheet', () {
    testWidgets('EMPTY state + the sheet-open status sweep', (tester) async {
      final (stub, _) = await _pump(
        tester,
        const Scaffold(body: ReadyNotificationsSheet()),
      );
      expect(find.byKey(const Key('ready-sheet-empty')), findsOneWidget);
      expect(stub.reconcileCalls, 1); // opening swept statuses exactly once
    });

    testWidgets('LOADING state while the first load runs', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: ReadyNotificationsSheet()),
        readyState: const PosReadyNotificationsState(loading: true),
        settle: false, // the spinner animates — settle would never terminate
      );
      expect(find.byKey(const Key('ready-sheet-loading')), findsOneWidget);
    });

    testWidgets('DEGRADED shows the quiet honest subtitle', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: ReadyNotificationsSheet()),
        readyState: PosReadyNotificationsState(
          initialized: true,
          degraded: true,
          records: [_record(1)],
        ),
      );
      expect(
        find.text('Ready updates temporarily unavailable — retrying'),
        findsOneWidget,
      );
    });

    testWidgets('rows: initial vs Addition/Round N, ready time, status pill, '
        'unread dot; Refresh triggers poll+sweep; NO Mark-all-read action '
        'remains (the bell owns acknowledgement)', (tester) async {
      final (stub, _) = await _pump(
        tester,
        const Scaffold(body: ReadyNotificationsSheet()),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [
            _record(1, read: true, status: 'served'),
            _record(2, type: 'service_round'),
          ],
        ),
      );
      expect(
        find.byKey(Key('ready-row-initial_order|${_uid(1)}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('ready-row-service_round|${_uid(2)}')),
        findsOneWidget,
      );
      expect(find.textContaining('Addition ready — Round 2'), findsOneWidget);
      expect(find.textContaining('Ready at'), findsNWidgets(2));
      expect(find.text('Served'), findsOneWidget);
      // Only the unread round row carries the dot.
      expect(
        find.byKey(Key('ready-unread-service_round|${_uid(2)}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('ready-unread-initial_order|${_uid(1)}')),
        findsNothing,
      );
      final sweepsBefore = stub.reconcileCalls;
      await tester.tap(find.byKey(const Key('ready-refresh-button')));
      await tester.pump();
      expect(stub.refreshCalls, 1);
      expect(stub.reconcileCalls, sweepsBefore + 1);
      // The separate Mark-all-read action is GONE — the bell tap is the
      // acknowledgement; the sheet itself marks nothing.
      expect(find.byKey(const Key('ready-mark-all-read')), findsNothing);
      expect(find.text('Mark all read'), findsNothing);
      expect(stub.markAllCalls, 0);
    });

    testWidgets('OPEN ORDER: a row tap marks THAT notification read and opens '
        'the orders centre with the exact orderId PINNED FIRST — the search '
        'stays independent and empty', (tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (stub, _) = await _pump(
        tester,
        Builder(
          builder: (context) => const Scaffold(body: ReadyNotificationsSheet()),
        ),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(1)],
        ),
        seededOrders: [_recentOrder(1)],
      );
      await tester.tap(find.byKey(Key('ready-row-initial_order|${_uid(1)}')));
      await tester.pumpAndSettle();
      expect(stub.readCalls, ['initial_order|${_uid(1)}']);
      // The orders centre opened focused: All selected, the TARGET is the
      // FIRST card, and the text search stayed independent/empty.
      expect(find.byKey(const Key('recent-orders-sheet')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('orders-search-field')))
            .controller!
            .text,
        isEmpty,
      );
      final firstCard = tester
          .widgetList(
            find.byWidgetPredicate(
              (w) => w.key.toString().contains('recent-order-'),
            ),
          )
          .first;
      expect(firstCard.key, const Key('recent-order-#000001'));
    });

    testWidgets('Hebrew renders the sheet RTL with localized strings', (
      tester,
    ) async {
      await _pump(
        tester,
        const Scaffold(body: ReadyNotificationsSheet()),
        locale: const Locale('he'),
        readyState: PosReadyNotificationsState(
          initialized: true,
          records: [_record(2, type: 'service_round')],
        ),
      );
      final direction = Directionality.of(
        tester.element(find.byKey(const Key('ready-notifications-sheet'))),
      );
      expect(direction, TextDirection.rtl);
      expect(find.text('היסטוריית התראות'), findsOneWidget);
      expect(find.textContaining('התוספת מוכנה — סבב 2'), findsOneWidget);
    });
  });

  group('history sheet display limit (newest 8 + Show more)', () {
    int listCount(WidgetTester tester) =>
        tester.widget<ListView>(find.byType(ListView)).semanticChildCount!;

    Future<(_StubReadyController, ProviderContainer)> pumpSheet(
      WidgetTester tester,
      int records,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      return _pump(
        tester,
        const Scaffold(body: ReadyNotificationsSheet()),
        readyState: PosReadyNotificationsState(
          initialized: true,
          // Deliberately SHUFFLED (odd then even) — the sheet must sort
          // newest-first itself.
          records: [
            for (var n = 1; n <= records; n += 2) _record(n),
            for (var n = 2; n <= records; n += 2) _record(n),
          ],
        ),
      );
    }

    testWidgets('6 records → all 6 visible and NO Show more', (tester) async {
      await pumpSheet(tester, 6);
      expect(listCount(tester), 6);
      expect(find.byKey(const Key('ready-show-more')), findsNothing);
    });

    testWidgets('12 records → the NEWEST 8 first, Show more reveals all 12 '
        'and then hides', (tester) async {
      await pumpSheet(tester, 12);
      expect(listCount(tester), 8);
      // Visible are n=12..5; n=4 is NOT in the list at all.
      expect(
        find.byKey(Key('ready-row-initial_order|${_uid(12)}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('ready-row-initial_order|${_uid(4)}')),
        findsNothing,
      );
      expect(find.text('Show more'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ready-show-more')));
      await tester.pumpAndSettle();
      expect(listCount(tester), 12);
      expect(find.byKey(const Key('ready-show-more')), findsNothing);
    });

    testWidgets('25 records reveal 8 → 16 → 24 → 25', (tester) async {
      await pumpSheet(tester, 25);
      expect(listCount(tester), 8);
      for (final expected in [16, 24, 25]) {
        await tester.tap(find.byKey(const Key('ready-show-more')));
        await tester.pumpAndSettle();
        expect(listCount(tester), expected);
      }
      expect(find.byKey(const Key('ready-show-more')), findsNothing);
    });

    testWidgets('REOPENING the sheet starts back at the newest 8', (
      tester,
    ) async {
      await pumpSheet(tester, 12);
      await tester.tap(find.byKey(const Key('ready-show-more')));
      await tester.pumpAndSettle();
      expect(listCount(tester), 12);
      // Close (a fresh mount) and reopen — a NEW sheet State resets to 8.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpSheet(tester, 12);
      expect(listCount(tester), 8);
    });

    testWidgets('NEWEST-FIRST ordering; a record arriving while OPEN sorts '
        'into position within the same visible page', (tester) async {
      final (stub, _) = await pumpSheet(tester, 9);
      expect(listCount(tester), 8);
      // Topmost row is the newest (n=9); n=1 (the oldest) is not listed.
      final topDy = tester
          .getTopLeft(find.byKey(Key('ready-row-initial_order|${_uid(9)}')))
          .dy;
      final secondDy = tester
          .getTopLeft(find.byKey(Key('ready-row-initial_order|${_uid(8)}')))
          .dy;
      expect(topDy, lessThan(secondDy));
      expect(
        find.byKey(Key('ready-row-initial_order|${_uid(1)}')),
        findsNothing,
      );
      // A NEW arrival (n=30, the newest) appears FIRST; the visible window
      // stays at 8, so the previous 8th (n=2) slides out.
      stub.setRecords([for (var n = 1; n <= 9; n++) _record(n), _record(30)]);
      await tester.pumpAndSettle();
      expect(listCount(tester), 8);
      final newTopDy = tester
          .getTopLeft(find.byKey(Key('ready-row-initial_order|${_uid(30)}')))
          .dy;
      expect(
        newTopDy,
        lessThan(
          tester
              .getTopLeft(find.byKey(Key('ready-row-initial_order|${_uid(9)}')))
              .dy,
        ),
      );
      expect(
        find.byKey(Key('ready-row-initial_order|${_uid(2)}')),
        findsNothing,
      );
    });
  });

  group('recent-orders focus (PSC-001A orderId pin)', () {
    Widget? firstCard(WidgetTester tester) => tester
        .widgetList(
          find.byWidgetPredicate(
            (w) => w.key.toString().contains('recent-order-'),
          ),
        )
        .firstOrNull;

    testWidgets('TWO orders sharing one display code: the requested orderId '
        'is the pinned target — identity, never the printed code', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Two DISTINCT orders with the IDENTICAL printed code; the older twin
      // sorts later naturally, so pinning must act by id, not by code order.
      final target = _recentOrderWith(n: 7, code: '#AAAAAA', hoursAgo: 3);
      final impostor = _recentOrderWith(n: 8, code: '#AAAAAA', hoursAgo: 1);
      await _pump(
        tester,
        Scaffold(body: RecentOrdersSheet(focusOrderId: _oid(7))),
        seededOrders: [impostor, target],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('orders-section-all')))
            .selected,
        isTrue,
      );
      // Both twins share the code-based card KEY, so identity is proven by
      // CONTENT: the first rendered card must carry the requested order's
      // table (T7). The target is 3h old and the impostor 1h — natural
      // newest-first sorting would lead with the impostor; only the id pin
      // can put the requested order first.
      final firstCardFinder = find
          .byWidgetPredicate((w) => w.key.toString().contains('recent-order-'))
          .first;
      expect(
        find.descendant(
          of: firstCardFinder,
          matching: find.textContaining('T7'),
        ),
        findsOneWidget,
      );
      expect(firstCard(tester), isNotNull);
    });

    testWidgets('the pin survives the ASYNC cache load; an UNKNOWN id '
        'degrades honestly (no same-code impostor is focused)', (tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(
        tester,
        Scaffold(body: RecentOrdersSheet(focusOrderId: _oid(1))),
        seededOrders: [_recentOrder(2), _recentOrder(1)],
      );
      // The store load is asynchronous — the pin applies once rows land.
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(firstCard(tester)!.key, const Key('recent-order-#000001'));
      // The search stayed independent of the focus.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('orders-search-field')))
            .controller!
            .text,
        isEmpty,
      );

      // A fresh tree — the previous sheet's element/state must not be reused.
      await tester.pumpWidget(const SizedBox.shrink());
      final (_, container) = await _pump(
        tester,
        const Scaffold(
          body: RecentOrdersSheet(
            focusOrderId: 'ffffffff-0000-4000-8000-0000000000ff',
          ),
        ),
        seededOrders: [_recentOrder(1), _recentOrder(2)],
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      // Honest degradation: no pin applied, no same-code substitute — the
      // natural newest-first order stands and both orders remain in state.
      expect(firstCard(tester)!.key, isNot(const Key('recent-order-#000001')));
      final orders = container.read(posRecentOrdersControllerProvider);
      expect(orders.where((o) => o.orderNumber.startsWith('#00000')).length, 2);
    });
  });
}
