/// POS-OPERATIONS-SYNC-001 (second review correction) — THE order status + settlement
/// pills, in ONE place.
///
/// The operational centre learned to speak about an order honestly: its authoritative
/// lifecycle status, and the three-valued settlement in which "No charge" is neither
/// Paid nor Unpaid. The confirmation screen never did — it showed a hard-coded
/// "Submitted" chip for the life of the screen, and a "Paid" chip driven by a LOCAL
/// payment marker. An order comped to zero, completed by the kitchen, or paid on
/// another till therefore sat there announcing itself as a freshly submitted, unpaid
/// order, indefinitely.
///
/// The fix is not to teach the second screen the same vocabulary — that is how two
/// screens drift apart in the first place. There is now ONE vocabulary, rendered by one
/// widget, and both screens use it.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_edit_read_model.dart' show PosRoundStage;
import '../data/order_snapshot.dart';

/// The two pills every order surface shows: LIFECYCLE (where the order is) and
/// SETTLEMENT (what it owes). They are different questions and are never merged.
class OrderStatusPills extends StatelessWidget {
  const OrderStatusPills({
    required this.serverStatus,
    required this.settlement,
    required this.keySuffix,
    this.orderType,
    this.hasActiveRound = false,
    this.roundStage,
    super.key,
  });

  /// The CANONICAL server status, or null when the server has not told us one. Null
  /// shows no lifecycle pill at all rather than an invented one.
  final String? serverStatus;

  final PosSettlement settlement;

  /// Disambiguates the pill keys between surfaces/rows.
  final String keySuffix;

  /// RESTAURANT-OPERATIONS-V1-001: the order's type, when known. The persisted
  /// `served` state is RENDERED "Picked up" for takeaway — one state machine,
  /// two operational meanings. Null falls back to the generic wording.
  final OrderType? orderType;

  /// ORDER-EDIT-001E: whether a service round of the order is still active
  /// (`has_active_round`). A `served` order with one shows the round's stage,
  /// never "Served" / "Picked up" — see [orderStatusLabelFor].
  final bool hasActiveRound;

  /// ORDER-EDIT-001E: the active rounds' stage when the surface knows it (only
  /// the detail preview does); null reads "In kitchen" from the flag alone.
  final PosRoundStage? roundStage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: RestoflowSpacing.xs,
      runSpacing: RestoflowSpacing.xs,
      children: [
        // STATUS. Text + icon, never colour alone — colour is not a label, and a
        // cashier with a colour-vision deficiency is still a cashier.
        if (serverStatus != null)
          RestoflowStatusPill(
            key: Key('order-status-$keySuffix'),
            label: orderStatusLabelFor(
              l10n,
              serverStatus!,
              orderType,
              hasActiveRound: hasActiveRound,
              roundStage: roundStage,
            ),
            tone: orderStatusTone(
              serverStatus!,
              hasActiveRound: hasActiveRound,
              roundStage: roundStage,
            ),
            icon: orderStatusIcon(
              serverStatus!,
              hasActiveRound: hasActiveRound,
              roundStage: roundStage,
            ),
          ),
        // SETTLEMENT — the three-valued truth. "No charge" is neither Paid (no money
        // was taken) nor Unpaid (nothing is owed).
        RestoflowStatusPill(
          key: Key('order-settlement-$keySuffix'),
          label: settlementPillLabel(l10n, settlement),
          tone: settlementTone(settlement),
          icon: settlementIcon(settlement),
        ),
      ],
    );
  }
}

/// An UNKNOWN status is shown verbatim rather than mapped to something we made up.
/// Inventing a friendly label for a token we do not understand would be inventing a
/// fact about the order.
String orderStatusLabel(AppLocalizations l10n, String status) =>
    orderStatusLabelFor(l10n, status, null);

/// ORDER-EDIT-001E (STATE_MACHINES §1, DECISION D-043) — the stage a `served`
/// order shows while kitchen work of it is still LIVE, or null when the
/// persisted status speaks for itself.
///
/// An order rests at `served` while an Add-items round opened on it, or a
/// sent-order edit's own round, is still in the kitchen. That `served` is not
/// the pickup and not a table service, so while any round is active
/// (`has_active_round`) the POS must not say "Served" / "Picked up": it says
/// the round's stage. [roundStage] is that stage when the surface knows it
/// (the detail preview, from the rounds); otherwise the flag alone reads
/// "In kitchen" — never a "Ready" nobody saw. Only `served` is overridden.
PosRoundStage? posServedRoundStage(
  String status, {
  required bool hasActiveRound,
  PosRoundStage? roundStage,
}) {
  if (status != 'served') return null;
  if (roundStage != null) return roundStage;
  return hasActiveRound ? PosRoundStage.inKitchen : null;
}

