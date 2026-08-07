import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DevicePrinterAssignments, DevicePrinterAssignmentsFailure;
import 'package:restoflow_core/restoflow_core.dart'
    show Failure, Result, Success;
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show kBluetoothPrintTimeout, nativePrintRasterizerProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../state/pos_bluetooth_printer_config.dart';
import '../state/pos_device_context.dart' show posPrinterScopeSegmentProvider;
import '../state/pos_network_printer_config.dart';
import '../state/pos_printer_assignments.dart';
import '../state/pos_printer_transport.dart';
import '../state/receipt_print_controller.dart'
    show ReceiptReadiness, ReceiptReadinessResolver;
import 'bluetooth_printer.dart';
import 'print_bridge.dart';
import 'print_document.dart' as app;

/// The bounded timeout for a native print attempt (ANDROID-003): a Wi-Fi/BT
/// printer that is off or out of range fails fast instead of hanging the UI.
const Duration kPosNativePrintTimeout = Duration(seconds: 5);

/// A [PosPrintBridge] that encodes a receipt document and delivers it over a
/// native [pp.PrintTransport] (Wi-Fi RAW/TCP or Bluetooth Classic) — ANDROID-003.
///
/// Reuses the SAME `receiptToEscPosDocument` → [pp.EscPosPrintAdapter] pipeline
/// as the loopback bridge (no duplicated receipt/money logic); only the
/// transport differs. Maps the transport's best-effort [pp.PrintResult] to the
/// honest [pp.BridgeSubmitResult] — success = bytes delivered to the printer
/// (NOT a hardware paper-print acknowledgement).
class NativeTransportPrintBridge implements PosPrintBridge {
  const NativeTransportPrintBridge({
    required this.transportFactory,
    this.adapter = const pp.EscPosPrintAdapter(),
    this.profile = pp.PrinterProfile.escPos80mm,
    this.mediaProfile = pp.MediaProfile.continuous80,
    this.rasterizer,
    this.sendGate,
    this.destinationKey,
    this.pageLabel,
    this.continuationHeader,
  });

  /// Builds a fresh transport per submit (a socket/BT connection is not reused).
  final pp.PrintTransport Function() transportFactory;
  final pp.PrintAdapter adapter;

  /// ESC/POS capabilities + code page for the adapter (the raster WIDTH comes
  /// from [mediaProfile], not from here — the adapter never reads paper width).
  final pp.PrinterProfile profile;

  /// PRINT-LAYOUT-001A: the selected print media profile for THIS assignment —
  /// the single source of the text columns, raster width, safe margins, font
  /// scale, feed, and fixed-media pagination. Defaults to the backward-compatible
  /// continuous 80mm roll (576 dots / 48 columns / feed 3, no pagination).
  final pp.MediaProfile mediaProfile;

  /// Localized page-number / continuation-header builders for multi-page fixed
  /// media (null => none; a paginated ticket then carries no page number).
  final pp.PageLineLabel? pageLabel;
  final pp.PageLineLabel? continuationHeader;

  /// KITCHEN-MODE-001C2C (LOCKED DECISION 3): the SHARED per-physical-printer
  /// FIFO gate. When set (with [destinationKey]), the physical send is
  /// serialized against every other send — receipt OR kitchen — to the same
  /// canonical endpoint. Encoding/rasterization stay OUTSIDE the gate.
  final pp.PrinterDestinationSendGate? sendGate;

  /// Canonical destination key for [sendGate] (never logged).
  final String? destinationKey;

  /// PRINT-RTL-001: the raster renderer (null => ESC/POS text only). When set,
  /// Arabic/Hebrew (+ non-ASCII ₪/×) receipts render as a bitmap so they print
  /// correctly on printers without a Unicode codepage.
  final pp.ReceiptRasterizer? rasterizer;

  @override
  Future<pp.BridgeSubmitResult> submit(app.PrintDocument document) async {
    // PRINT-BRANDING-LOGO-001 (§4): the logo can only be omitted BEFORE the
    // transport begins. If ENCODING the logo-bearing document fails (a raster
    // encoding failure — case A), strip the logo and re-encode text-only; nothing
    // has reached the device yet, so this is safe. There is NO retry AFTER a send
    // begins: a transport failure is not distinguishable from a partial physical
    // print (case B), so we return it and leave manual retry to the operator.
    Uint8List bytes;
    try {
      bytes = await _encode(document);
    } catch (_) {
      try {
        bytes = await _encode(_withoutLogo(document));
      } catch (_) {
        return pp.BridgeSubmitResult.failed(
          pp.PrinterErrorCategory.unknown,
          'encode_failed',
        );
      }
    }
    return _send(bytes);
  }

