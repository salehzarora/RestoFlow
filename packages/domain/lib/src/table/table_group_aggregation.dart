/// PILOT-OPERATIONS-CORRECTIONS-001 (A4) — the ONE canonical linked-table GROUP
/// aggregation, shared by every surface that presents tables (POS floor read, POS
/// picker, the table-operations sheet, and the owner/manager dashboard).
///
/// A linked group is presented as ONE operational unit: every member shows the SAME
/// group-wide effective state and the SAME group-wide active dine-in count. Without
/// this, a free peer of an occupied group (T2 available, count 0) looked selectable
/// while its group (T1 occupied, count 1) was in use — the exact defect this closes.
///
/// PURE. No widgets, no providers, no I/O — the precedence lives in exactly one place
/// so two widgets can never disagree about the same group.
library;

/// GROUP effective-state precedence rank (higher wins). The DOCUMENTED single source
/// of truth for a linked group's fused state:
///
///   out_of_service (4) > occupied (3) > reserved (2) > available (1)
///
/// A group is 'available' ONLY when every member is available. A broken member
/// (out_of_service) is the top rank, so it is never hidden. Occupancy — whether
/// derived (a live dine-in order) or a manual hold — dominates a reservation, and a
/// reserved member makes the whole group reserved. This mirrors the per-table backend
/// rule `app.table_effective_state`, applied ACROSS the members of a group: each
/// member's [effectiveState] already fused its own manual status with its own derived
/// occupancy, so the group state is the highest-precedence member state.
int tableEffectiveStateRank(String effectiveState) => switch (effectiveState) {
  'out_of_service' => 4,
  'occupied' => 3,
  'reserved' => 2,
  _ => 1, // available / unknown fails to the lowest (never masks a real hold)
};

/// The aggregated group-wide state + count that every member of a group projects.
class TableGroupAggregate {
  const TableGroupAggregate({
    required this.effectiveState,
    required this.activeOrderCount,
  });

  /// The group-wide effective state (highest-precedence member state).
  final String effectiveState;

  /// The group-wide active dine-in order count (the SUM across members).
  final int activeOrderCount;

  /// A group is selectable for a NEW dine-in order only when it is fully available.
  bool get isAvailable => effectiveState == 'available';
}

/// Aggregates the members of ONE group into a single group-wide state + count.
///
/// [members] are `(effectiveState, activeOrderCount)` for every table sharing the
/// group id. The effective state is the highest-precedence member state; the count is
/// the SUM — each active order sits on exactly one physical table, so summing the
/// per-member counts can never double-count the same order. Historical takeaway rows
/// never carry dine-in occupancy, so they never contribute (the per-member counts are
/// already dine-in-only, per the backend).
TableGroupAggregate aggregateTableGroup(
  Iterable<({String effectiveState, int activeOrderCount})> members,
) {
  var bestRank = 0;
  var effective = 'available';
  var count = 0;
  for (final m in members) {
    count += m.activeOrderCount;
    final rank = tableEffectiveStateRank(m.effectiveState);
    if (rank > bestRank) {
      bestRank = rank;
      effective = m.effectiveState;
    }
  }
  return TableGroupAggregate(
    effectiveState: effective,
    activeOrderCount: count,
  );
}
