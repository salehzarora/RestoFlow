import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// STOREFRONT-PUBLISH-001 — list / retract / cancel envelopes, the one-retry
/// rule with the SAME request id, and the re-list on an unknown outcome.
const _org = '11111111-1111-4111-8111-111111111111';
const _rest = '22222222-2222-4222-8222-222222222222';
const _m1 = '44444444-4444-4444-8444-444444444444';
const _m2 = '55555555-5555-4555-8555-555555555555';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.scripts);

  /// function -> replies (Map returned, SyncTransportException thrown; the
  /// last reply repeats).
  final Map<String, List<Object?>> scripts;
  final List<(String, Map<String, dynamic>)> calls = [];

  List<Map<String, dynamic>> callsTo(String fn) => [
    for (final c in calls)
      if (c.$1 == fn) c.$2,
  ];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    final script = scripts[function];
    if (script == null) throw StateError('unexpected $function');
    calls.add((function, params));
    final n = callsTo(function).length - 1;
    final r = script[n < script.length ? n : script.length - 1];
    if (r is SyncTransportException) throw r;
    return r;
  }
}

const _timeout = SyncTransportException(
  SyncTransportErrorKind.transient,
  message: 'timeout',
);

const _denied42501 = SyncTransportException(
  SyncTransportErrorKind.server,
  code: '42501',
  message: 'permission denied',
);

Map<String, dynamic> _row({
  String id = _m1,
  String state = 'published',
  List<String> inUse = const [],
}) => {
  'id': id,
  'source_bucket': 'restaurant-logos',
  'source_key': '$_org/$_rest/logo/66666666-6666-4666-8666-666666666666.png',
  'variant': 'w480',
  'object_key': '0123456789abcdef0123456789abcdef/${'a' * 64}.webp',
  'content_hash': 'a' * 64,
  'width': 480,
  'height': 240,
  'bytes': 12345,
  'state': state,
  'published_at': state == 'staged' ? null : '2026-09-24T10:00:00+00:00',
  'unpublished_at': state == 'retracted' ? '2026-09-24T11:00:00+00:00' : null,
  'created_at': '2026-09-24T09:59:00.5+00:00',
  'in_use': inUse,
};

Map<String, dynamic> _list(List<Map<String, dynamic>> rows) => {
  'ok': true,
  'entity': 'storefront_media',
  'restaurant_id': _rest,
  'media_prefix': '0123456789abcdef0123456789abcdef',
  'media': rows,
};

SupabaseStorefrontMediaRepository _repo(_FakeTransport t, {int nonce = 3}) =>
    SupabaseStorefrontMediaRepository(
      transport: t,
      organizationId: _org,
      restaurantId: _rest,
      nonce: () => nonce,
    );

