/// DASHBOARD-OWNER-ANALYTICS-F0.5 — the ONE localized payment-method label.
///
/// Three copies of this mapping existed, and they had diverged in the way that
/// matters:
///
///   * `order_detail_sheet.dart` and `order_preview_builders.dart` each held a
///     PRIVATE, complete cash/card/bit/external mapper — identical to each
///     other, invisible to everyone else;
///   * the Overview payment summary and the payment-mix donut each held a
///     CASH-ONLY version (`m == 'cash' ? … : m`), so a card, Bit or external
///     tender rendered its raw wire token straight into the owner's dashboard.
///
/// The owner therefore saw "Card" inside an order sheet and the bare string
/// `card` on the Overview, for the same tender, in the same app. That is not a
/// styling inconsistency — it is a wire token leaking into a financial surface,
/// and it gets worse the moment Phase A widens the payment filters to card /
/// bit / external and those tokens start appearing in more places.
///
/// This module is deliberately tiny and presentation-only. It changes no data
/// semantics: the wire token remains the identity everywhere, and only its
/// DISPLAY is resolved here. It reuses the existing `posPaymentMethod*` keys,
/// which already ship in en/ar/he, so no new localization is required.
library;

import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_report.dart' show DashboardReport;
import '../data/order_history_models.dart' show PaymentFilter;

/// Localizes a payment-method wire token (`cash` / `card` / `bit` /
/// `external`).
///
/// An UNKNOWN token falls back to the raw string rather than throwing or
/// rendering an empty cell. That is deliberate: a new server-side method must
/// degrade to something an owner can still read and report, not vanish from a
/// money breakdown whose parts must sum to the whole. The fallback is the
/// signal that a localization is missing — it should never be the normal path
/// for the four known methods.
String paymentMethodLabel(AppLocalizations l10n, String method) =>
    switch (method) {
      'cash' => l10n.posPaymentMethodCash,
      'card' => l10n.posPaymentMethodCard,
      'bit' => l10n.posPaymentMethodBit,
      'external' => l10n.posPaymentMethodExternal,
      _ => method,
    };

/// The payment-method wire tokens the platform actually persists, in the order
/// analytics surfaces should present them.
///
/// Exposed so a chart legend, a filter list and a breakdown table cannot drift
/// into three different orderings or, worse, three different ideas of which
/// methods exist.
const List<String> kPaymentMethodWireTokens = <String>[
  'cash',
  'card',
  'bit',
  'external',
];

/// True when [method] is a token this app knows how to localize.
///
/// Useful for asserting in tests that a breakdown returned by the server is
/// fully presentable, without hard-coding the list at each call site.
bool isKnownPaymentMethod(String method) =>
    kPaymentMethodWireTokens.contains(method);

/// CLIENT-C — the localized label for an order-history payment FILTER.
///
/// Delegates the four tender methods to [paymentMethodLabel] so the Overview's
/// payment mix and the Orders filter can never disagree about what a tender is
/// called; only the settlement states (`all` / `paid` / `unpaid`) have their own
/// wording, which already ships.
String paymentFilterLabel(AppLocalizations l10n, PaymentFilter filter) =>
    switch (filter) {
      PaymentFilter.all => l10n.ordersPaymentAll,
      PaymentFilter.paid => l10n.dashboardPaid,
      PaymentFilter.unpaid => l10n.dashboardUnpaid,
      PaymentFilter.cash ||
      PaymentFilter.card ||
      PaymentFilter.bit ||
      PaymentFilter.external => paymentMethodLabel(l10n, filter.wire!),
    };

/// The payment-filter options an Orders dropdown should OFFER, always including
/// [current] so the control can display the state it is actually in.
///
/// The manually offered set is deliberately the pre-existing one — all / paid /
/// unpaid / cash. card / bit / external are reachable by DRILL-DOWN, which is
/// gated on proof that the server can answer them
/// ([DashboardReport.supportsPaymentMethodHistoryFilters]); offering them in a
/// free-standing dropdown would hand an owner on a pre-SERVER-B database a
/// filter that silently returns nothing.
///
/// But a control must still be able to RENDER a value applied from elsewhere:
/// a dropdown whose current value is missing from its items is a framework
/// assertion, and more importantly an owner who arrived by drill-down has to be
/// able to see, and undo, the filter they are looking at.
Map<PaymentFilter, String> paymentFilterOptions(
  AppLocalizations l10n,
  PaymentFilter current,
) {
  final options = <PaymentFilter, String>{
    for (final f in const [
      PaymentFilter.all,
      PaymentFilter.paid,
      PaymentFilter.unpaid,
      PaymentFilter.cash,
    ])
      f: paymentFilterLabel(l10n, f),
  };
  options.putIfAbsent(current, () => paymentFilterLabel(l10n, current));
  return options;
}

/// F0.5 — the shift-state wire tokens the owner report can actually carry.
///
/// Only these two are real STATES. Every real report path
/// (owner_report_range, owner_daily_report and the sales_summary fallback)
/// hardcodes `'none'`, which is not a state at all — it means the payload
/// carried no shift information.
const String kShiftStateOpen = 'open';
const String kShiftStateClosed = 'closed';

/// Whether [report] carries a real shift state worth rendering.
///
/// False for `'none'` and for anything unrecognised. Callers use this to OMIT
/// shift/drawer rows rather than print a measured-looking zero: absence of
/// data and a genuine ₪0.00 variance are different facts and must not look
/// alike to an owner reconciling a till.
bool reportHasShiftState(DashboardReport report) =>
    report.shiftStatus == kShiftStateOpen ||
    report.shiftStatus == kShiftStateClosed;

/// Localizes a shift-state token for display.
///
/// Reuses the already-translated activity-log phrasings rather than adding new
/// keys: "Shift opened" / "Shift closed" read correctly as a state and ship in
/// en/ar/he today. A future polish pass may introduce dedicated adjective-form
/// keys; that is wording, not honesty, so it does not belong in this slice.
///
/// An unrecognised token (including `'none'`) returns an empty string, because
/// callers are expected to have skipped it via [reportHasShiftState] - it must
/// never fall through to the raw wire value.
String shiftStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      kShiftStateOpen => l10n.activityLogTitleShiftOpened,
      kShiftStateClosed => l10n.activityLogTitleShiftClosed,
      _ => '',
    };
