import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;

import '../data/demo_tables.dart';
import 'cart_controller.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — a recoverable snapshot of the LAST submit
/// attempt, kept until the server authoritatively ACCEPTS the order or the cashier
/// deliberately discards it. It exists so a permanently-rejected NEW order
/// (item_unavailable) is not a dead-end: the cashier can restore the exact draft
/// (products, quantities, modifiers, notes, order type, table) into the cart,
/// correct it, and send a NEW deliberate submit — never a retry of the same
/// (server-ledgered, replay-only) rejected operation identity.
class PosDraftRecovery {
  const PosDraftRecovery({
    required this.draft,
    required this.orderType,
    required this.outboxEntryId,
    this.table,
    this.customerName,
  });

  final CartDraftSnapshot draft;
  final OrderType orderType;

  /// The outbox entry id of the submit this draft belongs to — so the recovery is
  /// only offered for the SAME rejected attempt (never a stale one).
  final String outboxEntryId;

  final DemoTable? table;
  final String? customerName;
}

class PosDraftRecoveryController extends Notifier<PosDraftRecovery?> {
  @override
  PosDraftRecovery? build() => null;

  /// Capture the draft of a just-started submit (overwrites any prior — only the
  /// LATEST attempt is recoverable, so restore can never revive a stale draft).
  void capture(PosDraftRecovery recovery) => state = recovery;

  /// Clear the recovery (after a restore, a discard, or an accepted order).
  void clear() => state = null;

  /// Clear only if the held recovery belongs to [outboxEntryId] (used when that
  /// entry is accepted — a newer attempt's recovery must not be wiped).
  void clearIfFor(String outboxEntryId) {
    if (state?.outboxEntryId == outboxEntryId) state = null;
  }
}

final posDraftRecoveryProvider =
    NotifierProvider<PosDraftRecoveryController, PosDraftRecovery?>(
      PosDraftRecoveryController.new,
    );
