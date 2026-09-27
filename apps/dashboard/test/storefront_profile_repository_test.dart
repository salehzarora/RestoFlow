import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_rpc.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// STOREFRONT-PUBLISH-001 — the profile repository's envelope mapping and its
/// lost-response rule: ONE stable request id per logical save, retried EXACTLY
/// once on an ambiguous transport failure, then a readback reconciliation.
const _org = '11111111-1111-4111-8111-111111111111';
const _rest = '22222222-2222-4222-8222-222222222222';
const _branch = '33333333-3333-4333-8333-333333333333';

/// Scripted per-function replies: a Map/other value is RETURNED, a
/// [SyncTransportException] is THROWN. The last reply repeats.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport({this.reads = const [], this.writes = const []});

  final List<Object?> reads;
  final List<Object?> writes;

  final List<Map<String, dynamic>> readCalls = [];
  final List<Map<String, dynamic>> writeCalls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    final List<Object?> script;
    final List<Map<String, dynamic>> calls;
    switch (function) {
      case 'get_restaurant_storefront_profile':
        script = reads;
        calls = readCalls;
      case 'set_restaurant_storefront_profile':
        script = writes;
        calls = writeCalls;
      default:
        throw StateError('unexpected $function');
    }
    calls.add(params);
    if (script.isEmpty) throw StateError('no scripted reply for $function');
    final r =
        script[calls.length - 1 < script.length
            ? calls.length - 1
            : script.length - 1];
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
  message: 'caller has no active membership covering the restaurant',
);

Map<String, dynamic> _profile({
  int version = 3,
  String slug = 'maps-burger',
  bool published = false,
  String displayName = 'Maps Burger',
  Object? hours,
}) => {
  'restaurant_id': _rest,
  'storefront_branch_id': _branch,
  'slug': slug,
  'display_name': displayName,
  'tagline': null,
  'public_city': 'Haifa',
  'public_address': null,
  'public_phone': '+972501234567',
  'primary_color': '#13322a',
  'accent_color': '#e07b2c',
  'visual_preset': 'dark',
  'locale_default': 'ar',
  'card_mode': 'list',
  'motion': 'full',
  'pickup_enabled': true,
  'delivery_enabled': false,
  'ordering_enabled': false,
  'paused_until': null,
  'pause_reason': null,
  'opening_hours':
      hours ??
      {
        'weekly': [
          {'dow': 0, 'open': '09:00', 'close': '17:00'},
          {'dow': 5, 'open': '18:00', 'close': '02:00'},
        ],
        'exceptions': [
          {'date': '2026-10-02', 'closed': true},
        ],
      },
  'logo_media_id': null,
  'hero_media_id': null,
  'is_published': published,
  'version': version,
  'created_at': '2026-09-20T10:00:00.123456+00:00',
  'updated_at': '2026-09-21T10:00:00+00:00',
};

Map<String, dynamic> _derived({
  List<String> blockers = const [],
  String? timezone = 'Asia/Jerusalem',
}) => {
  'timezone': timezone,
  'currency_code': 'ILS',
  'tax': {'enabled': false, 'rate_bp': 0, 'mode': 'exclusive'},
  'publish_ready': blockers.isEmpty,
  'publish_blockers': blockers,
  'media_prefix': '0123456789abcdef0123456789abcdef',
};

Map<String, dynamic> _read({
  bool exists = true,
  int version = 3,
  Map<String, dynamic>? profile,
  Map<String, dynamic>? derived,
}) => {
  'ok': true,
  'entity': 'restaurant_storefront_profile',
  'restaurant_id': _rest,
  'exists': exists,
  'version': exists ? version : 0,
  'profile': exists ? (profile ?? _profile(version: version)) : null,
  'derived': derived ?? _derived(),
};

Map<String, dynamic> _ok(int version, {bool published = false}) => {
  'ok': true,
  'idempotent_replay': false,
  'entity': 'restaurant_storefront_profile',
  'restaurant_id': _rest,
  'version': version,
  'slug': 'maps-burger',
  'is_published': published,
};

