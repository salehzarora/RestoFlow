import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/ids.dart';
import '../data/shift_repository.dart';
import 'payment_controller.dart';
import 'pos_session.dart';
import 'pos_shift.dart';

/// A read-only view of the current shift for the close/reconcile panel (RF-113).
/// All money is integer minor units (DECISION D-007).
///
/// [expectedSoFarMinor] is populated in DEMO mode only — the in-memory demo drawer is
/// its own authority. In REAL mode it is NULL here on purpose: the authoritative
/// expected comes from a FRESH server summary via [shiftExpectedCashProvider], never
/// from a client combination of a server snapshot and local payments (that was the
/// A5 double-count — a mid-recovery cash payment counted once in the snapshot and again
/// locally).
class CurrentShiftView {
  const CurrentShiftView({
    required this.isOpen,
    required this.isDemo,
    required this.openingFloatMinor,
    required this.expectedSoFarMinor,
    required this.openedAt,
    required this.currencyCode,
  });

  final bool isOpen;
  final bool isDemo;
  final int openingFloatMinor;

  /// The demo drawer total (demo mode only); NULL in real mode — see the class doc.
  final int? expectedSoFarMinor;
  final DateTime? openedAt;
  final String currencyCode;
}

/// The current shift for the panel. In demo mode it reflects the in-memory demo
/// shift/drawer; in real mode it reflects the captured open-shift handle (identity +
/// opening float + opened-at) — NOT any expected-cash figure, which is served
/// separately and authoritatively by [shiftExpectedCashProvider].
final currentShiftViewProvider = Provider<CurrentShiftView>((ref) {
  final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
  if (isDemo) {
    final shift = ref.watch(paymentControllerProvider).shift;
    return CurrentShiftView(
      isOpen: shift.shiftOpen,
      isDemo: true,
      openingFloatMinor: shift.openingFloatMinor,
      expectedSoFarMinor: shift.cashInDrawerMinor,
      openedAt: null,
      currencyCode: shift.currencyCode,
    );
  }
  final handle = ref.watch(posOpenShiftProvider);
  if (handle == null) {
    return const CurrentShiftView(
      isOpen: false,
      isDemo: false,
      openingFloatMinor: 0,
      expectedSoFarMinor: null,
      openedAt: null,
      currencyCode: 'ILS',
    );
  }
  return CurrentShiftView(
    isOpen: true,
    isDemo: false,
    openingFloatMinor: handle.openingFloatMinor,
    // Never combined with local cash — see the class doc (A5).
    expectedSoFarMinor: null,
    openedAt: handle.openedAt,
    currencyCode: 'ILS',
  );
});

/// PILOT-OPERATIONS-CORRECTIONS-001 (A5): the ONE authoritative expected-cash source
/// for the shift-close panel.
///
/// REAL mode: a FRESH `app.get_open_shift_summary` — the SAME server SQL as
/// `app.close_shift` (opening float + completed cash payments on the drawer). It is the
/// single source: the panel NEVER adds a local cash total on top of it, so a cash
/// payment that completes while the summary is loading cannot be counted twice. It is
/// re-fetched when the panel opens, and again whenever the payment state changes (a
/// completed cash payment bumps the server total) — so the displayed expected tracks the
/// server without ever double-counting. A failed/absent read returns null and the panel
/// shows a safe loading/unavailable state — never a fabricated 0 or a local figure.
///
/// DEMO mode: the in-memory demo drawer total, which is the demo's own authority (there
/// is no server and no race).
final shiftExpectedCashProvider = FutureProvider.autoDispose<int?>((ref) async {
  final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
  if (isDemo) {
    return ref.watch(paymentControllerProvider).shift.cashInDrawerMinor;
  }
  // Re-fetch when a payment lands: a completed cash payment changes the server total,
  // and this is how the display stays fresh without a local add-on.
  ref.watch(paymentControllerProvider);
  final handle = ref.watch(posOpenShiftProvider);
  if (handle == null) return null;
  final info = await ref.watch(shiftRepositoryProvider).readOpenShift();
  // Null on a failed/absent read — the caller must NOT fall back to a local figure.
  return info?.expectedCashMinor;
});

/// The REAL shift-close repository (real mode only). Reuses the shared transport +
/// session (fail-closed with neither).
final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return RealShiftRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
    ref.watch(clientIdGeneratorProvider),
  );
});

/// Drives the shift close/reconcile action. Holds the last [ShiftCloseOutcome]
/// (the server-authoritative reconciliation) once a close succeeds; a failure is
/// surfaced as an AsyncError carrying a safe [ShiftException] code. Demo mode
/// closes locally (computed from the demo store, clearly labelled — never faked
/// as a server close); real mode posts `shift.close` and reads the figures back.
class ShiftCloseController extends AsyncNotifier<ShiftCloseOutcome?> {
  @override
  FutureOr<ShiftCloseOutcome?> build() => null;

  Future<void> close({required int countedMinor, String? reason}) async {
    final view = ref.read(currentShiftViewProvider);
    if (!view.isOpen) {
      state = AsyncError(const ShiftException('not_open'), StackTrace.current);
      return;
    }
    if (countedMinor < 0) {
      state = AsyncError(
        const ShiftException('invalid_amount'),
        StackTrace.current,
      );
      return;
    }
    state = const AsyncLoading();
    try {
      if (view.isDemo) {
        // Local demo close: honest reconciliation computed from the demo store's
        // cash — NOT a server close (the panel labels it demo).
        final expected = view.expectedSoFarMinor ?? view.openingFloatMinor;
        state = AsyncData(
          ShiftCloseOutcome(
            expectedMinor: expected,
            countedMinor: countedMinor,
            varianceMinor: countedMinor - expected,
            currencyCode: view.currencyCode,
          ),
        );
        return;
      }
      final handle = ref.read(posOpenShiftProvider);
      if (handle == null) {
        state = AsyncError(
          const ShiftException('not_open'),
          StackTrace.current,
        );
        return;
      }
      final outcome = await ref
          .read(shiftRepositoryProvider)
          .closeShift(
            shiftId: handle.shiftId,
            countedMinor: countedMinor,
            reason: reason,
            currencyCode: view.currencyCode,
          );
      // Shift closed on the server. Return the POS to PIN sign-in (RF-113
      // post-close UX): the cashier can't sell without an open shift, and the
      // next sign-in opens a fresh one. endSession() also clears the handle, so
      // the POS is never left as an active cashier with no shift. The result
      // stays shown in this controller's own state (below).
      ref.read(posSessionControllerProvider.notifier).endSession();
      state = AsyncData(outcome);
    } on ShiftException catch (e) {
      state = AsyncError(e, StackTrace.current);
    } catch (_) {
      state = AsyncError(const ShiftException('rejected'), StackTrace.current);
    }
  }

  /// Reset the panel to its initial (pre-close) state.
  void reset() => state = const AsyncData(null);
}

final shiftCloseControllerProvider =
    AsyncNotifierProvider<ShiftCloseController, ShiftCloseOutcome?>(
      ShiftCloseController.new,
    );
