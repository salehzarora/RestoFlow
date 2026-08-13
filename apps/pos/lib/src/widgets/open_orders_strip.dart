import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_actions_assembly.dart';
import '../data/order_center_view.dart';
import '../data/recent_order.dart';
import '../state/order_sync_controller.dart';
import '../state/recent_orders_controller.dart';
import 'order_detail_preview.dart';
import 'order_status_pills.dart';

/// POS-OPEN-ORDERS-STRIP-011 — the horizontal OPEN-ORDERS strip on the POS
/// main screen: every currently-open order as a compact tappable card between
/// the category deck and the product grid.
///
/// A PRESENTATION layer only, over the one authoritative collection:
///  * membership = `sectionContains(PosOrderSection.open, o)` over
///    `posRecentOrdersControllerProvider` — the exact Orders-center "Open"
///    predicate. The strip never adds, removes or re-sorts rows itself; the
///    controller update + predicate own membership, so a terminal snapshot
///    drops the card on the same rebuild that updates the sheet.
///  * actions = the SAME [PosOrderActionsAssembly] verdicts the Orders sheet
///    renders; tapping a card opens the exact existing
///    [OrderDetailPreview.show] surface with them.
///  * freshness = local writes repaint instantly (provider state); server
///    truth arrives through the EXISTING resilience pull —
///    `addVisibleConsumer()` — at its existing cadence. Event-driven
///    invalidation (RF-058-style branch hints) is the intended primary
///    freshness path but is BLOCKED on a backend authorization gate: the
///    POS's anonymous device principal cannot pass the membership-only
///    `realtime.messages` policy (rf058_kds_realtime_hints.sql), so the
///    subscription requires an owner-approved migration. Nothing here may
///    pretend otherwise.
///
/// The strip hides COMPLETELY when no order is open (no empty-state band) and
/// inherits the collection's operational window (today + yesterday) — the
/// same honest horizon every order surface shows.
class OpenOrdersStrip extends ConsumerStatefulWidget {
  const OpenOrdersStrip({super.key, this.compact = false});

  /// Denser band for the tightest supported viewports (compactLandscape):
  /// the strip must not make 1024x600 unusable.
  final bool compact;

  @override
  ConsumerState<OpenOrdersStrip> createState() => _OpenOrdersStripState();
}

/// How often the ELAPSED text re-renders. Text-only: the tick never touches
/// the network or the orders provider. Null (the default, and every test)
/// disables the timer — `main.dart` sets one minute for the real app, the
/// same injection pattern as `posSyncPollIntervalProvider`, so
/// `pumpAndSettle` can never hang on it.
final posOpenOrdersElapsedTickProvider = Provider<Duration?>((ref) => null);

class _OpenOrdersStripState extends ConsumerState<OpenOrdersStrip> {
  Timer? _elapsedTick;
  PosOrderSyncController? _sync;

  @override
  void initState() {
    super.initState();
    // Register as a VISIBLE consumer of the order-snapshot pull, like the
    // Orders sheet: the existing resilience refresh (unchanged cadence) runs
    // while the strip is mounted, and reference counting keeps sheet+strip
    // to one timer. This is the FALLBACK healing path, not the primary
    // freshness contract (see the class doc). Unlike the modal sheet, the
    // strip does NOT fire the immediate push-sweep+pull: it mounts at app
    // start, where PosSyncLifecycle already runs that exact sequence.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sync = ref.read(posOrderSyncControllerProvider.notifier);
      _sync = sync;
      sync.addVisibleConsumer(syncImmediately: false);
    });
    final tick = ref.read(posOpenOrdersElapsedTickProvider);
    if (tick != null) {
      _elapsedTick = Timer.periodic(tick, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _elapsedTick?.cancel();
    _sync?.removeVisibleConsumer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final orders = ref.watch(posRecentOrdersControllerProvider);
    // The canonical Open predicate over the ALREADY newest-first collection —
    // membership and order both belong to the controller, never to the strip.
    final open = [
      for (final o in orders)
        if (sectionContains(PosOrderSection.open, o)) o,
    ];
    if (open.isEmpty) return const SizedBox.shrink();

    final assembly = PosOrderActionsAssembly.watch(ref, orders);
    final now = ref.watch(posSyncClockProvider)();
    // Accessibility scale: the band grows (bounded) with the text setting so
    // the number + status rows always FIT — the metadata line is shed first
    // (see the card), and beyond 1.5x the band stops growing.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height = (widget.compact ? 74.0 : 90.0) * textScale.clamp(1.0, 1.5);

    return SizedBox(
      key: const Key('open-orders-strip'),
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          widget.compact ? 6 : RestoflowSpacing.sm,
          RestoflowSpacing.lg,
          0,
        ),
        itemCount: open.length,
        separatorBuilder: (_, _) => const SizedBox(width: RestoflowSpacing.sm),
        itemBuilder: (context, i) {
          final order = open[i];
          return _OpenOrderCard(
            order: order,
            l10n: l10n,
            now: now,
            compact: widget.compact,
            onTap: () => OrderDetailPreview.show(
              context,
              order: order,
              actions: assembly.resolveFor(order),
            ),
          );
        },
      ),
    );
  }
}

