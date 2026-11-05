import 'storefront_media_publisher.dart';
import 'storefront_models.dart';

enum StorefrontBackgroundStatus {
  published,
  notNeeded,
  refused,
  unavailable,
  uncertain,
}

class StorefrontBackgroundResult {
  const StorefrontBackgroundResult(
    this.status, {
    this.baseRung,
    this.width,
    this.height,
    this.byteLength,
    this.code,
    this.calls = 0,
  });
  final StorefrontBackgroundStatus status;
  final int? baseRung, width, height, byteLength;
  final String? code;
  final int calls;
}

/// Optional background-only companion. The existing w960 publication and
/// content Save remain independent. No private path or image bytes leave the
/// client; the authenticated function resolves the eligible parent itself.
class StorefrontBackgroundPublisher {
  StorefrontBackgroundPublisher({
    required StorefrontFunctionInvoker invoker,
    required this.organizationId,
    required this.restaurantId,
  }) : _invoker = invoker;

  final StorefrontFunctionInvoker _invoker;
  final String organizationId, restaurantId;
  static const recipe = 'storefront-background-b1';
  static const variant = 'bg2560';
  static final _hash = RegExp(r'^[0-9a-f]{64}$');
  static final _key = RegExp(r'^[0-9a-f]{32}/[0-9a-f]{64}\.webp$');

  Future<StorefrontBackgroundResult> publish({
    required String requestId,
    required String branchId,
    required String baseMediaId,
    required int baseWidth,
    required int baseHeight,
    int? baseRung,
  }) async {
    if (![
          organizationId,
          restaurantId,
          requestId,
          branchId,
          baseMediaId,
        ].every(isCanonicalUuid) ||
        baseWidth < 1 ||
        baseHeight < 1 ||
        baseWidth > 960 ||
        baseHeight > 960 ||
        (baseRung != null && (baseRung < 0 || baseRung > 4))) {
      return const StorefrontBackgroundResult(
        StorefrontBackgroundStatus.refused,
        code: 'invalid_request',
      );
    }
    var candidate = baseRung ?? 0;
    var rung = 0;
    var calls = 0;
    // An existing selection may not have its original quality rung locally.
    // At most five no-effect base probes, then at most four higher rungs.
    for (var step = 0; step < 9; step++) {
      StorefrontFunctionReply? reply;
      final body = <String, Object?>{
        'request_id': requestId,
        'organization_id': organizationId,
        'restaurant_id': restaurantId,
        'branch_id': branchId,
        'base_media_id': baseMediaId,
        'slot': 'background',
        'variant': variant,
        'base_rung': candidate,
        'rung': rung,
      };
      // A single same-body retry for a missing/untyped answer. Retrying the
      // public registration keeps the same request identity and never saves.
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          reply = await _invoker.invoke(body);
        } catch (_) {
          reply = const StorefrontFunctionReply.transportFailure();
        }
        calls++;
        if (reply.json != null && !reply.transportFailed) break;
      }
      final json = reply?.json;
      StorefrontBackgroundResult result(
        StorefrontBackgroundStatus status, {
        String? code,
      }) => StorefrontBackgroundResult(
        status,
        baseRung: candidate,
        calls: calls,
        code: code,
      );
      if (json == null || reply!.transportFailed) {
        return result(StorefrontBackgroundStatus.uncertain);
      }
      if (reply.httpStatus == 422 &&
          json['status'] == 'refused' &&
          json['code'] == 'base_mismatch' &&
          baseRung == null &&
          rung == 0 &&
          candidate < 4) {
        candidate++;
        continue;
      }
      if (reply.httpStatus == 202 &&
          _keys(json, ['ok', 'status', 'next_rung']) &&
          json['ok'] == false &&
          json['status'] == 'ladder_next') {
        final next = json['next_rung'];
        if (next is int && next == rung + 1 && next <= 4) {
          rung = next;
          continue;
        }
        return result(StorefrontBackgroundStatus.uncertain);
      }
      if (reply.httpStatus == 200 &&
          _keys(json, ['ok', 'status']) &&
          json['ok'] == true &&
          json['status'] == 'not_needed') {
        return result(StorefrontBackgroundStatus.notNeeded);
      }
      if (reply.httpStatus == 200 &&
          _keys(json, ['ok', 'status', 'recipe', 'rung', 'media']) &&
          json['ok'] == true &&
          json['status'] == 'published' &&
          json['recipe'] == recipe &&
          json['rung'] == rung) {
        final media = json['media'];
        if (media is Map &&
            _keys(media, [
              'variant_id',
              'base_media_id',
              'object_key',
              'content_hash',
              'width',
              'height',
              'bytes',
              'variant',
              'recipe',
              'state',
            ])) {
          final width = media['width'], height = media['height'];
          final bytes = media['bytes'], hash = media['content_hash'];
          final key = media['object_key'], id = media['variant_id'];
          if (id is String &&
              isCanonicalUuid(id) &&
              media['base_media_id'] == baseMediaId &&
              media['variant'] == variant &&
              media['recipe'] == recipe &&
              media['state'] == 'published' &&
              width is int &&
              height is int &&
              bytes is int &&
              width > baseWidth &&
              height >= baseHeight &&
              width <= 2560 &&
              height <= 2560 &&
              bytes > 0 &&
              bytes <= 524288 &&
              hash is String &&
              _hash.hasMatch(hash) &&
              key is String &&
              _key.hasMatch(key) &&
              key.substring(33, 97) == hash) {
            return StorefrontBackgroundResult(
              StorefrontBackgroundStatus.published,
              baseRung: candidate,
              width: width,
              height: height,
              byteLength: bytes,
              calls: calls,
            );
          }
        }
        return result(StorefrontBackgroundStatus.uncertain);
      }
      if (reply.httpStatus == 422 && json['status'] == 'refused') {
        return result(
          StorefrontBackgroundStatus.refused,
          code: json['code'] is String ? json['code'] as String : null,
        );
      }
      if ([400, 401, 403, 404, 409].contains(reply.httpStatus)) {
        return result(
          StorefrontBackgroundStatus.unavailable,
          code: json['error'] is String ? json['error'] as String : null,
        );
      }
      if (reply.httpStatus == 503 &&
          json['retryable'] == true &&
          json['uncertain'] != true) {
        return result(StorefrontBackgroundStatus.unavailable);
      }
      return result(StorefrontBackgroundStatus.uncertain);
    }
    return StorefrontBackgroundResult(
      StorefrontBackgroundStatus.uncertain,
      baseRung: candidate,
      calls: calls,
    );
  }

  static bool _keys(Map value, List<String> expected) =>
      value.length == expected.length && expected.every(value.containsKey);
}
