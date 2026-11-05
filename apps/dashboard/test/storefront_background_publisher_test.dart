import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_background_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';

const org = '11111111-1111-4111-8111-111111111111';
const restaurant = '22222222-2222-4222-8222-222222222222';
const branch = '33333333-3333-4333-8333-333333333333';
const base = '44444444-4444-4444-8444-444444444444';
const request = '55555555-5555-4555-8555-555555555555';

Map<String, Object?> published({int rung = 0}) => {
  'ok': true,
  'status': 'published',
  'recipe': 'storefront-background-b1',
  'rung': rung,
  'media': <String, Object?>{
    'variant_id': request,
    'base_media_id': base,
    'object_key': '${'a' * 32}/${'b' * 64}.webp',
    'content_hash': 'b' * 64,
    'width': 1920,
    'height': 2560,
    'bytes': 459576,
    'variant': 'bg2560',
    'recipe': 'storefront-background-b1',
    'state': 'published',
  },
};

class Invoker implements StorefrontFunctionInvoker {
  Invoker(this.answer);
  final StorefrontFunctionReply Function(Map<String, Object?>, int) answer;
  final calls = <Map<String, Object?>>[];
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    calls.add(Map.of(body));
    return answer(body, calls.length);
  }
}

Future<StorefrontBackgroundResult> publish(Invoker invoker, {int? baseRung}) =>
    StorefrontBackgroundPublisher(
      invoker: invoker,
      organizationId: org,
      restaurantId: restaurant,
    ).publish(
      requestId: request,
      branchId: branch,
      baseMediaId: base,
      baseWidth: 720,
      baseHeight: 960,
      baseRung: baseRung,
    );

