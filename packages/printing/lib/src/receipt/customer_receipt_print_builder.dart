import '../print_document.dart';
import 'receipt_input.dart';
import 'receipt_money_format.dart';
import 'receipt_rasterizer.dart';

/// Builds a customer-receipt [PrintDocument] from an authoritative
/// [ReceiptInput] (RF-073).
///
/// Two strategies:
/// * **English (LTR)** — composed of [PrintTextLine]s, each pre-formatted to the
///   paper's column count (name-left / amount-right, item names wrapped, money
///   never truncated, total emphasized). ASCII renders crisply through the
///   RF-070 ESC/POS text path.
/// * **Arabic/Hebrew (RTL)** — the ESC/POS text path is ASCII/codepage-limited
///   and would print `?` for every Arabic/Hebrew glyph, so the whole receipt is
///   rendered to ONE monochrome bitmap via the injected [ReceiptRasterizer] and
///   emitted as a single [PrintRasterImageLine]. No Arabic/Hebrew text is ever
///   routed through the text path.
///
/// The builder reads ONLY authoritative integer minor-unit money supplied in the
/// input; it never recomputes subtotal/tax/total and uses no floating point
/// (D-007/D-008).
class CustomerReceiptPrintBuilder {
  const CustomerReceiptPrintBuilder._();

  /// Build the receipt document for [input] on [paper].
  ///
  /// [rasterizer] is REQUIRED for Arabic/Hebrew (RTL) locales and unused for
  /// English. Throws [ArgumentError] if an RTL receipt is built without one.
  static Future<PrintDocument> build({
    required ReceiptInput input,
    required ReceiptPaperSpec paper,
    ReceiptRasterizer? rasterizer,
  }) {
    if (input.locale.isRtl) {
      return _buildRaster(input: input, paper: paper, rasterizer: rasterizer);
    }
    return Future<PrintDocument>.value(_buildText(input: input, paper: paper));
  }

  // --- English / LTR text path -------------------------------------------

  static PrintDocument _buildText({
    required ReceiptInput input,
    required ReceiptPaperSpec paper,
  }) {
    final labels = input.effectiveLabels;
    final width = paper.columns;
    final lines = <PrintLine>[];

    for (final line in input.merchantLines) {
      lines.add(PrintTextLine(line, alignment: PrintAlignment.center));
    }
    if (input.isReprint) {
      lines.add(
        PrintTextLine(
          labels.duplicateMarker,
          alignment: PrintAlignment.center,
          emphasis: TextEmphasis.bold,
        ),
      );
    }

    lines
      ..add(PrintTextLine('${labels.receiptNumber}: ${input.receiptNumber}'))
      ..add(PrintTextLine('${labels.order}: ${input.orderRef}'))
      ..add(PrintTextLine(labels.serviceType(input.serviceType)))
      ..add(PrintTextLine(input.issuedAt.toIso8601String()))
      ..add(const PrintFeedLine());

    for (final item in input.items) {
      final label = '${item.quantity} x ${item.nameSnapshot}';
      _addRow(lines, label, _money(input, item.lineTotalMinor), width);
      for (final mod in item.modifiers) {
        final modLabel = '  + ${mod.nameSnapshot}';
        if (mod.amountMinor != null) {
          _addRow(lines, modLabel, _money(input, mod.amountMinor!), width);
        } else {
          lines.add(PrintTextLine(modLabel));
        }
      }
    }

    lines.add(const PrintFeedLine());
    _addRow(lines, labels.subtotal, _money(input, input.subtotalMinor), width);
    for (final discount in input.discounts) {
      _addRow(
        lines,
        discount.label,
        _money(input, discount.amountMinor),
        width,
      );
    }
    for (final tax in input.taxes) {
      _addRow(lines, tax.label, _money(input, tax.amountMinor), width);
    }
    _addRow(
      lines,
      labels.total,
      _moneyWithCurrency(input, input.totalMinor),
      width,
      emphasis: TextEmphasis.bold,
    );

    lines.add(const PrintFeedLine());
    _addRow(
      lines,
      '${labels.paid} (${input.tender.method})',
      _money(input, input.tender.paidMinor),
      width,
    );
    _addRow(
      lines,
      labels.change,
      _money(input, input.tender.changeMinor),
      width,
    );

    for (final line in input.footerLines) {
      lines.add(PrintTextLine(line, alignment: PrintAlignment.center));
    }
    lines
      ..add(const PrintFeedLine(2))
      ..add(const PrintCutLine());

    return PrintDocument(lines, localeTag: input.locale.tag);
  }

  // --- Arabic / Hebrew / RTL raster path ---------------------------------

