import 'dart:math' as math;
import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// PRINT-BRANDING-LOGO-001 §18 — BRANDED FIXED-MEDIA BYTE/PAGE TESTS.
///
/// Proves the F1 fix directly on the encoded page structure, for en/ar/he and
/// both fixed labels:
///   * the logo is COMPOSED into the SAME first physical page as the receipt
///     title/text — a single raster image, NOT a dedicated logo label;
///   * exactly ONE image + ONE feed + ONE cut per physical page (a dedicated
///     logo label would be an extra image+feed+cut → images/cuts == pages + 1);
///   * the logo sits at the TOP of page one, whole (uncropped), above a bounded
///     blank gap band, above the text (so at minimum the title shares page one);
///   * on a multi-page run the logo appears ONLY on page one;
///   * a CONTINUOUS roll keeps the logo above the receipt with ONE cut total
///     (no cut between the logo and the receipt).
///
/// The deterministic [FakeReceiptRasterizer] fills text rows with 0x55; the logo
/// fixture is filled with 0xFF and the gap band is 0x00, so the three regions are
/// distinguishable at the byte level without any dart:ui rendering.

const int _logoFill = 0xFF;
const int _logoHeightDots = 48;

PrintRasterImageLine _logoFor(MediaProfile profile) => PrintRasterImageLine(
  data: Uint8List(profile.widthBytes * _logoHeightDots)
    ..fillRange(0, profile.widthBytes * _logoHeightDots, _logoFill),
  widthBytes: profile.widthBytes,
  heightDots: _logoHeightDots,
);

/// A branded receipt: a leading logo raster (the customer-receipt header image)
/// followed by ~14 pre-formatted text lines. Tall enough to page-break on 50x50.
PrintDocument _brandedReceipt(String localeTag, List<String> lines) {
  final logo = _logoFor(
    MediaProfile.continuous80,
  ); // width fixed per-profile below.
  return PrintDocument(<PrintLine>[
    logo,
    const PrintFeedLine(1),
    for (var i = 0; i < lines.length; i++)
      PrintTextLine(
        lines[i],
        style: i == 0 ? PrintLineStyle.headingLarge : PrintLineStyle.normal,
      ),
    const PrintFeedLine(3),
    const PrintCutLine(),
  ], localeTag: localeTag);
}

/// The same doc but with the logo sized for [profile] (width must match the page
/// or the composer would drop it — this proves the real composed path).
PrintDocument _brandedFor(
  MediaProfile profile,
  String localeTag,
  List<String> lines,
) => PrintDocument(<PrintLine>[
  _logoFor(profile),
  const PrintFeedLine(1),
  for (var i = 0; i < lines.length; i++)
    PrintTextLine(
      lines[i],
      style: i == 0 ? PrintLineStyle.headingLarge : PrintLineStyle.normal,
    ),
  const PrintFeedLine(3),
  const PrintCutLine(),
], localeTag: localeTag);

const _locales = <String, List<String>>{
  'en': <String>[
    'THE CORNER BISTRO',
    'Order #A-1042',
    'Falafel Plate 32.00',
    'Extra tahini 3.00',
    'no onions',
    'Mint Lemonade 24.00',
    'Baklava 14.00',
    'Coffee 9.00',
    'Subtotal 82.00',
    'VAT 17% 13.94',
    'TOTAL 95.94',
    'Cash 100.00',
    'Change 4.06',
    'Thank you!',
  ],
  'ar': <String>[
    'مطعم الزاوية',
    'طلب #A-1042',
    'فلافل ₪32.00',
    'طحينة ₪3.00',
    'بدون بصل',
    'ليموناضة ₪24.00',
    'بقلاوة ₪14.00',
    'قهوة ₪9.00',
    'المجموع ₪82.00',
    'ضريبة ₪13.94',
    'الإجمالي ₪95.94',
    'نقداً ₪100.00',
    'الباقي ₪4.06',
    'شكراً',
  ],
  'he': <String>[
    'מסעדת הפינה',
    'הזמנה #A-1042',
    'פלאפל ₪32.00',
    'טחינה ₪3.00',
    'בלי בצל',
    'לימונדה ₪24.00',
    'בקלאווה ₪14.00',
    'קפה ₪9.00',
    'סכום ביניים ₪82.00',
    'מעמ ₪13.94',
    'סהכ ₪95.94',
    'מזומן ₪100.00',
    'עודף ₪4.06',
    'תודה',
  ],
};

