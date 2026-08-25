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
        aggregateOrderKitchenCounts,
        sortByMenuPrintOrder;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show KitchenTicketPrintLabels;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView, KdsTicketMapper, KdsTicketView;
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show kBluetoothPrintTimeout, nativePrintRasterizerProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../data/order_submission.dart' show kPermanentRejectionCodes;
import '../state/cart_controller.dart'
    show CartLineView, classifiedPrepForLine, kitchenMeatSnapshots;
import '../state/outbox_controller.dart' show outboxControllerProvider;
import '../state/pos_auto_print_prefs.dart';
import '../state/pos_bluetooth_printer_config.dart';
import '../state/pos_network_printer_config.dart';
import '../state/pos_printer_assignments.dart' show posRestaurantNameProvider;
import '../state/pos_printer_transport.dart';
import '../data/round_print_claim_store.dart';
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
///  * the server did NOT definitively refuse it — see
///    [OutboxEntry.isDefinitiveNoServerOrder]. A definitively-refused submit has
///    no server order to cook.
///
/// 024: the caller now passes that AUTHORITATIVE flag rather than an error code
/// for this helper to look up in [kPermanentRejectionCodes]. Gating on the code
/// set meant a typed `auth` refusal, and a structured refusal whose code was not
/// allowlisted, both printed a kitchen ticket for an order the server had
/// refused — and a new canonical server code would have silently reopened that
/// hole until someone remembered to extend the set. `rejectionCode` is kept as a
/// SECONDARY input so callers that only hold a code (older call sites, and the
/// dispatch-mode path) keep their exact behaviour; either input suppressing the
/// print is enough, and neither can re-enable it.
///
/// Deliberately unchanged for everything else: a PENDING or DELIVERY-UNCONFIRMED
/// order still prints. That is the offline-first contract — the order may well
/// exist, the ticket is money-free, and a kitchen with no paper is the worse
/// failure. Only a PROVEN refusal suppresses it.
bool isOrderEligibleForKitchenPrint({
  required String? orderId,
  required bool isDemoMode,
  bool definitivelyRejected = false,
  String? rejectionCode,
}) {
  if (isDemoMode) return false;
  if (definitivelyRejected) return false;
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
    this.mediaProfile = pp.MediaProfile.continuous80,
  });

  /// Canonical per-endpoint key for the SHARED send gate (never logged). Equal
  /// to the customer slot's key when both purposes use the same physical
  /// printer, which is exactly how the shared gate serializes them.
  final String destinationKey;

  /// Builds a fresh transport per send (a socket/BT link is not reused).
  final pp.PrintTransport Function() transportFactory;

  /// PRINT-LAYOUT-001A: the KITCHEN assignment's selected media profile — width
  /// + margins + pagination for the ticket. Default = backward-compatible 80mm.
  final pp.MediaProfile mediaProfile;
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
        mediaProfile: net.mediaProfile,
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
        mediaProfile: bt.mediaProfile,
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
  PosAutoKitchenPrintGuard({PosRoundPrintClaimStore? claims})
    : _claims = claims;

  /// MONEY-DURABLE-ADDITIONS-003C: the DURABLE half of the claim, or null when
  /// nothing durable is wired (demo mode / tests) — in which case the guard
  /// behaves exactly as it did before, session-scoped and honest about it.
  ///
  /// Consulted BEFORE `attempt` runs and written BEFORE the send, so a process
  /// that dies mid-print does not come back and print the round again. The
  /// in-memory halves stay: they are what makes concurrent callbacks share ONE
  /// send within a session, which no durable store can do.
  final PosRoundPrintClaimStore? _claims;

  final Map<String, Future<PosKitchenPrintOutcome>> _inFlight = {};
  final Set<String> _succeeded = {};

  /// [POS-OFFLINE-OPERATIONS-002] Pass C (B1) — the SESSION-ONLY claim overlay
  /// for keys whose DURABLE commit was REFUSED (the claim store threw). The
  /// durable store remains the authority whenever it holds an answer; this map
  /// answers only for keys the store could not record, so the pending-print
  /// notice and the recovery surfaces still see an honest
  /// claimed → sent/failed lifecycle within the session instead of nothing at
  /// all. Deliberately NOT crash-proof: after a restart these keys read as
  /// unclaimed again — the residual risk the refused-commit policy documents
  /// (the store's own storage-unhealthy signal is already at indicator
  /// priority 1).
  final Map<String, PosRoundPrintClaimState> _sessionOnlyClaims = {};

  /// B1: records that [key]'s durable `claimed` commit was refused, so the
  /// session overlay carries the lifecycle the store could not.
  void noteDurableClaimRefused(String key) {
    _sessionOnlyClaims[key] = PosRoundPrintClaimState.claimed;
  }

  /// B1: settles a session-only claim (no-op for keys whose durable commit
  /// succeeded — the durable store answers for those).
  void settleSessionOnlyClaim(String key, PosRoundPrintClaimState state) {
    if (_sessionOnlyClaims.containsKey(key)) _sessionOnlyClaims[key] = state;
  }

  /// The claim for [key] as the UI surfaces should read it: the durable store
  /// first (including its fail-closed unreadable-envelope answer), then the
  /// session-only overlay for keys whose durable commit was refused. Null
  /// means genuinely unclaimed.
  PosRoundPrintClaimState? effectiveClaimOf(String key) =>
      _claims?.claimOf(key) ?? _sessionOnlyClaims[key];

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

    // 003C: a DURABLE claim from an earlier process suppresses the automatic
    // send. `claimed` counts as suppressing: after a crash between claiming and
    // sending, the honest answer is "a ticket may already be at the printer",
    // and printing again to be sure is precisely the duplicate this prevents.
    // Only `failed` releases the round, so a genuine retry still runs.
    final durable = _claims?.claimOf(orderId);
    if (durable == PosRoundPrintClaimState.claimed ||
        durable == PosRoundPrintClaimState.sent) {
      return Future.value(PosKitchenPrintOutcome.printed);
    }

    // Race-safe: publish the in-flight future via a Completer FIRST, then invoke
    // attempt() inside a guarded driver. This holds even if attempt() throws
    // SYNCHRONOUSLY (before returning a Future) — the `finally` always removes
    // the in-flight entry, so a failed order is never permanently retained.
    final completer = Completer<PosKitchenPrintOutcome>();
    _inFlight[orderId] = completer.future;
    unawaited(_drive(orderId, attempt, completer));
    return completer.future;
  }

  /// [POS-OFFLINE-OPERATIONS-002] C9 — runs [attempt] for a key whose durable
  /// `claimed` record the CALLER already committed (the offline direct-print
  /// commit that lands BEFORE the cart clears). Identical to [runGuarded]
  /// except that the claimed-write is skipped — the caller already wrote it —
  /// and the durable pre-consult reads DIFFERENTLY (Pass C, C2):
  ///
  ///  * `sent` SUPPRESSES: the transport already accepted this key's bytes
  ///    (this run or an earlier process), so a second caller — whatever
  ///    surface it came through — gets the idempotent `printed` answer and
  ///    zero new sends;
  ///  * `claimed` PROCEEDS: it is either OUR CALLER's own just-committed
  ///    claim (the fresh submit, which must print exactly once — suppressing
  ///    here would read our own write and swallow the very send it protects)
  ///    or a claim left by a PRIOR crashed run — and the only paths that
  ///    re-enter here with such a key are the deliberate manual/recovery
  ///    surfaces, whose re-attempt is exactly the crash-recovery contract.
  ///    Nothing AUTOMATIC re-invokes this for an old key: the automatic
  ///    offline print fires only on a fresh submit, and the automatic
  ///    [runGuarded] path treats `claimed` as suppressing;
  ///  * `failed` / absent PROCEEDS: a failed send released the key.
  ///
  /// The in-memory in-flight/succeeded sharing and the truthful
  /// `sent`/`failed` settle are the SAME code path, so a double-invocation
  /// still produces exactly one physical send and a failure still releases
  /// the key for a legitimate retry.
  Future<PosKitchenPrintOutcome> runPreclaimed(
    String key,
    Future<PosKitchenPrintOutcome> Function() attempt,
  ) {
    if (_succeeded.contains(key)) {
      return Future.value(PosKitchenPrintOutcome.printed);
    }
    final active = _inFlight[key];
    if (active != null) return active;
    // C2: a durable `sent` is the one state that means bytes already went
    // out under this exact identity — never send them twice.
    if (_claims?.claimOf(key) == PosRoundPrintClaimState.sent) {
      return Future.value(PosKitchenPrintOutcome.printed);
    }
    final completer = Completer<PosKitchenPrintOutcome>();
    _inFlight[key] = completer.future;
    unawaited(_drive(key, attempt, completer, claimBeforeSend: false));
    return completer.future;
  }

  Future<void> _drive(
    String orderId,
    Future<PosKitchenPrintOutcome> Function() attempt,
    Completer<PosKitchenPrintOutcome> completer, {
    bool claimBeforeSend = true,
  }) async {
    PosKitchenPrintOutcome outcome;
    try {
      // 003C: CLAIM BEFORE SENDING. The window between "bytes went out" and
      // "we recorded that they did" is exactly where a crash produces the
      // duplicate ticket, so the claim is written first and a claim that could
      // not be written REFUSES the print. Choosing not to print is recoverable
      // — the operator can reprint on demand — while printing a second ticket
      // for a round the kitchen is already cooking is not.
      // C9: skipped for [runPreclaimed] — the caller committed the durable
      // `claimed` record itself, before the cart cleared.
      final claims = _claims;
      if (claims != null && claimBeforeSend) {
        try {
          await claims.record(orderId, PosRoundPrintClaimState.claimed);
        } catch (_) {
          _inFlight.remove(orderId);
          completer.complete(PosKitchenPrintOutcome.failed);
          return;
        }
      }
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
    // 003C: settle the durable claim TRUTHFULLY. `sent` means the transport
    // accepted the bytes — never that paper was produced, which the platform
    // does not tell us (PRINT-STABILITY-001). A non-success RELEASES the round
    // so a later legitimate automatic retry can still run; a print that never
    // happened must not be remembered as one that did.
    final settled = outcome == PosKitchenPrintOutcome.printed
        ? PosRoundPrintClaimState.sent
        : PosRoundPrintClaimState.failed;
    final claims = _claims;
    if (claims != null) {
      try {
        await claims.record(orderId, settled);
      } catch (_) {
        // The claim is already `claimed` on disk, which errs toward NOT
        // printing again — the safe direction. Surfaced via isDegraded.
      }
    }
    // B1: keys whose DURABLE commit was refused settle their session-only
    // overlay too, so the pending-print notice tells the truth in-session.
    settleSessionOnlyClaim(orderId, settled);
    completer.complete(outcome);
  }
}

