import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_publisher.dart';

const org = '11111111-1111-4111-8111-111111111111';
const restaurant = '22222222-2222-4222-8222-222222222222';
const request = '33333333-3333-4333-8333-333333333333';
const id = '44444444-4444-4444-8444-444444444444';
const source = '$org/$restaurant/55555555-5555-4555-8555-555555555555.mp4';
final hash = 'a' * 64;
final objectKey = '${'b' * 32}/$hash.mp4';

Map<String, Object?> videoMedia() => {
  'id': id,
  'object_key': objectKey,
  'content_hash': hash,
  'mime_type': 'video/mp4',
  'width': 1280,
  'height': 720,
  'duration_ms': 12000,
  'bytes': 123456,
  'published': true,
  'url': '/storage/v1/object/public/storefront-welcome-videos/$objectKey',
};
Map<String, Object?> publishedVideo() => {
  'ok': true,
  'status': 'published',
  'kind': 'welcome_video_v1',
  'organization_id': org,
  'restaurant_id': restaurant,
  'request_id': request,
  'media': videoMedia(),
};

class VideoInvoker implements StorefrontFunctionInvoker {
  VideoInvoker(this.replies);
  final List<Object> replies;
  final bodies = <Map<String, Object?>>[];
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    bodies.add(Map.of(body));
    final reply = replies[(bodies.length - 1).clamp(0, replies.length - 1)];
    if (reply is Error) throw reply;
    return reply as StorefrontFunctionReply;
  }
}

StorefrontWelcomeVideoPublisher videoPublisher(VideoInvoker invoker) =>
    StorefrontWelcomeVideoPublisher(
      invoker: invoker,
      organizationId: org,
      restaurantId: restaurant,
    );

