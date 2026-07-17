import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_status_chip.dart';

/// The honest per-ticket kitchen print-job status for the card (RF-115): a
/// localized label plus an optional Retry action (shown for failed /
/// bridge-unavailable / not-configured jobs). Money-free — it is chrome only.
class KdsTicketPrintStatus {
  const KdsTicketPrintStatus({
    required this.label,
    this.onRetry,
    this.isError = false,
    this.actionLabel,
  });

  final String label;

  /// Non-null => an action button is shown, wired to re-run the job (Retry for a
  /// failed job, Reprint for an already-sent one — see [actionLabel]).
  final VoidCallback? onRetry;

  /// PRINT-STABILITY-001: the action-button label. Null => "Retry" (the default,
  /// for failure states); a sent ticket passes the "Reprint" label so staff can
  /// print another money-free copy without changing any order state.
  final String? actionLabel;

  /// True for attention states (failed / bridge unavailable / not
  /// configured): the status line renders in the danger tone instead of the
  /// muted chrome color, so a print problem is visible from the pass
  /// (DESIGN-001 — previously failures looked identical to successes).
  final bool isError;
}

/// A polished KDS ticket card: a header row (the HUMAN order number — the same
/// `displayOrderCode` the POS shows — + colour-coded status chip), order-type/
/// table/station pills, large readable item lines with their modifier and note
/// sub-lines, the order-level note, and the status-gated lifecycle action.
///
/// RF-103: the action advances the ticket through its existing lifecycle —
/// Acknowledge / Start / Mark ready / Bump (forward, via [onAdvance]) and Recall
/// (via [onRecall]). Presentation only; the screen runs the existing
/// `KitchenTicketStateMachine`. No money is shown anywhere (SECURITY T-003).
///
/// Design-polish sprint: kitchen-readable type scale (the order number and item
/// lines read from across a pass), a 4px status-accent start edge matching the
/// chip's tone, warning-accent notes, and ≥48dp full-width actions.
class KdsTicketCard extends StatelessWidget {
  const KdsTicketCard({
    required this.ticket,
    required this.l10n,
    required this.onAdvance,
    required this.onRecall,
    this.printStatus,
    this.onReprint,
    this.highlightNew = false,
    this.newArrivalWindow = const Duration(seconds: 60),
    this.now,
    this.onAcknowledgeCancellation,
    this.ackPending = false,
    this.ackFailed = false,
    this.highlightCancelled = false,
    super.key,
  });

  final KdsTicketView ticket;
  final AppLocalizations l10n;

  /// KDS-ALERTS-AND-KITCHEN-COUNTS-002 (A1): an always-visible per-card reprint
  /// action. Non-null (the LIVE board) shows a compact Reprint control in the
  /// header that re-runs the money-free kitchen print for this ticket through
  /// the existing printer routing — it never creates an order or changes status.
  /// Null (demo / bare tests) hides it.
  final VoidCallback? onReprint;

  /// KDS-ALERTS-AND-KITCHEN-COUNTS-002 (A2): when true, the card shows a subtle,
  /// self-terminating attention glow so kitchen staff notice a newly-arrived
  /// order. The live board sets this only while the ticket is freshly in the
  /// "new" column and within [newArrivalWindow]; it stops on acknowledge (the
  /// card rebuilds with this false) or when the window elapses.
  final bool highlightNew;

  /// How long the new-arrival glow runs before it self-stops (A2). The animation
  /// fades out over this window, so it also stops even without a parent rebuild.
  final Duration newArrivalWindow;

  /// Reference clock for the elapsed pill (DESIGN-001). The board passes ONE
  /// build-time value so every card agrees; null falls back to
  /// [DateTime.now]. Deliberately no timer (the widget-test corpus
  /// `pumpAndSettle`s) — the live board rebuilds on every sync poll, which
  /// refreshes elapsed for free.
  final DateTime? now;

  /// Advance the ticket to [to] via the existing state machine (forward edges).
  final void Function(KitchenTicketStatus to) onAdvance;

  /// Recall a bumped ticket (existing audited `bumped -> in_preparation`).
  /// Null hides the action (the LIVE board — forward-only backend).
  final VoidCallback? onRecall;

