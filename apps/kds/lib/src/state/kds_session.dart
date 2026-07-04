import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// Operator-supplied real-mode PIN/device context for the KDS (RF-136), read from
/// `--dart-define`.
///
/// RF-136 wires the KDS app to REAL polling-first `public.sync_pull` (the engine,
/// transport, and money-free mapper already exist from RF-063). It deliberately
/// does NOT build login, device pairing, an employee picker, or a PIN-entry UI -
/// those surfaces are still deferred (no client-reachable RPC mints a device
/// session, `public.get_my_context` carries no `employee_profile_id`, and GoTrue
/// sign-in is not wired). Until they land, the three server-minted identifiers and
/// the PIN verifier that `public.start_pin_session` (RF-123/RF-051) needs are
/// supplied by the operator at run time via `--dart-define`, exactly like the
/// Supabase URL / anon key (DECISION D-011) - never hardcoded, never committed.
/// This mirrors the POS RF-131 pattern (apps/pos/lib/src/state/pos_session.dart);
/// KDS uses its own `RESTOFLOW_KDS_*` keys so one device can be either surface.
///
/// FAIL-CLOSED: [fromValues] / [fromEnvironment] return `null` whenever ANY field
/// is blank, so an unconfigured or partially-configured device yields NO session.
/// The KDS then stays on the demo/auth board and never contacts a backend - there
/// is no path to a fake "live" feed.
///
/// SECURITY: [pinVerifier] is the operator's PIN, verified SERVER-SIDE against a
/// bcrypt hash (the sprint's production verifier replaced the RF-051 interim
/// equality seam). It is forwarded to the RPC over TLS, never logged, and must be
/// passed at run time only (never committed to source). The PREFERRED production
/// path is the interactive PIN screen ([KdsSessionController.signInWithPin]);
/// this dart-define config remains an operator fallback.
class KdsRealSessionConfig {
  const KdsRealSessionConfig._({
    required this.deviceId,
    required this.deviceSessionId,
    required this.employeeProfileId,
    required this.pinVerifier,
  });

  /// The paired device's id (`p_device_id` for `public.sync_pull`).
  final String deviceId;

  /// The active device session id (`p_device_session_id`), minted out-of-band by
  /// a manager via `public.start_device_session` (a device-originated minting
  /// path is deferred).
  final String deviceSessionId;

  /// The signing-in employee's profile id (`p_employee_profile_id`).
  final String employeeProfileId;

  /// The opaque PIN verifier (RF-051 interim seam). Never logged.
  final String pinVerifier;

  /// `--dart-define` key for the paired device id.
  static const String deviceIdEnvName = 'RESTOFLOW_KDS_DEVICE_ID';

  /// `--dart-define` key for the active device session id.
  static const String deviceSessionIdEnvName =
      'RESTOFLOW_KDS_DEVICE_SESSION_ID';

  /// `--dart-define` key for the employee profile id.
  static const String employeeProfileIdEnvName =
      'RESTOFLOW_KDS_EMPLOYEE_PROFILE_ID';

  /// `--dart-define` key for the interim PIN verifier.
  static const String pinVerifierEnvName = 'RESTOFLOW_KDS_PIN_VERIFIER';

  /// Builds the context from raw values, or `null` (fail-closed) when ANY value
  /// is blank after trimming.
  static KdsRealSessionConfig? fromValues({
    required String deviceId,
    required String deviceSessionId,
    required String employeeProfileId,
    required String pinVerifier,
  }) {
    final device = deviceId.trim();
    final deviceSession = deviceSessionId.trim();
    final employee = employeeProfileId.trim();
    final verifier = pinVerifier.trim();
    if (device.isEmpty ||
        deviceSession.isEmpty ||
        employee.isEmpty ||
        verifier.isEmpty) {
      return null;
    }
    return KdsRealSessionConfig._(
      deviceId: device,
      deviceSessionId: deviceSession,
      employeeProfileId: employee,
      pinVerifier: verifier,
    );
  }

