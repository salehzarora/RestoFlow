import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../pos_palette.dart' show kPosCompactAppBarWidth;
import '../state/local_storage_health_provider.dart';
import '../state/outbox_controller.dart';
import 'outbox_status_summary.dart';
import 'sync_details_sheet.dart';

/// RF-114 / POS-SYNC-VISIBILITY-001: the app-bar indicator of the order
/// OUTBOX's aggregate sync state, so the cashier can keep taking orders while
/// earlier ones sync.
///
/// Aggregation and priority live in [PosOutboxStatusSummary] and are unchanged:
/// storage > failed > resolved > attention > syncing > pending > synced, and
/// "All orders synced" is still reached only when nothing non-final remains.
///
/// TWO things changed in POS-SYNC-VISIBILITY-001, both because an operator has
/// to be able to PROVE the queue is empty before the app is uninstalled:
///
///  1. It is ALWAYS VISIBLE. It used to render `SizedBox.shrink()` whenever the
///     queue was empty and storage was healthy ("no clutter"). That is exactly
///     the state a tablet is in before the first order of the day — so the one
///     moment the pre-migration gate needs to read "All orders synced", there
///     was nothing in the header at all. An absent chip and a healthy chip
///     looked identical, and neither could be cited as evidence.
///
///  2. Tapping it OPENS DETAILS instead of acting. A tap used to run retry-all
///     or clear-resolved depending on which state happened to be showing:
///     reading the till's status could re-queue its failed orders. Reading and
///     acting are now separate surfaces, and every action asks first.
///
/// RTL-safe (a plain [Row]; the framework mirrors it under an RTL Directionality).
class OutboxStatusIndicator extends ConsumerWidget {
  const OutboxStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summary = PosOutboxStatusSummary.from(
      entries: ref.watch(outboxControllerProvider),
      storage: ref.watch(posLocalStorageHealthProvider),
    );

    final label = summary.label(l10n);
    final color = summary.toneOf(theme);

    // PSC-001A compact app bar: below the compact width the TEXT label yields
    // (the five actions must all fit); the icon, spinner, colors and the FULL
    // label via tooltip + semantics all remain — the state is never hidden,
    // only its prose. Never colour alone: the tooltip and the semantics label
    // always carry the words.
    final compact = MediaQuery.sizeOf(context).width < kPosCompactAppBarWidth;
    final chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: RestoflowSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (summary.syncing > 0)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(summary.icon, size: 18, color: color),
          if (!compact) ...[
            const SizedBox(width: RestoflowSpacing.xs),
            // Flexible so a long localized label (ar/he) can ellipsize instead
            // of overflowing the action row on a narrower tablet.
            Flexible(
              child: Text(
                label,
                key: const Key('outbox-status-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ),
          ],
        ],
      ),
    );

    // [POS-OFFLINE-OPERATIONS-002] AUTH_HOLD carries its own explanation in
    // the tooltip: the count alone ("2 awaiting sign-in") does not tell the
    // operator that signing in — not retrying — is what resumes the sync.
    final tooltip = summary.isAuthHoldHeadline
        ? '$label\n${l10n.posOutboxAuthHoldTooltip}'
        : label;

    // A 44dp minimum target in BOTH presentations — it is a real button now.
    final sized = Tooltip(
      key: compact
          ? const Key('outbox-status-compact')
          : const Key('outbox-status-tooltip'),
      message: tooltip,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: compact
            ? chip
            // Bound the label on wide bars too, so ar/he prose cannot push the
            // neighbouring actions off the edge.
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: chip,
              ),
      ),
    );

    final spoken = summary.storageHealthy
        ? '$label. ${l10n.posSyncDetailsTitle}'
        : '$label. ${l10n.posStorageNeedsAttention}';

    return Semantics(
      button: true,
      label: spoken,
      child: InkWell(
        key: const Key('outbox-status-indicator'),
        // Opening a read-only sheet. This performs NO outbox mutation.
        onTap: () => PosSyncDetailsSheet.show(context),
        child: Center(child: sized),
      ),
    );
  }
}
