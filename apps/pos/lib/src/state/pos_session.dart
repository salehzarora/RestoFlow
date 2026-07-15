import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/ids.dart';
import '../data/shift_repository.dart';
import 'pos_device_context.dart';
import 'pos_shift.dart';

/// Operator-supplied real-mode PIN/device context (RF-131), read from
/// `--dart-define`.
///
/// RF-131 deliberately does NOT build login, device pairing, an employee picker,
/// or a PIN-entry UI - those surfaces are still deferred (no client-reachable RPC
/// mints a device session, `public.get_my_context` carries no
/// `employee_profile_id`, and GoTrue sign-in is not wired). Until they land, the
/// three server-minted identifiers and the PIN verifier that
/// `public.start_pin_session` (RF-123/RF-051) needs are supplied by the operator
/// at run time via `--dart-define`, exactly like the Supabase URL / anon key
/// (DECISION D-011) - never hardcoded, never committed.
///
/// FAIL-CLOSED: [fromValues] / [fromEnvironment] return `null` whenever ANY field
/// is blank, so an unconfigured or partially-configured device yields NO session
/// and every real-mode write repository fails closed (no false "live" submit).
///
/// SECURITY: [pinVerifier] is the operator's PIN, verified SERVER-SIDE against a
/// bcrypt hash (the sprint's production verifier replaced the RF-051 interim
/// equality seam). It is forwarded to the RPC over TLS, never logged, and must be
/// passed at run time only (never committed to source). The PREFERRED production
/// path is the interactive PIN screen ([PosSessionController.signInWithPin]);
/// this dart-define config remains an operator fallback.
class PosRealSessionConfig {
  const PosRealSessionConfig._({
    required this.deviceId,
    required this.deviceSessionId,
    required this.employeeProfileId,
    required this.pinVerifier,
  });

  /// The paired device's id (`p_device_id` for `public.sync_push`).
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
  static const String deviceIdEnvName = 'RESTOFLOW_POS_DEVICE_ID';

  /// `--dart-define` key for the active device session id.
  static const String deviceSessionIdEnvName =
      'RESTOFLOW_POS_DEVICE_SESSION_ID';

  /// `--dart-define` key for the employee profile id.
  static const String employeeProfileIdEnvName =
      'RESTOFLOW_POS_EMPLOYEE_PROFILE_ID';

  /// `--dart-define` key for the interim PIN verifier.
  static const String pinVerifierEnvName = 'RESTOFLOW_POS_PIN_VERIFIER';

