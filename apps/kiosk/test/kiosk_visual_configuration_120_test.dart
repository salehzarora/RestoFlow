import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show TableVisualMaterial;
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';

/// TABLE-VISUAL-CONFIGURATION-120 — the kiosk is a READ-ONLY, customer-safe
/// consumer of the persisted material/style keys: tolerant decode, geometry
/// untouched, and the envelope still carries no staff-only fields (the
/// presentation keys are the ONLY additions).
void main() {
  Map<String, dynamic> envelope() => {
    'ok': true,
    'entity': 'kiosk_tables',
    'tables': [
      {
        'id': 't-1',
        'label': 'T1',
        'seats': 4,
        'section_id': 's-1',
        'section_name': 'Hall',
        'section_display_order': 0,
        'effective_state': 'available',
        'layout_x': 2500,
        'layout_y': 7500,
        'visual_preset': 'round_table',
        'visual_material': 'neutral_modern',
        'section_floor_preset': 'wood_dark',
      },
      {
        'id': 't-2',
        'label': 'T2',
        'seats': 2,
        'section_id': 's-1',
        'section_name': 'Hall',
        'section_display_order': 0,
        'effective_state': 'available',
        'layout_x': 6000,
        'layout_y': 7500,
        'visual_material': 'obsidian', // unknown => Auto, never a failure
      },
    ],
    'floor_elements': [
      {
        'id': 'e-1',
        'section_id': 's-1',
        'kind': 'cashier',
        'layout_x': 6800,
        'layout_y': 0,
        'width_norm': 900,
        'height_norm': 900,
        'orientation_quarter_turns': 3,
        'label': 'Till',
        'visual_style': 'dark',
      },
      {
        'id': 'e-2',
        'section_id': 's-1',
        'kind': 'plant',
        'layout_x': 9000,
        'layout_y': 100,
        'width_norm': 900,
        'height_norm': 900,
        'visual_style': 'framed', // cross-kind => sanitized to null
      },
    ],
  };

  test('kiosk tables decode visual_material tolerantly', () {
    final zones = mapKioskTablesEnvelope(envelope())!;
    final tables = zones.expand((z) => z.tables).toList();
    final byId = {for (final t in tables) t.id: t};
    expect(byId['t-1']!.visualMaterial, TableVisualMaterial.neutralModern);
    expect(byId['t-2']!.visualMaterial, isNull);
  });

  test('kiosk fixtures decode visual_style (registry-sanitized), geometry '
      'and orientation untouched', () {
    final zones = mapKioskTablesEnvelope(envelope())!;
    final elements = zones.expand((z) => z.elements).toList();
    final byId = {for (final e in elements) e.id: e};
    expect(byId['e-1']!.visualStyle, 'dark');
    expect(byId['e-1']!.orientationQuarterTurns, 3);
    expect(byId['e-1']!.widthNorm, 900);
    expect(byId['e-2']!.visualStyle, isNull);
  });
}