const _fixedProfiles = <String, MediaProfile>{
  'label50x50': MediaProfile.label50x50,
  'label80x80': MediaProfile.label80x80,
};

/// The [i]-th raster row of [image] (widthBytes bytes).
List<int> _row(PrintRasterImageLine image, int i) =>
    image.data.sublist(i * image.widthBytes, (i + 1) * image.widthBytes);

bool _rowAll(PrintRasterImageLine image, int i, int value) =>
    _row(image, i).every((b) => b == value);

List<PrintRasterImageLine> _images(PrintDocument doc) =>
    doc.lines.whereType<PrintRasterImageLine>().toList(growable: false);

int _count<T>(PrintDocument doc) => doc.lines.whereType<T>().length;

Future<PrintDocument> _layout(PrintDocument doc, MediaProfile profile) =>
    rasterizeForMediaProfile(
      doc,
      rasterizer: FakeReceiptRasterizer(),
      profile: profile,
      pageLabel: (p, t) => 'PAGE $p/$t',
      continuationHeader: (p, t) => 'CONT $p',
    );

void main() {
  group('§18 branded fixed-media pages', () {
    for (final loc in _locales.entries) {
      for (final pf in _fixedProfiles.entries) {
        final title = '${loc.key} / ${pf.key}';
        test('$title composes the logo into page one only', () async {
          final profile = pf.value;
          final doc = _brandedFor(profile, loc.key, loc.value);
          final out = await _layout(doc, profile);

          final pages = _count<PrintCutLine>(out);
          final feeds = _count<PrintFeedLine>(out);
          final images = _images(out);

          // One image + one feed + one cut per physical page — NO dedicated
          // logo label (which would push images/cuts/feeds to pages + 1).
          expect(pages, greaterThanOrEqualTo(1), reason: title);
          expect(images.length, pages, reason: '$title one image per page');
          expect(feeds, pages, reason: '$title one feed per page');
          for (final line in out.lines.whereType<PrintFeedLine>()) {
            expect(line.lines, profile.feedLines, reason: '$title feed size');
          }

          // Page one: the WHOLE logo (uncropped, 0xFF) sits at the top.
          final first = images.first;
          for (var r = 0; r < _logoHeightDots; r++) {
            expect(
              _rowAll(first, r, _logoFill),
              isTrue,
              reason: '$title logo row $r must be intact on page one',
            );
          }
          // The logo is not cropped/stretched: its full height is present and the
          // very next row is NOT logo ink (the gap begins).
          expect(
            _rowAll(first, _logoHeightDots, _logoFill),
            isFalse,
            reason: '$title logo occupies exactly its own height (no stretch)',
          );

          // A bounded blank GAP band (0x00) follows the logo, then TEXT — so the
          // title shares page one with the logo (never a logo-only page).
          var gap = 0;
          while (_rowAll(first, _logoHeightDots + gap, 0x00)) {
            gap++;
          }
          expect(
            gap,
            greaterThanOrEqualTo(6),
            reason: '$title bounded gap band',
          );
          expect(
            _logoHeightDots + gap,
            lessThan(first.heightDots),
            reason: '$title text (title) shares page one below the logo',
          );

          // The logo appears ONLY on page one — later pages never start with an
          // all-0xFF (logo) row.
          for (var p = 1; p < images.length; p++) {
            expect(
              _rowAll(images[p], 0, _logoFill),
              isFalse,
              reason: '$title logo must not repeat on page ${p + 1}',
            );
          }
        });
      }
    }

    // ---- §18b: a TALL logo must never land ALONE on page one ---------------
    // A logo whose block fits `pageBudget` but not the planner's effective
    // per-page budget (pageBudget - reserved-for-page-number) would, under a
    // naive guard, be flushed alone onto page one with the title bumped to page
    // two — a near-dedicated logo page. The fix: it must be OMITTED (text-only)
    // instead. This exercises the exact isolation window on label50x50.
    PrintDocument brandedTall(int logoHeightDots, int lineCount) {
      const profile = MediaProfile.label50x50;
      final logo = PrintRasterImageLine(
        data: Uint8List(profile.widthBytes * logoHeightDots)
          ..fillRange(0, profile.widthBytes * logoHeightDots, _logoFill),
        widthBytes: profile.widthBytes,
        heightDots: logoHeightDots,
      );
      return PrintDocument(<PrintLine>[
        logo,
        for (var i = 0; i < lineCount; i++)
          PrintTextLine(
            i == 0 ? 'HEADER' : 'item $i',
            // Distinct blocks (item), so the planner can split logo from title.
            style: i == 0 ? PrintLineStyle.headingLarge : PrintLineStyle.item,
          ),
        const PrintFeedLine(2),
        const PrintCutLine(),
      ], localeTag: 'en');
    }

    Future<PrintDocument> layoutTall(PrintDocument doc) =>
        rasterizeForMediaProfile(
          doc,
          rasterizer: FakeReceiptRasterizer(dotsPerLine: 70),
          profile: MediaProfile.label50x50,
          pageLabel: (p, t) => 'PAGE $p/$t',
          continuationHeader: (p, t) => 'CONT $p',
        );

    test(
      'a tall logo that cannot share page one is OMITTED, never isolated',
      () async {
        const profile = MediaProfile.label50x50;
        const tallLogo = 144; // == §14 max height for a 384-dot label.
        expect(
          tallLogo,
          lessThanOrEqualTo(
            ReceiptLogoBounds.forProfile(profile).maxHeightDots,
          ),
          reason: 'the fixture logo stays within the §14 bounds',
        );
        // Document the regime: a NAIVE guard (logo + title <= pageBudget) WOULD
        // have composed this logo — so omission here is the fix, not a skip.
        final tail = bottomSafeTailRows(profile);
        final gap = math.max(6, tail ~/ 2);
        final pageBudget = profile.printableHeightDots - tail;
        const titleRows = 70; // the fake's dotsPerLine.
        expect(
          tallLogo + gap + titleRows,
          lessThanOrEqualTo(pageBudget),
          reason: 'the naive pageBudget guard would have (wrongly) composed it',
        );

        final out = await layoutTall(brandedTall(tallLogo, 6));
        final pages = _count<PrintCutLine>(out);
        final images = _images(out);
        expect(
          pages,
          greaterThanOrEqualTo(2),
          reason: 'the receipt is multi-page',
        );
        expect(
          images.length,
          pages,
          reason: 'one image per page, no extra label',
        );
        // The logo is fully OMITTED: no page begins with the 0xFF logo band, so
        // it never prints alone and never gets its own label/page.
        for (var p = 0; p < images.length; p++) {
          expect(
            _rowAll(images[p], 0, _logoFill),
            isFalse,
            reason: 'no logo band on page ${p + 1} (omitted, text-only)',
          );
        }
      },
    );

    test(
      'a small logo on the SAME multi-page receipt still composes on page one',
      () async {
        final out = await layoutTall(brandedTall(24, 6));
        final images = _images(out);
        expect(_count<PrintCutLine>(out), greaterThanOrEqualTo(2));
        // Composed: page one starts with the logo band and carries text below it.
        expect(
          _rowAll(images.first, 0, _logoFill),
          isTrue,
          reason: 'logo on page one',
        );
        expect(
          images.first.heightDots,
          greaterThan(24),
          reason: 'text (title) shares page one below the small logo',
        );
        // And the logo is only on page one.
        for (var p = 1; p < images.length; p++) {
          expect(_rowAll(images[p], 0, _logoFill), isFalse);
        }
      },
    );

    test(
      'a continuous roll keeps the logo above the receipt with ONE cut',
      () async {
        final doc = _brandedReceipt('ar', _locales['ar']!);
        final out = await _layout(doc, MediaProfile.continuous80);
        // Roll (ar => raster path): the logo raster stays ABOVE the text raster
        // with exactly ONE cut — and that cut is the LAST line, so the paper is
        // never cut BETWEEN the logo and the receipt (no separate logo label).
        expect(
          _count<PrintCutLine>(out),
          1,
          reason: 'exactly one cut on a roll',
        );
        expect(out.lines.last, isA<PrintCutLine>(), reason: 'the cut is last');
        final images = _images(out);
        expect(images.length, 2, reason: 'logo raster + receipt raster');
        // The first image is the whole logo (uncropped 0xFF); the second is text.
        expect(_rowAll(images.first, 0, _logoFill), isTrue);
        expect(images.first.heightDots, _logoHeightDots);
        expect(_rowAll(images.last, 0, _logoFill), isFalse);
      },
    );

    test(
      'a logo whose width mismatches the page is dropped, not corrupt',
      () async {
        // Defensive: a logo built at the wrong width must be omitted (text-only),
        // never composed into a mis-sized/corrupt image.
        final wrongWidthLogo = PrintRasterImageLine(
          data: Uint8List(MediaProfile.label50x50.widthBytes * 24),
          widthBytes:
              MediaProfile.label50x50.widthBytes, // 48, != label80x80 (72)
          heightDots: 24,
        );
        final doc = PrintDocument(<PrintLine>[
          wrongWidthLogo,
          const PrintTextLine('HEADER', style: PrintLineStyle.headingLarge),
          const PrintTextLine('body'),
          const PrintCutLine(),
        ], localeTag: 'en');
        final out = await _layout(doc, MediaProfile.label80x80);
        // No 0xFF logo band leaks in, and every image is the page width (72 bytes).
        for (final img in _images(out)) {
          expect(img.widthBytes, MediaProfile.label80x80.widthBytes);
        }
      },
    );
  });

  // ---- §12: exhaustive fixed-media SHARING-THRESHOLD boundaries -------------
  // The share/omit boundary is derived at RUNTIME from the profile geometry +
  // the fake line height, so these stay correct if typography changes. For a
  // multi-page ticket the planner packs page one against `pageBudget - 2*rowH`
  // (it reserves two rows for the page-number/continuation line), so the logo +
  // title share page one iff `logoHeight + gap + rowH <= pageBudget - 2*rowH`.
  group('§12 sharing-threshold boundaries (en/ar/he)', () {
    int gapFor(MediaProfile p) => math.max(6, bottomSafeTailRows(p) ~/ 2);
    int budgetFor(MediaProfile p) =>
        p.printableHeightDots - bottomSafeTailRows(p);
    // The tallest logo that still SHARES page one with the title, given row [d].
    int thresholdHeight(MediaProfile p, int d) =>
        budgetFor(p) - 3 * d - gapFor(p);

    PrintRasterImageLine logo(MediaProfile p, int h) => PrintRasterImageLine(
      data: Uint8List(p.widthBytes * h)
        ..fillRange(0, p.widthBytes * h, _logoFill),
      widthBytes: p.widthBytes,
      heightDots: h,
    );

    PrintDocument tallDoc(
      MediaProfile p,
      String loc,
      String title,
      int logoH,
      int lines,
    ) => PrintDocument(<PrintLine>[
      logo(p, logoH),
      PrintTextLine(title, style: PrintLineStyle.headingLarge),
      for (var i = 1; i < lines; i++)
        PrintTextLine('$loc row $i', style: PrintLineStyle.item),
      const PrintFeedLine(2),
      const PrintCutLine(),
    ], localeTag: loc);

    Future<PrintDocument> layoutD(MediaProfile p, int d, PrintDocument doc) =>
        rasterizeForMediaProfile(
          doc,
          rasterizer: FakeReceiptRasterizer(dotsPerLine: d),
          profile: p,
          pageLabel: (a, b) => 'P$a/$b',
          continuationHeader: (a, b) => 'C$a',
        );

    bool logoOnPageOne(PrintDocument out) {
      final im = _images(out);
      return im.isNotEmpty && _rowAll(im.first, 0, _logoFill);
    }

    bool anyLogoBand(PrintDocument out) =>
        _images(out).any((i) => _rowAll(i, 0, _logoFill));

    void assertShared(PrintDocument out, MediaProfile p, int logoH) {
      final images = _images(out);
      final pages = _count<PrintCutLine>(out);
      expect(logoOnPageOne(out), isTrue, reason: 'logo shares page one');
      expect(images.length, pages, reason: 'one image/feed/cut per page');
      expect(_count<PrintFeedLine>(out), pages);
      // Uncropped: the whole logo is intact, and the row after it is not logo ink.
      for (var r = 0; r < logoH; r++) {
        expect(_rowAll(images.first, r, _logoFill), isTrue);
      }
      expect(_rowAll(images.first, logoH, _logoFill), isFalse);
      // The title shares page one below the logo (never a logo-only page).
      expect(images.first.heightDots, greaterThan(logoH + gapFor(p)));
      // The logo appears ONLY on page one.
      for (var i = 1; i < images.length; i++) {
        expect(_rowAll(images[i], 0, _logoFill), isFalse);
      }
    }

    void assertOmitted(PrintDocument out) {
      final pages = _count<PrintCutLine>(out);
      expect(anyLogoBand(out), isFalse, reason: 'logo omitted, never alone');
      expect(_images(out).length, pages, reason: 'one image/feed/cut per page');
      expect(_count<PrintFeedLine>(out), pages);
    }

    final configs = [
      (profile: MediaProfile.label50x50, thD: 80, thN: 6, maxD: 40, maxN: 10),
      (profile: MediaProfile.label80x80, thD: 120, thN: 6, maxD: 60, maxN: 10),
    ];
    const titles = {
      'en': 'CORNER BISTRO',
      'ar': 'مطعم الزاوية',
      'he': 'מסעדת הפינה',
    };

    for (final cfg in configs) {
      final p = cfg.profile;
      final name = p.id.name;
      final threshold = thresholdHeight(p, cfg.thD);
      final maxH = ReceiptLogoBounds.forProfile(p).maxHeightDots;

      test(
        '$name: the boundary fixture is valid (in §14 bounds, multi-page)',
        () {
          expect(threshold, greaterThan(32));
          expect(
            threshold + 1,
            lessThanOrEqualTo(maxH),
            reason: 'the above-threshold logo stays within the §14 max height',
          );
          expect(
            cfg.thN * cfg.thD,
            greaterThan(budgetFor(p)),
            reason: 'multipage',
          );
        },
      );

      for (final loc in titles.entries) {
        test('$name/${loc.key}: one row BELOW threshold shares', () async {
          final out = await layoutD(
            p,
            cfg.thD,
            tallDoc(p, loc.key, loc.value, threshold - 1, cfg.thN),
          );
          assertShared(out, p, threshold - 1);
        });

        test('$name/${loc.key}: EXACTLY at threshold shares', () async {
          final out = await layoutD(
            p,
            cfg.thD,
            tallDoc(p, loc.key, loc.value, threshold, cfg.thN),
          );
          assertShared(out, p, threshold);
        });

        test('$name/${loc.key}: one row ABOVE threshold is OMITTED', () async {
          final out = await layoutD(
            p,
            cfg.thD,
            tallDoc(p, loc.key, loc.value, threshold + 1, cfg.thN),
          );
          assertOmitted(out);
        });

        test(
          '$name/${loc.key}: the MAXIMUM §14 logo ($maxH) shares, uncropped',
          () async {
            final out = await layoutD(
              p,
              cfg.maxD,
              tallDoc(p, loc.key, loc.value, maxH, cfg.maxN),
            );
            assertShared(out, p, maxH);
          },
        );
      }
    }
  });
}
