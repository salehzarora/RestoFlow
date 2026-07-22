import 'dart:async' show Completer, unawaited;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        KitchenCountItemInput,
        KitchenMeat,
        KitchenPrepComponent,
        KitchenTicketStatus,
        OrderType,
        aggregateOrderKitchenCounts;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show KitchenTicketPrintLabels;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView, KdsTicketMapper, KdsTicketView;
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show kBluetoothPrintTimeout, nativePrintRasterizerProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../data/order_submission.dart' show kPermanentRejectionCodes;
import '../state/cart_controller.dart' show CartLineView;
import '../state/pos_auto_print_prefs.dart';
import '../state/pos_bluetooth_printer_config.dart';
import '../state/pos_network_printer_config.dart';
import '../state/pos_printer_transport.dart';
import '../state/submitted_order_view.dart' show SubmittedOrderView;
import 'bluetooth_printer.dart';
import 'kitchen_ticket_render.dart' show renderKitchenTicketBytes;
import 'native_print_bridges.dart'
    show kPosNativePrintTimeout, posPrinterDestinationSendGateProvider;

// Callers depend on the SHARED kitchen contract: a KdsTicketView (the same model
// the KDS renders) + its localized chrome labels.
export 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show KitchenTicketPrintLabels;
export 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketView;
export 'kitchen_ticket_labels.dart' show kitchenTicketPrintLabelsFromL10n;

/// KITCHEN-PRINT-DUAL-001 / 001B — the POS dual-print KITCHEN service.
///
/// The cashier RECEIPT prints through the customer_receipt slot
/// ([posActivePrintBridgeProvider]); this prints the money-free KITCHEN ticket
/// through the INDEPENDENT kitchen_ticket slot ([posKitchenSelectedPrinterTransportProvider]
/// + kitchen network/bluetooth config). Both share the ONE process-wide
/// [posPrinterDestinationSendGateProvider], so when both purposes point at the
/// SAME physical printer the two documents serialize instead of interleaving.
///
/// 001B: the ticket bytes come from [renderKitchenTicketBytes], which renders the
/// SHARED `buildKdsTicketPrintDocument` layout the KDS live print uses — so a
/// ticket printed straight from the POS carries the SAME operational detail
/// (structured modifiers, whole-order kitchen counts, prep, kitchen notes,
/// table/order type) as one printed from the KDS. Never the receipt renderer.

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

  /// The order is not eligible for kitchen printing (demo / blank / placeholder
  /// id, or a permanently-rejected order with no real server order).
  ineligibleOrder,
}

