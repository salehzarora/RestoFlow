import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_submission.dart';
import '../state/local_storage_health_provider.dart';

/// POS-SYNC-VISIBILITY-001 — the ONE aggregation of outbox state.
///
/// The header chip and the sync-details sheet both read this, so an operator
/// running a migration gate can never be shown "All orders synced" in one place
/// and something else in the other.
///
/// The RF-114 aggregation is preserved EXACTLY, including its conservative
/// priority — storage > failed > resolved > attention > syncing > pending >
/// synced. "All orders synced" is still reached only when nothing non-final
/// remains; ambiguous states never fall through to it.
class PosOutboxStatusSummary {
  const PosOutboxStatusSummary({
    required this.failed,
    required this.resolved,
    required this.attention,
    required this.syncing,
    required this.pending,
    required this.storageHealthy,
    required this.storageWriteRefused,
    required this.storageUnreadable,
    required this.totalEntries,
  });

  factory PosOutboxStatusSummary.from({
    required List<OutboxEntry> entries,
    required PosLocalStorageHealth storage,
  }) {
    var failed = 0;
    var resolved = 0;
    var attention = 0;
    var syncing = 0;
    var pending = 0;
    for (final e in entries) {
      if (e.isDismissibleResolvedFailure) {
        resolved++;
        continue;
      }
      if (e.hasDefinitiveVerdict) {
        attention++;
        continue;
      }
      switch (e.syncState) {
        case OutboxSyncState.rejected:
        case OutboxSyncState.dead:
          failed++;
        case OutboxSyncState.conflict:
        case OutboxSyncState.resolved:
          attention++;
        case OutboxSyncState.inFlight:
          syncing++;
        case OutboxSyncState.created:
        case OutboxSyncState.pending:
          pending++;
        case OutboxSyncState.applied:
          break;
      }
    }
    return PosOutboxStatusSummary(
      failed: failed,
      resolved: resolved,
      attention: attention,
      syncing: syncing,
      pending: pending,
      storageHealthy: storage.isHealthy,
      storageWriteRefused: storage.writeRefused,
      storageUnreadable: storage.unreadableRecords,
      totalEntries: entries.length,
    );
  }

  final int failed;
  final int resolved;
  final int attention;
  final int syncing;
  final int pending;
  final bool storageHealthy;
  final bool storageWriteRefused;
  final int storageUnreadable;
  final int totalEntries;

  /// True only when nothing local is waiting, in flight, failed or ambiguous
  /// AND the durable store is healthy.
  ///
  /// An EMPTY queue satisfies this. That is the change this ticket makes: the
  /// indicator used to render nothing at all when the queue was empty ("no
  /// clutter"), which meant a tablet that had taken no orders yet showed no
  /// sync state whatsoever — exactly the moment the pre-migration gate needs to
  /// read one. "Nothing is waiting to send" and "everything sent has been
  /// confirmed" are the same fact for an operator about to uninstall the app.
  bool get isAllApplied =>
      storageHealthy &&
      failed == 0 &&
      resolved == 0 &&
      attention == 0 &&
      syncing == 0 &&
      pending == 0;

  IconData get icon {
    if (!storageHealthy) return Icons.sd_card_alert_outlined;
    if (failed > 0) return Icons.error_outline;
    if (resolved > 0) return Icons.playlist_remove_outlined;
    if (attention > 0) return Icons.warning_amber_outlined;
    if (syncing > 0) return Icons.sync;
    if (pending > 0) return Icons.schedule_outlined;
    return Icons.cloud_done_outlined;
  }

  RestoflowTone get tone {
    if (!storageHealthy) return RestoflowTone.danger;
    if (failed > 0) return RestoflowTone.danger;
    if (resolved > 0) return RestoflowTone.warning;
    if (attention > 0) return RestoflowTone.warning;
    if (syncing > 0) return RestoflowTone.info;
    if (pending > 0) return RestoflowTone.warning;
    return RestoflowTone.success;
  }

  Color toneOf(ThemeData theme) => tone.styleOf(theme).accent;

  /// The single headline. Identical in the chip and the sheet.
  String label(AppLocalizations l10n) {
    if (!storageHealthy) {
      return storageWriteRefused
          ? l10n.posStorageWriteRefused
          : l10n.posStorageUnreadable(storageUnreadable);
    }
    if (failed > 0) return l10n.posOutboxFailed(failed);
    if (resolved > 0) return l10n.posOutboxResolvedFailures(resolved);
    if (attention > 0) return l10n.posOutboxAttention;
    if (syncing > 0) return l10n.posOutboxSyncing;
    if (pending > 0) return l10n.posOutboxPending(pending);
    return l10n.posOutboxSynced;
  }

  /// Prose for the details sheet — says what the headline MEANS, because
  /// "All orders synced" is the sentence a migration decision rests on.
  String explanation(AppLocalizations l10n) {
    if (!storageHealthy) return l10n.posStorageNeedsAttention;
    if (failed > 0) return l10n.posSyncDetailsExplainFailed;
    if (resolved > 0) return l10n.posSyncDetailsExplainResolved;
    if (attention > 0) return l10n.posSyncDetailsExplainAttention;
    if (syncing > 0) return l10n.posSyncDetailsExplainSyncing;
    if (pending > 0) return l10n.posSyncDetailsExplainPending;
    return l10n.posSyncDetailsExplainSynced;
  }
}
