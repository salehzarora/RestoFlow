/// POS-OPERATIONS-SYNC-001 (second review correction) — THE identity of an order.
///
/// There is exactly ONE answer to "which order is this?", and it is NOT the thing
/// printed on the ticket.
///
/// `orderNumber` (`#XXXXXX`) is a SHORTENED, human-facing reference — the tail of the
/// order UUID. It was never promised to be unique and it is not: two genuinely
/// different server orders can carry the same code. The POS nevertheless used it as a
/// map key for payments, voids, receipts, recovery and dedupe, which meant a real
/// collision did not degrade gracefully — it MISFILED MONEY. The payment taken for
/// order A attached to order B, both rows inherited the one payment marker, B's
/// controls vanished, and B could serve up A's receipt. A display string is for
/// reading. It is not an identity, and this type exists so the compiler stops us from
/// confusing the two ever again.
///
/// The three kinds, in priority order:
///
///   * [server]  — the authoritative `orders.id`. The ONLY identity for a persisted
///                 order, and the only one two devices can agree on.
///   * [local]   — a row the server has not acknowledged yet (a queued submit, a
///                 draft). Its own local operation / outbox id: unique on this device,
///                 which is the only place it exists.
///   * [legacyDisplayCode] — LAST RESORT. Pre-upgrade persisted data that carries
///                 neither id. It is honestly marked as what it is, so it can never be
///                 mistaken for an authoritative identity, and it can never merge with
///                 one: a legacy row keyed `num:#A1B2C3` does not collide with the
///                 server row keyed `srv:<uuid>` even when their codes match.
///
/// Two different kinds NEVER collide, because the kind is part of the key.
library;

/// The identity of one order, for ASSOCIATION and DEDUPE — payment, void, receipt,
/// mutation, recovery. Never for display.
class PosOrderIdentity {
  const PosOrderIdentity._(this.key, this.isAuthoritative);

  /// The opaque association key. Prefixed by KIND, so a local row and a server row
  /// can never be merged merely because their display codes happen to agree.
  final String key;

  /// True only for a SERVER-backed identity — the kind two devices can agree on.
  final bool isAuthoritative;

  /// The authoritative identity of a persisted server order.
  factory PosOrderIdentity.server(String orderId) =>
      PosOrderIdentity._('srv:$orderId', true);

  /// A row that exists only on this device so far (queued submit / draft).
  factory PosOrderIdentity.local(String localId) =>
      PosOrderIdentity._('loc:$localId', false);

  /// LEGACY / LAST RESORT: a row that carries no id at all. Kept so a pre-upgrade
  /// persisted order is still addressable rather than being silently dropped — but
  /// marked non-authoritative, because a display code is a guess about identity and
  /// we will not pretend otherwise.
  factory PosOrderIdentity.legacyDisplayCode(String orderNumber) =>
      PosOrderIdentity._('num:$orderNumber', false);

  /// Resolves the best identity available, strongest first.
  ///
  /// A server id ALWAYS wins: once the server has named an order, that is its name,
  /// and any local id we also happen to hold is an implementation detail of how it got
  /// there.
  static PosOrderIdentity of({
    String? orderId,
    String? localOperationId,
    String? outboxEntryId,
    String orderNumber = '',
  }) {
    if (orderId != null && orderId.isNotEmpty) {
      return PosOrderIdentity.server(orderId);
    }
    final local = _firstNonEmpty(localOperationId, outboxEntryId);
    if (local != null) return PosOrderIdentity.local(local);
    return PosOrderIdentity.legacyDisplayCode(orderNumber);
  }

  @override
  bool operator ==(Object other) =>
      other is PosOrderIdentity && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

String? _firstNonEmpty(String? a, String? b) {
  if (a != null && a.isNotEmpty) return a;
  if (b != null && b.isNotEmpty) return b;
  return null;
}
