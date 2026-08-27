import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// TABLE-FLOOR-MAP-POLISH-027 — derived cluster packing for linked tables.
/// Pure and deterministic: all three surfaces derive identical layouts, and
/// because base coordinates are never written, unlink restore is exact by
/// construction.
void main() {
  group('packLinkedCluster', () {
    test('a singleton (or empty) derives identity', () {
      expect(packLinkedCluster(const []), isEmpty);
      final one = packLinkedCluster(const [(id: 'a', x: 4000, y: 5000)]);
      expect(one, {'a': (x: 4000, y: 5000)});
    });

    test('two members: the anchor keeps its base spot; the peer packs beside '
        'it with the seam', () {
      final derived = packLinkedCluster(const [
        (id: 'a', x: 1000, y: 1000),
        (id: 'b', x: 8000, y: 8000),
      ]);
      // Anchor = top-left-most base = a; unchanged.
      expect(derived['a'], (x: 1000, y: 1000));
      // b sits one footprint+seam to the right at the anchor's row:
      // roomLeft(a)=850; +1620 => 2470 room -> stored 2906.
      expect(derived['b'], (x: 2906, y: 1000));
    });

    test('anchor selection is top-left-most base (y, then x, then id)', () {
      final derived = packLinkedCluster(const [
        (id: 'z', x: 2000, y: 3000),
        (id: 'a', x: 6000, y: 3000), // same y, larger x -> not anchor
        (id: 'm', x: 2000, y: 5000), // larger y -> not anchor
      ]);
      expect(derived['z'], (x: 2000, y: 3000));
    });

    test('packed members NEVER overlap under the shared footprint', () {
      final derived = packLinkedCluster(const [
        (id: 'a', x: 3000, y: 3000),
        (id: 'b', x: 9000, y: 1000),
        (id: 'c', x: 1000, y: 9000),
        (id: 'd', x: 5000, y: 5000),
      ]);
      final points = derived.values.toList();
      for (var i = 0; i < points.length; i++) {
        for (var j = i + 1; j < points.length; j++) {
          expect(
            floorPlacementsOverlap(points[i], points[j]),
            isFalse,
            reason: 'cluster members must pack clear of each other',
          );
        }
      }
    });

    test('>6 members wrap to a second row', () {
      final members = [
        for (var i = 0; i < 7; i++) (id: 'm$i', x: 100 * i, y: 100 * i),
      ];
      final derived = packLinkedCluster(members);
      final ys = derived.values.map((p) => p.y).toSet();
      expect(ys.length, 2, reason: '7 members = 6 on row 1 + 1 wrapped');
      // Everything stays inside the room.
      for (final p in derived.values) {
        expect(p.x, inInclusiveRange(0, 10000));
        expect(p.y, inInclusiveRange(0, 10000));
      }
    });

    test('a cluster anchored near the right edge shifts left to stay inside '
        'the room', () {
      final derived = packLinkedCluster(const [
        (id: 'a', x: 9800, y: 1000), // anchor hugging the right wall
        (id: 'b', x: 9900, y: 9000),
        (id: 'c', x: 9700, y: 9500),
      ]);
      for (final p in derived.values) {
        expect(p.x, inInclusiveRange(0, 10000));
        expect(p.y, inInclusiveRange(0, 10000));
      }
      // And still no member overlaps another.
      final pts = derived.values.toList();
      for (var i = 0; i < pts.length; i++) {
        for (var j = i + 1; j < pts.length; j++) {
          expect(floorPlacementsOverlap(pts[i], pts[j]), isFalse);
        }
      }
    });

    test('derivation is deterministic (same input, same output)', () {
      const members = [
        (id: 'a', x: 3000, y: 3000),
        (id: 'b', x: 7000, y: 2000),
      ];
      expect(packLinkedCluster(members), packLinkedCluster(members));
    });

    // TABLE-ROOM-FRAME-121: the pack must round-trip under the SAME frame the
    // surfaces render with — a frame-free pack rendered frame-aware overlaps
    // (narrow rooms) or detaches (wide rooms).
    test('121: packed members keep the exact seam gap under EVERY frame '
        '(no overlap, no detach)', () {
      for (final frame in <TableSectionRoomFramePreset?>[
        null,
        ...TableSectionRoomFramePreset.values,
      ]) {
        final derived = packLinkedCluster(const [
          (id: 'a', x: 0, y: 0),
          (id: 'b', x: 8000, y: 8000),
        ], frame: frame);
        final a = floorTableRoomRect(
          derived['a']!.x,
          derived['a']!.y,
          frame: frame,
        );
        final b = floorTableRoomRect(
          derived['b']!.x,
          derived['b']!.y,
          frame: frame,
        );
        // b packs beside a with the seam gap when the frame fits two
        // columns; a one-column frame (long_narrow) wraps b BELOW a with
        // the same seam. Tolerances cover the stored-integer rounding of
        // the inverse projection.
        final fx = floorTableFootprintW(frame);
        final twoColumns =
            (kFloorLayoutMax + kFloorClusterSeam) ~/ (fx + kFloorClusterSeam) >=
            2;
        if (twoColumns) {
          expect(b.top, closeTo(a.top, 2), reason: '${frame?.wire}');
          expect(
            b.left - (a.left + a.width),
            closeTo(kFloorClusterSeam, 3),
            reason: '${frame?.wire}: gap must be the seam, not overlap/detach',
          );
        } else {
          expect(b.left, closeTo(a.left, 2), reason: '${frame?.wire}');
          expect(
            b.top - (a.top + a.height),
            closeTo(kFloorClusterSeam, 3),
            reason: '${frame?.wire}: one-column frames wrap with the seam',
          );
        }
      }
    });

    test('121: no packed member overlaps and all stay in the room under '
        'every frame, even large clusters near the right wall', () {
      for (final frame in <TableSectionRoomFramePreset?>[
        null,
        ...TableSectionRoomFramePreset.values,
      ]) {
        final derived = packLinkedCluster(const [
          (id: 'a', x: 9800, y: 1000),
          (id: 'b', x: 9900, y: 9000),
          (id: 'c', x: 9700, y: 9500),
          (id: 'd', x: 100, y: 9900),
        ], frame: frame);
        final pts = derived.values.toList();
        for (final p in pts) {
          expect(p.x, inInclusiveRange(0, 10000), reason: '${frame?.wire}');
          expect(p.y, inInclusiveRange(0, 10000), reason: '${frame?.wire}');
        }
        for (var i = 0; i < pts.length; i++) {
          for (var j = i + 1; j < pts.length; j++) {
            expect(
              floorPlacementsOverlap(pts[i], pts[j], frame: frame),
              isFalse,
              reason: '${frame?.wire}: members must pack clear',
            );
          }
        }
      }
    });

    test('121: a NULL frame packs byte-identically to the legacy call', () {
      const members = [
        (id: 'a', x: 1000, y: 1000),
        (id: 'b', x: 8000, y: 8000),
      ];
      expect(
        packLinkedCluster(members, frame: null),
        packLinkedCluster(members),
      );
      expect(packLinkedCluster(members)['b'], (x: 2906, y: 1000));
    });
  });

  group('floorClusterSeamRect', () {
    test('bounds the derived members with padding, clamped to the room', () {
      final derived = packLinkedCluster(const [
        (id: 'a', x: 0, y: 0),
        (id: 'b', x: 5000, y: 5000),
      ]);
      final seam = floorClusterSeamRect(derived.values);
      expect(seam.left, 0); // clamped at the wall
      expect(seam.top, 0);
      expect(seam.width, greaterThan(kFloorTableW.toDouble()));
      expect(seam.height, greaterThan(kFloorTableH.toDouble()));
      expect(seam.left + seam.width, lessThanOrEqualTo(10000));
      expect(seam.top + seam.height, lessThanOrEqualTo(10000));
    });
  });
}
