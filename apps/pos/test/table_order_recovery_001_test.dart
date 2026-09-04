// STALE-TABLE-ORDER-RECOVERY-001 — an occupied table must always expose a
// path to IDENTIFY and OPEN its live orders, and the recovery it offers is the
// canonical one (the shared OrderActionRow policy), never a client-side state
// change. Occupancy on the client is whatever the server derived; a stale age
// or a manual "available" never fakes a free table.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart'
    show KitchenFinishResult;
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/ids.dart' show ClientIdGenerator;
import 'package:restoflow_pos/src/data/payment_repository.dart'
    show PaymentException, RealPaymentRepository, isNoOpenShiftRefusal;
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show posHasKitchenNativePrinterProvider;
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart'
    show tablesProvider, tablesSnapshotProvider;
import 'package:restoflow_pos/src/state/pos_order_complete_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart'
    show posRecentOrdersStoreProvider;
import 'package:restoflow_pos/src/widgets/cancel_order_sheet.dart';
import 'package:restoflow_pos/src/widgets/table_operations_sheet.dart';
import 'package:restoflow_pos/src/widgets/table_order_recovery_sheet.dart';
import 'support/fixed_pos_clock.dart';

final DateTime _now = DateTime.utc(2026, 9, 4, 12, 0);
const String _id = '298e598d-9709-4807-b46a-9be2758dd505';
const String _code = '#8DD505';

PosTableActiveOrder _entry({
  String status = 'submitted',
  Duration age = const Duration(hours: 53),
  String payment = 'unpaid',
  String? shift,
}) => PosTableActiveOrder(
  orderId: _id,
  orderCode: _code,
  status: status,
  createdAt: _now.subtract(age),
  orderType: 'dine_in',
  revision: 1,
  paymentStatus: payment,
  shiftStatus: shift,
  kitchenWorkOpen: false,
);

DemoTable _table({
  int active = 1,
  List<PosTableActiveOrder> orders = const <PosTableActiveOrder>[],
  String manual = 'available',
}) => DemoTable(
  table: DiningTable(
    tableId: 't1',
    label: 'T1',
    organizationId: 'o',
    restaurantId: 'r',
    branchId: 'b',
  ),
  status: active > 0 ? TableStatusKind.occupied : TableStatusKind.available,
  manualStatus: manual,
  effectiveState: active > 0 ? 'occupied' : 'available',
  activeOrderCount: active,
  activeOrders: orders,
);

PosOrderSnapshot _snapshot(
  PosTableActiveOrder e, {
  PosSettlement settlement = PosSettlement.unpaid,
  String? status,
}) => PosOrderSnapshot(
  orderId: e.orderId,
  orderCode: e.orderCode,
  revision: 1,
  status: status ?? e.status,
  settlement: settlement,
  subtotalMinor: 23200,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 23200,
  createdAt: e.createdAt,
  updatedAt: e.createdAt,
  syncAt: _now,
  orderType: 'dine_in',
  tableLabel: 'T1',
  currencyCode: 'ILS',
);

/// A by-id snapshot source that can be told to fail (offline) and records how
/// many by-id reads the sheet made.
class _SnapRepo implements OrderSnapshotRepository {
  _SnapRepo({this.snapshot, this.fail = false});
  PosOrderSnapshot? snapshot;
  bool fail;
  int byIdCalls = 0;
  List<String>? lastIds;

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
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async {
    byIdCalls++;
    lastIds = orderIds;
    if (fail) {
      throw const PosSnapshotException(PosSnapshotFailure.transport);
    }
    final s = snapshot;
    return PosSnapshotPage(
      orders: <PosOrderSnapshot>[
        if (s != null && orderIds.contains(s.orderId)) s,
      ],
      hasMore: false,
    );
  }
}

class _FixedId implements ClientIdGenerator {
  @override
  String newId() => 'op-pay-1';
}

