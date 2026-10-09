import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/widgets/open_orders_strip.dart';
import 'package:restoflow_pos/src/widgets/order_detail_preview.dart';
import 'package:restoflow_pos/src/widgets/order_status_pills.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:restoflow_pos/src/widgets/table_order_recovery_sheet.dart';

/// ORDER-EDIT-001E — the `has_active_round` status-label rule
/// (STATE_MACHINES §1, DECISION D-043; ORDER_EDIT_DESIGN label test).
///
/// An order can rest at `served` while kitchen work of it is still live (an
/// Add-items round, or a sent-order edit's own round). That `served` is not
/// the pickup and not a table service, so while any round is active the POS
/// MUST NOT say "Picked up" / "Served": it says the round's stage — "In
/// kitchen", or "Ready" where the rounds are visible (the detail preview).
/// Only `served` is overridden. Plus the edit chips on the same surfaces.

Future<AppLocalizations> _l10n([String code = 'en']) =>
    AppLocalizations.delegate.load(Locale(code));

final DateTime _now = DateTime.now().toUtc().subtract(
  const Duration(hours: 1),
); // inside the recent-orders today+yesterday window

PosOrderSnapshot _snap({
  String id = 'oid-AR0001',
  String code = '#AR0001',
  String status = 'served',
  String orderType = 'takeaway',
  bool activeRound = true,
  int editCount = 0,
  bool ackPending = false,
  int revision = 3,
  DateTime? syncAt,
}) => PosOrderSnapshot(
  orderId: id,
  orderCode: code,
  revision: revision,
  status: status,
  settlement: PosSettlement.unpaid,
  subtotalMinor: 4200,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 4200,
  createdAt: _now,
  updatedAt: syncAt ?? _now,
  syncAt: syncAt ?? _now,
  orderType: orderType,
  currencyCode: 'ILS',
  hasActiveRound: activeRound,
  editCount: editCount,
  kitchenEditAckPending: ackPending,
);

PosTableActiveOrder _entry({
  String status = 'served',
  String orderType = 'dine_in',
  bool? kitchenWorkOpen,
}) => PosTableActiveOrder(
  orderId: 'oid-T1',
  orderCode: '#T00001',
  status: status,
  createdAt: _now,
  orderType: orderType,
  kitchenWorkOpen: kitchenWorkOpen,
);

const _noActions = PosOrderActions(
  canPay: false,
  canDiscount: false,
  canFullComp: false,
  canVoid: false,
  canMoveTable: false,
  canOpenReceipt: false,
  pendingKind: null,
);

