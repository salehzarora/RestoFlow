import 'dart:typed_data';

import 'kitchen_spool_payload.dart'
    show
        KitchenDispatchDocument,
        KitchenDispatchItem,
        KitchenDispatchModifierPrep,
        KitchenDispatchPrepComponent;
import 'kitchen_spool_status.dart' show KitchenSpoolDispatchType;
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenCount, formatPrepQuantity, kitchenCountDisplayLabel;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KIOSK-PRINT-114B.2: EXTRACTED VERBATIM from apps/pos/lib/src/spool/ so
/// the kiosk's claimed-dispatch print uses the EXACT printer_only renderer
/// the POS drain uses (no second formatter). Behavior-preserving move; the
/// POS keeps a re-export shim at the old path.
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
    required this.prepWithOption,
    required this.prepWithoutOption,
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

  /// 017 (Codex BLOCKER #1): the with/without wording for a preparation
  /// resource split by a classifying modifier option
  /// (KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016). Part of THIS injectable
  /// frame-label bundle, exactly like every other ticket word here — the shared
  /// composer that applies them carries no natural language of its own.
  final String Function(String resource, String option) prepWithOption;
  final String Function(String resource, String option) prepWithoutOption;

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
    prepWithOption: _enPrepWith,
    prepWithoutOption: _enPrepWithout,
  );

  static const KitchenTicketLabels ar = KitchenTicketLabels(
    kitchenMarker: 'المطبخ',
    voidMarker: 'ملغي',
    voidReasonLabel: 'السبب',
    affectedItemsLabel: 'الأصناف المتأثرة',
    roundLabel: 'جولة',
    tableLabel: 'طاولة',
    noteLabel: 'ملاحظة',
    // TABLE-FLOOR-LAYOUT-021 (owner decision 5): aligned to the canonical
    // `posOrderTypeDineIn` wording so the spool ticket and the shared POS/KDS
    // ticket name dine-in identically. Display-only — no wire value reads it.
    dineInLabel: 'تناول في المطعم',
    takeawayLabel: 'سفري',
    prepWithOption: _arPrepWith,
    prepWithoutOption: _arPrepWithout,
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
    prepWithOption: _hePrepWith,
    prepWithoutOption: _hePrepWithout,
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
  pp.PrintDocument buildDocument(
    KitchenDispatchDocument dispatch, {
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap C): the OPTIONAL phone from the
    // encrypted local payload (a crash-recovery replay), overriding the document's
    // (always-null, never-serialized) transient field. Null => nothing printed.
    String? customerPhoneOverride,
  }) {
    final isVoid = dispatch.kind == KitchenSpoolDispatchType.voidNotice;
    final customerPhone = customerPhoneOverride ?? dispatch.customerPhone;
    // TABLE-FLOOR-LAYOUT-021 (owner decision 4): a DINE-IN ticket opens and
    // closes with the same full-width ASCII star band the shared POS/KDS
    // composer prints, so a spool-recovered ticket carries the identical
    // marker. NOT the separator style (raster draws separators as a rule and
    // drops their text); pure ASCII, byte-safe in text mode.
    final dineInBand = dispatch.orderType == 'dine_in'
        ? pp.PrintTextLine(
            '*' * columns,
            alignment: pp.PrintAlignment.center,
            emphasis: pp.TextEmphasis.bold,
            style: pp.PrintLineStyle.normal,
          )
        : null;
    final lines = <pp.PrintLine>[
      if (dineInBand != null) dineInBand,
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
      // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL phone directly below the
      // name, matching the name's centered style. Only present on a locally-built
      // direct-print document (the persisted spool doc never carries it — see
      // KitchenDispatchDocument); null => nothing printed.
      if (customerPhone != null)
        pp.PrintTextLine(
          customerPhone,
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
      // TABLE-FLOOR-LAYOUT-021: the closing dine-in star band — the LAST
      // content line before the feed/cut.
      if (dineInBand != null) dineInBand,
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
    for (final modifier in item.modifiers) ...[
      pp.PrintTextLine(
        '  + ${modifier.name}${modifier.qty > 1 ? ' ×${modifier.qty}' : ''}',
        style: pp.PrintLineStyle.sub,
      ),
      // 019: the option's OWN preparation contribution — a 240g size option
      // contributes 2 Meat pieces — rendered directly under its modifier line,
      // with the classifier worded through the SAME shared composer the direct
      // POS print and the KDS card use. An option with no contribution prints
      // nothing extra, so every existing ticket is byte-identical.
      // 020 (Codex HIGH #3): only a contribution with a positive quantity AND
      // a unit is printable. A unit-only row would name a resource with no
      // count — an instruction the kitchen cannot act on.
      if (modifier.prep case final prep? when prep.isRenderable)
        pp.PrintTextLine(
          '  • ${_modifierPrepText(prep, modifier.qty)}',
          style: pp.PrintLineStyle.sub,
        ),
    ],
    for (final prep in item.prep)
      pp.PrintTextLine('  • ${_prepText(prep)}', style: pp.PrintLineStyle.sub),
    if (item.note != null)
      pp.PrintTextLine('  » ${item.note}', style: pp.PrintLineStyle.note),
  ];

  /// 017 (Codex BLOCKER #1): one prep component's text. An UNCLASSIFIED
  /// component renders byte-identically to before; a classified one wraps that
  /// same text in this bundle's localized with/without pattern, through the
  /// SHARED [kitchenCountDisplayLabel] composer the direct POS print and the KDS
  /// card use — so a durable retry cannot word the split differently from the
  /// ticket it is replacing.
  /// 019: one MODIFIER option's preparation contribution. [modifierQty] scales
  /// it exactly as the shared aggregation does (an option taken twice
  /// contributes twice); the classifier is PRESENCE-based and never scales.
  /// Unclassified contributions read as a plain "N unit" line.
  String _modifierPrepText(KitchenDispatchModifierPrep prep, int modifierQty) {
    final quantity = prep.quantity;
    final scaled = quantity == null ? null : quantity * modifierQty;
    final base = [
      if (scaled != null) formatPrepQuantity(scaled),
      if (prep.unit != null) prep.unit,
    ].join(' ');
    if (!prep.isClassified) return base;
    return kitchenCountDisplayLabel(
      KitchenCount(
        quantity: scaled ?? 0,
        label: base,
        classifier: prep.classifierOptionName!,
        classifierSelected: prep.classifierSelected!,
      ),
      withOption: labels.prepWithOption,
      withoutOption: labels.prepWithoutOption,
    );
  }

  String _prepText(KitchenDispatchPrepComponent prep) {
    final base = [
      if (prep.name != null) prep.name,
      if (prep.quantity != null) '${prep.quantity}',
      if (prep.unit != null) prep.unit,
    ].join(' ');
    if (!prep.isClassified) return base;
    return kitchenCountDisplayLabel(
      KitchenCount(
        quantity: prep.quantity ?? 0,
        label: base,
        classifier: prep.classifierOptionName!,
        classifierSelected: prep.classifierSelected!,
      ),
      withOption: labels.prepWithOption,
      withoutOption: labels.prepWithoutOption,
    );
  }

  /// Renders the ticket to 80mm ESC/POS bytes through the shared RTL raster
  /// seam. A rasterizer failure falls back to the text document — a ticket
  /// with '?' glyphs still beats no kitchen ticket.
  Future<Uint8List> renderToBytes(
    KitchenDispatchDocument dispatch, {
    String? customerPhoneOverride,
  }) async {
    final document = buildDocument(
      dispatch,
      customerPhoneOverride: customerPhoneOverride,
    );
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

// 017: const-friendly tear-off targets for the per-language with/without prep
// wording. Closures in a const bundle are not const; these top-level functions
// are — and they keep the natural language OUT of the shared composer.
String _enPrepWith(String resource, String option) => '$resource with $option';
String _enPrepWithout(String resource, String option) =>
    '$resource without $option';
String _arPrepWith(String resource, String option) => '$resource مع $option';
String _arPrepWithout(String resource, String option) =>
    '$resource بدون $option';
String _hePrepWith(String resource, String option) => '$resource עם $option';
String _hePrepWithout(String resource, String option) =>
    '$resource בלי $option';
