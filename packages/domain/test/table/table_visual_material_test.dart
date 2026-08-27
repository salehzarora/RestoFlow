import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// TABLE-VISUAL-CONFIGURATION-120 — the persisted material + fixture-style
/// vocabularies. These pins mirror the server setters exactly: a drift here
/// IS a contract break.
void main() {
  group('TableVisualMaterial', () {
    test('the six approved wire keys, exactly', () {
      expect(TableVisualMaterial.values.map((m) => m.wire), [
        'wood',
        'dark_wood',
        'light_wood',
        'rustic_wood',
        'plastic',
        'neutral_modern',
      ]);
    });

    test('every wire key round-trips strictly', () {
      for (final m in TableVisualMaterial.values) {
        expect(TableVisualMaterial.tryParse(m.wire), m);
        expect(
          isValidPresetKey(m.wire),
          isTrue,
          reason: '${m.wire} must satisfy the structural CHECK',
        );
      }
    });

    test('unknown / null / non-string decode to null (= Auto)', () {
      expect(TableVisualMaterial.tryParse('banana'), isNull);
      expect(TableVisualMaterial.tryParse(null), isNull);
      expect(TableVisualMaterial.tryParse(7), isNull);
      expect(TableVisualMaterial.tryParse('WOOD'), isNull);
      expect(
        TableVisualMaterial.tryParse('auto'),
        isNull,
        reason: 'Auto is NULL, never a wire key',
      );
    });

    test('the wire key constant matches every read contract', () {
      expect(kTableVisualMaterialWireKey, 'visual_material');
    });
  });

  group('floor element style registry', () {
    test('exact per-kind vocabularies (server-mirrored)', () {
      expect(kFloorElementStyleRegistry, {
        'cashier': ['modern', 'wood', 'dark'],
        'plant': ['leafy', 'palm', 'compact_pot'],
        'door': ['wood', 'glass', 'modern'],
        'window': ['modern_glass', 'framed', 'dark_frame'],
        'wall': ['plain', 'brick', 'wood_partition'],
      });
      expect(
        kFloorElementStyleRegistry.keys.toSet(),
        kFloorElementKinds.toSet(),
        reason: 'every kind has a registry entry',
      );
    });

    test('every registered style satisfies the structural CHECK', () {
      for (final styles in kFloorElementStyleRegistry.values) {
        for (final s in styles) {
          expect(isValidPresetKey(s), isTrue, reason: s);
        }
      }
    });

    test('cross-kind membership is false; null always allowed', () {
      expect(isFloorElementStyleAllowed('plant', 'glass'), isFalse);
      expect(isFloorElementStyleAllowed('door', 'leafy'), isFalse);
      expect(isFloorElementStyleAllowed('cashier', 'brick'), isFalse);
      expect(isFloorElementStyleAllowed('wall', 'modern'), isFalse);
      expect(isFloorElementStyleAllowed('plant', 'palm'), isTrue);
      for (final kind in kFloorElementKinds) {
        expect(isFloorElementStyleAllowed(kind, null), isTrue);
      }
      expect(
        floorElementStylesFor('fountain'),
        isEmpty,
        reason: 'unknown kinds have no variants',
      );
    });

    test('the style wire key constant', () {
      expect(kFloorElementStyleWireKey, 'visual_style');
    });
  });
}
