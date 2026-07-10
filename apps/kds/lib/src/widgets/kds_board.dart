import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_board_column.dart';
import 'kds_ticket_card.dart';

/// The LIVE KDS board: tickets in WORKFLOW STATUS columns
/// (New → Preparing → Ready → Cleared), deterministically ordered inside each
/// column (demo-readiness sprint — replaces the old station-grouped layout;
/// the station is now a per-card pill).
///
/// A ticket moves column purely by its status: Acknowledge moves New →
/// Preparing, Ready moves to Ready, Bump moves to Cleared — the screen's
/// setState re-buckets the card and the next poll confirms (server wins).
/// Responsive — columns side by side on wide screens (a real kitchen display),
/// stacked sections when narrow. Lifecycle actions are delegated per ticket:
/// [onAdvance] (forward transitions) and [onRecall].
class KdsBoard extends StatelessWidget {
  const KdsBoard({
    required this.tickets,
    required this.l10n,
    required this.onAdvance,
    required this.onRecall,
    this.printStatusFor,
    this.onReprint,
    this.newArrivalIds = const <String>{},
    this.newArrivalWindow = const Duration(seconds: 60),
    super.key,
  });

  static const double _wideBreakpoint = RestoflowBreakpoints.wide;
  static const double _columnWidth = RestoflowPanelWidths.kdsColumn;

  final List<KdsTicketView> tickets;
  final AppLocalizations l10n;
  final void Function(KdsTicketView ticket, KitchenTicketStatus to) onAdvance;

  /// Null hides the recall action (the LIVE board — forward-only backend).
  final void Function(KdsTicketView ticket)? onRecall;

  /// Optional per-ticket kitchen print-status (RF-115); null = none.
  final KdsTicketPrintStatus? Function(KdsTicketView ticket)? printStatusFor;

  /// A2/A1: an always-visible per-card reprint action (LIVE board); null hides it.
  final void Function(KdsTicketView ticket)? onReprint;

  /// A2: ticket ids that should show the new-arrival attention glow.
  final Set<String> newArrivalIds;

  /// A2: how long the new-arrival glow runs before it self-stops.
  final Duration newArrivalWindow;

  /// Buckets a status into its workflow column key.
  static String _bucket(KitchenTicketStatus status) => switch (status) {
    KitchenTicketStatus.newTicket => 'new',
    KitchenTicketStatus.acknowledged ||
    KitchenTicketStatus.inPreparation => 'preparing',
    KitchenTicketStatus.ready => 'ready',
    KitchenTicketStatus.bumped || KitchenTicketStatus.cancelled => 'cleared',
  };

