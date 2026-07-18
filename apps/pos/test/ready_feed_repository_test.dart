import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/ready_feed_repository.dart';

/// PSC-001A — the ready-feed client: exact RPC request shape, VERBATIM tuple
/// cursor round-trip, and strict fail-closed parsing (a malformed envelope,
/// row, or partial cursor is refused — never defaulted, never coerced).

const _u1 = '0a000000-0000-4000-8000-000000000001';
const _u2 = '0a000000-0000-4000-8000-000000000002';
const _o1 = '0b000000-0000-4000-8000-000000000001';

Map<String, Object?> _row({
  String type = 'initial_order',
  String id = _u1,
  String orderId = _o1,
  String readyAt = '2026-07-23T10:00:00.123456+00:00',
  int? round,
  int revision = 3,
}) => {
  'work_unit_type': type,
  'work_unit_id': id,
  'order_id': orderId,
  'order_code': '#A1B2C3',
  'round_number': round,
  'order_type': 'dine_in',
  'table_label': 'T4',
  'ready_at': readyAt,
  'work_unit_status': 'ready',
  'parent_order_status': 'preparing',
  'revision': revision,
};

Map<String, Object?> _envelope({
  List<Object?>? ready,
  bool hasMore = false,
  Object? nextCursor,
  Object? serverTs = '2026-07-23T10:00:05+00:00',
}) => {
  'ok': true,
  'entity': 'ready_feed',
  'server_ts': serverTs,
  'ready': ready ?? [_row()],
  'has_more': hasMore,
  'next_cursor': nextCursor,
};

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.response);
  Object? response;
  final List<Map<String, dynamic>> calls = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    expect(function, 'pos_ready_feed');
    calls.add(params);
    return response;
  }
}

RealReadyFeedRepository _repo(_FakeTransport transport) =>
    RealReadyFeedRepository(
      transport,
      const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
    );

