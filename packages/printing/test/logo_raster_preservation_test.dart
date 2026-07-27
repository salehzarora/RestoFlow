import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// PRINT-BRANDING-LOGO-001 — the leading logo raster must SURVIVE text
/// rasterization: on ar/he receipts (Arabic is the default locale) and on every
/// fixed-media label, not only on continuous80 + English.

const int _logoHeight = 8;

PrintRasterImageLine _logo() => PrintRasterImageLine(
  data: Uint8List(48 * _logoHeight),
  widthBytes: 48,
  heightDots: _logoHeight,
);

PrintDocument _docWith({required bool arabic}) => PrintDocument([
  _logo(),
  const PrintFeedLine(1),
  PrintTextLine(
    arabic ? 'مطعم' : 'Restaurant',
    style: PrintLineStyle.headingLarge,
  ),
  PrintTextLine(arabic ? 'طلب 12' : 'Order 12'),
  const PrintFeedLine(3),
  const PrintCutLine(),
]);

bool _hasLogo(PrintDocument doc) => doc.lines
    .whereType<PrintRasterImageLine>()
    .any((l) => l.heightDots == _logoHeight);

void main() {
  final rasterizer = FakeReceiptRasterizer();

  test(
    'continuous80 + English (LTR) keeps the logo (text stays text)',
    () async {
      final out = await rasterizeForMediaProfile(
        _docWith(arabic: false),
        rasterizer: rasterizer,
        profile: MediaProfile.continuous80,
      );
      expect(_hasLogo(out), isTrue);
    },
  );

  test(
    'continuous80 + Arabic (RTL, rasterized) STILL keeps the logo',
    () async {
      final out = await rasterizeForMediaProfile(
        _docWith(arabic: true),
        rasterizer: rasterizer,
        profile: MediaProfile.continuous80,
      );
      // The receipt body rasterized to an image AND the logo raster survived.
      expect(_hasLogo(out), isTrue);
      expect(
        out.lines.whereType<PrintRasterImageLine>().length,
        greaterThan(1),
      );
    },
  );

  test('label50x50 (fixed) emits the logo as a leading label', () async {
    final out = await rasterizeForMediaProfile(
      _docWith(arabic: true),
      rasterizer: rasterizer,
      profile: MediaProfile.label50x50,
    );
    expect(_hasLogo(out), isTrue);
    // The logo is the FIRST line (its own leading label, before the receipt).
    expect(out.lines.first, isA<PrintRasterImageLine>());
  });

  test('label80x80 (fixed) emits the logo as a leading label', () async {
    final out = await rasterizeForMediaProfile(
      _docWith(arabic: false),
      rasterizer: rasterizer,
      profile: MediaProfile.label80x80,
    );
    expect(_hasLogo(out), isTrue);
    expect(out.lines.first, isA<PrintRasterImageLine>());
  });

  test('a no-logo doc is unaffected (no spurious raster line)', () async {
    final noLogo = PrintDocument([
      const PrintTextLine('Restaurant', style: PrintLineStyle.headingLarge),
      const PrintTextLine('Order 12'),
      const PrintFeedLine(3),
      const PrintCutLine(),
    ]);
    final out = await rasterizeForMediaProfile(
      noLogo,
      rasterizer: rasterizer,
      profile: MediaProfile.continuous80,
    );
    // English continuous stays the text path — no raster image at all.
    expect(out.lines.whereType<PrintRasterImageLine>(), isEmpty);
  });
}
