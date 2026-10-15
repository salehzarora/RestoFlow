import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'kitchen_print_permission.dart';

/// A null result means local authorization deferred the RPC. No server result
/// exists, and the caller must retain its evidence and pending marker unchanged.
typedef KitchenAckInvoke =
    Future<KitchenAckResult?> Function({
      required String dispatchId,
      required KitchenImportAckStatus status,
      String? errorCode,
      KitchenPrintTarget? target,
    });

/// Scoped to server-imported POS spool acknowledgements. The existing repository
/// still reads credentials and decodes server outcomes; its transport checks the
/// operation permit after that credential await, immediately before invocation.
class KitchenContainedAck {
  const KitchenContainedAck({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
    required KitchenPrintAuthorizer authorize,
  }) : _transport = transport,
       _secretStore = secretStore,
       _authorize = authorize;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _secretStore;
  final KitchenPrintAuthorizer _authorize;

  Future<KitchenAckResult?> acknowledge({
    required String dispatchId,
    required KitchenImportAckStatus status,
    String? errorCode,
    KitchenPrintTarget? target,
  }) async {
    if (target != null &&
        (target.dispatchId != dispatchId ||
            !target.isCurrent ||
            (status != KitchenImportAckStatus.imported &&
                status != KitchenImportAckStatus.blockedConfiguration))) {
      // Authentic targeted outcomes use the irreversible attempt's separately
      // authorized finish/status contract; this service only ACKs its import.
      return null;
    }
    final operation = target == null
        ? KitchenPrintOperation.ordinaryAck
        : KitchenPrintOperation.targetAck;
    final KitchenPrintAuthorization? permit;
    try {
      permit = await _authorize(
        operation,
        dispatchId: dispatchId,
        target: target,
      );
    } on Object {
      return null;
    }
    if (permit == null ||
        permit.operation != operation ||
        permit.dispatchId != dispatchId ||
        !_sameTarget(permit.target, target) ||
        !permit.isCurrent) {
      return null;
    }
    final guarded = _AuthorizedAckTransport(
      _transport,
      permit,
      dispatchId,
      status,
      errorCode,
    );
    final result = await SupabaseKitchenDispatchAckRepository(
      transport: guarded,
      secretStore: _secretStore,
    ).acknowledge(dispatchId: dispatchId, status: status, errorCode: errorCode);
    // Once delegated, a later restriction cannot retract an RPC already sent.
    // Preserve the genuine server result rather than manufacturing a deferral.
    return guarded.denied ? null : result;
  }
}

bool _sameTarget(KitchenPrintTarget? left, KitchenPrintTarget? right) =>
    left == null
    ? right == null
    : right != null &&
          left.requestId == right.requestId &&
          left.orderId == right.orderId &&
          left.dispatchId == right.dispatchId &&
          left.decisionId == right.decisionId &&
          left.printerAssignmentId == right.printerAssignmentId;

class _AuthorizedAckTransport implements SyncRpcTransport {
  _AuthorizedAckTransport(
    this._delegate,
    this._permit,
    this._dispatchId,
    this._status,
    this._errorCode,
  );

  final SyncRpcTransport _delegate;
  final KitchenPrintAuthorization _permit;
  final String _dispatchId;
  final KitchenImportAckStatus _status;
  final String? _errorCode;
  bool denied = false;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    final deviceId = params['p_device_id'];
    final token = params['p_session_token'];
    if (function != 'acknowledge_kitchen_print_dispatch' ||
        params['p_dispatch_id'] != _dispatchId ||
        params['p_client_status'] != _status.wireName ||
        params['p_error_code'] != _errorCode ||
        deviceId is! String ||
        token is! String ||
        !_permit.isCurrent ||
        !_permit.matchesCredential(deviceId, token)) {
      denied = true;
      // The base repository reports malformed locally; acknowledge maps this
      // private rejection to null, so it never becomes a retry or terminal ACK.
      return Future<Object?>.value(null);
    }
    // A plain delegate may still await SDK authentication. Require the explicit
    // production capability; unsupported/partial wiring is local deferral.
    final delegate = _delegate;
    if (delegate is! GuardedKitchenAckTransport) {
      denied = true;
      return Future<Object?>.value(null);
    }
    return _invokeGuarded(delegate, params, deviceId, token);
  }

  Future<Object?> _invokeGuarded(
    GuardedKitchenAckTransport delegate,
    Map<String, dynamic> params,
    String deviceId,
    String token,
  ) async {
    try {
      return await delegate.invokeGuardedKitchenAck(
        Map<String, dynamic>.unmodifiable(params),
        isCurrent: () => _permit.matchesCredential(deviceId, token),
      );
    } on KitchenAckDispatchDeferred {
      denied = true;
      return null;
    }
  }
}
