import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

/// PRINT-LAYOUT-001A (section 3) — REAL raster geometry: renders through the
/// actual dart:ui FlutterReceiptRasterizer + rasterizeForMediaProfile and asserts
/// the produced bitmaps' exact width, page height <= media height, and content
/// bounds inside the safe margins (via measureRasterInkBounds). Not goldens —
/// dimensions, bytes-per-row, content bounds, and page counts.
void main() {
  // dart:ui Picture.toImage needs an initialized binding (no widget tree).
  TestWidgetsFlutterBinding.ensureInitialized();

  const rasterizer = FlutterReceiptRasterizer();

  PrintDocument doc(List<String> lines, {List<PrintLineStyle>? styles}) =>
      PrintDocument(<PrintLine>[
        for (var i = 0; i < lines.length; i++)
          PrintTextLine(
            lines[i],
            style: styles == null ? PrintLineStyle.normal : styles[i],
          ),
      ], localeTag: 'ar');

  Future<List<PrintRasterImageLine>> render(
    PrintDocument d,
    MediaProfile profile,
  ) async {
    final out = await rasterizeForMediaProfile(
      d,
      rasterizer: rasterizer,
      profile: profile,
      pageLabel: (page, total) => 'p$page/$total',
      continuationHeader: (page, total) => 'cont $page',
    );
    return out.lines.whereType<PrintRasterImageLine>().toList(growable: false);
  }

  /// Every generated PAGE renders at the profile's exact width, never exceeds the
  /// media height, and keeps its ink inside the safe margins.
  void assertPage(PrintRasterImageLine img, MediaProfile profile) {
    expect(
      img.widthBytes,
      profile.widthBytes,
      reason: 'exact ${profile.widthDots}-dot width',
    );
    expect(
      img.heightDots,
      lessThanOrEqualTo(profile.mediaHeightDots),
      reason: 'no page exceeds the ${profile.mediaHeightDots}-dot media height',
    );
    final b = measureRasterInkBounds(
      data: img.data,
      widthBytes: img.widthBytes,
      heightDots: img.heightDots,
    );
    if (b.hasInk) {
      expect(b.left, greaterThanOrEqualTo(profile.safeLeftDots));
      expect(
        b.right,
        lessThanOrEqualTo(profile.widthDots - profile.safeRightDots),
      );
      expect(b.top, greaterThanOrEqualTo(0));
      expect(b.bottom, lessThanOrEqualTo(img.heightDots - 1));
    }
  }

  // Arabic / Hebrew / English content (RTL vs LTR base direction is derived).
  const ar = ['فلافل مع طحينة', 'حمص كبير', 'شاورما دجاج'];
  const he = ['פלאפל עם טחינה', 'חומוס גדול', 'שווארמה עוף'];
  const en = ['Falafel with tahini', 'Large hummus', 'Chicken shawarma'];

  test(
    'A. label50x50 RTL: exact 384 dots, page <= 400, ink in safe bounds',
    () async {
      final imgs = await render(doc(ar), MediaProfile.label50x50);
      expect(imgs, isNotEmpty);
      for (final img in imgs) {
        expect(img.widthBytes, 48); // 384 / 8
        assertPage(img, MediaProfile.label50x50);
      }
    },
  );

  test(
    'B. label50x50 LTR: exact 384 dots, page <= 400, ink in safe bounds',
    () async {
      for (final img in await render(doc(en), MediaProfile.label50x50)) {
        expect(img.widthBytes, 48);
        assertPage(img, MediaProfile.label50x50);
      }
    },
  );

  test(
    'C. label80x80 RTL: exact 576 dots, page <= 640, ink in safe bounds',
    () async {
      final imgs = await render(doc(he), MediaProfile.label80x80);
      expect(imgs, isNotEmpty);
      for (final img in imgs) {
        expect(img.widthBytes, 72); // 576 / 8
        assertPage(img, MediaProfile.label80x80);
      }
    },
  );

  test(
    'D. label80x80 LTR: exact 576 dots, page <= 640, ink in safe bounds',
    () async {
      for (final img in await render(doc(en), MediaProfile.label80x80)) {
        expect(img.widthBytes, 72);
        assertPage(img, MediaProfile.label80x80);
      }
    },
  );

  test('E. a long kitchen ticket paginates; every page fits the 50x50 media '
      'and stays in bounds', () async {
    // ~30 item lines -> multiple 50x50 pages.
    final lines = <String>[for (var i = 0; i < 30; i++) 'صنف $i دجاج مشوي'];
    final styles = [for (var i = 0; i < 30; i++) PrintLineStyle.item];
    final imgs = await render(
      doc(lines, styles: styles),
      MediaProfile.label50x50,
    );
    expect(imgs.length, greaterThan(1), reason: 'a long fixed ticket splits');
    for (final img in imgs) {
      expect(img.widthBytes, 48);
      assertPage(img, MediaProfile.label50x50);
    }
  });

  test(
    'F. a long customer receipt paginates on 80x80; every page fits + bounds',
    () async {
      final lines = <String>[for (var i = 0; i < 40; i++) 'منتج $i مع إضافات'];
      final imgs = await render(doc(lines), MediaProfile.label80x80);
      expect(imgs.length, greaterThan(1));
      for (final img in imgs) {
        expect(img.widthBytes, 72);
        assertPage(img, MediaProfile.label80x80);
      }
    },
  );

  test('G. the diagnostic renders at the profile width — 50x50 is NEVER 576; '
      '80x80 is 576; content stays in bounds', () async {
    const labels = MediaProfileDiagnosticLabels(
      heading: 'DIAG',
      profileName: 'label',
      widthLine: 'W',
      heightLine: 'H',
      topSafe: 'TOP',
      bottomSafe: 'BOTTOM',
    );
    final small = await render(
      buildMediaProfileDiagnosticDocument(
        profile: MediaProfile.label50x50,
        labels: labels,
      ),
      MediaProfile.label50x50,
    );
    expect(small, isNotEmpty);
    for (final img in small) {
      expect(img.widthBytes, 48, reason: '50x50 diagnostic is 384, never 576');
      assertPage(img, MediaProfile.label50x50);
    }
    final big = await render(
      buildMediaProfileDiagnosticDocument(
        profile: MediaProfile.label80x80,
        labels: labels,
      ),
      MediaProfile.label80x80,
    );
    for (final img in big) {
      expect(img.widthBytes, 72, reason: '80x80 diagnostic is 576');
      assertPage(img, MediaProfile.label80x80);
    }
  });

  test('H. continuous80 stays ONE 576-dot image and does NOT paginate as fixed '
      'media (legacy compatible)', () async {
    final imgs = await render(doc(ar), MediaProfile.continuous80);
    expect(imgs, hasLength(1), reason: 'a continuous roll never paginates');
    expect(imgs.single.widthBytes, 72); // 576 / 8
    // No media-height bound on a roll: the single tall image is allowed.
    expect(imgs.single.heightDots, greaterThan(0));
  });

  // PRINT-LAYOUT-001B: the FULL new hierarchy — a brand heading, a secondary
  // order reference, centered meta, a separator, quantity-leading items with a
  // modifier + a note, an inter-item spacer, and a strong total — with the
  // bigger 001B fonts, on BOTH fixed labels, RTL + LTR, never clips.
  const fullStyles = <PrintLineStyle>[
    PrintLineStyle.headingLarge, // brand
    PrintLineStyle.subheading, // order reference
    PrintLineStyle.separator,
    PrintLineStyle.centered, // meta
    PrintLineStyle.item, // qty-leading item
    PrintLineStyle.sub, // modifier
    PrintLineStyle.note, // item note
    PrintLineStyle.spacer, // blank gap between items
    PrintLineStyle.item, // second item
    PrintLineStyle.separator,
    PrintLineStyle.total, // strong total
  ];
  const fullAr = <String>[
    'مطعم الاختبار',
    'طلب #A17',
    '----',
    'صالة',
    '2 × فلافل',
    '+ طحينة إضافية',
    '» ملاحظة: حار',
    '',
    '1 × حمص',
    '----',
    'الإجمالي        ₪42',
  ];
  const fullEn = <String>[
    'Test Restaurant',
    'Order #A17',
    '----',
    'Dine-in',
    '2 × Falafel',
    '+ Extra tahini',
    '» Note: spicy',
    '',
    '1 × Hummus',
    '----',
    'TOTAL           42.00',
  ];

  for (final profile in const [
    MediaProfile.label50x50,
    MediaProfile.label80x80,
  ]) {
    for (final lang in const ['RTL', 'LTR']) {
      test('I. 001B hierarchy on ${profile.id.name} ($lang): every new style '
          'renders with the bigger fonts and no page clips', () async {
        final lines = lang == 'RTL' ? fullAr : fullEn;
        final imgs = await render(doc(lines, styles: fullStyles), profile);
        expect(imgs, isNotEmpty);
        for (final img in imgs) {
          expect(img.widthBytes, profile.widthBytes);
          assertPage(img, profile);
        }
      });
    }
  }

  test('J. 001B typography is PROFILE-AWARE — the standard (80x80) brand hero '
      'renders TALLER than the compact (50x50) hero', () async {
    final measurer = rasterizer as RasterLineMeasurer;
    Future<int> heroRows(MediaProfile p) async {
      final rows = await measurer.measureLineRows(
        ReceiptRasterRequest(
          lines: const ['مطعم'],
          styles: const [PrintLineStyle.headingLarge],
          widthDots: p.widthDots,
          direction: ReceiptTextDirection.rtl,
          localeTag: 'ar',
          fontScale: p.fontScale,
          lineSpacing: p.lineSpacing,
          safeLeftDots: p.safeLeftDots,
          safeRightDots: p.safeRightDots,
          typography: PrintTypography.forProfile(p),
        ),
      );
      return rows.single;
    }

    final compactHero = await heroRows(MediaProfile.label50x50);
    final standardHero = await heroRows(MediaProfile.label80x80);
    expect(
      standardHero,
      greaterThan(compactHero),
      reason: '80x80 standard hero taller than 50x50 compact hero',
    );
  });
}
