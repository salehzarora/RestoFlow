/// POS-CASH-DRAWER-MANUAL-OPEN-001 — the state behind the POS manual
/// ("no-sale") cash-drawer button.
///
/// Owner-approved behaviour:
///  * the button starts LOCKED for every PIN session; the FIRST open asks for
///    the signed-in employee's OWN PIN (verified by the server — the PIN never
///    lives on the device, D-006), and that unlock immediately opens the drawer;
///  * once unlocked, ONE tap opens the drawer, until the employee locks it again
///    (a long press) or the PIN session changes / ends (automatic lock);
///  * EVERY open is recorded server-side (D-013) BEFORE the pulse when the
///    server is reachable; when it is not, the record is written to a durable
///    on-device journal FIRST and the pulse follows — only while the unlocked
///    session's server window still allows the record to land under the same
///    actor. With neither, the drawer does NOT open (the physical key remains);
///  * repeated taps inside a short window are de-bounced, and nothing is ever
///    re-pulsed automatically (PRINTERS_AND_HARDWARE_SPEC section 11).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/cash_drawer_manual_repository.dart';
import '../data/ids.dart';
import '../print/native_print_bridges.dart';
import 'discount_controller.dart' show staffCapabilitiesProvider;
import 'order_sync_controller.dart' show posSyncClockProvider;
import 'pos_offline_session_policy.dart';
import 'pos_session.dart';

/// Taps within this window after an open are ignored (the spec's de-bounce): a
/// second pulse would only re-open an already-open drawer.
const Duration kManualDrawerCooldown = Duration(seconds: 3);

/// An offline open is allowed only while the unlocked PIN session still has at
/// least this long to live on the server, so its journaled record can still be
/// recorded under the same actor when the connection returns.
const Duration kManualDrawerOfflineMargin = Duration(minutes: 10);

/// How often a non-empty journal retries reaching the server.
const Duration kManualDrawerJournalRetry = Duration(seconds: 60);

/// The result of one tap on the drawer button, mapped by the UI to one message.
enum ManualDrawerOpenOutcome {
  /// The pulse was handed to the receipt printer.
  opened,

  /// The open was recorded but the pulse could not be sent to the printer.
  sendFailed,

  /// The button is locked for this session — the UI asks for the PIN first.
  needsUnlock,

  /// The server refused: no open_cash_drawer permission. The button locks.
  denied,

  /// The PIN session is no longer valid server-side. The button locks.
  sessionEnded,

  /// The open could not be recorded (no server, no usable journal / offline
  /// window) — the drawer was NOT pulsed.
  cannotRecord,

  /// No receipt printer with a drawer port is configured on this till.
  noPrinter,

  /// Ignored: a previous open is still in flight or inside the cooldown.
  ignored,
}

/// The hardware seam: is there a drawer port, and pulse it once. Swappable in
/// tests; the real one uses the resolved CUSTOMER receipt bridge.
abstract class ManualDrawerKicker {
  Future<bool> isAvailable();

  /// One best-effort pulse. True when the bytes were handed to the printer.
  Future<bool> kick();
}

class RealManualDrawerKicker implements ManualDrawerKicker {
  const RealManualDrawerKicker(this._ref);

  final Ref _ref;

