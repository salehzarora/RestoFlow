import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// KITCHEN-MODE-001C3B1A2: whether [KitchenPosStatusReport.unresolvedLocalJobs]
/// is AUTHORITATIVE.
///
///  * [counted]  — the spool DB opened and the count is exact.
///  * [absent]   — no spool DB file; the count is proven 0 (nothing spooled).
///  * [unknown]  — the DB could not be opened/counted (or an old client); the
///    count is NON-authoritative and the future escape gate must never treat
///    it as empty.
///
/// INDEPENDENT of [KitchenPosStatusReport.secureSpoolAvailable] (printability):
/// a readable DB with a missing/corrupt key is still `counted`.
enum KitchenSpoolCountState {
  counted('counted'),
  absent('absent'),
  unknown('unknown');

  const KitchenSpoolCountState(this.wireName);

  final String wireName;
}

/// KITCHEN-MODE-001C3B1A/001C3B1A2 — device-token client for
/// `report_kitchen_pos_status`.
///
/// A CONFIGURATION-INDEPENDENT spool/status report: it carries only the
/// device's local spool health (usability + unresolved count + count
/// certainty) and the trusted server mode revision, so it stays fresh even
/// when NO kitchen printer is configured — the future safe `printer_only → kds`
/// escape gate needs an AUTHORITATIVE "unresolved_local_jobs = 0" statement
/// regardless of printer state. Compile-time closed; NEVER carries a printer
/// assignment, endpoint, fingerprint, payload, key, customer/order data,
/// notes, or money.
final class KitchenPosStatusReport {
  const KitchenPosStatusReport({
    required this.appBuild,
    required this.modeRevision,
    required this.secureSpoolAvailable,
    required this.unresolvedLocalJobs,
    required this.spoolCountState,
  });

  /// Short build identifier (server CHECK: 1..64 chars). Never an endpoint.
  final String appBuild;

  /// The SERVER-authoritative branch mode revision (never fabricated).
  final int modeRevision;

  final bool secureSpoolAvailable;

  /// Scope-specific durable spool count (0 when no spool exists). Authoritative
  /// only when [spoolCountState] is `counted` or `absent`.
  final int unresolvedLocalJobs;

  /// KITCHEN-MODE-001C3B1A2: whether the count above is authoritative. `absent`
  /// requires [unresolvedLocalJobs] == 0 (server-enforced).
  final KitchenSpoolCountState spoolCountState;
}

sealed class KitchenPosStatusResult {
  const KitchenPosStatusResult();
}

/// The server stored the status report (10-minute server-owned validity).
final class KitchenPosStatusAccepted extends KitchenPosStatusResult {
  const KitchenPosStatusAccepted();
}

/// The reported `mode_revision` no longer matches the branch — the response
/// carries the CURRENT server revision so the client can refetch/re-report.
final class KitchenPosStatusStaleModeRevision extends KitchenPosStatusResult {
  const KitchenPosStatusStaleModeRevision({required this.serverRevision});

  final int serverRevision;
}

/// The server rejected the request contract itself (a client bug).
enum KitchenPosStatusRejectionReason {
  invalidAppBuild('invalid_app_build'),
  invalidSpoolState('invalid_spool_state'),
  invalidUnresolvedCount('invalid_unresolved_count'),
  // KITCHEN-MODE-001C3B1A2: the count-state was not a closed value, or the
  // cross-field invariant (absent => 0) was violated.
  invalidSpoolCountState('invalid_spool_count_state');

  const KitchenPosStatusRejectionReason(this.wireName);

  final String wireName;
}

final class KitchenPosStatusRejected extends KitchenPosStatusResult {
  const KitchenPosStatusRejected(this.reason);

  final KitchenPosStatusRejectionReason reason;
}

/// invalid_session covers a missing credential, a revoked/expired session, and
/// a non-POS (KDS) device — the server never distinguishes them.
final class KitchenPosStatusInvalidSession extends KitchenPosStatusResult {
  const KitchenPosStatusInvalidSession();
}

final class KitchenPosStatusTransientFailure extends KitchenPosStatusResult {
  const KitchenPosStatusTransientFailure();
}

final class KitchenPosStatusServerFailure extends KitchenPosStatusResult {
  const KitchenPosStatusServerFailure();
}

final class KitchenPosStatusMalformedResponse extends KitchenPosStatusResult {
  const KitchenPosStatusMalformedResponse();
}

/// Device-token repository (house pattern: transport + secret store read per
/// request; the token never appears in logs, errors, or toString).
class SupabaseKitchenPosStatusRepository {
  SupabaseKitchenPosStatusRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _secretStore = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _secretStore;

  Future<KitchenPosStatusResult> report(KitchenPosStatusReport status) async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _secretStore.read();
    } on Exception {
      return const KitchenPosStatusInvalidSession();
    }
    if (cred == null) return const KitchenPosStatusInvalidSession();

    final Object? raw;
    try {
      // KITCHEN-MODE-001C3B1A2: the count-state-aware 7-arg signature. This
      // client NEVER falls back to the legacy 6-arg call — an old server
      // without the 7-arg overload fails closed (server failure), never a
      // silent downgrade of count certainty to unknown-pretending-success.
      raw = await _transport.invoke('report_kitchen_pos_status', {
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
        'p_app_build': status.appBuild,
        'p_mode_revision': status.modeRevision,
        'p_secure_spool_available': status.secureSpoolAvailable,
        'p_unresolved_local_jobs': status.unresolvedLocalJobs,
        'p_spool_count_state': status.spoolCountState.wireName,
      });
    } on SyncTransportException catch (e) {
      return switch (e.kind) {
        SyncTransportErrorKind.auth => const KitchenPosStatusInvalidSession(),
        SyncTransportErrorKind.transient =>
          const KitchenPosStatusTransientFailure(),
        _ => const KitchenPosStatusServerFailure(),
      };
    } on Exception {
      return const KitchenPosStatusTransientFailure();
    }

    if (raw is! Map) return const KitchenPosStatusMalformedResponse();
    final json = raw.map((k, v) => MapEntry(k.toString(), v));
    if (json['ok'] == true) return const KitchenPosStatusAccepted();
    final error = json['error'];
    if (error == 'invalid_session') {
      return const KitchenPosStatusInvalidSession();
    }
    if (error == 'stale_mode_revision') {
      final Object? server = json['mode_revision'];
      if (server is! int || server <= 0) {
        return const KitchenPosStatusMalformedResponse();
      }
      return KitchenPosStatusStaleModeRevision(serverRevision: server);
    }
    for (final reason in KitchenPosStatusRejectionReason.values) {
      if (error == reason.wireName) return KitchenPosStatusRejected(reason);
    }
    return const KitchenPosStatusMalformedResponse();
  }
}
