/// Models for the Dashboard "Activity log" — read-only operational audit
/// timeline (AUDIT-LOG-DASHBOARD-001).
///
/// These are plain immutable value objects so the demo and real (RPC)
/// repositories map into the SAME shape and the UI never branches on the source.
/// [AuditEvent] carries the already-safe (server secret-scrubbed) payload; the
/// PRESENTATION mapper ([audit_log_presentation.dart]) is the single place that
/// decides — via an explicit field allowlist — what actually renders. Money in
/// payloads is integer MINOR units (D-007); nothing here recomputes a figure.
library;

/// The date window — mirrors the backend `p_range` and the reports/orders
/// ranges (today / yesterday / last7 / last30). No custom range: the backend
/// resolves branch-local day boundaries (RF-REPORT-004 model; no second tz).
enum AuditRange {
  today('today'),
  yesterday('yesterday'),
  last7('last7'),
  last30('last30');

  const AuditRange(this.wire);

  /// The exact token the RPC expects for `p_range`.
  final String wire;

  static AuditRange fromWire(String wire) => AuditRange.values.firstWhere(
    (r) => r.wire == wire,
    orElse: () => AuditRange.today,
  );
}

/// Category filter. `all` sends null (no filter); the others map to the backend
/// `p_category` tokens. Kept in sync with the RPC's validated vocabulary.
enum AuditCategory {
  all(null),
  orders('orders'),
  voids('voids'),
  discounts('discounts'),
  payments('payments'),
  shifts('shifts'),
  staff('staff'),
  access('access'),
  devices('devices'),
  settings('settings'),
  menu('menu'),
  tables('tables'),
  organization('organization');

  const AuditCategory(this.wire);
  final String? wire;
}

/// One selectable BRANCH the caller covers (options come from the scope-safe
/// org-structure source; the caller never types an arbitrary UUID). `label`
/// is the display name (e.g. "Rest 1 · Downtown"); the two ids are sent to the
/// RPC's `p_restaurant_id`/`p_branch_id` when this branch is selected.
class AuditBranchOption {
  const AuditBranchOption({
    required this.branchId,
    required this.restaurantId,
    required this.label,
  });

  final String branchId;
  final String restaurantId;
  final String label;
}

/// One selectable STAFF actor the caller may filter by (options come from the
/// scope-safe staff source; names only, never email/phone). `employeeProfileId`
/// is sent to the RPC's `p_actor_employee_profile_id`.
class AuditActorOption {
  const AuditActorOption({
    required this.employeeProfileId,
    required this.label,
  });

  final String employeeProfileId;
  final String label;
}

/// The list controls (range + category + sensitive-only + branch + actor). The
/// screen's chips / dropdowns / toggle write this; the repository turns it into
/// RPC params. `branch == null` = "all permitted branches" (the caller's covered
/// scope); `actor == null` = "all staff".
class AuditQuery {
  const AuditQuery({
    this.range = AuditRange.today,
    this.category = AuditCategory.all,
    this.sensitiveOnly = false,
    this.branch,
    this.actor,
  });

  final AuditRange range;
  final AuditCategory category;
  final bool sensitiveOnly;

  /// The selected branch, or null for "all permitted branches" (covered scope).
  final AuditBranchOption? branch;

  /// The selected staff actor, or null for "all staff".
  final AuditActorOption? actor;

  AuditQuery copyWith({
    AuditRange? range,
    AuditCategory? category,
    bool? sensitiveOnly,
    AuditBranchOption? branch,
    bool clearBranch = false,
    AuditActorOption? actor,
    bool clearActor = false,
  }) => AuditQuery(
    range: range ?? this.range,
    category: category ?? this.category,
    sensitiveOnly: sensitiveOnly ?? this.sensitiveOnly,
    branch: clearBranch ? null : (branch ?? this.branch),
    actor: clearActor ? null : (actor ?? this.actor),
  );
}

/// One audit event, exactly as the (already secret-scrubbed) RPC returns it.
///
/// `oldValues` / `newValues` are the SERVER-redacted payloads; the presentation
/// mapper further allowlists which keys ever reach the UI. Nothing in this class
/// renders — it is raw transport data.
class AuditEvent {
  const AuditEvent({
    required this.eventId,
    required this.action,
    required this.category,
    required this.occurredAtLabel,
    this.actorName,
    this.restaurantName,
    this.branchName,
    this.deviceLabel,
    this.reason,
    this.oldValues = const {},
    this.newValues = const {},
  });

  final String eventId;

  /// The canonical action string (e.g. `order.voided`, `staff.capabilities_updated`).
  final String action;

  /// The server-derived display category (orders / voids / discounts / payments /
  /// shifts / staff / access / devices / menu / tables / organization / sync / other).
  final String category;

  /// Server-formatted branch-local timestamp (`YYYY-MM-DD HH:MM`).
  final String occurredAtLabel;

  /// The actor's staff display name — never an email/phone. Null when it could
  /// not be resolved (former staff / server actor without a profile).
  final String? actorName;
  final String? restaurantName;
  final String? branchName;
  final String? deviceLabel;

  /// Operational free-text reason (e.g. a void reason). Safe to show.
  final String? reason;

  final Map<String, Object?> oldValues;
  final Map<String, Object?> newValues;

  /// True for a denied / rejected attempt (surfaced as a "Denied" pill).
  bool get isDenied =>
      action.endsWith('_denied') ||
      action.endsWith('_rejected') ||
      action.endsWith('_conflict');
}

/// One page of events + the keyset continuation. `currencyCode` formats any
/// money-minor field in the payloads.
class AuditPage {
  const AuditPage({
    required this.events,
    this.hasMore = false,
    this.nextCursor,
    this.currencyCode = '',
  });

  const AuditPage.empty()
    : events = const [],
      hasMore = false,
      nextCursor = null,
      currencyCode = '';

  final List<AuditEvent> events;
  final bool hasMore;
  final String? nextCursor;
  final String currencyCode;

  bool get isEmpty => events.isEmpty;
}