  /// POS-CASH-DRAWER-AUTO-OPEN — submit ONE drawer-kick pulse to this bridge's
  /// printer, or return null when the profile does not support a drawer.
  ///
  /// Deliberately a NARROW extra method on the native bridge only (NOT on the
  /// [PosPrintBridge] interface): the loopback/fake bridges have no drawer
  /// port and must never be forced to fake one. The kick document is the
  /// RF-074 shape — `PrintDocument([PrintDrawerKickLine()])` — encoded by the
  /// SAME adapter + profile as receipts (the adapter emits the builder's
  /// default ESC p 0 25 25 pulse and honours
  /// `profile.capabilities.supportsDrawerKick`), and dispatched through the
  /// SAME [_send] path: same transport, same per-destination send gate, same
  /// no-auto-resend semantics. It deliberately does NOT pass through
  /// [_encode]/`rasterizeForMediaProfile` — a kick is a control pulse, not
  /// printable content, and must never be turned into raster bytes.
  ///
  /// Returns null (a typed "no drawer here" skip, not a failure) when the
  /// profile's capabilities exclude the drawer kick; the caller treats that
  /// as a benign skip. Receipt behaviour ([submit]/[_encode]) is untouched.
  Future<pp.BridgeSubmitResult?> submitDrawerKick() async {
    if (!profile.capabilities.supportsDrawerKick) return null;
    final bytes = adapter.encode(
      const pp.PrintDocument(<pp.PrintLine>[pp.PrintDrawerKickLine()]),
      profile,
    );
    return _send(bytes);
  }

  /// Strip the customer-receipt logo (header image) — used only to re-encode
  /// text-only BEFORE any transport send (case A). Never used as a resend.
  app.PrintDocument _withoutLogo(app.PrintDocument document) =>
      app.PrintDocument(
        title: document.title,
        lines: <app.PrintLine>[
          for (final l in document.lines)
            if (l.kind != app.PrintLineKind.headerImage) l,
        ],
      );

  Future<Uint8List> _encode(app.PrintDocument document) async {
    // PRINT-LAYOUT-001A: text columns + raster width + margins + pagination all
    // come from the selected media profile — never a hardcoded 80mm/576/48.
    final escpos = receiptToEscPosDocument(
      document,
      columns: mediaProfile.columns,
    );
    // On native Android, render Arabic/Hebrew (+ ₪/×) content as a raster image
    // so it prints correctly; a FIXED label always rasterizes + paginates at its
    // real width. A rasterizer failure falls back to the text document (a receipt
    // with "?????" is still better than no print).
    pp.PrintDocument doc = escpos;
    try {
      doc = await pp.rasterizeForMediaProfile(
        escpos,
        rasterizer: rasterizer,
        profile: mediaProfile,
        pageLabel: pageLabel,
        continuationHeader: continuationHeader,
      );
    } catch (_) {
      doc = escpos;
    }
    return adapter.encode(doc, profile);
  }

  Future<pp.BridgeSubmitResult> _send(Uint8List bytes) async {
    final transport = transportFactory();
    try {
      // Only the PHYSICAL transport operation runs under the shared
      // destination gate; document building/encoding already happened.
      final gate = sendGate;
      final key = destinationKey;
      final result = (gate != null && key != null)
          ? await gate.withDestination(key, () => transport.send(bytes))
          : await transport.send(bytes);
      if (result.ok) {
        return const pp.BridgeSubmitResult.sentToPrinter(mode: 'native');
      }
      // A transport failure — whether or not the send began — is returned as-is
      // (no auto-resend). PRINT-BRANDING-LOGO-001 (§7): preserve the transport's
      // physical dispatch stage + known byte count so the receipt controller can
      // distinguish a safe PRE-dispatch failure from a partial/unknown AFTER-
      // dispatch print (manual retry only). Unknown bytesSent stays null, not 0.
      return pp.BridgeSubmitResult.failed(
        result.category ?? pp.PrinterErrorCategory.unknown,
        result.message,
        result.physicalOutcome,
        result.bytesSent,
      );
    } finally {
      await transport.dispose();
    }
  }

  @override
  Future<pp.BridgeHealth> health() async => pp.BridgeHealth.connected;
}

