import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show KitchenModeResult, runtimeConfigProvider;

import '../data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import '../state/addition_controller.dart';
import '../state/discount_controller.dart';
import '../state/outbox_controller.dart';
import '../state/pos_order_complete_controller.dart';
import 'order_actions.dart';
import 'order_close_policy.dart';
import 'order_snapshot.dart';
import 'order_submission.dart' show OutboxEntry;
import 'recent_order.dart';
import 'staff_capabilities.dart' show PosStaffCapabilities;

/// POS-OPEN-ORDERS-STRIP-011 — the ONE shared assembly of the inputs
/// [resolveOrderActions] needs.
///
/// The policy body (`resolveOrderActions`) has always been central, but its
/// INPUTS — the pending-operation join, the submit-acknowledgement predicate,
/// the amendment-hydration blanket and the close-eligibility verdict — were
/// assembled inline in `RecentOrdersSheet.build` only. The confirmation screen
/// already showed how a second caller drifts (it omits several inputs); a
/// third caller must not hand-roll them again. This class is that assembly,
/// moved VERBATIM from the sheet (POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001
/// Pass B/C, PSC-001C, MONEY-CODEX-FINAL-CLOSURE-005 F1/F4,
/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 Gap B — every comment kept where the
/// rule lives now). Behaviour is byte-identical in effect: same providers
/// watched, same joins, same verdicts.
///
/// Construct it with [PosOrderActionsAssembly.watch] from a `build` method so
/// every input is WATCHED (never captured once): the moment a queued submit
/// flips to `applied`, every consumer recomputes on the same mounted tree.
class PosOrderActionsAssembly {
  PosOrderActionsAssembly._({
    required PosStaffCapabilities? capabilities,
    required bool isDemo,
    required Map<String, PosPendingKind> pendingByIdentity,
    required Map<String, OutboxEntry> submitByIdentity,
    required Set<String> hydrationBlanketOnly,
    required KitchenModeResult? verifiedMode,
    required Set<String> completingIds,
  }) : _capabilities = capabilities,
       _isDemo = isDemo,
       _pendingByIdentity = pendingByIdentity,
       _submitByIdentity = submitByIdentity,
       _hydrationBlanketOnly = hydrationBlanketOnly,
       _verifiedMode = verifiedMode,
       _completingIds = completingIds;

  /// Watches every input provider and builds the per-identity joins over the
  /// FULL loaded collection [orders] (always pass the whole
  /// `posRecentOrdersControllerProvider` list, not a filtered view — the
  /// hydration blanket must stamp every affected row).
  factory PosOrderActionsAssembly.watch(
    WidgetRef ref,
    List<PosRecentOrder> orders,
  ) {
    // EFFECTIVE rights, or null when UNKNOWN. Unknown is NOT denied — a failed
    // probe must not silently strip a manager of the ability to discount; the
    // server refuses correctly either way.
    final caps = ref.watch(staffCapabilitiesProvider).value;
    final entries = ref.watch(outboxControllerProvider);
    // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass B] Demo never reaches
    // the acknowledgement rule: a demo entry is never pushed, so it stays
    // pending forever and would strip payment from every demo order.
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap B): the inputs for the
    // printer-only Complete safety net — the VERIFIED kitchen mode (null
    // unless verified printer_only/kds) + the orders with a completion in
    // flight.
    final verifiedMode = ref.watch(posVerifiedKitchenModeProvider);
    final completingIds = ref.watch(posOrderCompleteControllerProvider);

    // The local queue, joined by ORDER IDENTITY. It reports what THIS DEVICE
    // is doing — never what the ORDER is doing. Conflating the two is what
    // made a queued payment look like a lifecycle state. (Joined on the code,
    // this map once put one order's "syncing" badge on a DIFFERENT order that
    // happened to share it.)
    final pendingByIdentity = <String, PosPendingKind>{
      for (final e in entries)
        if (e.syncState.isPending)
          posOutboxEntryIdentity(e).key: PosPendingKind.submit,
    };
    // Pass B: this device's `order.submit` entry per identity — the ONE input
    // the acknowledgement predicate needs. Restricted to submits on purpose:
    // a queued payment or discount targets the same order id and says nothing
    // about whether the ORDER was ever created.
    final submitByIdentity = <String, OutboxEntry>{
      for (final e in entries)
        if (e.operationType == 'order.submit') posOutboxEntryIdentity(e).key: e,
    };