  List<_BoardColumn> _columns() {
    final byBucket = <String, List<KdsTicketView>>{};
    for (final ticket in tickets) {
      (byBucket[_bucket(ticket.status)] ??= <KdsTicketView>[]).add(ticket);
    }
    // KDS-FIFO-001: within every status column, oldest submitted order first
    // (stable id tie-break) — the top card is the next ticket to handle. A
    // status change re-buckets the ticket, which then takes its age-order place
    // in the new column; a newer ticket never jumps above an older one.
    for (final list in byBucket.values) {
      list.sort(KdsTicketView.compareByOldestFirst);
    }
    return [
      _BoardColumn('new', l10n.kdsColNew, byBucket['new'] ?? const []),
      _BoardColumn(
        'preparing',
        l10n.kdsColPreparing,
        byBucket['preparing'] ?? const [],
      ),
      _BoardColumn('ready', l10n.kdsColReady, byBucket['ready'] ?? const []),
      _BoardColumn(
        'cleared',
        l10n.kdsColCleared,
        byBucket['cleared'] ?? const [],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columns();
    // ONE clock read per board build (DESIGN-001): every card computes its
    // elapsed pill against the same instant, and the value refreshes with the
    // sync-poll rebuild — deliberately no timer (pumpAndSettle test corpus).
    final now = DateTime.now();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          // DESIGN-001: when every column fits at its 340px minimum (large
          // kitchen TVs), the columns GROW to fill the screen instead of
          // clustering at the reading edge of a horizontal scroller. Below
          // that (including the 1400px test viewport, where 4 × (340+12) + 12
          // = 1420 > 1400) the original fixed-width scroll path is unchanged.
          final fillsScreen =
              constraints.maxWidth >=
              columns.length * (_columnWidth + RestoflowSpacing.md) +
                  RestoflowSpacing.md;
          if (fillsScreen) {
            return Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < columns.length; i++) ...[
                    if (i > 0) const SizedBox(width: RestoflowSpacing.md),
                    Expanded(
                      child: _StatusColumn(
                        column: columns[i],
                        l10n: l10n,
                        now: now,
                        onAdvance: onAdvance,
                        onRecall: onRecall,
                        printStatusFor: printStatusFor,
                        onReprint: onReprint,
                        newArrivalIds: newArrivalIds,
                        newArrivalWindow: newArrivalWindow,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(RestoflowSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final column in columns)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: RestoflowSpacing.md,
                    ),
                    child: SizedBox(
                      width: _columnWidth,
                      child: _StatusColumn(
                        column: column,
                        l10n: l10n,
                        now: now,
                        onAdvance: onAdvance,
                        onRecall: onRecall,
                        printStatusFor: printStatusFor,
                        onReprint: onReprint,
                        newArrivalIds: newArrivalIds,
                        newArrivalWindow: newArrivalWindow,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
        // Narrow stacked path: each column keeps its Key so tests (and tools)
        // can assert cards stay descendants of their status column — parity
        // with KitchenBoard and the wide layout.
        return ListView(
          padding: const EdgeInsets.all(RestoflowSpacing.md),
          children: [
            for (final column in columns)
              Column(
                key: Key('kds-col-${column.key}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KdsColumnHeader(
                    columnKey: column.key,
                    label: column.label,
                    count: column.tickets.length,
                  ),
                  const SizedBox(height: RestoflowSpacing.sm),
                  if (column.tickets.isEmpty)
                    const KdsEmptyColumnPlaceholder()
                  else
                    for (final ticket in column.tickets)
                      KdsTicketCard(
                        key: ValueKey('kds-card-${ticket.kitchenTicketId}'),
                        ticket: ticket,
                        l10n: l10n,
                        now: now,
                        printStatus: printStatusFor?.call(ticket),
                        onReprint: onReprint == null
                            ? null
                            : () => onReprint!(ticket),
                        highlightNew: newArrivalIds.contains(
                          ticket.kitchenTicketId,
                        ),
                        newArrivalWindow: newArrivalWindow,
                        onAdvance: (to) => onAdvance(ticket, to),
                        onRecall: onRecall == null
                            ? null
                            : () => onRecall!(ticket),
                      ),
                  const SizedBox(height: RestoflowSpacing.md),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({
    required this.column,
    required this.l10n,
    required this.now,
    required this.onAdvance,
    required this.onRecall,
    this.printStatusFor,
    this.onReprint,
    this.newArrivalIds = const <String>{},
    this.newArrivalWindow = const Duration(seconds: 60),
  });

  final _BoardColumn column;
  final AppLocalizations l10n;

  /// The board's single build-time clock read (see [KdsBoard.build]).
  final DateTime now;

  final void Function(KdsTicketView ticket, KitchenTicketStatus to) onAdvance;
  final void Function(KdsTicketView ticket)? onRecall;
  final KdsTicketPrintStatus? Function(KdsTicketView ticket)? printStatusFor;
  final void Function(KdsTicketView ticket)? onReprint;
  final Set<String> newArrivalIds;
  final Duration newArrivalWindow;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('kds-col-${column.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KdsColumnHeader(
          columnKey: column.key,
          label: column.label,
          count: column.tickets.length,
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Expanded(
          child: column.tickets.isEmpty
              ? const Align(
                  alignment: AlignmentDirectional.topCenter,
                  child: KdsEmptyColumnPlaceholder(),
                )
              : ListView(
                  children: [
                    for (final ticket in column.tickets)
                      KdsTicketCard(
                        key: ValueKey('kds-card-${ticket.kitchenTicketId}'),
                        ticket: ticket,
                        l10n: l10n,
                        now: now,
                        printStatus: printStatusFor?.call(ticket),
                        onReprint: onReprint == null
                            ? null
                            : () => onReprint!(ticket),
                        highlightNew: newArrivalIds.contains(
                          ticket.kitchenTicketId,
                        ),
                        newArrivalWindow: newArrivalWindow,
                        onAdvance: (to) => onAdvance(ticket, to),
                        onRecall: onRecall == null
                            ? null
                            : () => onRecall!(ticket),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _BoardColumn {
  const _BoardColumn(this.key, this.label, this.tickets);
  final String key;
  final String label;
  final List<KdsTicketView> tickets;
}
