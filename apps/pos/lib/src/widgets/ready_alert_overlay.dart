import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/ready_notifications_controller.dart';
import 'ready_notifications_sheet.dart';

/// PSC-001A — the ONE visible ready alert (a Stack child of the POS body).
///
/// One banner at a time: an individual card for a single arrival, a grouped
/// "N orders ready" card when several land together (the controller owns the
/// queue and its overflow-collapse). Prominent, never blocking, never a
/// stack of banners. Dismissing hides the banner and marks NOTHING read.
///
/// Reduced motion (the KDS finite-highlight convention): with animations
/// disabled the card appears/disappears statically; otherwise ONE finite
/// entrance — never a repeating animation. Each alert is announced to screen
/// readers exactly ONCE (per alert id — a repoll, resume, or status refresh
/// never re-announces).
class ReadyAlertOverlay extends ConsumerStatefulWidget {
  const ReadyAlertOverlay({super.key});

  @override
  ConsumerState<ReadyAlertOverlay> createState() => _ReadyAlertOverlayState();
}

class _ReadyAlertOverlayState extends ConsumerState<ReadyAlertOverlay> {
  int _announcedAlertId = 0;

  String _messageFor(AppLocalizations l10n, PosReadyAlert alert) {
    if (alert.isGrouped) return l10n.posReadyGroupedAlert(alert.items.length);
    final record = alert.items.single;
    final line = record.isServiceRound
        ? l10n.posReadyAdditionReady(record.roundNumber ?? 0)
        : l10n.posReadyOrderReady;
    final table = record.tableLabel;
    final context = table == null || table.trim().isEmpty
        ? record.orderCode
        : '${record.orderCode} · ${l10n.posTableLabel} $table';
    return '$line · $context';
  }

  void _announceOnce(PosReadyAlert alert, String message) {
    if (_announcedAlertId >= alert.id) return;
    _announcedAlertId = alert.id;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final alert = ref.watch(
      posReadyNotificationsControllerProvider.select((s) => s.activeAlert),
    );
    if (alert == null) return const SizedBox.shrink();
    final message = _messageFor(l10n, alert);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _announceOnce(alert, message);
    });

    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final isPhone =
        MediaQuery.sizeOf(context).width < RestoflowBreakpoints.posTwoPane;
    final tone = RestoflowTone.info.styleOf(theme);

    final card = Material(
      key: Key('ready-alert-${alert.id}'),
      color: tone.container,
      borderRadius: BorderRadius.circular(RestoflowRadii.lg),
      elevation: 3,
      child: InkWell(
        key: const Key('ready-alert-open'),
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        onTap: () {
          final controller = ref.read(
            posReadyNotificationsControllerProvider.notifier,
          );
          controller.dismissAlert();
          if (alert.isGrouped) {
            ReadyNotificationsSheet.show(context);
          } else {
            openReadyNotification(context, ref, alert.items.single);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RestoflowSpacing.md,
            vertical: RestoflowSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: RestoflowIconSizes.md,
                color: tone.accent,
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Flexible(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tone.accent,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              IconButton(
                key: const Key('ready-alert-dismiss'),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close, size: RestoflowIconSizes.sm),
                color: tone.accent,
                visualDensity: VisualDensity.compact,
                onPressed: () => ref
                    .read(posReadyNotificationsControllerProvider.notifier)
                    .dismissAlert(),
              ),
            ],
          ),
        ),
      ),
    );

    // ONE finite entrance; static under reduced motion. Keyed by alert id so
    // a REPLACED alert re-runs the (finite) entrance, never a loop.
    final animated = reducedMotion
        ? card
        : TweenAnimationBuilder<double>(
            key: ValueKey('ready-alert-anim-${alert.id}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, -8 * (1 - t)),
                child: child,
              ),
            ),
            child: card,
          );

    return PositionedDirectional(
      top: RestoflowSpacing.sm,
      start: isPhone ? RestoflowSpacing.lg : null,
      end: RestoflowSpacing.lg,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isPhone ? double.infinity : 420),
        child: animated,
      ),
    );
  }
}
