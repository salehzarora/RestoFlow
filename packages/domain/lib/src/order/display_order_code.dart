/// A short, human-facing display code derived DETERMINISTICALLY from an order
/// id, so every surface (POS confirmation/receipt, KDS ticket) shows the SAME
/// number for the same order without any extra wire field.
///
/// The backend has no per-branch order number yet — the only server-assigned
/// human number is the RF-054 `receipt_number`, which exists only once a
/// payment is recorded (and is redacted from kitchen pulls, T-003). Until a
/// proper order-number column lands (its own API-contract ticket), this code
/// is the shared display label: the LAST 6 hex characters of the order UUID,
/// uppercased, prefixed with '#'. Collisions within one shift are unlikely
/// (16^6 space) and harmless (a display label, never an identifier).
String displayOrderCode(String orderId) {
  final hex = orderId.replaceAll('-', '');
  final tail = hex.length <= 6 ? hex : hex.substring(hex.length - 6);
  return '#${tail.toUpperCase()}';
}
