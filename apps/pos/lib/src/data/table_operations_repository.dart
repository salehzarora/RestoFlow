import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'ids.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — the POS operational table-control write seam.
///
/// A cashier with `manage_table_operations` (or manager+) may set a table's manual
/// floor status and link/unlink tables from the POS. Each mutation dispatches a
/// `table.status_set` / `table.link` / `table.unlink` operation through
/// `public.sync_push` to the server-authoritative RPCs. Orders/bills are NEVER
/// merged. ONLINE-REQUIRED (offline rule): with no session/transport, or on a
/// transport failure, this THROWS [TableOperationException]('offline') — it never
/// claims a fake local success.
abstract class TableOperationsRepository {
  Future<void> setStatus({required String tableId, required String status});
  Future<void> link({required String tableIdA, required String tableIdB});
  Future<void> unlink({required String tableId});
}

/// Thrown when a table operation could not be applied. Carries only a safe, mapped
/// code the UI localizes — never raw backend text.
class TableOperationException implements Exception {
  const TableOperationException(this.code);

  /// 'offline', 'permission_denied', 'table_not_found', 'table_in_use',
  /// 'table_not_available', 'invalid_link', 'conflict', or 'rejected'.
  final String code;

  @override
  String toString() => 'TableOperationException: $code';
}

/// REAL table operations over the shared public-schema transport + PIN/device
/// session (anon key + signed-in session; never the `app` schema, never a
/// service-role key).
class RealTableOperationsRepository implements TableOperationsRepository {
  const RealTableOperationsRepository(
    this._transport,
    this._session,
    this._idGenerator,
  );

  final SyncRpcTransport? _transport;
  final SyncSession? _session;
  final ClientIdGenerator _idGenerator;

  @override
  Future<void> setStatus({required String tableId, required String status}) =>
      _dispatch(
        operationType: 'table.status_set',
        targetEntity: 'table',
        targetId: tableId,
        payload: <String, dynamic>{'table_id': tableId, 'status': status},
      );

  @override
  Future<void> link({required String tableIdA, required String tableIdB}) =>
      _dispatch(
        operationType: 'table.link',
        targetEntity: 'table',
        targetId: tableIdA,
        payload: <String, dynamic>{
          'table_id_a': tableIdA,
          'table_id_b': tableIdB,
        },
      );

  @override
  Future<void> unlink({required String tableId}) => _dispatch(
    operationType: 'table.unlink',
    targetEntity: 'table',
    targetId: tableId,
    payload: <String, dynamic>{'table_id': tableId},
  );

  Future<void> _dispatch({
    required String operationType,
    required String targetEntity,
    required String targetId,
    required Map<String, dynamic> payload,
  }) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const TableOperationException('offline');
    }
    final localOperationId = _idGenerator.newId();
    final op = <String, dynamic>{
      'local_operation_id': localOperationId,
      'operation_type': operationType,
      'target_entity': targetEntity,
      'target_id': targetId,
      'client_created_at': DateTime.now().toIso8601String(),
      'payload': payload,
    };
    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[op],
      });
    } on SyncTransportException {
      throw const TableOperationException('offline');
    }
    _check(raw, localOperationId);
  }

  void _check(Object? raw, String localOperationId) {
    if (raw is! Map) throw const TableOperationException('rejected');
    final results = raw['results'];
    if (results is! List || results.isEmpty) {
      throw const TableOperationException('rejected');
    }
    Map<String, dynamic>? op;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOperationId) {
        op = r.cast<String, dynamic>();
        break;
      }
    }
    if (op == null) throw const TableOperationException('rejected');
    if (op['status'] == 'applied' && op['ok'] != false) return; // success
    // Map the typed server error to a UI code.
    final error = op['error'];
    if (op['status'] == 'conflict') {
      throw const TableOperationException('conflict');
    }
    throw TableOperationException(switch (error) {
      'permission_denied' => 'permission_denied',
      'table_not_found' => 'table_not_found',
      'table_in_use' => 'table_in_use',
      'table_not_available' => 'table_not_available',
      'invalid_link' => 'invalid_link',
      _ => 'rejected',
    });
  }
}
