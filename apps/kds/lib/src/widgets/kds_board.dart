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
    super.key,
  });

  static const double _wideBreakpoint = RestoflowBreakpoints.wide;
  static const double _columnWidth = RestoflowPanelWidths.kdsColumn;

  final List<KdsTicketView> tickets;
  final AppLocalizations l10n;
  final void Function(KdsTicketView ticket, KitchenTicketStatus to) onAdvance;

  /// Null hides the recall action (the LIVE board — forward-only backend).
  final void Function(KdsTicketView ticket)? onRecall;

  /// Optional per-ticket kitchen print-status label (Part D); null = none.
  final String? Function(KdsTicketView ticket)? printStatusFor;

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
    for (final list in byBucket.values) {
      list.sort((a, b) => a.kitchenTicketId.compareTo(b.kitchenTicketId));
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
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
                        onAdvance: onAdvance,
                        onRecall: onRecall,
                        printStatusFor: printStatusFor,
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
                        ticket: ticket,
                        l10n: l10n,
                        printStatus: printStatusFor?.call(ticket),
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
    required this.onAdvance,
    required this.onRecall,
    this.printStatusFor,
  });

  final _BoardColumn column;
  final AppLocalizations l10n;
  final void Function(KdsTicketView ticket, KitchenTicketStatus to) onAdvance;
  final void Function(KdsTicketView ticket)? onRecall;
  final String? Function(KdsTicketView ticket)? printStatusFor;

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
                        ticket: ticket,
                        l10n: l10n,
                        printStatus: printStatusFor?.call(ticket),
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
