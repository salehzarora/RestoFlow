import 'sync_cursor.dart';

/// One paged entity result inside `changes` (RF-063): `{ rows, next_cursor,
/// has_more }` exactly as `app.sync_pull` returns it.
///
/// `rows` are kept as raw JSON maps — this package does not model business
/// entities (it must not depend on money fields; mapping to view models is the
/// `feature_kitchen` concern, approved decision A4). Tombstoned rows arrive
/// inline (`deleted_at` non-null, RF-057 A9) and are passed through untouched.
class SyncPullEntityPage {
  const SyncPullEntityPage({
    required this.rows,
    required this.nextCursor,
    required this.hasMore,
  });

  /// The changed rows (raw JSON), including inline tombstones.
  final List<Map<String, dynamic>> rows;

  /// The cursor to send next for this entity, or null when the server returned
  /// no rows (nothing to advance past).
  final SyncCursor? nextCursor;

  /// Whether more rows remain past this page (drain by re-pulling).
  final bool hasMore;

  static SyncPullEntityPage fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    final rows = <Map<String, dynamic>>[];
    if (rawRows is List) {
      for (final r in rawRows) {
        if (r is Map) {
          rows.add(r.map((k, v) => MapEntry(k.toString(), v)));
        } else {
          throw const FormatException('sync_pull: row is not an object');
        }
      }
    } else {
      throw const FormatException('sync_pull: rows is not an array');
    }
    final nextCursor = SyncCursor.fromJson(json['next_cursor']);
    final hasMore = json['has_more'] == true;
    // The RF-057 server guarantees has_more=true implies a valid next_cursor
    // (next_cursor is null only when zero rows, where has_more is false). Reject
    // the contradictory shape so a malformed page becomes InvalidResponseFailure
    // instead of an unadvanceable cursor the coordinator would re-pull (A5).
    if (hasMore && nextCursor == null) {
      throw const FormatException(
        'sync_pull: has_more is true but next_cursor is null/invalid',
      );
    }
    return SyncPullEntityPage(
      rows: rows,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }
}

/// One row of the current-device operation-status feed (RF-063), projecting the
/// status/conflict fields `app.sync_pull` exposes (raw `payload` is excluded
/// server-side, RF-057 A4). Money is never part of this projection.
class SyncOperationStatus {
  const SyncOperationStatus({
    required this.id,
    required this.localOperationId,
    required this.operationType,
    required this.status,
    required this.targetEntity,
    required this.targetId,
    required this.lastErrorCode,
    required this.rejectionReason,
    required this.retryCount,
    required this.updatedAt,
  });

  final String? id;
  final String? localOperationId;
  final String? operationType;
  final String? status;
  final String? targetEntity;
  final String? targetId;
  final String? lastErrorCode;
  final String? rejectionReason;
  final int? retryCount;
  final String? updatedAt;

  static String? _str(Object? v) => v is String ? v : (v == null ? null : '$v');

  static SyncOperationStatus fromJson(Map<String, dynamic> json) {
    final rawRetry = json['retry_count'];
    return SyncOperationStatus(
      id: _str(json['id']),
      localOperationId: _str(json['local_operation_id']),
      operationType: _str(json['operation_type']),
      status: _str(json['status']),
      targetEntity: _str(json['target_entity']),
      targetId: _str(json['target_id']),
      lastErrorCode: _str(json['last_error_code']),
      rejectionReason: _str(json['rejection_reason']),
      retryCount: rawRetry is int ? rawRetry : int.tryParse('$rawRetry'),
      updatedAt: _str(json['updated_at']),
    );
  }
}

/// The `operation_statuses` page (RF-063): typed rows plus pagination.
class SyncOperationStatusPage {
  const SyncOperationStatusPage({
    required this.statuses,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<SyncOperationStatus> statuses;
  final SyncCursor? nextCursor;
  final bool hasMore;

  static const SyncOperationStatusPage empty = SyncOperationStatusPage(
    statuses: [],
    nextCursor: null,
    hasMore: false,
  );

  static SyncOperationStatusPage fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    final statuses = <SyncOperationStatus>[];
    if (rawRows is List) {
      for (final r in rawRows) {
        if (r is Map) {
          statuses.add(
            SyncOperationStatus.fromJson(
              r.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        } else {
          throw const FormatException(
            'sync_pull: operation_status is not an object',
          );
        }
      }
    } else if (rawRows != null) {
      throw const FormatException(
        'sync_pull: operation_statuses rows is not an array',
      );
    }
    return SyncOperationStatusPage(
      statuses: statuses,
      nextCursor: SyncCursor.fromJson(json['next_cursor']),
      hasMore: json['has_more'] == true,
    );
  }
}

/// The set of per-entity pages under `changes` (RF-063), keyed by entity name.
class SyncPullChanges {
  const SyncPullChanges(this.entities);

  /// entity name -> page.
  final Map<String, SyncPullEntityPage> entities;

  SyncPullEntityPage? operator [](String entity) => entities[entity];

  static SyncPullChanges fromJson(Object? json) {
    if (json == null) return const SyncPullChanges({});
    if (json is! Map) {
      throw const FormatException('sync_pull: changes is not an object');
    }
    final out = <String, SyncPullEntityPage>{};
    json.forEach((key, value) {
      if (value is! Map) {
        throw const FormatException('sync_pull: change entry is not an object');
      }
      out[key.toString()] = SyncPullEntityPage.fromJson(
        value.map((k, v) => MapEntry(k.toString(), v)),
      );
    });
    return SyncPullChanges(out);
  }
}

/// The full, validated `app.sync_pull` response envelope (RF-063):
/// `{ ok, server_ts, changes, operation_statuses }`.
class SyncPullResponse {
  const SyncPullResponse({
    required this.serverTs,
    required this.changes,
    required this.operationStatuses,
  });

  /// The server clock at response time (raw ISO string; not parsed).
  final String? serverTs;

  /// Per-entity changed rows.
  final SyncPullChanges changes;

  /// The current-device operation-status feed.
  final SyncOperationStatusPage operationStatuses;

  /// Parse a decoded JSON envelope. Throws [FormatException] when the shape is
  /// not a valid `ok == true` envelope (the caller maps that to
  /// `InvalidResponseFailure`).
  static SyncPullResponse fromJson(Object? decoded) {
    if (decoded is! Map) {
      throw const FormatException('sync_pull: response is not an object');
    }
    final json = decoded.map((k, v) => MapEntry(k.toString(), v));
    if (json['ok'] != true) {
      throw const FormatException('sync_pull: response ok is not true');
    }
    final rawServerTs = json['server_ts'];
    final rawOps = json['operation_statuses'];
    return SyncPullResponse(
      serverTs: rawServerTs is String ? rawServerTs : rawServerTs?.toString(),
      changes: SyncPullChanges.fromJson(json['changes']),
      operationStatuses: rawOps == null
          ? SyncOperationStatusPage.empty
          : SyncOperationStatusPage.fromJson(
              (rawOps as Map).map((k, v) => MapEntry(k.toString(), v)),
            ),
    );
  }
}
