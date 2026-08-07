/// POS-CASH-DRAWER-AUTO-OPEN — the cash-drawer auto-open service.
///
/// One narrow job: after the ONE authoritative payment success edge
/// (`payCash` returning without throwing — DEFERRED-PAYMENT-RECEIPTS-001's
/// "payment command edge" in `cash_payment_sheet.dart`), decide whether THIS
/// till should pulse the drawer connected to its CUSTOMER receipt printer,
/// and do it at most once per payment.
///
/// Semantics come from RF-074 ([CashDrawerKickInput] /
/// [CashDrawerKickDispatcher]): CASH-ONLY, completed-only, void-excluded,
/// authorized-required, at-most-once, never retried. The RF-071 spool +
/// RF-074 dispatcher themselves stay app-dormant; this service reuses the
/// INPUT contract + the ESC/POS builder/adapter path only, replacing the
/// spool's idempotent enqueue with the durable [PosCashDrawerClaimStore]
/// (claim-BEFORE-send).
///
/// Drawer and receipt are INDEPENDENT: a kick outcome never touches payment
/// or receipt state, and a receipt failure never suppresses or repeats a
/// kick — the only shared thing is the physical printer, serialized by the
/// existing per-destination send gate inside the bridge.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_printing/restoflow_printing.dart'
    show CashDrawerKickInput;

import '../data/payment.dart';
import '../data/pos_cash_drawer_claim_store.dart';
import '../state/pos_cash_drawer_setting.dart';
import '../state/pos_session.dart' show posSyncSessionProvider;
import '../state/pos_sync_scope_provider.dart';
import 'native_print_bridges.dart';

/// The typed outcome of one [PosCashDrawerService.kickForPayment] call. Every
/// skip is SILENT at the call site; only [sendFailed] — the till expected the
/// drawer to open and the hardware send failed — surfaces to the cashier.
enum PosCashDrawerOutcome {
  /// The per-device toggle is OFF (the default) — the feature is dormant.
  disabledSkip,

  /// Demo mode: no real drawer, no real money, no hardware side effects.
  demoSkip,

  /// A non-cash tender (card/bit/external): no drawer cash, no change — the
  /// drawer NEVER opens (RF-074 cash-only rule).
  nonCashSkip,

  /// No native receipt printer is configured/resolved on this till, so there
  /// is no drawer port to pulse.
  noPrinterSkip,

  /// The resolved printer's profile does not support a drawer kick.
  unsupportedSkip,

  /// This payment already claimed its kick (here or in a previous process) —
  /// at-most-once holds, nothing is sent.
  duplicateSkip,

  /// The durable claim could not be persisted — NO kick (a missed open is
  /// safer than a possible double open; see [PosCashDrawerClaimStore]).
  claimPersistFailed,

  /// RF-074 validation refused the kick (missing tenant/device scope ids or
  /// no authorized PIN session). Nothing is sent.
  refused,

  /// The pulse bytes were handed to the printer transport (best-effort — a
  /// socket write, not a hardware "drawer opened" acknowledgement).
  sent,

  /// The transport send failed. The claim is RETAINED and the kick is NEVER
  /// retried (RF-074: a dispatch failure goes straight to abandoned) — the
  /// cashier gets the one honest snackbar and uses the manual release.
  sendFailed,
}

/// Provider-based so the service outlives the (dismissible) payment sheet
/// that triggers it, exactly like the notifiers the sheet already captures.
final posCashDrawerServiceProvider = Provider<PosCashDrawerService>(
  PosCashDrawerService.new,
);

class PosCashDrawerService {
  PosCashDrawerService(this._ref);

  final Ref _ref;

  /// Decide + (at most once) pulse the drawer for [payment]. Never throws:
  /// the call site fires it unawaited after a SUCCESSFUL payment, and no
  /// drawer problem may ever look like a payment problem.
  Future<PosCashDrawerOutcome> kickForPayment(CashPayment payment) async {
    try {
      return await _kick(payment);
    } catch (_) {
      // An unexpected failure ANYWHERE above the transport (provider container
      // torn down mid-flight, etc.) refuses silently: no bytes were sent, and
      // showing "drawer did not open" for a till that never promised to open
      // one would be noise.
      return PosCashDrawerOutcome.refused;
    }
  }