void main() {
  test('the request carries the active session/device, the FULL tuple cursor '
      'VERBATIM, and the limit; a cursorless request sends all-null', () async {
    final transport = _FakeTransport(
      _envelope(
        hasMore: true,
        nextCursor: {
          'ready_at': '2026-07-23T10:00:00.123456+00:00',
          'work_unit_type': 'initial_order',
          'id': _u1,
        },
      ),
    );
    final repo = _repo(transport);
    final first = await repo.fetch();
    var params = transport.calls.single;
    expect(params['p_pin_session_id'], 'pin-1');
    expect(params['p_device_id'], 'dev-1');
    expect(params['p_since_ready_at'], isNull);
    expect(params['p_since_type'], isNull);
    expect(params['p_since_id'], isNull);
    expect(params['p_limit'], 100);
    // The returned cursor round-trips VERBATIM — precision untouched.
    await repo.fetch(cursor: first.nextCursor, limit: 50);
    params = transport.calls.last;
    expect(params['p_since_ready_at'], '2026-07-23T10:00:00.123456+00:00');
    expect(params['p_since_type'], 'initial_order');
    expect(params['p_since_id'], _u1);
    expect(params['p_limit'], 50);
  });

  test('a valid page parses: rows, has_more, server_ts, cursor', () async {
    final transport = _FakeTransport(
      _envelope(
        ready: [
          _row(),
          _row(type: 'service_round', id: _u2, round: 2),
        ],
      ),
    );
    final page = await _repo(transport).fetch();
    expect(page.rows, hasLength(2));
    expect(page.rows.first.identityKey, 'initial_order|$_u1');
    expect(page.rows.last.identityKey, 'service_round|$_u2');
    expect(page.rows.last.roundNumber, 2);
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
    expect(page.serverTs, '2026-07-23T10:00:05+00:00');
  });

  test('no session/transport → session failure without any request', () async {
    const repo = RealReadyFeedRepository(null, null);
    await expectLater(
      repo.fetch(),
      throwsA(
        isA<PosReadyFeedException>().having(
          (e) => e.failure,
          'failure',
          PosReadyFeedFailure.session,
        ),
      ),
    );
  });

  test('server security refusals map to the STOP-polling failure', () async {
    for (final error in [
      'invalid_session',
      'invalid_device_type',
      'permission_denied',
    ]) {
      final transport = _FakeTransport({'ok': false, 'error': error});
      await expectLater(
        _repo(transport).fetch(),
        throwsA(
          isA<PosReadyFeedException>().having(
            (e) => e.failure,
            'failure',
            PosReadyFeedFailure.session,
          ),
        ),
        reason: error,
      );
    }
  });

  test(
    'a server-rejected request shape (invalid_cursor/invalid_limit) is the '
    'distinct REJECTED failure — never a silent cursorless restart',
    () async {
      for (final error in ['invalid_cursor', 'invalid_limit']) {
        final transport = _FakeTransport({'ok': false, 'error': error});
        await expectLater(
          _repo(transport).fetch(),
          throwsA(
            isA<PosReadyFeedException>().having(
              (e) => e.failure,
              'failure',
              PosReadyFeedFailure.rejected,
            ),
          ),
          reason: error,
        );
      }
    },
  );

  test('one malformed row rejects the WHOLE page (atomic — a half-parsed page '
      'would advance the cursor past unstored rows)', () async {
    final malformedRows = <Map<String, Object?>>[
      _row(type: 'mystery_unit'), // unknown type is never coerced
      _row(id: 'not-a-uuid'),
      _row(readyAt: 'yesterday-ish'),
      _row(revision: 0),
      _row(type: 'service_round', round: null), // a round must name its number
      _row(round: 2), // an initial unit must NOT carry one
      (_row()..remove('work_unit_status')),
      (_row()..remove('parent_order_status')),
      (_row()..remove('order_code')),
    ];
    for (final bad in malformedRows) {
      final transport = _FakeTransport(
        _envelope(
          ready: [
            _row(id: _u2),
            bad,
          ],
        ),
      );
      await expectLater(
        _repo(transport).fetch(),
        throwsA(
          isA<PosReadyFeedException>().having(
            (e) => e.failure,
            'failure',
            PosReadyFeedFailure.malformed,
          ),
        ),
        reason: '$bad',
      );
    }
  });

  test('a PARTIAL next_cursor is refused (all-three-or-none), and has_more '
      'without a cursor cannot be followed', () async {
    final partial = _FakeTransport(
      _envelope(
        nextCursor: {'ready_at': '2026-07-23T10:00:00+00:00', 'id': _u1},
      ),
    );
    await expectLater(
      _repo(partial).fetch(),
      throwsA(
        isA<PosReadyFeedException>().having(
          (e) => e.failure,
          'failure',
          PosReadyFeedFailure.malformed,
        ),
      ),
    );
    final noCursor = _FakeTransport(_envelope(hasMore: true));
    await expectLater(
      _repo(noCursor).fetch(),
      throwsA(
        isA<PosReadyFeedException>().having(
          (e) => e.failure,
          'failure',
          PosReadyFeedFailure.malformed,
        ),
      ),
    );
  });

  test(
    'a malformed envelope (server_ts / ready / has_more) is refused',
    () async {
      for (final bad in [
        _envelope(serverTs: null),
        _envelope(serverTs: 'not-a-time'),
        {
          'ok': true,
          'server_ts': '2026-07-23T10:00:05+00:00',
          'ready': 'x',
          'has_more': false,
        },
        {
          'ok': true,
          'server_ts': '2026-07-23T10:00:05+00:00',
          'ready': <Object?>[],
          'has_more': 'yes',
        },
        'not-a-map',
      ]) {
        final transport = _FakeTransport(bad);
        await expectLater(
          _repo(transport).fetch(),
          throwsA(isA<PosReadyFeedException>()),
          reason: '$bad',
        );
      }
    },
  );

  test('two rows sharing one ready_at both survive the parse (the tuple, '
      'never ready_at alone, is the ordering identity)', () async {
    const sharedAt = '2026-07-23T10:00:00+00:00';
    final transport = _FakeTransport(
      _envelope(
        ready: [
          _row(readyAt: sharedAt),
          _row(type: 'service_round', id: _u2, round: 2, readyAt: sharedAt),
        ],
      ),
    );
    final page = await _repo(transport).fetch();
    expect(page.rows.map((r) => r.identityKey).toSet(), hasLength(2));
    expect(page.rows.first.readyAt, page.rows.last.readyAt);
  });
}
