import '../print_document.dart';
import 'print_job_state.dart';

/// The kind of artifact a print job produces (RF-071). Templates/content are
/// RF-072 (kitchen) / RF-073 (receipt); RF-071 only tags the job.
enum PrintJobType {
  receipt('receipt'),
  kitchenTicket('kitchen_ticket');

  const PrintJobType(this.wireName);
  final String wireName;

  static PrintJobType fromWire(String wire) {
    for (final t in PrintJobType.values) {
      if (t.wireName == wire) return t;
    }
    throw ArgumentError.value(wire, 'wire', 'Unknown PrintJobType');
  }
}

/// Sentinel for [PrintJob.copyWith] to distinguish "leave unchanged" from
/// "set to null" on nullable fields.
const Object _unset = Object();

/// One durable print job in the spool (RF-071, DOMAIN_MODEL §9.1).
///
/// Carries the render-neutral [document] (re-rendered to bytes via the RF-070
/// adapter at print time — A4), tenant scope, the idempotency key
/// `(deviceId, localOperationId)` (D-022), retry bookkeeping, and reprint
/// linkage. NO money columns — text in [document] is caller-pre-formatted
/// (D-007/D-008).
class PrintJob {
  const PrintJob({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.deviceId,
    required this.localOperationId,
    required this.jobType,
    required this.document,
    required this.createdAt,
    required this.updatedAt,
    this.status = PrintJobState.created,
    this.stationId,
    this.retryCount = 0,
    this.maxRetries = 12,
    this.nextAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.reprintOf,
    this.reprintReason,
    this.printedAt,
    this.abandonedAt,
  });

  final String id;
  final String organizationId;
  final String branchId;
  final String deviceId;

  /// nullable station scope (set for kitchen-station tickets).
  final String? stationId;

  /// Idempotency key part (D-022): unique with [deviceId].
  final String localOperationId;

  final PrintJobType jobType;
  final PrintJobState status;

  /// The render-neutral document (re-rendered to bytes at print time).
  final PrintDocument document;

  final int retryCount;
  final int maxRetries;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  /// The original job id this is a reprint of (null for an original job).
  final String? reprintOf;

  /// The mandatory reason captured when this is a reprint (null otherwise).
  final String? reprintReason;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? printedAt;
  final DateTime? abandonedAt;

  /// Whether this job is a reprint of another.
  bool get isReprint => reprintOf != null;

  PrintJob copyWith({
    PrintJobState? status,
    int? retryCount,
    int? maxRetries,
    Object? nextAttemptAt = _unset,
    Object? lastErrorCode = _unset,
    Object? lastErrorMessage = _unset,
    DateTime? updatedAt,
    Object? printedAt = _unset,
    Object? abandonedAt = _unset,
  }) {
    return PrintJob(
      id: id,
      organizationId: organizationId,
      branchId: branchId,
      deviceId: deviceId,
      stationId: stationId,
      localOperationId: localOperationId,
      jobType: jobType,
      document: document,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      nextAttemptAt: nextAttemptAt == _unset
          ? this.nextAttemptAt
          : nextAttemptAt as DateTime?,
      lastErrorCode: lastErrorCode == _unset
          ? this.lastErrorCode
          : lastErrorCode as String?,
      lastErrorMessage: lastErrorMessage == _unset
          ? this.lastErrorMessage
          : lastErrorMessage as String?,
      reprintOf: reprintOf,
      reprintReason: reprintReason,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      printedAt: printedAt == _unset ? this.printedAt : printedAt as DateTime?,
      abandonedAt: abandonedAt == _unset
          ? this.abandonedAt
          : abandonedAt as DateTime?,
    );
  }
}