  static Future<PrintDocument> _buildRaster({
    required ReceiptInput input,
    required ReceiptPaperSpec paper,
    required ReceiptRasterizer? rasterizer,
  }) async {
    if (rasterizer == null) {
      throw ArgumentError.notNull('rasterizer');
    }
    final logicalLines = _logicalLines(input);
    final image = await rasterizer.rasterize(
      ReceiptRasterRequest(
        lines: logicalLines,
        widthDots: paper.rasterDots,
        direction: input.locale.direction,
        localeTag: input.locale.tag,
      ),
    );
    return PrintDocument(<PrintLine>[
      image.toPrintLine(),
      const PrintFeedLine(2),
      const PrintCutLine(),
    ], localeTag: input.locale.tag);
  }

  /// The localized logical receipt content (used as the raster source). The
  /// duplicate marker + Arabic/Hebrew labels are present HERE, before
  /// rasterization, so they end up inside the bitmap (never as `?` text).
  static List<String> _logicalLines(ReceiptInput input) {
    final labels = input.effectiveLabels;
    final out = <String>[...input.merchantLines];
    if (input.isReprint) {
      out.add(labels.duplicateMarker);
    }
    out
      ..add('${labels.receiptNumber}: ${input.receiptNumber}')
      ..add('${labels.order}: ${input.orderRef}')
      ..add(labels.serviceType(input.serviceType))
      ..add(input.issuedAt.toIso8601String());

    for (final item in input.items) {
      out.add(
        '${item.quantity} x ${item.nameSnapshot}   '
        '${_money(input, item.lineTotalMinor)}',
      );
      for (final mod in item.modifiers) {
        final amount = mod.amountMinor != null
            ? '   ${_money(input, mod.amountMinor!)}'
            : '';
        out.add('  + ${mod.nameSnapshot}$amount');
      }
    }

    out.add('${labels.subtotal}   ${_money(input, input.subtotalMinor)}');
    for (final discount in input.discounts) {
      out.add('${discount.label}   ${_money(input, discount.amountMinor)}');
    }
    for (final tax in input.taxes) {
      out.add('${tax.label}   ${_money(input, tax.amountMinor)}');
    }
    out
      ..add('${labels.total}   ${_moneyWithCurrency(input, input.totalMinor)}')
      ..add(
        '${labels.paid} (${input.tender.method})   '
        '${_money(input, input.tender.paidMinor)}',
      )
      ..add('${labels.change}   ${_money(input, input.tender.changeMinor)}')
      ..addAll(input.footerLines);
    return out;
  }

  // --- shared helpers -----------------------------------------------------

  static String _money(ReceiptInput input, int minor) =>
      ReceiptMoneyFormat.format(
        minor,
        currencyCode: input.currencyCode,
        exponentOverride: input.exponentOverride,
      );

  static String _moneyWithCurrency(ReceiptInput input, int minor) =>
      ReceiptMoneyFormat.formatWithCurrency(
        minor,
        currencyCode: input.currencyCode,
        exponentOverride: input.exponentOverride,
      );

  /// Append a name-left / amount-right row formatted to [width] columns,
  /// wrapping the label and NEVER truncating [amount].
  static void _addRow(
    List<PrintLine> lines,
    String label,
    String amount,
    int width, {
    TextEmphasis emphasis = TextEmphasis.normal,
  }) {
    for (final text in _row(label, amount, width)) {
      lines.add(PrintTextLine(text, emphasis: emphasis));
    }
  }

  static List<String> _row(String left, String right, int width) {
    // Amount alone too wide: never truncate — wrap the label, amount on its own.
    if (right.length >= width) {
      return <String>[..._wrapWords(left, width), right];
    }
    final maxLeft = width - right.length - 1; // keep >=1 space between
    if (left.length <= maxLeft) {
      final pad = width - left.length - right.length;
      return <String>['$left${' ' * pad}$right'];
    }
    final wrapped = _wrapWords(left, width);
    final last = wrapped.last;
    if (last.length <= maxLeft) {
      final pad = width - last.length - right.length;
      wrapped[wrapped.length - 1] = '$last${' ' * pad}$right';
      return wrapped;
    }
    wrapped.add(right.padLeft(width));
    return wrapped;
  }

  /// Deterministic word-wrap to [width]; hard-splits any single word longer
  /// than [width].
  static List<String> _wrapWords(String text, int width) {
    final out = <String>[];
    var current = '';
    for (final word in text.split(' ')) {
      var w = word;
      if (current.isEmpty) {
        current = w;
      } else if (current.length + 1 + w.length <= width) {
        current = '$current $w';
        continue;
      } else {
        out.add(current);
        current = w;
      }
      while (current.length > width) {
        out.add(current.substring(0, width));
        current = current.substring(width);
      }
    }
    if (current.isNotEmpty) {
      out.add(current);
    }
    return out.isEmpty ? <String>[''] : out;
  }
}
