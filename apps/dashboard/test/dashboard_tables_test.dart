import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualPreset;
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show
        AdminPermissionDenied,
        AdminResult,
        AdminScope,
        AdminTransient,
        AdminValidation;
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
  Future<AdminResult<TablesFloorSnapshot>> load() async => const Success(
    TablesFloorSnapshot(
      tables: <DashboardTable>[],
      sections: <DashboardTableSection>[],
    ),
  );

  @override
  Future<AdminResult<String>> upsertTable({
    String? id,
    required String label,
    int? seats,
    String? area,
    required bool isActive,
  }) async => Success(id ?? 'new-table');

  @override
  Future<AdminResult<void>> setStatus(
    String id,
    DiningTableStatus status,
  ) async => const Success(null);

  @override
  Future<AdminResult<void>> deleteTable(String id) async => const Success(null);

  @override
  Future<AdminResult<void>> upsertSection({
    String? id,
    required String name,
    required bool isActive,
  }) async => const Success(null);

  @override
  Future<AdminResult<void>> deleteSection(String id) async =>
      const Success(null);

  @override
  Future<AdminResult<void>> upsertFloorElement(
    DashboardFloorElement element,
  ) async => const Success(null);

  @override
  Future<AdminResult<void>> deleteFloorElement(String id) async =>
      const Success(null);

  @override
  Future<AdminResult<void>> setTableSection(
    String tableId,
    String? sectionId,
  ) async => const Success(null);

  @override
  Future<AdminResult<void>> setTablePosition(
    String tableId,
    int layoutX,
    int layoutY,
  ) async => const Success(null);

  @override
  Future<AdminResult<void>> reorderSections(List<String> ids) async =>
      const Success(null);

  @override
  Future<AdminResult<void>> setTableVisualPreset(
    String tableId,
    TableVisualPreset preset,
  ) async => const Success(null);

  @override
  Future<AdminResult<void>> setSectionFloorPreset(
    String sectionId,
    FloorPreset preset,
  ) async => const Success(null);
}

/// A repository returning a FIXED table list (for presentation tests).
class _StaticTablesRepo extends _EmptyTablesRepo {
  _StaticTablesRepo(this.tables);
  final List<DashboardTable> tables;
  @override
  Future<AdminResult<TablesFloorSnapshot>> load() async =>
      Success(TablesFloorSnapshot(tables: tables, sections: const []));
}

/// TABLE-FLOOR-LAYOUT-021: records every placement write so the arrange tests
/// can prove "one write, on drag END only".
class _RecordingStore extends InMemoryTablesStore {
  final List<(String, int, int)> positionWrites = [];

  @override
  Future<AdminResult<void>> setTablePosition(
    String tableId,
    int layoutX,
    int layoutY,
  ) {
    positionWrites.add((tableId, layoutX, layoutY));
    return super.setTablePosition(tableId, layoutX, layoutY);
  }
}

/// TABLE-FLOOR-LAYOUT-021: a store whose placement writes always fail, for the
/// optimistic-revert test.
class _FailingPositionStore extends InMemoryTablesStore {
  @override
  Future<AdminResult<void>> setTablePosition(
    String tableId,
    int layoutX,
    int layoutY,
  ) async => const Failure(AdminTransient());
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

    // Finding 5: the projected list has ONE tile per physical table id.
    test('Finding 5: input [t1, t1, t2] returns exactly 2 tiles', () {
      final out = withDashboardGroupAggregation([
        t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
        t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'), // dup
        t('t2', 'T2', effective: 'available', group: 'g1'),
      ]);
      expect(out.length, 2);
      expect(out.map((x) => x.id).toList(), ['t1', 't2']);
    });

