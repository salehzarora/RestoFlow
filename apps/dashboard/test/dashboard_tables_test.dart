import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminPermissionDenied, AdminResult, AdminScope, AdminValidation;
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

/// An always-empty repository for the honest empty-state test (no fake data).
class _EmptyTablesRepo implements TablesAdminRepository {
  @override
  Future<AdminResult<List<DashboardTable>>> load() async =>
      const Success(<DashboardTable>[]);

  @override
  Future<AdminResult<void>> upsertTable({
    String? id,
    required String label,
    int? seats,
    String? area,
    required bool isActive,
  }) async => const Success(null);

  @override
  Future<AdminResult<void>> setStatus(
    String id,
    DiningTableStatus status,
  ) async => const Success(null);

  @override
  Future<AdminResult<void>> deleteTable(String id) async => const Success(null);
}

/// A repository returning a FIXED table list (for presentation tests).
class _StaticTablesRepo implements TablesAdminRepository {
  _StaticTablesRepo(this.tables);
  final List<DashboardTable> tables;
  @override
  Future<AdminResult<List<DashboardTable>>> load() async => Success(tables);
  @override
  Future<AdminResult<void>> upsertTable({
    String? id,
    required String label,
    int? seats,
    String? area,
    required bool isActive,
  }) async => const Success(null);
  @override
  Future<AdminResult<void>> setStatus(
    String id,
    DiningTableStatus status,
  ) async => const Success(null);
  @override
  Future<AdminResult<void>> deleteTable(String id) async => const Success(null);
}

AdminScope get _scope => AdminScope.demo;

final RegExp _uuidShape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

Map<String, dynamic> _listOk() => {
  'ok': true,
  'entity': 'table',
  'tables': [
    {
      'id': 't-1',
      'label': 'T1',
      'seats': 4,
      'area': 'Main hall',
      'status': 'available',
      'branch_id': 'b-1',
      'is_active': true,
    },
    {
      'id': 't-2',
      'label': 'T2',
      'seats': null,
      'area': null,
      'status': 'out_of_service',
      'branch_id': 'b-1',
      'is_active': false,
    },
  ],
};

