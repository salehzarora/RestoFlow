import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';

/// A colour-coded status chip for a kitchen ticket.
///
/// RF-102 is restyle-only: the chip's VISIBLE TEXT is the raw
/// [KitchenTicketStatus] `canonicalName` (data) — it is not localized or
/// altered, and no status value/transition is added (DECISION D-018; RF-103
/// owns transitions).
///
/// RF-141E: rendered through the shared [RestoflowStatusPill] so the chip is
/// fully themeable (no hardcoded colours). Statuses map onto the semantic
/// [RestoflowTone] vocabulary (new/acknowledged share info-blue; bumped is the
/// quiet neutral), and `dense: false` keeps the kitchen-readable (larger)
/// text.
class KdsStatusChip extends StatelessWidget {
  const KdsStatusChip({required this.status, super.key});

  final KitchenTicketStatus status;

  @override
  Widget build(BuildContext context) {
    return RestoflowStatusPill(
      label: status.canonicalName,
      tone: kdsStatusTone(status),
      dense: false,
    );
  }
}

/// Maps each kitchen-ticket status to its semantic tone — blue for new and
/// acknowledged, warm/amber while cooking, green for ready, red for
/// cancelled, quiet neutral for bumped — so the kitchen keeps its at-a-glance
/// colour coding without any hardcoded colours. Shared by the chip AND the
/// ticket cards' status-accent edge (design-polish sprint) so the two signals
/// can never disagree.
///
/// DESIGN-001: `newTicket` moved neutral → info so a brand-new card carries the
/// SAME blue as the "New" column header it sits under (the approved status
/// vocabulary: blue = new/info). Previously the most time-critical card wore
/// the quietest colour while its column header was blue.
RestoflowTone kdsStatusTone(KitchenTicketStatus status) {
  switch (status) {
    case KitchenTicketStatus.newTicket:
      return RestoflowTone.info;
    case KitchenTicketStatus.acknowledged:
      return RestoflowTone.info;
    case KitchenTicketStatus.inPreparation:
      return RestoflowTone.warning;
    case KitchenTicketStatus.ready:
      return RestoflowTone.success;
    case KitchenTicketStatus.bumped:
      return RestoflowTone.neutral;
    case KitchenTicketStatus.cancelled:
      return RestoflowTone.danger;
  }
}