  Future<PosCashDrawerOutcome> _kick(CashPayment payment) async {
    // GATE 1 — the per-device toggle, DEFAULT OFF. Existing tills keep their
    // exact pre-feature behaviour until a human enables the drawer on them.
    final bool enabled;
    try {
      enabled = await _ref.read(posCashDrawerAutoOpenProvider.future);
    } catch (_) {
      return PosCashDrawerOutcome.disabledSkip; // unreadable toggle = OFF
    }
    if (!enabled) return PosCashDrawerOutcome.disabledSkip;

    // GATE 2 — demo mode never touches hardware cash controls.
    if (_ref.read(runtimeConfigProvider).isDemoMode) {
      return PosCashDrawerOutcome.demoSkip;
    }

    // GATE 3 — CASH-ONLY (RF-074). Card/bit/external move no drawer cash and
    // owe no change; the drawer stays shut for them, always.
    if (!payment.method.isCash) return PosCashDrawerOutcome.nonCashSkip;

    // GATE 4 — the RF-074 input contract, built from the LIVE operational
    // scope + session at THE authoritative edge:
    //  * isCompletedCashPayment: `payCash` returned without throwing and the
    //    tender is cash — the exact "completed cash payment" the contract
    //    means (never inferred from a hydrated/observed status, which would
    //    re-kick on refresh);
    //  * isVoidedOrCancelled: false BY CONSTRUCTION — a payment cannot be
    //    voided in the same instant it was successfully recorded, and this
    //    service only ever runs at that fresh edge (no observer path exists);
    //  * authorized: an active PIN session exists right now (R-007 — a
    //    revoked/expired operator cannot pop the drawer).
    final scope = _ref.read(posSyncScopeProvider);
    final input = CashDrawerKickInput(
      organizationId: scope?.organizationId ?? '',
      branchId: scope?.branchId ?? '',
      deviceId: scope?.deviceId ?? '',
      paymentId: payment.paymentId,
      isCompletedCashPayment: payment.method.isCash,
      isVoidedOrCancelled: false,
      authorized: _ref.read(posSyncSessionProvider) != null,
    );
    try {
      input.validateForKick(); // ArgumentError / StateError → refused
    } on ArgumentError {
      return PosCashDrawerOutcome.refused;
    } on StateError {
      return PosCashDrawerOutcome.refused;
    }
    if (!input.shouldKick) return PosCashDrawerOutcome.nonCashSkip;

    // GATE 5 — the resolved CUSTOMER receipt bridge (the drawer plugs into
    // the receipt printer's drawer port). The READY provider is awaited so a
    // cold start cannot mistake "not resolved yet" for "no printer"
    // (PRINT-STARTUP-REPRINT-001). Only the native transport bridge has a
    // drawer seam; loopback/web bridges skip benignly.
    final bridge = await _ref.read(posActivePrintBridgeReadyProvider.future);
    if (bridge is! NativeTransportPrintBridge) {
      return PosCashDrawerOutcome.noPrinterSkip;
    }

    // GATE 6 — profile capability (the adapter would omit the pulse anyway;
    // answering the typed skip here keeps "nothing will happen" honest and
    // burns no claim on a printer that cannot kick).
    if (!bridge.profile.capabilities.supportsDrawerKick) {
      return PosCashDrawerOutcome.unsupportedSkip;
    }

    // GATE 7 — the DURABLE at-most-once claim, written BEFORE any hardware
    // send. A refused/duplicate claim sends nothing; a crash after this line
    // is a missed open by design (see [PosCashDrawerClaimStore]).
    //
    // PR #205 review N2 — key scoping: the claim namespace uses the RF-074-
    // validated SYNC-SCOPE deviceId, while the toggle (GATE 1) is keyed by
    // `posPrinterScopeSegmentProvider`. In real paired mode both resolve to
    // the same paired device id; they diverge only in demo/unpaired states,
    // which GATE 2 / GATE 4 refuse long before any claim or hardware action.
    final claim = await _ref
        .read(posCashDrawerClaimStoreProvider)
        .claim(deviceSegment: input.deviceId, paymentId: payment.paymentId);
    switch (claim) {
      case PosCashDrawerClaimResult.duplicate:
        return PosCashDrawerOutcome.duplicateSkip;
      case PosCashDrawerClaimResult.persistFailed:
        return PosCashDrawerOutcome.claimPersistFailed;
      case PosCashDrawerClaimResult.claimed:
        break;
    }

    // SEND — one attempt, no retries anywhere (RF-074: a duplicate open is
    // worse than a missed retry). The claim above is deliberately retained on
    // failure so no later path can re-pulse this payment.
    try {
      final result = await bridge.submitDrawerKick();
      if (result == null) return PosCashDrawerOutcome.unsupportedSkip;
      return result.ok
          ? PosCashDrawerOutcome.sent
          : PosCashDrawerOutcome.sendFailed;
    } catch (_) {
      return PosCashDrawerOutcome.sendFailed;
    }
  }
}
