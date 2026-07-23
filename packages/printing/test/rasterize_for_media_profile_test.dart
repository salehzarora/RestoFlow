import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

/// PRINT-LAYOUT-001A (Raster geometry C + Pagination D) — rasterizeForMediaProfile
/// renders at the profile's EXACT width and paginates fixed media. Uses the
/// deterministic FakeReceiptRasterizer, so tests inspect the real produced
/// PrintDocument: page count, bytes-per-row (== width/8), ordering, feed/cut.
void main() {
  PrintDocument textDoc(List<String> lines, {List<PrintLineStyle>? styles}) =>
      PrintDocument([
        for (var i = 0; i < lines.length; i++)
          PrintTextLine(
            lines[i],
            style: styles == null ? PrintLineStyle.normal : styles[i],
          ),
      ], localeTag: 'ar'); // non-ASCII-ish tag; content forces raster anyway

  // Arabic content so the continuous path also rasterizes (needsRaster).
  List<String> arLines(int n) => [for (var i = 0; i < n; i++) 'صنف رقم $i'];

  List<PrintRasterImageLine> images(PrintDocument doc) =>
      doc.lines.whereType<PrintRasterImageLine>().toList();

  test('continuous80 => ONE image at 576 dots (72 bytes/row), feed 3, one cut', () async {
    final doc = await rasterizeForMediaProfile(
      textDoc(arLines(40)),
      rasterizer: FakeReceiptRasterizer(),
      profile: MediaProfile.continuous80,
    );
    final imgs = images(doc);
    expect(imgs, hasLength(1), reason: 'continuous roll never paginates');
    expect(imgs.single.widthBytes, 72, reason: '576 dots / 8');
    expect(
      doc.lines.whereType<PrintFeedLine>().single.lines,
      3,
      reason: 'continuous feed stays 3',
    );
    expect(doc.lines.whereType<PrintCutLine>(), hasLength(1));
  });

  test('label50x50 => raster width is 384 (48 bytes/row), NEVER 576/72', () async {
    final doc = await rasterizeForMediaProfile(
      textDoc(arLines(3)), // short => one page
      rasterizer: FakeReceiptRasterizer(),
      profile: MediaProfile.label50x50,
    );
    final imgs = images(doc);
    expect(imgs, isNotEmpty);
    for (final img in imgs) {
      expect(img.widthBytes, 48, reason: '384 dots / 8 — never a 576 canvas');
    }
    // feed comes from the profile (labels eject 2, not 3).
    expect(doc.lines.whereType<PrintFeedLine>().first.lines, 2);
  });

  test('label80x80 => raster width is 576 (72 bytes/row)', () async {
    final doc = await rasterizeForMediaProfile(
      textDoc(arLines(3)),
      rasterizer: FakeReceiptRasterizer(),
      profile: MediaProfile.label80x80,
    );
    for (final img in images(doc)) {
      expect(img.widthBytes, 72, reason: '576 dots / 8');
    }
  });

  test('a long fixed ticket paginates into multiple pages; each page is one '
      'image + feed + cut, in order', () async {
    final doc = await rasterizeForMediaProfile(
      textDoc(arLines(60)), // long => multiple 50x50 pages
      rasterizer: FakeReceiptRasterizer(dotsPerLine: 28),
      profile: MediaProfile.label50x50,
      pageLabel: (page, total) => 'ص $page/$total',
    );
    final imgs = images(doc);
    expect(imgs.length, greaterThan(1), reason: 'a long label ticket splits');
    // Structure: image, feed, cut repeated per page, in order.
    var i = 0;
    var pageCount = 0;
    while (i < doc.lines.length) {
      expect(doc.lines[i], isA<PrintRasterImageLine>());
      expect(doc.lines[i + 1], isA<PrintFeedLine>());
      expect(doc.lines[i + 2], isA<PrintCutLine>());
      i += 3;
      pageCount++;
    }
    expect(pageCount, imgs.length, reason: 'exactly image+feed+cut per page');
    // Every page renders at the 50x50 width.
    for (final img in imgs) {
      expect(img.widthBytes, 48);
    }
  });

  test('with no rasterizer a fixed profile degrades to the text doc (no crash)', () async {
    final input = textDoc(arLines(5));
    final doc = await rasterizeForMediaProfile(
      input,
      rasterizer: null,
      profile: MediaProfile.label50x50,
    );
    expect(identical(doc, input), isTrue);
  });

  test('every source line appears EXACTLY ONCE across the fixed-media pages, in '
      'order — no item/modifier/note lost or duplicated', () async {
    final fake = FakeReceiptRasterizer(dotsPerLine: 40);
    final source = [for (var i = 0; i < 25; i++) 'صنف-$i'];
    final doc = await rasterizeForMediaProfile(
      textDoc(source),
      rasterizer: fake,
      profile: MediaProfile.label50x50,
      pageLabel: (p, t) => 'PGLABEL',
      continuationHeader: (p, t) => 'CONTHDR',
    );
    expect(images(doc).length, greaterThan(1), reason: 'a long ticket splits');
    // Reconstruct the source lines from what each page ACTUALLY rendered
    // (the fake records one rasterize request per page), dropping the added
    // page-number + continuation-header lines.
    final rendered = <String>[
      for (final req in fake.requests)
        for (final line in req.lines)
          if (line != 'PGLABEL' && line != 'CONTHDR') line,
    ];
    expect(
      rendered,
      source,
      reason: 'every line once, in order, none dropped/duplicated',
    );
    // The final source line is present exactly once (no clipped tail).
    expect(rendered.where((l) => l == source.last), hasLength(1));
  });
}
