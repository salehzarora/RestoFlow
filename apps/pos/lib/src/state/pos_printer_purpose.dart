/// KITCHEN-MODE-001B: the POS's two LOCAL printer purposes.
///
/// Purpose-scoped local slots let one POS hold TWO independent printer
/// selections — the customer receipt printer and the kitchen ticket printer —
/// which may be two different physical printers or the SAME endpoint stored in
/// both slots (purpose-scoped independent configs; copying the customer
/// endpoint into the kitchen slot is an explicit user action, never a hidden
/// link — changing one slot afterwards NEVER changes the other).
///
/// COMPATIBILITY (identity migration): [customerReceipt] maps to the exact
/// LEGACY `shared_preferences` keys that every existing installation already
/// uses (`restoflow.printer.<kind>.pos.<device>`), so a cashier's existing
/// receipt printer IS the customer slot — nothing is copied, nothing can fail,
/// legacy keys stay intact, and re-running the mapping is trivially idempotent.
/// [kitchenTicket] uses new purpose-suffixed keys
/// (`restoflow.printer.<kind>.pos.kitchen_ticket.<device>`) and starts UNSET.
///
/// DORMANT preparation only: configuring/testing the kitchen slot is allowed
/// before printer-only activation, but NOTHING automatic prints kitchen
/// tickets in this phase — the receipt controller resolves the customer slot
/// only, and no order/payment behavior changes (KITCHEN-MODE-001C wires the
/// workflow).
enum PosPrinterPurpose {
  customerReceipt('customer_receipt'),
  kitchenTicket('kitchen_ticket');

  const PosPrinterPurpose(this.wire);

  /// The stable key/wire segment (`customer_receipt` / `kitchen_ticket`).
  final String wire;

  /// The extra key segment for purpose-scoped `shared_preferences` keys.
  /// Empty for [customerReceipt] — its slot IS the legacy key (see above).
  String get keySegment =>
      this == PosPrinterPurpose.customerReceipt ? '' : '$wire.';
}
