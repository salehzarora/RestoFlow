import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/ids.dart';
import '../data/secure_session_store.dart';
import '../data/shift_repository.dart';
import '../data/sync_cursor_store.dart' show PosSyncScope;
import 'cart_controller.dart' show posActiveCorrectionSourceProvider;
import 'outbox_controller.dart' show outboxControllerProvider;
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

  /// [POS-OFFLINE-OPERATIONS-002] (C6): true when the CURRENT session was
  /// restored from the secure store WITHOUT a server round-trip. Cleared by
  /// the next proven-online verification ([noteOnlineVerified]) and by every
  /// fresh online establish. Mirrored reactively into
  /// [posSessionOfflineRestoreInfoProvider].
  bool _restoredOffline = false;

  /// The hard end of the restored session's offline trust window
  /// (`min(serverExpiry ?? +inf, lastOnlineVerify + 8h)`); null when the
  /// session is live-online.
  DateTime? _offlineValidUntil;

  /// Throttle anchor for reconnect revalidation: the last time
  /// `last_online_verify` was PERSISTED (>5 min between writes, so a busy
  /// till's every push does not churn secure storage).
  DateTime? _lastVerifyPersistedAt;

  bool get restoredOffline => _restoredOffline;
  DateTime? get offlineValidUntil => _offlineValidUntil;

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
    // [POS-OFFLINE-OPERATIONS-002] The CLIENT-side idle/max-age expiry ends
    // the in-memory session but deliberately KEEPS the secure store record:
    // its own hard offline window (min(serverExpiry, lastOnlineVerify + 8h))
    // still bounds any restore, and the restore paths re-require the same
    // operator at the PIN gate. Only an explicit logout/unpair or a SERVER
    // auth refusal destroys the offline-continuity record.
    endSession(clearStoredSession: false);
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
    final ctx = ref.watch(posDeviceContextProvider);
    // [POS-OFFLINE-OPERATIONS-002] When a PAIRING TRANSITION (unpair / re-pair
    // into a different context) drops a bound session, the persisted offline
    // copy dies with it: a till unpaired from branch A must never restore
    // branch A's session, even before the store's own deviceSessionId check
    // would refuse it. A rebuild whose context still matches the old binding
    // (config churn, not a pairing change) keeps the record — that is exactly
    // the restart-continuity C6 exists for.
    final previousBinding = _binding;
    if (previousBinding != null &&
        (ctx == null || !previousBinding.matchesContext(ctx))) {
      final staleScope = _scopeOfBinding(previousBinding);
      if (staleScope != null) {
        // Timer-free fire-and-forget (Future(...) would arm a zero-duration
        // Timer, which widget tests flag as pending): the store contains its
        // own failures, so the bare future needs only an error sink.
        final store = ref.read(posSecureSessionStoreProvider);
        unawaited(store.clear(staleScope).catchError((_) {}));
      }
    }
    _binding = null;
    if (previousBinding != null) {
      // A REBUILD dropped a live session — reset the reactive mirror with it
      // (deferred one microtask: build() may not write another provider
      // synchronously). A first build has nothing to reset: the mirror's own
      // default is already "none", and publishing here would clobber a test's
      // override of the mirror before anything genuinely transitioned.
      _setOfflineRestoreInfo(restored: false, validUntil: null, deferred: true);
    } else {
      _restoredOffline = false;
      _offlineValidUntil = null;
    }
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
        // MENU-ORDER-001 (Codex #1): publish the stable worker id on the
        // dart-define path too (recovery ownership).
        ref
            .read(posSignedInEmployeeProfileIdProvider.notifier)
            .set(config.employeeProfileId);
        // [POS-OFFLINE-OPERATIONS-002] A successful ONLINE establish persists
        // the bounded offline-continuity record and releases any AUTH_HOLD
        // queued work (both contained; never load-bearing for sign-in).
        _afterOnlineEstablish(
          sessionId: started.pinSessionId,
          employeeProfileId: config.employeeProfileId,
          displayName: null,
        );
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
        // Finding 3: a fresh shift-open is NOT proof of close authorization. Publish a
        // FAIL-CLOSED, authorization-pending handle first (a shift IS open, but no close
        // form / no money until we know), then fetch the AUTHORITATIVE summary and
        // replace it with the server verdict (canClose / capability-denied / owner
        // mismatch + money). NEVER a permissive canClose=true handle.
        ref
            .read(posOpenShiftProvider.notifier)
            .set(
              PosOpenShift(
                shiftId: shiftId,
                cashDrawerSessionId: cashDrawerSessionId,
                openingFloatMinor: openingFloatMinor,
                openedAt: DateTime.now(),
                authorizationPending: true, // canClose defaults false
              ),
            );
        final published = await _recoverOpenShift(transport, session);
        if (!published) {
          // The authoritative summary could not be read: keep a fail-closed handle
          // (shift open, authorization unknown) — never assume close permission.
          ref
              .read(posOpenShiftProvider.notifier)
              .set(
                PosOpenShift(
                  shiftId: shiftId,
                  cashDrawerSessionId: cashDrawerSessionId,
                  openingFloatMinor: openingFloatMinor,
                  openedAt: DateTime.now(),
                  authorizationPending: true,
                ),
              );
        }
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

  /// Recover the current server-open shift's handle for this device (RF-113) from the
  /// AUTHORITATIVE summary. Returns true iff a handle was published from a server verdict
  /// (Finding 3: the caller re-publishes a fail-closed handle when this returns false
  /// after a fresh open). Fail-soft: on any read failure nothing is published here.
  Future<bool> _recoverOpenShift(
    SyncRpcTransport transport,
    SyncSession session,
  ) async {
    try {
      final info = await RealShiftRepository(
        transport,
        session,
        RandomClientIdGenerator(),
      ).readOpenShift();
      if (info == null) return false;
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
              // B1 + Finding 2 + Finding 3: the AUTHORITATIVE close-authorization
              // verdict — the ONLY thing that publishes a closable handle. Its arrival
              // clears authorizationPending.
              canClose: info.canClose,
              ownerMismatch: info.ownerMismatch,
              closeNotAllowed: info.closeNotAllowed,
              openedByEmployeeProfileId: info.openedByEmployeeProfileId,
            ),
          );
      return true;
    } catch (_) {
      // Fail-soft: publish nothing (the caller decides the fail-closed fallback).
      return false;
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
        // MENU-ORDER-001 (Codex #1): publish the STABLE worker id so a durable
        // recovery is owned by this worker (reclaimable after restart+re-login),
        // not the ephemeral pinSessionId.
        ref
            .read(posSignedInEmployeeProfileIdProvider.notifier)
            .set(employeeProfileId);
        // [POS-OFFLINE-OPERATIONS-002] A successful ONLINE establish persists
        // the bounded offline-continuity record (C6) and releases any
        // AUTH_HOLD queued work (C8). Contained; never load-bearing here.
        _afterOnlineEstablish(
          sessionId: started.pinSessionId,
          employeeProfileId: employeeProfileId,
          displayName: employeeDisplayName,
        );
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
  ///
  /// [POS-OFFLINE-OPERATIONS-002] [clearStoredSession] (default TRUE) also
  /// destroys the secure offline-continuity record — the right default for
  /// every EXPLICIT sign-out path (shift close, sign-out buttons) and for a
  /// server auth refusal. The RF-118 client idle/max-age expiry passes FALSE:
  /// the record's own hard window still bounds any restore, and destroying it
  /// there would brick a till that merely sat idle offline.
  void endSession({bool clearStoredSession = true}) {
    if (clearStoredSession) {
      final scope = _scopeOfBinding(_binding);
      if (scope != null) {
        final store = ref.read(posSecureSessionStoreProvider);
        unawaited(store.clear(scope).catchError((_) {}));
      }
    }
    ref.read(posOpenShiftProvider.notifier).clear();
    ref.read(posSignedInStaffNameProvider.notifier).clear();
    ref.read(posSignedInEmployeeProfileIdProvider.notifier).clear();
    // MENU-ORDER-001 (Codex correction-ownership §2/§9): drop the in-memory active
    // correction source on sign-out / worker handover. Clearing the signed-in worker id
    // already makes the DURABLE recovery inaccessible (binding mismatch) without deleting
    // it — the same worker reclaims it on re-login — but the volatile active source must
    // also be reset so the next worker's first submit can never re-link A's recovery.
    ref.read(posActiveCorrectionSourceProvider.notifier).clear();
    _binding = null;
    _startedAt = null; // RF-118: close the client expiry window.
    _pausedAt = null;
    _lastVerifyPersistedAt = null;
    _setOfflineRestoreInfo(restored: false, validUntil: null);
    state = const AsyncData(null);
  }

  // ---------------------------------------------------------------------
  // [POS-OFFLINE-OPERATIONS-002] (C6/C8) — secure bounded session
  // persistence, offline restore, reconnect revalidation, AUTH_HOLD release.
  // ---------------------------------------------------------------------

  /// The durable-store scope of [binding], or null when the binding is not a
  /// FULL pairing binding (the legacy dart-define path with no context —
  /// nothing may persist or restore for a scope we cannot fully name).
  PosSyncScope? _scopeOfBinding(PosPinSessionBinding? binding) {
    final organizationId = binding?.organizationId;
    final branchId = binding?.branchId;
    final deviceId = binding?.deviceId;
    if (binding == null ||
        organizationId == null ||
        branchId == null ||
        deviceId == null ||
        binding.deviceSessionId == null) {
      return null;
    }
    return PosSyncScope(
      organizationId: organizationId,
      restaurantId: binding.restaurantId ?? '',
      branchId: branchId,
      deviceId: deviceId,
    );
  }

  /// Publishes the restored-offline flags: synchronously into the controller
  /// fields, and (one microtask deferred when [deferred] — build() may not
  /// write another provider synchronously, the recovery-002 rule) into the
  /// reactive [posSessionOfflineRestoreInfoProvider] mirror. The deferred
  /// write publishes the CURRENT fields, so a faster subsequent transition is
  /// never clobbered by a stale capture.
  void _setOfflineRestoreInfo({
    required bool restored,
    required DateTime? validUntil,
    bool deferred = false,
  }) {
    _restoredOffline = restored;
    _offlineValidUntil = validUntil;
    void publish() {
      try {
        ref
            .read(posSessionOfflineRestoreInfoProvider.notifier)
            .publish(
              restoredOffline: _restoredOffline,
              validUntil: _offlineValidUntil,
            );
      } catch (_) {
        // Container torn down mid-transition — nothing to mirror into.
      }
    }

    if (deferred) {
      Future<void>.microtask(publish);
    } else {
      publish();
    }
  }

  /// Runs after EVERY successful ONLINE `start_pin_session`: persists the
  /// bounded offline-continuity record for the full pairing scope, clears the
  /// re-auth notice, and releases AUTH_HOLD outbox work so it resubmits under
  /// the fresh session with its ORIGINAL `(deviceId, localOperationId)`
  /// identity. Everything here is contained — a failure can never fail or
  /// delay the sign-in that triggered it.
  void _afterOnlineEstablish({
    required String sessionId,
    required String employeeProfileId,
    required String? displayName,
  }) {
    final now = clock();
    _setOfflineRestoreInfo(restored: false, validUntil: null);
    try {
      ref.read(posSessionReauthNoticeProvider.notifier).clear();
    } catch (_) {}
    final binding = _binding;
    final scope = _scopeOfBinding(binding);
    final deviceSessionId = binding?.deviceSessionId;
    if (scope != null && deviceSessionId != null) {
      _lastVerifyPersistedAt = now;
      final record = PosStoredPinSession(
        sessionId: sessionId,
        employeeProfileId: employeeProfileId,
        organizationId: scope.organizationId,
        restaurantId: scope.restaurantId,
        branchId: scope.branchId,
        deviceId: scope.deviceId,
        deviceSessionId: deviceSessionId,
        lastOnlineVerify: now.toUtc(),
        displayName: displayName,
        // start_pin_session returns a bare uuid (no expiry on the wire); the
        // 8h offline window is the binding bound until the server exposes one.
        serverExpiry: null,
      );
      final store = ref.read(posSecureSessionStoreProvider);
      unawaited(store.save(scope, record).catchError((_) {}));
    }
    // C8 release seam: a fresh ONLINE sign-in is the ONE event that releases
    // auth-held work back to pending (the controller then sweeps normally).
    try {
      unawaited(
        ref
            .read(outboxControllerProvider.notifier)
            .releaseAuthHold()
            .catchError((_) => 0),
      );
    } catch (_) {
      // Contained — release is retried on the next successful sign-in.
    }
  }

  /// [POS-OFFLINE-OPERATIONS-002] (C6): attempts to restore the persisted PIN
  /// session for EXACTLY the current pairing [device] — called by the PIN gate
  /// when `start_pin_session` failed at the TRANSPORT level (never on a server
  /// refusal) or when its cold-boot offline probe proved the backend
  /// unreachable. The restored session is marked [restoredOffline]; submission
  /// stays allowed strictly until the record's hard offline window ends
  /// ([posOfflineSessionPolicyProvider] consumes the mirror of that window).
  ///
  /// [attemptedEmployeeProfileId], when given (the typed-PIN path), must match
  /// the stored operator — a transport failure during B's sign-in must never
  /// resurrect A's session under B's fingers.
  Future<PosOfflineRestoreResult> restoreOfflineSession({
    required DeviceContext device,
    String? attemptedEmployeeProfileId,
  }) async {
    if (ref.read(runtimeConfigProvider).isDemoMode) {
      return PosOfflineRestoreResult.unavailable;
    }
    if (state.valueOrNull != null) {
      return PosOfflineRestoreResult.alreadySignedIn;
    }
    final deviceId = device.deviceId;
    final deviceSessionId = device.deviceSessionId;
    if (deviceId == null || deviceId.isEmpty || deviceSessionId == null) {
      return PosOfflineRestoreResult.unavailable;
    }
    final scope = PosSyncScope(
      organizationId: device.organizationId,
      restaurantId: device.restaurantId ?? '',
      branchId: device.branchId,
      deviceId: deviceId,
    );
    final PosStoredPinSession? record;
    try {
      record = await ref.read(posSecureSessionStoreProvider).read(scope);
    } catch (_) {
      return PosOfflineRestoreResult.noRecord;
    }
    if (record == null) return PosOfflineRestoreResult.noRecord;
    if (record.deviceSessionId != deviceSessionId) {
      // A DIFFERENT pairing minted this record (re-pair always changes the
      // device session). It can never be valid again — destroy it.
      unawaited(
        ref.read(posSecureSessionStoreProvider).clear(scope).catchError((_) {}),
      );
      return PosOfflineRestoreResult.wrongPairing;
    }
    if (attemptedEmployeeProfileId != null &&
        attemptedEmployeeProfileId != record.employeeProfileId) {
      return PosOfflineRestoreResult.wrongEmployee;
    }
    if (!record.isValidAt(clock())) {
      return PosOfflineRestoreResult.expired;
    }
    // Restore the SAME established-state shape a live establish produces —
    // full pairing binding, expiry anchors, published operator identity —
    // marked restoredOffline with its hard validity end.
    _binding = PosPinSessionBinding(
      organizationId: device.organizationId,
      restaurantId: device.restaurantId,
      branchId: device.branchId,
      deviceId: deviceId,
      deviceSessionId: deviceSessionId,
    );
    // RF-118 anchors: the expiry window measures from the last PROVEN online
    // moment, never from the restore instant (a restore must not extend
    // anything a real establish would not have).
    _startedAt = record.lastOnlineVerify;
    _pausedAt = null;
    _setOfflineRestoreInfo(
      restored: true,
      validUntil: record.offlineValidUntil,
    );
    ref.read(posSignedInStaffNameProvider.notifier).set(record.displayName);
    ref
        .read(posSignedInEmployeeProfileIdProvider.notifier)
        .set(record.employeeProfileId);
    state = AsyncData(
      SyncSession(pinSessionId: record.sessionId, deviceId: deviceId),
    );
    return PosOfflineRestoreResult.restored;
  }

  /// [POS-OFFLINE-OPERATIONS-002] The stored record for [device]'s scope, or
  /// null — a READ-ONLY peek the PIN gate uses to explain an EXPIRED offline
  /// window honestly. Never restores, never deletes.
  Future<PosStoredPinSession?> peekStoredOfflineSession(
    DeviceContext device,
  ) async {
    final deviceId = device.deviceId;
    if (deviceId == null || deviceId.isEmpty) return null;
    try {
      return await ref
          .read(posSecureSessionStoreProvider)
          .read(
            PosSyncScope(
              organizationId: device.organizationId,
              restaurantId: device.restaurantId ?? '',
              branchId: device.branchId,
              deviceId: deviceId,
            ),
          );
    } catch (_) {
      return null;
    }
  }

  /// [POS-OFFLINE-OPERATIONS-002] Reconnect revalidation: a REAL authenticated
  /// server round-trip completed under the current session (the outbox saw a
  /// structured `sync_push` answer). Clears the restored-offline mark and —
  /// throttled to once per 5 minutes — advances the persisted
  /// `last_online_verify` anchor, so the 8h offline window measures from
  /// genuine proof, not from optimism.
  void noteOnlineVerified() {
    final session = state.valueOrNull;
    if (session == null) return;
    final now = clock();
    _setOfflineRestoreInfo(restored: false, validUntil: null);
    try {
      ref.read(posSessionReauthNoticeProvider.notifier).clear();
    } catch (_) {}
    final last = _lastVerifyPersistedAt;
    if (last != null && now.difference(last) < const Duration(minutes: 5)) {
      return; // write-churn throttle — the anchor moved recently enough.
    }
    final scope = _scopeOfBinding(_binding);
    if (scope == null) return;
    _lastVerifyPersistedAt = now;
    unawaited(() async {
      try {
        final store = ref.read(posSecureSessionStoreProvider);
        final existing = await store.read(scope);
        // Only the record of THIS live session may be re-anchored; a record
        // for some other session id proves nothing about this one.
        if (existing != null && existing.sessionId == session.pinSessionId) {
          await store.save(scope, existing.withOnlineVerify(now));
        }
      } catch (_) {
        // Contained — verification persistence is an enhancement.
      }
    }());
  }

  /// [POS-OFFLINE-OPERATIONS-002] (C8, test 14): the server refused the WHOLE
  /// `sync_push` batch with 42501 — the PIN session itself is invalid
  /// (revoked / expired server-side). Ends the session (which destroys the
  /// offline-continuity record: the server just proved it worthless) and
  /// raises the gate's re-auth notice. Queued entries are already AUTH_HOLD
  /// and stay exactly where they are. Idempotent: with no live session this
  /// is a no-op, so one failing batch signals the seam once.
  void handleServerAuthRefusal() {
    if (state.valueOrNull == null) return;
    try {
      ref.read(posSessionReauthNoticeProvider.notifier).set();
    } catch (_) {}
    endSession();
  }
}