/// The strip's soft URGENCY tint — deliberately strip-local and DISTINCT from
/// the canonical [orderStatusTone] pill mapping (which other surfaces pin):
/// here red means "the kitchen has not accepted yet", yellow "being prepared",
/// green "ready/collected". Soft semantic CONTAINERS only — never the
/// saturated accents, and never color alone (the card always carries the
/// status text + icon).
RestoflowTone posOpenOrderStripTone(String? status) => switch (status) {
  'submitted' => RestoflowTone.danger,
  'accepted' || 'preparing' => RestoflowTone.warning,
  'ready' || 'served' => RestoflowTone.success,
  // Null (offline-submitted, not yet confirmed) and unknown tokens stay
  // NEUTRAL: nothing was refused, nothing is known — the pending affordance
  // says so in words.
  _ => RestoflowTone.neutral,
};

/// Compact localized elapsed-open label. Clock skew (a snapshot stamped ahead
/// of this device's clock) clamps to "now" rather than counting negative.
String posOpenOrderElapsedLabel(
  AppLocalizations l10n,
  DateTime now,
  DateTime openedAt,
) {
  final elapsed = now.difference(openedAt);
  if (elapsed.inMinutes < 1) return l10n.posOpenOrdersElapsedNow;
  if (elapsed.inMinutes < 60) {
    return l10n.posOpenOrdersElapsedMinutes(elapsed.inMinutes);
  }
  return l10n.posOpenOrdersElapsedHoursMinutes(
    elapsed.inHours,
    elapsed.inMinutes % 60,
  );
}

class _OpenOrderCard extends StatelessWidget {
  const _OpenOrderCard({
    required this.order,
    required this.l10n,
    required this.now,
    required this.compact,
    required this.onTap,
  });

  final PosRecentOrder order;
  final AppLocalizations l10n;
  final DateTime now;
  final bool compact;
  final VoidCallback onTap;

  /// customer · table, table only, customer only — or the order-type label
  /// when neither is known. Customer is the DEVICE-OWNED order-time name; a
  /// branch-discovered order simply has none here (the preview's
  /// authoritative fetch shows it) — we show what we have and invent nothing.
  String _meta() {
    final parts = <String>[
      if (order.order?.customerName case final c? when c.trim().isNotEmpty)
        c.trim(),
      if (order.tableLabel case final t? when t.trim().isNotEmpty)
        '${l10n.posTableLabel} ${t.trim()}',
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    return switch (order.orderType) {
      OrderType.dineIn => l10n.posOrderTypeDineIn,
      OrderType.takeaway => l10n.posOrderTypeTakeaway,
      // A discovered row whose snapshot carried no type: no metadata rather
      // than an invented one.
      null => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = order.serverStatus;
    final tone = posOpenOrderStripTone(status).styleOf(theme);
    final statusLabel = status == null
        ? l10n.posOfflineAwaitingSync
        : orderStatusLabelFor(l10n, status, order.orderType);
    final statusIcon = status == null ? Icons.sync : orderStatusIcon(status);
    final elapsed = posOpenOrderElapsedLabel(l10n, now, order.sortAt);
    // 2x text scale: the metadata line is the first thing shed — the order
    // number and the status always survive inside the fixed band.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final showMeta = !compact || textScale <= 1.3;
    final meta = _meta();

    return Semantics(
      button: true,
      label: [order.orderNumber, meta, statusLabel, elapsed].join(', '),
      child: Material(
        color: tone.container,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('open-strip-order-${order.orderNumber}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: compact ? 164 : 184,
            padding: EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.md,
              compact ? 6 : 8,
              RestoflowSpacing.md,
              compact ? 6 : 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tone.accent.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.orderNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 12.5 : 13.5,
                          color: kRestoflowInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // The elapsed label yields rather than overflowing: long
                    // localized hour forms (he) scale down inside a bounded
                    // box, the number always keeps its space.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 84),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          elapsed,
                          maxLines: 1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: compact ? 10 : 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (showMeta && textScale <= 1.6 && meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: compact ? 11 : 12,
                      color: kRestoflowInk2,
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      statusIcon,
                      size: compact ? 12 : 14,
                      color: tone.accent,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: compact ? 10.5 : 11.5,
                          fontWeight: FontWeight.w700,
                          color: tone.onContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
