import '../spool/print_job.dart';
import '../spool/print_spool.dart';
import 'customer_receipt_print_builder.dart';
import 'receipt_input.dart';
import 'receipt_rasterizer.dart';

/// Enqueues ORIGINAL customer-receipt print jobs into the RF-071 [PrintSpool]
/// (RF-073, approved D8).
///
/// Thin orchestration: validate the input (D9 gating) → build a money-free-of-
/// recomputation [PrintDocument] → enqueue a `receipt` job. It does NOT print,
/// drain the spool, or touch any transport. Idempotent per payment: the job's
/// `local_operation_id` is `receipt:<paymentId>` (D-022), so re-dispatching the
/// same payment collapses to the existing job (no duplicate receipt).
///
/// Reprint orchestration is intentionally NOT here — see the RF-073 report /
/// follow-up (RF-071's `reprint()` re-renders the original document and cannot
/// inject a freshly-built duplicate marker).
class ReceiptPrintDispatcher {
  ReceiptPrintDispatcher({
    required PrintSpool spool,
    ReceiptRasterizer? rasterizer,
    DateTime Function()? clock,
  }) : _spool = spool,
       _rasterizer = rasterizer,
       _clock = clock ?? DateTime.now;

  final PrintSpool _spool;

  /// Required only when an Arabic/Hebrew receipt is dispatched.
  final ReceiptRasterizer? _rasterizer;
  final DateTime Function() _clock;

  /// The deterministic idempotency / local-operation id for [paymentId].
  static String localOperationIdFor(String paymentId) => 'receipt:$paymentId';

  /// Validate, build, and enqueue the original receipt for [input] on [paper].
  /// Returns the enqueued job (or the existing job if it was already enqueued).
  Future<PrintJob> enqueueOriginalReceipt(
    ReceiptInput input,
    ReceiptPaperSpec paper,
  ) async {
    input.validateForOriginalPrint(); // D9 gating (throws on refusal)

    final document = await CustomerReceiptPrintBuilder.build(
      input: input,
      paper: paper,
      rasterizer: _rasterizer,
    );

    final localOperationId = localOperationIdFor(input.paymentId);
    final now = _clock();

    return _spool.enqueue(
      PrintJob(
        id: localOperationId,
        organizationId: input.organizationId,
        branchId: input.branchId,
        deviceId: input.deviceId,
        localOperationId: localOperationId,
        jobType: PrintJobType.receipt,
        document: document,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}
