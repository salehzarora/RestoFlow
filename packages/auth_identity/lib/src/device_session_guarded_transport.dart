import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// Stops NEW protected RPCs after an unproven or rejected device-session
/// verdict. Recovery calls remain available. This is retryable transport
/// evidence, never human-session rejection or POS AUTH_HOLD.
class DeviceSessionGuardedTransport
    implements
        GuardedKitchenAckTransport,
        AuthenticatedWebOrderDecisionTransport {
  DeviceSessionGuardedTransport(this._inner);

  final SyncRpcTransport _inner;
  bool _blocked = false;

  bool get isBlocked => _blocked;
  void block() => _blocked = true;
  void allow() => _blocked = false;

  static const _recovery = <String>{
    'redeem_device_pairing',
    'restore_device_session',
    'heartbeat_device_session',
    'revoke_device_session',
  };

  @override
  Future<Object?> decideWebOrder(Map<String, dynamic> body) {
    if (_blocked) {
      return Future.error(
        const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: 'device_session_unverified',
        ),
      );
    }
    final inner = _inner;
    if (inner is! AuthenticatedWebOrderDecisionTransport) {
      return Future.error(
        const SyncTransportException(SyncTransportErrorKind.server),
      );
    }
    // No await before handoff: a block during repository credential loading
    // wins here. Already handed-off outcomes remain uncertain, never retried.
    return (inner as AuthenticatedWebOrderDecisionTransport).decideWebOrder(
      body,
    );
  }

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    if (_blocked && !_recovery.contains(function)) {
      return Future<Object?>.error(
        const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: 'device_session_unverified',
        ),
      );
    }
    return _inner.invoke(function, params);
  }

  @override
  Future<Object?> invokeGuardedKitchenAck(
    Map<String, dynamic> params, {
    required bool Function() isCurrent,
  }) {
    final inner = _inner;
    if (_blocked || inner is! GuardedKitchenAckTransport) {
      return Future.error(const KitchenAckDispatchDeferred());
    }
    return inner.invokeGuardedKitchenAck(
      params,
      isCurrent: () => !_blocked && isCurrent(),
    );
  }
}
