import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show posHasKitchenNativePrinterProvider;
import 'package:restoflow_pos/src/state/kitchen_finish_controller.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_setup_controller.dart'
    show tablesProvider, tablesRepositoryProvider;
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart'
    show posRecentOrdersStoreProvider;
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// PRINTER-ONLY-CLOSE-ALL-ROUNDS-AND-RELEASE-TABLE-008 — the CLIENT half.
///
/// The authoritative work is the server's: completing the order closes every
/// service round, and table occupancy is DERIVED from live dine-in orders in
/// (submitted..served), so the completion IS the release — the POS never writes
/// a table.
///
/// What the CLIENT must do is stop showing the stale answer. `tablesProvider`
/// is the one floor read (picker, floor view, table-operations sheet). Nothing
/// invalidated it after a bulk finish, so a mounted floor view kept the table
/// looking occupied until something else happened to rebuild it — exactly the
/// "table still occupied" symptom, with the release already committed.
///
/// These drive the REAL button through the REAL controller.
class _RecordingRepo implements KitchenFinishRepository {
  _RecordingRepo({this.failComplete = false});

  final bool failComplete;
  final List<String> completed = [];

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
    required String batchRunId,
    required Future<String?> Function(String orderId) refreshStatus,
  }) async => KitchenFinishResult(orderId, KitchenFinishStatus.finished);

  @override
  Future<KitchenFinishResult> completeServedOrder({
    required String orderId,
    required String localOperationId,
  }) async {
    completed.add(orderId);
    return failComplete
        ? KitchenFinishResult(
            orderId,
            KitchenFinishStatus.failed,
            error: 'rounds_not_served',
          )
        : KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }
}

/// Counts how many times the floor read is actually performed.
class _CountingTables implements TablesRepository {
  int loads = 0;

  @override
  Future<List<DemoTable>> loadTables() async {
    loads++;
    return const <DemoTable>[];
  }
}

class _StubAutoKitchen extends PosAutoPrintKitchenTicketController {
  _StubAutoKitchen(this._on);
  final bool _on;
  @override
  Future<bool?> build() async => _on;
}

const _finishKey = Key('finish-all-kitchen-orders-button');

const _scope = PosSyncScope(
  organizationId: 'org1',
  restaurantId: 'r1',
  branchId: 'branch-A',
  deviceId: 'dev1',
);

final DateTime _verifiedAt = DateTime.utc(2026, 8, 1, 9);
final _printerOnly = KitchenModePrinterOnlyWithRevision(
  revision: 4,
  verifiedAt: _verifiedAt,
);

PosRecentOrder _servedPaidDineIn(String orderId) => PosRecentOrder.discovered(
  PosOrderSnapshot(
    orderId: orderId,
    orderCode: '#O00${orderId.hashCode.abs() % 1000}',
    revision: 3,
    status: 'served',
    settlement: PosSettlement.paid,
    subtotalMinor: 12000,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 12000,
    createdAt: DateTime.utc(2026, 8, 1, 10),
    updatedAt: DateTime.utc(2026, 8, 1, 10),
    syncAt: DateTime.utc(2026, 8, 1, 10),
    orderType: 'dine_in',
    tableLabel: 'T2',
    currencyCode: 'ILS',
  ),
);

class _Host extends ConsumerStatefulWidget {
  const _Host();
  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org1',
              branchId: 'branch-A',
              restaurantId: 'r1',
              deviceId: 'dev1',
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) => const RecentOrdersSheet();
}

/// Keeps the floor read MOUNTED, which is the case that actually goes stale.
class _FloorWatcher extends ConsumerWidget {
  const _FloorWatcher();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tablesProvider);
    return const SizedBox.shrink();
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required KitchenFinishRepository repo,
  required _CountingTables tables,
  List<PosRecentOrder> orders = const [],
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = InMemoryRecentOrdersStore();
  if (orders.isNotEmpty) await store.persist(_scope.key, orders);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
        ),
        posRecentOrdersStoreProvider.overrideWithValue(store),
        posSyncCursorStoreProvider.overrideWithValue(InMemorySyncCursorStore()),
        posSyncPollIntervalProvider.overrideWithValue(null),
        orderSnapshotRepositoryProvider.overrideWithValue(
          DemoOrderSnapshotRepository(),
        ),
        posHasKitchenNativePrinterProvider.overrideWithValue(true),
        posAutoPrintKitchenTicketProvider.overrideWith(
          () => _StubAutoKitchen(true),
        ),
        staffCapabilitiesProvider.overrideWith(
          (ref) async =>
              PosStaffCapabilities.fromJson(const {}, role: 'manager'),
        ),
        kitchenFinishRepositoryProvider.overrideWithValue(repo),
        posVerifiedKitchenModeProvider.overrideWithValue(_printerOnly),
        tablesRepositoryProvider.overrideWithValue(tables),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(
          body: Column(
            children: [
              _FloorWatcher(),
              Expanded(child: _Host()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  await tester.tap(find.byKey(_finishKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posFinishAllConfirmAction));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('T1 a successful bulk finish REFRESHES the floor read, so a '
      'released table stops looking occupied', (tester) async {
    final repo = _RecordingRepo();
    final tables = _CountingTables();
    await _pump(
      tester,
      repo: repo,
      tables: tables,
      orders: [_servedPaidDineIn('o-dinein')],
    );
    final before = tables.loads;
    expect(before, greaterThan(0), reason: 'the floor read is mounted');

    await _confirm(tester);

    expect(
      repo.completed,
      ['o-dinein'],
      reason: 'the order was completed server-side (that IS the table release)',
    );
    expect(
      tables.loads,
      greaterThan(before),
      reason:
          'occupancy is derived from the order, so once it completes the floor '
          'read must be re-run - otherwise the table keeps LOOKING occupied '
          'while the release is already committed',
    );
  });

  testWidgets('T2 a bulk finish that completed NOTHING does not churn the '
      'floor read', (tester) async {
    final repo = _RecordingRepo();
    final tables = _CountingTables();
    await _pump(tester, repo: repo, tables: tables);
    final before = tables.loads;

    await _confirm(tester);

    expect(repo.completed, isEmpty);
    expect(
      tables.loads,
      before,
      reason: 'nothing was released, so there is nothing to re-read',
    );
  });

  testWidgets('T3 a REFUSED completion does not refresh the floor - the table '
      'is still occupied and must keep looking occupied', (tester) async {
    final repo = _RecordingRepo(failComplete: true);
    final tables = _CountingTables();
    await _pump(
      tester,
      repo: repo,
      tables: tables,
      orders: [_servedPaidDineIn('o-refused')],
    );
    final before = tables.loads;

    await _confirm(tester);

    expect(repo.completed, ['o-refused'], reason: 'it was attempted');
    expect(
      tables.loads,
      before,
      reason:
          'the server refused, the order is still active and the table is still '
          'occupied - re-reading would only redraw the same truth, and claiming '
          'a release here would be the UI-only hiding this ticket forbids',
    );
  });
}
