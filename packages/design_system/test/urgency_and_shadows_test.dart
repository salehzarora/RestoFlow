import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

void main() {
  group('RestoflowUrgency (DESIGN-001)', () {
    test('thresholds are the shipped kitchen values', () {
      expect(RestoflowUrgency.warningMinutes, 10);
      expect(RestoflowUrgency.dangerMinutes, 20);
    });

    test('maps minutes onto the existing five-tone vocabulary', () {
      expect(RestoflowUrgency.toneForMinutes(0), RestoflowTone.info);
      expect(RestoflowUrgency.toneForMinutes(9), RestoflowTone.info);
      expect(RestoflowUrgency.toneForMinutes(10), RestoflowTone.warning);
      expect(RestoflowUrgency.toneForMinutes(19), RestoflowTone.warning);
      expect(RestoflowUrgency.toneForMinutes(20), RestoflowTone.danger);
      expect(RestoflowUrgency.toneForMinutes(90), RestoflowTone.danger);
    });

    test('clock skew (negative elapsed) stays calm, never urgent', () {
      expect(RestoflowUrgency.toneForMinutes(-3), RestoflowTone.info);
      expect(
        RestoflowUrgency.toneForElapsed(const Duration(minutes: -5)),
        RestoflowTone.info,
      );
    });

    test('duration overload agrees with the minutes map', () {
      expect(
        RestoflowUrgency.toneForElapsed(const Duration(minutes: 12)),
        RestoflowUrgency.toneForMinutes(12),
      );
      expect(
        RestoflowUrgency.toneForElapsed(const Duration(minutes: 25)),
        RestoflowUrgency.toneForMinutes(25),
      );
    });
  });

  group('RestoflowShadows (DESIGN-001)', () {
    test('tiers are non-empty and ordered by blur (soft-depth scale)', () {
      expect(RestoflowShadows.xs, isNotEmpty);
      expect(RestoflowShadows.sm, isNotEmpty);
      expect(RestoflowShadows.md, isNotEmpty);
      expect(RestoflowShadows.lg, isNotEmpty);
      expect(
        RestoflowShadows.xs.first.blurRadius,
        lessThan(RestoflowShadows.md.first.blurRadius),
      );
      expect(
        RestoflowShadows.md.first.blurRadius,
        lessThan(RestoflowShadows.lg.first.blurRadius),
      );
    });

    test('shadow ink is the brand navy-black, translucent', () {
      // RESTOFLOW-GLOBAL-VISUAL-V0: the brand moved green -> navy, so the ink
      // every tier tints with moved with it (#10201A -> #0B1526). The RULE is
      // unchanged and still asserted exactly: one shared brand ink across all
      // four tiers, never opaque. Pinned to the token rather than a literal, so
      // the next identity change cannot leave the tiers and the token disagreeing.
      for (final tier in [
        RestoflowShadows.xs,
        RestoflowShadows.sm,
        RestoflowShadows.md,
        RestoflowShadows.lg,
      ]) {
        for (final shadow in tier) {
          expect(
            shadow.color.toARGB32() & 0x00FFFFFF,
            kRestoflowShadowInk.toARGB32() & 0x00FFFFFF,
          );
          expect(shadow.color.a, lessThan(0.25));
        }
      }
      // The ink itself is the navy-black the rail is built from.
      expect(kRestoflowShadowInk.toARGB32() & 0x00FFFFFF, 0x0B1526);
    });
  });
}
