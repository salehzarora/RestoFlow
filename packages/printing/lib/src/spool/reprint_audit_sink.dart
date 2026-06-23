import 'print_job.dart';

/// A structured reprint-audit record (RF-071, PRINTERS §8.4 / DECISION D-013).
///
/// Captures who reprinted, why, and the link to the original artifact. RF-071
/// emits this to a [ReprintAuditSink] PORT only; the literal server
/// `audit_events` write is a deferred follow-up (it requires a SECURITY DEFINER
/// RPC + sync_push op, out of RF-071 scope per approved A1).
class ReprintAuditEntry {
  const ReprintAuditEntry({
    required this.originalJobId,
    required this.newJobId,
    required this.reason,
    required this.jobType,
    required this.organizationId,
    required this.branchId,
    required this.deviceId,
    this.stationId,
    this.actorId,
  });

  /// The original job/artifact being reprinted.
  final String originalJobId;

  /// The new reprint job created.
  final String newJobId;

  /// The mandatory reprint reason (PRINTERS §8.4 requires it).
  final String reason;

  final PrintJobType jobType;
  final String organizationId;
  final String branchId;
  final String deviceId;
  final String? stationId;

  /// Optional actor context (employee/app-user id) when known to the caller.
  /// RF-071 does not resolve identity; the deferred server RPC derives the
  /// authoritative actor from the PIN session.
  final String? actorId;

  @override
  String toString() =>
      'ReprintAuditEntry(reprint of $originalJobId -> $newJobId, '
      '$jobType, reason="$reason")';
}

/// A port that records reprint-audit intents (RF-071).
///
/// Implementations forward the entry to durable/audited storage. RF-071 ships
/// only the port + an in-memory fake (tests); no Supabase dependency.
abstract class ReprintAuditSink {
  Future<void> record(ReprintAuditEntry entry);
}

/// An in-memory [ReprintAuditSink] for tests: records every entry in order.
class InMemoryReprintAuditSink implements ReprintAuditSink {
  final List<ReprintAuditEntry> entries = [];

  @override
  Future<void> record(ReprintAuditEntry entry) async => entries.add(entry);
}
