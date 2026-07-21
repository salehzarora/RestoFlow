import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// KITCHEN-MODE-001C3A — member (JWT) client for
/// `list_kitchen_print_dispatches`.
///
/// READ-ONLY observability over the kitchen dispatch ledger for the future
/// 001C3C possiblyPrinted review panel. The server projects SAFE SCALARS
/// only; this client models EXACTLY those fields — no payload, endpoint,
/// fingerprint, claim internals, customer data, or money is ever parsed or
/// stored. Closed filter vocabulary; bounded page (server clamp 1..50);
/// deterministic newest-first keyset pagination.
enum KitchenDispatchInspectionFilter {
  unresolved('unresolved'),
  possiblyPrinted('possibly_printed'),
  completed('completed'),
  superseded('superseded'),
  all('all');

  const KitchenDispatchInspectionFilter(this.wireName);

  final String wireName;
}

/// One safe ledger row (server field set, verbatim).
final class KitchenDispatchInspectionEntry {
  const KitchenDispatchInspectionEntry({
    required this.dispatchId,
    required this.dispatchType,
    required this.orderId,
    required this.createdAt,
    required this.claimed,
    required this.lastClientStatus,
    required this.lastErrorCode,
    required this.completedAt,
    required this.possiblyPrinted,
    required this.superseded,
  });

  final String dispatchId;

  /// `initial_order` / `service_round` / `void` (server CHECK-closed).
  final String dispatchType;

  final String orderId;

  final DateTime createdAt;

  final bool claimed;

  /// One of the five server statuses, or null before any acknowledgement.
  final String? lastClientStatus;

  /// CHECK-constrained safe code (`^[a-z0-9_.\-]{1,64}$`) — never raw text.
  final String? lastErrorCode;

  final DateTime? completedAt;

  /// True only for the active ambiguous hold (operator review required).
  final bool possiblyPrinted;

  final bool superseded;
}

/// Opaque deterministic pagination cursor.
final class KitchenDispatchInspectionCursor {
  const KitchenDispatchInspectionCursor({
    required this.createdAt,
    required this.id,
  });

  final DateTime createdAt;
  final String id;
}

sealed class KitchenDispatchInspectionResult {
  const KitchenDispatchInspectionResult();
}

