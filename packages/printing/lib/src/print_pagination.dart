/// PRINT-LAYOUT-001 — a PURE, deterministic page-break planner for fixed-media
/// (label) printing. It contains no dart:ui and no rendering: given each line's
/// rendered height in dots and the page budget, it decides which source lines go
/// on which page so nothing runs off the bottom.
///
/// Rules:
///  * A CONTINUOUS profile (page budget <= 0) returns exactly one page.
///  * Content that fits in one page (before reserving header/footer rows) returns
///    exactly one page — a short ticket is never needlessly split or page-numbered.
///  * Otherwise it packs greedily, keeping each keep-together BLOCK (an item plus
///    its modifiers/notes) on one page when the whole block fits a fresh page;
///    a block that alone exceeds a page is split line-by-line; a single line
///    taller than the page is placed alone (it cannot be split further).
library;

/// One planned page: the ordered source line indices it carries.
class PrintPagePlan {
  const PrintPagePlan(this.lineIndexes);

  /// Indices into the original line list, in print order, for this page.
  final List<int> lineIndexes;

  int get lineCount => lineIndexes.length;
}

/// Partition [lineHeights] (rows per line) into pages of at most [maxPageRows]
/// rows each.
///
/// [blockStartAt] marks the indices that BEGIN a keep-together block; every line
/// from one block-start up to (but excluding) the next belongs to that block.
/// When empty, every line is its own block.
///
/// [reservedRowsPerPage] is subtracted from [maxPageRows] on multi-page output to
/// leave room for a page-number / continuation line the caller adds to each page;
/// it is ignored when the whole ticket fits one page.
List<PrintPagePlan> planPrintPages({
  required List<int> lineHeights,
  required int maxPageRows,
  Set<int> blockStartAt = const <int>{},
  int reservedRowsPerPage = 0,
}) {
  final n = lineHeights.length;
  if (n == 0) return const <PrintPagePlan>[];

  // Continuous roll (no page bound) => everything on one page.
  if (maxPageRows <= 0) {
    return <PrintPagePlan>[
      PrintPagePlan(List<int>.generate(n, (i) => i, growable: false)),
    ];
  }

  var total = 0;
  for (final h in lineHeights) {
    total += h;
  }
  // Fits one page as-is => a single, un-numbered page.
  if (total <= maxPageRows) {
    return <PrintPagePlan>[
      PrintPagePlan(List<int>.generate(n, (i) => i, growable: false)),
    ];
  }

  // Multi-page: reserve room for the per-page header/footer line(s).
  final budget = maxPageRows - reservedRowsPerPage;
  final effective = budget > 0 ? budget : maxPageRows;

  final pages = <PrintPagePlan>[];
  var current = <int>[];
  var currentRows = 0;

  void flush() {
    if (current.isNotEmpty) {
      pages.add(PrintPagePlan(current));
      current = <int>[];
      currentRows = 0;
    }
  }

  var i = 0;
  while (i < n) {
    // The extent of the block starting at i: i .. (next block-start - 1).
    var blockEnd = i + 1;
    while (blockEnd < n && !blockStartAt.contains(blockEnd)) {
      blockEnd++;
    }
    var blockRows = 0;
    for (var k = i; k < blockEnd; k++) {
      blockRows += lineHeights[k];
    }

    if (blockRows <= effective) {
      // The whole block fits a fresh page — flush first if it won't fit here.
      if (current.isNotEmpty && currentRows + blockRows > effective) flush();
      for (var k = i; k < blockEnd; k++) {
        current.add(k);
      }
      currentRows += blockRows;
    } else {
      // The block alone exceeds a page — split it line-by-line.
      for (var k = i; k < blockEnd; k++) {
        if (current.isNotEmpty && currentRows + lineHeights[k] > effective) {
          flush();
        }
        current.add(k);
        currentRows += lineHeights[k];
      }
    }
    i = blockEnd;
  }
  flush();
  return pages;
}
