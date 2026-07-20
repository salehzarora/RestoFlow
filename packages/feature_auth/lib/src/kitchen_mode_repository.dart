import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// KITCHEN-MODE-001C2B — device-token client for
/// `get_device_kitchen_workflow_mode`.
///
/// LOCKED DECISION D1: the current server envelope carries NO mode revision
/// (`{ok, entity, kitchen_workflow_mode, server_ts}` only), and printer-only
/// importing must never run without a TRUSTED non-null revision. Therefore
/// this production repository can yield [KitchenModeVerifiedKds] or
/// [KitchenModeRevisionUnavailable] — it can NEVER fabricate
/// [KitchenModePrinterOnlyWithRevision] (no fake revision, no default `1`).
/// The additive getter-envelope extension belongs to 001C3; until then,
/// production dispatch importing is structurally impossible (in addition to
/// the server-side readiness gate). Tests may construct the revision-bearing
/// result directly to drive coordinators.
///
/// There is NO silent-kds fallback: every failure is its own typed result.
sealed class KitchenModeResult {
  const KitchenModeResult();
}

/// The server verified this device's branch is in `kds` mode.
final class KitchenModeVerifiedKds extends KitchenModeResult {
  const KitchenModeVerifiedKds({required this.verifiedAt});

  final DateTime verifiedAt;
}

/// The server verified `printer_only` AND a trusted mode revision is known.
/// (Never produced by the production repository in 001C2B — see D1.)
final class KitchenModePrinterOnlyWithRevision extends KitchenModeResult {
  const KitchenModePrinterOnlyWithRevision({
    required this.revision,
    required this.verifiedAt,
  });

  final int revision;
  final DateTime verifiedAt;
}

/// `printer_only` was reported but NO trusted revision exists — printer-only
/// work stays disabled (fail closed).
final class KitchenModeRevisionUnavailable extends KitchenModeResult {
  const KitchenModeRevisionUnavailable();
}

final class KitchenModeInvalidSession extends KitchenModeResult {
  const KitchenModeInvalidSession();
}

final class KitchenModeTransientFailure extends KitchenModeResult {
  const KitchenModeTransientFailure();
}

final class KitchenModeServerFailure extends KitchenModeResult {
  const KitchenModeServerFailure();
}

final class KitchenModeMalformedResponse extends KitchenModeResult {
  const KitchenModeMalformedResponse();
}

/// Device-token repository (the house pattern: transport + secret store read
/// per request; the token never appears in logs or errors).
class SupabaseDeviceKitchenModeRepository {
  SupabaseDeviceKitchenModeRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
    DateTime Function()? now,
  }) : _transport = transport,
       _secretStore = secretStore,
       _now = now ?? DateTime.now;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _secretStore;
  final DateTime Function() _now;

  Future<KitchenModeResult> fetchMode() async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _secretStore.read();
    } on Exception {
      return const KitchenModeInvalidSession();
    }
    if (cred == null) return const KitchenModeInvalidSession();

    final Object? raw;
    try {
      raw = await _transport.invoke('get_device_kitchen_workflow_mode', {
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
      });
    } on SyncTransportException catch (e) {
      return switch (e.kind) {
        SyncTransportErrorKind.auth => const KitchenModeInvalidSession(),
        SyncTransportErrorKind.transient => const KitchenModeTransientFailure(),
        _ => const KitchenModeServerFailure(),
      };
    } on Exception {
      return const KitchenModeTransientFailure();
    }

    if (raw is! Map) return const KitchenModeMalformedResponse();
    final json = raw.map((k, v) => MapEntry(k.toString(), v));
    if (json['ok'] != true) {
      // The getter's only typed error is invalid_session (fail closed).
      return const KitchenModeInvalidSession();
    }
    return switch (json['kitchen_workflow_mode']) {
      'kds' => KitchenModeVerifiedKds(verifiedAt: _now()),
      // D1: printer_only WITHOUT a trusted revision must not enable work.
      'printer_only' => const KitchenModeRevisionUnavailable(),
      _ => const KitchenModeMalformedResponse(),
    };
  }
}
