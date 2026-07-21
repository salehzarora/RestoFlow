import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// KITCHEN-MODE-001C2B/001C3A — device-token client for
/// `get_device_kitchen_workflow_mode`.
///
/// 001C3A closes LOCKED DECISION D1's client half: the server envelope now
/// carries an ADDITIVE `mode_revision` (`branches.kitchen_workflow_mode_revision`,
/// server-authoritative, CHECK > 0). The parsing contract:
///
///  * `kds` + valid positive integer revision  -> [KitchenModeVerifiedKds]
///    WITH the revision (readiness-report eligible);
///  * `kds` + ABSENT revision key (old server) -> [KitchenModeVerifiedKds]
///    with a null revision — normal KDS operation is unchanged, but the
///    result is NOT eligible to produce a readiness report;
///  * `printer_only` + valid positive revision -> [KitchenModePrinterOnlyWithRevision]
///    (the trusted result — parseable ONLY when the server branch already is
///    printer_only; no supported workflow can put a branch there yet);
///  * `printer_only` + ABSENT revision key     -> [KitchenModeRevisionUnavailable]
///    (fail closed, old-server compatibility);
///  * a PRESENT-but-invalid revision (non-integer, zero, negative) in EITHER
///    mode -> [KitchenModeMalformedResponse] — a revision is NEVER fabricated,
///    NEVER defaulted to 1, and NEVER reused from another scope.
///
/// There is NO silent-kds fallback: every failure is its own typed result.
sealed class KitchenModeResult {
  const KitchenModeResult();
}

/// The server verified this device's branch is in `kds` mode.
final class KitchenModeVerifiedKds extends KitchenModeResult {
  const KitchenModeVerifiedKds({required this.verifiedAt, this.revision});

  final DateTime verifiedAt;

  /// The server's `kitchen_workflow_mode_revision` (positive), or null when
  /// the server predates 001C3A. A null revision keeps normal KDS behavior
  /// but is NOT eligible to produce a readiness report.
  final int? revision;
}

/// The server verified `printer_only` AND a trusted mode revision is known.
/// Production-parseable since 001C3A — but ONLY when the server branch is
/// already printer_only, which no supported workflow can produce until the
/// guarded 001C3B setter ships and is explicitly activated.
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
    // 001C3A: the additive server revision. ABSENT is legal (old server);
    // PRESENT-but-invalid is a contract violation — malformed, never
    // fabricated, never defaulted, never clamped.
    final hasRevisionKey = json.containsKey('mode_revision');
    final Object? rawRevision = json['mode_revision'];
    final int? revision = rawRevision is int && rawRevision > 0
        ? rawRevision
        : null;
    if (hasRevisionKey && revision == null) {
      return const KitchenModeMalformedResponse();
    }
    return switch (json['kitchen_workflow_mode']) {
      'kds' => KitchenModeVerifiedKds(verifiedAt: _now(), revision: revision),
      // D1 fail-closed half preserved: printer_only without a TRUSTED
      // server revision must not enable work.
      'printer_only' =>
        revision == null
            ? const KitchenModeRevisionUnavailable()
            : KitchenModePrinterOnlyWithRevision(
                revision: revision,
                verifiedAt: _now(),
              ),
      _ => const KitchenModeMalformedResponse(),
    };
  }
}
