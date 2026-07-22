import 'dart:typed_data' show Uint8List;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show kBluetoothPrintTimeout, nativePrintRasterizerProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../spool/kitchen_ticket_bytes.dart'
    show KitchenTicketInput, KitchenTicketLineInput, renderKitchenTicketBytes;
import '../state/cart_controller.dart' show CartLineView;
import '../state/pos_auto_print_prefs.dart';
import '../state/pos_bluetooth_printer_config.dart';
import '../state/pos_network_printer_config.dart';
import '../state/pos_printer_transport.dart';
import '../state/submitted_order_view.dart' show SubmittedOrderView;
import 'bluetooth_printer.dart';
import 'native_print_bridges.dart'
    show kPosNativePrintTimeout, posPrinterDestinationSendGateProvider;

// Callers depend only on this print seam for the money-free kitchen input DTO.
export '../spool/kitchen_ticket_bytes.dart'
    show KitchenTicketInput, KitchenTicketLineInput;

/// KITCHEN-PRINT-DUAL-001 — the POS dual-print KITCHEN service.
///
/// The cashier RECEIPT prints through the customer_receipt slot
/// ([posActivePrintBridgeProvider]); this prints the money-free KITCHEN ticket
/// through the INDEPENDENT kitchen_ticket slot ([posKitchenSelectedPrinterTransportProvider]
/// + kitchen network/bluetooth config). Both share the ONE process-wide
/// [posPrinterDestinationSendGateProvider], so when both purposes point at the
/// SAME physical printer the two documents serialize instead of interleaving.
/// The bytes come from the existing money-free [renderKitchenTicketBytes]
/// (never the receipt renderer).

/// The honest outcome of a kitchen-ticket send (bytes delivered to the printer
/// transport — never a hardware paper-print acknowledgement).
enum PosKitchenPrintOutcome {
  /// The bytes were accepted by the kitchen printer transport.
  printed,

  /// No kitchen printer is configured for this device.
  noPrinterConfigured,

  /// Native printing is unavailable on this build (e.g. web).
  unavailable,

  /// A kitchen printer was configured but the send failed.
  failed,
}

/// A resolved kitchen-ticket printer target for the current device.
final class ResolvedKitchenPrinter {
  const ResolvedKitchenPrinter({
    required this.destinationKey,
    required this.transportFactory,
  });

  /// Canonical per-endpoint key for the SHARED send gate (never logged). Equal
  /// to the customer slot's key when both purposes use the same physical
  /// printer, which is exactly how the shared gate serializes them.
  final String destinationKey;

  /// Builds a fresh transport per send (a socket/BT link is not reused).
  final pp.PrintTransport Function() transportFactory;
}

/// Resolves the KITCHEN slot into a send target, or null when native printing
/// is unavailable or no kitchen printer is configured. Independent of the
/// customer_receipt slot: configuring/removing one never affects the other.
Future<ResolvedKitchenPrinter?> resolveKitchenPrinterTarget(
  ProviderContainer container, {
  Duration networkTimeout = kPosNativePrintTimeout,
  Duration bluetoothTimeout = kBluetoothPrintTimeout,
}) async {
  if (!container.read(posNativePrintingAvailableProvider)) return null;
  final kind = await container.read(
    posKitchenSelectedPrinterTransportProvider.future,
  );
  switch (kind) {
    case PosPrinterTransportKind.network:
      final net = await container.read(
        posKitchenNetworkPrinterConfigProvider.future,
      );
      if (net == null) return null;
      return ResolvedKitchenPrinter(
        destinationKey: pp.PrinterDestinationSendGate.networkKey(
          net.host,
          net.port,
        ),
        transportFactory: () => pp.NetworkTcpPrintTransport(
          host: net.host,
          port: net.port,
          timeout: networkTimeout,
        ),
      );
    case PosPrinterTransportKind.bluetooth:
      final bt = await container.read(
        posKitchenBluetoothPrinterConfigProvider.future,
      );
      if (bt == null) return null;
      final connector = container.read(bluetoothPrinterConnectorProvider);
      return ResolvedKitchenPrinter(
        destinationKey: pp.PrinterDestinationSendGate.bluetoothKey(bt.address),
        transportFactory: () => BluetoothClassicPrintTransport(
          connector: connector,
          address: bt.address,
          timeout: bluetoothTimeout,
        ),
      );
  }
}