  /// Reads the four `--dart-define` values and builds the context, or `null`
  /// (fail-closed) when incomplete. [readEnv] is injectable so unit tests supply
  /// an environment map without compile-time defines; the default reads the
  /// compile-time `String.fromEnvironment` values.
  static KdsRealSessionConfig? fromEnvironment({
    String Function(String name)? readEnv,
  }) {
    final read = readEnv ?? _readDartDefine;
    return fromValues(
      deviceId: read(deviceIdEnvName),
      deviceSessionId: read(deviceSessionIdEnvName),
      employeeProfileId: read(employeeProfileIdEnvName),
      pinVerifier: read(pinVerifierEnvName),
    );
  }
}

/// Reads a compile-time `--dart-define` (the production source). Returns '' when
/// the define is absent, so the context fails closed.
String _readDartDefine(String name) {
  switch (name) {
    case KdsRealSessionConfig.deviceIdEnvName:
      return const String.fromEnvironment('RESTOFLOW_KDS_DEVICE_ID');
    case KdsRealSessionConfig.deviceSessionIdEnvName:
      return const String.fromEnvironment('RESTOFLOW_KDS_DEVICE_SESSION_ID');
    case KdsRealSessionConfig.employeeProfileIdEnvName:
      return const String.fromEnvironment('RESTOFLOW_KDS_EMPLOYEE_PROFILE_ID');
    case KdsRealSessionConfig.pinVerifierEnvName:
      return const String.fromEnvironment('RESTOFLOW_KDS_PIN_VERIFIER');
    default:
      return '';
  }
}

/// The real-mode PIN/device context (RF-136). Null in demo mode (the DEFAULT) and
/// whenever the real device context is unconfigured/incomplete (fail-closed).
/// Tests override this to inject a context without `--dart-define`s.
final kdsRealSessionConfigProvider = Provider<KdsRealSessionConfig?>(
  (ref) => KdsRealSessionConfig.fromEnvironment(),
);

/// The shared anon-key `public`-schema RPC transport for real mode (RF-136): one
/// [SupabaseAuthBootstrap] client used by BOTH the `start_pin_session` call here
/// and the `sync_pull` polling, so the app never constructs two `SupabaseClient`s.
/// Null in demo mode and when the Supabase config is missing/invalid/service-role
/// (fail-closed; clients use the PUBLIC anon key only, DECISION D-011). Tests
/// override this with a fake transport (no network).
final kdsAuthTransportProvider = Provider<SyncRpcTransport?>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  final supabase = cfg.supabase;
  if (cfg.isDemoMode || supabase == null) return null;
  return SupabaseAuthBootstrap(config: supabase).createRpcTransport();
});

/// Establishes and owns the KDS [SyncSession] for real mode (RF-136).
///
/// In demo mode (the DEFAULT), and whenever the Supabase transport or the
/// operator-supplied [KdsRealSessionConfig] is missing, it resolves to `null`
/// (fail-closed) and never contacts a backend. In real mode with a transport and
/// a complete context it calls `public.start_pin_session` (via [PinSessionService])
/// on the paired, active device and, on success, exposes
/// `SyncSession(pinSessionId, deviceId)`. A wrong PIN (NULL), a lockout /
/// precondition failure (42501), or a transient transport error all resolve to
/// `null` (fail-closed) - there is no path to a fake or forced session.
class KdsSessionController extends AsyncNotifier<SyncSession?> {
  /// RF-118: when the current PIN session was established (drives the client
  /// expiry policy). Null when no session is active. Mirrors the POS controller.
  DateTime? _startedAt;

  /// RF-118: when the app was last backgrounded — the last-activity anchor for
  /// the INACTIVITY check (a device left idle re-requires the PIN on resume).
  DateTime? _pausedAt;