class _OnKitchenPref extends PosAutoPrintKitchenTicketController {
  @override
  Future<bool?> build() async => true;
}

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.handler);
  final Object? Function(String fn, Map<String, dynamic> params) handler;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async =>
      handler(function, args);
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// A no-op printer-only Complete (the real one drives the sync pipeline).
class _FakeComplete extends PosOrderCompleteController {
  static int calls = 0;
  @override
  Future<KitchenFinishResult?> complete(String orderId) async {
    calls++;
    return null;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required DemoTable table,
  required _SnapRepo repo,
  String role = 'manager',
  KitchenModeResult? mode,
  List<Override> extra = const <Override>[],
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
        posSyncCursorStoreProvider.overrideWithValue(InMemorySyncCursorStore()),
        posSyncPollIntervalProvider.overrideWithValue(null),
        pinnedPosSyncClock(_now),
        orderSnapshotRepositoryProvider.overrideWithValue(repo),
        posHasKitchenNativePrinterProvider.overrideWithValue(true),
        posAutoPrintKitchenTicketProvider.overrideWith(_OnKitchenPref.new),
        staffCapabilitiesProvider.overrideWith(
          (ref) async => PosStaffCapabilities.fromJson(const {}, role: role),
        ),
        posVerifiedKitchenModeProvider.overrideWithValue(mode),
        ...extra,
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: TableOperationsSheet(table: table, allTables: [table]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('occupied table → open orders → canonical recovery', () {
    testWidgets(
      'an occupied table LISTS its open order (code · status · age · payment) and exposes Open',
      (tester) async {
        final l10n = await _en();
        final e = _entry();
        final repo = _SnapRepo(snapshot: _snapshot(e));
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: repo,
        );

        expect(
          find.byKey(const Key('table-ops-open-orders-heading')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('table-ops-open-order-$_code')),
          findsOneWidget,
        );
        final row = tester.widget<ListTile>(
          find.byKey(const Key('table-ops-open-order-$_code')),
        );
        final subtitle = (row.subtitle! as Text).data!;
        expect(subtitle, contains(l10n.ordersStatusSubmitted));
        expect(subtitle, contains(l10n.posTableOrderAgeDays(2, 5))); // 53 h
        expect(subtitle, contains(l10n.posTableOrderUnpaid));
        expect(subtitle, isNot(contains(l10n.posTableOrderShiftClosed)));

        // Open → the recovery sheet fetches BY ID (window bypass) and renders
        // the shared action row: a manager can CANCEL an unpaid order.
        await tester.tap(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('table-recovery-title')), findsOneWidget);
        expect(repo.byIdCalls, 1);
        expect(repo.lastIds, [_id]);
        expect(
          find.byKey(const Key('table-recovery-pay-$_code')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('table-recovery-cancel-$_code')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('table-recovery-no-actions')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('table-recovery-unavailable')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a closed originating shift is stated on the row (informational, never a block)',
      (tester) async {
        final l10n = await _en();
        final e = _entry(status: 'served', shift: 'reconciled');
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: _SnapRepo(snapshot: _snapshot(e)),
        );
        final row = tester.widget<ListTile>(
          find.byKey(const Key('table-ops-open-order-$_code')),
        );
        expect(
          (row.subtitle! as Text).data!,
          contains(l10n.posTableOrderShiftClosed),
        );
      },
    );

    testWidgets(
      'STALE + manual "available" never fakes a free table: the effective state stays occupied',
      (tester) async {
        final l10n = await _en();
        final e = _entry(age: const Duration(days: 3, hours: 4));
        await _pump(
          tester,
          table: _table(orders: [e], manual: 'available'),
          repo: _SnapRepo(snapshot: _snapshot(e)),
        );
        // The stale age is shown as information...
        final row = tester.widget<ListTile>(
          find.byKey(const Key('table-ops-open-order-$_code')),
        );
        expect(
          (row.subtitle! as Text).data!,
          contains(l10n.posTableOrderAgeDays(3, 4)),
        );
        // ...while the EFFECTIVE state (server-derived) is still occupied and
        // the manual "Mark available" action is merely a hint, not a release.
        expect(
          find.descendant(
            of: find.byKey(const Key('table-ops-effective')),
            matching: find.text(l10n.posTableStateOccupied),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('table-ops-available')), findsOneWidget);
        expect(
          find.byKey(const Key('table-ops-open-orders-heading')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a TERMINAL by-id result (voided or paid+completed elsewhere meanwhile) offers NO fake action and states the refusal',
      (tester) async {
        final l10n = await _en();
        final e = _entry(); // the floor still listed it...
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: _SnapRepo(
            snapshot: _snapshot(e, status: 'voided'),
          ), // ...but it is terminal now
        );
        await tester.tap(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('table-recovery-no-actions')),
          findsOneWidget,
        );
        expect(find.text(l10n.posTableRecoveryAlreadyClosed), findsOneWidget);
        expect(
          find.byKey(const Key('table-recovery-cancel-$_code')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('table-recovery-pay-$_code')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a KNOWN-paid (served, not completed) order is never offered Cancel or Pay; the refusal names completion',
      (tester) async {
        final l10n = await _en();
        final e = _entry(status: 'served', payment: 'paid');
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: _SnapRepo(
            snapshot: _snapshot(e, settlement: PosSettlement.paid),
          ),
        );
        await tester.tap(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('table-recovery-cancel-$_code')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('table-recovery-pay-$_code')),
          findsNothing,
        );
        expect(
          find.text(l10n.posTableRecoveryPaidNeedsCompletion),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'closing the cancel sheet re-reads the order by id (a void elsewhere reads terminal)',
      (tester) async {
        final e = _entry();
        final repo = _SnapRepo(snapshot: _snapshot(e));
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: repo,
        );
        await tester.tap(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
        );
        await tester.pumpAndSettle();
        expect(repo.byIdCalls, 1);
        await tester.tap(find.byKey(const Key('table-recovery-cancel-$_code')));
        await tester.pumpAndSettle();
        // the order was voided meanwhile: the next by-id read is terminal
        repo.snapshot = _snapshot(e, status: 'voided');
        // close the cancel sheet (a modal bottom sheet) without confirming
        Navigator.of(tester.element(find.byType(CancelOrderSheet))).pop();
        await tester.pumpAndSettle();
        expect(repo.byIdCalls, 2);
        expect(
          find.byKey(const Key('table-recovery-cancel-$_code')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('table-recovery-no-actions')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the operations sheet re-resolves its table from the floor read model (a freed table stops listing orders)',
      (tester) async {
        final e = _entry();
        final stale = _table(orders: [e]);
        final fresh = _table(active: 0);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              runtimeConfigProvider.overrideWithValue(
                RuntimeConfig.test(isDemoMode: false),
              ),
              pinnedPosSyncClock(_now),
              tablesProvider.overrideWith((ref) async => [fresh]),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: Scaffold(
                body: TableOperationsSheet(table: stale, allTables: [stale]),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('table-ops-open-orders-heading')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a failed by-id fetch is honest (unavailable + retry) and never synthesizes an order',
      (tester) async {
        final e = _entry();
        final repo = _SnapRepo(snapshot: _snapshot(e), fail: true);
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: repo,
        );
        await tester.tap(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('table-recovery-unavailable')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('table-recovery-cancel-$_code')),
          findsNothing,
        );

        // Back online: retry performs a NEW by-id read and the row appears.
        repo.fail = false;
        await tester.tap(find.byKey(const Key('table-recovery-retry')));
        await tester.pumpAndSettle();
        expect(repo.byIdCalls, 2);
        expect(
          find.byKey(const Key('table-recovery-unavailable')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('table-recovery-cancel-$_code')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a zero-total (nothing to pay) active order keeps its Cancel and is never called paid',
      (tester) async {
        final l10n = await _en();
        final e = _entry(payment: 'not_chargeable');
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: _SnapRepo(
            snapshot: _snapshot(e, settlement: PosSettlement.notChargeable),
          ),
        );
        await tester.tap(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('table-recovery-cancel-$_code')),
          findsOneWidget,
        );
        expect(
          find.text(l10n.posTableRecoveryPaidNeedsCompletion),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a PAID but not-yet-served order names the kitchen lifecycle as the exit',
      (tester) async {
        final l10n = await _en();
        final e = _entry(status: 'submitted', payment: 'paid');
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: _SnapRepo(
            snapshot: _snapshot(e, settlement: PosSettlement.paid),
          ),
        );
        await tester.tap(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('table-recovery-cancel-$_code')),
          findsNothing,
        );
        expect(
          find.text(l10n.posTableRecoveryPaidAwaitingKitchen),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'closing the cancel sheet re-fetches the FLOOR read model (the table frees as a consequence)',
      (tester) async {
        final e = _entry();
        final repo = _SnapRepo(snapshot: _snapshot(e));
        var snapshotFetches = 0;
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: repo,
          extra: [
            tablesSnapshotProvider.overrideWith((ref) async {
              snapshotFetches++;
              return const PosFloorSnapshot(tables: <DemoTable>[]);
            }),
          ],
        );
        await tester.tap(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
        );
        await tester.pumpAndSettle();
        final before = snapshotFetches;
        await tester.tap(find.byKey(const Key('table-recovery-cancel-$_code')));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(CancelOrderSheet))).pop();
        await tester.pumpAndSettle();
        expect(snapshotFetches, greaterThan(before));
      },
    );

    testWidgets(
      'printer-only Complete (served + paid) re-reads the order by id and refreshes the floor',
      (tester) async {
        final e = _entry(status: 'served', payment: 'paid');
        final repo = _SnapRepo(
          snapshot: _snapshot(e, settlement: PosSettlement.paid),
        );
        var snapshotFetches = 0;
        _FakeComplete.calls = 0;
        await _pump(
          tester,
          table: _table(orders: [e]),
          repo: repo,
          mode: KitchenModePrinterOnlyWithRevision(
            revision: 4,
            verifiedAt: _now,
          ),
          extra: [
            posOrderCompleteControllerProvider.overrideWith(_FakeComplete.new),
            tablesSnapshotProvider.overrideWith((ref) async {
              snapshotFetches++;
              return const PosFloorSnapshot(tables: <DemoTable>[]);
            }),
          ],
        );
        await tester.tap(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('table-recovery-complete-$_code')),
          findsOneWidget,
        );
        final before = snapshotFetches;
        // the server completed it meanwhile: the next by-id read is terminal
        repo.snapshot = _snapshot(
          e,
          settlement: PosSettlement.paid,
          status: 'completed',
        );
        await tester.tap(
          find.byKey(const Key('table-recovery-complete-$_code')),
        );
        await tester.pumpAndSettle();
        expect(_FakeComplete.calls, 1);
        expect(repo.byIdCalls, 2);
        expect(snapshotFetches, greaterThan(before));
        expect(
          find.byKey(const Key('table-recovery-complete-$_code')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('table-recovery-no-actions')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'without manage_table_operations the sheet is OPEN-ORDERS-ONLY: recovery entries stay, manual mutations are not built',
      (tester) async {
        final e = _entry();
        final t = _table(orders: [e]);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              runtimeConfigProvider.overrideWithValue(
                RuntimeConfig.test(isDemoMode: false),
              ),
              pinnedPosSyncClock(_now),
              tablesProvider.overrideWith((ref) async => [t]),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: Scaffold(
                body: TableOperationsSheet(
                  table: t,
                  allTables: [t],
                  canManage: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('table-ops-open-order-open-$_code')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('table-ops-available')), findsNothing);
        expect(find.byKey(const Key('table-ops-out-of-service')), findsNothing);
        expect(find.byKey(const Key('table-ops-link')), findsNothing);
      },
    );

    testWidgets('a free table shows no open-orders section', (tester) async {
      await _pump(tester, table: _table(active: 0), repo: _SnapRepo());
      expect(
        find.byKey(const Key('table-ops-open-orders-heading')),
        findsNothing,
      );
    });
  });

  group('floor payload → model (no fake client-side state)', () {
    test(
      'active_orders is parsed and the table state is the SERVER effective state',
      () async {
        final t = _FakeTransport(
          (fn, p) => {
            'ok': true,
            'tables': [
              {
                'id': 't1',
                'label': 'T1',
                'status': 'available', // manual hint
                'effective_state': 'occupied', // derived truth
                'active_order_count': 1,
                'active_orders': [
                  {
                    'order_id': _id,
                    'order_code': _code,
                    'status': 'submitted',
                    'order_type': 'dine_in',
                    'revision': 1,
                    'created_at': '2026-09-01T18:41:55Z',
                    'payment_status': 'unpaid',
                    'shift_status': null,
                    'kitchen_work_open': false,
                  },
                ],
              },
            ],
          },
        );
        final rows = await RealTablesRepository(
          t,
          const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
        ).loadTables();
        final t1 = rows.single;
        expect(t1.status, TableStatusKind.occupied);
        expect(t1.manualStatus, 'available');
        expect(t1.effectiveState, 'occupied');
        expect(t1.activeOrders, hasLength(1));
        final e = t1.activeOrders.single;
        expect(e.orderId, _id);
        expect(e.orderCode, _code);
        expect(e.createdAt, DateTime.utc(2026, 9, 1, 18, 41, 55));
        expect(e.isPaid, isFalse);
        expect(e.shiftStatus, isNull);
        expect(e.kitchenWorkOpen, isFalse);
        // copyWithGroupState (group projections) must not drop the list.
        final grouped = t1.copyWithGroupState(
          effectiveState: 'occupied',
          activeOrderCount: 1,
          status: TableStatusKind.occupied,
        );
        expect(grouped.activeOrders, hasLength(1));
      },
    );

    test('a linked-group member lists the orders occupying the GROUP', () {
      final e = _entry();
      final a = DemoTable(
        table: DiningTable(
          tableId: 'a',
          label: 'A',
          organizationId: 'o',
          restaurantId: 'r',
          branchId: 'b',
        ),
        status: TableStatusKind.occupied,
        effectiveState: 'occupied',
        activeOrderCount: 1,
        activeOrders: [e],
        groupId: 'g1',
      );
      final b = DemoTable(
        table: DiningTable(
          tableId: 'b',
          label: 'B',
          organizationId: 'o',
          restaurantId: 'r',
          branchId: 'b',
        ),
        status: TableStatusKind.available,
        effectiveState: 'available',
        groupId: 'g1',
      );
      final agg = withGroupAggregation([a, b]);
      final bAgg = agg.firstWhere((t) => t.tableId == 'b');
      expect(bAgg.activeOrderCount, 1); // the group-wide count...
      expect(bAgg.activeOrders.map((o) => o.orderId), [_id]); // ...WITH orders
    });

    test('listFromJson is tolerant but never fabricates', () {
      expect(PosTableActiveOrder.listFromJson(null), isEmpty);
      expect(PosTableActiveOrder.listFromJson('nope'), isEmpty);
      final parsed = PosTableActiveOrder.listFromJson([
        // identity missing → dropped
        {
          'order_code': '#X',
          'status': 'submitted',
          'created_at': '2026-09-01T00:00:00Z',
        },
        // bad timestamp → dropped
        {
          'order_id': 'a',
          'order_code': '#A',
          'status': 'submitted',
          'created_at': 'later',
        },
        // unknown payment token fails CLOSED to unpaid
        {
          'order_id': 'b',
          'order_code': '#B',
          'status': 'served',
          'created_at': '2026-09-01T00:00:00Z',
          'payment_status': 'maybe',
        },
        {
          'order_id': 'c',
          'order_code': '#C',
          'status': 'served',
          'created_at': '2026-09-01T00:00:00Z',
          'payment_status': 'not_chargeable',
          'shift_status': 'closed',
        },
      ]);
      expect(parsed.map((e) => e.orderId), ['b', 'c']);
      expect(parsed[0].paymentStatus, 'unpaid');
      expect(parsed[1].isNotChargeable, isTrue);
      expect(parsed[1].originatingShiftClosed, isTrue);
    });
  });

  group('entry + refusal plumbing', () {
    test(
      'an occupied table opens the operations sheet even without manage_table_operations',
      () {
        final occupied = _table(orders: [_entry()]);
        final free = _table(active: 0);
        expect(canOpenTableOperations(false, occupied), isTrue);
        expect(canOpenTableOperations(null, occupied), isTrue);
        expect(canOpenTableOperations(false, free), isFalse);
        expect(canOpenTableOperations(null, free), isFalse); // unknown != grant
        expect(canOpenTableOperations(true, free), isTrue);
      },
    );

    test(
      "the funnel's precondition_failed token becomes PaymentException.shiftRequired",
      () async {
        final t = _FakeTransport(
          (fn, p) => <String, Object?>{
            'ok': true,
            'results': <Object?>[
              <String, Object?>{
                'local_operation_id': 'op-pay-1',
                'operation_type': 'payment.create',
                'ok': false,
                'error': 'rejected',
                'sqlstate': '42501',
                'detail': 'precondition_failed',
                'status': 'rejected',
                'idempotency_replay': false,
              },
            ],
          },
        );
        final repo = RealPaymentRepository(
          t,
          const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
          _FixedId(),
        );
        await expectLater(
          () => repo.recordCashPayment(
            orderId: _id,
            orderNumber: _code,
            amountMinor: 23200,
            tenderedMinor: 23200,
            currencyCode: 'ILS',
          ),
          throwsA(
            isA<PaymentException>().having(
              (e) => e.shiftRequired,
              'shiftRequired',
              isTrue,
            ),
          ),
        );
      },
    );

    test('record_payment precondition refusals are recognized exactly', () {
      expect(
        isNoOpenShiftRefusal(
          const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: '42501',
            message:
                'record_payment: no open shift for this branch/device (precondition_failed)',
          ),
        ),
        isTrue,
      );
      expect(
        isNoOpenShiftRefusal(
          const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: '42501',
            message:
                'record_payment: no active cash drawer for the open shift (precondition_failed)',
          ),
        ),
        isTrue,
      );
      expect(
        isNoOpenShiftRefusal(
          const SyncTransportException(SyncTransportErrorKind.transient),
        ),
        isFalse,
      );
    });
  });

  group('labels', () {
    test('age is coarse and monotonic (min → h → d h)', () async {
      final l10n = await _en();
      expect(
        tableOrderAgeLabel(l10n, const Duration(minutes: 45)),
        l10n.posTableOrderAgeMinutes(45),
      );
      expect(
        tableOrderAgeLabel(l10n, const Duration(hours: 5, minutes: 59)),
        l10n.posTableOrderAgeHours(5),
      );
      expect(
        tableOrderAgeLabel(l10n, const Duration(days: 2, hours: 5)),
        l10n.posTableOrderAgeDays(2, 5),
      );
      expect(
        tableOrderAgeLabel(l10n, const Duration(minutes: -5)),
        l10n.posTableOrderAgeMinutes(0),
      );
    });

    test('payment + status words come from the server states', () async {
      final l10n = await _en();
      expect(
        tableOrderPaymentLabel(l10n, _entry(payment: 'paid')),
        l10n.posTableOrderPaid,
      );
      expect(
        tableOrderPaymentLabel(l10n, _entry(payment: 'not_chargeable')),
        l10n.posTableOrderNotChargeable,
      );
      expect(
        tableOrderStatusLabel(l10n, _entry(status: 'served')),
        l10n.ordersStatusServed,
      );
    });
  });
}