/// Whether THIS device has a native KITCHEN printer configured for the kitchen
/// slot's selected transport — the twin of `posHasNativePrinterProvider` for
/// the customer slot. Drives the auto-kitchen-print toggle's enabled state.
final posHasKitchenNativePrinterProvider = Provider<bool>((ref) {
  if (!ref.watch(posNativePrintingAvailableProvider)) return false;
  final kind =
      ref.watch(posKitchenSelectedPrinterTransportProvider).valueOrNull ??
      PosPrinterTransportKind.network;
  return switch (kind) {
    PosPrinterTransportKind.bluetooth =>
      ref.watch(posKitchenBluetoothPrinterConfigProvider).valueOrNull != null,
    PosPrinterTransportKind.network =>
      ref.watch(posKitchenNetworkPrinterConfigProvider).valueOrNull != null,
  };
});

/// The in-memory guard that stops a SINGLE order-creation operation from
/// auto-printing its kitchen ticket twice (double-tap / rebuild / a callback
/// firing twice). Session-scoped and best-effort — NOT crash-proof across
/// device data loss (the manual action remains an intentional reprint).
final class PosAutoKitchenPrintGuard {
  final Set<String> _claimed = {};

  /// Claims [orderId] for a first auto-print; returns false if already claimed.
  bool claim(String orderId) => _claimed.add(orderId);
}

final posAutoKitchenPrintGuardProvider = Provider<PosAutoKitchenPrintGuard>(
  (_) => PosAutoKitchenPrintGuard(),
);

/// The signature of the money-free bytes builder (injectable for tests).
typedef KitchenBytesBuilder =
    Future<Uint8List> Function({
      required KitchenTicketInput input,
      String? languageCode,
      pp.ReceiptRasterizer? rasterizer,
    });

/// Sends a money-free kitchen ticket to the resolved KITCHEN printer.
class PosKitchenTicketPrinter {
  PosKitchenTicketPrinter(
    this._container, {
    KitchenBytesBuilder buildBytes = renderKitchenTicketBytes,
    ResolvedKitchenPrinter? targetOverride,
  }) : _buildBytes = buildBytes,
       _targetOverride = targetOverride;

  final ProviderContainer _container;
  final KitchenBytesBuilder _buildBytes;

  /// Injectable resolved target for tests; real callers leave it null so the
  /// kitchen slot is resolved from this device's local config.
  final ResolvedKitchenPrinter? _targetOverride;

  /// Resolves the kitchen printer, renders the money-free ticket, and sends it
  /// under the shared destination gate.
  Future<PosKitchenPrintOutcome> printKitchenTicket({
    required KitchenTicketInput input,
    String? languageCode,
  }) async {
    if (!_container.read(posNativePrintingAvailableProvider)) {
      return PosKitchenPrintOutcome.unavailable;
    }
    final resolved =
        _targetOverride ?? await resolveKitchenPrinterTarget(_container);
    if (resolved == null) return PosKitchenPrintOutcome.noPrinterConfigured;

    final Uint8List bytes;
    try {
      bytes = await _buildBytes(
        input: input,
        languageCode: languageCode,
        rasterizer: _container.read(nativePrintRasterizerProvider),
      );
    } catch (_) {
      return PosKitchenPrintOutcome.failed;
    }

    final gate = _container.read(posPrinterDestinationSendGateProvider);
    final transport = resolved.transportFactory();
    try {
      final result = await gate.withDestination(
        resolved.destinationKey,
        () => transport.send(bytes),
      );
      return result.ok
          ? PosKitchenPrintOutcome.printed
          : PosKitchenPrintOutcome.failed;
    } catch (_) {
      return PosKitchenPrintOutcome.failed;
    } finally {
      await transport.dispose();
    }
  }
}

