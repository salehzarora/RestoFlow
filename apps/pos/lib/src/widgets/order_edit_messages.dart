import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_actions.dart' show PosOrderEditHold;
import '../data/order_edit_diff.dart' show OrderEditSendBlock;
import '../data/order_edit_journal_store.dart' show OrderEditJournalRecord;
import '../data/order_edit_read_model.dart' show PosKitchenChannel;
import '../data/order_edit_response.dart' show OrderEditApplied;
import '../state/order_edit_controller.dart';

/// ORDER-EDIT-001E — THE cashier-facing wording of the edit flow (plan §8b).
///
/// PURE: every function maps a typed value the controller or the planner
/// produced to its existing, translated string — no state, no widgets, no
/// raw backend text ever reaches the screen. The controller decides WHAT
/// happened ([OrderEditNotice], [OrderEditSendBlock], [OrderEditEntryResult]);
/// this file only says it.

/// The message of one [OrderEditNotice]. [items] are the item names an
/// `item_unavailable` refusal named (joined into its sentence).
String orderEditNoticeMessage(
  AppLocalizations l10n,
  OrderEditNotice notice, {
  List<String> items = const <String>[],
}) => switch (notice) {
  OrderEditNotice.rebased => l10n.posOrderEditRebased,
  OrderEditNotice.reasonRequired => l10n.posOrderEditReasonRequired,
  OrderEditNotice.allRemovedUseCancel => l10n.posOrderEditAllRemovedUseCancel,
  OrderEditNotice.discountExceedsOrderTotal =>
    l10n.posDiscountExceedsOrderTotal,
  OrderEditNotice.fullCompDenied => l10n.posDiscountFullCompDenied,
  OrderEditNotice.removalNotPermitted =>
    l10n.posOrderEditErrorRemovalNotPermitted,
  OrderEditNotice.finishedFoodNeedsManager =>
    l10n.posOrderEditErrorFinishedFoodNeedsManager,
  OrderEditNotice.notAllowed => l10n.posOrderEditErrorNotAllowed,
  OrderEditNotice.featureDisabled => l10n.posOrderEditErrorFeatureDisabled,
  OrderEditNotice.notEditable => l10n.posOrderEditErrorNotEditable,
  OrderEditNotice.alreadyPaid => l10n.posOrderEditErrorAlreadyPaid,
  OrderEditNotice.kitchenModeChanged =>
    l10n.posOrderEditErrorKitchenModeChanged,
  OrderEditNotice.taxModeUnsupported =>
    l10n.posOrderEditErrorTaxModeUnsupported,
  OrderEditNotice.lineHasDiscount => l10n.posOrderEditErrorLineHasDiscount,
  OrderEditNotice.legacyLine => l10n.posOrderEditErrorLegacyLine,
  OrderEditNotice.itemUnavailable => l10n.posOrderEditErrorItemUnavailable(
    items.join(', '),
  ),
  OrderEditNotice.optionNotInScope => l10n.posOrderEditErrorOptionNotInScope,
  OrderEditNotice.prepSnapshotStale => l10n.posPrepSnapshotStale,
  OrderEditNotice.invalid => l10n.posOrderEditErrorInvalid,
  OrderEditNotice.tooManyChanges => l10n.posOrderEditErrorTooManyChanges,
  OrderEditNotice.blockedUnacknowledged =>
    l10n.posOrderEditBlockedUnacknowledged,
  OrderEditNotice.slipTooLarge => l10n.posOrderEditErrorSlipTooLarge,
  OrderEditNotice.retry => l10n.posOrderEditRetry,
  OrderEditNotice.conflictBlocked => l10n.posAdditionConflictBlocked,
  OrderEditNotice.hydrating => l10n.posAdditionLoadingPending,
  OrderEditNotice.needsConnection => l10n.posOrderEditNeedsConnection,
  OrderEditNotice.detailUnavailable => l10n.posAdditionFailedRetry,
};

/// The result toast of an APPLIED edit (design §7.1 point 8), from the
/// server's own landing facts:
///
///  * the kitchen must confirm (`kitchen_ack_required`) — "Change N sent:
///    kitchen must confirm";
///  * otherwise, on a KDS branch, a change that landed only in a NEW round —
///    "Change N sent: new ticket for the kitchen";
///  * otherwise — paper included — "Change N saved". The paper change slip is
///    ORDER-EDIT-001F: until it prints, this till never claims "printed";
///  * [refreshRequired] (applied, not yet proven by the authoritative detail)
///    is always the honest "Change N saved";
///  * [remakeCount] > 0 adds "Already cooked: N dishes will be remade" (the
///    frozen plan's allotment, decision D8) on its own line.
String orderEditAppliedMessage(
  AppLocalizations l10n,
  OrderEditApplied applied, {
  int remakeCount = 0,
  bool refreshRequired = false,
}) {
  final n = applied.editNumber;
  final head = refreshRequired
      ? l10n.posOrderEditResultSaved(n)
      : applied.kitchenAckRequired
      ? l10n.posOrderEditResultKitchenMustConfirm(n)
      : (applied.kitchenChannel == PosKitchenChannel.kds &&
            applied.newRoundId != null)
      ? l10n.posOrderEditResultNewTicket(n)
      : l10n.posOrderEditResultSaved(n);
  if (remakeCount <= 0) return head;
  return '$head\n${l10n.posOrderEditResultRemake(remakeCount)}';
}