  /// Optional kitchen print-job status (RF-115): a small honest line
  /// ("prepared — bridge required" / "sent to printer" / "failed" …) after the
  /// acknowledge trigger, with a Retry action on recoverable states. Null
  /// renders nothing (demo boards). Never money — chrome only.
  final KdsTicketPrintStatus? printStatus;

  /// PSC-001D: acknowledge this PENDING cancellation card (server-authoritative
  /// `order.void_ack` on the LIVE board). Null (demo / bare tests) renders no
  /// acknowledgement action — never a dead button.
  final VoidCallback? onAcknowledgeCancellation;

  /// PSC-001D: the acknowledgement is in flight — the button shows its honest
  /// pending state and blocks duplicate taps. The card is NEVER hidden before
  /// the authoritative pull confirms.
  final bool ackPending;

  /// PSC-001D: the last acknowledgement attempt failed — the card stays, a
  /// localized failure line appears, and the action remains retryable.
  final bool ackFailed;

  /// PSC-001D: one finite, reduce-motion-aware DANGER pulse when the
  /// cancellation card first appears (locked decision).
  final bool highlightCancelled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The HUMAN number leads; demo fixtures without one keep the ticket id.
    final ticketHeader =
        ticket.orderNumber ??
        '${l10n.kdsTicketLabel} ${ticket.kitchenTicketId}';
    final dineIn = ticket.orderType == 'dine_in';
    final takeaway = ticket.orderType == 'takeaway';
    final tableLabel = ticket.tableLabel;
    final customerName = ticket.customerName;
    final showStation =
        ticket.stationId != KdsTicketMapper.unassignedStation &&
        ticket.stationId.isNotEmpty;
    // The status accent shares the chip's tone map, so the edge and the chip
    // can never disagree; notes use the warning accent (a kitchen instruction
    // demands attention, and `tertiary` was unreadable on the dark board).
    final statusAccent = kdsStatusTone(ticket.status).styleOf(theme).accent;
    final noteColor = RestoflowTone.warning.styleOf(theme).accent;

    // Elapsed-since-submit pill (DESIGN-001): computed at build, no timer.
    // Urgency escalates through the shared thresholds (info → 10m warning →
    // 20m danger). Negative diffs (clock skew) clamp to 0. No submittedAt on
    // the view (older fixtures) => no pill — never a fabricated age.
    RestoflowStatusPill? elapsedPill;
    if (ticket.submittedAt case final submittedAt?) {
      final minutes = (now ?? DateTime.now()).difference(submittedAt).inMinutes;
      final clamped = minutes < 0 ? 0 : minutes;
      elapsedPill = RestoflowStatusPill(
        key: Key('elapsed-${ticket.kitchenTicketId}'),
        icon: Icons.schedule,
        label: l10n.kdsElapsedMinutes(clamped),
        tone: RestoflowUrgency.toneForMinutes(clamped),
        dense: false,
      );
    }

    // Cleared work steps back visually (DESIGN-001): a bumped ticket dims so
    // the active columns stay the loud ones. Cancelled keeps full contrast —
    // its danger accent IS the signal.
    final dimmed = ticket.status == KitchenTicketStatus.bumped;

    // PSC-001D: a PENDING-ACKNOWLEDGEMENT cancellation gets the FULL-CARD
    // danger treatment — the whole card fills with the danger container tone
    // and carries a strong danger ring, so the cancellation is unmistakable
    // from across the pass (never colour alone: the banner says it in words).
    final pendingAckCancellation = ticket.requiresAck;
    final dangerStyle = RestoflowTone.danger.styleOf(theme);