    // PSC-001C: an addition THIS DEVICE has in flight withdraws that order's
    // other controls, exactly like any other pending local operation.
    // MONEY-CODEX-FINAL-CLOSURE-005 (F1/F4): every order with a live durable
    // amendment record, and every order at all while the journal is still
    // being read — keyed through `identity.key`.
    final addition = ref.watch(additionControllerProvider);
    final additionNotifier = ref.read(additionControllerProvider.notifier);
    final hydrating = additionNotifier.isStartupBlocked;
    final blockedOrderIds = <String>{
      ...additionNotifier.blockedOrderIds,
      if (addition.target case final t?)
        if (addition.sending || addition.failed || addition.awaitingRefresh)
          t.orderId,
    };
    // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass C] Which rows carry the
    // `itemsAdd` stamp ONLY because the journal has not been read yet. The
    // blanket is a fail-closed for MONEY actions; this set lets the central
    // policy relax the READ-ONLY pre-bill for rows it has no actual evidence
    // against. A row with a REAL blocked amendment is never in it.
    final hydrationBlanketOnly = <String>{};
    if (hydrating || blockedOrderIds.isNotEmpty) {
      for (final o in orders) {
        final id = o.orderId;
        final reallyBlocked = id != null && blockedOrderIds.contains(id);
        if (hydrating || reallyBlocked) {
          pendingByIdentity[o.identity.key] = PosPendingKind.itemsAdd;
          if (!reallyBlocked) hydrationBlanketOnly.add(o.identity.key);
        }
      }
    }

    return PosOrderActionsAssembly._(
      capabilities: caps,
      isDemo: isDemo,
      pendingByIdentity: pendingByIdentity,
      submitByIdentity: submitByIdentity,
      hydrationBlanketOnly: hydrationBlanketOnly,
      verifiedMode: verifiedMode,
      completingIds: completingIds,
    );
  }

  final PosStaffCapabilities? _capabilities;
  final bool _isDemo;
  final Map<String, PosPendingKind> _pendingByIdentity;
  final Map<String, OutboxEntry> _submitByIdentity;
  final Set<String> _hydrationBlanketOnly;
  final KitchenModeResult? _verifiedMode;
  final Set<String> _completingIds;

  /// This device's queued mutation for [order], if any (after the amendment
  /// blanket stamping) — the same value fed into [resolveFor].
  PosPendingKind? pendingFor(PosRecentOrder order) =>
      _pendingByIdentity[order.identity.key];

  /// Pass B: payment is withdrawn while the server has not acknowledged this
  /// order's submit (fail-open — see [posSubmitUnacknowledged]).
  bool submitUnacknowledgedFor(PosRecentOrder order) => posSubmitUnacknowledged(
    isDemo: _isDemo,
    hasServerSnapshot: order.snapshot != null,
    submitEntry: _submitByIdentity[order.identity.key],
  );

  /// The centrally-resolved action set for [order] — exactly what the Orders
  /// sheet has always computed per row.
  PosOrderActions resolveFor(PosRecentOrder order) {
    final unacknowledged = submitUnacknowledgedFor(order);
    return resolveOrderActions(
      order,
      capabilities: _capabilities,
      pending: pendingFor(order),
      submitUnacknowledged: unacknowledged,
      // Pass C: this row's `itemsAdd` stamp is the startup blanket, not a
      // known amendment — it relaxes the read-only pre-bill and nothing else.
      amendmentsHydrating: _hydrationBlanketOnly.contains(order.identity.key),
      // Gap B: the central close-eligibility policy decides the printer-only
      // Complete safety net (server re-enforces).
      completeEligible:
          posOrderCloseEligibility(
            // STALE-TABLE-ORDER-RECOVERY-001: the SERVER's status (snapshot
            // first). A by-id discovered row carries no local status, and the
            // printer-only Complete safety net is exactly its canonical repair.
            status: order.serverStatus ?? '',
            settled: order.settlement != PosSettlement.unpaid,
            verifiedMode: _verifiedMode,
            actorAuthorized: _capabilities?.canFinishKitchenOrders ?? false,
            transitionInFlight:
                pendingFor(order) != null ||
                _completingIds.contains(order.orderId),
          ) ==
          PosOrderCloseEligibility.allowed,
    );
  }
}
