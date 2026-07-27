import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// PRINT-BRANDING-LOGO-001 (correction §1-3 / §18) — the receipt logo must
/// SURVIVE text rasterization (ar/he — Arabic is the default locale) AND, on a
/// FIXED label, be COMPOSED into the SAME first physical page as the receipt
/// title/text — never a dedicated logo-only label.

/// A logo raster for [profile]'s exact width whose TOP row is all-black (0xFF)
/// and the rest white, so it is identifiable inside a composed page image.
PrintRasterImageLine _logo(MediaProfile profile, {int height = 40}) {
  final widthBytes = profile.widthBytes;
  final data = Uint8List(widthBytes * height);
  for (var b = 0; b < widthBytes; b++) {
    data[b] = 0xFF; // top row = solid black (the logo marker)
  }
  return PrintRasterImageLine(
    data: data,
    widthBytes: widthBytes,
    heightDots: height,
  );
}

PrintDocument _doc(
  MediaProfile profile, {
  required bool arabic,
  int bodyLines = 2,
  bool withLogo = true,
}) => PrintDocument([
  if (withLogo) _logo(profile),
  if (withLogo) const PrintFeedLine(1),
  PrintTextLine(
    arabic ? 'مطعم' : 'Restaurant',
    style: PrintLineStyle.headingLarge,
  ),
  for (var i = 0; i < bodyLines; i++)
    PrintTextLine(arabic ? 'سطر $i' : 'Line $i'),
  const PrintFeedLine(3),
  const PrintCutLine(),
]);

List<PrintRasterImageLine> _rasters(PrintDocument d) =>
    d.lines.whereType<PrintRasterImageLine>().toList();
int _count<T>(PrintDocument d) => d.lines.whereType<T>().length;

/// Whether [img]'s TOP row is the all-black logo marker.
bool _startsWithLogo(PrintRasterImageLine img) {
  final widthBytes = img.widthBytes;
  for (var b = 0; b < widthBytes; b++) {
    if (img.data[b] != 0xFF) return false;
  }
  return true;
}

void main() {
  final rasterizer = FakeReceiptRasterizer();

  group('continuous80 (single receipt job)', () {
    test('English (LTR) keeps the logo inline, one cut', () async {
      final out = await rasterizeForMediaProfile(
        _doc(MediaProfile.continuous80, arabic: false),
        rasterizer: rasterizer,
        profile: MediaProfile.continuous80,
      );
      // The logo is a real raster line; the text stays text; exactly one cut.
      expect(_rasters(out).any(_startsWithLogo), isTrue);
      expect(_count<PrintCutLine>(out), 1);
    });

    test('Arabic (RTL, rasterized) STILL keeps the logo, one cut', () async {
      final out = await rasterizeForMediaProfile(
        _doc(MediaProfile.continuous80, arabic: true),
        rasterizer: rasterizer,
        profile: MediaProfile.continuous80,
      );
      expect(_rasters(out).any(_startsWithLogo), isTrue);
      expect(_count<PrintCutLine>(out), 1, reason: 'one continuous receipt');
    });
  });

  for (final profile in [MediaProfile.label50x50, MediaProfile.label80x80]) {
    group('fixed media ${profile.idKey}', () {
      for (final arabic in [false, true]) {
        final locale = arabic ? 'Arabic' : 'English';
        test(
          'short receipt: logo COMPOSED into the ONE first page ($locale)',
          () async {
            final out = await rasterizeForMediaProfile(
              _doc(profile, arabic: arabic, bodyLines: 2),
              rasterizer: rasterizer,
              profile: profile,
            );
            final rasters = _rasters(out);
            // Exactly ONE page image (no dedicated logo label).
            expect(rasters.length, 1, reason: 'one physical page');
            final page = rasters.single;
            // Logo at the TOP, then real text below (taller than the logo alone).
            expect(_startsWithLogo(page), isTrue);
            expect(
              page.heightDots,
              greaterThan(40),
              reason: 'logo + gap + text stacked, not the 40-dot logo alone',
            );
            expect(
              page.data.any((b) => b == 0x55),
              isTrue,
              reason: 'the receipt text (fake fill 0x55) shares the page',
            );
            // Exactly one feed + one cut (one physical boundary), never two.
            expect(_count<PrintFeedLine>(out), 1);
            expect(_count<PrintCutLine>(out), 1);
          },
        );
      }

      test('no dedicated logo-only page (no image is the bare logo)', () async {
        final out = await rasterizeForMediaProfile(
          _doc(profile, arabic: true, bodyLines: 2),
          rasterizer: rasterizer,
          profile: profile,
        );
        // No emitted raster is exactly the 40-dot logo (which would be a logo
        // label); every logo-bearing image is a composed, taller page.
        expect(_rasters(out).any((r) => r.heightDots == 40), isFalse);
      });

      test('long receipt: paginates; logo ONLY on page one', () async {
        final out = await rasterizeForMediaProfile(
          _doc(profile, arabic: false, bodyLines: 60),
          rasterizer: rasterizer,
          profile: profile,
          pageLabel: (p, t) => 'Page $p/$t',
          continuationHeader: (p, t) => 'cont.',
        );
        final rasters = _rasters(out);
        expect(rasters.length, greaterThan(1), reason: 'genuinely multi-page');
        // The logo marker appears on EXACTLY one page (the first).
        expect(rasters.where(_startsWithLogo).length, 1);
        expect(_startsWithLogo(rasters.first), isTrue);
        // One feed + one cut PER page (never an extra logo boundary).
        expect(_count<PrintCutLine>(out), rasters.length);
        expect(_count<PrintFeedLine>(out), rasters.length);
      });
    });
  }

  test(
    'a no-logo fixed-media receipt is unaffected (no logo marker)',
    () async {
      final out = await rasterizeForMediaProfile(
        _doc(MediaProfile.label50x50, arabic: false, withLogo: false),
        rasterizer: rasterizer,
        profile: MediaProfile.label50x50,
      );
      expect(_rasters(out).any(_startsWithLogo), isFalse);
    },
  );

  test('a no-logo continuous English receipt stays the text path', () async {
    final out = await rasterizeForMediaProfile(
      _doc(MediaProfile.continuous80, arabic: false, withLogo: false),
      rasterizer: rasterizer,
      profile: MediaProfile.continuous80,
    );
    expect(_rasters(out), isEmpty);
  });
}
