import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:supabase/supabase.dart';

/// STOREFRONT-PUBLISH-001 — the client side of `storefront-media-publish`
/// (CONTRACT §2): the rung ladder with ONE request id, the typed terminal
/// answers, retry-once-then-uncertain, the hard cap, and a body of exactly the
/// eight contract keys (identifiers only — never image bytes).
const _org = '11111111-1111-4111-8111-111111111111';
const _rest = '22222222-2222-4222-8222-222222222222';
const _req = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const _mediaId = '44444444-4444-4444-8444-444444444444';
const _logoKey = '$_org/$_rest/logo/66666666-6666-4666-8666-666666666666.png';
const _menuKey =
    '$_org/$_rest/global/menu_item/77777777-7777-4777-8777-777777777777/'
    '88888888-8888-4888-8888-888888888888.jpg';

/// Scripted replies (the last one repeats); records every body sent. A
/// [StateError] entry is THROWN (an invoker that misbehaves).
class _FakeInvoker implements StorefrontFunctionInvoker {
  _FakeInvoker(this.replies);

  final List<Object> replies;
  final List<Map<String, Object?>> bodies = [];

  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    bodies.add(Map.of(body));
    final i = bodies.length - 1;
    final r = replies[i < replies.length ? i : replies.length - 1];
    if (r is StateError) throw r;
    return r as StorefrontFunctionReply;
  }

  List<Object?> get rungs => [for (final b in bodies) b['rung']];
}

StorefrontFunctionReply _reply(int status, [Map<String, Object?>? json]) =>
    StorefrontFunctionReply(httpStatus: status, json: json);

StorefrontFunctionReply _ladder(int next) =>
    _reply(202, {'ok': false, 'status': 'ladder_next', 'next_rung': next});

StorefrontFunctionReply _published({
  int rung = 0,
  int? profileVersion,
  String variant = 'w480',
  String bucket = 'restaurant-logos',
  String key = _logoKey,
}) => _reply(200, {
  'ok': true,
  'status': 'published',
  'recipe': 'storefront-media-c4',
  'rung': rung,
  'media': {
    'id': _mediaId,
    'object_key': '0123456789abcdef0123456789abcdef/${'b' * 64}.webp',
    'content_hash': 'b' * 64,
    'width': 480,
    'height': 320,
    'bytes': 40000,
    'variant': variant,
    'source_bucket': bucket,
    'source_key': key,
    'state': 'published',
  },
  'already_published': false,
  'republished': true,
  'replaced_media_id': '99999999-9999-4999-8999-999999999999',
  'profile_version': profileVersion,
});

const _transport = StorefrontFunctionReply.transportFailure();

StorefrontMediaPublisher _publisher(_FakeInvoker invoker) =>
    StorefrontMediaPublisher(
      invoker: invoker,
      organizationId: _org,
      restaurantId: _rest,
      retryDelay: Duration.zero,
    );

Future<StorefrontPublishResult> _publishLogo(_FakeInvoker invoker) =>
    _publisher(invoker).publish(
      slot: StorefrontSlot.logo,
      source: const StorefrontMediaSource.receiptLogo(_logoKey),
      requestId: _req,
    );

