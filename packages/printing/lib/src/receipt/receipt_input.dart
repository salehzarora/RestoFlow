import 'receipt_rasterizer.dart';

/// The locale a receipt is rendered in (RF-073, DECISION D-014). Arabic/Hebrew
/// are RTL and route through the raster path; English is LTR text.
enum ReceiptLocale {
  en('en', ReceiptTextDirection.ltr),
  ar('ar', ReceiptTextDirection.rtl),
  he('he', ReceiptTextDirection.rtl);

  const ReceiptLocale(this.tag, this.direction);

  /// BCP-47-ish tag (`en` / `ar` / `he`).
  final String tag;

  /// Base text direction for this locale.
  final ReceiptTextDirection direction;

  bool get isRtl => direction == ReceiptTextDirection.rtl;
}

/// The service type printed on a receipt (RF-073, approved A3). No table model
/// or RF-035 coupling — display metadata only.
enum ReceiptServiceType { dineIn, takeaway }

/// Printable paper specification, kept LOCAL to the receipt module (approved
/// D5). RF-073 does NOT modify `PrinterProfile`; it just needs the text column
/// count + the raster dot width per paper size.
class ReceiptPaperSpec {
  const ReceiptPaperSpec({required this.columns, required this.rasterDots})
    : assert(columns > 0),
      assert(rasterDots > 0 && rasterDots % 8 == 0);

  /// Monospace text columns (used for the English text layout).
  final int columns;

  /// Printable raster width in dots (used for Arabic/Hebrew bitmaps).
  final int rasterDots;

  /// Bytes per raster row (`rasterDots / 8`).
  int get widthBytes => rasterDots ~/ 8;

  /// 58mm: 32 columns, 384 raster dots.
  static const ReceiptPaperSpec mm58 = ReceiptPaperSpec(
    columns: 32,
    rasterDots: 384,
  );

  /// 80mm: 48 columns, 576 raster dots (the default).
  static const ReceiptPaperSpec mm80 = ReceiptPaperSpec(
    columns: 48,
    rasterDots: 576,
  );
}

/// Localized, receipt-specific structural labels (RF-073, approved D6).
///
/// Injected plain-Dart bundle — NO ARB keys, NO `BuildContext`. Built-in
/// defaults are provided for en/ar/he ([en], [ar], [he]); dynamic per-line
/// labels (a tax name, a discount name) live on the lines themselves, not here.
class ReceiptLabelBundle {
  const ReceiptLabelBundle({
    required this.receiptNumber,
    required this.order,
    required this.dineIn,
    required this.takeaway,
    required this.subtotal,
    required this.total,
    required this.paid,
    required this.change,
    required this.duplicateMarker,
  });

  final String receiptNumber;
  final String order;
  final String dineIn;
  final String takeaway;
  final String subtotal;
  final String total;
  final String paid;
  final String change;

  /// The visible reprint/duplicate marker (printed when `isReprint == true`).
  final String duplicateMarker;

  String serviceType(ReceiptServiceType type) =>
      type == ReceiptServiceType.dineIn ? dineIn : takeaway;

  static const ReceiptLabelBundle en = ReceiptLabelBundle(
    receiptNumber: 'Receipt',
    order: 'Order',
    dineIn: 'Dine-in',
    takeaway: 'Takeaway',
    subtotal: 'Subtotal',
    total: 'TOTAL',
    paid: 'Paid',
    change: 'Change',
    duplicateMarker: 'DUPLICATE / REPRINT',
  );

  static const ReceiptLabelBundle ar = ReceiptLabelBundle(
    receiptNumber: 'إيصال',
    order: 'طلب',
    dineIn: 'تناول في المطعم',
    takeaway: 'سفري',
    subtotal: 'المجموع الفرعي',
    total: 'الإجمالي',
    paid: 'المدفوع',
    change: 'الباقي',
    duplicateMarker: 'نسخة / إعادة طباعة',
  );

  static const ReceiptLabelBundle he = ReceiptLabelBundle(
    receiptNumber: 'קבלה',
    order: 'הזמנה',
    dineIn: 'ישיבה במקום',
    takeaway: 'לקחת',
    subtotal: 'סכום ביניים',
    total: 'סה"כ',
    paid: 'שולם',
    change: 'עודף',
    duplicateMarker: 'עותק / הדפסה חוזרת',
  );

  /// The built-in default bundle for [locale].
  static ReceiptLabelBundle defaultFor(ReceiptLocale locale) {
    switch (locale) {
      case ReceiptLocale.en:
        return en;
      case ReceiptLocale.ar:
        return ar;
      case ReceiptLocale.he:
        return he;
    }
  }
}

/// One modifier line under an item (option name + optional price delta).
class ReceiptModifierLine {
  const ReceiptModifierLine({required this.nameSnapshot, this.amountMinor});

  final String nameSnapshot;

  /// Integer minor-unit price delta, or null to print the name only.
  final int? amountMinor;
}

/// One ordered item line: name + quantity + authoritative line total + mods.
class ReceiptItemLine {
  /// Non-const so [modifiers] can be defensively copied — a caller-owned list
  /// must never be able to mutate this DTO after construction (RF073-B1).
  ReceiptItemLine({
    required this.nameSnapshot,
    required this.quantity,
    required this.lineTotalMinor,
    List<ReceiptModifierLine> modifiers = const <ReceiptModifierLine>[],
  }) : modifiers = List.unmodifiable(modifiers);

  final String nameSnapshot;
  final int quantity;

