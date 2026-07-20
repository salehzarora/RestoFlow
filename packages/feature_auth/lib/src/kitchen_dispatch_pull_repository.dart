import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// KITCHEN-MODE-001C2B — device-token client for
/// `pull_kitchen_print_dispatches` (the atomic server claim-and-pull).
///
/// The cursor is the server's FULL ordering tuple (`created_at`,
/// `type_rank`, `id`) forwarded verbatim — never partially. There is NO
/// readiness bypass of any kind here: the server independently refuses
/// claims without a fresh activation-capable readiness report
/// (`readiness_required`), which no production client files until 001C3.

/// One server dispatch row, strictly decoded (closed dispatch types; the
/// money-free payload map is carried TRANSIENTLY for the closed local
/// decoder — it is never persisted raw).
final class PulledKitchenDispatch {
  const PulledKitchenDispatch({
    required this.dispatchId,
    required this.dispatchType,
    required this.orderId,
    this.serviceRoundId,
    required this.payloadVersion,
    required this.moneyFreePayload,
    required this.createdAt,
    this.claimExpiresAt,
  });

  final String dispatchId;

  /// `initial_order` / `service_round` / `void` — closed on parse.
  final String dispatchType;
  final String orderId;
  final String? serviceRoundId;
  final int payloadVersion;
  final Map<String, Object?> moneyFreePayload;
  final String createdAt;
  final String? claimExpiresAt;
}

/// The full three-field keyset cursor (all-or-nothing on the server).
final class KitchenDispatchCursor {
  const KitchenDispatchCursor({
    required this.createdAt,
    required this.typeRank,
    required this.id,
  });

  final String createdAt;
  final int typeRank;
  final String id;
}

final class KitchenDispatchPullPage {
  const KitchenDispatchPullPage({
    required this.dispatches,
    required this.hasMore,
    this.nextCursor,
  });

  final List<PulledKitchenDispatch> dispatches;
  final bool hasMore;
  final KitchenDispatchCursor? nextCursor;
}

/// Closed pull outcomes (typed; the session token never appears anywhere).
sealed class KitchenDispatchPullResult {
  const KitchenDispatchPullResult();
}

final class KitchenDispatchPullSuccess extends KitchenDispatchPullResult {
  const KitchenDispatchPullSuccess(this.page);

  final KitchenDispatchPullPage page;
}

enum KitchenDispatchPullError {
  invalidSession,
  branchNotPrinterOnly,
  readinessRequired,
  invalidCursor,
  invalidLimit,
  transientFailure,
  permissionDenied,
  malformedResponse,
  serverFailure,
}

final class KitchenDispatchPullFailure extends KitchenDispatchPullResult {
  const KitchenDispatchPullFailure(this.error);

  final KitchenDispatchPullError error;
}

const Set<String> _closedDispatchTypes = {
  'initial_order',
  'service_round',
  'void',
};

/// Device-token repository (house pattern; token read per request).
class SupabaseKitchenDispatchPullRepository {
  SupabaseKitchenDispatchPullRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _secretStore = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _secretStore;