/// The SINGLE production eligibility rule for kitchen-printing an order — used by
/// BOTH the automatic submit path and the manual OrderConfirmation button, so
/// the two can never diverge. An order is eligible only when:
///
///  * it is NOT a demo order (demo mode, or a `demo-…` placeholder id);
///  * it carries a real, non-blank server order id; and
///  * it was NOT permanently rejected — any code in the canonical
///    [kPermanentRejectionCodes] (a permanently-rejected order has no server
///    order to cook).
bool isOrderEligibleForKitchenPrint({
  required String? orderId,
  required bool isDemoMode,
  String? rejectionCode,
}) {
  if (isDemoMode) return false;
  final id = orderId?.trim();
  if (id == null || id.isEmpty || id.startsWith('demo-')) return false;
  if (rejectionCode != null &&
      kPermanentRejectionCodes.contains(rejectionCode)) {
    return false;
  }
  return true;
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

/// The retry-safe, in-memory guard for AUTOMATIC kitchen printing.
///
/// It tracks an explicit per-order lifecycle — idle → inFlight → succeeded — so
/// that (unlike a claim-once set) a FAILED attempt releases the order for a
/// later legitimate retry, and only a CONFIRMED success suppresses duplicate
/// automatic callbacks. Concurrent callbacks for the same order share the one
/// in-flight attempt. Session-scoped and best-effort — NOT crash-proof across
/// device data loss. The MANUAL action never uses this guard (a deliberate
/// reprint is always allowed).
final class PosAutoKitchenPrintGuard {
  final Map<String, Future<PosKitchenPrintOutcome>> _inFlight = {};
  final Set<String> _succeeded = {};

  /// Runs [attempt] for [orderId] under the retry-safe lifecycle:
  ///  * a prior CONFIRMED success returns [PosKitchenPrintOutcome.printed]
  ///    without re-sending;
  ///  * an in-flight attempt is SHARED (a concurrent duplicate callback awaits
  ///    the same send, so exactly one physical send happens);
  ///  * a non-`printed` outcome (no printer / render / transport / thrown)
  ///    RELEASES the order so a later legitimate retry can run.
  ///
  /// The returned outcome always matches the real send result.
  Future<PosKitchenPrintOutcome> runGuarded(
    String orderId,
    Future<PosKitchenPrintOutcome> Function() attempt,
  ) {
    if (_succeeded.contains(orderId)) {
      return Future.value(PosKitchenPrintOutcome.printed);
    }
    final active = _inFlight[orderId];
    if (active != null) return active;

    // Race-safe: publish the in-flight future via a Completer FIRST, then invoke
    // attempt() inside a guarded driver. This holds even if attempt() throws
    // SYNCHRONOUSLY (before returning a Future) — the `finally` always removes
    // the in-flight entry, so a failed order is never permanently retained.
    final completer = Completer<PosKitchenPrintOutcome>();
    _inFlight[orderId] = completer.future;
    unawaited(_drive(orderId, attempt, completer));
    return completer.future;
  }

  Future<void> _drive(
    String orderId,
    Future<PosKitchenPrintOutcome> Function() attempt,
    Completer<PosKitchenPrintOutcome> completer,
  ) async {
    PosKitchenPrintOutcome outcome;
    try {
      // A synchronous throw from attempt() is caught here just like an async one.
      outcome = await attempt();
    } catch (_) {
      outcome = PosKitchenPrintOutcome.failed;
    } finally {
      // ALWAYS release: any non-success leaves the order un-succeeded, so a
      // later legitimate retry can run; a concurrent duplicate shared this same
      // future while it was in flight.
      _inFlight.remove(orderId);
    }
    if (outcome == PosKitchenPrintOutcome.printed) {
      _succeeded.add(orderId); // suppress duplicate auto callbacks this session
    }
    completer.complete(outcome);
  }
}

final posAutoKitchenPrintGuardProvider = Provider<PosAutoKitchenPrintGuard>(
  (_) => PosAutoKitchenPrintGuard(),
);

/// TEST SEAM: overrides how the kitchen printer builds its transport, so a
/// real-path (CartPanel / OrderConfirmation) test can capture the routed
/// endpoint + bytes without opening a socket. Null (the production default)
/// uses the resolved target's real per-endpoint transport. It receives the
/// resolved target — which carries the canonical destination key — so a test
/// can assert the exact endpoint the kitchen ticket reached.
final kitchenPrintTransportOverrideProvider =
    Provider<pp.PrintTransport Function(ResolvedKitchenPrinter target)?>(
      (_) => null,
    );

/// The signature of the money-free bytes builder (injectable for tests).
typedef KitchenBytesBuilder =
    Future<Uint8List> Function({
      required KdsTicketView ticket,
      required KitchenTicketPrintLabels labels,
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
    required KdsTicketView ticket,
    required KitchenTicketPrintLabels labels,
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
        ticket: ticket,
        labels: labels,
        rasterizer: _container.read(nativePrintRasterizerProvider),
      );
    } catch (_) {
      return PosKitchenPrintOutcome.failed;
    }

    final gate = _container.read(posPrinterDestinationSendGateProvider);
    final override = _container.read(kitchenPrintTransportOverrideProvider);
    final transport = override != null
        ? override(resolved)
        : resolved.transportFactory();
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
  required KdsTicketView ticket,
  required KitchenTicketPrintLabels labels,
  PosKitchenTicketPrinter? printer,
}) => (printer ?? PosKitchenTicketPrinter(container)).printKitchenTicket(
  ticket: ticket,
  labels: labels,
);

/// The AUTOMATIC entry point, called after a successful order creation. Prints
/// exactly one kitchen ticket ONLY when the order is eligible, the per-device
/// setting is enabled, and this order was not already auto-printed this session.
/// Best-effort — any failure is swallowed so it can NEVER turn a successful
/// order into a failure, and a failed attempt is released for a later retry.
///
/// 001B: this is ADDITIVE — when [enabled] it prints; it NEVER turns a successful
/// order into a failure. 001C: [enabled] is the IMMUTABLE decision the caller
/// resolved BEFORE the first submission await (the same decision that set the
/// order's dispatch_mode), so the print and the dispatch can never disagree and a
/// toggle change mid-submit cannot split the workflow — this NO LONGER re-reads
/// the toggle here.
Future<PosKitchenPrintOutcome> runAutoKitchenTicketPrintOnSubmit({
  required ProviderContainer container,
  required String orderId,
  required KdsTicketView ticket,
  required KitchenTicketPrintLabels labels,
  bool? enabled,
  bool isDemoMode = false,
  String? rejectionCode,
  PosKitchenTicketPrinter? printer,
}) async {
  // Rejected / demo / blank / placeholder orders never print (shared rule).
  if (!isOrderEligibleForKitchenPrint(
    orderId: orderId,
    isDemoMode: isDemoMode,
    rejectionCode: rejectionCode,
  )) {
    return PosKitchenPrintOutcome.ineligibleOrder;
  }
  // 001C: PREFER the caller's IMMUTABLE pre-await decision — the production path
  // (CartPanel) resolves it ONCE before the submit await (the same decision that
  // set the order's dispatch_mode) and never re-reads the toggle here. Only a
  // caller that did NOT pre-resolve falls back to the cold-start-correct toggle
  // read below (it may still be AsyncLoading right after restart; a sync read
  // would wrongly see false — fail closed on a real read error).
  final bool effectiveEnabled;
  if (enabled != null) {
    effectiveEnabled = enabled;
  } else {
    try {
      effectiveEnabled =
          (await container.read(posAutoPrintKitchenTicketProvider.future)) ??
          false;
    } catch (_) {
      return PosKitchenPrintOutcome.failed;
    }
  }
  if (!effectiveEnabled) return PosKitchenPrintOutcome.noPrinterConfigured;
  // Retry-safe: one confirmed send suppresses duplicate callbacks; any failure
  // releases the order so a later legitimate retry can send exactly once.
  return container
      .read(posAutoKitchenPrintGuardProvider)
      .runGuarded(
        orderId,
        () => printKitchenTicketForOrder(
          container: container,
          ticket: ticket,
          labels: labels,
          printer: printer,
        ),
      );
}