  /// RF-118 test seam: the clock the expiry window reads. Defaults to the wall
  /// clock; overridden in tests to exercise the real 30-min / 8-h boundaries
  /// deterministically.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// RF-118: records that the app went to the background (called from the KDS
  /// lifecycle guard). The FIRST background moment after a sign-in/resume wins
  /// (`??=`): on mobile, foregrounding passes back through hidden/inactive, which
  /// must NOT reset the idle anchor to ~now (that would defeat inactivity expiry).
  void noteAppPaused() => _pausedAt ??= clock();

  /// RF-118: at a SAFE boundary (app resume), end the session if it is stale per
  /// [policy] (inactivity or the absolute max age). Returns true when it ended a
  /// session (so the gate can show the "session expired — enter PIN again"
  /// notice). The KDS surface is money-free, so this only ever drops the kitchen
  /// board back to the PIN screen — it touches no financial state. The pause
  /// anchor is CONSUMED here so the next background cycle re-records it; when the
  /// app was never backgrounded (anchor null) the operator counts as active
  /// (lastActivity = now, zero idle) so only the max age can expire the session.
  bool endSessionIfExpired(PinSessionExpiryPolicy policy) {
    final started = _startedAt;
    if (state.valueOrNull == null || started == null) return false;
    final pausedAt = _pausedAt;
    _pausedAt = null;
    final now = clock();
    if (!policy.isExpired(
      startedAt: started,
      lastActivityAt: pausedAt ?? now,
      now: now,
    )) {
      return false;
    }
    endSession();
    return true;
  }

  @override
  FutureOr<SyncSession?> build() {
    final cfg = ref.watch(runtimeConfigProvider);
    if (cfg.isDemoMode) return null;
    final transport = ref.watch(kdsAuthTransportProvider);
    final config = ref.watch(kdsRealSessionConfigProvider);
    // Fail closed when login/transport or the device/PIN context is missing.
    if (transport == null || config == null) return null;
    return _establish(transport, config);
  }

  Future<SyncSession?> _establish(
    SyncRpcTransport transport,
    KdsRealSessionConfig config,
  ) async {
    final result = await PinSessionService(transport).startPinSession(
      deviceSessionId: config.deviceSessionId,
      employeeProfileId: config.employeeProfileId,
      pinVerifier: config.pinVerifier,
    );
    return result.fold<SyncSession?>(
      (started) {
        _startedAt = clock(); // RF-118: start the client expiry window.
        _pausedAt = null;
        return SyncSession(
          pinSessionId: started.pinSessionId,
          deviceId: config.deviceId,
        );
      },
      // Wrong PIN / locked-or-precondition (42501) / transient: fail closed.
      (failure) => null,
    );
  }

  /// INTERACTIVE PIN sign-in (sprint): establishes the session from the RESTORED
  /// device context (paired device id + in-memory device-session handle) plus
  /// the staff member + typed PIN from the shared, money-free [PinLoginScreen].
  /// Verified server-side (bcrypt); the PIN is never stored or logged. Returns
  /// null on success (the live board mounts via [kdsSyncSessionProvider]) or a
  /// typed, safe [PinLoginError]. Fail-closed: any failure leaves the session
  /// null and the KDS never fakes a live feed.
  Future<PinLoginError?> signInWithPin({
    required String deviceId,
    required String deviceSessionId,
    required String employeeProfileId,
    required String pin,
  }) async {
    final transport = ref.read(kdsAuthTransportProvider);
    if (transport == null) return PinLoginError.unavailable;
    final result = await PinSessionService(transport).startPinSession(
      deviceSessionId: deviceSessionId,
      employeeProfileId: employeeProfileId,
      pinVerifier: pin,
    );
    return result.fold<PinLoginError?>(
      (started) {
        _startedAt = clock(); // RF-118: start the client expiry window.
        _pausedAt = null;
        state = AsyncData(
          SyncSession(pinSessionId: started.pinSessionId, deviceId: deviceId),
        );
        return null;
      },
      (failure) => switch (failure) {
        AuthWrongPinFailure() => PinLoginError.wrongPin,
        AuthLockedOrPreconditionFailure() => PinLoginError.locked,
        AuthNetworkFailure() => PinLoginError.network,
        _ => PinLoginError.unavailable,
      },
    );
  }

