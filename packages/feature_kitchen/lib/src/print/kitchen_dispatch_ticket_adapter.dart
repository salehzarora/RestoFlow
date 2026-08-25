import 'dart:typed_data' show Uint8List;

import 'package:restoflow_data_local/kitchen_dispatch_document.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../kds_ticket_mapper.dart' show KdsTicketMapper;
import '../kds_ticket_view.dart';
import 'kds_ticket_print_builder.dart' show KitchenTicketPrintLabels;
import 'kitchen_ticket_render.dart' show renderKitchenTicketBytes;

/// KIOSK-PRINT-114B.5A — the CANONICAL dispatch → kitchen-ticket adapter.
///
/// Adapts the server's money-free dispatch payload ([KitchenDispatchDocument],
/// consumed by the POS printer-only drain and the kiosk claimed print) into the
/// SAME [KdsTicketView] the POS direct print builds from its cart lines and the
/// KDS builds from its sync rows — so every kitchen paper, whatever its origin
/// or path, is the ONE canonical ticket rendered by `buildKdsTicketPrintDocument`
/// (whole-order counts on top, then the items).
///
/// COUNT CONTRACT (KITCHEN-PREP-001 / KITCHEN-MEAT-001 / 114B.1):
///  * `item.prep` components are PER ONE ITEM UNIT — carried through as the
///    item's [KdsItemView.prepComponents] and fed to the shared aggregator,
///    which multiplies each by the line quantity EXACTLY once;
///  * a modifier's `prep` (the option's meat contribution) is PER ONE MODIFIER
///    UNIT — scaled by the modifier's own quantity here (`scaledBy`, exactly as
///    the POS cart projection `kitchenMeatSnapshots` does) and then by the line
///    quantity in the shared aggregator, never twice;
///  * the payload's own JSON shape is parsed by the SAME domain parsers the KDS
///    mapper uses ([KitchenPrepComponent.tryFromJson], [KitchenMeat.tryFromJson]),
///    so blank-name / non-positive / malformed entries are dropped identically.
///
/// Nothing is re-derived from the live menu (D-008): a dispatch without prep
/// (a pre-114B.1 historical kiosk order, or an item with no configured
/// components) simply yields no count block. Money-free by construction — a
/// [KdsTicketView] cannot carry money (D-007).
KdsTicketView kdsTicketViewFromKitchenDispatch(
  KitchenDispatchDocument dispatch, {
  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap C): the OPTIONAL phone from the
  // encrypted local payload (crash-recovery replay). Null keeps the document's
  // own (always-null persisted) value.
  String? customerPhoneOverride,
}) {
  final items = <KdsItemView>[];
  final countInputs = <KitchenCountItemInput>[];
  for (var i = 0; i < dispatch.items.length; i++) {
    final item = dispatch.items[i];
    final position = i + 1;
    final prepComponents = parseKitchenPrepComponents([
      for (final prep in item.prep) prep.toJson(),
    ]);
    final meats = <KitchenMeat>[
      for (final modifier in item.modifiers)
        if (modifier.prep case final prep?)
          if (modifier.qty > 0)
            if (KitchenMeat.tryFromJson(prep.toJson()) case final meat?)
              meat.scaledBy(modifier.qty),
    ];
    items.add(
      KdsItemView(
        name: item.name,
        quantity: item.qty,
        modifiers: [
          for (final modifier in item.modifiers)
            modifier.qty > 1
                ? '${modifier.name} ×${modifier.qty}'
                : modifier.name,
        ],
        note: item.note,
        prepComponents: prepComponents,
        linePosition: position,
      ),
    );
    countInputs.add(
      KitchenCountItemInput(
        quantity: item.qty,
        meats: meats,
        prepComponents: prepComponents,
        // The dispatch builder already emits items in the canonical print
        // order; the explicit 1-based position keeps the shared aggregator's
        // canonicalization a no-op by VALUE (017), exactly like the POS mapper.
        linePosition: position,
      ),
    );
  }
  return KdsTicketView(
    // A dispatch has no server kitchen-ticket id; the order code is the header
    // (orderNumber) and the id fallback both — the same as the POS direct ticket.
    kitchenTicketId: dispatch.orderCode,
    // Whole-order print — never station-routed, so the station line is
    // suppressed (the shared builder hides the unassigned station).
    stationId: KdsTicketMapper.unassignedStation,
    items: items,
    status: KitchenTicketStatus.newTicket,
    orderNumber: dispatch.orderCode,
    orderType: dispatch.orderType,
    tableLabel: dispatch.tableLabel,
    customerName: dispatch.customerDisplayName,
    customerPhone: customerPhoneOverride ?? dispatch.customerPhone,
    notes: dispatch.orderNote,
    // KIOSK-PRINT-114B.6: the ORDER CREATION instant the server stamped on the
    // dispatch (`created_at`, ISO-8601), in local time for the ticket header;
    // absent/unparseable => no timestamp line (never the print time).
    submittedAt: dispatch.createdAt == null
        ? null
        : DateTime.tryParse(dispatch.createdAt!)?.toLocal(),
    kitchenCounts: aggregateOrderKitchenCounts(countInputs),
    // DEFERRED-ORDER-AMENDMENTS-001: null on an initial order (the shared
    // builder then prints no addition marker); the applied round identity on a
    // service-round dispatch.
    roundId: dispatch.roundId,
    roundNumber: dispatch.roundNumber,
  );
}

