/// MONEY-DURABLE-STORES-003B: the capability a durable local store exposes when
/// it can report on its OWN health.
///
/// Deliberately a small separate interface rather than members on
/// [DurableOutboxStore] / [PosDraftRecoveryStore]: those are seams with several
/// in-memory and test implementations that store nothing and therefore have
/// nothing to report, and widening them would force every one of them to answer
/// a question that does not apply. A caller asks with `store is
/// PosDurableStoreHealth` and simply learns nothing when the answer is absent —
/// which is the honest outcome, not a silent "healthy".
abstract class PosDurableStoreHealth {
  /// Whether a durable write has been REFUSED since this store was created, so
  /// storage is behind what the app believes.
  ///
  /// Latched deliberately: a later successful write of a DIFFERENT set does not
  /// restore the update that was lost. Cleared only by creating a new store,
  /// i.e. by restarting — at which point what is on disk IS what the app knows.
  bool get isDegraded;

  /// How many stored records this build cannot decode, plus how many whole
  /// envelopes it had to set aside. Non-zero means the till is holding local
  /// records it cannot act on and the operator has to be told: they are being
  /// preserved, not silently discarded, and they are not going to sync.
  ///
  /// [scopeKey] is the per-device scope for stores keyed by it (the outbox);
  /// stores with a single global key ignore it (the recovery map, which carries
  /// its scope binding inside each record instead).
  int unreadableRecordCount(String scopeKey);
}