void main() {
  group('orderStatusLabelFor — only served is overridden', () {
    test('served + takeaway + active round reads In kitchen, never Picked '
        'up', () async {
      final l10n = await _l10n();
      expect(
        orderStatusLabelFor(
          l10n,
          'served',
          OrderType.takeaway,
          hasActiveRound: true,
        ),
        l10n.posOrdersStatusInKitchen,
      );
    });

    test(
      'served + dine-in + active round reads In kitchen, never Served',
      () async {
        final l10n = await _l10n();
        expect(
          orderStatusLabelFor(
            l10n,
            'served',
            OrderType.dineIn,
            hasActiveRound: true,
          ),
          l10n.posOrdersStatusInKitchen,
        );
      },
    );

    test('a known Ready stage reads Ready', () async {
      final l10n = await _l10n();
      expect(
        orderStatusLabelFor(
          l10n,
          'served',
          OrderType.takeaway,
          hasActiveRound: true,
          roundStage: PosRoundStage.ready,
        ),
        l10n.posOrdersStatusReady,
      );
    });

    test('no active round: the existing wording, unchanged', () async {
      final l10n = await _l10n();
      expect(
        orderStatusLabelFor(l10n, 'served', OrderType.takeaway),
        l10n.posOrdersStatusPickedUp,
      );
      expect(
        orderStatusLabelFor(l10n, 'served', OrderType.dineIn),
        l10n.posOrdersStatusServed,
      );
      expect(
        orderStatusLabelFor(
          l10n,
          'served',
          OrderType.takeaway,
          hasActiveRound: false,
        ),
        l10n.posOrdersStatusPickedUp,
      );
    });

    test('every other status ignores the flag', () async {
      final l10n = await _l10n();
      const expected = {
        'submitted': 'posOrdersStatusSubmitted',
        'ready': 'posOrdersStatusReady',
        'preparing': 'posOrdersStatusPreparing',
        'completed': 'posOrdersStatusCompleted',
      };
      for (final status in expected.keys) {
        expect(
          orderStatusLabelFor(
            l10n,
            status,
            OrderType.takeaway,
            hasActiveRound: true,
            roundStage: PosRoundStage.ready,
          ),
          orderStatusLabelFor(l10n, status, OrderType.takeaway),
          reason: status,
        );
      }
      expect(
        orderStatusLabelFor(
          l10n,
          'completed',
          OrderType.dineIn,
          hasActiveRound: true,
        ),
        l10n.posOrdersStatusCompleted,
      );
    });

    test('ar and he', () async {
      for (final code in ['ar', 'he']) {
        final l10n = await _l10n(code);
        final label = orderStatusLabelFor(
          l10n,
          'served',
          OrderType.takeaway,
          hasActiveRound: true,
        );
        expect(label, l10n.posOrdersStatusInKitchen, reason: code);
        expect(label, isNot(l10n.posOrdersStatusPickedUp), reason: code);
      }
      expect((await _l10n('ar')).posOrdersStatusInKitchen, 'في المطبخ');
      expect((await _l10n('he')).posOrdersStatusInKitchen, 'במטבח');
    });
  });

  group('tone and icon', () {
    test('In kitchen: info + the kitchen icon; Ready: success + done_all', () {
      expect(
        orderStatusTone('served', hasActiveRound: true),
        RestoflowTone.info,
      );
      expect(
        orderStatusIcon('served', hasActiveRound: true),
        Icons.local_fire_department_outlined,
      );
      expect(
        orderStatusTone(
          'served',
          hasActiveRound: true,
          roundStage: PosRoundStage.ready,
        ),
        RestoflowTone.success,
      );
      expect(
        orderStatusIcon(
          'served',
          hasActiveRound: true,
          roundStage: PosRoundStage.ready,
        ),
        Icons.done_all,
      );
    });

    test('without an active round: unchanged', () {
      expect(orderStatusTone('served'), RestoflowTone.info);
      expect(orderStatusIcon('served'), Icons.room_service_outlined);
      expect(
        orderStatusIcon('completed', hasActiveRound: true),
        Icons.task_alt,
      );
    });

    test('the strip tints a served order with a live round as in progress', () {
      expect(
        posOpenOrderStripTone('served', hasActiveRound: true),
        RestoflowTone.warning,
      );
      expect(posOpenOrderStripTone('served'), RestoflowTone.success);
      expect(
        posOpenOrderStripTone('ready', hasActiveRound: true),
        RestoflowTone.success,
      );
    });

    test('posServedRoundStage', () {
      expect(posServedRoundStage('served', hasActiveRound: false), isNull);
      expect(
        posServedRoundStage('served', hasActiveRound: true),
        PosRoundStage.inKitchen,
      );
      expect(
        posServedRoundStage(
          'served',
          hasActiveRound: true,
          roundStage: PosRoundStage.ready,
        ),
        PosRoundStage.ready,
      );
      expect(posServedRoundStage('ready', hasActiveRound: true), isNull);
    });
  });

  group('the table labels', () {
    test('served with kitchen_work_open (the floor stand-in) reads In '
        'kitchen', () async {
      final l10n = await _l10n();
      expect(
        tableOrderStatusLabel(l10n, _entry(kitchenWorkOpen: true)),
        l10n.ordersStatusInKitchen,
      );
      expect(
        tableOrderStatusLabel(
          l10n,
          _entry(orderType: 'takeaway', kitchenWorkOpen: true),
        ),
        l10n.ordersStatusInKitchen,
      );
    });

    test('kitchen_work_open false or unknown keeps Served', () async {
      final l10n = await _l10n();
      expect(
        tableOrderStatusLabel(l10n, _entry(kitchenWorkOpen: false)),
        l10n.ordersStatusServed,
      );
      expect(tableOrderStatusLabel(l10n, _entry()), l10n.ordersStatusServed);
    });

    test('the exact flag beats the stand-in, both ways', () async {
      final l10n = await _l10n();
      expect(
        tableOrderStatusLabel(
          l10n,
          _entry(kitchenWorkOpen: true),
          hasActiveRound: false,
        ),
        l10n.ordersStatusServed,
      );
      expect(
        tableOrderStatusLabel(
          l10n,
          _entry(kitchenWorkOpen: false),
          hasActiveRound: true,
        ),
        l10n.ordersStatusInKitchen,
      );
      expect(
        tableActiveOrderSummary(
          l10n,
          _entry(kitchenWorkOpen: false),
          _now,
          hasActiveRound: true,
        ),
        contains(l10n.ordersStatusInKitchen),
      );
    });

    test('other statuses ignore both', () async {
      final l10n = await _l10n();
      expect(
        tableOrderStatusLabel(
          l10n,
          _entry(status: 'ready', kitchenWorkOpen: true),
          hasActiveRound: true,
        ),
        l10n.ordersStatusReady,
      );
    });
  });

  group('orderEditChips', () {
    test('Edited, Kitchen to confirm, Kitchen confirmed', () async {
      final l10n = await _l10n();
      List<String> labels(List<Widget> ws) => [
        for (final w in ws) (w as RestoflowStatusPill).label,
      ];
      expect(
        orderEditChips(
          l10n,
          keySuffix: 'x',
          editCount: 0,
          kitchenAckPending: false,
        ),
        isEmpty,
      );
      expect(
        labels(
          orderEditChips(
            l10n,
            keySuffix: 'x',
            editCount: 2,
            kitchenAckPending: true,
            kitchenConfirmed: true,
          ),
        ),
        [l10n.posOrderEditedChip, l10n.posOrderEditKitchenPendingChip],
        reason: 'pending wins over confirmed',
      );
      expect(
        labels(
          orderEditChips(
            l10n,
            keySuffix: 'x',
            editCount: 1,
            kitchenAckPending: false,
            kitchenConfirmed: true,
          ),
        ),
        [l10n.posOrderEditedChip, l10n.posOrderEditKitchenConfirmedChip],
      );
    });
  });

  group('widgets', () {
    void size(WidgetTester tester, [Size s = const Size(1400, 2400)]) {
      tester.view.physicalSize = s;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Finder pillText(String key, String text) =>
        find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

    testWidgets('the Orders row: In kitchen while the round is live, Picked '
        'up once the server says it is over; edit chips', (tester) async {
      size(tester);
      final l10n = await _l10n();
      final store = InMemoryRecentOrdersStore();
      await store.persist(kDemoSyncScope.key, [
        PosRecentOrder.discovered(_snap(editCount: 1, ackPending: true)),
      ]);
      final container = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(store),
          orderSnapshotRepositoryProvider.overrideWithValue(
            DemoOrderSnapshotRepository(),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const Scaffold(body: RecentOrdersSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        pillText('order-status-#AR0001', l10n.posOrdersStatusInKitchen),
        findsOneWidget,
      );
      expect(
        pillText('order-status-#AR0001', l10n.posOrdersStatusPickedUp),
        findsNothing,
      );
      expect(find.byKey(const Key('order-edited-#AR0001')), findsOneWidget);
      expect(
        find.byKey(const Key('order-edit-kitchen-pending-#AR0001')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('order-edit-kitchen-confirmed-#AR0001')),
        findsNothing,
        reason: 'the list row never claims confirmed (D13)',
      );

      // The round is served: a NEWER snapshot (the widened sync stamp) clears
      // the flag and the pickup wording returns.
      await container
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots([
            _snap(
              activeRound: false,
              editCount: 1,
              syncAt: _now.add(const Duration(minutes: 1)),
            ),
          ]);
      await tester.pumpAndSettle();
      expect(
        pillText('order-status-#AR0001', l10n.posOrdersStatusPickedUp),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('order-edit-kitchen-pending-#AR0001')),
        findsNothing,
      );
    });

    testWidgets('the strip card reads In kitchen with the in-progress tint', (
      tester,
    ) async {
      size(tester);
      final l10n = await _l10n();
      final store = InMemoryRecentOrdersStore();
      await store.persist(kDemoSyncScope.key, [
        PosRecentOrder.discovered(_snap()),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posRecentOrdersStoreProvider.overrideWithValue(store),
            orderSnapshotRepositoryProvider.overrideWithValue(
              DemoOrderSnapshotRepository(),
            ),
            posSyncPollIntervalProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const Scaffold(body: OpenOrdersStrip()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const Key('open-strip-order-#AR0001'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.text(l10n.posOrdersStatusInKitchen),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.local_fire_department_outlined),
        ),
        findsOneWidget,
      );
      final material = tester.widget<Material>(
        find.ancestor(of: card, matching: find.byType(Material)).first,
      );
      final theme = Theme.of(tester.element(card));
      expect(material.color, RestoflowTone.warning.styleOf(theme).container);
    });

    group('the table recovery header', () {
      Future<void> pumpRecovery(
        WidgetTester tester, {
        required PosTableActiveOrder entry,
        required PosOrderSnapshot snapshot,
      }) async {
        size(tester, const Size(1000, 1800));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              runtimeConfigProvider.overrideWithValue(
                RuntimeConfig.test(isDemoMode: false),
              ),
              posSyncSessionProvider.overrideWithValue(
                const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
              ),
              posRecentOrdersStoreProvider.overrideWithValue(
                InMemoryRecentOrdersStore(),
              ),
              posSyncCursorStoreProvider.overrideWithValue(
                InMemorySyncCursorStore(),
              ),
              posSyncPollIntervalProvider.overrideWithValue(null),
              orderSnapshotRepositoryProvider.overrideWithValue(
                _ByIdRepo(snapshot),
              ),
              staffCapabilitiesProvider.overrideWith(
                (ref) async =>
                    PosStaffCapabilities.fromJson(const {}, role: 'manager'),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: Scaffold(
                body: TableOrderRecoverySheet(
                  table: DemoTable(
                    table: DiningTable(
                      tableId: 't1',
                      label: 'T1',
                      organizationId: 'o',
                      restaurantId: 'r',
                      branchId: 'b',
                    ),
                    status: TableStatusKind.occupied,
                    activeOrderCount: 1,
                    activeOrders: [entry],
                  ),
                  entry: entry,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      String summary(WidgetTester tester) => tester
          .widget<Text>(find.byKey(const Key('table-recovery-summary')))
          .data!;

      testWidgets('the exact by-id flag says In kitchen where the floor '
          'stand-in said nothing', (tester) async {
        final l10n = await _l10n();
        final e = _entry(kitchenWorkOpen: false);
        await pumpRecovery(
          tester,
          entry: e,
          snapshot: _snap(
            id: e.orderId,
            code: e.orderCode,
            orderType: 'dine_in',
          ),
        );
        expect(summary(tester), contains(l10n.ordersStatusInKitchen));
        expect(summary(tester), isNot(contains(l10n.ordersStatusServed)));
      });

      testWidgets('an explicit false from the snapshot beats the stand-in', (
        tester,
      ) async {
        final l10n = await _l10n();
        final e = _entry(kitchenWorkOpen: true);
        await pumpRecovery(
          tester,
          entry: e,
          snapshot: _snap(
            id: e.orderId,
            code: e.orderCode,
            orderType: 'dine_in',
            activeRound: false,
          ),
        );
        expect(summary(tester), contains(l10n.ordersStatusServed));
      });
    });

    group('the detail preview header', () {
      Future<void> pumpPreview(
        WidgetTester tester,
        OrderDetailRepository repo,
        PosRecentOrder order,
      ) async {
        size(tester);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              runtimeConfigProvider.overrideWithValue(
                RuntimeConfig.test(isDemoMode: false),
              ),
              orderDetailRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp(
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: Scaffold(
                body: OrderDetailPreview(order: order, actions: _noActions),
              ),
            ),
          ),
        );
      }

      const pill = 'order-status-preview-#AR0001';

      testWidgets('while loading, the snapshot flag alone reads In kitchen', (
        tester,
      ) async {
        final l10n = await _l10n();
        final repo = _GatedRepo();
        await pumpPreview(tester, repo, PosRecentOrder.discovered(_snap()));
        await tester.pump();
        expect(
          find.byKey(const Key('order-detail-preview-loading')),
          findsOneWidget,
        );
        expect(pillText(pill, l10n.posOrdersStatusInKitchen), findsOneWidget);
        repo.gate.complete(_detail(roundStatuses: ['preparing']));
        await tester.pumpAndSettle();
      });

      testWidgets('every active round ready reads Ready', (tester) async {
        final l10n = await _l10n();
        await pumpPreview(
          tester,
          _FixedRepo(_detail(roundStatuses: ['ready', 'served'])),
          PosRecentOrder.discovered(_snap()),
        );
        await tester.pumpAndSettle();
        expect(pillText(pill, l10n.posOrdersStatusReady), findsOneWidget);
      });

      testWidgets('a preparing round reads In kitchen', (tester) async {
        final l10n = await _l10n();
        await pumpPreview(
          tester,
          _FixedRepo(_detail(roundStatuses: ['ready', 'preparing'])),
          PosRecentOrder.discovered(_snap()),
        );
        await tester.pumpAndSettle();
        expect(pillText(pill, l10n.posOrdersStatusInKitchen), findsOneWidget);
      });

      testWidgets('the fresher detail wins over a stale snapshot flag; the '
          'edit chips come from the history', (tester) async {
        final l10n = await _l10n();
        await pumpPreview(
          tester,
          _FixedRepo(
            _detail(
              roundStatuses: ['served'],
              hasActiveRound: false,
              editCount: 1,
              edits: const [
                PosOrderDetailEdit(
                  orderEditId: 'e1',
                  editNumber: 1,
                  kitchenAckRequired: true,
                  kitchenAckAt: null,
                  kitchenAckPending: false,
                ),
              ],
            ),
          ),
          PosRecentOrder.discovered(_snap()),
        );
        await tester.pumpAndSettle();
        expect(pillText(pill, l10n.posOrdersStatusPickedUp), findsOneWidget);
        expect(
          find.byKey(const Key('order-edited-preview-#AR0001')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('order-edit-kitchen-confirmed-preview-#AR0001')),
          findsNothing,
          reason: 'no confirmation instant: never "confirmed"',
        );
      });

      testWidgets('Kitchen confirmed appears once every required edit is '
          'confirmed', (tester) async {
        await pumpPreview(
          tester,
          _FixedRepo(
            _detail(
              roundStatuses: const [],
              hasActiveRound: false,
              editCount: 2,
              edits: [
                const PosOrderDetailEdit(
                  orderEditId: 'e1',
                  editNumber: 1,
                  kitchenAckRequired: false,
                ),
                PosOrderDetailEdit(
                  orderEditId: 'e2',
                  editNumber: 2,
                  kitchenAckRequired: true,
                  kitchenAckAt: DateTime.utc(2026, 10, 8, 12),
                ),
              ],
            ),
          ),
          PosRecentOrder.discovered(_snap(ackPending: true, editCount: 1)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('order-edit-kitchen-confirmed-preview-#AR0001')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('order-edit-kitchen-pending-preview-#AR0001')),
          findsNothing,
          reason: 'the fresher history wins over the snapshot',
        );
      });
    });
  });
}

PosOrderDetail _detail({
  required List<String> roundStatuses,
  bool hasActiveRound = true,
  int editCount = 0,
  List<PosOrderDetailEdit>? edits = const [],
}) => PosOrderDetail(
  orderId: 'oid-AR0001',
  orderCode: '#AR0001',
  orderType: 'takeaway',
  status: 'served',
  revision: 3,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 4200,
  items: const [
    PosOrderDetailItem(
      name: 'Burger',
      quantity: 1,
      unitPriceMinor: 4200,
      lineDiscountMinor: 0,
      lineTotalMinor: 4200,
      modifiers: [],
    ),
  ],
  rounds: [
    for (var i = 0; i < roundStatuses.length; i++)
      PosOrderDetailRound(
        roundId: 'r-${i + 2}',
        roundNumber: i + 2,
        status: roundStatuses[i],
      ),
  ],
  hasActiveRound: hasActiveRound,
  editCount: editCount,
  edits: edits,
);

class _FixedRepo implements OrderDetailRepository {
  _FixedRepo(this.detail);
  final PosOrderDetail detail;
  @override
  Future<PosOrderDetail> fetch(String orderId) async => detail;
}

class _GatedRepo implements OrderDetailRepository {
  final Completer<PosOrderDetail> gate = Completer<PosOrderDetail>();
  @override
  Future<PosOrderDetail> fetch(String orderId) => gate.future;
}

class _ByIdRepo implements OrderSnapshotRepository {
  _ByIdRepo(this.snapshot);
  final PosOrderSnapshot snapshot;

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;

  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async =>
      PosSnapshotPage(
        orders: [if (orderIds.contains(snapshot.orderId)) snapshot],
        hasMore: false,
      );
}