/// KIOSK-PRINT-114B.5A — the CANONICAL [KitchenDispatchBytesRenderer].
///
/// For every normal dispatch (initial order / service round) it adapts the
/// document through [kdsTicketViewFromKitchenDispatch] and encodes it through
/// the ONE shared [renderKitchenTicketBytes] seam — the exact bytes the POS
/// direct print emits for the same order. A VOID notice has no canonical
/// representation (the shared builder knows initial/addition kinds only), so it
/// is delegated UNCHANGED to the legacy [KitchenTicketRenderer] frame: void
/// paper keeps its banner, reason and affected-count lines byte-for-byte.
final class CanonicalKitchenDispatchRenderer
    implements KitchenDispatchBytesRenderer {
  CanonicalKitchenDispatchRenderer({
    required this.labels,
    this.rasterizer,
    this.restaurantName,
    this.mediaProfile,
    KitchenTicketRenderer? voidRenderer,
  }) : _voidRenderer =
           voidRenderer ?? KitchenTicketRenderer(rasterizer: rasterizer);

  /// The shared chrome labels (see `kitchenTicketPrintLabelsFromL10n`).
  final KitchenTicketPrintLabels labels;

  /// The app-injected raster seam (PRINT-RTL-001); null keeps the text path.
  final pp.ReceiptRasterizer? rasterizer;

  /// PRINT-LAYOUT-001B: the brand header; null => the labels' fallback.
  final String? restaurantName;

  /// PRINT-LAYOUT-001A: the kitchen media profile; null => 80mm continuous,
  /// byte-identical to the legacy 80mm-only drain.
  final pp.MediaProfile? mediaProfile;

  final KitchenTicketRenderer _voidRenderer;

  @override
  Future<Uint8List> renderToBytes(
    KitchenDispatchDocument dispatch, {
    String? customerPhoneOverride,
  }) {
    if (dispatch.kind == KitchenSpoolDispatchType.voidNotice) {
      return _voidRenderer.renderToBytes(
        dispatch,
        customerPhoneOverride: customerPhoneOverride,
      );
    }
    return renderKitchenTicketBytes(
      ticket: kdsTicketViewFromKitchenDispatch(
        dispatch,
        customerPhoneOverride: customerPhoneOverride,
      ),
      labels: labels,
      rasterizer: rasterizer,
      mediaProfile: mediaProfile,
      restaurantName: restaurantName,
    );
  }
}