/// KITCHEN-MODE-001C2C (LOCKED DECISION 3): the ONE process-wide send gate.
/// Every physical send to a given printer endpoint — customer receipt today,
/// kitchen ticket in the worker phase — must serialize through THIS instance
/// so the same physical printer never receives interleaved byte streams.
final posPrinterDestinationSendGateProvider =
    Provider<pp.PrinterDestinationSendGate>(
      (_) => pp.PrinterDestinationSendGate(),
    );

/// The active POS print target (ANDROID-003 transport resolver):
/// - non-native (web): the compiled loopback print bridge (usually null — the
///   print-bridge path is unchanged; web NEVER uses a native transport).
/// - native + bluetooth selected + a saved BT printer → Bluetooth transport.
/// - native + network selected + a saved network printer → TCP transport.
/// - native but the selected transport isn't configured → the loopback bridge
///   (usually null → the receipt stays honestly `prepared`).
final posActivePrintBridgeProvider = Provider<PosPrintBridge?>((ref) {
  if (!ref.watch(posNativePrintingAvailableProvider)) {
    return ref.watch(posPrintBridgeProvider);
  }
  // PRINT-RTL-001: the app injects the real raster renderer; null keeps text mode.
  final rasterizer = ref.watch(nativePrintRasterizerProvider);
  final selected =
      ref.watch(posSelectedPrinterTransportProvider).valueOrNull ??
      PosPrinterTransportKind.network;
  switch (selected) {
    case PosPrinterTransportKind.bluetooth:
      final bt = ref.watch(posBluetoothPrinterConfigProvider).valueOrNull;
      if (bt != null) {
        final connector = ref.watch(bluetoothPrinterConnectorProvider);
        return NativeTransportPrintBridge(
          rasterizer: rasterizer,
          // PRINT-LAYOUT-001A: the CUSTOMER-receipt assignment's selected media
          // profile drives width + pagination for this send.
          mediaProfile: bt.mediaProfile,
          sendGate: ref.watch(posPrinterDestinationSendGateProvider),
          destinationKey: pp.PrinterDestinationSendGate.bluetoothKey(
            bt.address,
          ),
          transportFactory: () => BluetoothClassicPrintTransport(
            connector: connector,
            address: bt.address,
            // PRINT-BLUETOOTH-RECOVERY-001: BT gets its own budget — a cold
            // SPP connect regularly exceeds the 5s Wi-Fi budget, and the
            // native watchdog enforces the bound for real.
            timeout: kBluetoothPrintTimeout,
          ),
        );
      }
    case PosPrinterTransportKind.network:
      final net = ref.watch(posNetworkPrinterConfigProvider).valueOrNull;
      if (net != null) {
        return NativeTransportPrintBridge(
          rasterizer: rasterizer,
          mediaProfile: net.mediaProfile,
          sendGate: ref.watch(posPrinterDestinationSendGateProvider),
          destinationKey: pp.PrinterDestinationSendGate.networkKey(
            net.host,
            net.port,
          ),
          transportFactory: () => pp.NetworkTcpPrintTransport(
            host: net.host,
            port: net.port,
            timeout: kPosNativePrintTimeout,
          ),
        );
      }
  }
  return ref.watch(posPrintBridgeProvider);
});