void main() {
  group('withDashboardGroupAggregation (A4)', () {
    DashboardTable t(
      String id,
      String label, {
      DiningTableStatus status = DiningTableStatus.available,
      String effective = 'available',
      int active = 0,
      String? group,
    }) => DashboardTable(
      id: id,
      label: label,
      status: status,
      isActive: true,
      branchId: 'b',
      activeOrderCount: active,
      effectiveState: effective,
      groupId: group,
    );

    test('7. a linked group shows ONE coherent effective state + count', () {
      final out = withDashboardGroupAggregation([
        t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
        t('t2', 'T2', effective: 'available', active: 0, group: 'g1'),
        t('t3', 'T3', effective: 'available', active: 0), // ungrouped control
      ]);
      final t1 = out.firstWhere((x) => x.id == 't1');
      final t2 = out.firstWhere((x) => x.id == 't2');
      final t3 = out.firstWhere((x) => x.id == 't3');
      // Both grouped members read the group-wide truth: Occupied, count 1.
      expect(t1.effectiveState, 'occupied');
      expect(t2.effectiveState, 'occupied');
      expect(t1.activeOrderCount, 1);
      expect(t2.activeOrderCount, 1);
      // The ungrouped table is untouched.
      expect(t3.effectiveState, 'available');
    });

    test('out-of-service member propagates across the group', () {
      final out = withDashboardGroupAggregation([
        t('t1', 'T1', effective: 'out_of_service', group: 'g1'),
        t('t2', 'T2', effective: 'available', group: 'g1'),
      ]);
      expect(out.every((x) => x.effectiveState == 'out_of_service'), isTrue);
    });

    // Finding 4: a duplicate physical-table row must not double the group count.
    test('9/10. a duplicate physical row does not double the group count', () {
      final out = withDashboardGroupAggregation([
        t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
        t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'), // dup
        t('t2', 'T2', effective: 'available', active: 0, group: 'g1'),
      ]);
      // Every grouped tile shows the deduplicated group truth: Occupied, count 1.
      for (final x in out) {
        expect(x.effectiveState, 'occupied');
        expect(x.activeOrderCount, 1); // never 2
      }
    });
  });

  group('SupabaseTablesRepository', () {
    test('load parses the tables list (inactive included)', () async {
      final t = _FakeTransport((fn, p) => _listOk());
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final result = await repo.load();
      final tables = result.fold((s) => s, (f) => fail('expected success'));
      expect(t.calls.single.$1, 'list_tables');
      expect(t.calls.single.$2['p_organization_id'], _scope.organizationId);
      expect(tables, hasLength(2));
      expect(tables.first.label, 'T1');
      expect(tables.first.seats, 4);
      expect(tables.first.area, 'Main hall');
      expect(tables.first.status, DiningTableStatus.available);
      expect(tables.first.isActive, isTrue);
      expect(tables.first.branchId, 'b-1');
      // The inactive, seat-less, area-less row still parses (honest listing).
      expect(tables.last.seats, isNull);
      expect(tables.last.area, isNull);
      expect(tables.last.status, DiningTableStatus.outOfService);
      expect(tables.last.isActive, isFalse);
    });

    test('PILOT-OPERATIONS-CORRECTIONS-001: load parses effective_state + '
        'group_id', () async {
      final t = _FakeTransport(
        (fn, p) => {
          'ok': true,
          'tables': [
            {
              'id': 't-1',
              'label': 'T1',
              'status': 'available',
              'is_active': true,
              'branch_id': 'b-1',
              'active_order_count': 1,
              'effective_state': 'occupied',
              'group_id': 'g-1',
            },
          ],
        },
      );
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final tables = (await repo.load()).fold((s) => s, (f) => fail('$f'));
      expect(tables.single.effectiveState, 'occupied');
      expect(tables.single.groupId, 'g-1');
      expect(tables.single.isGrouped, isTrue);
    });

    test('upsert sends the contract params (p_label/p_seats/p_area/'
        'p_is_active + a uuid request id)', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': true, 'id': 't-9', 'action': 'created'},
      );
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final result = await repo.upsertTable(
        label: 'Window 2',
        seats: 4,
        area: 'Terrace',
        isActive: true,
      );
      expect(result.isSuccess, isTrue);
      expect(t.calls.single.$1, 'upsert_table');
      final params = t.calls.single.$2;
      expect(params['p_id'], isNull);
      expect(params['p_label'], 'Window 2');
      expect(params['p_seats'], 4);
      expect(params['p_area'], 'Terrace');
      expect(params['p_is_active'], true);
      expect(params['p_organization_id'], _scope.organizationId);
      expect(params['p_restaurant_id'], _scope.restaurantId);
      expect(params['p_branch_id'], _scope.branchId);
      expect(params['p_client_request_id'], matches(_uuidShape));
    });

    test('setStatus sends p_table_id + the wire status', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': true, 'id': 't-1', 'entity': 'table'},
      );
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final result = await repo.setStatus('t-1', DiningTableStatus.occupied);
      expect(result.isSuccess, isTrue);
      expect(t.calls.single.$1, 'set_table_status');
      final params = t.calls.single.$2;
      expect(params['p_table_id'], 't-1');
      expect(params['p_status'], 'occupied');
      expect(params['p_organization_id'], _scope.organizationId);
      expect(params['p_client_request_id'], matches(_uuidShape));
    });

    test('permission_denied maps to a typed failure', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': false, 'error': 'permission_denied'},
      );
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final result = await repo.load();
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminPermissionDenied>()),
      );
    });

    test('an org-wide (branch-less) scope fails closed on writes', () async {
      final t = _FakeTransport((fn, p) => fail('no backend call'));
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: AdminScope(
          organizationId: 'o',
          organizationName: 'Org',
          restaurantId: null,
          restaurantName: null,
          branchId: null,
          branchName: null,
          currencyCode: 'USD',
          actingRole: AdminScope.demo.actingRole,
        ),
        currentUserId: () => 'u',
      );
      final result = await repo.deleteTable('t-1');
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminValidation>()),
      );
      expect(t.calls, isEmpty);
    });
  });

  group('TablesScreen', () {
    Future<void> pump(WidgetTester tester, TablesAdminRepository repo) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(body: TablesScreen(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the seeded tables with honest status pills', (
      tester,
    ) async {
      await pump(tester, InMemoryTablesStore());
      // Seed labels across the two areas.
      expect(find.text('T1'), findsOneWidget);
      expect(find.text('T2'), findsOneWidget);
      expect(find.text('P1'), findsOneWidget);
      // The seeded statuses: one occupied, one out of service, one inactive.
      expect(find.text('Occupied'), findsOneWidget);
      expect(find.text('Out of service'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Available'), findsNWidgets(4));
    });

    testWidgets('adds a table through the dialog', (tester) async {
      final store = InMemoryTablesStore();
      await pump(tester, store);
      await tester.tap(find.text('Add table'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Table name / number'),
        'T9',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Seats'), '4');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final tables = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final saved = tables.singleWhere((t) => t.label == 'T9');
      expect(saved.seats, 4);
      expect(saved.status, DiningTableStatus.available);
      expect(find.text('T9'), findsOneWidget);
    });

    testWidgets('a positive seat count is required when given', (tester) async {
      await pump(tester, InMemoryTablesStore());
      await tester.tap(find.text('Add table'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Table name / number'),
        'T9',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Seats'), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Seats must be a positive number'), findsOneWidget);
    });

    testWidgets('sets a table status through the status menu', (tester) async {
      final store = InMemoryTablesStore();
      await pump(tester, store);
      // No seed table is reserved, so the menu item text is unambiguous.
      expect(find.text('Reserved'), findsNothing);
      await tester.tap(find.text('Set status').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reserved'));
      await tester.pumpAndSettle();

      final tables = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      // The first card is the first seeded table (T1).
      expect(
        tables.singleWhere((t) => t.label == 'T1').status,
        DiningTableStatus.reserved,
      );
      expect(find.text('Reserved'), findsOneWidget);
    });

    testWidgets('removes a table after the confirm dialog', (tester) async {
      final store = InMemoryTablesStore();
      await pump(tester, store);
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Remove this table? Existing orders keep their table reference.',
        ),
        findsOneWidget,
      );
      // The FilledButton in the dialog confirms the removal.
      await tester.tap(find.widgetWithText(FilledButton, 'Remove table'));
      await tester.pumpAndSettle();

      final tables = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(tables.any((t) => t.label == 'T1'), isFalse);
      expect(find.text('T1'), findsNothing);
    });

    testWidgets('the empty state is honest (no fake tables)', (tester) async {
      await pump(tester, _EmptyTablesRepo());
      expect(find.text('No tables yet'), findsOneWidget);
      expect(
        find.text(
          'Add your first table — the POS dine-in flow needs at '
          'least one.',
        ),
        findsOneWidget,
      );
      // No fabricated rows anywhere.
      expect(find.text('T1'), findsNothing);
      expect(find.byType(Card), findsNothing);
      // The empty state offers the add affordance (header + panel).
      expect(find.text('Add table'), findsNWidgets(2));
    });
  });

  group('DashboardShell navigation', () {
    testWidgets('the Tables nav item exists and opens the demo TablesScreen', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // A tall, wide surface so the side rail + the cards are fully laid out.
      tester.view.physicalSize = const Size(1300, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const ProviderScope(child: DashboardApp(demoMode: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.dashboardNavTables), findsWidgets);
      expect(find.byType(TablesScreen), findsNothing);
      await tester.tap(find.text(l10n.dashboardNavTables).first);
      await tester.pumpAndSettle();
      expect(find.byType(TablesScreen), findsOneWidget);
      // Demo mode keeps its honest demo banner + the seeded demo tables.
      expect(find.text(l10n.adminDemoBanner), findsOneWidget);
      expect(find.text('T1'), findsOneWidget);
    });

    testWidgets('PILOT-OPERATIONS-CORRECTIONS-001: linked group + effective '
        'state shown read-only', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: TablesScreen(
              repository: _StaticTablesRepo(const [
                DashboardTable(
                  id: 't-1',
                  label: 'T1',
                  status: DiningTableStatus.available, // manual
                  isActive: true,
                  branchId: 'b',
                  activeOrderCount: 1,
                  effectiveState: 'occupied', // differs -> shown
                  groupId: 'g-1',
                ),
                DashboardTable(
                  id: 't-2',
                  label: 'T2',
                  status: DiningTableStatus.available,
                  isActive: true,
                  branchId: 'b',
                  groupId: 'g-1',
                ),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The combined group label appears on BOTH grouped tiles (read-only; no
      // link/unlink control on the Dashboard).
      expect(find.text('${l10n.tablesLinked}: T1 + T2'), findsNWidgets(2));
      expect(find.byKey(const Key('table-linked-t-1')), findsOneWidget);
      // A4: the group-wide effective state (Occupied) is now surfaced on BOTH
      // members — t-2 is manually Available but the LINKED GROUP is occupied, so it
      // must not read as free. This is the aggregation fix: one coherent group truth.
      expect(
        find.textContaining(
          '${l10n.tablesEffective}: ${l10n.tablesStatusOccupied}',
        ),
        findsNWidgets(2),
      );
    });
  });
}
