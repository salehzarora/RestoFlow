/// The print-job lifecycle state (RF-071, DECISION D-018; transitions owned by
/// docs/STATE_MACHINES.md §8). Pure Dart — the Drift converter lives in
/// `packages/data_local`.
///
/// `created -> queued -> printing -> printed`; `printing -> failed`;
/// `failed -> retrying -> printing`; `failed -> abandoned` (after max retries);
/// `created/queued/retrying -> cancelled`. Terminal: `printed`, `cancelled`,
/// `abandoned`. `possiblyPrinted` is a CRASH-RECOVERY limbo (a job left in
/// `printing` whose outcome is unknown): it is NOT terminal but has NO automatic
/// transition — it is resolved only by explicit staff action (a new reprint
/// job), which RF-071 does not wire. It is NEVER auto-retried (§8.3).
enum PrintJobState {
  created('created'),
  queued('queued'),
  printing('printing'),
  printed('printed'),
  failed('failed'),
  retrying('retrying'),
  cancelled('cancelled'),
  abandoned('abandoned'),
  possiblyPrinted('possibly_printed');

  const PrintJobState(this.wireName);

  /// The canonical persisted/transported value (snake_case).
  final String wireName;

  /// Parse a [wireName] back to its state. Throws [ArgumentError] if unknown.
  static PrintJobState fromWire(String wire) {
    for (final s in PrintJobState.values) {
      if (s.wireName == wire) return s;
    }
    throw ArgumentError.value(wire, 'wire', 'Unknown PrintJobState');
  }

  /// Terminal states accept no further transition. `possiblyPrinted` is
  /// deliberately NOT terminal (it awaits explicit resolution) but is a dead-end
  /// for the engine (see [_allowed]).
  static const Set<PrintJobState> terminals = {printed, cancelled, abandoned};

  bool get isTerminal => terminals.contains(this);

  /// Legal forward transitions (STATE_MACHINES §8). Terminal states and
  /// `possiblyPrinted` map to the empty set (no automatic transition).
  static const Map<PrintJobState, Set<PrintJobState>> _allowed = {
    created: {queued, cancelled},
    queued: {printing, cancelled},
    // `printing -> cancelled` is FORBIDDEN (cannot cancel mid-print, §8.2);
    // crash recovery moves an interrupted `printing` job to `possiblyPrinted`.
    printing: {printed, failed, possiblyPrinted},
    // `failed -> printed` directly is FORBIDDEN (must go through retrying).
    failed: {retrying, abandoned},
    retrying: {printing, cancelled},
    printed: <PrintJobState>{},
    cancelled: <PrintJobState>{},
    abandoned: <PrintJobState>{},
    possiblyPrinted: <PrintJobState>{},
  };

  /// `true` iff [from] -> [to] is a legal transition.
  static bool canTransition(PrintJobState from, PrintJobState to) =>
      _allowed[from]!.contains(to);

  /// Whether this state may transition to [next].
  bool canTransitionTo(PrintJobState next) => canTransition(this, next);

  /// Crash-recovery mapping: a job interrupted while `printing` becomes
  /// `possiblyPrinted` (outcome unknown — never auto-reprinted, §8.3). Every
  /// other state is returned unchanged.
  static PrintJobState recoverInterrupted(PrintJobState current) =>
      current == printing ? possiblyPrinted : current;
}
