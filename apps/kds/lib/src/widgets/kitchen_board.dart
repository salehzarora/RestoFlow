import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kitchen_order.dart';
import 'kds_board_column.dart';
import 'kitchen_order_card.dart';

/// The KDS kitchen board (RF-117): order tickets grouped into status COLUMNS —
/// New / Preparing / Ready / Cleared. Responsive: columns side by side on wide
/// kitchen screens, stacked sections when narrow. Lifecycle actions are routed
/// per ticket id.
class KitchenBoard extends StatelessWidget {
  const KitchenBoard({
    required this.tickets,
    required this.now,
    required this.onStart,
    required this.onMarkReady,
    required this.onComplete,
    required this.onRecall,
    super.key,
  });

  final List<KitchenOrderTicket> tickets;
  final DateTime now;
  final void Function(String ticketId) onStart;
  final void Function(String ticketId) onMarkReady;
  final void Function(String ticketId) onComplete;
  final void Function(String ticketId) onRecall;

  static const double _wideBreakpoint = RestoflowBreakpoints.wide;
  static const double _columnWidth = RestoflowPanelWidths.kdsColumn;

  // KDS-FIFO-001: each status column ordered oldest submitted first (stable
  // ticketId tie-break) so the demo board reads FIFO like the live board — the
  // top card is the next ticket to handle.
  List<KitchenOrderTicket> _bucket(Set<KitchenTicketStatus> statuses) => [
    for (final t in tickets)
      if (statuses.contains(t.status)) t,
  ]..sort(KitchenOrderTicket.compareByOldestFirst);

  KitchenOrderCard _card(KitchenOrderTicket t) => KitchenOrderCard(
    ticket: t,
    now: now,
    onStart: () => onStart(t.ticketId),
    onMarkReady: () => onMarkReady(t.ticketId),
    onComplete: () => onComplete(t.ticketId),
    onRecall: () => onRecall(t.ticketId),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final columns = <_BoardColumn>[
      _BoardColumn(
        key: 'new',
        label: l10n.kdsColNew,
        tickets: _bucket({
          KitchenTicketStatus.newTicket,
          KitchenTicketStatus.acknowledged,
        }),
      ),
      _BoardColumn(
        key: 'preparing',
        label: l10n.kdsColPreparing,
        tickets: _bucket({KitchenTicketStatus.inPreparation}),
      ),
      _BoardColumn(
        key: 'ready',
        label: l10n.kdsColReady,
        tickets: _bucket({KitchenTicketStatus.ready}),
      ),
      _BoardColumn(
        key: 'cleared',
        label: l10n.kdsColCleared,
        tickets: _bucket({
          KitchenTicketStatus.bumped,
          KitchenTicketStatus.cancelled,
        }),
      ),
    ];

    // One wide-column body shared by the fill and scroll paths below.
    Widget columnBody(_BoardColumn col) => Column(
      key: Key('kds-col-${col.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KdsColumnHeader(
          columnKey: col.key,
          label: col.label,
          count: col.tickets.length,
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Expanded(
          child: col.tickets.isEmpty
              ? const Align(
                  alignment: AlignmentDirectional.topCenter,
                  child: KdsEmptyColumnPlaceholder(),
                )
              : ListView(children: [for (final t in col.tickets) _card(t)]),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          // DESIGN-001: same fill rule as the live KdsBoard — when all four
          // columns fit at their 340px minimum (large kitchen TVs) they grow
          // to use the whole width; below that (incl. every tested viewport)
          // the fixed-width horizontal scroll is unchanged. Demo and live
          // boards must read identically.
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
                    Expanded(child: columnBody(columns[i])),
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
                for (final col in columns)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: RestoflowSpacing.md,
                    ),
                    child: SizedBox(
                      width: _columnWidth,
                      child: columnBody(col),
                    ),
                  ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(RestoflowSpacing.md),
          children: [
            for (final col in columns)
              Column(
                key: Key('kds-col-${col.key}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KdsColumnHeader(
                    columnKey: col.key,
                    label: col.label,
                    count: col.tickets.length,
                  ),
                  const SizedBox(height: RestoflowSpacing.sm),
                  if (col.tickets.isEmpty)
                    const KdsEmptyColumnPlaceholder()
                  else
                    for (final t in col.tickets) _card(t),
                  const SizedBox(height: RestoflowSpacing.md),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _BoardColumn {
  const _BoardColumn({
    required this.key,
    required this.label,
    required this.tickets,
  });
  final String key;
  final String label;
  final List<KitchenOrderTicket> tickets;
}