void main() {
  group('request body', () {
    test(
      'exactly the 8 contract keys; identifiers only, never bytes',
      () async {
        final invoker = _FakeInvoker([_published()]);
        await _publishLogo(invoker);
        final body = invoker.bodies.single;
        expect(body.keys.toList(), StorefrontMediaPublisher.requestKeys);
        expect(body.keys.toSet(), {
          'request_id',
          'organization_id',
          'restaurant_id',
          'slot',
          'variant',
          'source_bucket',
          'source_key',
          'rung',
        });
        expect(body, {
          'request_id': _req,
          'organization_id': _org,
          'restaurant_id': _rest,
          'slot': 'logo',
          'variant': 'w480',
          'source_bucket': 'restaurant-logos',
          'source_key': _logoKey,
          'rung': 0,
        });
        // Only scalar identifiers: no List / typed-data / map (no image bytes).
        for (final v in body.values) {
          expect(
            v is String || v is int,
            isTrue,
            reason: 'got ${v.runtimeType}',
          );
        }
      },
    );

    test('hero from a menu original => w960 + menu-images', () async {
      final invoker = _FakeInvoker([
        _published(variant: 'w960', bucket: 'menu-images', key: _menuKey),
      ]);
      final r = await _publisher(invoker).publish(
        slot: StorefrontSlot.hero,
        source: const StorefrontMediaSource.menuImage(_menuKey),
        requestId: _req,
      );
      expect(r.status, StorefrontPublishStatus.published);
      expect(invoker.bodies.single['slot'], 'hero');
      expect(invoker.bodies.single['variant'], 'w960');
      expect(invoker.bodies.single['source_bucket'], 'menu-images');
    });

    test('hero may also use the receipt logo', () async {
      final invoker = _FakeInvoker([_published(variant: 'w960')]);
      final r = await _publisher(invoker).publish(
        slot: StorefrontSlot.hero,
        source: const StorefrontMediaSource.receiptLogo(_logoKey),
        requestId: _req,
      );
      expect(r.status, StorefrontPublishStatus.published);
      expect(invoker.bodies.single['source_bucket'], 'restaurant-logos');
    });

    test('local refusals never call the function', () async {
      final invoker = _FakeInvoker([_published()]);
      final p = _publisher(invoker);
      final logoFromMenu = await p.publish(
        slot: StorefrontSlot.logo,
        source: const StorefrontMediaSource.menuImage(_menuKey),
        requestId: _req,
      );
      expect(logoFromMenu.status, StorefrontPublishStatus.invalidRequest);
      expect(logoFromMenu.refusedLocally, isTrue);
      expect(logoFromMenu.invalidField, 'source_bucket');
      final upperId = await p.publish(
        slot: StorefrontSlot.logo,
        source: const StorefrontMediaSource.receiptLogo(_logoKey),
        requestId: _req.toUpperCase(),
      );
      expect(upperId.invalidField, 'request_id');
      final emptyKey = await p.publish(
        slot: StorefrontSlot.logo,
        source: const StorefrontMediaSource.receiptLogo(''),
        requestId: _req,
      );
      expect(emptyKey.invalidField, 'source_key');
      expect(invoker.bodies, isEmpty);
    });
  });

  group('ladder', () {
    test('202 ladder_next => next rung, SAME request id', () async {
      final invoker = _FakeInvoker([
        _ladder(1),
        _ladder(2),
        _published(rung: 2),
      ]);
      final r = await _publishLogo(invoker);
      expect(r.status, StorefrontPublishStatus.published);
      expect(invoker.rungs, [0, 1, 2]);
      expect(invoker.bodies.map((b) => b['request_id']).toSet(), {_req});
      expect(r.rung, 2);
      expect(r.calls, 3);
    });

    test('200 => published(media, profileVersion)', () async {
      final r = await _publishLogo(
        _FakeInvoker([_published(profileVersion: 7)]),
      );
      expect(r.status, StorefrontPublishStatus.published);
      expect(r.isPublished, isTrue);
      expect(r.media!.id, _mediaId);
      expect(r.media!.variant, StorefrontVariant.w480);
      expect(r.media!.sourceBucket, StorefrontSourceBucket.restaurantLogos);
      expect(r.media!.byteLength, 40000);
      expect(r.profileVersion, 7);
      expect(r.republished, isTrue);
      expect(r.alreadyPublished, isFalse);
      expect(r.replacedMediaId, '99999999-9999-4999-8999-999999999999');
      expect(r.requestId, _req);
    });

    test('profile_version null stays null (no re-point happened)', () async {
      final r = await _publishLogo(_FakeInvoker([_published()]));
      expect(r.profileVersion, isNull);
    });

    test('a 202 that does not climb stops at once (never loops)', () async {
      for (final bad in [
        _ladder(0),
        _ladder(5),
        _reply(202, {'status': 'ladder_next'}),
        _reply(202),
      ]) {
        final invoker = _FakeInvoker([bad]);
        final r = await _publishLogo(invoker);
        expect(r.status, StorefrontPublishStatus.uncertain);
        expect(invoker.bodies, hasLength(1));
      }
    });

    test('hard cap: the full ladder climbs to rung 4 and stops', () async {
      final invoker = _FakeInvoker([
        _ladder(1),
        _ladder(2),
        _ladder(3),
        _ladder(4),
        _ladder(5), // a 6th rung does not exist
      ]);
      final r = await _publishLogo(invoker);
      expect(r.status, StorefrontPublishStatus.uncertain);
      expect(invoker.rungs, [0, 1, 2, 3, 4]);
    });

    test(
      'hard cap: 5 rungs x (1 + 1 retry) = at most 10 invocations',
      () async {
        final invoker = _FakeInvoker([
          _reply(503, {'status': 'engine_unavailable', 'retryable': true}),
          _ladder(1),
          _reply(503),
          _ladder(2),
          _reply(503),
          _ladder(3),
          _reply(503),
          _ladder(4),
          _reply(503),
          _reply(503),
          _published(), // never reached
        ]);
        final r = await _publishLogo(invoker);
        expect(r.status, StorefrontPublishStatus.uncertain);
        expect(invoker.bodies, hasLength(10));
        expect(invoker.rungs, [0, 0, 1, 1, 2, 2, 3, 3, 4, 4]);
        expect(r.calls, 10);
      },
    );
  });

  group('typed terminal answers (no retry)', () {
    test('each 422 refusal code is kept', () async {
      for (final code in kStorefrontRefusalCodes) {
        final invoker = _FakeInvoker([
          _reply(422, {'ok': false, 'status': 'refused', 'code': code}),
        ]);
        final r = await _publishLogo(invoker);
        expect(r.status, StorefrontPublishStatus.refused);
        expect(r.refusalCode, code);
        expect(invoker.bodies, hasLength(1));
      }
      final unknown = await _publishLogo(
        _FakeInvoker([
          _reply(422, {'status': 'refused'}),
        ]),
      );
      expect(unknown.refusalCode, 'unknown');
    });

    test('CRIT-3: a content-address mismatch is a 409 object_conflict, never '
        'a 422 source refusal (no dead content_mismatch mapping)', () async {
      expect(kStorefrontRefusalCodes, isNot(contains('content_mismatch')));
      expect(kStorefrontPublishFaultCodes, isNot(contains('content_mismatch')));
      final invoker = _FakeInvoker([
        _reply(409, {'ok': false, 'status': 'object_conflict'}),
      ]);
      final r = await _publishLogo(invoker);
      expect(r.status, StorefrontPublishStatus.objectConflict);
      expect(r.refusalCode, isNull);
      expect(invoker.bodies, hasLength(1));
    });

    test('401 / 403 / 404 / 409 map to their statuses', () async {
      Future<StorefrontPublishResult> once(
        StorefrontFunctionReply reply,
      ) async {
        final invoker = _FakeInvoker([reply]);
        final r = await _publishLogo(invoker);
        expect(invoker.bodies, hasLength(1));
        return r;
      }

      expect(
        (await once(_reply(401, {'status': 'unauthenticated'}))).status,
        StorefrontPublishStatus.unauthenticated,
      );
      expect(
        (await once(_reply(403, {'status': 'permission_denied'}))).status,
        StorefrontPublishStatus.denied,
      );
      expect(
        (await once(_reply(404, {'status': 'source_not_found'}))).status,
        StorefrontPublishStatus.sourceMissing,
      );
      expect(
        (await once(_reply(409, {'status': 'restart_required'}))).status,
        StorefrontPublishStatus.restartRequired,
      );
      expect(
        (await once(_reply(409, {'status': 'object_conflict'}))).status,
        StorefrontPublishStatus.objectConflict,
      );
    });

    test('400/405/413/415 are programming errors (invalidRequest)', () async {
      final r = await _publishLogo(
        _FakeInvoker([
          _reply(400, {
            'ok': false,
            'status': 'invalid_request',
            'field': 'rung',
            'reason': 'value',
          }),
        ]),
      );
      expect(r.status, StorefrontPublishStatus.invalidRequest);
      expect(r.invalidField, 'rung');
      expect(r.invalidReason, 'value');
      expect(r.refusedLocally, isFalse);
      for (final (s, said) in [
        (405, 'method_not_allowed'),
        (413, 'request_too_large'),
        (415, 'unsupported_media_type'),
      ]) {
        final invoker = _FakeInvoker([
          _reply(s, {'ok': false, 'status': said}),
        ]);
        final r = await _publishLogo(invoker);
        expect(r.status, StorefrontPublishStatus.invalidRequest);
        expect(r.invalidReason, said);
        expect(invoker.bodies, hasLength(1));
      }
    });

    test('a 422 whose code is a stage / recipe fault is an invalid request, '
        'never a verdict on the source image', () async {
      for (final code in kStorefrontPublishFaultCodes) {
        final invoker = _FakeInvoker([
          _reply(422, {'ok': false, 'status': 'refused', 'code': code}),
        ]);
        final r = await _publishLogo(invoker);
        expect(r.status, StorefrontPublishStatus.invalidRequest, reason: code);
        expect(r.invalidReason, code);
        expect(r.refusalCode, isNull);
        expect(invoker.bodies, hasLength(1));
      }
      // The two registries are disjoint.
      expect(
        kStorefrontPublishFaultCodes.toSet().intersection(
          kStorefrontRefusalCodes.toSet(),
        ),
        isEmpty,
      );
    });

    test('a typed 4xx WITHOUT the contract status did not come from the '
        'function: serviceUnavailable, one call, no source verdict', () async {
      final gateway = [
        // The platform gateway while the function is not deployed.
        _reply(404, {
          'code': 'NOT_FOUND',
          'message': 'Requested function was not found',
        }),
        _reply(404),
        _reply(403, {'message': 'Forbidden'}),
        _reply(409, {'ok': false, 'status': 'something_else'}),
        _reply(422, {'code': 'corrupt'}),
        _reply(400),
        _reply(405),
        _reply(413, {'message': 'Payload too large'}),
        _reply(415),
      ];
      for (final reply in gateway) {
        final invoker = _FakeInvoker([reply, _published()]);
        final r = await _publishLogo(invoker);
        expect(
          r.status,
          StorefrontPublishStatus.serviceUnavailable,
          reason: '${reply.httpStatus} ${reply.json}',
        );
        expect(r.refusalCode, isNull);
        expect(invoker.bodies, hasLength(1));
      }
    });

    test('SEC-1: an anonymous (device / kiosk) session or a non-'
        '`authenticated` role/aud is refused by the function with 401 '
        'unauthenticated before any RPC or download: sign in again, one '
        'call, no retry, no source verdict', () async {
      final invoker = _FakeInvoker([
        _reply(401, {'ok': false, 'status': 'unauthenticated'}),
        _published(),
      ]);
      final r = await _publishLogo(invoker);
      expect(r.status, StorefrontPublishStatus.unauthenticated);
      expect(r.refusalCode, isNull);
      expect(r.media, isNull);
      expect(invoker.bodies, hasLength(1));
    });

    test('any 401 means the session was not accepted (the function, or the '
        'gateway refusing the JWT)', () async {
      for (final reply in [
        _reply(401, {'ok': false, 'status': 'unauthenticated'}),
        _reply(401, {'code': 401, 'message': 'Invalid JWT'}),
      ]) {
        final invoker = _FakeInvoker([reply]);
        expect(
          (await _publishLogo(invoker)).status,
          StorefrontPublishStatus.unauthenticated,
        );
        expect(invoker.bodies, hasLength(1));
      }
    });
  });

  group('unknown outcomes: retry ONCE (same id + rung), then uncertain', () {
    test('503 then 200 => published after one retry', () async {
      final invoker = _FakeInvoker([
        _reply(503, {'status': 'engine_unavailable', 'retryable': true}),
        _published(),
      ]);
      final r = await _publishLogo(invoker);
      expect(r.status, StorefrontPublishStatus.published);
      expect(invoker.rungs, [0, 0]);
      expect(invoker.bodies[0], invoker.bodies[1]);
    });

    test('503 twice => uncertain (server-flagged when it said so)', () async {
      final invoker = _FakeInvoker([
        _reply(503, {
          'status': 'upstream_unavailable',
          'retryable': true,
          'uncertain': true,
        }),
        _reply(503, {'status': 'engine_unavailable', 'retryable': true}),
      ]);
      final r = await _publishLogo(invoker);
      expect(r.status, StorefrontPublishStatus.uncertain);
      expect(r.serverFlaggedUncertain, isTrue);
      expect(invoker.bodies, hasLength(2));
    });

    test('500 then transport failure => uncertain', () async {
      final invoker = _FakeInvoker([
        _reply(500, {
          'status': 'internal_error',
          'retryable': true,
          'uncertain': true,
        }),
        _transport,
      ]);
      final r = await _publishLogo(invoker);
      expect(r.status, StorefrontPublishStatus.uncertain);
      expect(r.serverFlaggedUncertain, isTrue);
      expect(invoker.bodies, hasLength(2));
    });

    test('transport failure twice / other statuses => uncertain', () async {
      for (final reply in [_transport, _reply(502), _reply(429), _reply(302)]) {
        final invoker = _FakeInvoker([reply]);
        final r = await _publishLogo(invoker);
        expect(r.status, StorefrontPublishStatus.uncertain);
        expect(r.serverFlaggedUncertain, isFalse);
        expect(invoker.bodies, hasLength(2));
        expect(
          invoker.bodies[0]['request_id'],
          invoker.bodies[1]['request_id'],
        );
      }
    });

    test('platform failure answers (a runtime kill, an uncaught exception, '
        'a boot or idle timeout) are unknown outcomes: retry once, then '
        'uncertain (DEPLOYMENT §17.4 item 9)', () async {
      for (final reply in [
        _reply(546, {
          'code': 'WORKER_RESOURCE_LIMIT',
          'message':
              'Function failed due to not having enough compute resources '
              '(please check logs)',
        }),
        _reply(500, {
          'code': 'WORKER_ERROR',
          'message': 'Function failed to start or respond.',
        }),
        _reply(503),
        _reply(504),
      ]) {
        final invoker = _FakeInvoker([reply]);
        final r = await _publishLogo(invoker);
        expect(r.status, StorefrontPublishStatus.uncertain);
        expect(r.serverFlaggedUncertain, isFalse);
        expect(invoker.bodies, hasLength(2));
        expect(invoker.bodies[0], invoker.bodies[1]);
      }
    });

    test('an invoker that throws is a transport failure', () async {
      final invoker = _FakeInvoker([StateError('boom'), _published()]);
      final r = await _publishLogo(invoker);
      expect(r.status, StorefrontPublishStatus.published);
      expect(invoker.bodies, hasLength(2));
    });

    test('a 200 that is not a well-formed publish is ambiguous', () async {
      final bad = _reply(200, {'ok': true, 'status': 'published'});
      final retried = _FakeInvoker([bad, _published()]);
      expect(
        (await _publishLogo(retried)).status,
        StorefrontPublishStatus.published,
      );
      final twice = _FakeInvoker([bad]);
      expect(
        (await _publishLogo(twice)).status,
        StorefrontPublishStatus.uncertain,
      );
      expect(twice.bodies, hasLength(2));
    });
  });

  group('StorefrontFunctionReply.fromHttp', () {
    test('decodes a JSON map, JSON text, and tolerates plain text', () {
      final a = StorefrontFunctionReply.fromHttp(422, {
        'status': 'refused',
        'code': 'corrupt',
      });
      expect(a.httpStatus, 422);
      expect(a.json!['code'], 'corrupt');
      expect(a.transportFailed, isFalse);
      final b = StorefrontFunctionReply.fromHttp(
        409,
        '{"ok":false,"status":"restart_required"}',
      );
      expect(b.json!['status'], 'restart_required');
      final c = StorefrontFunctionReply.fromHttp(
        502,
        '<html>Bad gateway</html>',
      );
      expect(c.httpStatus, 502);
      expect(c.json, isNull);
      final d = StorefrontFunctionReply.fromHttp(200, null);
      expect(d.json, isNull);
    });
  });

  test('SupabaseStorefrontFunctionInvoker: an unreachable host is a transport '
      'failure, never a throw', () async {
    final invoker = SupabaseStorefrontFunctionInvoker(
      SupabaseClient('http://127.0.0.1:9', 'test-anon-key'),
      timeout: const Duration(seconds: 20),
    );
    final reply = await invoker.invoke({'request_id': _req});
    expect(reply.transportFailed, isTrue);
    expect(reply.httpStatus, isNull);
  });
}