  Future<KitchenDispatchPullResult> pull({
    int limit = 20,
    KitchenDispatchCursor? cursor,
  }) async {
    if (limit < 1 || limit > 50) {
      return const KitchenDispatchPullFailure(
        KitchenDispatchPullError.invalidLimit,
      );
    }
    final DeviceSessionCredential? cred;
    try {
      cred = await _secretStore.read();
    } on Exception {
      return const KitchenDispatchPullFailure(
        KitchenDispatchPullError.invalidSession,
      );
    }
    if (cred == null) {
      return const KitchenDispatchPullFailure(
        KitchenDispatchPullError.invalidSession,
      );
    }

    final Object? raw;
    try {
      raw = await _transport.invoke('pull_kitchen_print_dispatches', {
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
        'p_limit': limit,
        // Full tuple, forwarded verbatim (all-or-nothing).
        'p_cursor_created_at': cursor?.createdAt,
        'p_cursor_id': cursor?.id,
        'p_cursor_type_rank': cursor?.typeRank,
      });
    } on SyncTransportException catch (e) {
      return KitchenDispatchPullFailure(switch (e.kind) {
        SyncTransportErrorKind.auth => KitchenDispatchPullError.invalidSession,
        SyncTransportErrorKind.transient =>
          KitchenDispatchPullError.transientFailure,
        _ => KitchenDispatchPullError.serverFailure,
      });
    } on Exception {
      return const KitchenDispatchPullFailure(
        KitchenDispatchPullError.transientFailure,
      );
    }

    if (raw is! Map) {
      return const KitchenDispatchPullFailure(
        KitchenDispatchPullError.malformedResponse,
      );
    }
    final json = raw.map((k, v) => MapEntry(k.toString(), v));
    if (json['ok'] != true) {
      return KitchenDispatchPullFailure(switch (json['error']) {
        'invalid_session' => KitchenDispatchPullError.invalidSession,
        'branch_not_printer_only' =>
          KitchenDispatchPullError.branchNotPrinterOnly,
        'readiness_required' => KitchenDispatchPullError.readinessRequired,
        'invalid_cursor' => KitchenDispatchPullError.invalidCursor,
        'invalid_limit' => KitchenDispatchPullError.invalidLimit,
        _ => KitchenDispatchPullError.serverFailure,
      });
    }

    try {
      final rawDispatches = json['dispatches'];
      if (rawDispatches is! List) throw const FormatException();
      final dispatches = <PulledKitchenDispatch>[];
      for (final entry in rawDispatches) {
        if (entry is! Map) throw const FormatException();
        final row = entry.map((k, v) => MapEntry(k.toString(), v));
        final type = row['dispatch_type'];
        if (type is! String || !_closedDispatchTypes.contains(type)) {
          throw const FormatException();
        }
        final payload = row['payload'];
        if (payload is! Map) throw const FormatException();
        final payloadVersion = row['payload_version'];
        if (payloadVersion is! int || payloadVersion <= 0) {
          throw const FormatException();
        }
        dispatches.add(
          PulledKitchenDispatch(
            dispatchId: _requireString(row, 'id'),
            dispatchType: type,
            orderId: _requireString(row, 'order_id'),
            serviceRoundId: _optionalString(row, 'service_round_id'),
            payloadVersion: payloadVersion,
            moneyFreePayload: payload.map((k, v) => MapEntry(k.toString(), v)),
            createdAt: _requireString(row, 'created_at'),
            claimExpiresAt: _optionalString(row, 'claim_expires_at'),
          ),
        );
      }
      final hasMore = json['has_more'] == true;
      final rawCursor = json['next_cursor'];
      KitchenDispatchCursor? nextCursor;
      if (rawCursor is Map) {
        final c = rawCursor.map((k, v) => MapEntry(k.toString(), v));
        final rank = c['type_rank'];
        if (rank is! int) throw const FormatException();
        nextCursor = KitchenDispatchCursor(
          createdAt: _requireString(c, 'created_at'),
          typeRank: rank,
          id: _requireString(c, 'id'),
        );
      }
      // A contradictory page (more promised, no cursor) is malformed.
      if (hasMore && nextCursor == null) throw const FormatException();
      return KitchenDispatchPullSuccess(
        KitchenDispatchPullPage(
          dispatches: dispatches,
          hasMore: hasMore,
          nextCursor: nextCursor,
        ),
      );
    } on FormatException {
      return const KitchenDispatchPullFailure(
        KitchenDispatchPullError.malformedResponse,
      );
    }
  }

  static String _requireString(Map<String, Object?> row, String key) {
    final v = row[key];
    if (v is String && v.isNotEmpty) return v;
    throw const FormatException();
  }

  static String? _optionalString(Map<String, Object?> row, String key) {
    final v = row[key];
    if (v == null) return null;
    if (v is String && v.isNotEmpty) return v;
    throw const FormatException();
  }
}
