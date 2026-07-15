import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'ids.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — the POS cashier menu-availability write seam.
///
/// A cashier with `manage_menu_availability` (or a manager+) may set a menu item's
/// per-branch availability from the POS. The mutation dispatches the
/// `menu.availability_set` operation through `public.sync_push` to
/// `app.pos_set_item_availability`, which authorizes server-side and writes the
/// SAME override + audit as the Dashboard path (one model, one Activity Log).
///
/// ONLINE-REQUIRED (offline rule): changing another device's operational menu
/// availability requires authoritative server confirmation. With no session /
/// transport, or on a transport failure, this THROWS [MenuAvailabilityException]
/// ('offline') — it NEVER claims a fake local Sold-out/Available while offline.
abstract class MenuAvailabilityRepository {
  /// Sets [menuItemId] to [availability] ('available' | 'unavailable'); when
  /// unavailable, [reason] is 'sold_out' | 'paused'. Returns the confirmed state
  /// on success, or throws [MenuAvailabilityException] with a safe mapped code.
  Future<MenuAvailabilityState> setAvailability({
    required String menuItemId,
    required String availability,
    String? reason,
  });
}

/// The confirmed availability of an item after a successful mutation.
class MenuAvailabilityState {
  const MenuAvailabilityState({
    required this.menuItemId,
    required this.availability,
    this.reason,
  });

  final String menuItemId;
  final String availability; // 'available' | 'unavailable'
  final String? reason; // 'sold_out' | 'paused' | null

  bool get isUnavailable => availability == 'unavailable';
}

/// Thrown when the availability could not be changed. Carries only a safe, mapped
/// code the UI localizes — never raw backend text.
class MenuAvailabilityException implements Exception {
  const MenuAvailabilityException(this.code);

  /// 'offline' (no session/transport or transport failure — the retryable
  /// connectivity failure), 'permission_denied', 'not_found', or 'rejected'
  /// (any other non-applied result / malformed envelope).
  final String code;

  @override
  String toString() => 'MenuAvailabilityException: $code';
}

/// REAL POS availability mutation. Reuses the shared public-schema
/// [SyncRpcTransport] + [SyncSession] (anon key + PIN/device session), like the
/// order/payment/shift paths — never the `app` schema, never a service-role key.
class RealMenuAvailabilityRepository implements MenuAvailabilityRepository {
  const RealMenuAvailabilityRepository(
    this._transport,
    this._session,
    this._idGenerator,
  );

  final SyncRpcTransport? _transport;
  final SyncSession? _session;
  final ClientIdGenerator _idGenerator;

  @override
  Future<MenuAvailabilityState> setAvailability({
    required String menuItemId,
    required String availability,
    String? reason,
  }) async {
    final transport = _transport;
    final session = _session;
    // ONLINE-REQUIRED: no session/transport => offline failure, never fake success.
    if (transport == null || session == null) {
      throw const MenuAvailabilityException('offline');
    }

    final localOperationId = _idGenerator.newId();
    final op = <String, dynamic>{
      'local_operation_id': localOperationId,
      'operation_type': 'menu.availability_set',
      'target_entity': 'menu_item',
      'target_id': menuItemId,
      'client_created_at': DateTime.now().toIso8601String(),
      'payload': <String, dynamic>{
        'menu_item_id': menuItemId,
        'availability': availability,
        if (availability == 'unavailable' && reason != null) 'reason': reason,
      },
    };

    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[op],
      });
    } on SyncTransportException {
      // Transport-level failure is treated as the retryable OFFLINE case: the
      // authoritative state is unknown, so we surface a connectivity failure and
      // keep the previous state (never a fake success).
      throw const MenuAvailabilityException('offline');
    }

    return _apply(raw, localOperationId, menuItemId);
  }

  MenuAvailabilityState _apply(
    Object? raw,
    String localOperationId,
    String menuItemId,
  ) {
    if (raw is! Map) throw const MenuAvailabilityException('rejected');
    final results = raw['results'];
    if (results is! List || results.isEmpty) {
      throw const MenuAvailabilityException('rejected');
    }
    Map<String, dynamic>? op;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOperationId) {
        op = r.cast<String, dynamic>();
        break;
      }
    }
    if (op == null) throw const MenuAvailabilityException('rejected');

    if (op['status'] != 'applied' || op['ok'] == false) {
      final error = op['error'];
      if (error == 'permission_denied') {
        throw const MenuAvailabilityException('permission_denied');
      }
      if (error == 'not_found') {
        throw const MenuAvailabilityException('not_found');
      }
      throw const MenuAvailabilityException('rejected');
    }

    final availability = op['availability'];
    if (availability is! String) {
      throw const MenuAvailabilityException('rejected');
    }
    final reason = op['reason'];
    return MenuAvailabilityState(
      menuItemId: menuItemId,
      availability: availability,
      reason: reason is String ? reason : null,
    );
  }
}