void main() {
  test(
    'only bounded identities are sent; exact companion is decoded',
    () async {
      final invoker = Invoker(
        (_, _) => StorefrontFunctionReply.fromHttp(200, published()),
      );
      final result = await publish(invoker, baseRung: 2);
      expect(result.status, StorefrontBackgroundStatus.published);
      expect(result.width, 1920);
      expect(result.height, 2560);
      expect(result.byteLength, 459576);
      expect(invoker.calls.single, {
        'request_id': request,
        'organization_id': org,
        'restaurant_id': restaurant,
        'branch_id': branch,
        'base_media_id': base,
        'slot': 'background',
        'variant': 'bg2560',
        'base_rung': 2,
        'rung': 0,
      });
    },
  );

  test('old selection probes base rungs only until exact hash proof', () async {
    final invoker = Invoker(
      (body, _) => body['base_rung'] == 2
          ? StorefrontFunctionReply.fromHttp(200, published())
          : StorefrontFunctionReply.fromHttp(422, {
              'ok': false,
              'status': 'refused',
              'code': 'base_mismatch',
            }),
    );
    final result = await publish(invoker);
    expect(result.status, StorefrontBackgroundStatus.published);
    expect(result.baseRung, 2);
    expect(invoker.calls.map((v) => v['base_rung']), [0, 1, 2]);
    expect(invoker.calls.map((v) => v['request_id']).toSet(), {request});
  });

  test(
    'one finite base search followed by high ladder has nine calls',
    () async {
      final invoker = Invoker((body, _) {
        if (body['base_rung'] != 4)
          return StorefrontFunctionReply.fromHttp(422, {
            'ok': false,
            'status': 'refused',
            'code': 'base_mismatch',
          });
        final rung = body['rung']! as int;
        return rung < 4
            ? StorefrontFunctionReply.fromHttp(202, {
                'ok': false,
                'status': 'ladder_next',
                'next_rung': rung + 1,
              })
            : StorefrontFunctionReply.fromHttp(200, published(rung: rung));
      });
      final result = await publish(invoker);
      expect(result.status, StorefrontBackgroundStatus.published);
      expect(result.calls, 9);
      expect(invoker.calls.skip(4).map((v) => v['base_rung']).toSet(), {4});
      expect(invoker.calls.skip(4).map((v) => v['rung']), [0, 1, 2, 3, 4]);
    },
  );

  test('lost answer retries the identical bounded request once', () async {
    final invoker = Invoker(
      (_, call) => call == 1
          ? const StorefrontFunctionReply.transportFailure()
          : StorefrontFunctionReply.fromHttp(200, published()),
    );
    expect(
      (await publish(invoker)).status,
      StorefrontBackgroundStatus.published,
    );
    expect(invoker.calls, hasLength(2));
    expect(invoker.calls.first, invoker.calls.last);
    final absent = Invoker(
      (_, _) => const StorefrontFunctionReply.transportFailure(),
    );
    expect(
      (await publish(absent)).status,
      StorefrontBackgroundStatus.uncertain,
    );
    expect(absent.calls, hasLength(2));
  });

  test(
    'no native enlargement and typed failure do not advance the ladder',
    () async {
      final native = Invoker(
        (_, _) => StorefrontFunctionReply.fromHttp(200, {
          'ok': true,
          'status': 'not_needed',
        }),
      );
      expect(
        (await publish(native)).status,
        StorefrontBackgroundStatus.notNeeded,
      );
      expect(native.calls, hasLength(1));
      final stale = Invoker(
        (_, _) => StorefrontFunctionReply.fromHttp(422, {
          'ok': false,
          'status': 'refused',
          'code': 'source_stale',
        }),
      );
      expect((await publish(stale)).status, StorefrontBackgroundStatus.refused);
      expect(stale.calls, hasLength(1));
      final denied = Invoker(
        (_, _) => StorefrontFunctionReply.fromHttp(403, {
          'ok': false,
          'error': 'permission_denied',
        }),
      );
      expect(
        (await publish(denied)).status,
        StorefrontBackgroundStatus.unavailable,
      );
      expect(denied.calls, hasLength(1));
    },
  );

  test(
    'foreign parents, oversized or malformed evidence never claim success',
    () async {
      for (final change in <void Function(Map<String, Object?>)>[
        (m) => m['base_media_id'] = restaurant,
        (m) => m['width'] = 2561,
        (m) => m['height'] = 800,
        (m) => m['width'] = 720,
        (m) => m['bytes'] = 524289,
        (m) => m['variant'] = 'w960',
        (m) => m['recipe'] = 'storefront-media-c4',
        (m) => m['state'] = 'staged',
        (m) => m['content_hash'] = 'c' * 64,
        (m) => m['object_key'] = 'https://example.invalid/file.webp',
        (m) => m['extra'] = true,
      ]) {
        final wire = published();
        change(wire['media']! as Map<String, Object?>);
        final invoker = Invoker(
          (_, _) => StorefrontFunctionReply.fromHttp(200, wire),
        );
        expect(
          (await publish(invoker)).status,
          StorefrontBackgroundStatus.uncertain,
        );
        expect(invoker.calls, hasLength(1));
      }
    },
  );

  test('unknown success and skipped/out-of-range rungs fail closed', () async {
    for (final wire in <Map<String, Object?>>[
      {'ok': true, 'status': 'not_needed', 'extra': true},
      for (final next in [0, 2, 5])
        {'ok': false, 'status': 'ladder_next', 'next_rung': next},
    ]) {
      final invoker = Invoker(
        (_, _) => StorefrontFunctionReply.fromHttp(
          wire['status'] == 'ladder_next' ? 202 : 200,
          wire,
        ),
      );
      expect(
        (await publish(invoker)).status,
        StorefrontBackgroundStatus.uncertain,
      );
      expect(invoker.calls, hasLength(1));
    }
  });

  test('invalid identities or base evidence cause no request', () async {
    final invoker = Invoker((_, _) => throw StateError('must not send'));
    for (final size in [0, 961]) {
      final result =
          await StorefrontBackgroundPublisher(
            invoker: invoker,
            organizationId: org,
            restaurantId: restaurant,
          ).publish(
            requestId: request,
            branchId: branch,
            baseMediaId: base,
            baseWidth: size,
            baseHeight: 960,
          );
      expect(result.status, StorefrontBackgroundStatus.refused);
    }
    expect(invoker.calls, isEmpty);
  });
}
