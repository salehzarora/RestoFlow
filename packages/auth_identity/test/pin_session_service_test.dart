import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

import 'fake_rpc_transport.dart';

void main() {
  group('PinSessionService.startPinSession', () {
    test(
      'success uuid -> PinSessionStarted; sends the 4 p_ args and no user id',
      () async {
        final transport = FakeRpcTransport(value: 'pin-session-uuid-123');
        final service = PinSessionService(
          transport,
          generateLocalOperationId: () => 'op-fixed',
        );

        final result = await service.startPinSession(
          deviceSessionId: 'dsess-1',
          employeeProfileId: 'emp-1',
          pinVerifier: 'ref:A',
        );

        expect(result.isSuccess, isTrue);
        final started =
            (result as Success<PinSessionStarted, AuthFailure>).value;
        expect(started.pinSessionId, 'pin-session-uuid-123');
        expect(started.localOperationId, 'op-fixed');

        expect(transport.lastFunction, 'start_pin_session');
        expect(transport.lastParams, {
          'p_device_session_id': 'dsess-1',
          'p_employee_profile_id': 'emp-1',
          'p_pin_verifier': 'ref:A',
          'p_local_operation_id': 'op-fixed',
        });
        // No user id is ever sent.
        expect(transport.lastParams!.keys, isNot(contains('user_id')));
      },
    );

    test('NULL result -> AuthWrongPinFailure (wrong PIN, no error)', () async {
      final transport = FakeRpcTransport(value: null);
      final result = await PinSessionService(transport).startPinSession(
        deviceSessionId: 'dsess-1',
        employeeProfileId: 'emp-1',
        pinVerifier: 'ref:WRONG',
      );
      expect(
        (result as Failure<PinSessionStarted, AuthFailure>).failure,
        isA<AuthWrongPinFailure>(),
      );
    });

    test('42501 -> AuthLockedOrPreconditionFailure', () async {
      final transport = FakeRpcTransport(
        error: const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
        ),
      );
      final result = await PinSessionService(transport).startPinSession(
        deviceSessionId: 'dsess-1',
        employeeProfileId: 'emp-1',
        pinVerifier: 'ref:A',
      );
      expect(
        (result as Failure<PinSessionStarted, AuthFailure>).failure,
        isA<AuthLockedOrPreconditionFailure>(),
      );
    });

    test('transient error -> AuthNetworkFailure', () async {
      final transport = FakeRpcTransport(
        error: const SyncTransportException(SyncTransportErrorKind.transient),
      );
      final result = await PinSessionService(transport).startPinSession(
        deviceSessionId: 'dsess-1',
        employeeProfileId: 'emp-1',
        pinVerifier: 'ref:A',
      );
      expect(
        (result as Failure<PinSessionStarted, AuthFailure>).failure,
        isA<AuthNetworkFailure>(),
      );
    });

    test('a supplied local_operation_id is passed through unchanged', () async {
      final transport = FakeRpcTransport(value: 'uuid');
      await PinSessionService(transport).startPinSession(
        deviceSessionId: 'dsess-1',
        employeeProfileId: 'emp-1',
        pinVerifier: 'ref:A',
        localOperationId: 'caller-op-7',
      );
      expect(transport.lastParams!['p_local_operation_id'], 'caller-op-7');
    });

    test(
      'a local_operation_id is generated (uuid v4 shape) when not supplied',
      () async {
        final transport = FakeRpcTransport(value: 'uuid');
        await PinSessionService(transport).startPinSession(
          deviceSessionId: 'dsess-1',
          employeeProfileId: 'emp-1',
          pinVerifier: 'ref:A',
        );
        final opId = transport.lastParams!['p_local_operation_id'] as String;
        expect(
          opId,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      },
    );

    test('generated ids are unique across attempts', () async {
      final transport = FakeRpcTransport(value: 'uuid');
      final service = PinSessionService(transport);
      await service.startPinSession(
        deviceSessionId: 'd',
        employeeProfileId: 'e',
        pinVerifier: 'ref:A',
      );
      final first = transport.lastParams!['p_local_operation_id'];
      await service.startPinSession(
        deviceSessionId: 'd',
        employeeProfileId: 'e',
        pinVerifier: 'ref:A',
      );
      final second = transport.lastParams!['p_local_operation_id'];
      expect(first, isNot(second));
    });
  });
}