/// The MANUAL "Print kitchen ticket" entry point — an intentional print/reprint
/// for an already-created order. No idempotency guard (a deliberate press may
/// print again); it never changes order/payment/KDS state.
Future<PosKitchenPrintOutcome> printKitchenTicketForOrder({
  required ProviderContainer container,
  required KitchenTicketInput input,
  String? languageCode,
  PosKitchenTicketPrinter? printer,
}) => (printer ?? PosKitchenTicketPrinter(container)).printKitchenTicket(
  input: input,
  languageCode: languageCode,
);

/// The AUTOMATIC entry point, called after a successful order creation. Prints
/// exactly one kitchen ticket ONLY when the per-device setting is enabled and
/// this order was not already auto-printed this session. Best-effort — any
/// failure is swallowed so it can NEVER turn a successful order into a failure.
Future<PosKitchenPrintOutcome> runAutoKitchenTicketPrintOnSubmit({
  required ProviderContainer container,
  required String orderId,
  required KitchenTicketInput input,
  String? languageCode,
  PosKitchenTicketPrinter? printer,
}) async {
  final stored = container.read(posAutoPrintKitchenTicketProvider).valueOrNull;
  // The setting is OFF by default; when off the whole flow is inert.
  if (!(stored ?? false)) return PosKitchenPrintOutcome.noPrinterConfigured;
  // Duplicate protection: only the FIRST call for this order prints.
  if (!container.read(posAutoKitchenPrintGuardProvider).claim(orderId)) {
    return PosKitchenPrintOutcome.printed;
  }
  try {
    return await printKitchenTicketForOrder(
      container: container,
      input: input,
      languageCode: languageCode,
      printer: printer,
    );
  } catch (_) {
    return PosKitchenPrintOutcome.failed;
  }
}

/// Maps a live cart (the rich submit-time lines) to a money-free
/// [KitchenTicketInput]. Drops every price/total; keeps qty/name/note and the
/// modifier display names (with any "×N" folded in).
KitchenTicketInput kitchenTicketInputFromCartLines({
  required String orderCode,
  required OrderType orderType,
  required List<CartLineView> lines,
  String? tableLabel,
  String? customerName,
  String? createdAtIso,
}) => KitchenTicketInput(
  orderCode: orderCode,
  orderType: _orderTypeWire(orderType),
  tableLabel: tableLabel,
  customerName: customerName,
  createdAtIso: createdAtIso,
  lines: [
    for (final line in lines)
      KitchenTicketLineInput(
        qty: line.quantity,
        name: line.name,
        note: line.note,
        modifiers: [
          for (final modifier in line.modifiers)
            modifier.quantity > 1
                ? '${modifier.optionName} ×${modifier.quantity}'
                : modifier.optionName,
        ],
      ),
  ],
);

/// Maps an already-created [SubmittedOrderView] (flattened lines) to a
/// money-free [KitchenTicketInput] — used by the manual reprint action.
KitchenTicketInput kitchenTicketInputFromSubmittedOrder(
  SubmittedOrderView order,
) => KitchenTicketInput(
  orderCode: order.orderNumber,
  orderType: _orderTypeWire(order.orderType),
  tableLabel: order.tableLabel,
  customerName: order.customerName,
  lines: [
    for (final line in order.lines)
      KitchenTicketLineInput(
        qty: line.quantity,
        name: line.name,
        note: line.note,
        modifiers: line.modifiers,
      ),
  ],
);

String _orderTypeWire(OrderType type) =>
    type == OrderType.dineIn ? 'dine_in' : 'takeaway';
