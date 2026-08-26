import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// TABLE-VISUAL-LAYOUT-118 — the shared visual-preset vocabulary. Every
/// surface (Dashboard editor, POS picker/move sheet, kiosk floor) parses the
/// SAME wire keys through the SAME tolerant decoder, so a legacy row (no
/// key), a null, or an unknown future key always lands on the safe default
/// instead of failing a floor read.
void main() {
  group('TableVisualPreset', () {
    test('has exactly the four owner presets with stable wire keys', () {
      expect(TableVisualPreset.values.map((p) => p.wire).toList(), [
        'classic_rect_table',
        'round_table',
        'table_with_barrels',
        'booth_table',
      ]);
    });

    test(
      'the default is the classic rectangle (legacy rows look unchanged)',
      () {
        expect(
          TableVisualPreset.defaultPreset,
          TableVisualPreset.classicRectTable,
        );
        expect(
          TableVisualPreset.fromWire(null),
          TableVisualPreset.classicRectTable,
        );
        expect(
          TableVisualPreset.fromWire(''),
          TableVisualPreset.classicRectTable,
        );
        expect(
          TableVisualPreset.fromWire('sofa_table'),
          TableVisualPreset.classicRectTable,
        );
        expect(
          TableVisualPreset.fromWire(42),
          TableVisualPreset.classicRectTable,
        );
      },
    );

    test('every wire key round-trips; tryParse is strict', () {
      for (final p in TableVisualPreset.values) {
        expect(TableVisualPreset.fromWire(p.wire), p);
        expect(TableVisualPreset.tryParse(p.wire), p);
      }
      expect(TableVisualPreset.tryParse('round_table '), isNull);
      expect(TableVisualPreset.tryParse('ROUND_TABLE'), isNull);
      expect(TableVisualPreset.tryParse(null), isNull);
    });

    test('wire keys satisfy the DB key CHECK (^[a-z][a-z0-9_]{0,39}\$)', () {
      for (final p in TableVisualPreset.values) {
        expect(isValidPresetKey(p.wire), isTrue, reason: p.wire);
      }
      expect(isValidPresetKey('Round'), isFalse);
      expect(isValidPresetKey('1round'), isFalse);
      expect(isValidPresetKey('a' * 41), isFalse);
      expect(isValidPresetKey(''), isFalse);
    });
  });

  group('FloorPreset', () {
    test('has exactly the four owner floor styles with stable wire keys', () {
      expect(FloorPreset.values.map((p) => p.wire).toList(), [
        'plain_light',
        'wood_dark',
        'tile_modern',
        'stone_neutral',
      ]);
    });

    test('the default is plain light (legacy sections look unchanged)', () {
      expect(FloorPreset.defaultPreset, FloorPreset.plainLight);
      expect(FloorPreset.fromWire(null), FloorPreset.plainLight);
      expect(FloorPreset.fromWire('marble'), FloorPreset.plainLight);
      expect(FloorPreset.fromWire(''), FloorPreset.plainLight);
    });

    test('every wire key round-trips; tryParse is strict', () {
      for (final p in FloorPreset.values) {
        expect(FloorPreset.fromWire(p.wire), p);
        expect(FloorPreset.tryParse(p.wire), p);
        expect(isValidPresetKey(p.wire), isTrue);
      }
      expect(FloorPreset.tryParse('Wood_Dark'), isNull);
    });

    test('dark floors are declared so tiles can pick contrasting ink', () {
      expect(FloorPreset.plainLight.isDark, isFalse);
      expect(FloorPreset.woodDark.isDark, isTrue);
      expect(FloorPreset.tileModern.isDark, isFalse);
      expect(FloorPreset.stoneNeutral.isDark, isFalse);
    });
  });

  group('wire keys', () {
    test('the row/section key names are the shared contract', () {
      expect(kTableVisualPresetWireKey, 'visual_preset');
      expect(kFloorPresetWireKey, 'floor_preset');
      expect(kSectionFloorPresetWireKey, 'section_floor_preset');
    });
  });
}
