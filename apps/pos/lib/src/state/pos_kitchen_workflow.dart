import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import 'pos_auto_print_prefs.dart';
import 'pos_bluetooth_printer_config.dart';
import 'pos_network_printer_config.dart';
import 'pos_printer_transport.dart';

/// KITCHEN-PRINT-DUAL-001C — whether THIS device has a USABLE kitchen printer
/// configured, resolved through the REAL async printer-config providers so a
/// caller can tell "still loading" apart from "resolved: no printer".
///
/// Unlike [posHasKitchenNativePrinterProvider] — a synchronous `bool` that
/// collapses AsyncLoading to `false` via `valueOrNull` — this SURFACES loading
/// and error. It mirrors the exact usability rule of `resolveKitchenPrinterTarget`
/// (native printing available, a selected transport, and a non-null config for
/// that transport). Native printing unavailable resolves to `false` IMMEDIATELY
/// (there is no printer config to load), never a spurious loading state.
final posKitchenPrinterConfiguredProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(posNativePrintingAvailableProvider)) return false;
  final kind = await ref.watch(
    posKitchenSelectedPrinterTransportProvider.future,
  );
  switch (kind) {
    case PosPrinterTransportKind.network:
      return (await ref.watch(posKitchenNetworkPrinterConfigProvider.future)) !=
          null;
    case PosPrinterTransportKind.bluetooth:
      return (await ref.watch(
            posKitchenBluetoothPrinterConfigProvider.future,
          )) !=
          null;
  }
});

/// The SINGLE explicit kitchen-workflow decision the Send action consumes. It is
/// derived from the resolution STATE of the real async inputs, never from a bool
/// that hides AsyncLoading — so Send can never enable while a required input is
/// still resolving.
enum PosKitchenWorkflowDecision {
  /// A required input (the toggle, or — when the toggle is ON — the printer
  /// configuration) is still resolving. Send MUST stay disabled; loading is
  /// NEVER interpreted as "no printer".
  loading,

  /// A required input failed to read. Send disabled; an honest localized retry
  /// is surfaced (the operator may also disable the option in Device Settings).
  error,

  /// The order takes the NORMAL KDS workflow — the toggle is OFF (or demo mode).
  /// Send enables WITHOUT waiting for the (irrelevant) printer configuration.
  normalKdsReady,

  /// The toggle is ON and a valid kitchen printer is configured — the order is
  /// dispatched direct_print and prints exactly one ticket. Send enabled.
  directPrintReady,

  /// The toggle is ON but the printer configuration RESOLVED with no usable
  /// kitchen printer. Send DISABLED; the operator must configure a printer or
  /// disable the option — the order is NOT auto-submitted into the normal KDS.
  directPrintMissingPrinter,
}

/// Derives [PosKitchenWorkflowDecision] from the REAL async inputs. Demo mode is
/// always the normal KDS workflow (the toggle is never consulted in demo).
final posKitchenWorkflowDecisionProvider = Provider<PosKitchenWorkflowDecision>((
  ref,
) {
  if (ref.watch(runtimeConfigProvider).isDemoMode) {
    return PosKitchenWorkflowDecision.normalKdsReady;
  }
  final toggle = ref.watch(posAutoPrintKitchenTicketProvider);
  if (toggle.hasError) return PosKitchenWorkflowDecision.error;
  if (toggle.isLoading) return PosKitchenWorkflowDecision.loading;
  // Toggle RESOLVED. OFF (or never chosen) -> normal KDS IMMEDIATELY; the printer
  // configuration is irrelevant, so do NOT wait for it (§1B).
  if (!(toggle.valueOrNull ?? false)) {
    return PosKitchenWorkflowDecision.normalKdsReady;
  }
  // Toggle ON -> the printer configuration MUST fully resolve before deciding.
  // Reading it here (only when ON) also triggers its load while the cart is shown.
  final printer = ref.watch(posKitchenPrinterConfiguredProvider);
  if (printer.hasError) return PosKitchenWorkflowDecision.error;
  if (printer.isLoading) return PosKitchenWorkflowDecision.loading;
  return (printer.valueOrNull ?? false)
      ? PosKitchenWorkflowDecision.directPrintReady
      : PosKitchenWorkflowDecision.directPrintMissingPrinter;
});

/// Re-reads EVERY input the workflow decision depends on — the retry after an
/// error. Each invalidate forces a fresh read of the backing store, so a genuine
/// read failure that blocked Send can be recovered without restarting the app.
void refreshKitchenWorkflowInputs(WidgetRef ref) {
  ref.invalidate(posAutoPrintKitchenTicketProvider);
  ref.invalidate(posKitchenSelectedPrinterTransportProvider);
  ref.invalidate(posKitchenNetworkPrinterConfigProvider);
  ref.invalidate(posKitchenBluetoothPrinterConfigProvider);
  ref.invalidate(posKitchenPrinterConfiguredProvider);
}
