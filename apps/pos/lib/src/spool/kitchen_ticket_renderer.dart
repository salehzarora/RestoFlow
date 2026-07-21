import 'dart:typed_data';

import 'package:restoflow_data_local/restoflow_data_local.dart'
    show KitchenDispatchDocument, KitchenDispatchItem, KitchenSpoolDispatchType;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-MODE-001C2C — the MONEY-FREE kitchen ticket renderer.
///
/// Consumes the CLOSED, decrypted [KitchenDispatchDocument] (which carries
/// no money vocabulary by construction — the hostile-key validator and the
/// closed decoder both enforce it) and emits the shared render-neutral
/// [pp.PrintDocument], then 80mm ESC/POS bytes through the SAME
/// rasterization seam the receipt path uses:
///
///   document → maybeRasterizeForRtl (ar/he → one GS v 0 bitmap; ASCII
///   keeps the text path) → EscPosPrintAdapter.encode(escPos80mm).
///
/// LOCALIZATION: ticket FRAME labels ship as const ar/he/en bundles below
/// (payload content — item names, notes, customer — is already the
/// operator's own language). Generated l10n keys are deliberately NOT added
/// in this pass (no gen-l10n run permitted); the bundles are injectable so
/// the UX phase can swap in AppLocalizations-backed labels without touching
/// worker logic. NEVER rendered: totals, prices, taxes, discounts,
/// payments, tender, change, currency — the model cannot even carry them,
/// and `PrintLineStyle.total` is never emitted.
///
/// KNOWN LIMITATION (documented, not fixed here): main's rasterizer has the
/// PILOT-PRINT-FIDELITY-001 height-without-ink defect (a failed glyph run
/// can yield silent blank space inside the bitmap). The fix is pending in
/// Draft PR #173; this renderer is injected through the stable
/// [pp.ReceiptRasterizer] contract and inherits the fix on merge with no
/// code change.
final class KitchenTicketLabels {
  const KitchenTicketLabels({
    required this.kitchenMarker,
    required this.voidMarker,
    required this.voidReasonLabel,
    required this.affectedItemsLabel,
    required this.roundLabel,
    required this.tableLabel,
    required this.noteLabel,
    required this.dineInLabel,
    required this.takeawayLabel,
  });

  final String kitchenMarker;
  final String voidMarker;
  final String voidReasonLabel;
  final String affectedItemsLabel;
  final String roundLabel;
  final String tableLabel;
  final String noteLabel;
  final String dineInLabel;
  final String takeawayLabel;

  String orderTypeLabel(String wire) => switch (wire) {
    'dine_in' => dineInLabel,
    'takeaway' => takeawayLabel,
    _ => wire,
  };

  static const KitchenTicketLabels en = KitchenTicketLabels(
    kitchenMarker: 'KITCHEN',
    voidMarker: 'VOID',
    voidReasonLabel: 'Reason',
    affectedItemsLabel: 'Affected items',
    roundLabel: 'Round',
    tableLabel: 'Table',
    noteLabel: 'Note',
    dineInLabel: 'Dine-in',
    takeawayLabel: 'Takeaway',
  );

  static const KitchenTicketLabels ar = KitchenTicketLabels(
    kitchenMarker: 'المطبخ',
    voidMarker: 'ملغي',
    voidReasonLabel: 'السبب',
    affectedItemsLabel: 'الأصناف المتأثرة',
    roundLabel: 'جولة',
    tableLabel: 'طاولة',
    noteLabel: 'ملاحظة',
    dineInLabel: 'محلي',
    takeawayLabel: 'سفري',
  );

  static const KitchenTicketLabels he = KitchenTicketLabels(
    kitchenMarker: 'מטבח',
    voidMarker: 'מבוטל',
    voidReasonLabel: 'סיבה',
    affectedItemsLabel: 'פריטים מושפעים',
    roundLabel: 'סבב',
    tableLabel: 'שולחן',
    noteLabel: 'הערה',
    dineInLabel: 'ישיבה',
    takeawayLabel: 'איסוף',
  );

  /// Resolves a bundle from a BCP-47/locale language code (fail-safe: en).
  static KitchenTicketLabels forLanguageCode(String? code) =>
      switch (code?.toLowerCase()) {
        'ar' => ar,
        'he' || 'iw' => he,
        _ => en,
      };
}

final class KitchenTicketRenderer {
  const KitchenTicketRenderer({
    this.labels = KitchenTicketLabels.en,
    this.rasterizer,
    this.adapter = const pp.EscPosPrintAdapter(),
    this.profile = pp.PrinterProfile.escPos80mm,
    this.columns = 48,
    this.rasterWidthDots = pp.kNativeRasterWidthDots,
  });

  final KitchenTicketLabels labels;

  /// The app-injected raster seam (PRINT-RTL-001). Null keeps the ESC/POS
  /// text path (ASCII-only tickets).
  final pp.ReceiptRasterizer? rasterizer;
  final pp.EscPosPrintAdapter adapter;

  /// 80mm ONLY (D2) — there is deliberately no 58mm parameter.
  final pp.PrinterProfile profile;
  final int columns;
  final int rasterWidthDots;

