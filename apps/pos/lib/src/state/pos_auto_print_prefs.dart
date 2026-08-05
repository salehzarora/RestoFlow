import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import '../data/order_dispatch.dart' show resolveOrderDispatchMode;
import '../data/order_submission.dart' show OrderDispatchMode;
import '../print/pos_kitchen_ticket_printer.dart'
    show posHasKitchenNativePrinterProvider;
import 'pos_device_context.dart';
import 'pos_printer_transport.dart' show posNativePrintingAvailableProvider;

/// HIDE-REDUNDANT-AUTO-PRINT-SETTINGS-014 — the ONE place that decides whether
/// the branch's AUTHORITATIVE workflow makes both automatic prints mandatory.
///
/// In `printer_only` the POS *is* the kitchen: tickets and receipts print from
/// this station by definition, so asking the cashier to opt in is redundant and
/// a stale `false` would silently stop the kitchen seeing food. Both effective
/// values are therefore forced ON, and the two device switches are hidden.
///
/// FAIL-SAFE BY CONSTRUCTION: the mode comes from the server-verified
/// [posVerifiedKitchenModeProvider], and `resolveOrderDispatchMode(null)` is
/// `kds`. So while the mode is still loading, and if it never resolves, this is
/// `false` — the stored preferences keep deciding and nothing is forced. It is
/// never inferred from printers, paired devices or local state.
///
/// UI visibility AND runtime behaviour both read THIS provider, so the settings
/// screen and the printer can never disagree.
final posPrinterOnlyAutoPrintProvider = Provider<bool>(
  (ref) =>
      resolveOrderDispatchMode(ref.watch(posVerifiedKitchenModeProvider)) ==
      OrderDispatchMode.directPrint,
);

/// POS-KITCHEN-WORKFLOW-REGRESSION-001 — does THIS surface take its
/// kitchen-ticket decision from the Dashboard kitchen workflow?
///
/// A CAPABILITY question, deliberately independent of the current readiness
/// VALUE. [posPrinterOnlyAutoPrintProvider] answers "is the branch printer_only
/// right now", which is false while loading, false when verification failed and
/// false on a Separate-KDS branch — three different situations that all used to
/// collapse into "fall back to the device toggle". Asking whether the central
/// workflow GOVERNS this surface separates "the answer is not known yet" from
/// "there is no central answer here", so an unresolved workflow can never be
/// mistaken for permission to let a local switch decide.
///
/// True on the real native POS: that is the build that pairs to a branch, runs
/// the kitchen-mode readiness gate and prints through locally configured
/// printers. False in demo (no backend workflow exists) and on web POS (no
/// on-device printing), which keep their historical local behaviour.
final posCentralKitchenWorkflowProvider = Provider<bool>(
  (ref) =>
      !ref.watch(runtimeConfigProvider).isDemoMode &&
      ref.watch(posNativePrintingAvailableProvider),
);

/// The ONE effective answer to "should this station print a kitchen ticket
/// automatically?" — read by the settings UI, the submit path and the
/// recent-orders action, so a control can never imply something the printer
/// will not do.
///
/// Where the central workflow governs, the stored device preference is NOT
/// consulted at all:
///   * direct-print  -> true  (the station IS the kitchen; mandatory)
///   * Separate KDS  -> false (the KDS owns the ticket)
///   * loading/failed-> false (fail safe: never print on a guess)
/// A stale `true` from a branch that has since moved to a KDS therefore cannot
/// produce a rogue ticket, and a stale `false` cannot suppress a mandatory one.
/// The stored value is left on disk, untouched, and governs again on any
/// surface where the central workflow does not apply.
final posKitchenTicketAutoPrintProvider = Provider<bool>((ref) {
  if (ref.watch(posCentralKitchenWorkflowProvider)) {
    return ref.watch(posPrinterOnlyAutoPrintProvider);
  }
  return posAutoPrintKitchenTicketEnabled(
    stored: ref.watch(posAutoPrintKitchenTicketProvider).valueOrNull,
    hasKitchenPrinter: ref.watch(posHasKitchenNativePrinterProvider),
    printerOnly: ref.watch(posPrinterOnlyAutoPrintProvider),
  );
});

/// Per-DEVICE auto-print preference (device settings sprint, Part C): should
/// THIS POS station prepare a customer-receipt print job automatically after
/// a successful payment?
///
/// Stored locally per browser/device via `shared_preferences` (same
/// mechanism as the language choice), keyed by the paired device id so two
/// stations sharing a machine never share the setting. Stores a plain bool —
/// never tokens/secrets. `null` = the cashier never chose; the EFFECTIVE
/// default is then ON iff an enabled receipt printer is assigned (see
/// [posAutoPrintReceiptEnabled] in the sheet/trigger call sites).
const String kPosAutoPrintReceiptKeyPrefix =
    'restoflow.autoprint.pos.receiptOnPaid.';

