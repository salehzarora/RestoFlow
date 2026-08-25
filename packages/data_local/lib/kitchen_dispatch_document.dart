/// KIOSK-PRINT-114B.5A — the WEB-SAFE kitchen dispatch document library.
///
/// Exposes ONLY the money-free dispatch payload model
/// ([KitchenDispatchDocument] + its items/prep/modifier types and the
/// hostile-key validator), the dispatch kind enum, and the dispatch bytes
/// renderer seam ([KitchenDispatchBytesRenderer] + the legacy
/// [KitchenTicketRenderer]) — as a DEDICATED library, deliberately separate
/// from the package barrel.
///
/// WHY: the barrel (`restoflow_data_local.dart`) also exports the Drift/SQLite
/// stores, which must never reach a `flutter build web` graph. The canonical
/// kitchen ticket adapter in `restoflow_feature_kitchen` (consumed by the POS
/// web build and the kiosk) needs the payload model only; importing it from
/// here keeps every file on this graph free of `dart:ffi` / `package:drift`
/// (the three files below import nothing but `dart:convert`, `dart:typed_data`,
/// `restoflow_domain` and `restoflow_printing`).
library;

export 'src/kitchen_spool/kitchen_spool_payload.dart';
export 'src/kitchen_spool/kitchen_spool_status.dart';
export 'src/kitchen_spool/kitchen_ticket_renderer.dart';
