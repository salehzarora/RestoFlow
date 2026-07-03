import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The real, backend-backed [DevicePrinterAssignmentsReader] (device settings
/// sprint): calls `public.get_device_printer_assignments(p_device_id,
/// p_session_token)` through the authenticated (anonymous) anon-key
/// transport.
///
/// TOKEN-PROVEN like the staff directory / `restore_device_session` (RF-161):
/// the raw device-session token is read from OS-backed secure storage, sent
/// over TLS, and verified by hash server-side. The response is the MINIMAL
/// per-branch printer projection (identity/role/capability — no
/// connection_config, no secrets, no money). Failures are safe, typed
/// [DevicePrinterAssignmentsFailure]s; the token is never logged or surfaced.
class SupabaseDevicePrinterAssignmentsRepository
    implements DevicePrinterAssignmentsReader {
  SupabaseDevicePrinterAssignmentsRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
    DateTime Function()? now,
  }) : _transport = transport,
       _store = secretStore,
       _now = now ?? DateTime.now;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _store;
  final DateTime Function() _now;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      // A throwing secure-storage read fails closed as an invalid session.
      return const Failure(DevicePrinterAssignmentsFailure.invalidSession);
    }
    if (cred == null) {
      return const Failure(DevicePrinterAssignmentsFailure.invalidSession);
    }
    final Object? raw;
    try {
      raw = await _transport.invoke(
        'get_device_printer_assignments',
        <String, dynamic>{
          'p_device_id': cred.deviceId,
          'p_session_token': cred.sessionToken,
        },
      );
    } on SyncTransportException catch (e) {
      return Failure(switch (e.kind) {
        SyncTransportErrorKind.auth =>
          DevicePrinterAssignmentsFailure.invalidSession,
        SyncTransportErrorKind.transient =>
          DevicePrinterAssignmentsFailure.network,
        _ => DevicePrinterAssignmentsFailure.unknown,
      });
    } catch (_) {
      return const Failure(DevicePrinterAssignmentsFailure.network);
    }
    if (raw is! Map || raw['ok'] != true) {
      return const Failure(DevicePrinterAssignmentsFailure.invalidSession);
    }
    final device = raw['device'];
    final deviceMap = device is Map ? device : const <String, Object?>{};
    String? optString(Object? value) {
      final text = value?.toString() ?? '';
      return text.isEmpty ? null : text;
    }

    return Success(
      DevicePrinterAssignments(
        fetchedAt: _now(),
        deviceLabel: optString(deviceMap['label']),
        deviceType: optString(deviceMap['device_type']),
        branchName: optString(deviceMap['branch_name']),
        restaurantName: optString(deviceMap['restaurant_name']),
        printers: [
          for (final row in (raw['printers'] as List?) ?? const [])
            if (row is Map)
              AssignedPrinter(
                id: (row['id'] ?? '').toString(),
                displayName: (row['display_name'] ?? '').toString(),
                role: (row['role'] ?? '').toString(),
                connectionType: (row['connection_type'] ?? '').toString(),
                paperWidth: (row['paper_width'] ?? '').toString(),
                isEnabled: row['is_enabled'] == true,
              ),
        ],
        routes: [
          for (final row in (raw['routes'] as List?) ?? const [])
            if (row is Map)
              PrinterRoute(
                stationId: (row['station_id'] ?? '').toString(),
                printerDeviceId: (row['printer_device_id'] ?? '').toString(),
                isEnabled: row['is_enabled'] == true,
              ),
        ],
        stations: [
          for (final row in (raw['stations'] as List?) ?? const [])
            if (row is Map)
              PrinterStation(
                id: (row['id'] ?? '').toString(),
                name: (row['name'] ?? '').toString(),
              ),
        ],
      ),
    );
  }
}