SupabaseStorefrontProfileRepository _repo(_FakeTransport t, {int nonce = 7}) =>
    SupabaseStorefrontProfileRepository(
      transport: t,
      organizationId: _org,
      restaurantId: _rest,
      nonce: () => nonce,
    );

void main() {
  group('read', () {
    test('ok + exists decodes the profile and the derived facts', () async {
      final t = _FakeTransport(reads: [_read()]);
      final r = await _repo(t).read();
      expect(r.status, StorefrontReadStatus.ok);
      expect(r.exists, isTrue);
      expect(r.version, 3);
      final p = r.profile!;
      expect(p.slug, 'maps-burger');
      expect(p.storefrontBranchId, _branch);
      expect(p.visualPreset, StorefrontVisualPreset.dark);
      expect(p.localeDefault, StorefrontLocale.ar);
      expect(p.cardMode, StorefrontCardMode.list);
      expect(p.motion, StorefrontMotion.full);
      expect(p.publicPhone, '+972501234567');
      expect(p.openingHours.weekly, hasLength(2));
      expect(p.openingHours.weekly[1].crossesMidnight, isTrue);
      expect(p.openingHours.exceptions.single.closed, isTrue);
      expect(r.derived!.timezone, 'Asia/Jerusalem');
      expect(r.derived!.publishReady, isTrue);
      expect(r.derived!.publishBlockers, isEmpty);
      expect(r.derived!.tax!.rateBp, 0);
      expect(t.readCalls.single, {
        'p_organization_id': _org,
        'p_restaurant_id': _rest,
      });
    });

    test('exists:false is ok with version 0 and no profile', () async {
      final t = _FakeTransport(
        reads: [
          _read(
            exists: false,
            derived: _derived(
              timezone: null,
              blockers: ['slug_missing', 'branch_missing', 'hours_missing'],
            ),
          ),
        ],
      );
      final r = await _repo(t).read();
      expect(r.status, StorefrontReadStatus.ok);
      expect(r.exists, isFalse);
      expect(r.version, 0);
      expect(r.profile, isNull);
      expect(r.derived!.timezone, isNull);
      expect(r.derived!.publishReady, isFalse);
      expect(r.derived!.publishBlockers, [
        'slug_missing',
        'branch_missing',
        'hours_missing',
      ]);
    });

    test('not_found => denied (no fields, no leak)', () async {
      final t = _FakeTransport(
        reads: [
          {
            'ok': false,
            'error': 'not_found',
            'entity': 'restaurant_storefront_profile',
          },
        ],
      );
      final r = await _repo(t).read();
      expect(r.status, StorefrontReadStatus.denied);
      expect(r.profile, isNull);
      expect(r.derived, isNull);
    });

    test('transport failure => unavailable', () async {
      final r = await _repo(_FakeTransport(reads: [_timeout])).read();
      expect(r.status, StorefrontReadStatus.unavailable);
    });

    test('42501 => unavailable carrying the SQLSTATE', () async {
      final r = await _repo(_FakeTransport(reads: [_denied42501])).read();
      expect(r.status, StorefrontReadStatus.unavailable);
      expect(r.code, '42501');
    });

    test('an unrecognised error envelope => unavailable', () async {
      final r = await _repo(
        _FakeTransport(
          reads: [
            {'ok': false, 'error': 'something_new'},
          ],
        ),
      ).read();
      expect(r.status, StorefrontReadStatus.unavailable);
    });

    Future<StorefrontProfileRead> readWith(Object? envelope) =>
        _repo(_FakeTransport(reads: [envelope])).read();

    test(
      'a malformed field is a TYPED decode failure, never a crash',
      () async {
        final badPreset = _read(
          profile: {..._profile(), 'visual_preset': 'neon'},
        );
        final r1 = await readWith(badPreset);
        expect(r1.status, StorefrontReadStatus.malformed);
        expect(r1.decodeError!.field, 'profile.visual_preset');

        final badHours = _read(
          profile: _profile(
            hours: {
              'weekly': <Object>[],
              'exceptions': [
                {
                  'date': '2026-10-02',
                  'closed': false,
                  'open': '09:00',
                  'close': '10:00',
                },
              ],
            },
          ),
        );
        final r2 = await readWith(badHours);
        expect(r2.status, StorefrontReadStatus.malformed);
        expect(r2.decodeError!.field, 'profile.opening_hours');

        final badVersion = _read(profile: {..._profile(), 'version': '3'});
        expect(
          (await readWith(badVersion)).decodeError!.field,
          'profile.version',
        );

        final badTimestamp = _read(
          profile: {..._profile(), 'paused_until': 'tomorrow'},
        );
        expect(
          (await readWith(badTimestamp)).decodeError!.field,
          'profile.paused_until',
        );

        final badBlockers = _read(
          derived: {
            ..._derived(),
            'publish_blockers': [1],
          },
        );
        expect(
          (await readWith(badBlockers)).status,
          StorefrontReadStatus.malformed,
        );

        final disagreeing = _read(
          derived: {
            ..._derived(blockers: ['no_live_item']),
            'publish_ready': true,
          },
        );
        expect(
          (await readWith(disagreeing)).decodeError!.field,
          'derived.publish_ready',
        );
      },
    );

    test('stored hours with an entry MISSING a key (the SQL check lets it '
        'through) read ok and flagged, not malformed', () async {
      final r = await readWith(
        _read(
          profile: _profile(
            hours: {
              'weekly': [
                {'dow': 1, 'open': '09:00'},
                {'dow': 2, 'open': '10:00', 'close': '14:00'},
              ],
            },
          ),
        ),
      );
      expect(r.status, StorefrontReadStatus.ok);
      expect(r.profile!.openingHours.hasUnreadableEntries, isTrue);
      expect(r.profile!.openingHours.weekly, hasLength(1));
    });

    test('envelope-level inconsistencies are malformed', () async {
      expect(
        (await readWith('not a map')).status,
        StorefrontReadStatus.malformed,
      );
      expect(
        (await readWith({..._read(), 'exists': 'yes'})).decodeError!.field,
        'exists',
      );
      // Top-level version disagrees with the row's version.
      expect(
        (await readWith({..._read(), 'version': 4})).decodeError!.field,
        'profile.version',
      );
      // exists:false must come with version 0 and no profile.
      expect(
        (await readWith({..._read(exists: false), 'version': 2})).status,
        StorefrontReadStatus.malformed,
      );
      // An envelope for another restaurant is never shown.
      expect(
        (await readWith({
          ..._read(),
          'restaurant_id': '99999999-9999-4999-8999-999999999999',
        })).decodeError!.field,
        'restaurant_id',
      );
      expect(
        (await readWith({..._read(), 'derived': null})).decodeError!.field,
        'derived',
      );
    });
  });

  group('save — envelopes', () {
    test('ok: sends the CAS params and reports the new version', () async {
      final t = _FakeTransport(writes: [_ok(4)]);
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'display_name': 'Maps'});
      expect(r.status, StorefrontWriteStatus.ok);
      expect(r.version, 4);
      expect(r.isPublished, isFalse);
      expect(t.writeCalls, hasLength(1));
      final params = t.writeCalls.single;
      expect(params.keys.toSet(), {
        'p_client_request_id',
        'p_organization_id',
        'p_restaurant_id',
        'p_expected_version',
        'p_patch',
      });
      expect(isCanonicalUuid(params['p_client_request_id'] as String), isTrue);
      expect(r.requestId, params['p_client_request_id']);
      expect(params['p_expected_version'], 3);
      expect(params['p_patch'], {'display_name': 'Maps'});
      expect(t.readCalls, isEmpty, reason: 'callers re-read themselves');
    });

    test('version_conflict => conflict carrying the current version', () async {
      final t = _FakeTransport(
        writes: [
          {
            'ok': false,
            'error': 'version_conflict',
            'entity': 'restaurant_storefront_profile',
            'restaurant_id': _rest,
            'version': 9,
            'slug': 'maps-burger',
            'is_published': true,
          },
        ],
      );
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.conflict);
      expect(r.version, 9);
      expect(r.isPublished, isTrue);
      expect(t.writeCalls, hasLength(1), reason: 'a typed answer is final');
    });

    test('permission_denied => denied', () async {
      final t = _FakeTransport(
        writes: [
          {'ok': false, 'error': 'permission_denied'},
        ],
      );
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.denied);
      expect(t.writeCalls, hasLength(1));
    });

    test('invalid carries reason + field + detail blockers', () async {
      final t = _FakeTransport(
        writes: [
          {
            'ok': false,
            'error': 'invalid',
            'reason': 'publish_precondition',
            'detail': ['timezone_missing', 'no_live_item'],
            'entity': 'restaurant_storefront_profile',
          },
          {
            'ok': false,
            'error': 'invalid',
            'reason': 'unknown_field',
            'field': 'ordering_enabled',
          },
        ],
      );
      final repo = _repo(t);
      final r1 = await repo.save(
        expectedVersion: 3,
        patch: {'is_published': true},
      );
      expect(r1.status, StorefrontWriteStatus.invalid);
      expect(r1.reason, 'publish_precondition');
      expect(r1.blockers, ['timezone_missing', 'no_live_item']);
      expect(r1.refusedLocally, isFalse);
      final r2 = await repo.save(expectedVersion: 3, patch: {'tagline': 'y'});
      expect(r2.reason, 'unknown_field');
      expect(r2.field, 'ordering_enabled');
      expect(t.writeCalls, hasLength(2), reason: 'no retries on typed invalid');
    });

    test('every writer reason is kept verbatim', () async {
      for (final reason in kStorefrontInvalidReasons) {
        final t = _FakeTransport(
          writes: [
            {'ok': false, 'error': 'invalid', 'reason': reason},
          ],
        );
        final r = await _repo(
          t,
        ).save(expectedVersion: 1, patch: {'tagline': null});
        expect(r.status, StorefrontWriteStatus.invalid);
        expect(r.reason, reason);
      }
    });

    test('42501 => unavailable, definitive (no retry, no readback)', () async {
      final t = _FakeTransport(writes: [_denied42501]);
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.unavailable);
      expect(r.code, '42501');
      expect(t.writeCalls, hasLength(1));
      expect(t.readCalls, isEmpty);
    });

    test('an unrecognised error envelope => unavailable', () async {
      final t = _FakeTransport(
        writes: [
          {'ok': false, 'error': 'brand_new_error'},
        ],
      );
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.unavailable);
      expect(t.writeCalls, hasLength(1));
    });
  });

  group('save — one retry with the SAME id, then readback', () {
    void expectSameId(_FakeTransport t) {
      expect(t.writeCalls, hasLength(2));
      expect(
        t.writeCalls[0]['p_client_request_id'],
        t.writeCalls[1]['p_client_request_id'],
      );
    }

    test(
      'timeout then the retry answers (replay) => ok, no readback',
      () async {
        final t = _FakeTransport(
          writes: [
            _timeout,
            {..._ok(4), 'idempotent_replay': true},
          ],
        );
        final r = await _repo(
          t,
        ).save(expectedVersion: 3, patch: {'tagline': 'x'});
        expect(r.status, StorefrontWriteStatus.ok);
        expect(r.idempotentReplay, isTrue);
        expectSameId(t);
        expect(t.readCalls, isEmpty);
      },
    );

    test('a non-envelope answer is ambiguous too (retried)', () async {
      final t = _FakeTransport(writes: ['<html>502</html>', _ok(4)]);
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.ok);
      expectSameId(t);
    });

    test('both lost, version unchanged => notCommitted', () async {
      final t = _FakeTransport(writes: [_timeout, _timeout], reads: [_read()]);
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.notCommitted);
      expect(r.version, 3);
      expect(r.readback!.isOk, isTrue);
      expectSameId(t);
      expect(t.readCalls, hasLength(1));
    });

    test('both lost, version == expected+1 with OUR values => ok', () async {
      final t = _FakeTransport(
        writes: [_timeout, _timeout],
        reads: [_read(version: 4, profile: _profile(version: 4))],
      );
      final r = await _repo(t).save(
        expectedVersion: 3,
        patch: {
          'display_name': '  Maps Burger  ',
          'primary_color': '#13322A',
          'public_city': 'Haifa',
          'tagline': '   ',
          'storefront_branch_id': _branch.toUpperCase(),
          'is_published': false,
        },
      );
      expect(r.status, StorefrontWriteStatus.ok);
      expect(r.version, 4);
      expect(r.readback!.profile!.version, 4);
      expectSameId(t);
    });

    test(
      'both lost, version == expected+1 but NOT our values => conflict',
      () async {
        final t = _FakeTransport(
          writes: [_timeout, _timeout],
          reads: [_read(version: 4, profile: _profile(version: 4))],
        );
        final r = await _repo(
          t,
        ).save(expectedVersion: 3, patch: {'is_published': true});
        expect(r.status, StorefrontWriteStatus.conflict);
        expect(r.version, 4);
      },
    );

    test('both lost, version jumped further => conflict', () async {
      final t = _FakeTransport(
        writes: [_timeout, _timeout],
        reads: [_read(version: 6, profile: _profile(version: 6))],
      );
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'public_city': 'Haifa'});
      expect(r.status, StorefrontWriteStatus.conflict);
      expect(r.version, 6);
    });

    test('both lost and the readback fails => uncertain', () async {
      final t = _FakeTransport(writes: [_timeout, _timeout], reads: [_timeout]);
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.uncertain);
      expect(r.readback!.status, StorefrontReadStatus.unavailable);
      // What a "Try again" needs to replay THIS request verbatim.
      expect(r.requestId, t.writeCalls.first['p_client_request_id']);
      expect(r.expectedVersion, 3);
      expectSameId(t);
    });

    test('a bare HTTP status in `code` (gateway page) is ambiguous, not a '
        'database answer', () async {
      // The PostgREST client puts the HTTP status into `code` when the error
      // body is not JSON — e.g. a 502 from a proxy: the statement may have run.
      const gateway = SyncTransportException(
        SyncTransportErrorKind.server,
        code: '502',
        message: '<html>Bad gateway</html>',
      );
      final t = _FakeTransport(writes: [gateway, _ok(4)]);
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.ok);
      expectSameId(t);
    });

    test('a PostgREST code (PGRST...) is a definitive refusal', () async {
      const notFound = SyncTransportException(
        SyncTransportErrorKind.server,
        code: 'PGRST202',
        message: 'Could not find the function',
      );
      final t = _FakeTransport(writes: [notFound]);
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.unavailable);
      expect(r.code, 'PGRST202');
      expect(t.writeCalls, hasLength(1));
    });

    test('a refusal of the RETRY stays ambiguous (reconciled)', () async {
      // The first attempt may have committed before the session died.
      final t = _FakeTransport(
        writes: [_timeout, _denied42501],
        reads: [_read()],
      );
      final r = await _repo(
        t,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      expect(r.status, StorefrontWriteStatus.notCommitted);
      expect(t.readCalls, hasLength(1));
    });

    test(
      'create (expected 0): lost twice, profile still absent => notCommitted',
      () async {
        final t = _FakeTransport(
          writes: [_timeout, _timeout],
          reads: [_read(exists: false)],
        );
        final r = await _repo(t).save(
          expectedVersion: 0,
          patch: {
            'slug': 'maps-burger',
            'storefront_branch_id': _branch,
            'display_name': 'Maps Burger',
          },
        );
        expect(r.status, StorefrontWriteStatus.notCommitted);
        expect(r.version, 0);
      },
    );
  });

  group('save — local guards (no server call)', () {
    test('slug is NEVER sent when the profile exists (version > 0)', () async {
      final t = _FakeTransport(writes: [_ok(4)]);
      final r = await _repo(t).save(
        expectedVersion: 3,
        patch: {'slug': 'maps-burger', 'tagline': 'x'},
      );
      expect(r.status, StorefrontWriteStatus.invalid);
      expect(r.reason, 'slug_immutable');
      expect(r.field, 'slug');
      expect(r.refusedLocally, isTrue);
      expect(r.requestId, isNull);
      expect(t.writeCalls, isEmpty);
    });

    test('slug IS sent on create (version 0)', () async {
      final t = _FakeTransport(writes: [_ok(1)]);
      final r = await _repo(t).save(
        expectedVersion: 0,
        patch: {
          'slug': 'maps-burger',
          'storefront_branch_id': _branch,
          'display_name': 'Maps Burger',
        },
      );
      expect(r.status, StorefrontWriteStatus.ok);
      expect((t.writeCalls.single['p_patch'] as Map)['slug'], 'maps-burger');
    });

    test(
      'a key outside the allowlist (e.g. ordering_enabled) is refused',
      () async {
        final t = _FakeTransport(writes: [_ok(4)]);
        for (final key in ['ordering_enabled', 'delivery_enabled', 'version']) {
          final r = await _repo(t).save(expectedVersion: 3, patch: {key: true});
          expect(r.status, StorefrontWriteStatus.invalid);
          expect(r.reason, 'unknown_field');
          expect(r.field, key);
          expect(r.refusedLocally, isTrue);
        }
        expect(t.writeCalls, isEmpty);
      },
    );

    test(
      'a supplied request id is reused verbatim; a bad one is refused',
      () async {
        const id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
        final t = _FakeTransport(writes: [_ok(4)]);
        final r = await _repo(
          t,
        ).save(expectedVersion: 3, patch: {'tagline': 'x'}, requestId: id);
        expect(r.requestId, id);
        expect(t.writeCalls.single['p_client_request_id'], id);
        await expectLater(
          _repo(t).save(
            expectedVersion: 3,
            patch: const {},
            requestId: 'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE',
          ),
          throwsArgumentError,
        );
        expect(t.writeCalls, hasLength(1));
      },
    );

    test('request ids: deterministic per nonce, distinct per press', () async {
      final t = _FakeTransport(writes: [_ok(4)]);
      await _repo(
        t,
        nonce: 1,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      await _repo(
        t,
        nonce: 1,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      await _repo(
        t,
        nonce: 2,
      ).save(expectedVersion: 3, patch: {'tagline': 'x'});
      final ids = t.writeCalls.map((c) => c['p_client_request_id']).toList();
      expect(ids[0], ids[1]);
      expect(ids[0], isNot(ids[2]));
      expect(ids.every((id) => isCanonicalUuid(id as String)), isTrue);
    });
  });

  test('isStorefrontDatabaseErrorCode: SQLSTATE / PGRST only', () {
    for (final code in ['42501', '22P02', '40001', 'P0001', 'PGRST202']) {
      expect(isStorefrontDatabaseErrorCode(code), isTrue, reason: code);
    }
    for (final code in [null, '', '200', '500', '502', '520', 'pgrst202']) {
      expect(isStorefrontDatabaseErrorCode(code), isFalse, reason: '$code');
    }
  });

  group('storefrontProfileReflectsPatch', () {
    final profile = StorefrontProfile.fromJson({
      ..._profile(version: 4),
      'paused_until': '2026-10-01T15:00:00+00:00',
      'pause_reason': 'Renovation',
    });

    test('mirrors the writer normalisation', () {
      expect(
        storefrontProfileReflectsPatch(profile, {
          'display_name': ' Maps Burger ',
          'accent_color': '#E07B2C',
          'public_address': '',
          'paused_until': '2026-10-01T18:00:00+03:00',
          'pause_reason': 'Renovation ',
          'opening_hours': profile.openingHours.toJson(),
          'logo_media_id': null,
        }),
        isTrue,
      );
    });

    test('a different value is not ours', () {
      expect(
        storefrontProfileReflectsPatch(profile, {
          'paused_until': '2026-10-01T18:00:00+00:00',
        }),
        isFalse,
      );
      expect(
        storefrontProfileReflectsPatch(profile, {'motion': 'calm'}),
        isFalse,
      );
      expect(
        storefrontProfileReflectsPatch(profile, {
          'opening_hours': {'weekly': <Object>[], 'exceptions': <Object>[]},
        }),
        isFalse,
      );
      // Postgres btrim trims spaces only — a tab is kept.
      expect(
        storefrontProfileReflectsPatch(profile, {
          'display_name': '\tMaps Burger',
        }),
        isFalse,
      );
    });
  });
}