/// The message of any [OrderEditResult], or null when there is nothing to say
/// (a send the footer already explains, or a superseded continuation).
///
/// A rebase names what no longer applies on its own line.
String? orderEditResultMessage(AppLocalizations l10n, OrderEditResult result) {
  final applied = result.applied;
  if (result.status == OrderEditSubmitStatus.applied && applied != null) {
    return orderEditAppliedMessage(
      l10n,
      applied,
      remakeCount: result.remakeCount,
      refreshRequired: result.refreshRequired,
    );
  }
  final notice = result.notice;
  if (notice == null) return null;
  final message = orderEditNoticeMessage(
    l10n,
    notice,
    items: result.unavailableItems,
  );
  if (result.droppedItems.isEmpty) return message;
  return '$message\n'
      '${l10n.posOrderEditRebaseDropped(result.droppedItems.join(', '))}';
}

/// Why "Send changes" is disabled — the footer's one reason line, in the
/// order [orderEditSendBlock] reports them (design §7.1 point 4).
String orderEditSendBlockMessage(
  AppLocalizations l10n,
  OrderEditSendBlock block,
) => switch (block) {
  OrderEditSendBlock.noChanges => l10n.posOrderEditNoChanges,
  OrderEditSendBlock.wouldEmpty => l10n.posOrderEditAllRemovedUseCancel,
  OrderEditSendBlock.discountExceeds =>
    l10n.posOrderEditDiscountExceedsNewSubtotal,
  OrderEditSendBlock.fullCompDenied => l10n.posDiscountFullCompDenied,
  OrderEditSendBlock.tooManyChanges => l10n.posOrderEditErrorTooManyChanges,
  OrderEditSendBlock.invalidLineChange => l10n.posOrderEditErrorInvalid,
  OrderEditSendBlock.removalNotPermitted =>
    l10n.posOrderEditErrorRemovalNotPermitted,
  OrderEditSendBlock.finishedFoodNeedsManager =>
    l10n.posOrderEditErrorFinishedFoodNeedsManager,
  OrderEditSendBlock.offline => l10n.posOrderEditNeedsConnection,
  OrderEditSendBlock.reasonRequired => l10n.posOrderEditReasonRequired,
  OrderEditSendBlock.reasonOtherRequired =>
    l10n.posOrderEditReasonOtherRequired,
};

/// Why an "Edit order" tap did not open the edit, or null when there is
/// nothing to say: it [OrderEditEntryResult.entered], it was superseded by a
/// newer tap, or the cart is not empty (the caller offers Park / Clear).
///
/// A not-found order is the anti-oracle: the server does not know it yet —
/// "Waiting for the order to reach the server" (design §7.1 point 1).
String? orderEditEntryMessage(
  AppLocalizations l10n,
  OrderEditEntryResult result,
) => switch (result) {
  OrderEditEntryResult.entered ||
  OrderEditEntryResult.superseded ||
  OrderEditEntryResult.cartNotEmpty => null,
  OrderEditEntryResult.hydrating => l10n.posAdditionLoadingPending,
  // The cart holds another flow's work — an open edit or an Add-items
  // addition. Neither can be parked or cleared, so no action is offered.
  OrderEditEntryResult.busy ||
  OrderEditEntryResult.additionActive => l10n.posOrderEditCartNotEmptyBody,
  OrderEditEntryResult.offline => l10n.posOrderEditNeedsConnection,
  OrderEditEntryResult.pendingAttempt => l10n.posOrderEditPendingBlocked,
  OrderEditEntryResult.orderNotFound => l10n.posOrderEditBlockedUnacknowledged,
  OrderEditEntryResult.featureDisabled => l10n.posOrderEditErrorFeatureDisabled,
  OrderEditEntryResult.notEditable => l10n.posOrderEditErrorNotEditable,
  OrderEditEntryResult.alreadyPaid => l10n.posOrderEditErrorAlreadyPaid,
  OrderEditEntryResult.kitchenModeChanged =>
    l10n.posOrderEditErrorKitchenModeChanged,
  OrderEditEntryResult.detailUnavailable => l10n.posAdditionFailedRetry,
};

/// The row pill of an `orderEdit` pending stamp, by what the stamp
/// actually is ([PosOrderEditHold]) — the same words the cart banner uses for
/// the same states:
///
///  * on the wire, or outcome unknown — "Sending changes…";
///  * APPLIED, the refresh not yet proven — "Change N saved" (never "not
///    sent": the server has it and the kitchen was told). Without a number,
///    the refresh it needs — "Refresh orders";
///  * a conflict — the existing "needs to be resolved" wording;
///  * the journal's startup blanket — the neutral "Checking for unfinished
///    changes" wording: it is no evidence about this order.
String orderEditHoldLabel(
  AppLocalizations l10n,
  PosOrderEditHold? hold, {
  int? appliedEditNumber,
}) => switch (hold) {
  PosOrderEditHold.appliedAwaitingRefresh =>
    appliedEditNumber == null
        ? l10n.posOrdersRefresh
        : l10n.posOrderEditResultSaved(appliedEditNumber),
  PosOrderEditHold.conflict => l10n.posAdditionConflictBlocked,
  PosOrderEditHold.journalLoading => l10n.posAdditionLoadingPending,
  PosOrderEditHold.sending || null => l10n.posOrderEditSending,
};

/// The label of the row's Retry for [record]: an applied edit only needs its
/// refresh ("Refresh orders" — the retry never sends it again); an edit whose
/// outcome is unknown is replayed ("Changes not sent — tap to retry").
String orderEditRetryLabel(
  AppLocalizations l10n,
  OrderEditJournalRecord record,
) => record.awaitingRefresh ? l10n.posOrdersRefresh : l10n.posOrderEditRetry;
