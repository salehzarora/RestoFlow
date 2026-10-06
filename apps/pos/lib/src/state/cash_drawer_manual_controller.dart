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
///    server is reachable; when it is not (no answer at all), the record is
///    written to a durable on-device journal FIRST and the pulse follows — only
///    inside the unlocked session's server window (measured in SERVER time).
///    A journaled record is never dropped for want of a live session: it is
///    re-sent under whoever is signed in next, still attributed to the employee
///    who opened the drawer. A server that answers without a verdict, or no
///    usable journal, means the drawer does NOT open (the physical key remains);
///  * one open at a time; repeated taps inside a short window after a pulse are
///    de-bounced, and nothing is ever re-pulsed automatically
///    (PRINTERS_AND_HARDWARE_SPEC section 11).
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
/// least this long to live on the server (in server time), so the open always
/// falls inside the lifetime the server checks when the record arrives late.
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

  /// The open could not be recorded (no verdict from the server, no usable
  /// journal / offline window) — the drawer was NOT pulsed.
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
    this.serverClockOffset = Duration.zero,
    this.busy = false,
  });

  /// The PIN session the button was unlocked for (null = locked).
  final String? unlockedPinSessionId;

  /// The server PIN-session expiry returned by the unlock — the bound for
  /// offline opens.
  final DateTime? sessionExpiresAt;

  /// Server clock minus device clock, measured at the unlock. Offline windows
  /// and record times use device time + this offset, so a wrong device clock
  /// can neither stretch the window nor mis-date a record.
  final Duration serverClockOffset;

  /// An unlock or open is in flight.
  final bool busy;

  bool isUnlockedFor(String? pinSessionId) =>
      pinSessionId != null && pinSessionId == unlockedPinSessionId;

  ManualDrawerState copyWith({bool? busy}) => ManualDrawerState(
    unlockedPinSessionId: unlockedPinSessionId,
    sessionExpiresAt: sessionExpiresAt,
    serverClockOffset: serverClockOffset,
    busy: busy ?? this.busy,
  );
}

final posCashDrawerManualControllerProvider =
    NotifierProvider<CashDrawerManualController, ManualDrawerState>(
      CashDrawerManualController.new,
    );

class CashDrawerManualController extends Notifier<ManualDrawerState> {
  DateTime? _lastOpenAt;

  /// The ONE in-flight guard, set synchronously before any await: an unlock
  /// and an open (or two opens) can never overlap, whatever rebuilds the
  /// state meanwhile.
  bool _inFlight = false;
  bool _flushing = false;
  bool _disposed = false;
  Timer? _retryTimer;

  @override
  ManualDrawerState build() {
    // ANY change of the PIN session (sign-out, a different employee, an expired
    // session replaced by a new one) re-locks the button: an unlock is bound to
    // exactly one session.
    ref.listen<SyncSession?>(posSyncSessionProvider, (previous, next) {
      if (!state.isUnlockedFor(next?.pinSessionId)) _relock();
      if (next != null) unawaited(flushJournal());
    });
    ref.onDispose(() {
      _disposed = true;
      _retryTimer?.cancel();
    });
    // A journal left by a previous run (app restart while offline) is retried
    // as soon as this controller exists.
    Future<void>.microtask(flushJournal);
    return const ManualDrawerState();
  }

  /// Whether the button is unlocked for the CURRENT session.
  bool get isUnlocked =>
      state.isUnlockedFor(ref.read(posSyncSessionProvider)?.pinSessionId);

  /// Locks the button (long press / menu). The next open asks for the PIN.
  void lock() => _relock();

  void _relock() {
    _lastOpenAt = null;
    state = ManualDrawerState(busy: _inFlight);
  }

  /// Locks only while still unlocked for [pinSessionId]: a late refusal for an
  /// earlier session never locks a fresh unlock of the next one.
  void _relockIfFor(String pinSessionId) {
    if (state.unlockedPinSessionId == pinSessionId) _relock();
  }

  DateTime _serverNow() =>
      ref.read(posSyncClockProvider)().add(state.serverClockOffset);