/// Maps a live cart (the rich submit-time lines) + the menu's PER-ITEM prep
/// snapshot into the SHARED [KdsTicketView] — the SAME model the KDS renders —
/// so the POS direct kitchen print carries the SAME detail. Money-free: keeps
/// only qty/name/note, the structured modifier display names (with any "×N"
/// folded in), the item prep components, and the whole-order kitchen counts
/// (owner-configured meat + prep, aggregated exactly as the KDS mapper does).
/// Drops every price/total — a [KdsTicketView] cannot carry money.
///
/// [prepByItemId] is the live menu's `menuItemId -> prepComponents` snapshot
/// (D-008), looked up the SAME way the outbox builds the order payload; empty
/// for unconfigured items.
KdsTicketView kdsTicketViewFromCartLines({
  required String orderCode,
  required OrderType orderType,
  required List<CartLineView> lines,
  Map<String, List<KitchenPrepComponent>> prepByItemId =
      const <String, List<KitchenPrepComponent>>{},
  String? tableLabel,
  String? customerName,
  String? orderNote,
}) {
  final items = <KdsItemView>[];
  final countInputs = <KitchenCountItemInput>[];
  for (final line in lines) {
    final prep =
        prepByItemId[line.menuItemId] ?? const <KitchenPrepComponent>[];
    items.add(
      KdsItemView(
        name: line.name,
        quantity: line.quantity,
        // Structured modifier lines (name first, ×N when >1 — the KDS convention).
        modifiers: [
          for (final modifier in line.modifiers)
            modifier.quantity > 1
                ? '${modifier.optionName} ×${modifier.quantity}'
                : modifier.optionName,
        ],
        note: line.note,
        prepComponents: prep,
      ),
    );
    // KITCHEN-MEAT-001: an option's meat_snapshot, PRE-multiplied by its modifier
    // units (× the item quantity is the count factor, applied by the aggregator).
    countInputs.add(
      KitchenCountItemInput(
        quantity: line.quantity,
        meats: [
          for (final modifier in line.modifiers)
            if (modifier.kitchenMeat case final meat?)
              if (modifier.quantity > 0)
                KitchenMeat(
                  quantity: meat.quantity * modifier.quantity,
                  unit: meat.unit,
                ),
        ],
        prepComponents: prep,
      ),
    );
  }
  return KdsTicketView(
    // A POS direct ticket has no server kitchen-ticket id; the order code is the
    // header (orderNumber) and the id fallback both.
    kitchenTicketId: orderCode,
    // Whole-order print — never station-routed, so the station line is suppressed.
    stationId: KdsTicketMapper.unassignedStation,
    items: items,
    status: KitchenTicketStatus.newTicket,
    orderNumber: orderCode,
    orderType: _orderTypeWire(orderType),
    tableLabel: tableLabel,
    customerName: customerName,
    notes: orderNote,
    kitchenCounts: aggregateOrderKitchenCounts(countInputs),
  );
}

/// Maps an already-created [SubmittedOrderView] (flattened lines) to a
/// [KdsTicketView] — used by the manual reprint action. The confirmation
/// snapshot carries name/qty/modifiers/note/table/customer/type but NOT the
/// per-item prep/meat snapshot, so a reprinted ticket omits the whole-order
/// counts (it is a best-effort reprint of what the confirmation shows).
KdsTicketView kdsTicketViewFromSubmittedOrder(SubmittedOrderView order) =>
    KdsTicketView(
      kitchenTicketId: order.orderNumber,
      stationId: KdsTicketMapper.unassignedStation,
      items: [
        for (final line in order.lines)
          KdsItemView(
            name: line.name,
            quantity: line.quantity,
            // Already pre-formatted as `name ×N` on the submitted view.
            modifiers: line.modifiers,
            note: line.note,
          ),
      ],
      status: KitchenTicketStatus.newTicket,
      orderNumber: order.orderNumber,
      orderType: _orderTypeWire(order.orderType),
      tableLabel: order.tableLabel,
      customerName: order.customerName,
    );

String _orderTypeWire(OrderType type) =>
    type == OrderType.dineIn ? 'dine_in' : 'takeaway';