void main() {
  group('list', () {
    test('ok decodes every row, newest first as served', () async {
      final t = _FakeTransport({
        'list_storefront_media': [
          _list([
            _row(id: _m2, state: 'staged'),
            _row(inUse: ['logo', 'hero']),
          ]),
        ],
      });
      final l = await _repo(t).list();
      expect(l.status, StorefrontMediaListStatus.ok);
      expect(l.mediaPrefix, '0123456789abcdef0123456789abcdef');
      expect(l.media, hasLength(2));
      final staged = l.media[0];
      expect(staged.state, StorefrontMediaState.staged);
      expect(staged.isStaged, isTrue);
      expect(staged.publishedAt, isNull);
      final live = l.byId(_m1.toUpperCase())!;
      expect(live.isLive, isTrue);
      expect(live.inUse, [StorefrontSlot.logo, StorefrontSlot.hero]);
      expect(live.sourceBucket, StorefrontSourceBucket.restaurantLogos);
      expect(live.variant, StorefrontVariant.w480);
      expect(live.byteLength, 12345);
      expect(live.width, 480);
      expect(live.createdAt.isUtc, isTrue);
      expect(t.callsTo('list_storefront_media').single, {
        'p_organization_id': _org,
        'p_restaurant_id': _rest,
      });
    });

    test('not_found => denied', () async {
      final l = await _repo(
        _FakeTransport({
          'list_storefront_media': [
            {'ok': false, 'error': 'not_found', 'entity': 'storefront_media'},
          ],
        }),
      ).list();
      expect(l.status, StorefrontMediaListStatus.denied);
      expect(l.media, isEmpty);
    });

    test('42501 / transport => unavailable', () async {
      final l1 = await _repo(
        _FakeTransport({
          'list_storefront_media': [_denied42501],
        }),
      ).list();
      expect(l1.status, StorefrontMediaListStatus.unavailable);
      expect(l1.code, '42501');
      final l2 = await _repo(
        _FakeTransport({
          'list_storefront_media': [_timeout],
        }),
      ).list();
      expect(l2.status, StorefrontMediaListStatus.unavailable);
    });

    test('a malformed row is a typed decode failure', () async {
      Future<StorefrontMediaList> listWith(Object? envelope) => _repo(
        _FakeTransport({
          'list_storefront_media': [envelope],
        }),
      ).list();
      final l1 = await listWith(_list([_row(state: 'deleted')]));
      expect(l1.status, StorefrontMediaListStatus.malformed);
      expect(l1.decodeError!.field, 'media[0].state');
      final l2 = await listWith(
        _list([
          _row(),
          {
            ..._row(),
            'in_use': ['banner'],
          },
        ]),
      );
      expect(l2.decodeError!.field, 'media[1].in_use[0]');
      final l3 = await listWith(
        _list([
          {..._row(), 'source_bucket': 'storefront-media'},
        ]),
      );
      expect(l3.decodeError!.field, 'media[0].source_bucket');
      final l4 = await listWith({..._list([]), 'media': null});
      expect(l4.decodeError!.field, 'media');
      final l5 = await listWith('nope');
      expect(l5.status, StorefrontMediaListStatus.malformed);
      final l6 = await listWith({
        ..._list([_row()]),
        'restaurant_id': '99999999-9999-4999-8999-999999999999',
      });
      expect(l6.decodeError!.field, 'restaurant_id');
    });
  });

  group('retract', () {
    Future<(StorefrontMediaActionResult, _FakeTransport)> retractWith(
      List<Object?> replies, {
      List<Object?> list = const [],
    }) async {
      final t = _FakeTransport({
        'retract_storefront_media': replies,
        'list_storefront_media': list,
      });
      return (await _repo(t).retract(_m1), t);
    }

    test('ok sends the four params with a canonical request id', () async {
      final (r, t) = await retractWith([
        {
          'ok': true,
          'idempotent_replay': false,
          'entity': 'storefront_media',
          'media_id': _m1,
          'state': 'retracted',
          'already_retracted': false,
        },
      ]);
      expect(r.status, StorefrontMediaActionStatus.ok);
      expect(r.alreadyRetracted, isFalse);
      final params = t.callsTo('retract_storefront_media').single;
      expect(params.keys.toSet(), {
        'p_client_request_id',
        'p_organization_id',
        'p_restaurant_id',
        'p_media_id',
      });
      expect(params['p_media_id'], _m1);
      expect(isCanonicalUuid(params['p_client_request_id'] as String), isTrue);
      expect(r.requestId, params['p_client_request_id']);
      expect(t.callsTo('list_storefront_media'), isEmpty);
    });

    test('already_retracted is ok', () async {
      final (r, _) = await retractWith([
        {'ok': true, 'already_retracted': true, 'idempotent_replay': false},
      ]);
      expect(r.status, StorefrontMediaActionStatus.ok);
      expect(r.alreadyRetracted, isTrue);
    });

    test('media_in_use carries the slots', () async {
      final (r, t) = await retractWith([
        {
          'ok': false,
          'error': 'media_in_use',
          'slots': ['logo', 'hero'],
          'entity': 'storefront_media',
        },
      ]);
      expect(r.status, StorefrontMediaActionStatus.mediaInUse);
      expect(r.slots, [StorefrontSlot.logo, StorefrontSlot.hero]);
      expect(t.callsTo('retract_storefront_media'), hasLength(1));
    });

    test('media_not_published / not_found / permission_denied', () async {
      expect(
        (await retractWith([
          {'ok': false, 'error': 'media_not_published'},
        ])).$1.status,
        StorefrontMediaActionStatus.mediaNotPublished,
      );
      expect(
        (await retractWith([
          {'ok': false, 'error': 'not_found'},
        ])).$1.status,
        StorefrontMediaActionStatus.notFound,
      );
      expect(
        (await retractWith([
          {'ok': false, 'error': 'permission_denied'},
        ])).$1.status,
        StorefrontMediaActionStatus.denied,
      );
      expect(
        (await retractWith([
          {'ok': false, 'error': 'mystery'},
        ])).$1.status,
        StorefrontMediaActionStatus.unavailable,
      );
    });

    test(
      'DB-4: stale_request (a replay whose row is LIVE again or gone) is '
      'its own typed outcome — never ok / "retracted", never unavailable',
      () async {
        final (r, t) = await retractWith(
          [
            {
              'ok': false,
              'error': 'stale_request',
              'entity': 'storefront_media',
            },
          ],
          list: [
            _list([_row()]),
          ],
        );
        expect(r.status, StorefrontMediaActionStatus.staleRequest);
        expect(r.isOk, isFalse);
        expect(r.alreadyRetracted, isFalse);
        expect(t.callsTo('retract_storefront_media'), hasLength(1));
        // Replaying the SAME id (the slot's Try again) is what can meet it.
        const replayId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
        final t2 = _FakeTransport({
          'retract_storefront_media': [
            {'ok': false, 'error': 'stale_request'},
          ],
          'list_storefront_media': const <Object?>[],
        });
        final replay = await _repo(t2).retract(_m1, requestId: replayId);
        expect(replay.status, StorefrontMediaActionStatus.staleRequest);
        expect(replay.requestId, replayId);
        expect(
          t2.callsTo('retract_storefront_media').single['p_client_request_id'],
          replayId,
        );
      },
    );

    test('42501 is definitive: unavailable, no retry, no re-list', () async {
      final (r, t) = await retractWith([_denied42501]);
      expect(r.status, StorefrontMediaActionStatus.unavailable);
      expect(r.code, '42501');
      expect(t.callsTo('retract_storefront_media'), hasLength(1));
      expect(t.callsTo('list_storefront_media'), isEmpty);
    });

    test('timeout then the retry answers: ONE retry, SAME id', () async {
      final (r, t) = await retractWith([
        _timeout,
        {'ok': true, 'idempotent_replay': true, 'already_retracted': false},
      ]);
      expect(r.status, StorefrontMediaActionStatus.ok);
      expect(r.idempotentReplay, isTrue);
      final calls = t.callsTo('retract_storefront_media');
      expect(calls, hasLength(2));
      expect(calls[0]['p_client_request_id'], calls[1]['p_client_request_id']);
      expect(t.callsTo('list_storefront_media'), isEmpty);
    });

    test('unknown outcome re-lists: row retracted => ok (recovered)', () async {
      final (r, t) = await retractWith(
        [_timeout, _timeout],
        list: [
          _list([_row(state: 'retracted')]),
        ],
      );
      expect(r.status, StorefrontMediaActionStatus.ok);
      expect(r.recovered!.isOk, isTrue);
      expect(t.callsTo('retract_storefront_media'), hasLength(2));
      expect(t.callsTo('list_storefront_media'), hasLength(1));
    });

    test(
      'unknown outcome re-lists: row still LIVE => uncertain + list',
      () async {
        final (r, _) = await retractWith(
          [_timeout, _timeout],
          list: [
            _list([_row()]),
          ],
        );
        expect(r.status, StorefrontMediaActionStatus.uncertain);
        expect(r.recovered!.byId(_m1)!.isLive, isTrue);
        expect(isCanonicalUuid(r.requestId), isTrue);
      },
    );

    test('unknown outcome re-lists: row staged / gone are typed', () async {
      final (staged, _) = await retractWith(
        [_timeout, _timeout],
        list: [
          _list([_row(state: 'staged')]),
        ],
      );
      expect(staged.status, StorefrontMediaActionStatus.mediaNotPublished);
      final (gone, _) = await retractWith(
        [_timeout, _timeout],
        list: [_list(const [])],
      );
      expect(gone.status, StorefrontMediaActionStatus.notFound);
    });

    test(
      'unknown outcome and the re-list fails => uncertain, nothing recovered',
      () async {
        final (r, _) = await retractWith(
          [_timeout, _timeout],
          list: [_timeout],
        );
        expect(r.status, StorefrontMediaActionStatus.uncertain);
        expect(r.recovered, isNull);
      },
    );

    test('Try again reuses the supplied request id', () async {
      const id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      final t = _FakeTransport({
        'retract_storefront_media': [
          {'ok': true, 'already_retracted': false},
        ],
      });
      final r = await _repo(t).retract(_m1, requestId: id);
      expect(r.requestId, id);
      expect(
        t.callsTo('retract_storefront_media').single['p_client_request_id'],
        id,
      );
      await expectLater(
        _repo(t).retract(_m1, requestId: 'not-a-uuid'),
        throwsArgumentError,
      );
    });

    test('a fresh press mints a fresh id (per nonce)', () async {
      final t = _FakeTransport({
        'retract_storefront_media': [
          {'ok': true},
        ],
        'cancel_storefront_media': [
          {'ok': true},
        ],
      });
      await _repo(t, nonce: 1).retract(_m1);
      await _repo(t, nonce: 2).retract(_m1);
      await _repo(t, nonce: 1).cancel(_m1);
      final retracts = t.callsTo('retract_storefront_media');
      expect(
        retracts[0]['p_client_request_id'],
        isNot(retracts[1]['p_client_request_id']),
      );
      // The op is part of the seed: retract and cancel never collide.
      expect(
        t.callsTo('cancel_storefront_media').single['p_client_request_id'],
        isNot(retracts[0]['p_client_request_id']),
      );
    });
  });

  group('cancel', () {
    Future<(StorefrontMediaActionResult, _FakeTransport)> cancelWith(
      List<Object?> replies, {
      List<Object?> list = const [],
    }) async {
      final t = _FakeTransport({
        'cancel_storefront_media': replies,
        'list_storefront_media': list,
      });
      return (await _repo(t).cancel(_m2), t);
    }

    test('ok / media_published / not_found / denied', () async {
      final (ok, t) = await cancelWith([
        {
          'ok': true,
          'idempotent_replay': false,
          'entity': 'storefront_media',
          'media_id': _m2,
          'state': 'cancelled',
        },
      ]);
      expect(ok.status, StorefrontMediaActionStatus.ok);
      expect(t.callsTo('cancel_storefront_media').single['p_media_id'], _m2);
      expect(
        (await cancelWith([
          {'ok': false, 'error': 'media_published'},
        ])).$1.status,
        StorefrontMediaActionStatus.mediaPublished,
      );
      expect(
        (await cancelWith([
          {'ok': false, 'error': 'not_found'},
        ])).$1.status,
        StorefrontMediaActionStatus.notFound,
      );
      expect(
        (await cancelWith([
          {'ok': false, 'error': 'permission_denied'},
        ])).$1.status,
        StorefrontMediaActionStatus.denied,
      );
      // Defensive: a stale replay is never read as "discarded".
      expect(
        (await cancelWith([
          {'ok': false, 'error': 'stale_request'},
        ])).$1.status,
        StorefrontMediaActionStatus.staleRequest,
      );
    });

    test('unknown outcome re-lists: staged row gone => ok', () async {
      final (r, t) = await cancelWith(
        [_timeout, _timeout],
        list: [
          _list([_row()]),
        ],
      );
      expect(r.status, StorefrontMediaActionStatus.ok);
      final calls = t.callsTo('cancel_storefront_media');
      expect(calls, hasLength(2));
      expect(calls[0]['p_client_request_id'], calls[1]['p_client_request_id']);
    });

    test(
      'unknown outcome re-lists: still staged => uncertain + list',
      () async {
        final (r, _) = await cancelWith(
          [_timeout, _timeout],
          list: [
            _list([_row(id: _m2, state: 'staged')]),
          ],
        );
        expect(r.status, StorefrontMediaActionStatus.uncertain);
        expect(r.recovered!.byId(_m2)!.isStaged, isTrue);
      },
    );

    test('unknown outcome re-lists: row is LIVE => mediaPublished', () async {
      final (r, _) = await cancelWith(
        [_timeout, _timeout],
        list: [
          _list([_row(id: _m2)]),
        ],
      );
      expect(r.status, StorefrontMediaActionStatus.mediaPublished);
    });
  });
}
