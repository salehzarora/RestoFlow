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

/// The CANONICAL normalized operational states (Finding 6). Any value outside the four
/// known server states normalizes to 'unknown' — a fail-closed, NON-assignable state
/// ranked MORE restrictive than 'available', so a merge is deterministic regardless of
/// input order and an unrecognized/missing state can never present as free capacity.
const List<String> kTableEffectiveStates = <String>[
  'out_of_service',
  'occupied',
  'reserved',
  'available',
  'unknown',
];

/// Normalizes any effective-state value to one of [kTableEffectiveStates]. Unrecognized
/// / missing values become 'unknown' — never silently coerced to 'available'.
String normalizeTableEffectiveState(String effectiveState) =>
    switch (effectiveState) {
      'out_of_service' ||
      'occupied' ||
      'reserved' ||
      'available' => effectiveState,
      _ => 'unknown',
    };

/// GROUP effective-state precedence rank (higher wins), on the NORMALIZED state. The
/// DOCUMENTED single source of truth for a linked group's fused state:
///
///   out_of_service (5) > occupied (4) > reserved (3) > unknown (2) > available (1)
///
/// Every state has a DISTINCT rank, so merging two states with a strict `>` is
/// deterministic regardless of input order (Finding 6). A group is 'available' ONLY
/// when every member is available. 'unknown' outranks 'available' (fail-closed:
/// available + unknown resolves to unknown, never to a selectable available), while a
/// known hold (reserved/occupied/out_of_service) is more informative and outranks
/// unknown. This mirrors the per-table backend rule `app.table_effective_state`, applied
/// ACROSS the members of a group: each member's [effectiveState] already fused its own
/// manual status with its own derived occupancy, so the group state is the
/// highest-precedence member state.
int tableEffectiveStateRank(String effectiveState) =>
    switch (normalizeTableEffectiveState(effectiveState)) {
      'out_of_service' => 5,
      'occupied' => 4,
      'reserved' => 3,
      'unknown' => 2,
      _ => 1, // available
    };

/// The more RESTRICTIVE (higher-rank) of two states, NORMALIZED and deterministic —
/// the merge rule for two rows of the SAME physical table. Commutative: swapping the
/// arguments yields the same result (equal ranks only occur for equal normalized
/// states, so ties are trivially deterministic). Callers that project deduplicated
/// table lists (Finding 5) use this to merge a duplicate physical row's state.
String mostRestrictiveTableState(String a, String b) =>
    tableEffectiveStateRank(a) >= tableEffectiveStateRank(b)
    ? normalizeTableEffectiveState(a)
    : normalizeTableEffectiveState(b);

/// One member row fed to [aggregateTableGroup]: the PHYSICAL table id plus that
/// table's own (already-fused) effective state and derived active dine-in count.
///
/// PILOT-OPERATIONS-CORRECTIONS-001 (Finding 4): the [tableId] is REQUIRED so the
/// aggregation can deduplicate by physical table — a row duplicated by an upstream
/// join/projection must never double a table's occupancy.
typedef TableGroupMember = ({
  String tableId,
  String effectiveState,
  int activeOrderCount,
});

/// The aggregated group-wide state + count that every member of a group projects.
class TableGroupAggregate {
  const TableGroupAggregate({
    required this.effectiveState,
    required this.activeOrderCount,
  });

  /// The group-wide effective state (highest-precedence member state), NORMALIZED.
  final String effectiveState;

  /// The group-wide active dine-in order count (the SUM across DISTINCT tables).
  final int activeOrderCount;

  /// A group is selectable for a NEW dine-in order only when it is fully available.
  /// An 'unknown' group is NOT available (fail-closed).
  bool get isAvailable => effectiveState == 'available';
}

/// Aggregates the members of ONE group into a single group-wide state + count.
///
/// STEP 1 — DEDUP BY PHYSICAL TABLE ID (Finding 4). A physical table contributes to a
/// group AT MOST ONCE, so a row duplicated upstream cannot double-count its orders.
/// When the same [TableGroupMember.tableId] appears more than once, its rows are merged
/// deterministically and SAFELY: the effective state becomes the most RESTRICTIVE of
/// them ([mostRestrictiveTableState]) and the active-order count becomes the MAX of them
/// (never the sum) — conflicting duplicates never turn into extra capacity or a
/// contradictory state.
///
/// STEP 2 — aggregate the DISTINCT physical members: the group effective state is the
/// highest-precedence per-table state; the count is the SUM across the distinct tables.
/// Each active dine-in order sits on exactly one physical table, so summing distinct
/// per-table counts can never double-count the same order. Historical takeaway rows
/// never carry dine-in occupancy, so they never contribute. The returned effective state
/// is NORMALIZED.
TableGroupAggregate aggregateTableGroup(Iterable<TableGroupMember> members) {
  // Step 1: collapse duplicate rows per physical table.
  final byTable = <String, ({String effectiveState, int activeOrderCount})>{};
  for (final m in members) {
    final existing = byTable[m.tableId];
    if (existing == null) {
      byTable[m.tableId] = (
        effectiveState: normalizeTableEffectiveState(m.effectiveState),
        activeOrderCount: m.activeOrderCount,
      );
    } else {
      // Restrictive merge: keep the higher-precedence state and the MAX count.
      final effective = mostRestrictiveTableState(
        m.effectiveState,
        existing.effectiveState,
      );
      final count = m.activeOrderCount > existing.activeOrderCount
          ? m.activeOrderCount
          : existing.activeOrderCount;
      byTable[m.tableId] = (effectiveState: effective, activeOrderCount: count);
    }
  }

  // Step 2: aggregate the distinct physical members.
  var bestRank = 0;
  var effective = 'available';
  var count = 0;
  for (final t in byTable.values) {
    count += t.activeOrderCount;
    final rank = tableEffectiveStateRank(t.effectiveState);
    if (rank > bestRank) {
      bestRank = rank;
      effective = t.effectiveState;
    }
  }
  return TableGroupAggregate(
    effectiveState: effective,
    activeOrderCount: count,
  );
}
