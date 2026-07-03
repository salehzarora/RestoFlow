import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/ids.dart';
import '../data/payment.dart';
import '../data/shift_repository.dart';
import 'payment_controller.dart';
import 'pos_session.dart';
import 'pos_shift.dart';

/// A read-only view of the current shift for the close/reconcile panel (RF-113).
/// All money is integer minor units (DECISION D-007). [expectedSoFarMinor] is a
/// client-side ESTIMATE (opening float + this session's completed cash sales) to
/// guide counting; the SERVER computes the authoritative expected at close.
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

  /// The estimated expected cash so far, or null when it cannot be computed
  /// (honest "not available" state rather than a fake total).
  final int? expectedSoFarMinor;
  final DateTime? openedAt;
  final String currencyCode;
}

/// Sum of this session's completed CASH payments (integer minor units).
int _sessionCashSalesMinor(Iterable<CashPayment> payments) => payments
    .where(
      (p) =>
          p.method == PaymentMethod.cash && p.status == PaymentStatus.completed,
    )
    .fold<int>(0, (sum, p) => sum + p.amountMinor);

/// The current shift for the panel. In demo mode it reflects the in-memory demo
/// shift/drawer; in real mode it reflects the captured open-shift handle plus the
/// session's recorded cash payments.
final currentShiftViewProvider = Provider<CurrentShiftView>((ref) {
  final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
  final paymentState = ref.watch(paymentControllerProvider);
  if (isDemo) {
    final shift = paymentState.shift;
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
  final cashSales = _sessionCashSalesMinor(paymentState.payments.values);
  return CurrentShiftView(
    isOpen: true,
    isDemo: false,
    openingFloatMinor: handle.openingFloatMinor,
    expectedSoFarMinor: handle.openingFloatMinor + cashSales,
    openedAt: handle.openedAt,
    currencyCode: 'ILS',
  );
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
      // Shift is closed on the server; drop the handle so the panel reflects it.
      ref.read(posOpenShiftProvider.notifier).clear();
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
