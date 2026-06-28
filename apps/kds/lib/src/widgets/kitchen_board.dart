import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kitchen_order.dart';
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

  static const double _wideBreakpoint = 900;
  static const double _columnWidth = 340;

  List<KitchenOrderTicket> _bucket(Set<KitchenTicketStatus> statuses) => [
    for (final t in tickets)
      if (statuses.contains(t.status)) t,
  ];

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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
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
                      child: Column(
                        key: Key('kds-col-${col.key}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ColumnHeader(col: col),
                          const SizedBox(height: RestoflowSpacing.sm),
                          Expanded(
                            child: ListView(
                              children: [for (final t in col.tickets) _card(t)],
                            ),
                          ),
                        ],
                      ),
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
                  _ColumnHeader(col: col),
                  const SizedBox(height: RestoflowSpacing.sm),
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

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.col});

  final _BoardColumn col;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              col.label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RestoflowSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.onPrimaryContainer.withValues(
                alpha: 0.15,
              ),
              borderRadius: BorderRadius.circular(RestoflowRadii.pill),
            ),
            child: Text(
              col.tickets.length.toString(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
