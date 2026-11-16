import 'storefront_media_publisher.dart';
import 'storefront_welcome_video_models.dart';

class StorefrontWelcomeVideoAttempt {
  const StorefrontWelcomeVideoAttempt({
    required this.organizationId,
    required this.restaurantId,
    required this.requestId,
    required this.sourceKey,
  });
  final String organizationId, restaurantId, requestId, sourceKey;
  Map<String, Object?> get body => Map.unmodifiable({
    'kind': 'welcome_video_v1',
    'request_id': requestId,
    'organization_id': organizationId,
    'restaurant_id': restaurantId,
    'source_key': sourceKey,
  });
}

enum StorefrontWelcomeVideoPublishStatus {
  published,
  refused,
  denied,
  unauthenticated,
  sourceMissing,
  restartRequired,
  objectConflict,
  invalidRequest,
  serviceUnavailable,
  uncertain,
}

class StorefrontWelcomeVideoPublishResult {
  const StorefrontWelcomeVideoPublishResult(
    this.status, {
    required this.attempt,
    this.media,
    this.code,
    this.calls = 1,
  });
  final StorefrontWelcomeVideoPublishStatus status;
  final StorefrontWelcomeVideoAttempt attempt;
  final StorefrontWelcomeVideoMedia? media;
  final String? code;
  final int calls;
  bool get isPublished =>
      status == StorefrontWelcomeVideoPublishStatus.published;
  bool get isUncertain =>
      status == StorefrontWelcomeVideoPublishStatus.uncertain;
}

/// One call per explicit action. This does not inherit the image publisher's
/// automatic ladder/retry behavior. Unknown outcomes retain the exact attempt.
class StorefrontWelcomeVideoPublisher {
  const StorefrontWelcomeVideoPublisher({
    required StorefrontFunctionInvoker invoker,
    required this.organizationId,
    required this.restaurantId,
  }) : _invoker = invoker;
  final StorefrontFunctionInvoker _invoker;
  final String organizationId, restaurantId;
  Object get bindingIdentity => _invoker;

  StorefrontWelcomeVideoAttempt prepare({
    required String sourceKey,
    required String requestId,
  }) => StorefrontWelcomeVideoAttempt(
    organizationId: organizationId,
    restaurantId: restaurantId,
    requestId: requestId,
    sourceKey: sourceKey,
  );

  Future<StorefrontWelcomeVideoPublishResult> publish(
    StorefrontWelcomeVideoAttempt attempt,
  ) async {
    StorefrontWelcomeVideoPublishResult result(
      StorefrontWelcomeVideoPublishStatus status, {
      StorefrontWelcomeVideoMedia? media,
      String? code,
      int calls = 1,
    }) => StorefrontWelcomeVideoPublishResult(
      status,
      attempt: attempt,
      media: media,
      code: code,
      calls: calls,
    );
    if (!welcomeVideoUuid(attempt.requestId) ||
        attempt.organizationId != organizationId ||
        attempt.restaurantId != restaurantId ||
        !welcomeVideoSourceBelongsTo(
          attempt.sourceKey,
          organizationId,
          restaurantId,
        )) {
      return result(
        StorefrontWelcomeVideoPublishStatus.invalidRequest,
        calls: 0,
      );
    }
    StorefrontFunctionReply reply;
    try {
      reply = await _invoker.invoke(attempt.body);
    } catch (_) {
      return result(StorefrontWelcomeVideoPublishStatus.uncertain);
    }
    if (reply.transportFailed || reply.json == null)
      return result(StorefrontWelcomeVideoPublishStatus.uncertain);
    final j = reply.json!;
    if (reply.httpStatus == 200) {
      const keys = {
        'ok',
        'status',
        'kind',
        'organization_id',
        'restaurant_id',
        'request_id',
        'media',
      };
      if (j.length != keys.length ||
          !keys.every(j.containsKey) ||
          j['ok'] != true ||
          j['status'] != 'published' ||
          j['kind'] != 'welcome_video_v1' ||
          j['organization_id'] != organizationId ||
          j['restaurant_id'] != restaurantId ||
          j['request_id'] != attempt.requestId) {
        return result(StorefrontWelcomeVideoPublishStatus.uncertain);
      }
      try {
        final media = StorefrontWelcomeVideoMedia.fromJson(j['media']);
        return result(
          StorefrontWelcomeVideoPublishStatus.published,
          media: media,
        );
      } catch (_) {
        return result(StorefrontWelcomeVideoPublishStatus.uncertain);
      }
    }
    if (j['ok'] != false)
      return result(StorefrontWelcomeVideoPublishStatus.uncertain);
    final status = j['status'];
    if (reply.httpStatus == 403 && status == 'permission_denied')
      return result(StorefrontWelcomeVideoPublishStatus.denied);
    if (reply.httpStatus == 401 && status == 'unauthenticated')
      return result(StorefrontWelcomeVideoPublishStatus.unauthenticated);
    if (reply.httpStatus == 404 && status == 'source_not_found')
      return result(StorefrontWelcomeVideoPublishStatus.sourceMissing);
    if (reply.httpStatus == 409 && status == 'restart_required')
      return result(StorefrontWelcomeVideoPublishStatus.restartRequired);
    if (reply.httpStatus == 409 && status == 'object_conflict')
      return result(StorefrontWelcomeVideoPublishStatus.objectConflict);
    if (reply.httpStatus == 422 && status == 'refused') {
      final code = j['code'];
      if (const {
        'invalid_mp4',
        'unsupported_video_codec',
        'unsupported_audio_codec',
        'unsupported_video_layout',
        'input_too_large',
        'duration_too_long',
        'dimensions_exceeded',
        'source_unavailable',
      }.contains(code))
        return result(
          StorefrontWelcomeVideoPublishStatus.refused,
          code: code as String,
        );
      return result(StorefrontWelcomeVideoPublishStatus.serviceUnavailable);
    }
    if (const [400, 405, 413, 415].contains(reply.httpStatus) &&
        status == 'invalid_request')
      return result(StorefrontWelcomeVideoPublishStatus.invalidRequest);
    if ((reply.httpStatus ?? 0) >= 500 || j['uncertain'] == true)
      return result(StorefrontWelcomeVideoPublishStatus.uncertain);
    return result(StorefrontWelcomeVideoPublishStatus.serviceUnavailable);
  }
}
