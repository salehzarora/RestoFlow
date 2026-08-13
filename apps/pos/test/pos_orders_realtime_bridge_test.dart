import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        DisabledInvalidationSource,
        InvalidationHint,
        InvalidationSource,
        RealtimeScope;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart'
    show PosSnapshotPage;
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/pos_menu_screen.dart' show PosMenuScreen;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_orders_realtime_bridge.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/pos_sync_lifecycle.dart';

/// POS-OPEN-ORDERS-REALTIME-GATE-013 — the branch-hint bridge:
/// hint → EXISTING authoritative refresh, coalesced; orders-entity only; no
/// payload ever applied; lifecycle owns socket start/stop; polling untouched.
final DateTime _pinnedNow = DateTime.utc(2026, 8, 13, 12);
DateTime _clock() => _pinnedNow;

InvalidationHint _hint(String entityId, {String entity = 'orders'}) =>
    InvalidationHint(
      organizationId: kDemoSyncScope.organizationId,
      branchId: kDemoSyncScope.branchId,
      entity: entity,
      entityId: entityId,
    );

/// A controllable fake source (the KDS wiring-test pattern).
class _FakeSource implements InvalidationSource {
  final StreamController<InvalidationHint> _c =
      StreamController<InvalidationHint>.broadcast();
  bool started = false;
  bool disposed = false;

  void emit(InvalidationHint h) => _c.add(h);
  void emitError() => _c.addError(StateError('socket burp'));

  @override
  Stream<InvalidationHint> get hints => _c.stream;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _c.close();
  }
}

