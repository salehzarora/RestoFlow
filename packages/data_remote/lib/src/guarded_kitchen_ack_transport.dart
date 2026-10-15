import 'sync_rpc_transport.dart';

/// Capability required for an imported-spool ACK. Implementations must check
/// [isCurrent] after authentication preparation, at HTTP transport handoff.
/// A plain [SyncRpcTransport.invoke] is deliberately not a fallback.
abstract interface class GuardedKitchenAckTransport
    implements SyncRpcTransport {
  Future<Object?> invokeGuardedKitchenAck(
    Map<String, dynamic> params, {
    required bool Function() isCurrent,
  });
}

/// Local non-delivery, not a server outcome. Carries no request or credentials.
final class KitchenAckDispatchDeferred implements Exception {
  const KitchenAckDispatchDeferred();

  @override
  String toString() => 'KitchenAckDispatchDeferred';
}