final class KitchenDispatchInspectionPage
    extends KitchenDispatchInspectionResult {
  const KitchenDispatchInspectionPage({
    required this.entries,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<KitchenDispatchInspectionEntry> entries;
  final bool hasMore;
  final KitchenDispatchInspectionCursor? nextCursor;
}

/// Scope-leak-free denial: unknown branch OR insufficient membership.
final class KitchenDispatchInspectionNotFound
    extends KitchenDispatchInspectionResult {
  const KitchenDispatchInspectionNotFound();
}

/// The request contract itself was rejected (client bug — never retried
/// blindly): invalid filter, limit, or cursor.
final class KitchenDispatchInspectionInvalidRequest
    extends KitchenDispatchInspectionResult {
  const KitchenDispatchInspectionInvalidRequest();
}

final class KitchenDispatchInspectionUnauthorized
    extends KitchenDispatchInspectionResult {
  const KitchenDispatchInspectionUnauthorized();
}

final class KitchenDispatchInspectionTransientFailure
    extends KitchenDispatchInspectionResult {
  const KitchenDispatchInspectionTransientFailure();
}

final class KitchenDispatchInspectionServerFailure
    extends KitchenDispatchInspectionResult {
  const KitchenDispatchInspectionServerFailure();
}

final class KitchenDispatchInspectionMalformedResponse
    extends KitchenDispatchInspectionResult {
  const KitchenDispatchInspectionMalformedResponse();
}

/// Member JWT repository (authorization = the caller's authenticated session
/// + membership rank; there is no device token on this path).
class SupabaseKitchenDispatchInspectionRepository {
  SupabaseKitchenDispatchInspectionRepository({
    required SyncRpcTransport transport,
  }) : _transport = transport;

  final SyncRpcTransport _transport;

  Future<KitchenDispatchInspectionResult> list({
    required String organizationId,
    required String restaurantId,
    required String branchId,
    KitchenDispatchInspectionFilter filter =
        KitchenDispatchInspectionFilter.unresolved,
    int limit = 20,
    KitchenDispatchInspectionCursor? cursor,
  }) async {
    final Object? raw;
    try {
      raw = await _transport.invoke('list_kitchen_print_dispatches', {
        'p_organization_id': organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_status_filter': filter.wireName,
        'p_limit': limit,
        'p_cursor_created_at': cursor?.createdAt.toUtc().toIso8601String(),
        'p_cursor_id': cursor?.id,
      });
    } on SyncTransportException catch (e) {
      return switch (e.kind) {
        SyncTransportErrorKind.auth =>
          const KitchenDispatchInspectionUnauthorized(),
        SyncTransportErrorKind.transient =>
          const KitchenDispatchInspectionTransientFailure(),
        _ => const KitchenDispatchInspectionServerFailure(),
      };
    } on Exception {
      return const KitchenDispatchInspectionTransientFailure();
    }

    if (raw is! Map) return const KitchenDispatchInspectionMalformedResponse();
    final json = raw.map((k, v) => MapEntry(k.toString(), v));
    if (json['ok'] != true) {
      return switch (json['error']) {
        'not_found' => const KitchenDispatchInspectionNotFound(),
        'invalid_status_filter' ||
        'invalid_limit' ||
        'invalid_cursor' => const KitchenDispatchInspectionInvalidRequest(),
        _ => const KitchenDispatchInspectionMalformedResponse(),
      };
    }

    final Object? rows = json['dispatches'];
    if (rows is! List) {
      return const KitchenDispatchInspectionMalformedResponse();
    }
    final entries = <KitchenDispatchInspectionEntry>[];
    for (final row in rows) {
      if (row is! Map) {
        return const KitchenDispatchInspectionMalformedResponse();
      }
      final r = row.map((k, v) => MapEntry(k.toString(), v));
      final dispatchId = r['dispatch_id'];
      final dispatchType = r['dispatch_type'];
      final orderId = r['order_id'];
      final createdAtRaw = r['created_at'];
      final claimed = r['claimed'];
      final possiblyPrinted = r['possibly_printed'];
      final superseded = r['superseded'];
      if (dispatchId is! String ||
          dispatchType is! String ||
          orderId is! String ||
          createdAtRaw is! String ||
          claimed is! bool ||
          possiblyPrinted is! bool ||
          superseded is! bool) {
        return const KitchenDispatchInspectionMalformedResponse();
      }
      const dispatchTypes = {'initial_order', 'service_round', 'void'};
      if (!dispatchTypes.contains(dispatchType)) {
        return const KitchenDispatchInspectionMalformedResponse();
      }
      final DateTime createdAt;
      final DateTime? completedAt;
      try {
        createdAt = DateTime.parse(createdAtRaw);
        final completedRaw = r['completed_at'];
        completedAt = completedRaw is String
            ? DateTime.parse(completedRaw)
            : null;
      } on FormatException {
        return const KitchenDispatchInspectionMalformedResponse();
      }
      entries.add(
        KitchenDispatchInspectionEntry(
          dispatchId: dispatchId,
          dispatchType: dispatchType,
          orderId: orderId,
          createdAt: createdAt,
          claimed: claimed,
          lastClientStatus: r['last_client_status'] is String
              ? r['last_client_status'] as String
              : null,
          lastErrorCode: r['last_error_code'] is String
              ? r['last_error_code'] as String
              : null,
          completedAt: completedAt,
          possiblyPrinted: possiblyPrinted,
          superseded: superseded,
        ),
      );
    }

    final hasMore = json['has_more'] == true;
    KitchenDispatchInspectionCursor? nextCursor;
    final Object? cursorRaw = json['next_cursor'];
    if (cursorRaw is Map) {
      final c = cursorRaw.map((k, v) => MapEntry(k.toString(), v));
      final createdAtRaw = c['created_at'];
      final id = c['id'];
      if (createdAtRaw is! String || id is! String) {
        return const KitchenDispatchInspectionMalformedResponse();
      }
      try {
        nextCursor = KitchenDispatchInspectionCursor(
          createdAt: DateTime.parse(createdAtRaw),
          id: id,
        );
      } on FormatException {
        return const KitchenDispatchInspectionMalformedResponse();
      }
    }
    if (hasMore && nextCursor == null) {
      return const KitchenDispatchInspectionMalformedResponse();
    }
    return KitchenDispatchInspectionPage(
      entries: entries,
      hasMore: hasMore,
      nextCursor: nextCursor,
    );
  }
}
