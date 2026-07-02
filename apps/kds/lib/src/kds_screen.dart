import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'widgets/kds_board.dart';
import 'widgets/kds_state_message.dart';

/// Local Kitchen Display screen (RF-034, restyled in RF-102): renders
/// fake/local tickets grouped by station with bump/recall actions. Pure UI +
/// the local kitchen state machines — NO repository, backend, persistence, or
/// printing. All chrome text comes from `AppLocalizations`; item/station/ticket
/// data is rendered as-is. No money appears anywhere (SECURITY T-003).
class KdsScreen extends StatefulWidget {
  const KdsScreen({
    required this.tickets,
    this.onRecall,
    this.onAdvanced,
    this.allowRecall = true,
    this.appBarActions = const <Widget>[],
    this.showStaleBanner = false,
    super.key,
  });

  /// Local fixture/view models supplied by the caller (no repository).
  final List<KdsTicketView> tickets;

  /// Extra AppBar actions (design-polish sprint): the LIVE board threads the
  /// app's LanguageSelector through here. Injected rather than embedded so this
  /// screen stays pumpable in bare (provider-less) test harnesses.
  final List<Widget> appBarActions;

  /// Renders the offline/stale warning banner above the board (design-polish
  /// sprint): the LIVE board sets this from `KdsViewState.isStale` so a
  /// last-good-pull board is visibly marked instead of silently ageing.
  final bool showStaleBanner;

  /// Optional sink for the in-memory recall audit placeholder (test/observer).
  final void Function(RecallAuditEvent event)? onRecall;

  /// Whether the bumped->recall action is offered. The LIVE board passes false
  /// (the backend allows forward transitions only, so a local-only recall
  /// would lie and revert on the next poll); the demo board keeps it.
  final bool allowRecall;

  /// Optional sink invoked AFTER a successful forward advance (sprint): the
  /// LIVE board pushes the matching `order.status` through `public.sync_push`
  /// so the kitchen's progress persists (the next poll re-syncs the board to
  /// the server's state either way — the server always wins). Null in demo
  /// mode (local-only board, nothing to persist).
  final void Function(KdsTicketView ticket, KitchenTicketStatus to)? onAdvanced;

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

  /// Advance [ticket] to [to] via the existing forward state-machine edges
  /// (acknowledge / start / mark-ready / bump). Mutates the local view first
  /// (instant feedback), then notifies [KdsScreen.onAdvanced] so a LIVE board
  /// can persist the transition (demo boards pass null — local only).
  void _advance(KdsTicketView ticket, KitchenTicketStatus to) {
    setState(() {
      ticket.status = KitchenTicketStateMachine.transition(ticket.status, to);
    });
    widget.onAdvanced?.call(ticket, ticket.status);
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

    final body = widget.tickets.isEmpty
        ? KdsStateMessage(
            icon: Icons.restaurant_outlined,
            message: l10n.kdsEmptyState,
          )
        : KdsBoard(
            tickets: widget.tickets,
            l10n: l10n,
            onAdvance: _advance,
            onRecall: widget.allowRecall ? _recall : null,
          );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.kitchen_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Text(l10n.kdsAppTitle),
          ],
        ),
        actions: widget.appBarActions,
      ),
      body: widget.showStaleBanner
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    RestoflowSpacing.md,
                    RestoflowSpacing.md,
                    RestoflowSpacing.md,
                    0,
                  ),
                  child: RestoflowNoticeBanner(
                    tone: RestoflowTone.warning,
                    icon: Icons.cloud_off_outlined,
                    body: l10n.kdsStaleBanner,
                  ),
                ),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }
}
