import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// KITCHEN-MODE-001C3A — device-token client for
/// `report_kitchen_printer_readiness`.
///
/// COMPILE-TIME CLOSED: the capability token and printer purpose are PINNED
/// constants (never caller strings), the transport kind and paper width are
/// closed enums, and the request is built from a typed evidence value — no
/// arbitrary map ever reaches the wire from a production call site.
///
/// PRIVACY CONTRACT (server-enforced twice over — the table has no columns
/// for any of these): the request NEVER carries a host, port, Bluetooth
/// address, endpoint label, payload, key/ciphertext, customer data, notes,
/// money, or raw exception text. The printer is identified ONLY by the
/// existing non-secret SHA-256 routing fingerprint (16..128 lowercase hex).
enum KitchenReadinessTransportKind {
  network('network'),
  bluetooth('bluetooth');

  const KitchenReadinessTransportKind(this.wireName);

  final String wireName;
}

enum KitchenReadinessPaperWidth {
  mm58('58mm'),
  mm80('80mm');

  const KitchenReadinessPaperWidth(this.wireName);

  final String wireName;
}

/// The typed readiness evidence a POS files. Endpoint-free by construction.
final class KitchenReadinessReport {
  const KitchenReadinessReport({
    required this.appBuild,
    required this.transportKind,
    required this.paperWidth,
    required this.printerFingerprint,
    required this.secureSpoolAvailable,
    required this.unresolvedLocalJobs,
    required this.modeRevision,
  });

  /// Short build identifier (server CHECK: 1..64 chars). Never an endpoint.
  final String appBuild;

  final KitchenReadinessTransportKind transportKind;

  final KitchenReadinessPaperWidth paperWidth;

  /// The existing NON-SECRET SHA-256 routing fingerprint (lowercase hex).
  final String printerFingerprint;

  final bool secureSpoolAvailable;

  /// Scope-specific durable spool count (0 when no spool exists).
  final int unresolvedLocalJobs;

  /// The SERVER-authoritative branch mode revision (from the trusted mode
  /// snapshot — never fabricated locally).
  final int modeRevision;
}

sealed class KitchenReadinessResult {
  const KitchenReadinessResult();
}

/// The server stored the report. `activationReady` mirrors the server's
/// qualifying evaluation (80mm + secure spool); the report itself expires
/// server-side ~10 minutes after acceptance.
final class KitchenReadinessAccepted extends KitchenReadinessResult {
  const KitchenReadinessAccepted({required this.activationReady});

  final bool activationReady;
}

/// The reported `mode_revision` no longer matches the branch — the response
/// carries the CURRENT server revision so the client can refetch/re-report.
final class KitchenReadinessStaleModeRevision extends KitchenReadinessResult {
  const KitchenReadinessStaleModeRevision({required this.serverRevision});

  /// The authoritative `branches.kitchen_workflow_mode_revision` (positive).
  final int serverRevision;
}

/// The server rejected the request contract itself (a client bug — never
/// retried blindly). Closed reasons mapping the server's typed errors.
enum KitchenReadinessRejectionReason {
  unsupportedCapability('unsupported_capability'),
  unsupportedPurpose('unsupported_purpose'),
  unsupportedTransport('unsupported_transport'),
  unsupportedPaperWidth('unsupported_paper_width'),
  invalidAppBuild('invalid_app_build'),
  invalidFingerprint('invalid_fingerprint'),
  invalidSpoolState('invalid_spool_state'),
  invalidUnresolvedCount('invalid_unresolved_count');

  const KitchenReadinessRejectionReason(this.wireName);

  final String wireName;
}

final class KitchenReadinessRejected extends KitchenReadinessResult {
  const KitchenReadinessRejected(this.reason);

  final KitchenReadinessRejectionReason reason;
}

final class KitchenReadinessInvalidSession extends KitchenReadinessResult {
  const KitchenReadinessInvalidSession();
}

final class KitchenReadinessTransientFailure extends KitchenReadinessResult {
  const KitchenReadinessTransientFailure();
}

final class KitchenReadinessServerFailure extends KitchenReadinessResult {
  const KitchenReadinessServerFailure();
}

final class KitchenReadinessMalformedResponse extends KitchenReadinessResult {
  const KitchenReadinessMalformedResponse();
}

/// Device-token repository (house pattern: transport + secret store read per
/// request; the token never appears in logs, errors, or toString).
class SupabaseKitchenReadinessRepository {
  SupabaseKitchenReadinessRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _secretStore = secretStore;

  /// PINNED capability token — the ONLY capability this client can claim.
  static const String capability = 'kitchen_printer_only_v1';

  /// PINNED printer purpose.
  static const String printerPurpose = 'kitchen_ticket';

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _secretStore;

  Future<KitchenReadinessResult> report(KitchenReadinessReport evidence) async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _secretStore.read();
    } on Exception {
      return const KitchenReadinessInvalidSession();
    }
    if (cred == null) return const KitchenReadinessInvalidSession();

    final Object? raw;
    try {
      raw = await _transport.invoke('report_kitchen_printer_readiness', {
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
        'p_capability': capability,
        'p_app_build': evidence.appBuild,
        'p_printer_purpose': printerPurpose,
        'p_transport_kind': evidence.transportKind.wireName,
        'p_paper_width': evidence.paperWidth.wireName,
        'p_printer_fingerprint': evidence.printerFingerprint,
        'p_secure_spool_available': evidence.secureSpoolAvailable,
        'p_unresolved_local_jobs': evidence.unresolvedLocalJobs,
        'p_mode_revision': evidence.modeRevision,
      });
    } on SyncTransportException catch (e) {
      return switch (e.kind) {
        SyncTransportErrorKind.auth => const KitchenReadinessInvalidSession(),
        SyncTransportErrorKind.transient =>
          const KitchenReadinessTransientFailure(),
        _ => const KitchenReadinessServerFailure(),
      };
    } on Exception {
      return const KitchenReadinessTransientFailure();
    }

    if (raw is! Map) return const KitchenReadinessMalformedResponse();
    final json = raw.map((k, v) => MapEntry(k.toString(), v));
    if (json['ok'] == true) {
      final Object? ready = json['activation_ready'];
      if (ready is! bool) return const KitchenReadinessMalformedResponse();
      return KitchenReadinessAccepted(activationReady: ready);
    }
    final error = json['error'];
    if (error == 'invalid_session') {
      return const KitchenReadinessInvalidSession();
    }
    if (error == 'stale_mode_revision') {
      // The ONLY error carrying the authoritative revision.
      final Object? server = json['mode_revision'];
      if (server is! int || server <= 0) {
        return const KitchenReadinessMalformedResponse();
      }
      return KitchenReadinessStaleModeRevision(serverRevision: server);
    }
    for (final reason in KitchenReadinessRejectionReason.values) {
      if (error == reason.wireName) return KitchenReadinessRejected(reason);
    }
    return const KitchenReadinessMalformedResponse();
  }
}