    // Finding 6: an unknown effective state is preserved as unknown (never available).
    test(
      'Finding 6: available + unknown resolves to unknown for the group',
      () {
        final out = withDashboardGroupAggregation([
          t('t1', 'T1', effective: 'mystery', group: 'g1'),
          t('t2', 'T2', effective: 'available', group: 'g1'),
        ]);
        expect(out.every((x) => x.effectiveState == 'unknown'), isTrue);
      },
    );
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
      final snapshot = result.fold((s) => s, (f) => fail('expected success'));
      final tables = snapshot.tables;
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
      // A legacy envelope carries no sections catalog: empty, never an error.
      expect(snapshot.sections, isEmpty);
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
      final tables = (await repo.load()).fold(
        (s) => s.tables,
        (f) => fail('$f'),
      );
      expect(tables.single.effectiveState, 'occupied');
      expect(tables.single.groupId, 'g-1');
      expect(tables.single.isGrouped, isTrue);
    });

    test('TABLE-FLOOR-LAYOUT-021: load parses the sections catalog + the '
        'per-row section/placement keys', () async {
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
              'section_id': 's-1',
              'section_name': 'Main hall',
              'section_display_order': 0,
              'layout_x': 2500,
              'layout_y': 7500,
            },
            {
              'id': 't-2',
              'label': 'T2',
              'status': 'available',
              'is_active': true,
              'branch_id': 'b-1',
              'section_id': null,
              'section_name': null,
              'section_display_order': null,
              // A half placement must NEVER survive parsing (defensive
              // both-or-neither; the DB forbids it anyway).
              'layout_x': 9999,
              'layout_y': null,
            },
          ],
          'sections': [
            {
              'id': 's-1',
              'name': 'Main hall',
              'display_order': 0,
              'is_active': true,
              'branch_id': 'b-1',
            },
            {
              'id': 's-2',
              'name': 'Terrace',
              'display_order': 1,
              'is_active': false,
              'branch_id': 'b-1',
            },
          ],
        },
      );
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final snapshot = (await repo.load()).fold((s) => s, (f) => fail('$f'));
      expect(snapshot.sections, hasLength(2));
      expect(snapshot.sections.first.name, 'Main hall');
      expect(snapshot.sections.first.displayOrder, 0);
      expect(snapshot.sections.last.isActive, isFalse);
      final placed = snapshot.tables.first;
      expect(placed.sectionId, 's-1');
      expect(placed.sectionName, 'Main hall');
      expect(placed.sectionDisplayOrder, 0);
      expect(placed.layoutX, 2500);
      expect(placed.layoutY, 7500);
      expect(placed.isPlaced, isTrue);
      final legacy = snapshot.tables.last;
      expect(legacy.sectionId, isNull);
      expect(legacy.layoutX, isNull);
      expect(legacy.layoutY, isNull);
      expect(legacy.isPlaced, isFalse);
    });

    test('TABLE-FLOOR-LAYOUT-021: section + placement writes send the '
        'contract params', () async {
      final t = _FakeTransport((fn, p) => {'ok': true});
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      expect(
        (await repo.upsertSection(name: 'Garden', isActive: true)).isSuccess,
        isTrue,
      );
      expect((await repo.setTableSection('t-1', 's-1')).isSuccess, isTrue);
      expect((await repo.setTablePosition('t-1', 100, 9999)).isSuccess, isTrue);
      expect((await repo.deleteSection('s-1')).isSuccess, isTrue);
      expect((await repo.reorderSections(['s-2', 's-1'])).isSuccess, isTrue);
      expect(t.calls.map((c) => c.$1).toList(), [
        'upsert_table_section',
        'set_table_section',
        'set_table_layout_position',
        'soft_delete_table_section',
        'reorder_table_sections',
      ]);
      final up = t.calls[0].$2;
      expect(up['p_name'], 'Garden');
      expect(up['p_is_active'], true);
      expect(up['p_id'], isNull);
      expect(up['p_organization_id'], _scope.organizationId);
      expect(up['p_client_request_id'], matches(_uuidShape));
      final setSection = t.calls[1].$2;
      expect(setSection['p_table_id'], 't-1');
      expect(setSection['p_section_id'], 's-1');
      expect(setSection['p_client_request_id'], matches(_uuidShape));
      final position = t.calls[2].$2;
      expect(position['p_table_id'], 't-1');
      expect(position['p_layout_x'], 100);
      expect(position['p_layout_y'], 9999);
      expect(position['p_client_request_id'], matches(_uuidShape));
      final reorder = t.calls[4].$2;
      expect(reorder['p_ids'], ['s-2', 's-1']);
      // The reorder RPC is naturally idempotent — no request id by contract.
      expect(reorder.containsKey('p_client_request_id'), isFalse);
    });

    test('TABLE-FLOOR-LAYOUT-021: an out-of-range placement fails closed '
        'client-side (no backend call)', () async {
      final t = _FakeTransport((fn, p) => fail('no backend call'));
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: _scope,
        currentUserId: () => 'u',
      );
      final result = await repo.setTablePosition('t-1', 10001, 0);
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminValidation>()),
      );
      expect(t.calls, isEmpty);
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
      // Tall enough that the floor canvases AND the card grid are all laid
      // out and hittable (two ~855px canvases sit above the cards).
      tester.view.physicalSize = const Size(1400, 4600);
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
      // Every seeded table appears TWICE: its floor-map tile + its card.
      expect(find.text('T1'), findsNWidgets(2));
      expect(find.text('T2'), findsNWidgets(2));
      expect(find.text('P1'), findsNWidgets(2));
      // The seeded statuses: pills on the cards + footnotes on the tiles.
      expect(find.text('Occupied'), findsNWidgets(2));
      expect(find.text('Out of service'), findsNWidgets(2));
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Available'), findsNWidgets(8));
    });

    testWidgets('TABLE-FLOOR-LAYOUT-021: sections render as floor canvases '
        'with the saved placements', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await pump(tester, InMemoryTablesStore());
      // One white canvas per active section, in owner order.
      expect(
        find.byKey(const Key('floor-canvas-demo-section-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('floor-canvas-demo-section-2')),
        findsOneWidget,
      );
      // Section headers name the canvases exactly once.
      expect(find.text('Main hall'), findsOneWidget);
      expect(find.text('Terrace'), findsOneWidget);
      // Placed tiles exist for the placed seeds.
      expect(find.byKey(const Key('floor-table-demo-table-1')), findsOneWidget);
      expect(find.byKey(const Key('floor-table-demo-table-5')), findsOneWidget);
      // P3 (no section) sits in the clearly-labelled unassigned zone.
      expect(find.text(l10n.tablesUnassignedZone), findsOneWidget);
      expect(find.byKey(const Key('floor-table-demo-table-6')), findsOneWidget);
      // Outside arrange mode there are NO drag handles and no section admin.
      expect(find.byKey(const Key('floor-drag-demo-table-1')), findsNothing);
      expect(
        find.byKey(const Key('section-delete-demo-section-1')),
        findsNothing,
      );
    });

    testWidgets('TABLE-FLOOR-LAYOUT-021: an arrange drag saves ONE placement '
        'on drag END only', (tester) async {
      final store = _RecordingStore();
      await pump(tester, store);
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floor-drag-demo-table-1')), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('floor-drag-demo-table-1')),
        const Offset(120, 60),
      );
      await tester.pumpAndSettle();
      // Exactly ONE write — never one per pointer move.
      expect(store.positionWrites, hasLength(1));
      final (id, x, y) = store.positionWrites.single;
      expect(id, 'demo-table-1');
      // Moved right + down from the seed (1500, 2500), still in range.
      expect(x, greaterThan(1500));
      expect(y, greaterThan(2500));
      expect(x, inInclusiveRange(0, 10000));
      expect(y, inInclusiveRange(0, 10000));
      // The saved position round-trips into the store.
      final snapshot = (await store.load()).fold((s) => s, (f) => fail('$f'));
      final moved = snapshot.tables.singleWhere((t) => t.id == 'demo-table-1');
      expect((moved.layoutX, moved.layoutY), (x, y));
    });

    testWidgets('TABLE-FLOOR-LAYOUT-021: a failed placement write reverts '
        'the tile (optimistic + revert)', (tester) async {
      final store = _FailingPositionStore();
      await pump(tester, store);
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('floor-table-demo-table-1'));
      final before = tester.getTopLeft(tile);
      await tester.drag(
        find.byKey(const Key('floor-drag-demo-table-1')),
        const Offset(150, 80),
      );
      await tester.pumpAndSettle();
      // The failure is reported and the tile is back at its SAVED spot.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.getTopLeft(tile), before);
      final snapshot = (await store.load()).fold((s) => s, (f) => fail('$f'));
      final t1 = snapshot.tables.singleWhere((t) => t.id == 'demo-table-1');
      expect((t1.layoutX, t1.layoutY), (1500, 2500)); // untouched
    });

    testWidgets('TABLE-FLOOR-LAYOUT-021: assigning a section through the '
        'card chooser (no position invented)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final store = InMemoryTablesStore();
      await pump(tester, store);
      await tester.ensureVisible(
        find.byKey(const Key('table-set-section-demo-table-6')),
      );
      await tester.tap(find.byKey(const Key('table-set-section-demo-table-6')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-section-demo-section-1')));
      await tester.pumpAndSettle();
      final snapshot = (await store.load()).fold((s) => s, (f) => fail('$f'));
      final p3 = snapshot.tables.singleWhere((t) => t.label == 'P3');
      expect(p3.sectionId, 'demo-section-1');
      // Assignment NEVER invents coordinates — the table lands in the
      // section's not-placed strip until someone places it.
      expect(p3.layoutX, isNull);
      expect(p3.layoutY, isNull);
      expect(find.text(l10n.tablesNotPlaced), findsOneWidget);
    });

    testWidgets('TABLE-FLOOR-LAYOUT-021: Place on map uses the deterministic '
        'initial placement', (tester) async {
      final store = InMemoryTablesStore();
      await store.setTableSection('demo-table-6', 'demo-section-1');
      await pump(tester, store);
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-place-demo-table-6')));
      await tester.pumpAndSettle();
      final snapshot = (await store.load()).fold((s) => s, (f) => fail('$f'));
      final p3 = snapshot.tables.singleWhere((t) => t.id == 'demo-table-6');
      expect(p3.isPlaced, isTrue);
      // The 4×3 grid's first slot Chebyshev-clear (>=1500) of the seeds
      // (1500,2500), (5000,2500), (8200,6500) is deterministically (8750,1667).
      expect((p3.layoutX, p3.layoutY), (8750, 1667));
    });

    testWidgets('TABLE-FLOOR-LAYOUT-021: adds a section through the dialog '
        '(appended after the live siblings)', (tester) async {
      final store = InMemoryTablesStore();
      await pump(tester, store);
      await tester.tap(find.byKey(const Key('tables-add-section')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('section-name-field')),
        'Garden',
      );
      await tester.tap(find.byKey(const Key('section-save')));
      await tester.pumpAndSettle();
      final snapshot = (await store.load()).fold((s) => s, (f) => fail('$f'));
      expect(snapshot.sections.last.name, 'Garden');
      expect(snapshot.sections.last.displayOrder, 2);
      // The new (empty) canvas renders immediately.
      expect(find.text('Garden'), findsOneWidget);
    });

    testWidgets('TABLE-FLOOR-LAYOUT-021: arrange reorders sections with the '
        'complete id list', (tester) async {
      final store = InMemoryTablesStore();
      await pump(tester, store);
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('section-up-demo-section-2')));
      await tester.pumpAndSettle();
      final snapshot = (await store.load()).fold((s) => s, (f) => fail('$f'));
      expect(snapshot.sections.first.id, 'demo-section-2');
      expect(snapshot.sections.first.displayOrder, 0);
      expect(snapshot.sections.last.id, 'demo-section-1');
    });

    testWidgets('TABLE-FLOOR-LAYOUT-021: deleting a section detaches its '
        'tables — never deletes them', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final store = InMemoryTablesStore();
      await pump(tester, store);
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('section-delete-demo-section-2')));
      await tester.pumpAndSettle();
      // The confirm copy says tables are kept.
      expect(find.text(l10n.tablesSectionDeleteConfirm), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.tablesSectionDelete),
      );
      await tester.pumpAndSettle();
      final snapshot = (await store.load()).fold((s) => s, (f) => fail('$f'));
      expect(snapshot.sections.any((s) => s.id == 'demo-section-2'), isFalse);
      final p1 = snapshot.tables.singleWhere((t) => t.label == 'P1');
      expect(p1.sectionId, isNull);
      expect(p1.layoutX, isNull);
      // P1 survives: unassigned-zone tile + card.
      expect(find.text('P1'), findsNWidgets(2));
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
        (s) => s.tables,
        (f) => fail('expected success'),
      );
      final saved = tables.singleWhere((t) => t.label == 'T9');
      expect(saved.seats, 4);
      expect(saved.status, DiningTableStatus.available);
      // A fresh table has no section: unassigned-zone tile + card.
      expect(find.text('T9'), findsNWidgets(2));
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
        (s) => s.tables,
        (f) => fail('expected success'),
      );
      // The first card is the first seeded table (T1).
      expect(
        tables.singleWhere((t) => t.label == 'T1').status,
        DiningTableStatus.reserved,
      );
      // Card pill + floor-tile footnote both read Reserved.
      expect(find.text('Reserved'), findsNWidgets(2));
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
        (s) => s.tables,
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
      tester.view.physicalSize = const Size(1300, 4600);
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
      // Demo mode keeps its honest demo banner + the seeded demo tables
      // (floor tile + card since TABLE-FLOOR-LAYOUT-021).
      expect(find.text(l10n.adminDemoBanner), findsOneWidget);
      expect(find.text('T1'), findsNWidgets(2));
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
