import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

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
/// SECURITY: [pinVerifier] is the RF-051 INTERIM verifier seam (the backend
/// currently checks it by plaintext equality - NOT production crypto; a salted
/// credential scheme is deferred). It is forwarded to the RPC, never logged, and
/// must be passed at run time only (never committed to source).
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
  @override
  FutureOr<SyncSession?> build() {
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
      (started) => SyncSession(
        pinSessionId: started.pinSessionId,
        deviceId: config.deviceId,
      ),
      // Wrong PIN / locked-or-precondition (42501) / transient: fail closed.
      (failure) => null,
    );
  }
}

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
