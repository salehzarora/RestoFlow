/// KITCHEN-PRINT-DUAL-001 — the WEB-SAFE kitchen-ticket input contract.
///
/// These plain, money-free DTOs sit on the POS **web** compile graph (the print
/// service, the submit hook, and the order-confirmation action all reference
/// them). They MUST NOT import `restoflow_data_local`/drift/sqlite3 — doing so
/// drags the native SQLite stack onto `flutter build web` (the Vercel target)
/// and fails with "dart:ffi is not available on this platform". The actual
/// money-free render lives in `lib/src/spool/kitchen_ticket_bytes.dart` behind a
/// `dart.library.io` conditional import.
library;

/// One money-free kitchen line: quantity, name, an optional kitchen note, and
/// pre-formatted modifier display strings. Structurally cannot carry a price.
final class KitchenTicketLineInput {
  const KitchenTicketLineInput({
    required this.qty,
    required this.name,
    this.note,
    this.modifiers = const [],
  });

  final int qty;
  final String name;
  final String? note;

  /// Modifier display strings (any "×N" is already baked in by the caller).
  final List<String> modifiers;
}

/// A money-free kitchen-ticket input for one created order.
final class KitchenTicketInput {
  const KitchenTicketInput({
    required this.orderCode,
    required this.orderType,
    this.tableLabel,
    this.customerName,
    this.orderNote,
    this.lines = const [],
    this.createdAtIso,
  });

  /// The human order code (e.g. `#000042`).
  final String orderCode;

  /// The order-type wire token (`dine_in` / `takeaway`) the kitchen labels map.
  final String orderType;
  final String? tableLabel;
  final String? customerName;
  final String? orderNote;
  final List<KitchenTicketLineInput> lines;
  final String? createdAtIso;
}
