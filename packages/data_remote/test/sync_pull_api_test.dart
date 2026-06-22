import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

/// A fake transport that returns a canned decoded result or throws a typed
/// transport error — so `SyncPullApi` is tested with NO live Supabase (A1).
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport.returns(this._result);
  _FakeTransport.throwsKind(SyncTransportErrorKind kind, {String? code})
    : _result = null,
      _error = SyncTransportException(kind, code: code, message: 'boom');

  Object? _result;
  SyncTransportException? _error;

  String? lastFunction;
  Map<String, dynamic>? lastParams;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    lastFunction = function;
    lastParams = params;
    final err = _error;
    if (err != null) throw err;
    return _result;
  }
}

Map<String, dynamic> _okEnvelope() => {
  'ok': true,
  'server_ts': '2026-06-22T10:00:00+00:00',
  'changes': {
    'orders': {
      'rows': [
        {'id': 'o1', 'status': 'preparing'},
      ],
      'next_cursor': {'updated_at': '2026-06-22T09:59:00+00:00', 'id': 'o1'},
      'has_more': false,
    },
  },
  'operation_statuses': {
    'rows': <Map<String, dynamic>>[],
    'next_cursor': null,
    'has_more': false,
  },
};

void main() {
  const session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

  group('SyncPullApi.pull', () {
    test('builds the exact RPC params and parses a success envelope', () async {
      final transport = _FakeTransport.returns(_okEnvelope());
      final api = SyncPullApi(transport);

      final res = await api.pull(
        session,
        const SyncPullRequest(
          entities: ['orders', 'order_items', 'order_item_modifiers'],
          cursors: {
            'orders': SyncCursor(
              updatedAt: '2026-06-22T09:00:00+00:00',
              id: 'oX',
            ),
          },
          limit: 250,
        ),
      );

      expect(transport.lastFunction, 'sync_pull');
      expect(transport.lastParams, {
        'p_pin_session_id': 'pin-1',
        'p_device_id': 'dev-1',
        'p_entities': ['orders', 'order_items', 'order_item_modifiers'],
        'p_cursors': {
          'orders': {'updated_at': '2026-06-22T09:00:00+00:00', 'id': 'oX'},
        },
        'p_limit': 250,
      });

      expect(res.isSuccess, isTrue);
      final ok = (res as Success<SyncPullResponse, SyncFailure>).value;
      expect(ok.changes['orders']!.rows.single['id'], 'o1');
    });

    test('42501 / auth -> ReauthRequiredFailure', () async {
      final api = SyncPullApi(
        _FakeTransport.throwsKind(SyncTransportErrorKind.auth, code: '42501'),
      );
      final res = await api.pull(session, const SyncPullRequest());
      expect(res.isFailure, isTrue);
      expect(
        (res as Failure<SyncPullResponse, SyncFailure>).failure,
        isA<ReauthRequiredFailure>(),
      );
    });

    test('transient -> TransientFailure', () async {
      final api = SyncPullApi(
        _FakeTransport.throwsKind(SyncTransportErrorKind.transient),
      );
      final res = await api.pull(session, const SyncPullRequest());
      expect(
        (res as Failure<SyncPullResponse, SyncFailure>).failure,
        isA<TransientFailure>(),
      );
    });

    test('server -> ServerFailure', () async {
      final api = SyncPullApi(
        _FakeTransport.throwsKind(SyncTransportErrorKind.server),
      );
      final res = await api.pull(session, const SyncPullRequest());
      expect(
        (res as Failure<SyncPullResponse, SyncFailure>).failure,
        isA<ServerFailure>(),
      );
    });

    test('malformed envelope -> InvalidResponseFailure (fails safe)', () async {
      final api = SyncPullApi(_FakeTransport.returns({'ok': false}));
      final res = await api.pull(session, const SyncPullRequest());
      expect(
        (res as Failure<SyncPullResponse, SyncFailure>).failure,
        isA<InvalidResponseFailure>(),
      );
    });

    test(
      'null entities serialises as p_entities: null (server picks role set)',
      () async {
        final transport = _FakeTransport.returns(_okEnvelope());
        final api = SyncPullApi(transport);
        await api.pull(session, const SyncPullRequest());
        expect(transport.lastParams!['p_entities'], isNull);
        expect(transport.lastParams!['p_cursors'], <String, dynamic>{});
        expect(transport.lastParams!['p_limit'], 500);
      },
    );

    test('p_limit is clamped to the server range [1, 1000] (A5)', () async {
      final transport = _FakeTransport.returns(_okEnvelope());
      final api = SyncPullApi(transport);

      await api.pull(session, const SyncPullRequest(limit: 5000));
      expect(transport.lastParams!['p_limit'], 1000);

      await api.pull(session, const SyncPullRequest(limit: 0));
      expect(transport.lastParams!['p_limit'], 1);
    });
  });
}