  /// Ends the current staff session locally (the server window expires on its
  /// own — Q-009). The KDS falls back to the PIN screen.
  void endSession() {
    _startedAt = null; // RF-118: close the client expiry window.
    _pausedAt = null;
    state = const AsyncData(null);
  }
}

/// Owns [KdsSessionController].
final kdsSessionControllerProvider =
    AsyncNotifierProvider<KdsSessionController, SyncSession?>(
      KdsSessionController.new,
    );

/// RF-118: the KDS staff PIN-session expiry policy (client-side) — the SAME
/// default as the POS (8-hour absolute max age mirroring the server
/// `pin_sessions.expires_at` window, RF-051, plus a 30-minute inactivity
/// timeout). Generous enough that a normal kitchen session never trips, but a
/// device left idle re-requires the PIN on the next resume. Overridable in tests.
final kdsPinSessionExpiryPolicyProvider = Provider<PinSessionExpiryPolicy>(
  (ref) => const PinSessionExpiryPolicy(),
);

/// RF-118: whether the LAST sign-out was due to session expiry, so the PIN gate
/// shows the "enter PIN again" notice after the app root re-mounts it.
///
/// The KDS routes the LIVE board (`KdsSyncedHome`) as a SIBLING of the gate
/// (`home: live ? board : gate`), so the gate — and any lifecycle observer inside
/// it — is torn down the instant a session goes live (unlike the POS, whose gate
/// stays mounted as the surface's parent). The lifecycle observer therefore lives
/// at the app root (`KdsSessionLifecycleObserver`), ABOVE that swap, and hands the
/// expiry signal to the re-mounted gate through THIS provider. Cleared whenever a
/// new session is established.
class KdsExpiredNoticeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// An inactivity/max-age expiry just signed the operator out.
  void show() => state = true;

  /// A fresh session (or a manual re-entry) clears the notice.
  void clear() => state = false;
}

final kdsExpiredNoticeProvider =
    NotifierProvider<KdsExpiredNoticeNotifier, bool>(
      KdsExpiredNoticeNotifier.new,
    );

/// The current authenticated KDS sync session - the `(pinSessionId, deviceId)`
/// tuple needed to poll `public.sync_pull` (RF-064) in real mode, or `null` when
/// no real session is established.
///
/// It is `null` in demo mode (the DEFAULT) and, in real mode, until
/// [KdsSessionController] has established a session from an authenticated context
/// (a Supabase transport + a complete [KdsRealSessionConfig] + a successful
/// `start_pin_session`). While the session is loading, or after any failure, it
/// stays `null`. The app root reads this to decide whether to mount the live
/// [KdsSyncedHome] board - a null session keeps the demo/auth board, so the KDS
/// never fakes a live feed.
final kdsSyncSessionProvider = Provider<SyncSession?>(
  (ref) => ref.watch(kdsSessionControllerProvider).valueOrNull,
);

/// The real-mode KDS sync source (RF-136): a polling-first `public.sync_pull`
/// [KdsSyncCoordinator] built from the established [SyncSession] + the shared
/// anon-key transport. `null` in demo mode (the DEFAULT) and whenever the
/// transport or session is missing (fail-closed) - the app root then keeps the
/// demo/auth board.
///
/// Money-free by construction: the coordinator only ever requests the
/// non-financial kitchen entities (`kKdsPullEntities` = orders / order_items /
/// order_item_modifiers), so no `*_minor` / receipt field is ever pulled
/// (SECURITY T-003). Disposal is owned by `kdsRepositoryProvider` (which disposes
/// the wrapped source); the coordinator's `dispose()` is idempotent.
final kdsRealSyncSourceProvider = Provider<KdsSyncSource?>((ref) {
  final transport = ref.watch(kdsAuthTransportProvider);
  final session = ref.watch(kdsSyncSessionProvider);
  if (transport == null || session == null) return null;
  return KdsSyncCoordinator(api: SyncPullApi(transport), session: session);
});