  /// Verifies the signed-in employee's own [pin] with the server and, on
  /// success, unlocks the button for the current session.
  Future<DrawerUnlockResult> unlock(String pin) async {
    final session = ref.read(posSyncSessionProvider);
    if (session == null) return DrawerUnlockResult.sessionInvalid;
    if (_inFlight) return DrawerUnlockResult.unavailable;
    _inFlight = true;
    state = state.copyWith(busy: true);
    try {
      DrawerUnlockOutcome outcome;
      try {
        outcome = await ref
            .read(posCashDrawerManualRepositoryProvider)
            .verifyPin(pin);
      } catch (_) {
        outcome = const DrawerUnlockOutcome(DrawerUnlockResult.unavailable);
      }
      if (_disposed) return DrawerUnlockResult.unavailable;
      // The session may have changed while the server answered: an unlock for
      // a session that is no longer current unlocks nothing.
      final current = ref.read(posSyncSessionProvider);
      if (outcome.result == DrawerUnlockResult.unlocked) {
        if (current?.pinSessionId != session.pinSessionId) {
          return DrawerUnlockResult.sessionInvalid;
        }
        final serverNow = outcome.serverNow;
        state = ManualDrawerState(
          unlockedPinSessionId: session.pinSessionId,
          sessionExpiresAt: outcome.sessionExpiresAt,
          serverClockOffset: serverNow == null
              ? Duration.zero
              : serverNow.difference(ref.read(posSyncClockProvider)()),
          busy: true,
        );
        unawaited(flushJournal());
      }
      return outcome.result;
    } finally {
      _inFlight = false;
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  /// Opens the drawer once (see the library doc for the exact order).
  Future<ManualDrawerOpenOutcome> open() async {
    if (_inFlight) return ManualDrawerOpenOutcome.ignored;
    final clock = ref.read(posSyncClockProvider);
    final last = _lastOpenAt;
    if (last != null && clock().difference(last) < kManualDrawerCooldown) {
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
    _inFlight = true;
    state = state.copyWith(busy: true);
    try {
      final kicker = ref.read(posManualDrawerKickerProvider);
      if (!await kicker.isAvailable()) return ManualDrawerOpenOutcome.noPrinter;
      final record = NoSaleRecord(
        localOperationId: ref.read(clientIdGeneratorProvider).newId(),
        pinSessionId: session.pinSessionId,
        deviceId: session.deviceId,
        occurredAt: _serverNow(),
      );
      final push = await ref
          .read(posCashDrawerManualRepositoryProvider)
          .pushNoSale(record);
      switch (push) {
        case NoSalePushResult.recorded:
          return await _pulse(kicker);
        case NoSalePushResult.denied:
          _relockIfFor(session.pinSessionId);
          return ManualDrawerOpenOutcome.denied;
        case NoSalePushResult.sessionInvalid:
          _relockIfFor(session.pinSessionId);
          return ManualDrawerOpenOutcome.sessionEnded;
        case NoSalePushResult.rejected:
        case NoSalePushResult.unconfirmed:
          return ManualDrawerOpenOutcome.cannotRecord;
        case NoSalePushResult.offline:
          if (!_offlineAllowed(session.pinSessionId)) {
            return ManualDrawerOpenOutcome.cannotRecord;
          }
          // Journal FIRST: a pulse without a durable record is exactly what the
          // audit exists to prevent.
          final persisted = await ref
              .read(posCashDrawerNoSaleJournalProvider)
              .append(session.deviceId, record);
          if (!persisted) return ManualDrawerOpenOutcome.cannotRecord;
          _scheduleRetry();
          return await _pulse(kicker);
      }
    } finally {
      _inFlight = false;
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  /// ONE pulse, never retried. The cooldown runs from the pulse itself.
  Future<ManualDrawerOpenOutcome> _pulse(ManualDrawerKicker kicker) async {
    final ok = await kicker.kick();
    _lastOpenAt = ref.read(posSyncClockProvider)();
    return ok
        ? ManualDrawerOpenOutcome.opened
        : ManualDrawerOpenOutcome.sendFailed;
  }

  bool _offlineAllowed(String pinSessionId) {
    // Re-locked while the push was in flight: no offline open.
    if (!state.isUnlockedFor(pinSessionId)) return false;
    final expires = state.sessionExpiresAt;
    if (expires == null) return false; // unknown server window: fail closed
    if (!_serverNow().isBefore(expires.subtract(kManualDrawerOfflineMargin))) {
      return false;
    }
    // The bounded offline window of an offline-restored session still applies.
    return ref.read(posOfflineSessionPolicyProvider).canSubmit;
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(kManualDrawerJournalRetry, () => flushJournal());
  }

  /// Sends every journaled record (oldest first) under the CURRENT session; each
  /// record names its own origin session, so the server attributes it to the
  /// employee who opened the drawer. A record leaves the journal ONLY on a
  /// server verdict that is itself recorded server-side (recorded / denied /
  /// a ledgered rejection). No answer or no verdict keeps it and retries; a
  /// refused current session keeps it until the next sign-in (which flushes).
  Future<void> flushJournal() async {
    if (_flushing || _disposed) return;
    _flushing = true;
    try {
      final deviceId = ref.read(posSyncSessionProvider)?.deviceId;
      if (deviceId == null) return;
      final journal = ref.read(posCashDrawerNoSaleJournalProvider);
      final pending = await journal.pending(deviceId);
      if (pending.isEmpty) return;
      final repo = ref.read(posCashDrawerManualRepositoryProvider);
      for (final record in pending) {
        if (_disposed) return;
        switch (await repo.pushNoSale(record)) {
          case NoSalePushResult.recorded:
          case NoSalePushResult.denied:
          case NoSalePushResult.rejected:
            await journal.remove(deviceId, record.localOperationId);
          case NoSalePushResult.sessionInvalid:
            return;
          case NoSalePushResult.offline:
          case NoSalePushResult.unconfirmed:
            _scheduleRetry();
            return;
        }
      }
    } catch (_) {
      _scheduleRetry();
    } finally {
      _flushing = false;
    }
  }
}
