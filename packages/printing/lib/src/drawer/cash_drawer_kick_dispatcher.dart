import '../print_document.dart';
import '../spool/print_job.dart';
import '../spool/print_spool.dart';
import 'cash_drawer_kick_input.dart';

/// Enqueues a one-shot cash-drawer kick into the RF-071 [PrintSpool] (RF-074).
///
/// Thin orchestration mirroring the receipt dispatcher: validate the input →
/// (no-op for non-cash/voided) → enqueue a kick-only `PrintDocument` as a
/// `cashDrawer` job. It NEVER prints, drains the spool, or touches transport.
///
/// SAFETY (at-most-once): the kick job is enqueued with `maxRetries: 0`, so any
/// dispatch failure goes straight to `abandoned` (never retried), and its
/// `local_operation_id` is `drawer:<paymentId>` (D-022), so re-dispatching the
/// same payment collapses to the existing job (no second kick). A drawer job
/// also cannot be reprinted (RF-58 guard) and a crash leaves it in
/// `possiblyPrinted` (manual review, never auto-replayed). A duplicate open is
/// worse than a missed retry, so none of these paths can re-open the drawer.
class CashDrawerKickDispatcher {
  CashDrawerKickDispatcher({
    required PrintSpool spool,
    DateTime Function()? clock,
  }) : _spool = spool,
       _clock = clock ?? DateTime.now;

  final PrintSpool _spool;
  final DateTime Function() _clock;

  /// The deterministic idempotency / local-operation id for [paymentId].
  static String localOperationIdFor(String paymentId) => 'drawer:$paymentId';

  /// Validate and (if it should kick) enqueue the drawer-kick job for [input].
  ///
  /// Returns the enqueued job (or the existing job on a duplicate dispatch), or
  /// `null` when the payment must not open the drawer (not a completed cash
  /// payment, or voided/cancelled). Throws [ArgumentError] for missing ids and
  /// [StateError] for an unauthorized session.
  Future<PrintJob?> enqueueKick(CashDrawerKickInput input) async {
    input.validateForKick(); // throws on missing ids / unauthorized session
    if (!input.shouldKick) {
      return null; // non-cash / not-completed / voided / cancelled → no kick
    }

    final localOperationId = localOperationIdFor(input.paymentId);
    final now = _clock();

    return _spool.enqueue(
      PrintJob(
        id: localOperationId,
        organizationId: input.organizationId,
        branchId: input.branchId,
        deviceId: input.deviceId,
        localOperationId: localOperationId,
        jobType: PrintJobType.cashDrawer,
        document: const PrintDocument([PrintDrawerKickLine()]),
        maxRetries: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}