/// PRINT-STARTUP-REPRINT-001 (BLUETOOTH-FIRST-PRINT) — the RESOLVED customer
/// print bridge for the FIRST receipt of a fresh process.
///
/// [posActivePrintBridgeProvider] samples `posSelectedPrinterTransportProvider`
/// and the printer configs with `.valueOrNull` (:198, :202, :225). Those are
/// `AsyncNotifier`s with an async `build()`, so on their FIRST synchronous read
/// in a new process they are necessarily still `AsyncLoading` — the bridge falls
/// through to `posPrintBridgeProvider`, which is `null` in every shipped build.
/// The paid receipt was then dispatched to NO bridge and stopped at `prepared`,
/// which shows no Retry. The second receipt printed because the providers had
/// landed and the `Provider` recomputed.
///
/// The readiness work (Defect 1) fixed the JOB-CREATION half of that race — it
/// awaits the same sources — but the bridge was captured as an eager argument
/// BEFORE that await ran, so the dispatch half stayed broken. This provider
/// awaits, so the bridge can be resolved AFTER readiness, on the same job.
/// It changes no transport, connection, retry or layout behaviour.
final posActivePrintBridgeReadyProvider = FutureProvider<PosPrintBridge?>((
  ref,
) async {
  if (!ref.watch(posNativePrintingAvailableProvider)) {
    return ref.watch(posPrintBridgeProvider);
  }
  final rasterizer = ref.watch(nativePrintRasterizerProvider);
  final selected = await ref.watch(posSelectedPrinterTransportProvider.future);
  switch (selected) {
    case PosPrinterTransportKind.bluetooth:
      final bt = await ref.watch(posBluetoothPrinterConfigProvider.future);
      if (bt != null) {
        final connector = ref.watch(bluetoothPrinterConnectorProvider);
        return NativeTransportPrintBridge(
          rasterizer: rasterizer,
          mediaProfile: bt.mediaProfile,
          sendGate: ref.watch(posPrinterDestinationSendGateProvider),
          destinationKey: pp.PrinterDestinationSendGate.bluetoothKey(
            bt.address,
          ),
          transportFactory: () => BluetoothClassicPrintTransport(
            connector: connector,
            address: bt.address,
            timeout: kBluetoothPrintTimeout,
          ),
        );
      }
    case PosPrinterTransportKind.network:
      final net = await ref.watch(posNetworkPrinterConfigProvider.future);
      if (net != null) {
        return NativeTransportPrintBridge(
          rasterizer: rasterizer,
          mediaProfile: net.mediaProfile,
          sendGate: ref.watch(posPrinterDestinationSendGateProvider),
          destinationKey: pp.PrinterDestinationSendGate.networkKey(
            net.host,
            net.port,
          ),
          transportFactory: () => pp.NetworkTcpPrintTransport(
            host: net.host,
            port: net.port,
            timeout: kPosNativePrintTimeout,
          ),
        );
      }
  }
  return ref.watch(posPrintBridgeProvider);
});

/// PRINT-STARTUP-REPRINT-001 — the AUTHORITATIVE receipt-readiness resolver.
///
/// The receipt trigger used to read every printer source with `.valueOrNull` and
/// return silently while they were unresolved, which dropped the paid receipt on
/// a cold start. This resolver AWAITS each authoritative source instead, so an
/// unresolved source can never be mistaken for "not configured":
///
///  1. the Defect 3 preference scope (a pending device restore is waited out);
///  2. the native path — selected transport + its saved profile;
///  3. the bridge/assignment path.
///
/// A load failure is reported distinctly from "definitively none" so the UI can
/// offer a meaningful Retry. No timeouts are introduced: each awaited source
/// already resolves on its own (local prefs, or the assignment reader's own
/// bounded load).
final posReceiptReadinessResolverProvider = Provider<ReceiptReadinessResolver>((
  ref,
) {
  return () async {
    // 1. Never choose a namespace from a transient null (Defect 3 contract).
    await ref.read(posPrinterScopeSegmentProvider.future);

    // 2. A native printer configured on THIS device counts on its own.
    if (ref.read(posNativePrintingAvailableProvider)) {
      final transport = await ref.read(
        posSelectedPrinterTransportProvider.future,
      );
      final nativeConfigured = switch (transport) {
        PosPrinterTransportKind.bluetooth =>
          await ref.read(posBluetoothPrinterConfigProvider.future) != null,
        PosPrinterTransportKind.network =>
          await ref.read(posNetworkPrinterConfigProvider.future) != null,
      };
      if (nativeConfigured) return ReceiptReadiness.configured;
    }

    // 3. Otherwise the backend assignment/bridge path.
    final Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>?
    assignments;
    try {
      assignments = await ref.read(posPrinterAssignmentsProvider.future);
    } catch (_) {
      return ReceiptReadiness.loadFailed; // retryable, NOT "not configured"
    }
    return switch (assignments) {
      Success(:final value) =>
        value.hasEnabledPrinter
            ? ReceiptReadiness.configured
            : ReceiptReadiness.notConfigured,
      Failure() => ReceiptReadiness.loadFailed,
      _ => ReceiptReadiness.notConfigured, // demo / no reader wired
    };
  };
});

/// Whether THIS device has a native printer configured for the selected
/// transport (ANDROID-003). Drives the receipt auto-print "has a printer" gate.
/// Always false on web (the print-bridge path is unchanged there).
final posHasNativePrinterProvider = Provider<bool>((ref) {
  if (!ref.watch(posNativePrintingAvailableProvider)) return false;
  final selected =
      ref.watch(posSelectedPrinterTransportProvider).valueOrNull ??
      PosPrinterTransportKind.network;
  return switch (selected) {
    PosPrinterTransportKind.bluetooth =>
      ref.watch(posBluetoothPrinterConfigProvider).valueOrNull != null,
    PosPrinterTransportKind.network =>
      ref.watch(posNetworkPrinterConfigProvider).valueOrNull != null,
  };
});
