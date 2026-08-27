import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show TableVisualMaterial;
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminScope;

/// TABLE-VISUAL-CONFIGURATION-120 — the Dashboard repository contract for the
/// persisted material/style keys: tolerant decode, DEDICATED setter RPCs with
/// the exact wire args (never the full-replace upserts), honest failures.
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

Map<String, dynamic> _listEnvelope() => {
  'ok': true,
  'entity': 'table',
  'tables': [
    {
      'id': 't-1',
      'label': 'T1',
      'status': 'available',
      'branch_id': 'b-1',
      'is_active': true,
      'visual_preset': 'round_table',
      'visual_material': 'rustic_wood',
    },
    {
      // A legacy row: no material key at all.
      'id': 't-2',
      'label': 'T2',
      'status': 'available',
      'branch_id': 'b-1',
      'is_active': true,
    },
    {
      // A key this client does not know: Auto, never a failure.
      'id': 't-3',
      'label': 'T3',
      'status': 'available',
      'branch_id': 'b-1',
      'is_active': true,
      'visual_material': 'marble',
    },
  ],
  'sections': <Object?>[],
  'floor_elements': [
    {
      'id': 'e-1',
      'section_id': 's-1',
      'kind': 'plant',
      'layout_x': 100,
      'layout_y': 100,
      'width_norm': 900,
      'height_norm': 900,
      'orientation_quarter_turns': 0,
      'visual_style': 'palm',
    },
    {
      // CROSS-KIND garbage from a hypothetical writer: sanitized to null.
      'id': 'e-2',
      'section_id': 's-1',
      'kind': 'door',
      'layout_x': 300,
      'layout_y': 0,
      'width_norm': 900,
      'height_norm': 150,
      'orientation_quarter_turns': 1,
      'visual_style': 'leafy',
    },
  ],
};

void main() {
  group('decode', () {
    test('material + style decode tolerantly (absent/unknown => null/Auto; '
        'cross-kind style sanitized)', () async {
      final repo = SupabaseTablesRepository(
        transport: _FakeTransport((fn, p) => _listEnvelope()),
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final snapshot = (await repo.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final byId = {for (final t in snapshot.tables) t.id: t};
      expect(byId['t-1']!.visualMaterial, TableVisualMaterial.rusticWood);
      expect(byId['t-2']!.visualMaterial, isNull);
      expect(byId['t-3']!.visualMaterial, isNull);
      final elements = {for (final e in snapshot.floorElements) e.id: e};
      expect(elements['e-1']!.visualStyle, 'palm');
      expect(
        elements['e-2']!.visualStyle,
        isNull,
        reason: 'a cross-kind style never survives the decode',
      );
      // Geometry fields untouched by the new keys.
      expect(elements['e-2']!.orientationQuarterTurns, 1);
      expect(elements['e-1']!.widthNorm, 900);
    });
  });

  group('dedicated writers', () {
    test('the setters call the DEDICATED RPCs with the wire keys', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': true, 'idempotent_replay': false},
      );
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final a = await repo.setTableVisualMaterial(
        't-1',
        TableVisualMaterial.darkWood,
      );
      final b = await repo.setFloorElementStyle('e-1', 'palm');
      final c = await repo.setTableVisualMaterial('t-1', null);
      expect(a.fold((_) => true, (_) => false), isTrue);
      expect(b.fold((_) => true, (_) => false), isTrue);
      expect(c.fold((_) => true, (_) => false), isTrue);
      expect(t.calls.map((call) => call.$1).toList(), [
        'set_table_visual_material',
        'set_floor_element_style',
        'set_table_visual_material',
      ]);
      expect(t.calls[0].$2['p_table_id'], 't-1');
      expect(t.calls[0].$2['p_visual_material'], 'dark_wood');
      expect(t.calls[0].$2['p_client_request_id'], isA<String>());
      expect(t.calls[1].$2['p_element_id'], 'e-1');
      expect(t.calls[1].$2['p_visual_style'], 'palm');
      expect(
        t.calls[2].$2['p_visual_material'],
        isNull,
        reason: 'null clears back to Auto',
      );
      // Never through the full-replace upserts.
      expect(t.calls.any((call) => call.$1.startsWith('upsert_')), isFalse);
    });

    test('a permission_denied envelope surfaces honestly', () async {
      final repo = SupabaseTablesRepository(
        transport: _FakeTransport(
          (fn, p) => {'ok': false, 'error': 'permission_denied'},
        ),
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final res = await repo.setTableVisualMaterial(
        't-1',
        TableVisualMaterial.wood,
      );
      expect(res.fold((_) => false, (_) => true), isTrue);
    });

    test('the in-memory demo store persists material + style and validates '
        'the registry', () async {
      final store = InMemoryTablesStore();
      final snapshotBefore = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final tableId = snapshotBefore.tables.first.id;
      final element = snapshotBefore.floorElements.first;
      expect(
        (await store.setTableVisualMaterial(
          tableId,
          TableVisualMaterial.plastic,
        )).fold((_) => true, (_) => false),
        isTrue,
      );
      expect(
        (await store.setFloorElementStyle(
          element.id,
          // any first valid style for that element's kind
          const {
            'cashier': 'modern',
            'plant': 'palm',
            'door': 'glass',
            'window': 'framed',
            'wall': 'brick',
          }[element.kind],
        )).fold((_) => true, (_) => false),
        isTrue,
      );
      expect(
        (await store.setFloorElementStyle(
          element.id,
          'banana',
        )).fold((_) => false, (_) => true),
        isTrue,
        reason: 'the in-memory store mirrors the server registry',
      );
      final after = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(
        after.tables.firstWhere((t) => t.id == tableId).visualMaterial,
        TableVisualMaterial.plastic,
      );
      expect(
        after.floorElements.firstWhere((e) => e.id == element.id).visualStyle,
        isNotNull,
      );
    });
  });
}
