import 'dart:math';

import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'auth_failure.dart';

/// A successfully started PIN session (`public.start_pin_session` returned a
/// bare uuid, RF-123).
class PinSessionStarted {
  const PinSessionStarted({
    required this.pinSessionId,
    required this.localOperationId,
  });

  /// The server-issued PIN session id (a bare uuid).
  final String pinSessionId;

  /// The idempotency key used for this attempt (D-022), echoed for replay/debug.
  final String localOperationId;
}

/// Calls `public.start_pin_session(...)` (RF-123) via the injected
/// [SyncRpcTransport].
///
/// STAGE 1 = a typed SERVICE METHOD only. There is NO PIN-entry UI, NO device
/// provisioning, and NO employee picker here. The caller supplies the
/// server-minted `device_session_id` + `employee_profile_id` (device
/// provisioning is deferred - no client-reachable RPC mints them yet) and an
/// OPAQUE verifier (the RF-051 interim seam - NOT a plaintext PIN). The verifier
/// is forwarded to the RPC and is NEVER logged.
class PinSessionService {
  PinSessionService(
    this._transport, {
    String Function()? generateLocalOperationId,
  }) : _generateLocalOperationId =
           generateLocalOperationId ?? _defaultLocalOperationId;

  final SyncRpcTransport _transport;
  final String Function() _generateLocalOperationId;

  /// Wraps `start_pin_session`:
  /// - a bare uuid -> [PinSessionStarted];
  /// - NULL (wrong verifier) -> [AuthWrongPinFailure];
  /// - SQLSTATE 42501 (locked / structural / precondition) ->
  ///   [AuthLockedOrPreconditionFailure];
  /// - transient transport error -> [AuthNetworkFailure].
  ///
  /// [localOperationId] is generated (uuid v4) when not supplied (D-022 = device
  /// + local_operation_id; the server replays the same session id only after
  /// full validation + verifier success).
  Future<Result<PinSessionStarted, AuthFailure>> startPinSession({
    required String deviceSessionId,
    required String employeeProfileId,
    required String pinVerifier,
    String? localOperationId,
  }) async {
    final operationId = localOperationId ?? _generateLocalOperationId();
    final Object? raw;
    try {
      raw = await _transport.invoke('start_pin_session', <String, dynamic>{
        'p_device_session_id': deviceSessionId,
        'p_employee_profile_id': employeeProfileId,
        'p_pin_verifier': pinVerifier, // opaque verifier; never logged
        'p_local_operation_id': operationId,
      });
    } on SyncTransportException catch (e) {
      return Failure(switch (e.kind) {
        // 42501 from start_pin_session = locked / structural / precondition
        // (NOT the same as get_my_context's auth-denied 42501).
        SyncTransportErrorKind.auth => const AuthLockedOrPreconditionFailure(),
        SyncTransportErrorKind.transient => const AuthNetworkFailure(),
        SyncTransportErrorKind.server => const AuthUnknownFailure(
          'server error',
        ),
        SyncTransportErrorKind.unknown => const AuthUnknownFailure(),
      });
    } catch (_) {
      return const Failure(
        AuthNetworkFailure('start_pin_session transport error'),
      );
    }
    if (raw == null) {
      // The RPC returns NULL (no row, no error) for a wrong verifier.
      return const Failure(AuthWrongPinFailure());
    }
    if (raw is String && raw.isNotEmpty) {
      return Success(
        PinSessionStarted(pinSessionId: raw, localOperationId: operationId),
      );
    }
    return const Failure(
      AuthInvalidResponseFailure('unexpected start_pin_session result'),
    );
  }
}

/// Default idempotency key: an RFC-4122 v4 uuid from a CSPRNG. Injectable, so
/// tests can supply a deterministic generator.
String _defaultLocalOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  String hex(int index) => bytes[index].toRadixString(16).padLeft(2, '0');
  return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
      '${hex(4)}${hex(5)}-'
      '${hex(6)}${hex(7)}-'
      '${hex(8)}${hex(9)}-'
      '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
}
