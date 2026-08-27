import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// TABLE-ROOM-FRAME-121 — the per-section ROOM FRAME preset: one authoritative
/// domain registry (aspect + table-footprint width in stored units) with the
/// invariants that make variable rooms safe:
///  * NULL = Standard = the exact legacy geometry, byte-for-byte;
///  * every preset keeps the TABLE TILE's physical aspect identical (no
///    squashed/stretched furniture);
///  * every preset leaves a positive usable span (legal placements exist);
///  * stored layout_x/layout_y are never reinterpreted destructively — the
///    same stored point stays at the same RELATIVE room position.
void main() {
  const legacyAspect = 1.9;
  const legacyFx = 1500;
  const fy = 2400;
  final legacyTileRatio = (legacyFx / fy) * legacyAspect; // 1.1875

  group('registry', () {
    test('the five persisted wire keys, exactly (standard is NULL)', () {
      expect(TableSectionRoomFramePreset.values.map((p) => p.wire), [
        'compact',
        'square',
        'wide',
        'portrait',
        'long_narrow',
      ]);
      expect(
        TableSectionRoomFramePreset.tryParse('standard'),
        isNull,
        reason: 'standard is never persisted',
      );
      expect(TableSectionRoomFramePreset.tryParse(null), isNull);
      expect(TableSectionRoomFramePreset.tryParse('banana'), isNull);
      for (final p in TableSectionRoomFramePreset.values) {
        expect(TableSectionRoomFramePreset.tryParse(p.wire), p);
        expect(isValidPresetKey(p.wire), isTrue);
      }
    });

    test('NULL resolves the exact legacy aspect + footprint', () {
      expect(floorRoomAspect(null), legacyAspect);
      expect(floorTableFootprintW(null), legacyFx);
    });

    test('every preset preserves the legacy TABLE TILE physical ratio '
        '(no squash/stretch) within 1%', () {
      for (final p in TableSectionRoomFramePreset.values) {
        final ratio = (p.tableFootprintXUnits / fy) * p.aspect;
        expect(
          (ratio - legacyTileRatio).abs() / legacyTileRatio,
          lessThan(0.01),
          reason: '${p.wire}: $ratio vs $legacyTileRatio',
        );
      }
    });

    test('aspects are distinct and intentional (wide > standard > compact > '
        'square > portrait > long_narrow)', () {
      double a(TableSectionRoomFramePreset p) => p.aspect;
      expect(a(TableSectionRoomFramePreset.wide), greaterThan(legacyAspect));
      expect(legacyAspect, greaterThan(a(TableSectionRoomFramePreset.compact)));
      expect(
        a(TableSectionRoomFramePreset.compact),
        greaterThan(a(TableSectionRoomFramePreset.square)),
      );
      expect(
        a(TableSectionRoomFramePreset.square),
        greaterThan(a(TableSectionRoomFramePreset.portrait)),
      );
      expect(
        a(TableSectionRoomFramePreset.portrait),
        greaterThan(a(TableSectionRoomFramePreset.longNarrow)),
      );
      expect(a(TableSectionRoomFramePreset.square), 1.0);
    });

    test('every preset leaves a positive usable span and fits at least one '
        'legal table', () {
      for (final p in <TableSectionRoomFramePreset?>[
        null,
        ...TableSectionRoomFramePreset.values,
      ]) {
        final fx = floorTableFootprintW(p);
        expect(fx, greaterThan(0));
        expect(kFloorLayoutMax - fx, greaterThan(0), reason: '${p?.wire}');
        expect(kFloorLayoutMax - kFloorTableH, greaterThan(0));
        final rect = floorTableRoomRect(0, 0, frame: p);
        expect(rect.left, 0);
        expect(rect.top, 0);
        expect(rect.width, fx.toDouble());
        expect(rect.height, fy.toDouble());
      }
    });
  });

  group('projection contract', () {
    test('Standard/NULL room rects are byte-identical to the legacy call', () {
      for (final (x, y) in const [(0, 0), (2500, 7500), (10000, 10000)]) {
        final legacy = floorTableRoomRect(x, y);
        final explicit = floorTableRoomRect(x, y, frame: null);
        expect(explicit, legacy);
      }
    });

    test('stored coordinates keep their RELATIVE room position in every '
        'frame (never mutated, only reprojected)', () {
      for (final p in TableSectionRoomFramePreset.values) {
        final fx = floorTableFootprintW(p);
        for (final (x, y) in const [(0, 0), (5000, 5000), (10000, 10000)]) {
          final r = floorTableRoomRect(x, y, frame: p);
          expect(r.left, closeTo(x / 10000 * (10000 - fx), 0.001));
          expect(r.top, closeTo(y / 10000 * (10000 - fy), 0.001));
          // Round-trip through the inverse: the stored point survives.
          final back = floorStoredFromRoomTopLeft(r.left, r.top, frame: p);
          expect(back.x, x, reason: '${p.wire}');
          expect(back.y, y, reason: '${p.wire}');
        }
      }
    });

    test('overlap detection follows the frame footprint', () {
      // Two anchors that clear each other under Standard but collide under
      // long_narrow's much wider footprint.
      const a = (x: 0, y: 0);
      const b = (x: 2500, y: 0);
      expect(floorPlacementsOverlap(a, b), isFalse);
      expect(
        floorPlacementsOverlap(
          a,
          b,
          frame: TableSectionRoomFramePreset.longNarrow,
        ),
        isTrue,
      );
    });

    test('initial placement never overlaps while grid capacity remains '
        '(narrow frames hold fewer default slots)', () {
      for (final p in <TableSectionRoomFramePreset?>[
        null,
        ...TableSectionRoomFramePreset.values,
      ]) {
        final columns = p == null
            ? 4
            : ((kFloorLayoutMax - floorTableFootprintW(p)) /
                      floorTableFootprintW(p))
                  .floor()
                  .clamp(1, 4)
                  .toInt();
        final capacity = columns * 3;
        expect(capacity, greaterThanOrEqualTo(3), reason: '${p?.wire}');
        final occupied = <FloorPoint>[];
        final take = capacity < 6 ? capacity : 6;
        for (var i = 0; i < take; i++) {
          final next = initialFloorPlacement(occupied, frame: p);
          expect(
            occupied.every((o) => !floorPlacementsOverlap(next, o, frame: p)),
            isTrue,
            reason: '${p?.wire} #$i',
          );
          occupied.add(next);
        }
      }
    });
  });
}
