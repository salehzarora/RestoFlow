import 'package:restoflow_data_local/restoflow_data_local.dart';

/// KITCHEN-MODE-001C2C — the idempotent LOCAL VOID sweep.
///
/// Re-applies durable VOID evidence to this scope's unresolved jobs so a
/// crash between the void's durable import and its reconciliation — or a
/// job that was PRINTING when the void arrived and later fell back to
/// failedRetryable — can never print a voided order's ticket:
///
///  * imported / queued / failedRetryable / blockedConfiguration →
///    superseded (the store's evidence transition; printing is excluded
///    there by design and transportAccepted stays history);
///  * possiblyPrinted keeps its ambiguity and only gains the evidence link;
///  * the VOID dispatch itself is never superseded by this sweep;
///  * other orders and other scopes are untouched.
///
/// Evidence source: UNRESOLVED void rows in scope (resolved voids already
/// ran the import-time reconciliation before their acknowledgement).
Future<({int superseded, int links})> reconcileLocalVoidEvidence(
  KitchenSpoolStore store, {
  required String deviceId,
  required String branchId,
  required DateTime now,
}) async {
  var superseded = 0, links = 0;
  final unresolved = await store.listUnresolved(
    deviceId: deviceId,
    branchId: branchId,
  );
  final voids = [
    for (final row in unresolved)
      if (row.dispatchType == KitchenSpoolDispatchType.voidNotice) row,
  ];
  for (final evidence in voids) {
    for (final prior in unresolved) {
      if (prior.orderId != evidence.orderId) continue;
      if (prior.dispatchId == evidence.dispatchId) continue;
      if (prior.dispatchType == KitchenSpoolDispatchType.voidNotice) continue;
      if (prior.status == KitchenSpoolJobStatus.possiblyPrinted) {
        if (await store.linkSupersessionEvidence(
          dispatchId: prior.dispatchId,
          supersededByDispatchId: evidence.dispatchId,
          now: now,
        )) {
          links++;
        }
      } else if (await store.markSupersededFromServerEvidence(
        dispatchId: prior.dispatchId,
        supersededByDispatchId: evidence.dispatchId,
        now: now,
      )) {
        superseded++;
      }
    }
  }
  return (superseded: superseded, links: links);
}
