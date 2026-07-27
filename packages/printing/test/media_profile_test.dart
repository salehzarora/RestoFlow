import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

/// PRINT-LAYOUT-001 — the typed media profile geometry + the backward-compatible
/// default resolution.
void main() {
  test(
    'the continuous-80 default is byte-compatible geometry (576/48, no page)',
    () {
      const p = MediaProfile.continuous80;
      expect(p.widthDots, 576);
      expect(p.widthBytes, 72);
      expect(p.columns, 48);
      expect(p.mediaHeightDots, 0);
      expect(p.paginates, isFalse, reason: 'a continuous roll never paginates');
      expect(p.printableHeightDots, 0);
      expect(p.feedLines, 3);
      expect(p.fontScale, 1.0);
      expect(p.safeLeftDots, 0);
      expect(p.safeRightDots, 0);
    },
  );

  test('50×50 is a narrow fixed label (384 dots, paginates, safe margins)', () {
    const p = MediaProfile.label50x50;
    expect(p.widthDots, 384);
    expect(p.widthBytes, 48);
    expect(p.widthDots % 8, 0);
    expect(p.columns, 32);
    expect(p.mediaHeightDots, 400); // 50mm @ 8 dots/mm
    expect(p.paginates, isTrue);
    expect(p.printableWidthDots, 384 - 8 - 8);
    expect(p.printableHeightDots, 400 - 12 - 20);
    expect(p.printableHeightDots, greaterThan(0));
  });

  test('80×80 is a wide fixed label (576 dots, paginates, larger type)', () {
    const p = MediaProfile.label80x80;
    expect(p.widthDots, 576);
    expect(p.widthBytes, 72);
    expect(p.columns, 48);
    expect(p.mediaHeightDots, 640); // 80mm @ 8 dots/mm
    expect(p.paginates, isTrue);
    expect(p.printableHeightDots, 640 - 16 - 24);
    expect(
      p.fontScale,
      greaterThan(MediaProfile.label50x50.fontScale),
      reason: '80×80 uses its extra room for larger type',
    );
  });

  test('every profile keeps widthDots a positive multiple of 8', () {
    for (final p in MediaProfile.all) {
      expect(p.widthDots > 0 && p.widthDots % 8 == 0, isTrue, reason: p.idKey);
    }
  });

  test('fromId resolves keys and defaults unknown/absent to continuous-80', () {
    expect(MediaProfile.fromId('label50x50').id, MediaProfileId.label50x50);
    expect(MediaProfile.fromId('label80x80').id, MediaProfileId.label80x80);
    expect(MediaProfile.fromId('continuous80').id, MediaProfileId.continuous80);
    // Backward compatibility: an unknown or missing key => the safe default.
    expect(MediaProfile.fromId(null).id, MediaProfileId.continuous80);
    expect(MediaProfile.fromId('').id, MediaProfileId.continuous80);
    expect(MediaProfile.fromId('mm999').id, MediaProfileId.continuous80);
    // Round-trip: idKey -> fromId is stable for every profile.
    for (final p in MediaProfile.all) {
      expect(MediaProfile.fromId(p.idKey).id, p.id, reason: p.idKey);
    }
  });

  test('the operator-selectable set is exactly the two fixed labels', () {
    expect(MediaProfile.selectable.map((p) => p.id), [
      MediaProfileId.label50x50,
      MediaProfileId.label80x80,
    ]);
  });
}
