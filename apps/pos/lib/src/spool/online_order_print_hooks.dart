import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/online_order_inbox_controller.dart'
    show onlineOrderInboxIdentityProvider;
import 'pos_kitchen_spool_composition.dart' show posKitchenSpoolRuntimeProvider;
import 'web_order_print_history.dart';
export 'web_order_print_history.dart';

/// Web-safe, exact-request callback. No stores, keys, endpoints, raw payloads,
/// or broad branch drain is exposed to the inbox controller or UI.
abstract interface class PosWebOrderPrintHooks {
  Future<WebOrderPrintOutcome?> readWebPrintRecovery();
  void cancelPendingWebPrint();
  Future<WebOrderPrintOutcome> onAcceptedWebOrder(
    String requestId,
    String orderId,
  );
}

/// Read-only durable recovery projection. No claim, begin, retry, or send.
final onlineInboxPrintRecoveryProvider = FutureProvider<WebOrderPrintHistory?>((
  ref,
) async {
  final identity = ref.watch(onlineOrderInboxIdentityProvider);
  if (identity == null) return null;
  var active = true;
  ref.onDispose(() => active = false);
  final hooks = ref.watch(posKitchenSpoolRuntimeProvider);
  if (hooks is PosWebOrderPrintHistoryHooks) {
    final history = await (hooks as PosWebOrderPrintHistoryHooks)
        .readWebPrintHistory();
    return active && ref.read(onlineOrderInboxIdentityProvider) == identity
        ? history
        : null;
  }
  final outcome = hooks is PosWebOrderPrintHooks
      ? (hooks as PosWebOrderPrintHooks).readWebPrintRecovery()
      : null;
  final value = await outcome;
  if (!active || ref.read(onlineOrderInboxIdentityProvider) != identity)
    return null;
  return value == null
      ? null
      : WebOrderPrintHistory(unidentifiedOutcome: value);
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