/// TYPE-AWARE status label (RESTAURANT-OPERATIONS-V1-001): identical to
/// [orderStatusLabel] except that a TAKEAWAY order's persisted `served` renders
/// as "Picked up" — the customer collected it; nothing was carried to a table.
/// The persisted state machine is untouched; only the words change.
///
/// ORDER-EDIT-001E: checked FIRST, a `served` order with an active round reads
/// the round's stage instead ([posServedRoundStage]) — for takeaway as much as
/// dine-in: an edit-made `served` is not the customer pickup.
String orderStatusLabelFor(
  AppLocalizations l10n,
  String status,
  OrderType? orderType, {
  bool hasActiveRound = false,
  PosRoundStage? roundStage,
}) {
  switch (posServedRoundStage(
    status,
    hasActiveRound: hasActiveRound,
    roundStage: roundStage,
  )) {
    case PosRoundStage.ready:
      return l10n.posOrdersStatusReady;
    case PosRoundStage.inKitchen:
      return l10n.posOrdersStatusInKitchen;
    case null:
      break;
  }
  if (status == 'served' && orderType == OrderType.takeaway) {
    return l10n.posOrdersStatusPickedUp;
  }
  return switch (status) {
    'submitted' => l10n.posOrdersStatusSubmitted,
    'accepted' => l10n.posOrdersStatusAccepted,
    'preparing' => l10n.posOrdersStatusPreparing,
    'ready' => l10n.posOrdersStatusReady,
    'served' => l10n.posOrdersStatusServed,
    'completed' => l10n.posOrdersStatusCompleted,
    'cancelled' => l10n.posOrdersStatusCancelled,
    'voided' => l10n.posOrdersStatusVoided,
    _ => status,
  };
}

/// The pill tone. ORDER-EDIT-001E: a `served` order with an active round takes
/// the tone of the round's stage (see [posServedRoundStage]).
RestoflowTone orderStatusTone(
  String status, {
  bool hasActiveRound = false,
  PosRoundStage? roundStage,
}) => switch (posServedRoundStage(
  status,
  hasActiveRound: hasActiveRound,
  roundStage: roundStage,
)) {
  PosRoundStage.ready => RestoflowTone.success,
  PosRoundStage.inKitchen => RestoflowTone.info,
  null => switch (status) {
    'ready' => RestoflowTone.success,
    'served' => RestoflowTone.info,
    'completed' => RestoflowTone.neutral,
    'cancelled' || 'voided' => RestoflowTone.danger,
    _ => RestoflowTone.info,
  },
};

/// The pill icon. ORDER-EDIT-001E: a `served` order with an active round takes
/// the icon of the round's stage (see [posServedRoundStage]).
IconData orderStatusIcon(
  String status, {
  bool hasActiveRound = false,
  PosRoundStage? roundStage,
}) => switch (posServedRoundStage(
  status,
  hasActiveRound: hasActiveRound,
  roundStage: roundStage,
)) {
  PosRoundStage.ready => Icons.done_all,
  PosRoundStage.inKitchen => Icons.local_fire_department_outlined,
  null => _plainOrderStatusIcon(status),
};

IconData _plainOrderStatusIcon(String status) => switch (status) {
  'submitted' => Icons.receipt_outlined,
  'accepted' => Icons.thumb_up_outlined,
  'preparing' => Icons.local_fire_department_outlined,
  'ready' => Icons.done_all,
  'served' => Icons.room_service_outlined,
  'completed' => Icons.task_alt,
  'cancelled' || 'voided' => Icons.block,
  _ => Icons.help_outline,
};

/// PAID / UNPAID / NO CHARGE. A zero-total order is NOT "paid" — saying so of an order
/// nobody paid for is a lie the audit trail already refuses to tell.
String settlementPillLabel(AppLocalizations l10n, PosSettlement s) =>
    switch (s) {
      PosSettlement.paid => l10n.posPaidChip,
      PosSettlement.unpaid => l10n.posUnpaidChip,
      PosSettlement.notChargeable => l10n.posNoChargeChip,
    };

RestoflowTone settlementTone(PosSettlement s) => switch (s) {
  PosSettlement.paid => RestoflowTone.success,
  PosSettlement.unpaid => RestoflowTone.warning,
  PosSettlement.notChargeable => RestoflowTone.neutral,
};

IconData settlementIcon(PosSettlement s) => switch (s) {
  PosSettlement.paid => Icons.check_circle_outline,
  PosSettlement.unpaid => Icons.schedule,
  PosSettlement.notChargeable => Icons.money_off_outlined,
};

/// ORDER-EDIT-001E — the sent-order-edit chips of an order card (design §7.1
/// step 8): "Edited" once any edit was applied, and the kitchen's answer —
/// "Kitchen to confirm" while a required confirmation is outstanding, else
/// "Kitchen confirmed" once every required one was given. Returned as plain
/// pills so each surface places them inside its own [Wrap].
///
/// The list rows know only the snapshot's two server facts, so they never
/// pass [kitchenConfirmed]: "confirmed" needs the edit history, which only the
/// detail preview reads (decision D13). Pending wins over confirmed — the two
/// are never shown together.
List<Widget> orderEditChips(
  AppLocalizations l10n, {
  required String keySuffix,
  required int editCount,
  required bool kitchenAckPending,
  bool kitchenConfirmed = false,
}) => [
  if (editCount > 0)
    RestoflowStatusPill(
      key: Key('order-edited-$keySuffix'),
      label: l10n.posOrderEditedChip,
      tone: RestoflowTone.info,
      icon: Icons.edit_note,
    ),
  if (kitchenAckPending)
    RestoflowStatusPill(
      key: Key('order-edit-kitchen-pending-$keySuffix'),
      label: l10n.posOrderEditKitchenPendingChip,
      tone: RestoflowTone.warning,
      icon: Icons.pending_actions,
    )
  else if (kitchenConfirmed)
    RestoflowStatusPill(
      key: Key('order-edit-kitchen-confirmed-$keySuffix'),
      label: l10n.posOrderEditKitchenConfirmedChip,
      tone: RestoflowTone.success,
      icon: Icons.task_alt,
    ),
];