  Future<NativeTransportPrintBridge?> _bridge() async {
    try {
      final bridge = await _ref.read(posActivePrintBridgeReadyProvider.future);
      if (bridge is NativeTransportPrintBridge &&
          bridge.profile.capabilities.supportsDrawerKick) {
        return bridge;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<bool> isAvailable() async => (await _bridge()) != null;

  @override
  Future<bool> kick() async {
    final bridge = await _bridge();
    if (bridge == null) return false;
    try {
      final result = await bridge.submitDrawerKick();
      return result?.ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

final posManualDrawerKickerProvider = Provider<ManualDrawerKicker>(
  RealManualDrawerKicker.new,
);

/// Whether THIS till can pulse a drawer at all: a native (Android) build with a
/// resolved receipt printer that supports the drawer kick. Re-resolves when the
/// printer configuration changes. Never true in demo mode or on the web.
final posManualDrawerHardwareAvailableProvider = FutureProvider<bool>((
  ref,
) async {
  if (ref.watch(runtimeConfigProvider).isDemoMode) return false;
  final bridge = await ref.watch(posActivePrintBridgeReadyProvider.future);
  return bridge is NativeTransportPrintBridge &&
      bridge.profile.capabilities.supportsDrawerKick;
});

/// Whether the drawer button is shown: hardware available, an active PIN
/// session, and the employee not KNOWN to lack the permission (unknown — e.g. an
/// offline-restored session — still shows the locked button; the server decides
/// at unlock).
final posManualDrawerVisibleProvider = Provider<bool>((ref) {
  if (ref.watch(posSyncSessionProvider) == null) return false;
  final hardware =
      ref.watch(posManualDrawerHardwareAvailableProvider).valueOrNull ?? false;
  if (!hardware) return false;
  final caps = ref.watch(staffCapabilitiesProvider).valueOrNull;
  return caps == null || caps.openCashDrawer;
});

final posCashDrawerManualRepositoryProvider =
    Provider<CashDrawerManualRepository>((ref) {
      if (ref.watch(runtimeConfigProvider).isDemoMode) {
        return const DemoCashDrawerManualRepository();
      }
      return RealCashDrawerManualRepository(
        ref.watch(posAuthTransportProvider),
        ref.watch(posSyncSessionProvider),
      );
    });

/// The lock state of the drawer button.
class ManualDrawerState {
  const ManualDrawerState({
    this.unlockedPinSessionId,
    this.sessionExpiresAt,
    this.busy = false,
  });

  /// The PIN session the button was unlocked for (null = locked).
  final String? unlockedPinSessionId;

  /// The server PIN-session expiry returned by the unlock — the bound for
  /// offline opens.
  final DateTime? sessionExpiresAt;

  /// An unlock or open is in flight.
  final bool busy;

  bool isUnlockedFor(String? pinSessionId) =>
      pinSessionId != null && pinSessionId == unlockedPinSessionId;

  ManualDrawerState copyWith({bool? busy}) => ManualDrawerState(
    unlockedPinSessionId: unlockedPinSessionId,
    sessionExpiresAt: sessionExpiresAt,
    busy: busy ?? this.busy,
  );
}

final posCashDrawerManualControllerProvider =
    NotifierProvider<CashDrawerManualController, ManualDrawerState>(
      CashDrawerManualController.new,
    );

class CashDrawerManualController extends Notifier<ManualDrawerState> {
  DateTime? _lastOpenAt;
  bool _flushing = false;
  Timer? _retryTimer;

  @override
  ManualDrawerState build() {
    // ANY change of the PIN session (sign-out, a different employee, an expired
    // session replaced by a new one) re-locks the button: an unlock is bound to
    // exactly one session.
    ref.listen<SyncSession?>(posSyncSessionProvider, (previous, next) {
      if (!state.isUnlockedFor(next?.pinSessionId)) {
        state = const ManualDrawerState();
      }
      if (next != null) unawaited(flushJournal());
    });
    ref.onDispose(() => _retryTimer?.cancel());
    // A journal left by a previous run (app restart while offline) is retried
    // as soon as this controller exists.
    Future<void>.microtask(flushJournal);
    return const ManualDrawerState();
  }

  /// Whether the button is unlocked for the CURRENT session.
  bool get isUnlocked =>
      state.isUnlockedFor(ref.read(posSyncSessionProvider)?.pinSessionId);

  /// Locks the button (long press / menu). The next open asks for the PIN.
  void lock() => state = const ManualDrawerState();

  /// Verifies the signed-in employee's own [pin] with the server and, on
  /// success, unlocks the button for the current session.
  Future<DrawerUnlockResult> unlock(String pin) async {
    final session = ref.read(posSyncSessionProvider);
    if (session == null) return DrawerUnlockResult.sessionInvalid;
    if (state.busy) return DrawerUnlockResult.unavailable;
    state = state.copyWith(busy: true);
    DrawerUnlockOutcome outcome;
    try {
      outcome = await ref
          .read(posCashDrawerManualRepositoryProvider)
          .verifyPin(pin);
    } catch (_) {
      outcome = const DrawerUnlockOutcome(DrawerUnlockResult.unavailable);
    }
    // The session may have changed while the server answered: an unlock for a
    // session that is no longer current unlocks nothing.
    final current = ref.read(posSyncSessionProvider);
    if (outcome.result == DrawerUnlockResult.unlocked &&
        current?.pinSessionId == session.pinSessionId) {
      state = ManualDrawerState(
        unlockedPinSessionId: session.pinSessionId,
        sessionExpiresAt: outcome.sessionExpiresAt,
      );
      unawaited(flushJournal());
      return DrawerUnlockResult.unlocked;
    }
    state = state.copyWith(busy: false);
    if (outcome.result == DrawerUnlockResult.unlocked) {
      return DrawerUnlockResult.sessionInvalid;
    }
    return outcome.result;
  }

  /// Opens the drawer once (see the library doc for the exact order).
  Future<ManualDrawerOpenOutcome> open() async {
    if (state.busy) return ManualDrawerOpenOutcome.ignored;
    final clock = ref.read(posSyncClockProvider);
    final now = clock();
    final last = _lastOpenAt;
    if (last != null && now.difference(last) < kManualDrawerCooldown) {
      return ManualDrawerOpenOutcome.ignored;
    }
    final session = ref.read(posSyncSessionProvider);
    if (session == null) {
      lock();
      return ManualDrawerOpenOutcome.sessionEnded;
    }
    if (!state.isUnlockedFor(session.pinSessionId)) {
      return ManualDrawerOpenOutcome.needsUnlock;
    }
    final kicker = ref.read(posManualDrawerKickerProvider);
    if (!await kicker.isAvailable()) return ManualDrawerOpenOutcome.noPrinter;

    state = state.copyWith(busy: true);
    try {
      final record = NoSaleRecord(
        localOperationId: ref.read(clientIdGeneratorProvider).newId(),
        pinSessionId: session.pinSessionId,
        deviceId: session.deviceId,
        occurredAt: now,
      );
      final push = await ref
          .read(posCashDrawerManualRepositoryProvider)
          .pushNoSale(record);
      switch (push) {
        case NoSalePushResult.recorded:
          return await _pulse(kicker, now);
        case NoSalePushResult.denied:
          state = const ManualDrawerState(busy: true);
          return ManualDrawerOpenOutcome.denied;
        case NoSalePushResult.sessionInvalid:
          state = const ManualDrawerState(busy: true);
          return ManualDrawerOpenOutcome.sessionEnded;
        case NoSalePushResult.rejected:
          return ManualDrawerOpenOutcome.cannotRecord;
        case NoSalePushResult.offline:
          if (!_offlineAllowed(clock())) {
            return ManualDrawerOpenOutcome.cannotRecord;
          }
          // Journal FIRST: a pulse without a durable record is exactly what the
          // audit exists to prevent.
          final persisted = await ref
              .read(posCashDrawerNoSaleJournalProvider)
              .append(session.deviceId, record);
          if (!persisted) return ManualDrawerOpenOutcome.cannotRecord;
          _scheduleRetry();
          return await _pulse(kicker, now);
      }
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<ManualDrawerOpenOutcome> _pulse(
    ManualDrawerKicker kicker,
    DateTime now,
  ) async {
    _lastOpenAt = now;
    final ok = await kicker.kick();
    return ok
        ? ManualDrawerOpenOutcome.opened
        : ManualDrawerOpenOutcome.sendFailed;
  }

  bool _offlineAllowed(DateTime now) {
    final expires = state.sessionExpiresAt;
    if (expires == null) return false; // unknown server window: fail closed
    if (!now.isBefore(expires.subtract(kManualDrawerOfflineMargin))) {
      return false;
    }
    // The bounded offline window of an offline-restored session still applies.
    return ref.read(posOfflineSessionPolicyProvider).canSubmit;
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(kManualDrawerJournalRetry, () => flushJournal());
  }

  /// Sends every journaled record (oldest first) under its OWN session. A final
  /// server verdict removes a record; an offline result stops the pass and
  /// schedules a retry. A record whose session is dead can never land and is
  /// dropped (the offline window above keeps that case narrow).
  Future<void> flushJournal() async {
    if (_flushing) return;
    final deviceId = ref.read(posSyncSessionProvider)?.deviceId;
    if (deviceId == null) return;
    _flushing = true;
    try {
      final journal = ref.read(posCashDrawerNoSaleJournalProvider);
      final pending = await journal.pending(deviceId);
      if (pending.isEmpty) return;
      final repo = ref.read(posCashDrawerManualRepositoryProvider);
      for (final record in pending) {
        final result = await repo.pushNoSale(record);
        if (result == NoSalePushResult.offline) {
          _scheduleRetry();
          return;
        }
        await journal.remove(deviceId, record.localOperationId);
      }
    } catch (_) {
      _scheduleRetry();
    } finally {
      _flushing = false;
    }
  }
}
