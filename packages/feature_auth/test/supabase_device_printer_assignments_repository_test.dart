import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// Device settings sprint (Part B): the token-proven printer-assignments
/// read. Parses the safe projection only; every failure is a typed,
/// fail-closed value — never a fabricated printer list.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.response);

  final Object? Function(String function, Map<String, dynamic> params) response;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return response(function, params);
  }
}

const _cred = DeviceSessionCredential(
  deviceId: 'dev-1',
  sessionToken: 'raw-token',
);

/// An in-memory store pre-seeded with [cred] (the ctor takes no initial).
InMemoryDeviceSessionSecretStore _storeWith(DeviceSessionCredential cred) {
  final store = InMemoryDeviceSessionSecretStore();
  store.write(cred);
  return store;
}

Map<String, Object?> _envelope() => {
  'ok': true,
  'entity': 'device_printer_assignments',
  'device': {
    'device_id': 'dev-1',
    'device_type': 'pos',
    'label': 'Front POS',
    'branch_id': 'branch-1',
    'branch_name': 'Main branch',
    'restaurant_name': 'Falafel House',
  },
  'printers': [
    {
      'id': 'prn-1',
      'display_name': 'Counter receipt',
      'role': 'receipt',
      'connection_type': 'network',
      'paper_width': '80mm',
      'is_enabled': true,
    },
    {
      'id': 'prn-2',
      'display_name': 'Backup receipt',
      'role': 'receipt',
      'connection_type': 'usb',
      'paper_width': '58mm',
      'is_enabled': false,
    },
  ],
  'routes': [
    {'station_id': 'st-1', 'printer_device_id': 'prn-1', 'is_enabled': true},
  ],
  'stations': [
    {'id': 'st-1', 'name': 'Grill'},
  ],
  'server_ts': '2026-07-03T10:00:00Z',
};

void main() {
  test(
    'a successful load parses the safe projection + device context',
    () async {
      final transport = _FakeTransport((_, _) => _envelope());
      final repo = SupabaseDevicePrinterAssignmentsRepository(
        transport: transport,
        secretStore: _storeWith(_cred),
        now: () => DateTime(2026, 7, 3, 12, 30),
      );

      final result = await repo.load();

      final assignments = (result as Success).value as DevicePrinterAssignments;
      // The RPC was called token-proven with the stored credential.
      expect(transport.calls.single.$1, 'get_device_printer_assignments');
      expect(transport.calls.single.$2['p_device_id'], 'dev-1');
      expect(transport.calls.single.$2['p_session_token'], 'raw-token');
      expect(assignments.deviceLabel, 'Front POS');
      expect(assignments.restaurantName, 'Falafel House');
      expect(assignments.branchName, 'Main branch');
      expect(assignments.printers, hasLength(2));
      expect(assignments.printers.first.displayName, 'Counter receipt');
      expect(assignments.printers.first.isEnabled, isTrue);
      expect(assignments.printers.last.isEnabled, isFalse);
      expect(assignments.hasEnabledPrinter, isTrue);
      expect(assignments.stationNamesFor(assignments.printers.first), [
        'Grill',
      ]);
      expect(assignments.fetchedAt, DateTime(2026, 7, 3, 12, 30));
    },
  );

  test('invalid_session from the server fails closed (typed)', () async {
    final transport = _FakeTransport(
      (_, _) => {'ok': false, 'error': 'invalid_session'},
    );
    final repo = SupabaseDevicePrinterAssignmentsRepository(
      transport: transport,
      secretStore: _storeWith(_cred),
    );

    final result = await repo.load();

    expect(
      (result as Failure).failure,
      DevicePrinterAssignmentsFailure.invalidSession,
    );
  });

  test(
    'no stored credential fails closed WITHOUT touching the network',
    () async {
      final transport = _FakeTransport((_, _) => _envelope());
      final repo = SupabaseDevicePrinterAssignmentsRepository(
        transport: transport,
        secretStore: InMemoryDeviceSessionSecretStore(),
      );

      final result = await repo.load();

      expect(
        (result as Failure).failure,
        DevicePrinterAssignmentsFailure.invalidSession,
      );
      expect(transport.calls, isEmpty);
    },
  );

  test('a transport failure is a typed network failure', () async {
    final transport = _FakeTransport(
      (_, _) => throw const SyncTransportException(
        SyncTransportErrorKind.transient,
        message: 'down',
      ),
    );
    final repo = SupabaseDevicePrinterAssignmentsRepository(
      transport: transport,
      secretStore: _storeWith(_cred),
    );

    final result = await repo.load();

    expect(
      (result as Failure).failure,
      DevicePrinterAssignmentsFailure.network,
    );
  });
}
