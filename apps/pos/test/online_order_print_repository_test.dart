import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/online_order_print_repository.dart';
import 'online_order_inbox_fixtures.dart';

const dispatchId = '90000000-0000-4000-8000-000000000001';
const assignmentId = 'a0000000-0000-4000-8000-000000000001';
const attemptId = 'b0000000-0000-4000-8000-000000000001';

class _Transport implements SyncRpcTransport {
  Object? response;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return response;
  }
}

Map<String, Object?> result(
  String state, {
  bool authorized = false,
  bool payload = false,
}) => {
  'ok': true,
  'request_id': requestId,
  'canonical_order_id': canonicalId,
  'decision_id': decisionId,
  'dispatch_id': dispatchId,
  'printer_assignment_id': assignmentId,
  'attempt_id': state == 'claimed' ? null : attemptId,
  'state': state,
  'send_authorized': authorized,
  if (payload)
    'dispatch': {
      'id': dispatchId,
      'order_id': canonicalId,
      'dispatch_type': 'initial_order',
      'service_round_id': null,
      'payload_version': 1,
      'created_at': inboxNow.toIso8601String(),
      'claim_expires_at': inboxNow
          .add(const Duration(minutes: 1))
          .toIso8601String(),
      'payload': <String, Object?>{'v': 1, 'kind': 'initial_order'},
    },
};

void main() {
  late _Transport transport;
  late InMemoryDeviceSessionSecretStore secrets;
  var current = true;
  late RealOnlineOrderPrintRepository repo;
  setUp(() async {
    transport = _Transport();
    secrets = InMemoryDeviceSessionSecretStore();
    current = true;
    await secrets.write(
      const DeviceSessionCredential(
        deviceId: deviceId,
        sessionToken: 'private-test-token',
      ),
    );
    repo = RealOnlineOrderPrintRepository(
      transport: transport,
      session: const SyncSession(deviceId: deviceId, pinSessionId: pinId),
      secretStore: secrets,
      isCurrent: () => current,
    );
  });
  test('claim sends real device/PIN proof and ONLY request lookup', () async {
    transport.response = result('claimed', payload: true);
    final claim = await repo.claim(requestId);
    expect(claim.dispatch!.dispatchId, dispatchId);
    expect(claim.sendAuthorized, isFalse);
    expect(transport.calls.single.$1, 'pos_claim_web_order_print');
    expect(transport.calls.single.$2, {
      'p_request_id': requestId,
      'p_device_id': deviceId,
      'p_pin_session_id': pinId,
      'p_device_session_token': 'private-test-token',
    });
  });
  test(
    'fresh exact begin is the only send grant; replay is no grant',
    () async {
      transport.response = result('send_reserved', authorized: true);
      expect((await repo.begin(requestId, attemptId)).sendAuthorized, isTrue);
      transport.response = result('reconciliation_required');
      expect((await repo.begin(requestId, attemptId)).sendAuthorized, isFalse);
    },
  );
  for (final change in <String, Object?>{
    'request_id': canonicalId,
    'dispatch_id': 'invalid',
    'state': 'unexpected',
    'canonical_order_id': null,
    'printer_assignment_id': null,
    'ok': false,
  }.entries) {
    test('fails closed on malformed ${change.key}', () async {
      transport.response = result('claimed', payload: true)
        ..[change.key] = change.value;
      await expectLater(
        repo.claim(requestId),
        throwsA(isA<OnlineOrderPrintException>()),
      );
    });
  }
  test('claim can never manufacture send authority', () async {
    transport.response = result('claimed', authorized: true, payload: true);
    await expectLater(
      repo.claim(requestId),
      throwsA(isA<OnlineOrderPrintException>()),
    );
  });
  test('initial dispatch order identity is checked', () async {
    final reply = result('claimed', payload: true);
    (reply['dispatch'] as Map)['order_id'] = requestId;
    transport.response = reply;
    await expectLater(
      repo.claim(requestId),
      throwsA(isA<OnlineOrderPrintException>()),
    );
  });
  test(
    'missing or swapped device secret and stale PIN never invoke RPC',
    () async {
      await secrets.write(
        const DeviceSessionCredential(
          deviceId: canonicalId,
          sessionToken: 'different-device',
        ),
      );
      await expectLater(
        repo.claim(requestId),
        throwsA(isA<OnlineOrderPrintException>()),
      );
      expect(transport.calls, isEmpty);
      await secrets.write(
        const DeviceSessionCredential(
          deviceId: deviceId,
          sessionToken: 'private-test-token',
        ),
      );
      current = false;
      await expectLater(
        repo.claim(requestId),
        throwsA(isA<OnlineOrderPrintException>()),
      );
      expect(transport.calls, isEmpty);
    },
  );
  test(
    'finish and status use targeted contracts without dispatch authority',
    () async {
      transport.response = result('transport_accepted');
      expect(
        (await repo.finish(requestId, attemptId, 'transport_accepted')).state,
        OnlineOrderPrintState.transportAccepted,
      );
      expect(transport.calls.single.$2.containsKey('p_dispatch_id'), isFalse);
      expect(
        (await repo.status(requestId)).state,
        OnlineOrderPrintState.transportAccepted,
      );
      expect(transport.calls.last.$1, 'pos_web_order_print_status');
    },
  );
  test('unsafe finish status and diagnostics are refused locally', () async {
    expect(
      () => repo.finish(requestId, attemptId, 'retry-now'),
      throwsA(isA<OnlineOrderPrintException>()),
    );
    expect(
      () => repo.finish(
        requestId,
        attemptId,
        'possibly_printed',
        errorCode: 'raw endpoint or credential',
      ),
      throwsA(isA<OnlineOrderPrintException>()),
    );
    expect(transport.calls, isEmpty);
  });
}
