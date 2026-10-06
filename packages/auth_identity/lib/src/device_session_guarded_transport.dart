import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// Stops NEW protected RPCs after an unproven or rejected device-session
/// verdict. Recovery calls remain available. This is retryable transport
/// evidence, never human-session rejection or POS AUTH_HOLD.
class DeviceSessionGuardedTransport implements SyncRpcTransport {
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
}
