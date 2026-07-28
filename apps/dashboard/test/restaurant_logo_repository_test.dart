import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// PRINT-BRANDING-LOGO-001 (§7/§9) — the repository reconciles an AMBIGUOUS write
/// outcome (lost RPC response) via an idempotent retry with a STABLE request id,
/// then a readback — so it never reports a delete-the-orphan verdict for a write
/// that actually committed.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport({this.setResponses = const [], this.getResponse});

  /// Per set-call: a Map (a response) or a SyncTransportException (a throw).
  final List<Object> setResponses;

  /// The readback response: a Map or a SyncTransportException.
  final Object? getResponse;

  final List<Map<String, dynamic>> setCalls = [];
  int getCalls = 0;
  int _i = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'set_restaurant_receipt_logo') {
      setCalls.add(params);
      final r =
          setResponses[_i < setResponses.length ? _i : setResponses.length - 1];
      _i++;
      if (r is SyncTransportException) throw r;
      return r;
    }
    if (function == 'get_restaurant_receipt_logo') {
      getCalls++;
      final g = getResponse;
      if (g is SyncTransportException) throw g;
      return g;
    }
    throw StateError('unexpected $function');
  }
}

final _timeout = const SyncTransportException(
  SyncTransportErrorKind.transient,
  message: 'timeout',
);

Map<String, dynamic> _okResp(String? path, bool enabled, int version) => {
  'ok': true,
  'receipt_logo_path': path,
  'receipt_logo_enabled': enabled,
  'receipt_logo_version': version,
};

Map<String, dynamic> _getResp(String? path, bool enabled, int version) => {
  'ok': true,
  'receipt_logo_path': path,
  'receipt_logo_enabled': enabled,
  'receipt_logo_version': version,
  'can_manage': true,
};

SupabaseRestaurantLogoRepository _repo(_FakeTransport t) =>
    SupabaseRestaurantLogoRepository(
      transport: t,
      organizationId: 'org1',
      restaurantId: 'rest1',
      nonce: () => 42, // deterministic request id
    );

void main() {
  test('a responded error is definitive (no retry)', () async {
    final t = _FakeTransport(
      setResponses: [
        {'ok': false, 'error': 'permission_denied'},
      ],
    );
    final r = await _repo(t).save(path: 'p', enabled: true, expectedVersion: 0);
    expect(r.status, RestaurantLogoWriteStatus.denied);
    expect(
      t.setCalls.length,
      1,
      reason: 'no retry after a definitive response',
    );
  });

  test('a responded version_conflict is definitive (no retry)', () async {
    final t = _FakeTransport(
      setResponses: [
        {
          'ok': false,
          'error': 'version_conflict',
          'receipt_logo_path': 'other',
          'receipt_logo_enabled': true,
          'receipt_logo_version': 9,
        },
      ],
    );
    final r = await _repo(t).save(path: 'p', enabled: true, expectedVersion: 0);
    expect(r.status, RestaurantLogoWriteStatus.conflict);
    expect(r.settings?.version, 9);
    expect(t.setCalls.length, 1);
  });

  test('timeout then idempotent retry REPLAYS the committed result', () async {
    final t = _FakeTransport(
      setResponses: [_timeout, _okResp('newp', true, 1)],
    );
    final r = await _repo(
      t,
    ).save(path: 'newp', enabled: true, expectedVersion: 0);
    expect(r.status, RestaurantLogoWriteStatus.ok);
    expect(r.settings?.version, 1);
    expect(t.setCalls.length, 2);
    // The retry uses the SAME idempotency id (server replays, no double bump).
    expect(
      t.setCalls[0]['p_client_request_id'],
      t.setCalls[1]['p_client_request_id'],
    );
    expect(t.getCalls, 0, reason: 'the retry answered — no readback needed');
  });

  test('both attempts time out, readback CONFIRMS commit => ok', () async {
    final t = _FakeTransport(
      setResponses: [_timeout, _timeout],
      getResponse: _getResp('newp', true, 1), // version advanced to intended
    );
    final r = await _repo(
      t,
    ).save(path: 'newp', enabled: true, expectedVersion: 0);
    expect(r.status, RestaurantLogoWriteStatus.ok);
    expect(t.getCalls, 1);
  });

  test(
    'both time out, readback shows UNCHANGED version => notCommitted',
    () async {
      final t = _FakeTransport(
        setResponses: [_timeout, _timeout],
        getResponse: _getResp('oldp', true, 0), // never advanced
      );
      final r = await _repo(
        t,
      ).save(path: 'newp', enabled: true, expectedVersion: 0);
      expect(r.status, RestaurantLogoWriteStatus.notCommitted);
    },
  );

  test(
    'both time out, readback shows a DIFFERENT newer change => conflict',
    () async {
      final t = _FakeTransport(
        setResponses: [_timeout, _timeout],
        getResponse: _getResp('someone-else', true, 5),
      );
      final r = await _repo(
        t,
      ).save(path: 'newp', enabled: true, expectedVersion: 0);
      expect(r.status, RestaurantLogoWriteStatus.conflict);
    },
  );

  test('both time out AND readback fails => uncertain', () async {
    final t = _FakeTransport(
      setResponses: [_timeout, _timeout],
      getResponse: _timeout,
    );
    final r = await _repo(
      t,
    ).save(path: 'newp', enabled: true, expectedVersion: 0);
    expect(r.status, RestaurantLogoWriteStatus.uncertain);
    expect(r.settings, isNull);
  });
}