/// MONEY-DURABLE-ADDITIONS-003C: the durable round-print claim store. Null by
/// default => session-scoped guarding only (demo mode / tests / the pre-003C
/// behaviour). `main.dart` overrides it for the real app.
final posRoundPrintClaimStoreProvider = Provider<PosRoundPrintClaimStore?>(
  (_) => null,
);

final posAutoKitchenPrintGuardProvider = Provider<PosAutoKitchenPrintGuard>(
  (ref) => PosAutoKitchenPrintGuard(
    claims: ref.watch(posRoundPrintClaimStoreProvider),
  ),
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
      pp.MediaProfile? mediaProfile,
      String? restaurantName,
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
        mediaProfile: resolved.mediaProfile,
        // PRINT-LAYOUT-001B: the station's own restaurant name for the brand
        // header — a stable device-level value, offline-safe (null => the
        // shared builder uses the localized fallback on [labels]).
        restaurantName: _container.read(posRestaurantNameProvider),
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

/// ORDER-REPRINT-CHOOSER-038 — the KITCHEN reprint seam used by the Orders
/// reprint chooser.
///
/// It exists so a test can assert EXACTLY which printer path a selection
/// invoked: the routing rule ("customer -> receipt printer only, kitchen ->
/// kitchen printer only, never a cross-purpose fallback") is only meaningfully
/// provable if each path is observable on its own. The default is the
/// canonical print-and-settle function the confirmation screen already calls —
/// this adds no second printing architecture, only a named door onto the
/// existing one.
typedef PosKitchenReprint =
    Future<PosKitchenPrintOutcome> Function({
      required ProviderContainer container,
      required SubmittedOrderView order,
      required KitchenTicketPrintLabels labels,
    });

final posKitchenReprintProvider = Provider<PosKitchenReprint>(
  (ref) =>
      ({required container, required order, required labels}) =>
          printKitchenTicketAndSettleOwedClaims(
            container: container,
            order: order,
            labels: labels,
          ),
);

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
/// DEFERRED-ORDER-AMENDMENTS-001: [guardKey] overrides the exactly-once identity
/// the print is guarded under. It defaults to [orderId] — correct for an initial
/// order, where the order IS the work unit — but an ADDITION must never share
/// that key: the parent order has already printed once, so a parent-keyed guard
/// would silently swallow every later round's ticket and the kitchen would never
/// see the added food. Additions pass
/// [posAdditionKitchenPrintGuardKey] (order identity AND round identity).
Future<PosKitchenPrintOutcome> runAutoKitchenTicketPrintOnSubmit({
  required ProviderContainer container,
  required String orderId,
  required KdsTicketView ticket,
  required KitchenTicketPrintLabels labels,
  bool? enabled,
  bool isDemoMode = false,
  bool definitivelyRejected = false,
  String? rejectionCode,
  PosKitchenTicketPrinter? printer,
  String? guardKey,
}) async {
  // Rejected / demo / blank / placeholder orders never print (shared rule).
  if (!isOrderEligibleForKitchenPrint(
    orderId: orderId,
    isDemoMode: isDemoMode,
    definitivelyRejected: definitivelyRejected,
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
  } else if (container.read(posPrinterOnlyAutoPrintProvider)) {
    // HIDE-REDUNDANT-AUTO-PRINT-SETTINGS-014: on a printer_only branch the
    // ticket MUST print — the station is the kitchen. Decided without reading
    // the stored preference at all, so neither a stale `false` nor an
    // unreadable preference can stop the kitchen seeing the food. The stored
    // value is untouched and governs again under `kds`.
    effectiveEnabled = true;
  } else if (container.read(posCentralKitchenWorkflowProvider)) {
    // POS-KITCHEN-WORKFLOW-REGRESSION-001: the Dashboard workflow governs this
    // station, and it is NOT direct-print (the branch above already handled
    // that). So the answer is no — the KDS owns the ticket, or the workflow is
    // not yet known and printing on a guess is exactly what must not happen.
    // The stored preference is not consulted, so a stale `true` left over from
    // a branch that has since moved to a KDS cannot produce a rogue ticket.
    effectiveEnabled = false;
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
        guardKey ?? orderId,
        () => printKitchenTicketForOrder(
          container: container,
          ticket: ticket,
          labels: labels,
          printer: printer,
        ),
      );
}

/// DEFERRED-ORDER-AMENDMENTS-001 — the exactly-once print identity of ONE service
/// round: the original order AND the round the server applied.
///
/// The parent order id alone is NOT an identity here. It is the same order for
/// every addition, and the initial ticket already claimed it, so a parent-keyed
/// guard reports "already printed" and the kitchen silently never receives the
/// added items. Round-scoped, so each round prints exactly once and a failed
/// round print can still be retried on its own.
String posAdditionKitchenPrintGuardKey({
  required String orderId,
  required String roundId,
}) => '$orderId|round:$roundId';

/// [POS-OFFLINE-OPERATIONS-002] C9 — bumps whenever an offline direct-print
/// attempt (or a manual reprint that settles one) records a claim transition,
/// so the confirmation's pending-print line re-reads the durable claim. Claim
/// writes are plain storage and notify nobody; this is the one legal rebuild
/// signal, written only OUTSIDE provider builds.
final posOfflineKitchenPrintRevisionProvider = StateProvider<int>((_) => 0);

/// [POS-OFFLINE-OPERATIONS-002] C9 — the OFFLINE direct-print automatic
/// kitchen ticket: the PHYSICAL attempt that runs AFTER the caller durably
/// committed the print job (the `claimed` record under
/// [posLocalKitchenDispatchClaimKey], written BEFORE the cart cleared) and
/// after the queued confirmation was shown. Ordering per the spec:
/// outbox commit → durable print-job commit → cart clear + queued success →
/// THIS physical attempt → server sync later.
///
/// THE TRUE GUARANTEE (Pass C, stated precisely so nobody reads more into it):
///
///  * AT-MOST-ONCE AUTOMATIC PHYSICAL SEND PER SUBMIT. The automatic attempt
///    fires only on a fresh submit, [PosAutoKitchenPrintGuard.runPreclaimed]
///    shares concurrent duplicates into one send, a durable `sent` suppresses
///    any re-send under the same identity, and the spool dispatch-import path
///    consults the order-scoped mirror claim before ever creating a server-
///    driven print job for the same initial ticket.
///  * ESC/POS GIVES NO RELIABLE ACKNOWLEDGEMENT. `sent` means the transport
///    accepted the bytes — never that paper came out. When the transport's
///    answer is ambiguous (timeout after the write, a dropped socket), a
///    DELIBERATE manual reprint can therefore produce a duplicate ticket;
///    that is the operator's informed call, never something automatic paths
///    do on their own.
///  * OWED TICKETS ARE RECOVERABLE, AND THE RECOVERY SURVIVES RESTART. A
///    `claimed` (crash window) or `failed` (released) claim keeps the ticket
///    owed; both the order confirmation AND the recent-orders row expose the
///    manual print action for it, driven by the DURABLE claim + the durable
///    outbox entry — process death loses neither.
///
/// The claim settles truthfully: `sent` when the transport accepted the
/// bytes, `failed` (released for a retry through the manual surfaces)
/// otherwise. On a confirmed send the ORDER-scoped
/// [posInitialKitchenPrintClaimKey] mirror is ALSO recorded — see its doc for
/// the drain-side consult. Bluetooth transports remain genuinely reachable
/// offline — the transport layer is untouched; a LAN failure surfaces as the
/// honest `failed` outcome, never a fake success.
Future<PosKitchenPrintOutcome> runOfflineDirectPrintKitchenTicket({
  required ProviderContainer container,
  required String orderId,
  required String localDispatchClaimKey,
  required KdsTicketView ticket,
  required KitchenTicketPrintLabels labels,
  bool isDemoMode = false,
  PosKitchenTicketPrinter? printer,
}) async {
  // The SHARED eligibility rule — a demo/blank/placeholder order never cooks.
  if (!isOrderEligibleForKitchenPrint(
    orderId: orderId,
    isDemoMode: isDemoMode,
  )) {
    return PosKitchenPrintOutcome.ineligibleOrder;
  }
  final outcome = await container
      .read(posAutoKitchenPrintGuardProvider)
      .runPreclaimed(
        localDispatchClaimKey,
        () => printKitchenTicketForOrder(
          container: container,
          ticket: ticket,
          labels: labels,
          printer: printer,
        ),
      );
  if (outcome == PosKitchenPrintOutcome.printed) {
    final claims = container.read(posRoundPrintClaimStoreProvider);
    if (claims != null) {
      try {
        await claims.record(
          posInitialKitchenPrintClaimKey(orderId),
          PosRoundPrintClaimState.sent,
        );
      } catch (_) {
        // The local dispatch claim is already `sent`, which dedupes every
        // LOCAL path. Losing the mirror weakens the DRAIN-side defence (the
        // spool dispatch import consults it before creating a print job for
        // `initial:<orderId>`): a documented residual, and the store is
        // already surfacing storage-unhealthy when this write fails.
      }
    }
  }
  try {
    container.read(posOfflineKitchenPrintRevisionProvider.notifier).state++;
  } catch (_) {
    // A torn-down container mid-print must not throw out of a fire-and-forget.
  }
  return outcome;
}

/// [POS-OFFLINE-OPERATIONS-002] Pass C (B2) — the ONE manual print-and-settle
/// seam for an already-created order, shared by the confirmation's "Print
/// kitchen ticket" button and the recent-orders recovery action, so the two
/// surfaces can never drift on what a successful manual print MEANS for the
/// owed claims.
///
/// A deliberate operator print: one money-free ticket per call, no idempotency
/// guard (a deliberate press may print again), never a receipt, never an
/// order/payment/KDS mutation. On a CONFIRMED send it settles this order's
/// owed direct-print dispatch claims (see [settleOwedKitchenDispatchClaims]);
/// on anything else it settles nothing and the owed state keeps standing.
/// Works from durable data only (the [SubmittedOrderView] + the durable outbox
/// entry + the durable claim store), so it survives a process restart and runs
/// in any connectivity phase.
Future<PosKitchenPrintOutcome> printKitchenTicketAndSettleOwedClaims({
  required ProviderContainer container,
  required SubmittedOrderView order,
  required KitchenTicketPrintLabels labels,
  PosKitchenTicketPrinter? printer,
}) async {
  PosKitchenPrintOutcome outcome;
  try {
    outcome = await printKitchenTicketForOrder(
      container: container,
      ticket: kdsTicketViewFromSubmittedOrder(order),
      labels: labels,
      printer: printer,
    );
  } catch (_) {
    outcome = PosKitchenPrintOutcome.failed;
  }
  if (outcome == PosKitchenPrintOutcome.printed) {
    await settleOwedKitchenDispatchClaims(container: container, order: order);
  }
  return outcome;
}

/// C9(d) / Pass C (B2): a manual print that SUCCEEDS while this queued
/// direct_print order's local dispatch claim is still owed (claimed/failed)
/// settles the claim — the ticket physically went out, so the pending-print
/// copy stops claiming otherwise and no future automatic path re-prints it.
/// Scoped to EXACTLY the owed case: only when the order's outbox entry is a
/// direct-print `order.submit` and its local claim (durable or the B1
/// session-only overlay) reads claimed/failed — an ordinary reprint of an
/// online order records nothing, keeping the manual path's "never consults
/// the guard" contract otherwise untouched. Best-effort throughout; a refused
/// settle leaves the owed copy standing (honest) and the manual surfaces
/// remain available.
Future<void> settleOwedKitchenDispatchClaims({
  required ProviderContainer container,
  required SubmittedOrderView order,
}) async {
  final entryId = order.outboxEntryId;
  if (entryId == null) return;
  final entry = container
      .read(outboxControllerProvider.notifier)
      .entryById(entryId);
  if (entry == null || !entry.isDirectPrintOrderSubmit) return;
  final guard = container.read(posAutoKitchenPrintGuardProvider);
  final key = posLocalKitchenDispatchClaimKey(
    deviceId: entry.deviceId,
    localOperationId: entry.localOperationId,
  );
  final claim = guard.effectiveClaimOf(key);
  if (claim != PosRoundPrintClaimState.claimed &&
      claim != PosRoundPrintClaimState.failed) {
    return;
  }
  final claims = container.read(posRoundPrintClaimStoreProvider);
  if (claims != null) {
    try {
      await claims.record(key, PosRoundPrintClaimState.sent);
      await claims.record(
        posInitialKitchenPrintClaimKey(entry.targetId),
        PosRoundPrintClaimState.sent,
      );
    } catch (_) {
      // A refused durable settle leaves the pending copy standing — honest,
      // and the deliberate manual reprint remains available.
    }
  }
  // B1: a key whose durable commit was refused settles its session overlay.
  guard.settleSessionOnlyClaim(key, PosRoundPrintClaimState.sent);
  try {
    container.read(posOfflineKitchenPrintRevisionProvider.notifier).state++;
  } catch (_) {
    // Torn-down container — nothing left to repaint.
  }
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
/// DEFERRED-ORDER-AMENDMENTS-001: [roundId] / [roundNumber] are the SERVER's
/// applied service-round identity. Passing them makes the resulting view an
/// ADDITION ticket — the shared builder derives
/// [KitchenTicketDocumentKind.orderAddition] from the round number and prints
/// the "Addition · Round N" marker. Omitting them (the initial-order path) is
/// byte-identical to before.
KdsTicketView kdsTicketViewFromCartLines({
  required String orderCode,
  required OrderType orderType,
  required List<CartLineView> lines,
  Map<String, List<KitchenPrepComponent>> prepByItemId =
      const <String, List<KitchenPrepComponent>>{},
  String? tableLabel,
  String? customerName,
  String? customerPhone,
  String? orderNote,
  String? roundId,
  int? roundNumber,
  // KIOSK-PRINT-114B.6: the order's creation instant (the outbox entry's
  // clientCreatedAt on submit) — printed in the canonical header; never the
  // print time.
  DateTime? createdAt,
}) {
  // MENU-ORDER-001: order items by the shared canonical print order (category ->
  // item display order -> cart index) so the POS-direct kitchen ticket matches
  // the cashier receipt + KDS. Cart lines are already in cart order, so the
  // helper's input-index tie-breaker reproduces the line_position order. The
  // parallel countInputs follow the same sorted order (single loop).
  final sortedLines = sortByMenuPrintOrder(
    lines,
    (l) => [l.categoryDisplayOrder, l.itemDisplayOrder],
  );
  return _kdsTicketViewFromKitchenLines(
    createdAt: createdAt,
    orderCode: orderCode,
    orderType: orderType,
    tableLabel: tableLabel,
    customerName: customerName,
    customerPhone: customerPhone,
    orderNote: orderNote,
    roundId: roundId,
    roundNumber: roundNumber,
    lines: [
      for (final line in sortedLines)
        _KitchenTicketLine(
          name: line.name,
          quantity: line.quantity,
          // Structured modifier lines (name first, ×N when >1 — the KDS
          // convention), via the ONE shared formatter.
          modifierLines: [for (final m in line.modifiers) m.displayName],
          note: line.note,
          // KITCHEN-MEAT-001: each option's meat_snapshot PRE-multiplied by its
          // modifier units (× the item quantity is applied by the aggregator).
          meats: kitchenMeatSnapshots(line.modifiers),
          // KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: the direct kitchen print
          // resolves the classification from the SAME cart line the wire payload
          // does, so paper and KDS show the identical split.
          prepComponents: classifiedPrepForLine(
            prepByItemId[line.menuItemId] ?? const <KitchenPrepComponent>[],
            line.modifiers,
          ),
        ),
    ],
  );
}

/// PRINT-STARTUP-REPRINT-001 (Defect 2) — ONE canonical, money-free kitchen
/// ticket line. Both the automatic initial print (from live cart lines) and the
/// manual reprint (from the stored order snapshot) map onto this shape, so the
/// two tickets cannot drift apart.
class _KitchenTicketLine {
  const _KitchenTicketLine({
    required this.name,
    required this.quantity,
    required this.modifierLines,
    required this.note,
    required this.meats,
    required this.prepComponents,
  });

  final String name;
  final int quantity;

  /// Already-formatted modifier text (`name ×N`). NEVER parsed back for counts.
  final List<String> modifierLines;
  final String? note;

  /// Meat contributions, pre-multiplied by the option's units. Deliberately not
  /// index-aligned with [modifierLines].
  final List<KitchenMeat> meats;
  final List<KitchenPrepComponent> prepComponents;
}

/// The SINGLE kitchen-ticket mapper: canonical lines (already in canonical
/// print order) -> the shared [KdsTicketView], with the ONE whole-order
/// [aggregateOrderKitchenCounts] invocation in the POS. Money-free throughout —
/// a [KdsTicketView] cannot carry money (D-007).
KdsTicketView _kdsTicketViewFromKitchenLines({
  required String orderCode,
  required OrderType orderType,
  required List<_KitchenTicketLine> lines,
  String? tableLabel,
  String? customerName,
  String? customerPhone,
  String? orderNote,
  String? roundId,
  int? roundNumber,
  // KIOSK-PRINT-114B.6: the ORDER CREATION instant (the submit's client time /
  // the detail's created_at) for the canonical header stamp; null => none.
  DateTime? createdAt,
}) {
  final items = <KdsItemView>[];
  final countInputs = <KitchenCountItemInput>[];
  for (final line in lines) {
    items.add(
      KdsItemView(
        name: line.name,
        quantity: line.quantity,
        modifiers: line.modifierLines,
        note: line.note,
        prepComponents: line.prepComponents,
      ),
    );
    countInputs.add(
      KitchenCountItemInput(
        quantity: line.quantity,
        meats: line.meats,
        prepComponents: line.prepComponents,
        // 017: [lines] arrive already in canonical print order, so the shared
        // aggregator's own canonicalization is a no-op here — the position is
        // passed explicitly (1-based) so POS, KDS and spool agree by VALUE and
        // not merely by arriving in the right sequence.
        linePosition: countInputs.length + 1,
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
    customerPhone: customerPhone,
    notes: orderNote,
    kitchenCounts: aggregateOrderKitchenCounts(countInputs),
    // DEFERRED-ORDER-AMENDMENTS-001: null on the initial order (work unit 1) —
    // the shared builder then prints no marker; the server's applied round
    // identity on an addition.
    roundId: roundId,
    roundNumber: roundNumber,
    submittedAt: createdAt,
  );
}

/// Maps an already-created [SubmittedOrderView] (flattened lines) to the SHARED
/// [KdsTicketView] — used by the manual reprint action.
///
/// PRINT-STARTUP-REPRINT-001 (Defect 2): the submitted view now carries the
/// ORDER-TIME kitchen count snapshots, so a reprint goes through the SAME
/// mapper and aggregates the SAME whole-order counts as the automatic ticket.
///
/// A record stored BEFORE that change — or a view rebuilt from the server
/// projection, which exposes no meat/prep — decodes to empty snapshots, and the
/// count section is then honestly OMITTED. Quantities are never recovered by
/// parsing the `name ×N` display strings, and never re-read from the live menu.
KdsTicketView kdsTicketViewFromSubmittedOrder(SubmittedOrderView order) {
  // MENU-ORDER-001: items in the canonical menu-configured print order (shared
  // getter) so the manual kitchen reprint matches the cashier receipt + KDS.
  final sortedLines = order.printOrderedLines;
  return _kdsTicketViewFromKitchenLines(
    createdAt: order.createdAt,
    orderCode: order.orderNumber,
    orderType: order.orderType,
    tableLabel: order.tableLabel,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    lines: [
      for (final line in sortedLines)
        _KitchenTicketLine(
          name: line.name,
          quantity: line.quantity,
          // Already pre-formatted as `name ×N` on the submitted view.
          modifierLines: line.modifiers,
          note: line.note,
          meats: line.kitchenMeats,
          prepComponents: line.prepComponents,
        ),
    ],
  );
}

String _orderTypeWire(OrderType type) =>
    type == OrderType.dineIn ? 'dine_in' : 'takeaway';