/// [POS-OFFLINE-OPERATIONS-002] The typed outcome of an offline restore
/// attempt — the PIN gate switches on it to choose an honest notice.
enum PosOfflineRestoreResult {
  restored,
  noRecord,
  expired,
  wrongPairing,
  wrongEmployee,
  alreadySignedIn,
  unavailable,
}

/// [POS-OFFLINE-OPERATIONS-002] The REACTIVE mirror of the session
/// controller's restored-offline mark (+ its hard validity end), so the
/// offline session policy and the cart recompute the moment it changes —
/// the controller's own state object ([SyncSession]) deliberately cannot
/// carry it (shared-package type; additive fields need their own ticket).
class PosSessionOfflineRestoreInfo {
  const PosSessionOfflineRestoreInfo({
    required this.restoredOffline,
    this.validUntil,
  });

  static const PosSessionOfflineRestoreInfo none = PosSessionOfflineRestoreInfo(
    restoredOffline: false,
  );

  /// True while the current session was restored WITHOUT server proof.
  final bool restoredOffline;

  /// The hard end of the restored session's offline trust window; null when
  /// [restoredOffline] is false.
  final DateTime? validUntil;
}

class PosSessionOfflineRestoreInfoController
    extends Notifier<PosSessionOfflineRestoreInfo> {
  @override
  PosSessionOfflineRestoreInfo build() => PosSessionOfflineRestoreInfo.none;

  void publish({required bool restoredOffline, required DateTime? validUntil}) {
    state = restoredOffline
        ? PosSessionOfflineRestoreInfo(
            restoredOffline: true,
            validUntil: validUntil,
          )
        : PosSessionOfflineRestoreInfo.none;
  }
}

