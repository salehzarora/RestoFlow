import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/sync_cursor_store.dart';

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

/// Safe local evidence, never a claim about paper or a server attempt UUID.
/// No payload, destination, credential or writable spool handle crosses here.
class WebOrderPrintHistoryIssue {
  const WebOrderPrintHistoryIssue({
    required this.scope,
    required this.localJobId,
    required this.dispatchId,
    required this.createdAt,
    required this.localStatus,
    required this.attemptCount,
    required this.lastAttemptAt,
    required this.errorCode,
    required this.terminalCode,
    required this.supersededByDispatchId,
    required this.outcome,
  });

  final PosSyncScope scope;
  final String localJobId, dispatchId, localStatus;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? errorCode, terminalCode, supersededByDispatchId;
  final WebOrderPrintOutcome outcome;

  bool get reviewable => const {
    'blocked_configuration',
    'possibly_printed',
    'failed_retryable',
  }.contains(localStatus);

  /// Exact local attempt and meaningful failure evidence. Routine ACK retries,
  /// refresh/update timestamps and unrelated successful printing are excluded.
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            1,
            scope.organizationId,
            scope.restaurantId,
            scope.branchId,
            scope.deviceId,
            localJobId,
            dispatchId,
            createdAt.toUtc().toIso8601String(),
            attemptCount,
            lastAttemptAt?.toUtc().toIso8601String(),
            localStatus,
            errorCode,
            terminalCode,
            supersededByDispatchId,
          ]),
        ),
      )
      .toString();
}

class WebOrderPrintHistory {
  WebOrderPrintHistory({
    Iterable<WebOrderPrintHistoryIssue> issues = const [],
    this.unidentifiedOutcome,
  }) : issues = List.unmodifiable(issues);

  final List<WebOrderPrintHistoryIssue> issues;

  /// Read failure/legacy aggregate: visible, but cannot be marked reviewed.
  final WebOrderPrintOutcome? unidentifiedOutcome;

  WebOrderPrintOutcome? get outcome {
    if (unidentifiedOutcome != null) return unidentifiedOutcome;
    if (issues.isEmpty) return null;
    if (issues.any(
      (i) => i.outcome == WebOrderPrintOutcome.reconciliationRequired,
    )) {
      return WebOrderPrintOutcome.reconciliationRequired;
    }
    if (issues.any((i) => i.outcome == WebOrderPrintOutcome.failed)) {
      return WebOrderPrintOutcome.failed;
    }
    return WebOrderPrintOutcome.attention;
  }
}

abstract interface class PosWebOrderPrintHistoryHooks {
  Future<WebOrderPrintHistory?> readWebPrintHistory();
}
