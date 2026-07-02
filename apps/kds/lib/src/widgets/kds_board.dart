import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_ticket_card.dart';

/// The KDS board: tickets grouped by station, deterministically ordered.
///
/// Responsive — station COLUMNS side by side on wide screens (a real kitchen
/// display), and readable STACKED sections when narrow. Lifecycle actions are
/// delegated per ticket: [onAdvance] (forward transitions) and [onRecall].
class KdsBoard extends StatelessWidget {
  const KdsBoard({
    required this.tickets,
    required this.l10n,
    required this.onAdvance,
    required this.onRecall,
    super.key,
  });

  static const double _wideBreakpoint = 900;
  static const double _columnWidth = 340;

  final List<KdsTicketView> tickets;
  final AppLocalizations l10n;
  final void Function(KdsTicketView ticket, KitchenTicketStatus to) onAdvance;

  /// Null hides the recall action (the LIVE board — forward-only backend).
  final void Function(KdsTicketView ticket)? onRecall;

  List<_Station> _stations() {
    final byStation = <String, List<KdsTicketView>>{};
    for (final ticket in tickets) {
      (byStation[ticket.stationId] ??= <KdsTicketView>[]).add(ticket);
    }
    final ids = byStation.keys.toList()..sort();
    return [for (final id in ids) _Station(id, byStation[id]!)];
  }

  @override
  Widget build(BuildContext context) {
    final stations = _stations();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(RestoflowSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final station in stations)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: RestoflowSpacing.md,
                    ),
                    child: SizedBox(
                      width: _columnWidth,
                      child: _StationColumn(
                        station: station,
                        l10n: l10n,
                        onAdvance: onAdvance,
                        onRecall: onRecall,
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
            for (final station in stations) ...[
              _StationHeader(station: station, l10n: l10n),
              const SizedBox(height: RestoflowSpacing.sm),
              for (final ticket in station.tickets)
                KdsTicketCard(
                  ticket: ticket,
                  l10n: l10n,
                  onAdvance: (to) => onAdvance(ticket, to),
                  onRecall: onRecall == null ? null : () => onRecall!(ticket),
                ),
              const SizedBox(height: RestoflowSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

class _StationColumn extends StatelessWidget {
  const _StationColumn({
    required this.station,
    required this.l10n,
    required this.onAdvance,
    required this.onRecall,
  });

  final _Station station;
  final AppLocalizations l10n;
  final void Function(KdsTicketView ticket, KitchenTicketStatus to) onAdvance;
  final void Function(KdsTicketView ticket)? onRecall;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StationHeader(station: station, l10n: l10n),
        const SizedBox(height: RestoflowSpacing.sm),
        Expanded(
          child: ListView(
            children: [
              for (final ticket in station.tickets)
                KdsTicketCard(
                  ticket: ticket,
                  l10n: l10n,
                  onAdvance: (to) => onAdvance(ticket, to),
                  onRecall: onRecall == null ? null : () => onRecall!(ticket),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StationHeader extends StatelessWidget {
  const _StationHeader({required this.station, required this.l10n});

  final _Station station;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Data: station label + raw station id (kept so it stays findable/legible).
    final headerText = '${l10n.kdsStationLabel}: ${station.id}';
    final countText = station.tickets.length.toString();

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
          Icon(
            Icons.kitchen_outlined,
            size: 20,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              headerText,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
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
              countText,
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

class _Station {
  const _Station(this.id, this.tickets);
  final String id;
  final List<KdsTicketView> tickets;
}
