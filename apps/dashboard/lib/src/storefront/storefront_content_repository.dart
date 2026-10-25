import 'dart:convert';

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'storefront_content_models.dart';
import 'storefront_models.dart';
import 'storefront_rpc.dart';

enum StorefrontContentReadStatus {
  ok,
  denied,
  notFound,
  unavailable,
  malformed,
}

class StorefrontContentRead {
  const StorefrontContentRead(this.status, {this.snapshot});
  final StorefrontContentReadStatus status;
  final StorefrontContentSnapshot? snapshot;
  bool get isOk => status == StorefrontContentReadStatus.ok;
}

enum StorefrontContentWriteStatus {
  ok,
  conflict,
  branchConflict,
  denied,
  notFound,
  invalid,
  unavailable,
  uncertain,
}

class StorefrontContentAttempt {
  const StorefrontContentAttempt({
    required this.requestId,
    required this.expectedVersion,
    required this.expectedBranchId,
    required this.document,
  });
  final String requestId, expectedBranchId;
  final int expectedVersion;
  final StorefrontContentDocument document;
}

class StorefrontContentWrite {
  const StorefrontContentWrite(
    this.status, {
    required this.attempt,
    this.version,
    this.reason,
    this.field,
    this.replay = false,
    this.readback,
  });
  final StorefrontContentWriteStatus status;
  final StorefrontContentAttempt attempt;
  final int? version;
  final String? reason, field;
  final bool replay;
  final StorefrontContentRead? readback;
}

class StorefrontContentMediaList {
  const StorefrontContentMediaList({required this.version, required this.rows});
  final int version;
  final List<StorefrontContentMediaRow> rows;
}

abstract interface class StorefrontContentRepository {
  Future<StorefrontContentRead> readContent();
  Future<StorefrontContentWrite> saveContent(StorefrontContentAttempt attempt);
  Future<StorefrontContentMediaList?> listContentMedia();
  StorefrontContentAttempt prepareContent({
    required int expectedVersion,
    required String expectedBranchId,
    required StorefrontContentDocument document,
  });
}

/// The production profile composition exposes this capability using the same
/// authenticated transport and fixed organization/restaurant, not client roles.
abstract interface class StorefrontContentRepositoryBinding {
  StorefrontContentRepository get contentRepository;
}