final posSessionOfflineRestoreInfoProvider =
    NotifierProvider<
      PosSessionOfflineRestoreInfoController,
      PosSessionOfflineRestoreInfo
    >(PosSessionOfflineRestoreInfoController.new);

/// [POS-OFFLINE-OPERATIONS-002] True after the server refused a whole batch
/// for auth reasons (the session died mid-shift) until the next successful
/// establish — the PIN gate shows its expired/sign-in-again notice for it.
class PosSessionReauthNotice extends Notifier<bool> {
  @override
  bool build() => false;

  void set() => state = true;

  void clear() => state = false;
}

final posSessionReauthNoticeProvider =
    NotifierProvider<PosSessionReauthNotice, bool>(PosSessionReauthNotice.new);

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

/// MENU-ORDER-001 (Codex #1): the STABLE authenticated worker id of the signed-in
/// POS operator — the server `employee_profile_id` (device-staff roster id), which
/// is the SAME for a worker across every PIN login, unlike the ephemeral
/// pinSessionId (a new one is minted per `start_pin_session`). Used to bind a
/// durable draft recovery to its owner so the SAME worker can reclaim it after an
/// app restart + re-login, while a different worker cannot. Identity id only — NO
/// PIN / hash / token / JWT. Set at sign-in, cleared on sign-out.
class PosSignedInEmployeeProfileId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) =>
      state = (id != null && id.trim().isNotEmpty) ? id.trim() : null;

  void clear() => state = null;
}

final posSignedInEmployeeProfileIdProvider =
    NotifierProvider<PosSignedInEmployeeProfileId, String?>(
      PosSignedInEmployeeProfileId.new,
    );

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