  /// Builds the context from raw values, or `null` (fail-closed) when ANY value
  /// is blank after trimming.
  static PosRealSessionConfig? fromValues({
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
    return PosRealSessionConfig._(
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
  static PosRealSessionConfig? fromEnvironment({
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
    case PosRealSessionConfig.deviceIdEnvName:
      return const String.fromEnvironment('RESTOFLOW_POS_DEVICE_ID');
    case PosRealSessionConfig.deviceSessionIdEnvName:
      return const String.fromEnvironment('RESTOFLOW_POS_DEVICE_SESSION_ID');
    case PosRealSessionConfig.employeeProfileIdEnvName:
      return const String.fromEnvironment('RESTOFLOW_POS_EMPLOYEE_PROFILE_ID');
    case PosRealSessionConfig.pinVerifierEnvName:
      return const String.fromEnvironment('RESTOFLOW_POS_PIN_VERIFIER');
    default:
      return '';
  }
}

/// The real-mode PIN/device context (RF-131). Null in demo mode (the DEFAULT) and
/// whenever the real device context is unconfigured/incomplete (fail-closed).
/// Tests override this to inject a context without `--dart-define`s.
final posRealSessionConfigProvider = Provider<PosRealSessionConfig?>(
  (ref) => PosRealSessionConfig.fromEnvironment(),
);

/// The shared anon-key `public`-schema RPC transport for real mode (RF-131): one
/// [SupabaseAuthBootstrap] client used by BOTH the `start_pin_session` call here
/// and the outbox `sync_push` push, so the app never constructs two
/// `SupabaseClient`s. Null in demo mode and when the Supabase config is
/// missing/invalid/service-role (fail-closed; clients use the PUBLIC anon key
/// only, DECISION D-011). Tests override this with a fake transport (no network).
final posAuthTransportProvider = Provider<SyncRpcTransport?>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  final supabase = cfg.supabase;
  if (cfg.isDemoMode || supabase == null) return null;
  return SupabaseAuthBootstrap(config: supabase).createRpcTransport();
});

/// The device's read-only signed-URL resolver for menu images (menu/media
/// sprint). Null in demo mode and whenever the real device bootstrap did not
/// run — the POS then renders its imageless cards (fail-soft; images are an
/// enhancement, never load-bearing). Overridden in `main.dart` with the
/// resolver riding the SAME anonymously-authenticated client as the transport.
final posImageUrlResolverProvider = Provider<DeviceImageUrlResolver?>(
  (ref) => null,
);

/// POS-OPERATIONS-SYNC-001 (final review) — WHAT a PIN session is valid FOR.
///
/// A PIN session is minted for ONE exact operational pairing context: the
/// organization, restaurant and branch the device was paired into, the paired
/// device itself, and — the strongest handle both sides already carry — the
/// DEVICE SESSION the PIN session was started against (`start_pin_session`'s
/// `p_device_session_id`). A new pairing always mints a new device session, so the
/// binding distinguishes two pairings even in the hypothetical where a device id
/// were ever reused across them.
///
/// This is CLIENT CONTAINMENT ONLY. The server remains the sole authority on what
/// the session may actually do; the binding exists so a session that outlived its
/// pairing (unpair's server revoke is best-effort and can fail offline) can never
/// unlock a surface, name a sync scope, or be compared by the deviceId alone —
/// which was the previous check, and deviceId alone cannot distinguish "the same
/// till" from "the same till re-paired somewhere else".
class PosPinSessionBinding {
  const PosPinSessionBinding({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.deviceSessionId,
  });

  /// The tenant scope of the pairing the session was established under. Null only
  /// on the legacy dart-define path when no device context existed at establish
  /// time — in which case [matchesContext] can never return true and the operator
  /// signs in through the gate, which records a full binding.
  final String? organizationId;
  final String? restaurantId;
  final String? branchId;

  /// The paired device the session was started on.
  final String? deviceId;

  /// The DEVICE SESSION handle the PIN session was started against — the pairing
  /// identity itself. A re-pair always changes it.
  final String? deviceSessionId;

  /// True only when EVERY component of the current pairing context matches the
  /// one this session was established under. deviceId alone is NOT sufficient:
  /// the same device id in a different branch, tenant, or pairing is a different
  /// operational world.
  bool matchesContext(DeviceContext ctx) =>
      organizationId != null &&
      organizationId == ctx.organizationId &&
      restaurantId == ctx.restaurantId &&
      branchId == ctx.branchId &&
      deviceId != null &&
      deviceId == ctx.deviceId &&
      deviceSessionId != null &&
      deviceSessionId == ctx.deviceSessionId;
}

/// Establishes and owns the POS [SyncSession] for real mode (RF-131).
///
/// In demo mode (the DEFAULT), and whenever the Supabase transport or the
/// operator-supplied [PosRealSessionConfig] is missing, it resolves to `null`
/// (fail-closed) and never contacts a backend. In real mode with a transport and
/// a complete context it calls `public.start_pin_session` (via [PinSessionService])
/// on the paired, active device and, on success, exposes
/// `SyncSession(pinSessionId, deviceId)`. A wrong PIN (NULL), a lockout /
/// precondition failure (42501), or a transient transport error all resolve to
/// `null` (fail-closed) - there is no path to a fake or forced session.
class PosSessionController extends AsyncNotifier<SyncSession?> {
  /// The exact pairing context the CURRENT session was established under, or null
  /// when no session is active. Read via [posPinSessionBindingProvider]; compared
  /// by the PIN gate and the sync-scope provider. Never trusted by the server.
  PosPinSessionBinding? _binding;

  /// The current session's pairing binding (see [PosPinSessionBinding]).
  PosPinSessionBinding? get binding => _binding;

  /// RF-118: when the current PIN session was established (drives the client
  /// expiry policy). Null when no session is active.
  DateTime? _startedAt;

  /// RF-118: when the app was last backgrounded — the last-activity anchor for
  /// the INACTIVITY check (a device left idle re-requires the PIN on resume).
  DateTime? _pausedAt;

  /// RF-118 test seam: the clock the expiry window reads. Defaults to the wall
  /// clock; overridden in tests to exercise the real 30-min / 8-h boundaries
  /// deterministically.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// RF-118: records that the app went to the background (called from the POS
  /// lifecycle guard). The FIRST background moment after a sign-in/resume wins
  /// (`??=`): on mobile, foregrounding passes back through hidden/inactive, which
  /// must NOT reset the idle anchor to ~now (that would defeat inactivity expiry).
  void noteAppPaused() => _pausedAt ??= clock();

  /// RF-118: at a SAFE boundary (app resume), end the session if it is stale per
  /// [policy] (inactivity or the absolute max age). Returns true when it ended a
  /// session (so the gate can show the "session expired — enter PIN again"
  /// notice). Never fires mid-order: it is only consulted on resume, and a
  /// backgrounded POS is not ringing up a sale. Voids no money / order. The pause
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
    // A SESSION DIES WITH ITS PAIRING. Watching the device context means ANY
    // pairing transition — unpair, re-pair, restore into a different context —
    // re-runs this build and DROPS the imperatively-established session (and its
    // binding) on the floor. That is the point: a PIN session belongs to exactly
    // one pairing, the unpair's server-side revoke is only best-effort, and
    // nothing else client-side would ever end the old session. The pairing gate
    // publishes the context once per genuine transition (init / restore / paired /
    // unpair), never per rebuild, so this cannot churn a live session.
    ref.watch(posDeviceContextProvider);
    _binding = null;
    final cfg = ref.watch(runtimeConfigProvider);
    if (cfg.isDemoMode) return null;
    final transport = ref.watch(posAuthTransportProvider);
    final config = ref.watch(posRealSessionConfigProvider);
    // Fail closed when login/transport or the device/PIN context is missing.
    if (transport == null || config == null) return null;
    return _establish(transport, config);
  }

  Future<SyncSession?> _establish(
    SyncRpcTransport transport,
    PosRealSessionConfig config,
  ) async {
    final result = await PinSessionService(transport).startPinSession(
      deviceSessionId: config.deviceSessionId,
      employeeProfileId: config.employeeProfileId,
      pinVerifier: config.pinVerifier,
    );
    return result.fold<SyncSession?>(
      (started) {
        final session = SyncSession(
          pinSessionId: started.pinSessionId,
          deviceId: config.deviceId,
        );
        // Bind the session to the pairing context it was established under. On
        // this legacy dart-define path the context may be absent — the binding
        // then matches NOTHING (fail closed) until a gate sign-in records a full
        // one.
        final ctx = ref.read(posDeviceContextProvider);
        _binding = PosPinSessionBinding(
          organizationId: ctx?.organizationId,
          restaurantId: ctx?.restaurantId,
          branchId: ctx?.branchId,
          deviceId: config.deviceId,
          deviceSessionId: config.deviceSessionId,
        );
        _startedAt = clock(); // RF-118: start the client expiry window.
        _pausedAt = null;
        unawaited(_openShiftBestEffort(transport, session));
        return session;
      },
      // Wrong PIN / locked-or-precondition (42501) / transient: fail closed.
      (failure) => null,
    );
  }

  /// Best-effort shift bootstrap (review fix). RF-055 made `record_payment`
  /// REQUIRE an open shift + active cash drawer, and this build has no shift UI
  /// yet — so the POS opens a REAL shift (opening float 0, server rows, audited)
  /// through the same `sync_push` pipeline right after a staff session starts.
  /// A rejection (a shift is already open for the device, or the operator's
  /// role may not open one) is accepted silently: payment surfaces its own
  /// honest server error if no shift ends up open. Closing/reconciling shifts
  /// (and a real opening-float entry) remain deferred with the RF-055 UI.
  Future<void> _openShiftBestEffort(
    SyncRpcTransport transport,
    SyncSession session,
  ) async {
    final ids = RandomClientIdGenerator();
    final shiftId = ids.newId();
    final cashDrawerSessionId = ids.newId();
    const openingFloatMinor = 0;
    try {
      final raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[
          <String, dynamic>{
            'local_operation_id': ids.newId(),
            'operation_type': 'shift.open',
            'target_entity': 'shift',
            'target_id': shiftId,
            'client_created_at': DateTime.now().toIso8601String(),
            'payload': <String, dynamic>{
              'shift_id': shiftId,
              'cash_drawer_session_id': cashDrawerSessionId,
              'opening_float_minor': openingFloatMinor,
            },
          },
        ],
      });
      // RF-113: capture the shift handle when we actually opened it, so the
      // close/reconcile UI has the shift id + opening float. A conflict (a shift
      // already open with a different id) leaves the handle null -> the close UI
      // shows an honest "no open shift on this device" state (never a fake one).
      if (_shiftOpenApplied(raw)) {
        ref
            .read(posOpenShiftProvider.notifier)
            .set(
              PosOpenShift(
                shiftId: shiftId,
                cashDrawerSessionId: cashDrawerSessionId,
                openingFloatMinor: openingFloatMinor,
                openedAt: DateTime.now(),
              ),
            );
      } else {
        // The open did NOT apply — almost always because a shift is ALREADY
        // open for this (org, branch, device) from before a refresh/re-sign-in.
        // RECOVER that shift's handle via a secure sync_pull read so the
        // close/reconcile UI works instead of falsely reporting "no open shift".
        await _recoverOpenShift(transport, session);
      }
    } catch (_) {
      // Best-effort: the payment path reports its own error if no shift opened.
    }
  }

  /// Recover the current server-open shift's handle for this device (RF-113).
  /// Fail-soft: on any read failure the handle stays null and the panel shows an
  /// honest "couldn't restore — sign in again" state (never a fake shift).
  Future<void> _recoverOpenShift(
    SyncRpcTransport transport,
    SyncSession session,
  ) async {
    try {
      final info = await RealShiftRepository(
        transport,
        session,
        RandomClientIdGenerator(),
      ).readOpenShift();
      if (info != null) {
        ref
            .read(posOpenShiftProvider.notifier)
            .set(
              PosOpenShift(
                shiftId: info.shiftId,
                cashDrawerSessionId: info.cashDrawerSessionId,
                openingFloatMinor: info.openingFloatMinor,
                openedAt: info.openedAt,
                // PILOT-OPERATIONS-CORRECTIONS-001: carry the server-authoritative
                // expected cash so the close UI shows the real figure after restart.
                expectedCashMinor: info.expectedCashMinor,
              ),
            );
      }
    } catch (_) {
      // Fail-soft: leave the handle null.
    }
  }

  /// True when the `shift.open` op in a `sync_push` envelope applied (the shift is
  /// now open for the id we sent). An idempotent replay of the SAME shift also
  /// reports 'applied'; a conflict/rejection does not.
  bool _shiftOpenApplied(Object? raw) {
    if (raw is! Map) return false;
    final results = raw['results'];
    if (results is! List) return false;
    for (final r in results) {
      if (r is Map && r['operation_type'] == 'shift.open') {
        return r['status'] == 'applied' && r['ok'] != false;
      }
    }
    return false;
  }

  /// INTERACTIVE PIN sign-in (sprint): establishes the session from the RESTORED
  /// device context (the paired device's id + in-memory device-session handle)
  /// plus the staff member + typed PIN from the shared [PinLoginScreen]. The PIN
  /// travels over the authenticated TLS transport to `start_pin_session` and is
  /// verified server-side (bcrypt); it is never stored or logged. Returns null
  /// on success (the session is exposed via [posSyncSessionProvider]) or a
  /// typed, safe [PinLoginError] for the screen to show. Fail-closed: any
  /// failure leaves the session null.
  Future<PinLoginError?> signInWithPin({
    required DeviceContext device,
    required String deviceId,
    required String deviceSessionId,
    required String employeeProfileId,
    required String pin,
    String? employeeDisplayName,
  }) async {
    final transport = ref.read(posAuthTransportProvider);
    if (transport == null) return PinLoginError.unavailable;
    final result = await PinSessionService(transport).startPinSession(
      deviceSessionId: deviceSessionId,
      employeeProfileId: employeeProfileId,
      pinVerifier: pin,
    );
    return result.fold<PinLoginError?>(
      (started) {
        final session = SyncSession(
          pinSessionId: started.pinSessionId,
          deviceId: deviceId,
        );
        // The session is valid for EXACTLY this pairing context and no other.
        _binding = PosPinSessionBinding(
          organizationId: device.organizationId,
          restaurantId: device.restaurantId,
          branchId: device.branchId,
          deviceId: deviceId,
          deviceSessionId: deviceSessionId,
        );
        _startedAt = clock(); // RF-118: start the client expiry window.
        _pausedAt = null;
        state = AsyncData(session);
        // PILOT-OPERATIONS-CORRECTIONS-001: remember whose shift this is (identity
        // text only) so the shift-close surface can name the operator.
        ref
            .read(posSignedInStaffNameProvider.notifier)
            .set(employeeDisplayName);
        // A cashier needs an open shift before payments (RF-055); best-effort.
        unawaited(_openShiftBestEffort(transport, session));
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

  /// Ends the current staff session locally (the server session expires on its
  /// own window — Q-009). The POS falls back to the PIN screen. Clears the
  /// captured open-shift handle (RF-113) so a new sign-in starts fresh.
  void endSession() {
    ref.read(posOpenShiftProvider.notifier).clear();
    ref.read(posSignedInStaffNameProvider.notifier).clear();
    _binding = null;
    _startedAt = null; // RF-118: close the client expiry window.
    _pausedAt = null;
    state = const AsyncData(null);
  }
}

/// The display name of the currently signed-in POS employee (from the PIN roster),
/// or null when unknown. PILOT-OPERATIONS-CORRECTIONS-001: shown on the shift-close
/// surface so the operator sees whose shift they are closing. Set at PIN sign-in,
/// cleared on sign-out. Money-free identity text only; never a stale previous
/// operator (cleared before a new session is established).
class PosSignedInStaffName extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? name) =>
      state = (name != null && name.trim().isNotEmpty) ? name.trim() : null;

  void clear() => state = null;
}

