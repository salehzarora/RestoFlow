import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'kitchen_dispatch_import_coordinator.dart';

/// KITCHEN-MODE-001C2B-CORRECTION-001 — the bounded dormant drain seam:
/// pull one page → import every row DURABLY → acknowledge
/// imported/blocked_configuration → forward the EXACT three-field cursor →
/// next page → stop safely.
///
/// This coordinator owns paging and typed stop classification only. It is
/// invoked exclusively by [PosKitchenSpoolRuntime] for a TRUSTED
/// printer-only-with-revision mode state — which the production mode
/// repository can NEVER construct today (D1: the getter exposes no
/// revision), and which the server independently refuses to serve without a
/// readiness report (`readiness_required`) that nothing files until 001C3.
/// Tests inject the trusted state explicitly.
///
/// Fatal database/key/storage failures deliberately PROPAGATE (they must
/// stop the drain and surface typed at the runtime boundary — a broad catch
/// here could silently break the durable-before-ack guarantee). Row-local
/// payload failures are absorbed inside the import coordinator.
enum KitchenDrainStopReason {
  /// The server reported no further pages (`has_more` false).
  complete,

  /// A page arrived with zero dispatches — nothing left to drain.
  emptyPage,

  readinessRequired,
  branchNotPrinterOnly,
  invalidSession,

  /// Network-class pull failure; safe to retry on a later cadence tick.
  transientFailure,

  /// Non-transient server-side pull failure.
  serverFailure,

  /// The server rejected the forwarded cursor tuple.
  invalidCursor,

  /// Structurally invalid page (including `has_more` without a cursor).
  malformedPage,

  /// The server returned the SAME cursor tuple again — aborting instead of
  /// looping forever.
  cursorStalled,

  /// The 50-page safety cap was reached with more pages still promised.
  pageCapExceeded,

  /// Runtime-produced (never by the drain loop itself): the dedicated spool
  /// database could not be opened.
  databaseUnavailable,

  /// Runtime-produced: the spool key is missing-over-rows / corrupted /
  /// unavailable (D3 — never wiped, never regenerated).
  keyUnavailable,

  /// Runtime-produced: the restored device scope is incomplete/mismatched.
  scopeMismatch,

  /// Runtime-produced: the kitchen destination could not be determined at
  /// all (distinct from a DEFINITIVE blocked resolution, which imports as
  /// blockedConfiguration).
  destinationUnresolvable,
}

/// Closed, safe-scalar drain report. Never contains payloads, endpoints,
/// tokens, customer data, money, or raw server exceptions.
final class KitchenDispatchDrainReport {
  const KitchenDispatchDrainReport({
    required this.stoppedReason,
    this.pagesPulled = 0,
    this.rowsReceived = 0,
    this.rowsImported = 0,
    this.rowsAlreadyPresent = 0,
    this.rowsBlockedConfiguration = 0,
    this.rowsRejected = 0,
    this.rowsLocalStateConflict = 0,
    this.acknowledgementsSucceeded = 0,
    this.acknowledgementsPending = 0,
    this.acknowledgementsTerminal = 0,
  });

  final KitchenDrainStopReason stoppedReason;
  final int pagesPulled;
  final int rowsReceived;
  final int rowsImported;
  final int rowsAlreadyPresent;
  final int rowsBlockedConfiguration;
  final int rowsRejected;
  final int rowsLocalStateConflict;
  final int acknowledgementsSucceeded;

  /// Acknowledgements persisted for RETRY (durable; the pending-ack
  /// coordinator re-drives them on later cadence ticks).
  final int acknowledgementsPending;
  final int acknowledgementsTerminal;

  /// Whether the drain finished without an error-class stop.
  bool get isSuccess =>
      stoppedReason == KitchenDrainStopReason.complete ||
      stoppedReason == KitchenDrainStopReason.emptyPage;
}

final class KitchenDispatchDrainCoordinator {
  KitchenDispatchDrainCoordinator({
    required SupabaseKitchenDispatchPullRepository pullRepository,
    required KitchenDispatchImportCoordinator importCoordinator,
    int pageLimit = 20,
    int maxPages = 50,
  }) : assert(pageLimit >= 1 && pageLimit <= 50),
       assert(maxPages >= 1 && maxPages <= 50),
       _pullRepository = pullRepository,
       _importCoordinator = importCoordinator,
       _pageLimit = pageLimit,
       _maxPages = maxPages;

