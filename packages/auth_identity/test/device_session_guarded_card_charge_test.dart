// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: the device-session guard forwards the
// card Edge capability (execution packet §5.1 and §5.3). A blocked guard
// refuses before the Edge invocation; an allowed one hands the exchange to its
// inner transport exactly once and makes the inner transport ask it again at
// the HTTP handoff. No network: the inner transports are in-memory spies.
import 'dart:async';

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

import 'fake_rpc_transport.dart';

/// An inner card-capable transport that records what the guard hands it.
final class _CardSpy
    implements SyncRpcTransport, AuthenticatedCardChargeTransport {
  final bodies = <Map<String, dynamic>>[];
  final checks = <bool Function()?>[];
  final rpcCalls = <String>[];
  CardChargeTransportResult answer = CardChargeAnswered(const {
    'ok': true,
    'attempt_id': 'cccccccc-cccc-4ccc-accc-cccccccccccc',
  });

  @override
  Future<CardChargeTransportResult> sendCardCharge(
    Map<String, dynamic> body, {
    bool Function()? isCurrent,
  }) async {
    bodies.add(body);
    checks.add(isCurrent);
    return answer;
  }

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    rpcCalls.add(function);
    return const {'ok': true};
  }
}

Map<String, dynamic> _body() => <String, dynamic>{
  'action': 'start',
  'pin_session_id': 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
  'device_id': 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',
  'device_session_token': 'synthetic-device-proof',
  'attempt_id': 'cccccccc-cccc-4ccc-accc-cccccccccccc',
  'mode': 'test',
  'amount_minor': 1200,
  'currency_code': 'ILS',
};

Matcher _notSent(CardChargeFailureReason reason) =>
    isA<CardChargeTransportFailure>()
        .having((f) => f.kind, 'kind', CardChargeFailureKind.notSent)
        .having((f) => f.reason, 'reason', reason);

void main() {
  test('the guard implements the capability', () {
    expect(
      DeviceSessionGuardedTransport(_CardSpy()),
      isA<AuthenticatedCardChargeTransport>(),
    );
  });

  test('a blocked guard refuses before the Edge invocation: notSent, the '
      'inner transport never called', () async {
    final spy = _CardSpy();
    final guard = DeviceSessionGuardedTransport(spy)..block();
    expect(
      await guard.sendCardCharge(_body()),
      _notSent(CardChargeFailureReason.deviceSessionUnverified),
    );
    expect(spy.bodies, isEmpty);
  });

  test('an allowed guard forwards exactly once: the same body object and the '
      'inner result unchanged', () async {
    final spy = _CardSpy();
    final guard = DeviceSessionGuardedTransport(spy);
    final body = _body();
    final result = await guard.sendCardCharge(body);
    expect(spy.bodies, hasLength(1));
    expect(identical(spy.bodies.single, body), isTrue);
    expect(identical(result, spy.answer), isTrue);
  });

  test('the handoff check follows the guard: a block after the call started '
      'refuses at the handoff, an allow restores it', () async {
    final spy = _CardSpy();
    final guard = DeviceSessionGuardedTransport(spy);
    await guard.sendCardCharge(_body());
    final check = spy.checks.single;
    expect(check, isNotNull);
    expect(check!(), isTrue);
    guard.block();
    expect(check(), isFalse);
    guard.allow();
    expect(check(), isTrue);
  });

  test('a caller check is combined with the guard: both must hold', () async {
    final spy = _CardSpy();
    final guard = DeviceSessionGuardedTransport(spy);
    var callerOk = true;
    await guard.sendCardCharge(_body(), isCurrent: () => callerOk);
    final check = spy.checks.single!;
    expect(check(), isTrue);
    callerOk = false;
    expect(check(), isFalse);
    callerOk = true;
    guard.block();
    expect(check(), isFalse);
  });

  test('an inner transport without the capability refuses: notSent, nothing '
      'invoked', () async {
    final inner = FakeRpcTransport(value: const {'ok': true});
    final guard = DeviceSessionGuardedTransport(inner);
    expect(
      await guard.sendCardCharge(_body()),
      _notSent(CardChargeFailureReason.capabilityUnavailable),
    );
    expect(inner.invocations, 0);
  });

  test('block then allow never replays a refused card exchange', () async {
    final spy = _CardSpy();
    final guard = DeviceSessionGuardedTransport(spy)..block();
    await guard.sendCardCharge(_body());
    guard.allow();
    await Future<void>.delayed(Duration.zero);
    expect(spy.bodies, isEmpty);
    await guard.sendCardCharge(_body());
    expect(spy.bodies, hasLength(1));
  });

  test('every other guarded call behaves as before', () async {
    final spy = _CardSpy();
    final guard = DeviceSessionGuardedTransport(spy)..block();
    await guard.invoke('heartbeat_device_session', {});
    expect(spy.rpcCalls, ['heartbeat_device_session']);
    await expectLater(
      guard.invoke('sync_push', {}),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.code,
          'code',
          'device_session_unverified',
        ),
      ),
    );
    expect(spy.rpcCalls, ['heartbeat_device_session']);
  });
}
