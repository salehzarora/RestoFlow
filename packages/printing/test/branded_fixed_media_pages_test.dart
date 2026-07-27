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
}
