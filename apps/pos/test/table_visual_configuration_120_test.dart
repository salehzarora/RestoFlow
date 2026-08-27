import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show TableVisualMaterial;
import 'package:restoflow_pos/src/data/demo_tables.dart';

/// TABLE-VISUAL-CONFIGURATION-120 — the POS is a READ-ONLY consumer of the
/// persisted material/style keys: tolerant decode, geometry untouched, no
/// write path exists.
void main() {
  Map<String, dynamic> envelope() => {
    'ok': true,
    'entity': 'tables',
    'tables': [
      {
        'id': 't-1',
        'label': 'T1',
        'status': 'available',
        'effective_state': 'available',
        'visual_preset': 'round_table',
        'visual_material': 'dark_wood',
        'section_floor_preset': 'wood_dark',
      },
      {
        'id': 't-2',
        'label': 'T2',
        'status': 'available',
        'effective_state': 'available',
        // no material key (legacy hosted) => Auto
      },
      {
        'id': 't-3',
        'label': 'T3',
        'status': 'available',
        'effective_state': 'available',
        'visual_material': 'marble', // unknown => Auto, never a failure
      },
    ],
    'floor_elements': [
      {
        'id': 'e-1',
        'section_id': 's-1',
        'kind': 'window',
        'layout_x': 4600,
        'layout_y': 0,
        'width_norm': 2000,
        'height_norm': 150,
        'orientation_quarter_turns': 2,
        'visual_style': 'dark_frame',
      },
      {
        'id': 'e-2',
        'section_id': 's-1',
        'kind': 'wall',
        'layout_x': 100,
        'layout_y': 100,
        'width_norm': 3000,
        'height_norm': 150,
        'visual_style': 'leafy', // cross-kind garbage => sanitized to null
      },
    ],
  };

  test('pos_tables rows decode visual_material tolerantly', () async {
    final repo = RealTablesRepository(
      _StubTransport(envelope()),
      const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
    );
    final snapshot = await repo.loadFloorSnapshot();
    final byId = {for (final t in snapshot.tables) t.table.tableId: t};
    expect(byId['t-1']!.visualMaterial, TableVisualMaterial.darkWood);
    expect(byId['t-2']!.visualMaterial, isNull);
    expect(byId['t-3']!.visualMaterial, isNull);
  });

  test('fixture rows decode visual_style (registry-sanitized) with geometry '
      'untouched', () async {
    final repo = RealTablesRepository(
      _StubTransport(envelope()),
      const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
    );
    final snapshot = await repo.loadFloorSnapshot();
    final byId = {for (final e in snapshot.floorElements) e.id: e};
    expect(byId['e-1']!.visualStyle, 'dark_frame');
    expect(byId['e-1']!.orientationQuarterTurns, 2);
    expect(byId['e-1']!.widthNorm, 2000);
    expect(byId['e-2']!.visualStyle, isNull);
  });
}

class _StubTransport implements SyncRpcTransport {
  _StubTransport(this.result);
  final Object? result;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    expect(function, 'pos_tables');
    return result;
  }
}