  /// Builds the render-neutral money-free ticket document.
  pp.PrintDocument buildDocument(KitchenDispatchDocument dispatch) {
    final isVoid = dispatch.kind == KitchenSpoolDispatchType.voidNotice;
    final lines = <pp.PrintLine>[
      pp.PrintTextLine(
        labels.kitchenMarker,
        alignment: pp.PrintAlignment.center,
        style: pp.PrintLineStyle.headingLarge,
      ),
      if (isVoid) ...[
        const pp.PrintTextLine('', style: pp.PrintLineStyle.separator),
        pp.PrintTextLine(
          '*** ${labels.voidMarker} ***',
          alignment: pp.PrintAlignment.center,
          emphasis: pp.TextEmphasis.bold,
          style: pp.PrintLineStyle.headingLarge,
        ),
        const pp.PrintTextLine('', style: pp.PrintLineStyle.separator),
      ],
      pp.PrintTextLine(
        dispatch.orderCode,
        alignment: pp.PrintAlignment.center,
        style: pp.PrintLineStyle.headingLarge,
      ),
      pp.PrintTextLine(
        labels.orderTypeLabel(dispatch.orderType),
        alignment: pp.PrintAlignment.center,
        style: pp.PrintLineStyle.centered,
      ),
      if (dispatch.tableLabel != null)
        pp.PrintTextLine(
          '${labels.tableLabel}: ${dispatch.tableLabel}',
          alignment: pp.PrintAlignment.center,
          style: pp.PrintLineStyle.centered,
        ),
      if (dispatch.customerDisplayName != null)
        pp.PrintTextLine(
          dispatch.customerDisplayName!,
          alignment: pp.PrintAlignment.center,
          style: pp.PrintLineStyle.centered,
        ),
      if (dispatch.roundNumber != null)
        pp.PrintTextLine(
          '${labels.roundLabel} ${dispatch.roundNumber}',
          alignment: pp.PrintAlignment.center,
          emphasis: pp.TextEmphasis.bold,
          style: pp.PrintLineStyle.centered,
        ),
      if (dispatch.createdAt != null)
        pp.PrintTextLine(
          dispatch.createdAt!,
          alignment: pp.PrintAlignment.center,
          style: pp.PrintLineStyle.centered,
        ),
      const pp.PrintTextLine('', style: pp.PrintLineStyle.separator),
      for (final item in dispatch.items) ..._itemLines(item),
      if (dispatch.orderNote != null) ...[
        const pp.PrintTextLine('', style: pp.PrintLineStyle.separator),
        pp.PrintTextLine(
          '${labels.noteLabel}: ${dispatch.orderNote}',
          style: pp.PrintLineStyle.note,
        ),
      ],
      if (isVoid) ...[
        const pp.PrintTextLine('', style: pp.PrintLineStyle.separator),
        if (dispatch.reason != null)
          pp.PrintTextLine(
            '${labels.voidReasonLabel}: ${dispatch.reason}',
            style: pp.PrintLineStyle.note,
          ),
        if (dispatch.affectedItemCount != null)
          pp.PrintTextLine(
            '${labels.affectedItemsLabel}: ${dispatch.affectedItemCount}',
            style: pp.PrintLineStyle.note,
          ),
      ],
      const pp.PrintFeedLine(3),
      const pp.PrintCutLine(),
    ];
    return pp.PrintDocument(lines);
  }

  List<pp.PrintLine> _itemLines(KitchenDispatchItem item) => [
    pp.PrintTextLine(
      '${item.qty} × ${item.name}',
      emphasis: pp.TextEmphasis.bold,
      style: pp.PrintLineStyle.item,
    ),
    for (final modifier in item.modifiers)
      pp.PrintTextLine(
        '  + ${modifier.name}${modifier.qty > 1 ? ' ×${modifier.qty}' : ''}',
        style: pp.PrintLineStyle.sub,
      ),
    for (final prep in item.prep)
      pp.PrintTextLine(
        '  • ${[if (prep.name != null) prep.name, if (prep.quantity != null) '${prep.quantity}', if (prep.unit != null) prep.unit].join(' ')}',
        style: pp.PrintLineStyle.sub,
      ),
    if (item.note != null)
      pp.PrintTextLine('  » ${item.note}', style: pp.PrintLineStyle.note),
  ];

  /// Renders the ticket to 80mm ESC/POS bytes through the shared RTL raster
  /// seam. A rasterizer failure falls back to the text document — a ticket
  /// with '?' glyphs still beats no kitchen ticket.
  Future<Uint8List> renderToBytes(KitchenDispatchDocument dispatch) async {
    final document = buildDocument(dispatch);
    pp.PrintDocument out = document;
    final raster = rasterizer;
    if (raster != null) {
      try {
        out = await pp.maybeRasterizeForRtl(
          document,
          rasterizer: raster,
          widthDots: rasterWidthDots,
        );
      } catch (_) {
        out = document;
      }
    }
    return adapter.encode(out, profile);
  }
}