    final card = Card(
      margin: const EdgeInsetsDirectional.only(bottom: RestoflowSpacing.md),
      color: pendingAckCancellation
          ? dangerStyle.container
          : theme.colorScheme.surfaceContainerLow,
      child: Container(
        decoration: BoxDecoration(
          border: pendingAckCancellation
              // Full danger ring for the cancellation card…
              ? Border.all(color: dangerStyle.accent, width: 2)
              // …else the existing status-accent start edge, unchanged.
              : BorderDirectional(
                  start: BorderSide(color: statusAccent, width: 4),
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PSC-001D: the cancellation banner LEADS the card — a localized
              // title, the stop-preparing instruction and the honest void time.
              // Words, not colour alone. Money-free.
              if (pendingAckCancellation) ...[
                _CancelledBanner(
                  key: Key('kds-cancelled-banner-${ticket.kitchenTicketId}'),
                  l10n: l10n,
                  voidedAt: ticket.voidedAt,
                ),
                const SizedBox(height: RestoflowSpacing.sm),
              ],
              // KDS-ALERTS (C): a loud, unmistakable "New order" badge while the
              // ticket is freshly arrived, so the chef notices it from the pass —
              // paired with the stronger pulsing glow. Money-free chrome.
              if (highlightNew) ...[
                _NewOrderBadge(
                  key: Key('kds-new-badge-${ticket.kitchenTicketId}'),
                  label: l10n.kdsNewOrderBadge,
                ),
                const SizedBox(height: RestoflowSpacing.sm),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticketHeader,
                      // PRINT-LAYOUT-001: the order number reads from across the
                      // pass — one step larger than before.
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (elapsedPill != null) ...[
                    const SizedBox(width: RestoflowSpacing.sm),
                    elapsedPill,
                  ],
                  const SizedBox(width: RestoflowSpacing.sm),
                  KdsStatusChip(status: ticket.status),
                  // A1: the always-visible per-card Reprint control (LIVE board).
                  // Money-free; re-runs the existing kitchen print, never an
                  // order/status change.
                  if (onReprint != null) ...[
                    const SizedBox(width: RestoflowSpacing.xs),
                    IconButton(
                      key: Key('kds-reprint-${ticket.kitchenTicketId}'),
                      tooltip: l10n.printReprintAction,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.print_outlined),
                      onPressed: onReprint,
                    ),
                  ],
                ],
              ),
              if (dineIn ||
                  takeaway ||
                  tableLabel != null ||
                  customerName != null ||
                  showStation) ...[
                const SizedBox(height: RestoflowSpacing.sm),
                Wrap(
                  spacing: RestoflowSpacing.sm,
                  runSpacing: RestoflowSpacing.xs,
                  children: [
                    if (dineIn)
                      RestoflowStatusPill(
                        icon: Icons.restaurant,
                        label: l10n.posOrderTypeDineIn,
                      ),
                    if (takeaway)
                      RestoflowStatusPill(
                        icon: Icons.takeout_dining,
                        label: l10n.posOrderTypeTakeaway,
                      ),
                    if (tableLabel != null)
                      RestoflowStatusPill(
                        icon: Icons.event_seat,
                        label: '${l10n.posTableLabel} $tableLabel',
                      ),
                    // ORDER-CUSTOMER-001: the OPTIONAL customer name pill,
                    // compact + kitchen-friendly, next to table/type. Money-free.
                    if (customerName != null)
                      RestoflowStatusPill(
                        key: Key('customer-${ticket.kitchenTicketId}'),
                        icon: Icons.person_outline,
                        label:
                            '${l10n.customerNameKitchenLabel}: $customerName',
                      ),
                    if (showStation)
                      RestoflowStatusPill(
                        icon: Icons.kitchen_outlined,
                        label: '${l10n.kdsStationLabel}: ${ticket.stationId}',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: RestoflowSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: RestoflowSpacing.sm),
              // KDS-ALERTS-AND-KITCHEN-COUNTS-002: the unified WHOLE-ORDER kitchen
              // count summary — one prominent line PER RESOURCE (patties, buns,
              // …), combining the modifier-option and item-base counts. Shown
              // above the item details; hidden when the order carries no
              // configured count. Money-free.
              if (ticket.kitchenCounts.isNotEmpty) ...[
                _KitchenCountsSection(counts: ticket.kitchenCounts, l10n: l10n),
                const SizedBox(height: RestoflowSpacing.sm),
              ],
              for (final item in ticket.items)
                _ItemLine(item: item, l10n: l10n, noteColor: noteColor),
              if (ticket.notes case final note?) ...[
                const SizedBox(height: RestoflowSpacing.xs),
                Text(
                  '» ${l10n.kdsNoteLabel}: $note',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: noteColor,
                  ),
                ),
              ],
              if (printStatus case final status?) ...[
                const SizedBox(height: RestoflowSpacing.xs),
                Row(
                  key: const Key('ticket-print-status'),
                  children: [
                    Icon(
                      Icons.print_outlined,
                      size: RestoflowIconSizes.sm,
                      // A print problem must LOOK like a problem (DESIGN-001):
                      // attention states go danger; quiet states stay muted.
                      color: status.isError
                          ? RestoflowTone.danger.styleOf(theme).accent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: RestoflowSpacing.xs),
                    Expanded(
                      child: Text(
                        '${l10n.kdsTicketPrintLabel}: ${status.label}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: status.isError
                            ? theme.textTheme.bodyMedium?.copyWith(
                                color: RestoflowTone.danger
                                    .styleOf(theme)
                                    .accent,
                                fontWeight: FontWeight.w600,
                              )
                            : theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                      ),
                    ),
                    if (status.onRetry case final onRetry?) ...[
                      const SizedBox(width: RestoflowSpacing.xs),
                      TextButton.icon(
                        key: const Key('ticket-print-retry'),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(
                          status.actionLabel ?? l10n.printRetryAction,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              _TicketAction(
                status: ticket.status,
                l10n: l10n,
                takeaway: ticket.orderType == 'takeaway',
                onAdvance: onAdvance,
                onRecall: onRecall,
              ),
              // PSC-001D: the ONE acknowledgement action for a pending
              // cancellation (the cancelled status renders no normal
              // progression action above). LIVE board only — a null callback
              // (demo / bare tests) renders no button, never a dead control.
              // Honest pending state; a failure keeps the card and the action.
              if (pendingAckCancellation &&
                  onAcknowledgeCancellation != null) ...[
                if (ackFailed) ...[
                  const SizedBox(height: RestoflowSpacing.xs),
                  Text(
                    l10n.kdsAckFailed,
                    key: Key('kds-ack-failed-${ticket.kitchenTicketId}'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: dangerStyle.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    top: RestoflowSpacing.sm,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: Key('kds-ack-${ticket.kitchenTicketId}'),
                      onPressed: ackPending ? null : onAcknowledgeCancellation,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      // STATIC pending glyph (no spinner): the board's
                      // animation doctrine is FINITE-only (pumpAndSettle
                      // corpus; an indeterminate spinner never settles). The
                      // disabled state + localized pending label carry the
                      // signal.
                      icon: Icon(
                        ackPending
                            ? Icons.hourglass_top
                            : Icons.visibility_outlined,
                      ),
                      label: Text(
                        ackPending
                            ? l10n.kdsAckPending
                            : l10n.kdsAcknowledgeCancellation,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    Widget result = card;
    // PSC-001D: one finite, reduce-motion-aware DANGER pulse when the
    // cancellation card first appears (reuses the shipped self-terminating
    // highlight — never an infinite animation).
    if (highlightCancelled) {
      result = _NewArrivalHighlight(
        key: Key('kds-cancel-arrival-${ticket.kitchenTicketId}'),
        window: newArrivalWindow,
        color: theme.colorScheme.error,
        child: result,
      );
    }
    // A2: a subtle, self-terminating attention glow for a freshly-arrived
    // ticket (readable on the dark board; never a harsh blink).
    if (highlightNew) {
      result = _NewArrivalHighlight(
        key: Key('kds-new-arrival-${ticket.kitchenTicketId}'),
        window: newArrivalWindow,
        color: theme.colorScheme.primary,
        child: result,
      );
    }
    // Cleared work steps back visually (a bumped ticket dims).
    if (dimmed) result = Opacity(opacity: 0.62, child: result);
    return result;
  }
}

/// KDS-ALERTS-AND-KITCHEN-COUNTS-002 (A2): a subtle, ACCESSIBILITY-aware
/// new-arrival attention glow. A single finite animation over [window] drives a
/// gentle breathing glow (≈0.7 Hz — well below any seizure threshold) that FADES
/// OUT over the window, so it self-stops even without a parent rebuild and never
/// flashes harshly. Under "reduce motion" it renders a static soft outline
/// instead. Money-free chrome.
class _NewArrivalHighlight extends StatefulWidget {
  const _NewArrivalHighlight({
    required this.child,
    required this.window,
    required this.color,
    super.key,
  });

  final Widget child;
  final Duration window;
  final Color color;

  @override
  State<_NewArrivalHighlight> createState() => _NewArrivalHighlightState();
}

class _NewArrivalHighlightState extends State<_NewArrivalHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// The breathing period; the number of oscillations = window / this.
  static const Duration _pulsePeriod = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.window)
      // FINITE: forward once over the whole window, then stop (self-terminating,
      // pumpAndSettle-safe). No .repeat() — an infinite animation would neither
      // settle in tests nor stop on the board.
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Accessibility: honor the platform "reduce motion" setting — a static, but
    // now BOLD, ring + soft glow still draws the eye without any animation.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          boxShadow: [
            // A bold bright ring (reads as a glowing border) + a soft halo.
            BoxShadow(
              color: widget.color.withValues(alpha: 0.70),
              blurRadius: 4,
              spreadRadius: 2.5,
            ),
            BoxShadow(
              color: widget.color.withValues(alpha: 0.40),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: widget.child,
      );
    }
    final cycles = (widget.window.inMilliseconds / _pulsePeriod.inMilliseconds)
        .clamp(1, 120)
        .toDouble();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value; // 0 -> 1 over the window
        // A breathing 0..1 oscillation that ATTENUATES to 0 as the window ends.
        final osc = (0.5 + 0.5 * math.sin(t * cycles * 2 * math.pi)) * (1 - t);
        final glow = osc.clamp(0.0, 1.0);
        // KDS-ALERTS (C): a STRONGER, more noticeable alert — a pulsing bright
        // ring (tight shadow) reads as a glowing border, over a wider soft glow.
        // Still a gentle ≈0.7 Hz breath that self-attenuates (never a harsh
        // flash), and readable on the dark board.
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            boxShadow: glow <= 0.02
                ? null
                : [
                    // A tight bright ring — the pulsing "border" glow.
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.30 + 0.55 * glow),
                      blurRadius: 3 + 5 * glow,
                      spreadRadius: 1 + 1.5 * glow,
                    ),
                    // A wider soft halo behind it.
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.12 + 0.30 * glow),
                      blurRadius: 10 + 22 * glow,
                      spreadRadius: 1 + 3 * glow,
                    ),
                  ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// KDS-ALERTS (C): the loud "New order" badge shown at the top of a freshly-
/// arrived ticket card. A small filled pill (brand-primary → high contrast on
/// the dark board) with a bell icon. Static (the pulsing glow carries the
/// motion), so it never breaks `pumpAndSettle`. Money-free chrome.
class _NewOrderBadge extends StatelessWidget {
  const _NewOrderBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.sm,
        RestoflowSpacing.xxs,
        RestoflowSpacing.md,
        RestoflowSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_active,
            size: RestoflowIconSizes.sm,
            color: theme.colorScheme.onPrimary,
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// PSC-001D: the leading banner of a PENDING-ACKNOWLEDGEMENT cancellation card.
/// A danger-toned block that says IN WORDS what happened (the cashier canceled
/// this order), tells the kitchen to stop, and shows the honest cancellation
/// time (localized clock format; omitted when the wire carried no timestamp —
/// never a fabricated time). Money-free chrome.
class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner({
    required this.l10n,
    required this.voidedAt,
    super.key,
  });

  final AppLocalizations l10n;
  final DateTime? voidedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = RestoflowTone.danger.styleOf(theme);
    final String? cancelledAt = voidedAt == null
        ? null
        : MaterialLocalizations.of(
            context,
          ).formatTimeOfDay(TimeOfDay.fromDateTime(voidedAt!.toLocal()));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: danger.accent,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cancel_outlined,
                size: RestoflowIconSizes.md,
                color: theme.colorScheme.onError,
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Text(
                  l10n.kdsCancelledCardTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onError,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          Text(
            l10n.kdsCancelledCardBody,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onError,
            ),
          ),
          if (cancelledAt != null) ...[
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              '${l10n.kdsCancelledAtLabel}: $cancelledAt',
              key: const Key('kds-cancelled-at'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onError,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// KDS-ALERTS-AND-KITCHEN-COUNTS-002: the unified WHOLE-ORDER kitchen count
/// summary — the prominent top chef note. One clean, bold line PER RESOURCE,
/// using the generic "Kitchen total: {count} {label}" copy (l10n
/// `kdsMeatTotalLabel`; the label is owner-written, e.g. "19 قطع لحم" / "7 خبز").
/// Multiple resources (patties, buns, fish pieces, …) appear together, each
/// aggregated over the whole order. Money-free; shown only when the order
/// carries an explicit owner-configured count.
class _KitchenCountsSection extends StatelessWidget {
  const _KitchenCountsSection({required this.counts, required this.l10n});

  final List<KitchenCount> counts;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('kds-kitchen-counts'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.summarize_outlined,
            size: RestoflowIconSizes.md,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final count in counts)
                  Text(
                    l10n.kdsMeatTotalLabel(
                      formatPrepQuantity(count.quantity),
                      count.label,
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({
    required this.item,
    required this.l10n,
    required this.noteColor,
  });

  final KdsItemView item;
  final AppLocalizations l10n;
  final Color noteColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Data text (item name + quantity), rendered as a single Text. Kept in the
    // exact '{name} ×{quantity}' form (U+00D7) — readable, money-free.
    final line = '${item.name} ×${item.quantity}';
    return Padding(
      // PRINT-LAYOUT-001: more breathing room between items so the pass scans.
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          // Modifier options as their own readable sub-lines (never money).
          for (final modifier in item.modifiers)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: RestoflowSpacing.md,
              ),
              child: Text(
                '+ $modifier',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (item.note case final note?)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: RestoflowSpacing.md,
              ),
              // PRINT-LAYOUT-001: a "»" marker + heavier weight so a kitchen
              // instruction is never missed.
              child: Text(
                '» ${l10n.kdsNoteLabel}: $note',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  color: noteColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The single status-gated lifecycle action for a ticket. Forward transitions
/// are filled buttons that call [onAdvance] with the next status; recall is an
/// outlined button. Terminal/no-action statuses render nothing. All actions
/// are full-width and ≥48dp tall (greasy-finger targets); Bump — the action a
/// kitchen hits most — uses the big touch-first style.
class _TicketAction extends StatelessWidget {
  const _TicketAction({
    required this.status,
    required this.l10n,
    required this.takeaway,
    required this.onAdvance,
    required this.onRecall,
  });

  final KitchenTicketStatus status;
  final AppLocalizations l10n;

  /// RESTAURANT-OPERATIONS-V1-001: the ready-stage action is TYPE-AWARE. The
  /// underlying transition is the SAME canonical `served` push either way —
  /// only the words change: a dine-in plate is "Served" to the table, a
  /// takeaway bag is "Picked up" by the customer.
  final bool takeaway;

  final void Function(KitchenTicketStatus to) onAdvance;
  final VoidCallback? onRecall;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case KitchenTicketStatus.newTicket:
        return _ForwardButton(
          icon: Icons.visibility_outlined,
          label: l10n.kdsAcknowledgeAction,
          onPressed: () => onAdvance(KitchenTicketStatus.acknowledged),
        );
      case KitchenTicketStatus.acknowledged:
        return _ForwardButton(
          icon: Icons.play_arrow_rounded,
          label: l10n.kdsStartAction,
          onPressed: () => onAdvance(KitchenTicketStatus.inPreparation),
        );
      case KitchenTicketStatus.inPreparation:
        return _ForwardButton(
          icon: Icons.check_circle_outline,
          label: l10n.kdsReadyAction,
          onPressed: () => onAdvance(KitchenTicketStatus.ready),
        );
      case KitchenTicketStatus.ready:
        return _ForwardButton(
          icon: takeaway ? Icons.takeout_dining_outlined : Icons.room_service,
          label: takeaway ? l10n.kdsPickedUpAction : l10n.kdsServedAction,
          style: RestoflowButtonStyles.big(context),
          onPressed: () => onAdvance(KitchenTicketStatus.bumped),
        );
      case KitchenTicketStatus.bumped:
        // No recall sink (the LIVE board): a bumped ticket shows no action —
        // never a button whose effect would silently revert on the next poll.
        if (onRecall == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(top: RestoflowSpacing.sm),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRecall,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.undo),
              label: Text(l10n.kdsRecallAction),
            ),
          ),
        );
      case KitchenTicketStatus.cancelled:
        return const SizedBox.shrink();
    }
  }
}

class _ForwardButton extends StatelessWidget {
  const _ForwardButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.style,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: RestoflowSpacing.sm),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          style:
              style ??
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}
