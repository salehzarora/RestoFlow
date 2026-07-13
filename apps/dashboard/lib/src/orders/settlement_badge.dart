/// The ONE rendering of a [SettlementState] (MONEY-SETTLEMENT-CONSISTENCY-001).
///
/// The live board, the history list and the order detail sheet all render the payment
/// badge from here, so the same order can never read "Unpaid" on one screen and
/// "No charge" on another. Colour is never the only signal: each state carries its own
/// icon and its own localized label.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_history_models.dart';

/// The localized label — `No charge` for a non-chargeable (zero-total) order, which is
/// neither "Paid" (no payment was taken) nor "Unpaid" (nothing is owed).
String settlementLabel(AppLocalizations l10n, SettlementState s) => switch (s) {
  SettlementState.paid => l10n.dashboardPaid,
  SettlementState.unpaid => l10n.dashboardUnpaid,
  SettlementState.notChargeable => l10n.dashboardNoCharge,
};

/// Settled states are calm; only OUTSTANDING money warns. A non-chargeable order is
/// neutral: nothing happened and nothing needs to.
RestoflowTone settlementTone(SettlementState s) => switch (s) {
  SettlementState.paid => RestoflowTone.success,
  SettlementState.unpaid => RestoflowTone.warning,
  SettlementState.notChargeable => RestoflowTone.neutral,
};

IconData settlementIcon(SettlementState s) => switch (s) {
  SettlementState.paid => Icons.check_circle_outline,
  SettlementState.unpaid => Icons.schedule,
  SettlementState.notChargeable => Icons.money_off_outlined,
};

/// The badge itself — used wherever an order's payment state is shown.
RestoflowStatusPill settlementPill(AppLocalizations l10n, SettlementState s) =>
    RestoflowStatusPill(
      label: settlementLabel(l10n, s),
      tone: settlementTone(s),
      icon: settlementIcon(s),
    );