final posAutoPrintReceiptProvider =
    AsyncNotifierProvider<PosAutoPrintReceiptController, bool?>(
      PosAutoPrintReceiptController.new,
    );

class PosAutoPrintReceiptController extends AsyncNotifier<bool?> {
  /// This preference is DEVICE-only: with no paired device there is no key and
  /// nothing is stored (unchanged behaviour). PRINT-STARTUP-REPRINT-001 only
  /// changes WHEN the namespace is decided — after the scope resolves, never
  /// from a transient null.
  String? _keyFor(PosPrinterScope scope) =>
      scope.isDevice ? '$kPosAutoPrintReceiptKeyPrefix${scope.deviceId}' : null;

  @override
  Future<bool?> build() async {
    await ref.watch(posPrinterScopeSegmentProvider.future);
    final key = _keyFor(ref.read(posPrinterScopeProvider));
    if (key == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key);
    } catch (_) {
      return null; // Unreadable prefs degrade to the default, never crash.
    }
  }

  /// Persists the cashier's choice (state first, storage best-effort).
  Future<void> setEnabled(bool value) async {
    await ref.read(posPrinterScopeSegmentProvider.future);
    final key = _keyFor(ref.read(posPrinterScopeProvider));
    if (key == null) return;
    state = AsyncData(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Best-effort persistence: the in-session choice still applies.
    }
  }
}

/// The EFFECTIVE auto-print decision: a printer must exist and be enabled
/// (no printer = OFF and not toggleable), and the stored choice wins over
/// the configured-printer default of ON.
/// 014: [printerOnly] forces the decision ON without reading — let alone
/// writing — the stored preference, which is left exactly as the cashier last
/// set it and takes over again the moment the branch returns to `kds`.
/// A configured, enabled printer is still required: that is a physical
/// precondition, not a preference (no printer has always meant "cannot print").
bool posAutoPrintReceiptEnabled({
  required bool? stored,
  required bool hasEnabledPrinter,
  bool printerOnly = false,
}) => hasEnabledPrinter && (printerOnly || (stored ?? true));

/// KITCHEN-PRINT-DUAL-001: per-DEVICE "automatically print a KITCHEN ticket
/// after a successful order creation?" — the independent twin of
/// [posAutoPrintReceiptProvider]. Same local `shared_preferences` mechanism,
/// keyed by the paired device id, stores a plain bool. Unlike the receipt
/// default (ON), this DEFAULTS OFF: normal POS behaviour is unchanged until a
/// cashier deliberately enables it.
const String kPosAutoPrintKitchenTicketKeyPrefix =
    'restoflow.autoprint.pos.kitchenTicket.';

final posAutoPrintKitchenTicketProvider =
    AsyncNotifierProvider<PosAutoPrintKitchenTicketController, bool?>(
      PosAutoPrintKitchenTicketController.new,
    );

class PosAutoPrintKitchenTicketController extends AsyncNotifier<bool?> {
  String? _keyFor(PosPrinterScope scope) => scope.isDevice
      ? '$kPosAutoPrintKitchenTicketKeyPrefix${scope.deviceId}'
      : null;

  @override
  Future<bool?> build() async {
    await ref.watch(posPrinterScopeSegmentProvider.future);
    final key = _keyFor(ref.read(posPrinterScopeProvider));
    if (key == null) return null;
    // KITCHEN-PRINT-DUAL-001C: a genuine prefs READ FAILURE must SURFACE as
    // AsyncError, NOT silently degrade to null (OFF). CartPanel gates Send on this
    // setting being RESOLVED, so a swallowed read error would let a cold-start
    // order submit into the normal KDS workflow when the operator may expect a
    // direct kitchen print. A MISSING key is NOT an error — getBool returns null
    // (the cashier never chose), which resolves to the OFF default downstream.
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key);
  }

  /// Persists the cashier's choice (state first, storage best-effort). Setting the
  /// state to AsyncData FIRST also clears any prior read-error state — so toggling
  /// the option through Device Settings is the operator's escape hatch if a read
  /// ever failed and blocked Send.
  Future<void> setEnabled(bool value) async {
    await ref.read(posPrinterScopeSegmentProvider.future);
    final key = _keyFor(ref.read(posPrinterScopeProvider));
    if (key == null) return;
    state = AsyncData(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Best-effort persistence: the in-session choice still applies.
    }
  }
}

/// The EFFECTIVE auto-kitchen-print decision: a KITCHEN printer must be
/// configured (no printer = OFF and not toggleable), and the DEFAULT is OFF
/// (the cashier must opt in) — `stored ?? false`, never `?? true`.
/// 014: [printerOnly] forces the decision ON, overriding the opt-in default and
/// any stored `false`, without mutating the stored value. The kitchen-printer
/// precondition is unchanged.
bool posAutoPrintKitchenTicketEnabled({
  required bool? stored,
  required bool hasKitchenPrinter,
  bool printerOnly = false,
}) => hasKitchenPrinter && (printerOnly || (stored ?? false));