void main() {
  test(
    'exact original success envelope and five identifiers; no image ladder',
    () async {
      final invoker = VideoInvoker([
        StorefrontFunctionReply.fromHttp(200, publishedVideo()),
      ]);
      final publisher = videoPublisher(invoker);
      final attempt = publisher.prepare(sourceKey: source, requestId: request);
      final result = await publisher.publish(attempt);
      expect(result.isPublished, isTrue);
      expect(result.media!.id, id);
      expect(
        result.media!.publicPath,
        '/storage/v1/object/public/storefront-welcome-videos/$objectKey',
      );
      expect(invoker.bodies, [
        {
          'kind': 'welcome_video_v1',
          'request_id': request,
          'organization_id': org,
          'restaurant_id': restaurant,
          'source_key': source,
        },
      ]);
      expect(result.calls, 1);
      expect(result.attempt, same(attempt));
    },
  );

  test(
    'unknown outcome sends one POST; only explicit replay repeats exact body',
    () async {
      final invoker = VideoInvoker([
        const StorefrontFunctionReply.transportFailure(),
        StorefrontFunctionReply.fromHttp(200, publishedVideo()),
      ]);
      final publisher = videoPublisher(invoker),
          attempt = videoPublisher(
            invoker,
          ).prepare(sourceKey: source, requestId: request);
      final result = await publisher.publish(attempt);
      expect(result.status, StorefrontWelcomeVideoPublishStatus.uncertain);
      expect(invoker.bodies, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      expect(invoker.bodies, hasLength(1));
      expect((await publisher.publish(result.attempt)).isPublished, isTrue);
      expect(invoker.bodies, hasLength(2));
      expect(invoker.bodies.first, invoker.bodies.last);
    },
  );

  test(
    'another restaurant, old binding and invalid request identity never POST',
    () async {
      final invoker = VideoInvoker([
        StorefrontFunctionReply.fromHttp(200, publishedVideo()),
      ]);
      final publisher = videoPublisher(invoker);
      for (final attempt in [
        publisher.prepare(
          sourceKey: source.replaceFirst(restaurant, request),
          requestId: request,
        ),
        publisher.prepare(
          sourceKey: source,
          requestId: 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
        ),
        StorefrontWelcomeVideoAttempt(
          organizationId: request,
          restaurantId: restaurant,
          requestId: request,
          sourceKey: source,
        ),
      ]) {
        expect(
          (await publisher.publish(attempt)).status,
          StorefrontWelcomeVideoPublishStatus.invalidRequest,
        );
      }
      expect(invoker.bodies, isEmpty);
    },
  );

  test(
    'HTTP200, UI text or malformed/mismatched success is never acceptance',
    () async {
      final invalid = <Map<String, Object?>>[
        {},
        {...publishedVideo(), 'extra': true},
        {...publishedVideo(), 'organization_id': request},
        {...publishedVideo(), 'restaurant_id': request},
        {...publishedVideo(), 'request_id': id},
        {...publishedVideo(), 'kind': 'image'},
        {
          ...publishedVideo(),
          'media': {...videoMedia(), 'published': false, 'url': null},
        },
        {
          ...publishedVideo(),
          'media': {...videoMedia(), 'duration_ms': 30001},
        },
        {
          ...publishedVideo(),
          'media': {...videoMedia(), 'width': 1280.0},
        },
        {
          ...publishedVideo(),
          'media': {...videoMedia(), 'height': 1081},
        },
        {
          ...publishedVideo(),
          'media': {...videoMedia(), 'bytes': welcomeVideoMaxBytes + 1},
        },
        {
          ...publishedVideo(),
          'media': {
            ...videoMedia(),
            'object_key': '${'b' * 32}/${'c' * 64}.mp4',
          },
        },
        {
          ...publishedVideo(),
          'media': {
            ...videoMedia(),
            'url': 'https://private.example/original.mp4',
          },
        },
        {
          ...publishedVideo(),
          'media': {...videoMedia(), 'source_key': source},
        },
      ];
      for (final body in invalid) {
        final invoker = VideoInvoker([
          StorefrontFunctionReply.fromHttp(200, body),
        ]);
        final publisher = videoPublisher(invoker);
        final result = await publisher.publish(
          publisher.prepare(sourceKey: source, requestId: request),
        );
        expect(result.status, StorefrontWelcomeVideoPublishStatus.uncertain);
        expect(result.media, isNull);
        expect(invoker.bodies, hasLength(1));
      }
    },
  );

  test(
    'bounded terminal failure statuses and unknown refusal remain distinct',
    () async {
      for (final row in [
        (
          401,
          'unauthenticated',
          null,
          StorefrontWelcomeVideoPublishStatus.unauthenticated,
        ),
        (
          403,
          'permission_denied',
          null,
          StorefrontWelcomeVideoPublishStatus.denied,
        ),
        (
          404,
          'source_not_found',
          null,
          StorefrontWelcomeVideoPublishStatus.sourceMissing,
        ),
        (
          409,
          'restart_required',
          null,
          StorefrontWelcomeVideoPublishStatus.restartRequired,
        ),
        (
          409,
          'object_conflict',
          null,
          StorefrontWelcomeVideoPublishStatus.objectConflict,
        ),
        (
          422,
          'refused',
          'invalid_mp4',
          StorefrontWelcomeVideoPublishStatus.refused,
        ),
        (
          422,
          'refused',
          'unknown_successor',
          StorefrontWelcomeVideoPublishStatus.serviceUnavailable,
        ),
        (
          503,
          'upstream_unavailable',
          null,
          StorefrontWelcomeVideoPublishStatus.uncertain,
        ),
      ]) {
        final invoker = VideoInvoker([
          StorefrontFunctionReply.fromHttp(row.$1, {
            'ok': false,
            'status': row.$2,
            if (row.$3 != null) 'code': row.$3,
          }),
        ]);
        final publisher = videoPublisher(invoker);
        expect(
          (await publisher.publish(
            publisher.prepare(sourceKey: source, requestId: request),
          )).status,
          row.$4,
        );
        expect(invoker.bodies, hasLength(1));
      }
    },
  );

  test(
    'manager decoder binds canonical published URL/hash and rejects private extra fields',
    () {
      expect(
        StorefrontWelcomeVideoMedia.fromJson(videoMedia()).byteLength,
        123456,
      );
      for (final row in [
        {...videoMedia(), 'source_key': source},
        {
          ...videoMedia(),
          'url': '/storage/v1/object/public/storefront-media/$objectKey',
        },
        {
          ...videoMedia(),
          'url':
              '/storage/v1/object/public/storefront-welcome-videos/$objectKey?token=x',
        },
        {...videoMedia(), 'mime_type': 'video/webm'},
        {...videoMedia(), 'bytes': 0},
        {...videoMedia(), 'published': false, 'url': null},
      ]) {
        expect(
          () => StorefrontWelcomeVideoMedia.fromJson(row),
          throwsException,
        );
      }
      final staged = StorefrontWelcomeVideoMedia.fromJson({
        ...videoMedia(),
        'published': false,
        'url': null,
      }, requirePublished: false);
      expect(staged.published, isFalse);
      expect(staged.publicPath, isNull);
    },
  );

  test(
    'capability adapter exposes invoker only, without a storage/client fallback',
    () {
      final invoker = VideoInvoker([
        const StorefrontFunctionReply.transportFailure(),
      ]);
      final imagePublisher = StorefrontMediaPublisher(
        invoker: invoker,
        organizationId: org,
        restaurantId: restaurant,
      );
      expect(imagePublisher.welcomeVideoInvoker, same(invoker));
      expect(imagePublisher.welcomeVideoStorage, isNull);
    },
  );
}
