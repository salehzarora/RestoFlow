import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// KITCHEN-MODE-001C2B — device-token client for
/// `acknowledge_kitchen_print_dispatch`.
///
/// COMPILE-TIME CLOSED: 001C2B may acknowledge ONLY `imported` and
/// `blocked_configuration` — the transport/ambiguity statuses
/// (`transport_accepted`, `possibly_printed`, `failed_retryable`) do not
/// exist in this API and arrive with the 001C2C worker orchestration.
enum KitchenImportAckStatus {
  imported('imported'),
  blockedConfiguration('blocked_configuration');

  const KitchenImportAckStatus(this.wireName);

  final String wireName;
}

/// TERMINAL server verdicts: the server refused ownership/state permanently —
/// retries must STOP and the local job stays non-runnable (its encrypted
/// content and history are preserved).
enum KitchenAckTerminalCode {
  notClaimOwner('not_claim_owner'),
  conflict('conflict'),
  notFound('not_found'),
  ambiguousPrintHold('ambiguous_print_hold');

  const KitchenAckTerminalCode(this.wireName);

  final String wireName;
}

sealed class KitchenAckResult {
  const KitchenAckResult();
}

/// The server recorded the acknowledgement (idempotent replays included).
final class KitchenAckAccepted extends KitchenAckResult {
  const KitchenAckAccepted({required this.idempotencyReplay});

  final bool idempotencyReplay;
}

final class KitchenAckTerminal extends KitchenAckResult {
  const KitchenAckTerminal(this.code);

  final KitchenAckTerminalCode code;
}

final class KitchenAckInvalidSession extends KitchenAckResult {
  const KitchenAckInvalidSession();
}

final class KitchenAckTransientFailure extends KitchenAckResult {
  const KitchenAckTransientFailure();
}

final class KitchenAckServerFailure extends KitchenAckResult {
  const KitchenAckServerFailure();
}

final class KitchenAckMalformedResponse extends KitchenAckResult {
  const KitchenAckMalformedResponse();
}

/// Device-token repository (house pattern; token read per request; no raw
/// exception text, endpoint, payload, or money ever leaves this boundary).
class SupabaseKitchenDispatchAckRepository {
  SupabaseKitchenDispatchAckRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _secretStore = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _secretStore;

  Future<KitchenAckResult> acknowledge({
    required String dispatchId,
    required KitchenImportAckStatus status,
    String? errorCode,
  }) async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _secretStore.read();
    } on Exception {
      return const KitchenAckInvalidSession();
    }
    if (cred == null) return const KitchenAckInvalidSession();

    final Object? raw;
    try {
      raw = await _transport.invoke('acknowledge_kitchen_print_dispatch', {
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
        'p_dispatch_id': dispatchId,
        'p_client_status': status.wireName,
        'p_error_code': errorCode,
      });
    } on SyncTransportException catch (e) {
      return switch (e.kind) {
        SyncTransportErrorKind.auth => const KitchenAckInvalidSession(),
        SyncTransportErrorKind.transient => const KitchenAckTransientFailure(),
        _ => const KitchenAckServerFailure(),
      };
    } on Exception {
      return const KitchenAckTransientFailure();
    }

    if (raw is! Map) return const KitchenAckMalformedResponse();
    final json = raw.map((k, v) => MapEntry(k.toString(), v));
    if (json['ok'] == true) {
      return KitchenAckAccepted(
        idempotencyReplay: json['idempotency_replay'] == true,
      );
    }
    return switch (json['error']) {
      'invalid_session' => const KitchenAckInvalidSession(),
      'not_claim_owner' => const KitchenAckTerminal(
        KitchenAckTerminalCode.notClaimOwner,
      ),
      'conflict' => const KitchenAckTerminal(KitchenAckTerminalCode.conflict),
      'not_found' => const KitchenAckTerminal(KitchenAckTerminalCode.notFound),
      'ambiguous_print_hold' => const KitchenAckTerminal(
        KitchenAckTerminalCode.ambiguousPrintHold,
      ),
      _ => const KitchenAckServerFailure(),
    };
  }
}
