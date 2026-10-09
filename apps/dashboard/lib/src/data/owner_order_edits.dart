/// ORDER-EDIT-001G — the Overview "Order edits" result (`owner_order_edits`,
/// API_CONTRACT §4.47; MONEY_AND_TAX_SPEC §13 M13).
///
/// A SEPARATE result type from [DashboardReport], for the reason every other
/// Overview card has one: it comes from its own RPC, it can be UNAVAILABLE on
/// its own (a database where the reader is not deployed answers PGRST202), and
/// folding it into the report would let one failed block take the KPIs down.
///
/// Every money figure is an `int` in minor units (D-007), exactly as the server
/// computed it per edit AS WRITTEN. The client never recomputes a figure from
/// another one except where the contract defines the identity (net and gross),
/// and it never adds money across currencies.
library;

/// The eight M13 figures shared by the summary, the breakdown rows and each
/// edit (API_CONTRACT §4.47).
class OrderEditFigures {
  const OrderEditFigures({
    this.editCount = 0,
    this.editedOrderCount = 0,
    this.removedMinor = 0,
    this.replacedOutMinor = 0,
    this.replacedInMinor = 0,
    this.addedMinor = 0,
    this.netChangeMinor = 0,
    this.grossRetiredMinor = 0,
  });

  /// An all-zero summary: what an empty window honestly reports.
  static const OrderEditFigures zero = OrderEditFigures();

  final int editCount;
  final int editedOrderCount;
  final int removedMinor;
  final int replacedOutMinor;
  final int replacedInMinor;
  final int addedMinor;

  /// Signed: `replaced_in + added − removed − replaced_out`. Derived, and never
  /// shown in place of [grossRetiredMinor] (MONEY §12.2).
  final int netChangeMinor;

  /// `removed + replaced_out`: the value taken off sent orders, always shown.
  final int grossRetiredMinor;
}

/// One "By reason" row. A null [reasonCode] is the no-reason bucket: edits
/// that only added items or raised a quantity (API_CONTRACT §4.45.2 step 6a).
class OrderEditReasonRow {
  const OrderEditReasonRow({required this.reasonCode, required this.figures});

  final String? reasonCode;
  final OrderEditFigures figures;
}

/// One "By staff member" row. Present only when the caller may see staff
/// names (`staff_visible`); the server sends no staff identifier.
class OrderEditStaffRow {
  const OrderEditStaffRow({required this.staffName, required this.figures});

  final String? staffName;
  final OrderEditFigures figures;
}

/// One edit in the "latest edits" list. Named `…ReportRow` so it never
/// collides with the order drawer's [OrderEditTimelineEntry].
class OrderEditReportRow {
  const OrderEditReportRow({
    required this.orderEditId,
    required this.orderId,
    required this.orderCode,
    required this.editNumber,
    required this.orderStatus,
    required this.orderType,
    required this.createdAtLabel,
    required this.currencyCode,
    required this.figures,
    this.branchName,
    this.staffName,
    this.reasonCode,
    this.kitchenChannel,
    this.createdAtUtc,
    this.businessDay,
    this.timezone,
  });

  final String orderEditId;
  final String orderId;

  /// The shared `#XXXXXX` display code (POS / KDS / receipt / Orders).
  final String orderCode;
  final int editNumber;

  /// The order's status NOW (an edited order may since have been voided).
  final String orderStatus;
  final String orderType;

  /// The edit's time, already formatted branch-local by the server.
  final String createdAtLabel;

  /// The order's own currency. The client never adds across currencies.
  final String currencyCode;
  final OrderEditFigures figures;
  final String? branchName;

  /// Null when the caller may not see staff names, or the profile has none.
  final String? staffName;
  final String? reasonCode;
  final String? kitchenChannel;
  final String? createdAtUtc;
  final String? businessDay;
  final String? timezone;

  bool get orderVoided => orderStatus == 'voided';
}

/// The whole `owner_order_edits` envelope for one window and scope.
class OwnerOrderEdits {
  const OwnerOrderEdits({
    required this.currencyCode,
    required this.rangeWire,
    this.currencyCodes = const <String>[],
    this.enabledInScope = false,
    this.staffVisible = false,
    this.summary = OrderEditFigures.zero,
    this.byReason = const <OrderEditReasonRow>[],
    this.byStaff = const <OrderEditStaffRow>[],
    this.edits = const <OrderEditReportRow>[],
    this.count = 0,
    this.matching = 0,
    this.hasMore = false,
    this.nextCursor,
    this.supported = true,
  });

  /// The reader is not deployed on this database. Distinct from an empty
  /// window, which is a supported answer with zero edits.
  const OwnerOrderEdits.unavailable(this.rangeWire)
    : currencyCode = '',
      currencyCodes = const <String>[],
      enabledInScope = false,
      staffVisible = false,
      summary = OrderEditFigures.zero,
      byReason = const <OrderEditReasonRow>[],
      byStaff = const <OrderEditStaffRow>[],
      edits = const <OrderEditReportRow>[],
      count = 0,
      matching = 0,
      hasMore = false,
      nextCursor = null,
      supported = false;

  /// The scope's effective currency (the OPS-043 rule).
  final String currencyCode;

  /// The distinct currencies of the counted edits' orders, sorted.
  final List<String> currencyCodes;

  /// The range token the server echoed (`custom` for a custom window).
  final String rangeWire;

  /// Any branch in scope has `order_edit_enabled` (API_CONTRACT §4.47).
  final bool enabledInScope;

  /// Whether the caller may see staff names (manager and above).
  final bool staffVisible;
  final OrderEditFigures summary;
  final List<OrderEditReasonRow> byReason;
  final List<OrderEditStaffRow> byStaff;

  /// The newest edits first, one page.
  final List<OrderEditReportRow> edits;

  /// Rows on this page.
  final int count;

  /// Every edit the filter selects (the total behind "Showing 1–N of M").
  final int matching;
  final bool hasMore;
  final String? nextCursor;
  final bool supported;

  bool get isEmpty => summary.editCount == 0;

  /// The Overview shows the block when the reader answered and either editing
  /// was turned on somewhere in the scope or the window holds edits. A scope
  /// that never enabled the feature gets no always-empty card, and edits that
  /// exist are shown even after the switch is turned off.
  bool get visibleOnOverview =>
      supported && (enabledInScope || summary.editCount > 0);

  /// Money may be shown in [windowCurrency] only when every counted edit's
  /// order is in that currency. An empty window has nothing to mislabel.
  bool moneyRenderableIn(String windowCurrency) =>
      currencyCodes.every((code) => code == windowCurrency);
}
