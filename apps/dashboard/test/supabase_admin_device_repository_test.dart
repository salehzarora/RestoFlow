import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';

import 'package:restoflow_dashboard/src/admin/supabase_admin_device_repository.dart';

/// A recording fake transport: captures every (fn, params) call and returns/throws
/// whatever the handler decides.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

const _branchScope = AdminScope(
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest',
  branchId: 'branch-1',
  branchName: 'Main',
  currencyCode: 'USD',
  actingRole: MembershipRole.manager,
);

const _orgWideScope = AdminScope(
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: null,
  restaurantName: null,
  branchId: null,
  branchName: null,
  currencyCode: 'USD',
  actingRole: MembershipRole.orgOwner,
);

SupabaseAdminDeviceRepository _repo(
  _FakeTransport t, {
  AdminScope scope = _branchScope,
}) => SupabaseAdminDeviceRepository(
  transport: t,
  scope: scope,
  currentUserId: () => 'user-1',
  nonce: () => 42,
);

final _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

void main() {
  group('loadDevices', () {
    test(
      'fetch clock starts before transport and is shared by rows and copies',
      () async {
        var elapsed = Duration.zero;
        var started = false;
        final t = _FakeTransport((_, _) {
          expect(started, isTrue);
          elapsed = const Duration(seconds: 3);
          return {
            'ok': true,
            'server_now': '2035-01-01T12:00:00Z',
            'devices': [
              for (final id in ['d1', 'd2'])
                {
                  'device_id': id,
                  'status': 'code_issued',
                  'has_open_session': true,
                  'session_expires_at': '2035-01-01T12:00:05Z',
                  'code_expires_at': '2035-01-01T12:00:05Z',
                },
            ],
          };
        });
        final repo = SupabaseAdminDeviceRepository(
          transport: t,
          scope: _branchScope,
          currentUserId: () => 'user-1',
          snapshotClock: () {
            started = true;
            return AdminDeviceSnapshotClock(elapsed: () => elapsed);
          },
        );
        final result = await repo.loadDevices();
        final devices =
            (result as Success<List<AdminDevice>, AdminFailure>).value;
        expect(
          devices.first.estimatedServerNow,
          DateTime.utc(2035, 1, 1, 12, 0, 3),
        );
        expect(devices.first.snapshotClock, same(devices.last.snapshotClock));
        final copied = devices.first.copyWith();
        expect(copied.snapshotClock, same(devices.first.snapshotClock));
        expect(copied.isCodeExpired, isFalse);
        elapsed = const Duration(seconds: 5);
        expect(copied.isCodeExpired, isTrue);
        expect(copied.isSessionActive, isFalse);
      },
    );

    test('sends the scope + parses the device rows', () async {
      final t = _FakeTransport(
        (fn, p) => {
          'ok': true,
          'entity': 'device',
          'server_now': '2035-01-01T12:00:00Z',
          'devices': [
            {
              'device_id': 'd1',
              'label': 'Front POS',
              'device_type': 'pos',
              'branch_id': 'branch-1',
              'branch_label': 'Main',
              'status': 'paired',
              'device_pairing_id': 'p1',
              'has_open_session': true,
              'session_expires_at': '2035-01-31T12:00:00Z',
              'last_seen_at': '2035-01-01T11:00:00Z',
            },
            {
              'device_id': 'd2',
              'label': 'KDS',
              'device_type': 'kds',
              'branch_id': 'branch-1',
              'branch_label': 'Main',
              'status': 'none',
              'device_pairing_id': null,
              'has_open_session': false,
            },
          ],
        },
      );

      final r = await _repo(t).loadDevices();

      expect(t.calls.single.$1, 'list_devices');
      expect(t.calls.single.$2, {
        'p_organization_id': 'org-1',
        'p_restaurant_id': 'rest-1',
        'p_branch_id': 'branch-1',
      });
      final devices = (r as Success<List<AdminDevice>, AdminFailure>).value;
      expect(devices, hasLength(2));
      expect(devices[0].id, 'd1');
      expect(devices[0].status, DeviceLifecycleStatus.paired);
      expect(devices[0].pairingId, 'p1');
      expect(devices[0].hasOpenSession, isTrue);
      expect(devices[0].sessionExpiresAt, DateTime.utc(2035, 1, 31, 12));
      expect(devices[0].lastSeenAt, DateTime.utc(2035, 1, 1, 11));
      expect(devices[0].serverNow, DateTime.utc(2035, 1, 1, 12));
      expect(devices[0].branchLabel, 'Main');
      expect(devices[1].status, DeviceLifecycleStatus.none);
      expect(devices[1].pairingId, isNull);
      expect(devices[1].hasOpenSession, isFalse);
    });

    for (final sample
        in <
          ({
            String name,
            Map<String, Object?> envelope,
            Map<String, Object?> row,
            bool active,
          })
        >[
          (name: 'old server', envelope: {}, row: {}, active: false),
          (
            name: 'missing expiry',
            envelope: {'server_now': '2035-01-01T12:00:00Z'},
            row: {},
            active: false,
          ),
          (
            name: 'malformed expiry',
            envelope: {'server_now': '2035-01-01T12:00:00Z'},
            row: {'session_expires_at': 'invalid'},
            active: false,
          ),
          (
            name: 'malformed server clock',
            envelope: {'server_now': 123},
            row: {'session_expires_at': null},
            active: false,
          ),
          (
            name: 'explicit legacy NULL',
            envelope: {'server_now': '2035-01-01T12:00:00Z'},
            row: {'session_expires_at': null},
            active: true,
          ),
        ]) {
      test(
        '${sample.name} session metadata is handled conservatively',
        () async {
          final transport = _FakeTransport(
            (_, _) => {
              'ok': true,
              ...sample.envelope,
              'devices': [
                {
                  'device_id': 'd1',
                  'status': 'active',
                  'has_open_session': true,
                  'last_seen_at': {'malformed': true},
                  ...sample.row,
                },
              ],
            },
          );
          final result = await _repo(transport).loadDevices();
          final device = result.fold(
            (rows) => rows.single,
            (_) => fail('load failed'),
          );
          expect(device.hasOpenSession, sample.active);
          expect(device.isSessionActive, sample.active);
          expect(device.lastSeenAt, isNull);
        },
      );
    }

    test('an org-wide scope sends null restaurant/branch', () async {
      final t = _FakeTransport((fn, p) => {'ok': true, 'devices': []});
      await _repo(t, scope: _orgWideScope).loadDevices();
      expect(t.calls.single.$2, {
        'p_organization_id': 'org-1',
        'p_restaurant_id': null,
        'p_branch_id': null,
      });
    });

    test(
      'a permission_denied envelope maps to AdminPermissionDenied',
      () async {
        final t = _FakeTransport(
          (fn, p) => {'ok': false, 'error': 'permission_denied'},
        );
        final r = await _repo(t).loadDevices();
        expect(r.isSuccess, isFalse);
        r.fold((_) => fail('expected failure'), (f) {
          expect(f, isA<AdminPermissionDenied>());
        });
      },
    );

    test('a 42501 transport error maps to AdminPermissionDenied', () async {
      final t = _FakeTransport((fn, p) {
        throw const SyncTransportException(SyncTransportErrorKind.auth);
      });
      final r = await _repo(t).loadDevices();
      r.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminPermissionDenied>()),
      );
    });

    test('a transient transport error maps to AdminTransient', () async {
      final t = _FakeTransport((fn, p) {
        throw const SyncTransportException(SyncTransportErrorKind.transient);
      });
      final r = await _repo(t).loadDevices();
      r.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminTransient>()),
      );
    });
  });

  group('createDevice', () {
    test(
      'sends create_device with the branch scope + a UUID request id',
      () async {
        final t = _FakeTransport((fn, p) => {'ok': true, 'device_id': 'new-d'});
        final r = await _repo(
          t,
        ).createDevice(label: '  Patio POS ', deviceType: 'pos');

        expect(t.calls.single.$1, 'create_device');
        final params = t.calls.single.$2;
        expect(params['p_organization_id'], 'org-1');
        expect(params['p_restaurant_id'], 'rest-1');
        expect(params['p_branch_id'], 'branch-1');
        expect(params['p_device_type'], 'pos');
        expect(params['p_label'], 'Patio POS');
        expect(params['p_client_request_id'], matches(_uuidRe));

        final device = (r as Success<AdminDevice, AdminFailure>).value;
        expect(device.id, 'new-d');
        expect(device.label, 'Patio POS');
        expect(device.status, DeviceLifecycleStatus.none);
      },
    );

    test(
      'an org-wide scope (no branch) fails closed without a backend call',
      () async {
        final t = _FakeTransport(
          (fn, p) => fail('should not call the backend'),
        );
        final r = await _repo(
          t,
          scope: _orgWideScope,
        ).createDevice(label: 'X', deviceType: 'pos');
        expect(t.calls, isEmpty);
        r.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<AdminValidation>()),
        );
      },
    );

    test('an empty label is rejected locally', () async {
      final t = _FakeTransport((fn, p) => fail('should not call the backend'));
      final r = await _repo(t).createDevice(label: '   ', deviceType: 'pos');
      expect(t.calls, isEmpty);
      r.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminValidation>()),
      );
    });

    test('an unknown device type is rejected locally', () async {
      final t = _FakeTransport((fn, p) => fail('should not call the backend'));
      final r = await _repo(t).createDevice(label: 'X', deviceType: 'tablet');
      expect(t.calls, isEmpty);
      expect(r.isSuccess, isFalse);
    });
  });

  group('issueEnrollmentCode', () {
    test(
      'H6 missing inactive device 42501 maps to device_changed conflict',
      () async {
        final t = _FakeTransport(
          (_, _) => throw const SyncTransportException(
            SyncTransportErrorKind.server,
            code: '42501',
            message:
                'issue_device_enrollment_code: device not found, inactive, or its scope is soft-deleted',
          ),
        );
        final result = await _repo(t).issueEnrollmentCode('d1');
        result.fold((_) => fail('expected conflict'), (failure) {
          expect(failure, isA<AdminConflict>());
          expect((failure as AdminConflict).message, 'device_changed');
        });
      },
    );

    test('H6 unrelated auth 42501 remains permission denied', () async {
      final t = _FakeTransport(
        (_, _) => throw const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
          message: 'permission denied',
        ),
      );
      final result = await _repo(t).issueEnrollmentCode('d1');
      result.fold(
        (_) => fail('expected permission denial'),
        (failure) => expect(failure, isA<AdminPermissionDenied>()),
      );
    });

    test('returns the one-time code on the first response', () async {
      final t = _FakeTransport(
        (fn, p) => {
          'ok': true,
          'device_pairing_id': 'p9',
          'device_id': 'd1',
          'status': 'code_issued',
          'enrollment_code': 'ABCD1234',
        },
      );
      final r = await _repo(t).issueEnrollmentCode('d1');
      expect(t.calls.single.$1, 'issue_device_enrollment_code');
      expect(t.calls.single.$2['p_device_id'], 'd1');
      final issued = (r as Success<EnrollmentCodeIssued, AdminFailure>).value;
      expect(issued.code, 'ABCD1234');
      expect(issued.pairingId, 'p9');
    });

    test(
      'an idempotent replay (no code) is a conflict, never an empty code',
      () async {
        final t = _FakeTransport(
          (fn, p) => {
            'ok': true,
            'device_pairing_id': 'p9',
            'device_id': 'd1',
            'status': 'code_issued',
          },
        );
        final r = await _repo(t).issueEnrollmentCode('d1');
        r.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<AdminConflict>()),
        );
      },
    );
  });

  group('deferred lifecycle (device-auth bridge)', () {
    test(
      'redeem/approve/activate/startSession never hit the backend',
      () async {
        final t = _FakeTransport((fn, p) => fail('must not call the backend'));
        final repo = _repo(t);
        for (final r in [
          await repo.redeemEnrollmentCode('d1'),
          await repo.approveDevice('d1'),
          await repo.activateDevice('d1'),
          await repo.startDeviceSession('d1'),
        ]) {
          expect(r.isSuccess, isFalse);
          r.fold(
            (_) => fail('expected a deferred failure'),
            (f) => expect(f, isA<AdminConflict>()),
          );
        }
        expect(t.calls, isEmpty);
      },
    );
  });
}