  final SupabaseKitchenDispatchPullRepository _pullRepository;
  final KitchenDispatchImportCoordinator _importCoordinator;
  final int _pageLimit;
  final int _maxPages;

  Future<KitchenDispatchDrainReport> drain() async {
    KitchenDispatchCursor? cursor;
    var pageCount = 0;
    var pagesPulled = 0;
    var rowsReceived = 0, rowsImported = 0, rowsAlreadyPresent = 0;
    var rowsBlocked = 0, rowsRejected = 0, rowsConflict = 0;
    var acked = 0, pending = 0, terminal = 0;

    KitchenDispatchDrainReport report(KitchenDrainStopReason reason) =>
        KitchenDispatchDrainReport(
          stoppedReason: reason,
          pagesPulled: pagesPulled,
          rowsReceived: rowsReceived,
          rowsImported: rowsImported,
          rowsAlreadyPresent: rowsAlreadyPresent,
          rowsBlockedConfiguration: rowsBlocked,
          rowsRejected: rowsRejected,
          rowsLocalStateConflict: rowsConflict,
          acknowledgementsSucceeded: acked,
          acknowledgementsPending: pending,
          acknowledgementsTerminal: terminal,
        );

    while (true) {
      // 1–2: pull with the current FULL cursor; every failure is typed.
      final result = await _pullRepository.pull(
        limit: _pageLimit,
        cursor: cursor,
      );
      final KitchenDispatchPullPage page;
      switch (result) {
        case KitchenDispatchPullSuccess(page: final successPage):
          page = successPage;
        case KitchenDispatchPullFailure(:final error):
          return report(switch (error) {
            KitchenDispatchPullError.invalidSession =>
              KitchenDrainStopReason.invalidSession,
            KitchenDispatchPullError.branchNotPrinterOnly =>
              KitchenDrainStopReason.branchNotPrinterOnly,
            KitchenDispatchPullError.readinessRequired =>
              KitchenDrainStopReason.readinessRequired,
            KitchenDispatchPullError.invalidCursor =>
              KitchenDrainStopReason.invalidCursor,
            KitchenDispatchPullError.invalidLimit =>
              KitchenDrainStopReason.malformedPage,
            KitchenDispatchPullError.transientFailure =>
              KitchenDrainStopReason.transientFailure,
            KitchenDispatchPullError.permissionDenied =>
              KitchenDrainStopReason.invalidSession,
            KitchenDispatchPullError.malformedResponse =>
              KitchenDrainStopReason.malformedPage,
            KitchenDispatchPullError.serverFailure =>
              KitchenDrainStopReason.serverFailure,
          });
      }
      pagesPulled++;
      rowsReceived += page.dispatches.length;

      // 3: an empty page ends the drain successfully.
      if (page.dispatches.isEmpty) {
        return report(KitchenDrainStopReason.emptyPage);
      }

      // 4: the ENTIRE page imports durably (fatal storage/key errors
      // propagate) before any next-page decision.
      final summary = await _importCoordinator.importDispatches(
        page.dispatches,
      );
      rowsImported += summary.imported;
      rowsAlreadyPresent += summary.duplicates;
      rowsBlocked += summary.blocked;
      rowsRejected += summary.rejected;
      rowsConflict += summary.localStateConflicts;
      acked += summary.acked;
      pending += summary.ackRetriesScheduled;
      terminal += summary.ackTerminal;

      // 5–8: only now inspect pagination.
      if (!page.hasMore) return report(KitchenDrainStopReason.complete);
      final next = page.nextCursor;
      if (next == null) return report(KitchenDrainStopReason.malformedPage);
      if (cursor != null &&
          next.createdAt == cursor.createdAt &&
          next.typeRank == cursor.typeRank &&
          next.id == cursor.id) {
        return report(KitchenDrainStopReason.cursorStalled);
      }

      // 9–11: bounded continuation with the exact three-field tuple.
      pageCount++;
      if (pageCount >= _maxPages) {
        return report(KitchenDrainStopReason.pageCapExceeded);
      }
      cursor = next;
    }
  }
}
