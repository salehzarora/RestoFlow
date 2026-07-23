import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

/// PRINT-LAYOUT-001 — the pure page planner + ink-bounds helper.
void main() {
  group('planPrintPages', () {
    List<int> flatten(List<PrintPagePlan> pages) =>
        [for (final p in pages) ...p.lineIndexes];

    test('continuous (budget 0) => exactly one page with every line', () {
      final pages = planPrintPages(
        lineHeights: [24, 24, 24, 24, 24],
        maxPageRows: 0,
      );
      expect(pages, hasLength(1));
      expect(pages.single.lineIndexes, [0, 1, 2, 3, 4]);
    });

    test('content that fits one page is never split or numbered', () {
      final pages = planPrintPages(
        lineHeights: [24, 24, 24], // 72 total
        maxPageRows: 100,
      );
      expect(pages, hasLength(1));
      expect(pages.single.lineIndexes, [0, 1, 2]);
    });

    test('a long ticket splits into multiple pages; every line appears exactly '
        'once, in order', () {
      final heights = List<int>.filled(10, 30); // 300 rows total
      final pages = planPrintPages(lineHeights: heights, maxPageRows: 100);
      expect(pages.length, greaterThan(1));
      final all = flatten(pages);
      expect(all, List<int>.generate(10, (i) => i), reason: 'order preserved');
      expect(all.toSet(), hasLength(10), reason: 'no duplicates, none dropped');
      // No page exceeds the budget.
      for (final p in pages) {
        final rows = p.lineIndexes.fold<int>(0, (s, i) => s + heights[i]);
        expect(rows, lessThanOrEqualTo(100));
      }
    });

    test('a keep-together block is not split across pages when it fits a page', () {
      // 3 blocks of {item(30) + 2 mods(20,20)} = 70 rows each; page budget 100.
      final heights = <int>[30, 20, 20, 30, 20, 20, 30, 20, 20];
      final blockStarts = {0, 3, 6};
      final pages = planPrintPages(
        lineHeights: heights,
        maxPageRows: 100,
        blockStartAt: blockStarts,
      );
      // Each 70-row block must stay whole (never split): each page holds exactly
      // one block (two blocks = 140 > 100).
      for (final p in pages) {
        // A page must contain complete blocks only: it never starts mid-block.
        expect(blockStarts.contains(p.lineIndexes.first), isTrue);
        // And it never ends leaving a block's tail for the next page.
        final last = p.lineIndexes.last;
        final endsBlock = last == heights.length - 1 || blockStarts.contains(last + 1);
        expect(endsBlock, isTrue, reason: 'block kept whole');
      }
      expect(flatten(pages), List<int>.generate(9, (i) => i));
    });

    test('a block taller than a page is split line-by-line (never lost)', () {
      // One block of 5 lines * 30 = 150 rows > page 100.
      final heights = List<int>.filled(5, 30);
      final pages = planPrintPages(
        lineHeights: heights,
        maxPageRows: 100,
        blockStartAt: {0},
      );
      expect(pages.length, greaterThan(1));
      expect(flatten(pages), [0, 1, 2, 3, 4]);
    });

    test('reserved rows shrink the usable budget on multi-page output', () {
      final heights = List<int>.filled(6, 30); // 180 total
      final withReserve = planPrintPages(
        lineHeights: heights,
        maxPageRows: 100,
        reservedRowsPerPage: 40, // usable 60 => 2 lines/page
      );
      for (final p in withReserve) {
        final rows = p.lineIndexes.fold<int>(0, (s, i) => s + heights[i]);
        expect(rows, lessThanOrEqualTo(60));
      }
      expect(withReserve.length, greaterThanOrEqualTo(3));
    });

    test('empty input => no pages', () {
      expect(planPrintPages(lineHeights: const [], maxPageRows: 100), isEmpty);
    });
  });

  group('measureRasterInkBounds', () {
    test('all-white => no ink', () {
      final data = Uint8List(6 * 4); // 48 dots wide, 4 rows
      final b = measureRasterInkBounds(data: data, widthBytes: 6, heightDots: 4);
      expect(b.hasInk, isFalse);
      expect(b.left, -1);
    });

    test('a single black dot is located exactly', () {
      // 16 dots wide (2 bytes), 3 rows. Set dot at (x=10, y=1).
      final data = Uint8List(2 * 3);
      // x=10 -> byte 1, bit index 2 (0x80>>2 = 0x20).
      data[1 * 2 + 1] = 0x20;
      final b = measureRasterInkBounds(data: data, widthBytes: 2, heightDots: 3);
      expect(b.hasInk, isTrue);
      expect(b.left, 10);
      expect(b.right, 10);
      expect(b.top, 1);
      expect(b.bottom, 1);
    });

    test('bounds span the inked region and prove no bottom clip / left inset', () {
      // 24 dots wide (3 bytes), 5 rows. Ink from x=3..20, y=1..3.
      const widthBytes = 3, height = 5;
      final data = Uint8List(widthBytes * height);
      for (var y = 1; y <= 3; y++) {
        for (var x = 3; x <= 20; x++) {
          data[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
      final b = measureRasterInkBounds(
        data: data,
        widthBytes: widthBytes,
        heightDots: height,
      );
      expect(b.left, 3);
      expect(b.right, 20);
      expect(b.top, 1);
      expect(b.bottom, 3);
      // Safe-margin style assertions a page-bounds test would make:
      expect(b.left, greaterThanOrEqualTo(2)); // left safe margin
      expect(b.right, lessThanOrEqualTo(24 - 2)); // right safe margin
      expect(b.bottom, lessThanOrEqualTo(height - 1)); // nothing past the page
    });
  });
}
