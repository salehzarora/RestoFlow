/// Models for the Dashboard ACTIVE-ORDERS operations centre (ACTIVE-ORDERS-001).
///
/// READ-ONLY throughout: nothing here can change an order, a payment, a shift or
/// a kitchen job. Money is integer MINOR units (D-007), read straight from the
/// stored order snapshot the backend returns (D-008).
///
/// THE CANONICAL STATE PARTITION LIVES HERE, ONCE. It is the state model the
/// backend already enforces — this feature introduces NO second taxonomy
/// (`app.update_order_status`'s legal FROM set, `app.void_order`'s legal source
/// gate and `app.record_payment`'s legal source gate are all EXACTLY these five
/// values; docs/STATE_MACHINES.md + DECISION D-018 + `OrderStatus.isTerminal`
/// agree). The server re-derives it independently — this list is presentation
/// only and is never trusted as an authorization boundary.
library;

import 'audit_log_models.dart' show AuditBranchOption;
import 'order_history_models.dart';

/// The OPERATIONALLY ACTIVE order statuses, in lifecycle order.
///
/// `draft` is deliberately absent: it is a LOCAL-ONLY pre-state (RF-032) that is
/// never written server-side. `completed` / `cancelled` / `voided` are TERMINAL.
const List<String> kActiveOrderStatuses = <String>[
  'submitted',
  'accepted',
  'preparing',
  'ready',
  'served',
];

/// The TERMINAL order statuses — these never appear on the active board.
const List<String> kTerminalOrderStatuses = <String>[
  'completed',
  'cancelled',
  'voided',
];

/// Whether [status] is operationally active (canonical partition above).
bool isActiveOrderStatus(String status) =>
    kActiveOrderStatuses.contains(status);

/// Whether [status] is terminal (canonical partition above).
bool isTerminalOrderStatus(String status) =>
    kTerminalOrderStatuses.contains(status);

/// The operational-stage filter — `all` sends null; the others map 1:1 to the
/// canonical active statuses (the RPC rejects anything else with a 22023 bad
/// request, so a terminal or unknown token can never reach the board).
enum ActiveOrderStageFilter {
  all(null),
  submitted('submitted'),
  accepted('accepted'),
  preparing('preparing'),
  ready('ready'),
  served('served');

  const ActiveOrderStageFilter(this.wire);

  /// The exact token the RPC expects for `p_status` (null = no filter).
  final String? wire;
}

/// The active-board controls. [branch] is picked from the SCOPE-SAFE option list
/// (never a typed UUID); null means "every branch I am permitted to see", which
/// the repository resolves from the caller's role — the server intersects it with
/// the server-derived scope regardless.
class ActiveOrdersQuery {
  const ActiveOrdersQuery({
    this.branch,
    this.stage = ActiveOrderStageFilter.all,
    this.orderType = OrderTypeFilter.all,
    this.payment = PaymentFilter.all,
    this.search = '',
  });

  final AuditBranchOption? branch;
  final ActiveOrderStageFilter stage;
  final OrderTypeFilter orderType;
  final PaymentFilter payment;
  final String search;

  ActiveOrdersQuery copyWith({
    AuditBranchOption? branch,
    bool clearBranch = false,
    ActiveOrderStageFilter? stage,
    OrderTypeFilter? orderType,
    PaymentFilter? payment,
    String? search,
  }) => ActiveOrdersQuery(
    branch: clearBranch ? null : (branch ?? this.branch),
    stage: stage ?? this.stage,
    orderType: orderType ?? this.orderType,
    payment: payment ?? this.payment,
    search: search ?? this.search,
  );

  /// The trimmed search, or null when blank (so the RPC skips the filter).
  String? get searchOrNull {
    final s = search.trim();
    return s.isEmpty ? null : s;
  }
}

/// The scope's operational picture. Deliberately covers the SCOPE (org /
/// restaurant / branch) and NOT the stage/payment/type/search filters, so the
/// counters stay stable while the operator narrows the list below them.
class ActiveOrdersSummary {
  const ActiveOrdersSummary({
    this.total = 0,
    this.unpaid = 0,
    this.byStatus = const <String, int>{},
  });

  final int total;

  /// Active orders with NO completed payment. Unpaid is a PAYMENT attribute, not
  /// an operational stage (D-025) — an unpaid order can sit at any stage.
  final int unpaid;

  /// Count per canonical active status. Always carries all five keys.
  final Map<String, int> byStatus;

  int stage(String status) => byStatus[status] ?? 0;

  int get ready => stage('ready');

  /// Cooked and handed to the guest, but not yet closed by the lifecycle.
  int get served => stage('served');
}

/// One bounded read of the active board.
class ActiveOrdersSnapshot {
  const ActiveOrdersSnapshot({
    this.rows = const <OrderHistoryRow>[],
    this.summary = const ActiveOrdersSummary(),
    this.currencyCode = '',
    this.matching = 0,
    this.limit = 100,
    this.truncated = false,
  });

  /// The board rows, OLDEST FIRST (FIFO — the project's canonical rule).
  final List<OrderHistoryRow> rows;
  final ActiveOrdersSummary summary;
  final String currencyCode;

  /// How many orders matched the filters server-side (may exceed [rows.length]).
  final int matching;

  /// The server-applied page cap.
  final int limit;

  /// True when the cap bit — the board is showing the OLDEST [limit] of
  /// [matching]. Surfaced to the operator; never a silent cut.
  final bool truncated;

  bool get isEmpty => rows.isEmpty;
}

/// How long [row] has been open, from its ABSOLUTE created instant.
///
/// Returns null when the backend gave no machine-readable timestamp — an unknown
/// age is left BLANK rather than fabricated as "0 min". Negative values (device
/// clock skew) clamp to 0, the same rule the KDS already applies.
///
/// NOTE: this is ELAPSED time, not lateness. No promised/due/ETA/SLA field
/// exists anywhere in the schema, so this feature never claims an order is late.
int? openMinutes(OrderHistoryRow row, DateTime now) {
  final createdAt = row.createdAtUtc;
  if (createdAt == null) return null;
  final minutes = now.toUtc().difference(createdAt.toUtc()).inMinutes;
  return minutes < 0 ? 0 : minutes;
}
