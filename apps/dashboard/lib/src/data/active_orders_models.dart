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

/// The statuses of the IN-PROGRESS queue — the orders actually moving through
/// preparation. A PRESENTATION grouping OVER the canonical states, never a new
/// taxonomy: every member is one of the five canonical active statuses.
const List<String> kInProgressStatuses = <String>[
  'submitted',
  'accepted',
  'preparing',
  'ready',
];

/// The statuses of the AWAITING-CLOSE queue: cooked and handed over, but not yet
/// closed by the lifecycle. Still ACTIVE — never moved to History before it is
/// actually completed (ORDER-COMPLETION-001).
const List<String> kAwaitingCloseStatuses = <String>['served'];

/// The operational queues of the active board (ACTIVE-ORDERS-002).
///
/// In production the board runs ~127 `served` orders against a handful in
/// preparation, so a single flat list buries the live work and reads like
/// History. The queues separate the two WITHOUT hiding anything: every active
/// order is still reachable, and terminal orders still live only in History.
enum ActiveOrderQueue {
  /// The DEFAULT landing queue: what is actually moving right now.
  inProgress('in_progress', kInProgressStatuses),

  /// Served, waiting to be completed (or paid first — D-025).
  awaitingClose('awaiting_close', kAwaitingCloseStatuses),

  /// Every canonical active state.
  allActive('all_active', kActiveOrderStatuses);

  const ActiveOrderQueue(this.wire, this.statuses);

  /// The exact token the RPC expects for `p_queue`.
  final String wire;

  /// The canonical statuses this queue contains.
  final List<String> statuses;

  bool contains(String status) => statuses.contains(status);
}

/// The board's sort order. AUTHORITATIVE and SERVER-SIDE: the page is capped, so
/// the un-fetched rows are simply not in the payload — reversing the page on the
/// client would silently omit them.
enum ActiveOrdersSort {
  /// The DEFAULT: what just came in, first (`created_at DESC, id DESC`).
  newest('newest'),

  /// FIFO (`created_at ASC, id ASC`) — the classic kitchen queue order.
  oldest('oldest');

  const ActiveOrdersSort(this.wire);

  /// The exact token the RPC expects for `p_sort`.
  final String wire;
}

/// The active-board controls. [branch] is picked from the SCOPE-SAFE option list
/// (never a typed UUID); null means "every branch I am permitted to see", which
/// the repository resolves from the caller's role — the server intersects it with
/// the server-derived scope regardless.
class ActiveOrdersQuery {
  const ActiveOrdersQuery({
    this.queue = ActiveOrderQueue.inProgress,
    this.sort = ActiveOrdersSort.newest,
    this.branch,
    this.stage = ActiveOrderStageFilter.all,
    this.orderType = OrderTypeFilter.all,
    this.payment = PaymentFilter.all,
    this.search = '',
  });

  /// The operational queue. Defaults to IN PROGRESS — the board opens on the work
  /// that is actually moving, not on the served backlog.
  final ActiveOrderQueue queue;

  /// The server-side sort. Defaults to NEWEST first.
  final ActiveOrdersSort sort;

  final AuditBranchOption? branch;
  final ActiveOrderStageFilter stage;
  final OrderTypeFilter orderType;
  final PaymentFilter payment;
  final String search;

  ActiveOrdersQuery copyWith({
    ActiveOrderQueue? queue,
    ActiveOrdersSort? sort,
    AuditBranchOption? branch,
    bool clearBranch = false,
    ActiveOrderStageFilter? stage,
    OrderTypeFilter? orderType,
    PaymentFilter? payment,
    String? search,
  }) {
    final nextQueue = queue ?? this.queue;
    var nextStage = stage ?? this.stage;
    // A stage filter must sit INSIDE the queue — the RPC rejects a contradiction
    // (22023), so changing queue drops a stage the new queue cannot contain
    // rather than sending an impossible request.
    if (nextStage.wire != null && !nextQueue.contains(nextStage.wire!)) {
      nextStage = ActiveOrderStageFilter.all;
    }
    return ActiveOrdersQuery(
      queue: nextQueue,
      sort: sort ?? this.sort,
      branch: clearBranch ? null : (branch ?? this.branch),
      stage: nextStage,
      orderType: orderType ?? this.orderType,
      payment: payment ?? this.payment,
      search: search ?? this.search,
    );
  }

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

  /// The IN-PROGRESS queue count (submitted + accepted + preparing + ready),
  /// server-computed over the whole scope.
  int get inProgress {
    var n = 0;
    for (final s in kInProgressStatuses) {
      n += stage(s);
    }
    return n;
  }

  /// The AWAITING-CLOSE queue count (served), server-computed over the scope.
  int get awaitingClose => served;

  /// The count of the given [queue] — the number the queue's card renders.
  int ofQueue(ActiveOrderQueue queue) => switch (queue) {
    ActiveOrderQueue.inProgress => inProgress,
    ActiveOrderQueue.awaitingClose => awaitingClose,
    ActiveOrderQueue.allActive => total,
  };
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
    this.hasMore = false,
    this.nextCursor,
  });

  /// The board rows, in the SERVER-applied order (newest first by default).
  final List<OrderHistoryRow> rows;
  final ActiveOrdersSummary summary;
  final String currencyCode;

  /// How many orders matched the QUEUE + filters server-side — the FULL set,
  /// never the loaded page. Drives the honest "showing N of [matching]" line.
  final int matching;

  /// The server-applied page cap.
  final int limit;

  /// True when more matching orders exist than have been delivered so far.
  final bool truncated;

  /// True when a further page can be fetched.
  final bool hasMore;

  /// The keyset continuation, TAGGED with the sort it was minted under. The
  /// server rejects it if replayed under the other direction, so it can never
  /// silently mis-page the board.
  final String? nextCursor;

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
