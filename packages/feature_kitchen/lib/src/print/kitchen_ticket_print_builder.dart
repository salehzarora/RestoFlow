import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

import 'station_printer_routing.dart';

/// Builds a render-neutral, **money-free** kitchen-ticket [PrintDocument] from a
/// routed [KitchenTicket] + its source [LocalOrder] (RF-072).
///
/// Print layout lives here, NOT in the KDS UI. The document carries ONLY
/// operational fields — station header, order reference, service type,
/// timestamp, and per-item name/quantity/modifier-option-names/kitchen note
/// (product-rescue sprint: notes are operational kitchen data). It NEVER reads
/// money (`*_minor`/price/total), receipt, payment, cash, tax, or table number
/// (D-007/D-008; approved A2/A3/A4). All CHROME text is ASCII so it renders
/// deterministically through the RF-070 ESC/POS adapter; item/note text is
/// tenant DATA and may be any script.
class KitchenTicketPrintBuilder {
  const KitchenTicketPrintBuilder._();

  /// Build the document for [ticket] of [order]. [at] is injected for
  /// deterministic timestamps; [destination] supplies the station label.
  static PrintDocument build(
    KitchenTicket ticket,
    LocalOrder order, {
    required DateTime at,
    PrintDestination? destination,
  }) {
    // Modifier option-name snapshots per order item (join by orderItemId).
    final modsByItem = <String, List<String>>{
      for (final item in order.items)
        item.orderItemId: [
          for (final m in item.modifiers)
            m.quantity > 1
                ? '${m.optionNameSnapshot} x${m.quantity}'
                : m.optionNameSnapshot,
        ],
    };

    // Per-item kitchen notes (join by orderItemId). Note text is tenant data
    // (may be Arabic/Hebrew) — data, not chrome.
    final noteByItem = <String, String>{
      for (final item in order.items)
        if (item.note case final note?) item.orderItemId: note,
    };

    final lines = <PrintLine>[
      // Centered/bold station header (label falls back to the station id).
      PrintTextLine(
        destination?.label ?? ticket.stationId,
        alignment: PrintAlignment.center,
        emphasis: TextEmphasis.bold,
      ),
      PrintTextLine('Order: ${_orderRef(order.orderId)}'),
      PrintTextLine(_serviceType(order.orderType)),
      PrintTextLine(at.toIso8601String()),
      const PrintFeedLine(),
    ];

    for (final stationItem in ticket.stationItems) {
      lines.add(
        PrintTextLine(
          '${stationItem.itemNameSnapshot} x${stationItem.quantity}',
        ),
      );
      for (final modName in modsByItem[stationItem.orderItemId] ?? const []) {
        lines.add(PrintTextLine('  + $modName'));
      }
      // The item's kitchen note, after its modifier lines (absent when null).
      if (noteByItem[stationItem.orderItemId] case final note?) {
        lines.add(PrintTextLine('  * $note'));
      }
    }

    lines
      ..add(const PrintFeedLine(2))
      ..add(const PrintCutLine());

    return PrintDocument(lines, localeTag: null);
  }

  /// Deterministic order reference (approved A4): the full client order id (no
  /// receipt-numbering / human order-number logic).
  static String _orderRef(String orderId) => orderId;

  static String _serviceType(OrderType type) =>
      type == OrderType.dineIn ? 'Dine-in' : 'Takeaway';
}
