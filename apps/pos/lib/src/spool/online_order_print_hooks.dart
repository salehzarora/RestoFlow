import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pos_kitchen_spool_composition.dart' show posKitchenSpoolRuntimeProvider;

/// Web-safe, exact-request callback. No stores, keys, endpoints, raw payloads,
/// or broad branch drain is exposed to the inbox controller or UI.
enum WebOrderPrintOutcome {
  sent,
  reconciliationRequired,
  blocked,
  failed,
  busy,
  kds,
  unavailable,
}

abstract interface class PosWebOrderPrintHooks {
  void cancelPendingWebPrint();
  Future<WebOrderPrintOutcome> onAcceptedWebOrder(
    String requestId,
    String orderId,
  );
}

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
    final hooks = ref.read(posKitchenSpoolRuntimeProvider);
    if (hooks is PosWebOrderPrintHooks)
      (hooks as PosWebOrderPrintHooks).cancelPendingWebPrint();
  },
);
