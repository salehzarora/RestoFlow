import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pos_kitchen_spool_composition.dart' show posKitchenSpoolRuntimeProvider;

/// Web-safe, exact-request callback. No stores, keys, endpoints, raw payloads,
/// or broad branch drain is exposed to the inbox controller or UI.
enum WebOrderPrintOutcome {
  sent,
  reconciliationRequired,
  blocked,
  attention,
  failed,
  busy,
  kds,
  unavailable,
}

abstract interface class PosWebOrderPrintHooks {
  Future<WebOrderPrintOutcome?> readWebPrintRecovery();
  void cancelPendingWebPrint();
  Future<WebOrderPrintOutcome> onAcceptedWebOrder(
    String requestId,
    String orderId,
  );
}

/// Read-only durable recovery projection. No claim, begin, retry, or send.
final onlineInboxPrintRecoveryProvider = FutureProvider<WebOrderPrintOutcome?>((
  ref,
) async {
  final hooks = ref.watch(posKitchenSpoolRuntimeProvider);
  return hooks is PosWebOrderPrintHooks
      ? (hooks as PosWebOrderPrintHooks).readWebPrintRecovery()
      : null;
});

final onlineInboxAcceptedPrintProvider =
    Provider<Future<WebOrderPrintOutcome> Function(String, String)>((ref) {
      return (requestId, orderId) async {
        final hooks = ref.read(posKitchenSpoolRuntimeProvider);
        return hooks is PosWebOrderPrintHooks
            ? (hooks as PosWebOrderPrintHooks).onAcceptedWebOrder(
                requestId,
                orderId,
              )
            : WebOrderPrintOutcome.unavailable;
      };
    });
final onlineInboxCancelPrintProvider = Provider<void Function()>(
  (ref) => () {
    // Pause/security cleanup must not instantiate a native runtime when no
    // print operation or recovery view ever used one.
    if (!ref.exists(posKitchenSpoolRuntimeProvider)) return;
    final hooks = ref.read(posKitchenSpoolRuntimeProvider);
    if (hooks is PosWebOrderPrintHooks)
      (hooks as PosWebOrderPrintHooks).cancelPendingWebPrint();
  },
);