final posSignedInStaffNameProvider =
    NotifierProvider<PosSignedInStaffName, String?>(PosSignedInStaffName.new);

/// RF-118: the POS staff PIN-session expiry policy (client-side). Defaults to an
/// 8-hour absolute max age (mirroring the SERVER `pin_sessions.expires_at`
/// window, RF-051) plus a 30-minute inactivity timeout — generous enough that a
/// normal service session (or the RF-112 browser smoke) never trips, but a
/// device left idle re-requires the PIN on the next resume. Overridable in tests.
final posPinSessionExpiryPolicyProvider = Provider<PinSessionExpiryPolicy>(
  (ref) => const PinSessionExpiryPolicy(),
);

/// Owns [PosSessionController].
final posSessionControllerProvider =
    AsyncNotifierProvider<PosSessionController, SyncSession?>(
      PosSessionController.new,
    );

/// The current authenticated POS sync session - the `(pinSessionId, deviceId)`
/// tuple needed to call `public.sync_push` (RF-126) in real mode, or `null` when
/// no real session is established.
///
/// It is `null` in demo mode (the DEFAULT) and, in real mode, until
/// [PosSessionController] has established a session from an authenticated context
/// (a Supabase transport + a complete [PosRealSessionConfig] + a successful
/// `start_pin_session`). While the session is loading, or after any failure, it
/// stays `null`, so the real-mode write repositories (e.g. [RealOutboxRepository])
/// fail closed - there is no path to a false "live" submit. Nothing else in the
/// write path changes: it simply reads a non-null session here once one exists.
final posSyncSessionProvider = Provider<SyncSession?>(
  (ref) => ref.watch(posSessionControllerProvider).valueOrNull,
);

/// The pairing binding of the CURRENT PIN session, or null when there is no
/// controller-established session.
///
/// Every production session flows through [PosSessionController] and therefore
/// carries a binding; a session injected past the controller (a test override of
/// [posSyncSessionProvider]) has none, and consumers document how they fail in
/// that case. Recomputed whenever the session changes.
final posPinSessionBindingProvider = Provider<PosPinSessionBinding?>((ref) {
  ref.watch(posSessionControllerProvider);
  return ref.read(posSessionControllerProvider.notifier).binding;
});