class SupabaseStorefrontContentRepository
    implements StorefrontContentRepository {
  SupabaseStorefrontContentRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
    int Function()? nonce,
  }) : _transport = transport,
       _nonce = nonce ?? (() => DateTime.now().microsecondsSinceEpoch);
  final SyncRpcTransport _transport;
  final String organizationId, restaurantId;
  final int Function() _nonce;
  static const readFunction = 'get_restaurant_storefront_content_v1';
  static const writeFunction = 'set_restaurant_storefront_content_v1';
  static const mediaFunction = 'list_storefront_content_media_v1';
  Map<String, dynamic> get _scope => {
    'p_organization_id': organizationId,
    'p_restaurant_id': restaurantId,
  };

  @override
  Future<StorefrontContentRead> readContent() async {
    final result = await invokeStorefrontRpc(_transport, readFunction, _scope);
    if (!result.isResponded)
      return const StorefrontContentRead(
        StorefrontContentReadStatus.unavailable,
      );
    final raw = result.response!;
    final typedFailure =
        raw.length == 3 &&
        raw['ok'] == false &&
        raw['entity'] == storefrontContentEntity &&
        raw.containsKey('error');
    if (typedFailure && raw['error'] == 'not_found')
      return const StorefrontContentRead(StorefrontContentReadStatus.notFound);
    if (typedFailure && raw['error'] == 'permission_denied')
      return const StorefrontContentRead(StorefrontContentReadStatus.denied);
    try {
      return StorefrontContentRead(
        StorefrontContentReadStatus.ok,
        snapshot: StorefrontContentSnapshot.fromJson(raw, restaurantId),
      );
    } on StorefrontDecodeException {
      return const StorefrontContentRead(StorefrontContentReadStatus.malformed);
    } catch (_) {
      return const StorefrontContentRead(StorefrontContentReadStatus.malformed);
    }
  }

  @override
  StorefrontContentAttempt prepareContent({
    required int expectedVersion,
    required String expectedBranchId,
    required StorefrontContentDocument document,
  }) {
    if (expectedVersion < 1 || !contentId(expectedBranchId))
      throw ArgumentError('invalid content scope');
    return StorefrontContentAttempt(
      requestId: storefrontRequestId('pbl:storefront:content:', [
        organizationId,
        restaurantId,
        expectedVersion.toString(),
        expectedBranchId,
        jsonEncode(document.json),
      ], _nonce()),
      expectedVersion: expectedVersion,
      expectedBranchId: expectedBranchId,
      document: document,
    );
  }

  @override
  Future<StorefrontContentWrite> saveContent(
    StorefrontContentAttempt attempt,
  ) async {
    if (!contentId(attempt.requestId) ||
        !contentId(attempt.expectedBranchId) ||
        attempt.expectedVersion < 1) {
      return StorefrontContentWrite(
        StorefrontContentWriteStatus.invalid,
        attempt: attempt,
        reason: 'target_invalid',
        field: 'document',
      );
    }
    // Deeply immutable input is constructed before the first await. Both
    // bounded invocations and any explicit replay retain this exact tuple.
    final params = <String, dynamic>{
      ..._scope,
      'p_client_request_id': attempt.requestId,
      'p_expected_version': attempt.expectedVersion,
      'p_expected_storefront_branch_id': attempt.expectedBranchId,
      'p_document': attempt.document.json,
    };
    final result = await invokeStorefrontMutation(
      _transport,
      writeFunction,
      params,
    );
    if (result.isRefused)
      return StorefrontContentWrite(
        StorefrontContentWriteStatus.unavailable,
        attempt: attempt,
      );
    if (result.isResponded) {
      final raw = result.response!;
      bool exact(Set<String> keys) =>
          raw.length == keys.length && keys.every(raw.containsKey);
      if (raw['ok'] == true &&
          raw['entity'] == storefrontContentEntity &&
          exact({
            'ok',
            'idempotent_replay',
            'entity',
            'restaurant_id',
            'version',
            'slug',
            'is_published',
          }) &&
          raw['restaurant_id'] == restaurantId &&
          raw['version'] == attempt.expectedVersion + 1 &&
          raw['idempotent_replay'] is bool &&
          raw['is_published'] is bool &&
          raw['slug'] is String &&
          (raw['slug'] as String).isNotEmpty) {
        return StorefrontContentWrite(
          StorefrontContentWriteStatus.ok,
          attempt: attempt,
          version: raw['version'],
          replay: raw['idempotent_replay'],
        );
      }
      if (raw['ok'] == false && raw['entity'] == storefrontContentEntity) {
        switch (raw['error']) {
          case 'version_conflict':
            if (exact({
                  'ok',
                  'error',
                  'entity',
                  'restaurant_id',
                  'version',
                  'slug',
                  'is_published',
                }) &&
                raw['restaurant_id'] == restaurantId &&
                raw['version'] is int &&
                raw['slug'] is String &&
                raw['is_published'] is bool) {
              return StorefrontContentWrite(
                StorefrontContentWriteStatus.conflict,
                attempt: attempt,
                version: raw['version'],
              );
            }
          case 'branch_conflict':
            if (exact({'ok', 'error', 'entity', 'version'}) &&
                raw['version'] is int)
              return StorefrontContentWrite(
                StorefrontContentWriteStatus.branchConflict,
                attempt: attempt,
                version: raw['version'],
              );
          case 'invalid':
            if (exact({'ok', 'error', 'entity', 'reason', 'field'}) &&
                storefrontContentReasons.contains(raw['reason']) &&
                contentFieldPath(raw['field'])) {
              return StorefrontContentWrite(
                StorefrontContentWriteStatus.invalid,
                attempt: attempt,
                reason: raw['reason'],
                field: raw['field'],
              );
            }
          case 'permission_denied':
            if (exact({'ok', 'error', 'entity'}))
              return StorefrontContentWrite(
                StorefrontContentWriteStatus.denied,
                attempt: attempt,
              );
          case 'not_found':
            if (exact({'ok', 'error', 'entity'}))
              return StorefrontContentWrite(
                StorefrontContentWriteStatus.notFound,
                attempt: attempt,
              );
        }
      }
    }
    // A readable matching document is not proof of which manager committed.
    // Keep the original attempt; no new identity or third automatic POST.
    return StorefrontContentWrite(
      StorefrontContentWriteStatus.uncertain,
      attempt: attempt,
      readback: await readContent(),
    );
  }

  @override
  Future<StorefrontContentMediaList?> listContentMedia() async {
    final result = await invokeStorefrontRpc(_transport, mediaFunction, _scope);
    if (!result.isResponded) return null;
    try {
      final j = contentObject(result.response, {
        'ok',
        'entity',
        'restaurant_id',
        'version',
        'media_prefix',
        'media',
      }, 'media');
      if (j['ok'] != true ||
          j['entity'] != 'storefront_content_media' ||
          j['restaurant_id'] != restaurantId ||
          j['version'] is! int ||
          (j['version'] as int) < 1 ||
          j['media_prefix'] is! String ||
          j['media'] is! List ||
          (j['media'] as List).length > 200)
        return null;
      final rows = (j['media'] as List)
          .map(StorefrontContentMediaRow.fromJson)
          .toList();
      if (rows.map((row) => row.media.id).toSet().length != rows.length)
        return null;
      return StorefrontContentMediaList(
        version: j['version'],
        rows: List.unmodifiable(rows),
      );
    } catch (_) {
      return null;
    }
  }
}