  /// Authoritative integer minor-unit line total (supplied, never computed).
  final int lineTotalMinor;

  /// Unmodifiable copy of the supplied modifiers (defensively copied).
  final List<ReceiptModifierLine> modifiers;
}

/// A discount line. [amountMinor] is the value to DISPLAY exactly as supplied
/// (typically negative, e.g. `-500`); RF-073 performs no arithmetic on it.
class ReceiptDiscountLine {
  const ReceiptDiscountLine({required this.label, required this.amountMinor});

  final String label;
  final int amountMinor;
}

/// A tax/VAT line (e.g. label `VAT 17%`). [amountMinor] is supplied, not computed.
class ReceiptTaxLine {
  const ReceiptTaxLine({required this.label, required this.amountMinor});

  final String label;
  final int amountMinor;
}

/// The tender/payment summary (method + authoritative paid/change minors).
class ReceiptTenderLine {
  const ReceiptTenderLine({
    required this.method,
    required this.paidMinor,
    required this.changeMinor,
  });

  /// Free-text/localized payment method label (e.g. `Cash`).
  final String method;
  final int paidMinor;
  final int changeMinor;
}

/// The complete, authoritative input for ONE customer receipt (RF-073, D1/D2).
///
/// Every money value is an integer minor unit, supplied by the caller (computed
/// upstream by RF-054). RF-073 NEVER recomputes subtotal/tax/total and never
/// reads non-authoritative preview fields. Populating this from real server
/// JSON (the domain/payment/receipt mapper) is a deferred follow-up ticket;
/// tests build it directly.
class ReceiptInput {
  /// Non-const so every list-backed field can be defensively copied with
  /// [List.unmodifiable] — caller-owned lists must never be able to mutate this
  /// authoritative DTO after construction (RF073-B1).
  ReceiptInput({
    required this.organizationId,
    required this.branchId,
    required this.deviceId,
    required this.paymentId,
    required this.receiptNumber,
    required this.orderRef,
    required this.serviceType,
    required this.currencyCode,
    required this.locale,
    required this.issuedAt,
    required List<ReceiptItemLine> items,
    required this.subtotalMinor,
    required this.totalMinor,
    required this.tender,
    List<String> merchantLines = const <String>[],
    List<ReceiptDiscountLine> discounts = const <ReceiptDiscountLine>[],
    List<ReceiptTaxLine> taxes = const <ReceiptTaxLine>[],
    List<String> footerLines = const <String>[],
    this.isReprint = false,
    this.isPaid = true,
    this.isVoidedOrCancelled = false,
    this.exponentOverride,
    this.labels,
  }) : items = List.unmodifiable(items),
       merchantLines = List.unmodifiable(merchantLines),
       discounts = List.unmodifiable(discounts),
       taxes = List.unmodifiable(taxes),
       footerLines = List.unmodifiable(footerLines);

  // Tenant + device scope (DECISION D-001/D-002, D-022) — required for enqueue.
  final String organizationId;
  final String branchId;
  final String deviceId;

  // Authoritative identifiers (from RF-054).
  final String paymentId;
  final String receiptNumber;
  final String orderRef;

  final ReceiptServiceType serviceType;
  final String currencyCode;
  final ReceiptLocale locale;

  /// Printed issue timestamp (caller-supplied so the document is deterministic).
  final DateTime issuedAt;

  final List<ReceiptItemLine> items;

  /// Authoritative integer minor-unit money (supplied, never computed here).
  final int subtotalMinor;
  final int totalMinor;
  final ReceiptTenderLine tender;

  final List<String> merchantLines;
  final List<ReceiptDiscountLine> discounts;
  final List<ReceiptTaxLine> taxes;
  final List<String> footerLines;

  /// When true, the builder prints a visible duplicate/reprint marker.
  final bool isReprint;

  /// Payment-completion + lifecycle gates (approved D9). An original receipt
  /// may print only when paid and not voided/cancelled.
  final bool isPaid;
  final bool isVoidedOrCancelled;

  /// Optional currency-exponent override for display formatting.
  final int? exponentOverride;

  /// Optional explicit label bundle; defaults to the built-in one for [locale].
  final ReceiptLabelBundle? labels;

  /// The effective label bundle (explicit or the built-in default for [locale]).
  ReceiptLabelBundle get effectiveLabels =>
      labels ?? ReceiptLabelBundle.defaultFor(locale);

  /// Validate that this input may be enqueued as an ORIGINAL receipt (D9).
  ///
  /// Throws [ArgumentError] for missing required identifiers and [StateError]
  /// for an unpaid or voided/cancelled order. RF-073 refuses rather than
  /// printing a receipt for money that was never settled (RISK R-008).
  void validateForOriginalPrint() {
    void requireField(String value, String name) {
      if (value.trim().isEmpty) {
        throw ArgumentError.value(value, name, 'must not be empty');
      }
    }

    requireField(paymentId, 'paymentId');
    requireField(receiptNumber, 'receiptNumber');
    requireField(branchId, 'branchId');
    requireField(deviceId, 'deviceId');
    requireField(organizationId, 'organizationId');
    requireField(orderRef, 'orderRef');
    requireField(currencyCode, 'currencyCode');

    if (!isPaid) {
      throw StateError(
        'cannot print an original receipt for an unpaid order '
        '(paymentId=$paymentId)',
      );
    }
    if (isVoidedOrCancelled) {
      throw StateError(
        'cannot print an original receipt for a voided/cancelled order '
        '(orderRef=$orderRef)',
      );
    }
  }
}