PosOrderSnapshot _snapshot(
  String orderId, {
  required String status,
  String code = '#RX0001',
  int revision = 2,
}) => PosOrderSnapshot(
  orderId: orderId,
  orderCode: code,
  revision: revision,
  status: status,
  settlement: PosSettlement.unpaid,
  subtotalMinor: 4200,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 4200,
  createdAt: _pinnedNow.subtract(const Duration(minutes: 3)),
  updatedAt: _pinnedNow.subtract(const Duration(minutes: 1)),
  syncAt: _pinnedNow.subtract(const Duration(minutes: 1)),
  orderType: 'takeaway',
  currencyCode: 'ILS',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B. Bridge unit behavior (injectable debounce)', () {
    late _FakeSource source;
    late List<List<String>> refreshCalls;
    late List<Completer<void>> pendingDelays;
    late PosOrdersRealtimeBridge bridge;

    setUp(() {
      source = _FakeSource();
      refreshCalls = [];
      pendingDelays = [];
      bridge = PosOrdersRealtimeBridge(
        createSource: () => source,
        refreshOrders: (ids) async => refreshCalls.add(ids),
        delay: (_) {
          final c = Completer<void>();
          pendingDelays.add(c);
          return c.future;
        },
      );
    });

    Future<void> flushWindow() async {
      pendingDelays.removeAt(0).complete();
      await Future<void>.delayed(Duration.zero);
    }

    test('B1. an orders hint triggers ONE authoritative targeted refresh '
        'after the debounce — no poll timer involved anywhere', () async {
      await bridge.start();
      expect(source.started, isTrue);
      source.emit(_hint('oid-1'));
      await Future<void>.delayed(Duration.zero);
      expect(refreshCalls, isEmpty, reason: 'debounce window still open');
      await flushWindow();
      expect(refreshCalls, [
        ['oid-1'],
      ]);
      expect(bridge.refreshCount, 1);
    });

    test(
      'B2. a hint storm with duplicates coalesces into ONE deduped batch',
      () async {
        await bridge.start();
        source
          ..emit(_hint('oid-1'))
          ..emit(_hint('oid-2'))
          ..emit(_hint('oid-1'))
          ..emit(_hint('oid-2'))
          ..emit(_hint('oid-3'));
        await Future<void>.delayed(Duration.zero);
        await flushWindow();
        expect(refreshCalls.length, 1);
        expect(refreshCalls.single.toSet(), {'oid-1', 'oid-2', 'oid-3'});
      },
    );

    test('B3. a batch clamps to the repository limit (100 ids)', () async {
      await bridge.start();
      for (var i = 0; i < 130; i++) {
        source.emit(_hint('oid-$i'));
      }
      await Future<void>.delayed(Duration.zero);
      await flushWindow();
      expect(
        refreshCalls.single.length,
        PosOrdersRealtimeBridge.maxIdsPerRefresh,
      );
    });

    test('B4. order_items hints are IGNORED (item id is not an order id; '
        'strip-relevant flows also bump the orders row)', () async {
      await bridge.start();
      source.emit(_hint('item-1', entity: 'order_items'));
      source.emit(_hint('mod-1', entity: 'order_item_modifiers'));
      await Future<void>.delayed(Duration.zero);
      expect(pendingDelays, isEmpty, reason: 'no window even opens');
      expect(refreshCalls, isEmpty);
    });

    test(
      'B5. a stream error is harmless — the NEXT hint still refreshes',
      () async {
        await bridge.start();
        source.emitError();
        await Future<void>.delayed(Duration.zero);
        source.emit(_hint('oid-1'));
        await Future<void>.delayed(Duration.zero);
        await flushWindow();
        expect(refreshCalls, [
          ['oid-1'],
        ]);
      },
    );

    test('B6. dispose is safe and final: the source is disposed and later '
        'hints/windows are inert', () async {
      await bridge.start();
      source.emit(_hint('oid-1'));
      await Future<void>.delayed(Duration.zero);
      bridge.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(source.disposed, isTrue);
      // The already-open window fires after dispose — nothing happens.
      pendingDelays.removeAt(0).complete();
      await Future<void>.delayed(Duration.zero);
      expect(refreshCalls, isEmpty);
    });

    test('B7. start is idempotent', () async {
      await bridge.start();
      await bridge.start();
      source.emit(_hint('oid-1'));
      await Future<void>.delayed(Duration.zero);
      await flushWindow();
      expect(refreshCalls.length, 1);
    });
  });

  group('L. Provider + lifecycle wiring', () {
    testWidgets('L1. with a valid scope the bridge exists, the factory gets '
        'the EXACT branch scope, and the lifecycle starts the source', (
      tester,
    ) async {
      final created = <_FakeSource>[];
      RealtimeScope? seenScope;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posInvalidationSourceFactoryProvider.overrideWithValue((scope) {
              seenScope = scope;
              final s = _FakeSource();
              created.add(s);
              return s;
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const PosSyncLifecycle(child: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(created, hasLength(1));
      expect(created.single.started, isTrue);
      expect(seenScope?.branchId, kDemoSyncScope.branchId);
      expect(seenScope?.organizationId, kDemoSyncScope.organizationId);
      expect(seenScope?.branchTopic, 'kds:branch:${kDemoSyncScope.branchId}');
    });

    testWidgets('L2. backgrounding DISPOSES the socket; resuming starts a '
        'FRESH authorized subscription', (tester) async {
      final created = <_FakeSource>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posInvalidationSourceFactoryProvider.overrideWithValue((_) {
              final s = _FakeSource();
              created.add(s);
              return s;
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const PosSyncLifecycle(child: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(created.single.started, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(
        created.first.disposed,
        isTrue,
        reason: 'background closes the channel',
      );
      expect(created, hasLength(1), reason: 'no new socket while backgrounded');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        created,
        hasLength(2),
        reason: 'resume opens a FRESH subscription',
      );
      expect(created.last.started, isTrue);
      expect(created.last.disposed, isFalse);
    });

    test(
      'L3. scope change disposes the OLD branch subscription and creates '
      'a NEW one; scope loss (logout/unpair) disposes and yields null',
      () async {
        final created = <_FakeSource>[];
        final scopeState = StateProvider<PosSyncScope?>(
          (ref) => const PosSyncScope(
            organizationId: 'org-1',
            restaurantId: 'r1',
            branchId: 'branch-A',
            deviceId: 'dev-1',
          ),
        );
        final container = ProviderContainer(
          overrides: [
            posSyncScopeProvider.overrideWith((ref) => ref.watch(scopeState)),
            posInvalidationSourceFactoryProvider.overrideWithValue((_) {
              final s = _FakeSource();
              created.add(s);
              return s;
            }),
          ],
        );
        addTearDown(container.dispose);

        final bridgeA = container.read(posOrdersRealtimeBridgeProvider);
        expect(bridgeA, isNotNull);
        await bridgeA!.start();
        expect(created, hasLength(1));
        expect(created.single.started, isTrue);

        // Branch switch: the old channel MUST NOT survive.
        container.read(scopeState.notifier).state = const PosSyncScope(
          organizationId: 'org-1',
          restaurantId: 'r1',
          branchId: 'branch-B',
          deviceId: 'dev-1',
        );
        final bridgeB = container.read(posOrdersRealtimeBridgeProvider);
        expect(bridgeB, isNotNull);
        expect(identical(bridgeA, bridgeB), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(
          created.first.disposed,
          isTrue,
          reason: 'old branch subscription cannot survive a branch switch',
        );
        await bridgeB!.start();
        expect(
          created,
          hasLength(2),
          reason: 'the new branch gets its own fresh subscription',
        );

        // Scope loss: bridge is gone, last source disposed.
        container.read(scopeState.notifier).state = null;
        expect(container.read(posOrdersRealtimeBridgeProvider), isNull);
        await Future<void>.delayed(Duration.zero);
        expect(created.last.disposed, isTrue);
      },
    );

    test(
      'L4. the DEFAULT factory is DISABLED — demo/tests open no socket',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final factory = container.read(posInvalidationSourceFactoryProvider);
        expect(
          factory(const RealtimeScope(organizationId: 'o', branchId: 'b')),
          isA<DisabledInvalidationSource>(),
        );
      },
    );
  });

  group('I. End-to-end: hint → authoritative refresh → strip', () {
    SubmittedOrderView view(String number) => SubmittedOrderView(
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

    Future<InMemoryRecentOrdersStore> seeded(
      List<PosRecentOrder> orders,
    ) async {
      final store = InMemoryRecentOrdersStore();
      await store.persist(kDemoSyncScope.key, orders);
      return store;
    }

    Widget app({
      required InMemoryRecentOrdersStore store,
      required DemoOrderSnapshotRepository repo,
      required _FakeSource source,
    }) => ProviderScope(
      overrides: [
        posRecentOrdersStoreProvider.overrideWithValue(store),
        orderSnapshotRepositoryProvider.overrideWithValue(repo),
        posSyncPollIntervalProvider.overrideWithValue(null),
        posSyncClockProvider.overrideWithValue(_clock),
        posInvalidationSourceFactoryProvider.overrideWithValue((_) => source),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosSyncLifecycle(child: PosMenuScreen()),
      ),
    );

    void size(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('I1. a hint for an UNSEEN remote order fetches it '
        'authoritatively and the card appears — with the poll timer OFF', (
      tester,
    ) async {
      size(tester);
      final source = _FakeSource();
      // The repo starts EMPTY: the startup window pull sees nothing. The
      // remote order is created AFTER startup — exactly the case polling
      // would only catch on a later tick.
      final repo = DemoOrderSnapshotRepository();
      await tester.pumpWidget(
        app(store: await seeded([]), repo: repo, source: source),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-orders-strip')), findsNothing);
      expect(source.started, isTrue);

      repo.upsert(_snapshot('oid-rx', status: 'preparing', code: '#RX0001'));
      source.emit(_hint('oid-rx'));
      // Real 250ms debounce + the targeted fetch + repaint.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('open-strip-order-#RX0001')),
        findsOneWidget,
        reason: 'branchDiscovered adoption must surface the card immediately',
      );
    });

    testWidgets('I2. a status hint repaints; a TERMINAL hint removes the '
        'card through the canonical predicate', (tester) async {
      size(tester);
      final source = _FakeSource();
      // Empty at startup: the local submitted order is the only truth.
      final repo = DemoOrderSnapshotRepository();
      final store = await seeded([
        PosRecentOrder(
          order: view('#U1'),
          status: 'submitted',
          submittedAt: _pinnedNow.subtract(const Duration(minutes: 7)),
        ),
      ]);
      await tester.pumpWidget(app(store: store, repo: repo, source: source));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.posOrdersStatusSubmitted), findsOneWidget);

      // Remote kitchen advanced the order to READY.
      repo.upsert(_snapshot('oid-#U1', status: 'ready', code: '#U1'));
      source.emit(_hint('oid-#U1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('open-strip-order-#U1')),
          matching: find.text(l10n.posOrdersStatusReady),
        ),
        findsOneWidget,
      );

      // Remote completion: a NEWER terminal snapshot -> the predicate drops
      // the card (an equal-revision copy would be reconciled as stale).
      repo.upsert(
        _snapshot('oid-#U1', status: 'completed', code: '#U1', revision: 3),
      );
      source.emit(_hint('oid-#U1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-strip-order-#U1')), findsNothing);
      expect(find.byKey(const Key('open-orders-strip')), findsNothing);
    });

    testWidgets('I3. realtime adds ZERO polling: one hint = one targeted '
        'fetch, no window/change pulls from the strip', (tester) async {
      size(tester);
      final source = _FakeSource();
      final repo = _CountingRepo(
        seed: [_snapshot('oid-rx', status: 'preparing', code: '#RX0001')],
      );
      await tester.pumpWidget(
        app(store: await seeded([]), repo: repo, source: source),
      );
      await tester.pumpAndSettle();
      final baselineWindow = repo.windowCalls;
      final baselineChanges = repo.changeCalls;

      source.emit(_hint('oid-rx'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(repo.orderCalls, 1, reason: 'exactly one targeted fetch');
      expect(repo.windowCalls, baselineWindow, reason: 'no extra window pull');
      expect(repo.changeCalls, baselineChanges, reason: 'no extra change pull');
    });
  });
}

/// Counting repo for I3 (targeted-vs-poll accounting).
class _CountingRepo extends DemoOrderSnapshotRepository {
  _CountingRepo({super.seed});

  int windowCalls = 0;
  int changeCalls = 0;
  int orderCalls = 0;

  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) {
    windowCalls++;
    return super.fetchWindow(
      before: before,
      limit: limit,
      windowDays: windowDays,
    );
  }

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) {
    changeCalls++;
    return super.fetchChanges(
      cursor: cursor,
      limit: limit,
      windowDays: windowDays,
    );
  }

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) {
    orderCalls++;
    return super.fetchOrders(orderIds);
  }
}
