import 'package:flutter/material.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Minimal local Kitchen Display screen (RF-034): renders fake/local tickets
/// grouped by station with bump/recall actions. Pure UI + the local kitchen
/// state machines — NO repository, NO backend, NO persistence, NO printing. All
/// chrome text comes from `AppLocalizations`; data text comes from the model.
class KdsScreen extends StatefulWidget {
  const KdsScreen({required this.tickets, this.onRecall, super.key});

  /// Local fixture/view models supplied by the caller (no repository).
  final List<KdsTicketView> tickets;

  /// Optional sink for the in-memory recall audit placeholder (test/observer).
  final void Function(RecallAuditEvent event)? onRecall;

  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> {
  // Internal placeholders for the recall audit event (RF-034): not user-facing
  // chrome, not persisted, not a real audit row.
  static const String _recallReason = 'recalled from KDS';
  static const String _actorId = 'kds-device';

  /// Last recall audit placeholder produced on this screen (test-accessible).
  RecallAuditEvent? lastRecallEvent;

  void _bump(KdsTicketView ticket) {
    setState(() {
      ticket.status = KitchenTicketStateMachine.transition(
        ticket.status,
        KitchenTicketStatus.bumped,
      );
    });
  }

  void _recall(KdsTicketView ticket) {
    final event = KitchenTicketStateMachine.recall(
      kitchenTicketId: ticket.kitchenTicketId,
      from: ticket.status,
      reason: _recallReason,
      actorId: _actorId,
    );
    setState(() {
      ticket.status = event.toStatus; // bumped -> inPreparation
      lastRecallEvent = event;
    });
    widget.onRecall?.call(event);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.kdsAppTitle)),
      body: widget.tickets.isEmpty
          ? Center(child: Text(l10n.kdsEmptyState))
          : ListView(children: _stationSections(context, l10n)),
    );
  }

  List<Widget> _stationSections(BuildContext context, AppLocalizations l10n) {
    // Group by station, deterministic station ordering.
    final byStation = <String, List<KdsTicketView>>{};
    for (final t in widget.tickets) {
      (byStation[t.stationId] ??= <KdsTicketView>[]).add(t);
    }
    final stationIds = byStation.keys.toList()..sort();

    final sections = <Widget>[];
    for (final stationId in stationIds) {
      final stationHeader = '${l10n.kdsStationLabel}: $stationId';
      sections.add(
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            stationHeader,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
      for (final ticket in byStation[stationId]!) {
        sections.add(_ticketCard(l10n, ticket));
      }
    }
    return sections;
  }

  Widget _ticketCard(AppLocalizations l10n, KdsTicketView ticket) {
    final ticketHeader = '${l10n.kdsTicketLabel} ${ticket.kitchenTicketId}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ticketHeader),
            Text(ticket.status.canonicalName),
            for (final item in ticket.items) _itemLine(item),
            _ticketAction(l10n, ticket),
          ],
        ),
      ),
    );
  }

  Widget _itemLine(KdsItemView item) {
    // Data text (built into a variable so it is rendered via Text(identifier),
    // not a literal) — item names/quantities are data, not localized chrome.
    final line = '${item.name} ×${item.quantity}';
    return Text(line);
  }

  Widget _ticketAction(AppLocalizations l10n, KdsTicketView ticket) {
    switch (ticket.status) {
      case KitchenTicketStatus.ready:
        return TextButton(
          onPressed: () => _bump(ticket),
          child: Text(l10n.kdsBumpAction),
        );
      case KitchenTicketStatus.bumped:
        return TextButton(
          onPressed: () => _recall(ticket),
          child: Text(l10n.kdsRecallAction),
        );
      case KitchenTicketStatus.newTicket:
      case KitchenTicketStatus.acknowledged:
      case KitchenTicketStatus.inPreparation:
      case KitchenTicketStatus.cancelled:
        return const SizedBox.shrink();
    }
  }
}
