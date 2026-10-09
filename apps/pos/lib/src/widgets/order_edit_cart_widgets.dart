import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_edit_baseline.dart';
import '../data/order_edit_diff.dart';
import '../data/order_edit_read_model.dart' show PosLineStage;
import '../data/order_identity.dart' show PosOrderIdentity;
import '../data/staff_capabilities.dart';
import '../design/pos_visual_tokens.dart';
import '../format/money_format.dart';
import '../format/payment_method_label.dart' show taxLineLabel;
import '../pos_palette.dart';
import '../state/cart_controller.dart';
import '../state/order_edit_controller.dart';
import '../state/receipt_print_controller.dart';
import 'modifier_selection_sheet.dart' show ltrIsolate;
import 'order_edit_messages.dart';

/// ORDER-EDIT-001E — the cart's EDIT MODE chrome (design §7.1 points 3-6,
/// plan §8a): the banner, the per-line stage chips, badges and hints, the
/// "Was → Now" footer with its one disabled reason, the reason chips, the
/// finished-food confirm sheet and the cart-not-empty prompt.
///
/// Every control here DRAWS what the planner ([planOrderEdit]) and the edit
/// controller already decided — no money is computed in a widget, and every
/// string is an existing, translated key.

// ---------------------------------------------------------------------------
// The reason draft.
// ---------------------------------------------------------------------------

/// The cashier's reason chip and "Other" text for ONE open edit.
///
/// Bound to the edit's entry [generation]: a draft written for an earlier
/// edit is ignored (read as empty) by the next one, so a stale reason can
/// never ride a later edit.
class OrderEditReasonDraft {
  const OrderEditReasonDraft({
    this.generation = -1,
    this.code,
    this.text = '',
    this.chosen = false,
  });

  final int generation;

  /// The chip the cashier tapped (null when they cleared it).
  final String? code;

  /// The "Other" text, as typed.
  final String text;

  /// Whether the cashier touched the chips at all — until then the plan's
  /// preselect ("Customer changed mind", design §7.1 point 5) applies.
  final bool chosen;
}

/// The reason draft of the open edit. Held in a provider, not in a widget, so
/// it survives the side cart and the phone sheet swapping hosts.
final orderEditReasonDraftProvider = StateProvider<OrderEditReasonDraft>(
  (_) => const OrderEditReasonDraft(),
);

/// The reason the send uses: the cashier's own chip once they touched the
/// chips, otherwise the plan's preselect (or none). [generation] is the open
/// edit's entry generation (`CartEditContext.generation`).
({String? code, String text}) orderEditEffectiveReason(
  OrderEditReasonDraft draft, {
  required int generation,
  required OrderEditPlan plan,
}) {
  final mine = draft.generation == generation;
  return (
    code: mine && draft.chosen ? draft.code : plan.preselectedReasonCode,
    text: mine ? draft.text : '',
  );
}

// ---------------------------------------------------------------------------
// Decision D7 — the pre-bill this till presented.
// ---------------------------------------------------------------------------

/// The receipt-print job key of an order's customer BILL — the same key the
/// order row prints the bill under (`'bill:<identity>'`); a server-backed
/// order's identity is always its server id.
String orderEditBillJobKey(String orderId) =>
    'bill:${PosOrderIdentity.server(orderId).key}';

/// Decision D7: the instant THIS session handed a bill for the order to a
/// printer, or null. Only a job that reached the printer counts; nothing is
/// guessed for a bill printed elsewhere (no durable marker exists yet).
DateTime? orderEditBillPresentedAt(ReceiptPrintJob? job) =>
    job != null && job.status == PrintJobStatus.sentToPrinter ? job.at : null;

// ---------------------------------------------------------------------------
// Per-line controls.
// ---------------------------------------------------------------------------

/// The one explanation a sent line carries when its controls are narrowed.
enum OrderEditLineHint {
  removeOnlyDiscount,
  removeOnlyLegacy,
  keepOrRemoveOnly,
}

/// Which of a cart line's controls are live in edit mode, and what the line
/// says about it. PURE — the cart tile only draws it.
class OrderEditLineControls {
  const OrderEditLineControls({
    this.canIncrease = false,
    this.canDecrease = false,
    this.canRemove = false,
    this.canEdit = false,
    this.canUndo = false,
    this.managerNeeded = false,
    this.hint,
  });

  final bool canIncrease;
  final bool canDecrease;
  final bool canRemove;
  final bool canEdit;

  /// A struck-through sent line can be taken back.
  final bool canUndo;

  /// "Manager needed" (finished-food switch ON, KDS, a cashier, Ready/Served).
  final bool managerNeeded;
  final OrderEditLineHint? hint;
}

/// The edit-mode controls of [line] (design §7.1 point 3):
///
///  * a line the cashier ADDED is an ordinary cart line (up to 999);
///  * a struck-through sent line offers Undo only;
///  * REMOVE ONLY (a line discount, a legacy price) and KEEP OR REMOVE ONLY
///    (the item or an option left the menu, decision D11) keep the trash
///    alone;
///  * '+' is withheld while the item is not sellable, and at 999;
///  * when `void_order` is KNOWN denied (unknown is not denied, D14), or the
///    line needs a manager, the removing controls go — trash, edit, and '−'
///    below the sent quantity — while '+' stays;
///  * [locked] (a frozen attempt owns the cart) turns everything off.
OrderEditLineControls orderEditLineControls(
  CartLineView line, {
  required OrderEditBaseline baseline,
  PosStaffCapabilities? capabilities,
  bool locked = false,
}) {
  final source = line.editSource;
  if (source == null) {
    if (locked) return const OrderEditLineControls();
    return OrderEditLineControls(
      canIncrease: line.quantity < kOrderEditMaxQuantity,
      canDecrease: true,
      canRemove: true,
      canEdit: true,
    );
  }
  final managerNeeded = baseline.needsManagerFor(source, capabilities);
  final hint = source.hasLineDiscount
      ? OrderEditLineHint.removeOnlyDiscount
      : source.isLegacy
      ? OrderEditLineHint.removeOnlyLegacy
      : source.keepOrRemoveOnly
      ? OrderEditLineHint.keepOrRemoveOnly
      : null;
  if (line.editRemoved) {
    return OrderEditLineControls(
      canUndo: !locked,
      managerNeeded: managerNeeded,
      hint: hint,
    );
  }
  if (locked) {
    return OrderEditLineControls(managerNeeded: managerNeeded, hint: hint);
  }
  final removing = capabilities?.voidOrder != false && !managerNeeded;
  final fixed = source.removeOnly || source.keepOrRemoveOnly;
  final primary = line.lineId == orderEditLineIdFor(source.orderItemId);
  return OrderEditLineControls(
    canIncrease:
        !fixed &&
        !source.increaseBlocked &&
        line.quantity < kOrderEditMaxQuantity,
    // Below the sent quantity '−' is a removing change; above it, it only
    // takes back an increase.
    canDecrease:
        !fixed && (removing || (primary && line.quantity > source.quantity)),
    canRemove: removing,
    canEdit: removing && !fixed,
    managerNeeded: managerNeeded,
    hint: hint,
  );
}

String orderEditLineHintText(AppLocalizations l10n, OrderEditLineHint hint) =>
    switch (hint) {
      OrderEditLineHint.removeOnlyDiscount =>
        l10n.posOrderEditRemoveOnlyDiscount,
      OrderEditLineHint.removeOnlyLegacy => l10n.posOrderEditRemoveOnlyLegacy,
      OrderEditLineHint.keepOrRemoveOnly => l10n.posOrderEditKeepOrRemoveOnly,
    };

// ---------------------------------------------------------------------------
// Line decorations.
// ---------------------------------------------------------------------------

/// The kitchen stage of a sent line (design §7.1 point 3): Waiting / In
/// kitchen / Ready / Served, and "Printed" on every line of a printer-only
/// branch.
class OrderEditStageChip extends StatelessWidget {
  const OrderEditStageChip({required this.stage, super.key});

  final PosLineStage stage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, tone, icon) = switch (stage) {
      PosLineStage.waiting => (
        l10n.posOrderEditStageWaiting,
        RestoflowTone.neutral,
        Icons.schedule,
      ),
      PosLineStage.inKitchen => (
        l10n.posOrderEditStageInKitchen,
        RestoflowTone.info,
        Icons.local_fire_department_outlined,
      ),
      PosLineStage.ready => (
        l10n.posOrderEditStageReady,
        RestoflowTone.success,
        Icons.done_all,
      ),
      PosLineStage.served => (
        l10n.posOrderEditStageServed,
        RestoflowTone.neutral,
        Icons.room_service_outlined,
      ),
      PosLineStage.printed => (
        l10n.posOrderEditStagePrinted,
        RestoflowTone.neutral,
        Icons.print_outlined,
      ),
    };
    return RestoflowStatusPill(label: label, tone: tone, icon: icon);
  }
}

/// The edit-mode row under a cart line's name: its stage chip, the "New"
/// badge of an added line, "Manager needed", and the one hint that explains
/// narrowed controls.
class OrderEditLineBadges extends StatelessWidget {
  const OrderEditLineBadges({
    required this.line,
    required this.controls,
    super.key,
  });

  final CartLineView line;
  final OrderEditLineControls controls;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stage = line.editStage;
    final hint = controls.hint;
    final chips = <Widget>[
      if (stage != null)
        OrderEditStageChip(
          key: Key('cart-line-stage-${line.lineId}'),
          stage: stage,
        ),
      if (line.editAdded)
        RestoflowStatusPill(
          key: Key('cart-line-new-${line.lineId}'),
          label: l10n.posOrderEditNewBadge,
          tone: RestoflowTone.success,
          icon: Icons.fiber_new_outlined,
        ),
      if (controls.managerNeeded)
        RestoflowStatusPill(
          key: Key('cart-line-manager-${line.lineId}'),
          label: l10n.posOrderEditManagerNeeded,
          tone: RestoflowTone.warning,
          icon: Icons.lock_outline,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: RestoflowSpacing.xxs),
            child: Wrap(
              spacing: RestoflowSpacing.xs,
              runSpacing: RestoflowSpacing.xxs,
              children: chips,
            ),
          ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: RestoflowSpacing.xxs),
            child: Text(
              orderEditLineHintText(l10n, hint),
              key: Key('cart-line-hint-${line.lineId}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: RestoflowTone.warning.styleOf(theme).accent,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The banner.
// ---------------------------------------------------------------------------

/// Asks before "Discard changes" — the order stays exactly as it was sent.
Future<bool> confirmOrderEditDiscard(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('order-edit-discard-dialog'),
      title: Text(l10n.posOrderEditDiscardConfirmTitle),
      content: Text(l10n.posOrderEditDiscardConfirmBody),
      actions: [
        TextButton(
          key: const Key('order-edit-discard-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          key: const Key('order-edit-discard-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.posOrderEditDiscard),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The amber edit-mode banner (design §7.1 point 3), in the order-setup
/// slot: "Editing #A1B2C3 · Table 4" with "Discard changes" while the edit
/// is unsent, then the honest state of the send — sending, not sent (tap to
/// retry the SAME identity), in conflict, or saved but not yet refreshed.
///
/// Discard is DISABLED, not hidden, once anything reached the server: the
/// controller refuses it regardless ([OrderEditState.canDiscard]).
class OrderEditBanner extends StatelessWidget {
  const OrderEditBanner({
    required this.orderCode,
    required this.edit,
    required this.onDiscard,
    required this.onRetry,
    required this.onRetryRefresh,
    this.tableLabel,
    this.removalNotAllowed = false,
    super.key,
  });

  final String orderCode;
  final String? tableLabel;
  final OrderEditState edit;
  final VoidCallback onDiscard;
  final VoidCallback onRetry;
  final VoidCallback onRetryRefresh;

  /// `void_order` is KNOWN denied: say once that additions still work.
  final bool removalNotAllowed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final conflict =
        edit.lastError == 'conflict' ||
        (edit.attempt != null &&
            edit.conflictingOrderIds.contains(edit.attempt!.orderId));
    final failed = edit.phase == OrderEditPhase.failed;
    final applied = edit.phase == OrderEditPhase.appliedAwaitingRefresh;
    final tone = failed
        ? RestoflowTone.danger
        : applied
        ? RestoflowTone.info
        : RestoflowTone.warning;
    final style = tone.styleOf(theme);
    final table = tableLabel;
    final text = switch (edit.phase) {
      OrderEditPhase.sending => l10n.posOrderEditSending,
      OrderEditPhase.failed =>
        conflict ? l10n.posAdditionConflictBlocked : l10n.posOrderEditRetry,
      OrderEditPhase.appliedAwaitingRefresh => l10n.posOrderEditResultSaved(
        edit.applied?.editNumber ?? 0,
      ),
      _ =>
        table != null && table.isNotEmpty
            ? l10n.posOrderEditBannerWithTable(orderCode, table)
            : l10n.posOrderEditBanner(orderCode),
    };
    final message = Text(
      text,
      key: const Key('pos-order-edit-banner-text'),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: style.accent,
        fontWeight: FontWeight.w700,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    return Container(
      key: const Key('pos-order-edit-banner'),
      width: double.infinity,
      color: style.container,
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (edit.sending)
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: style.accent,
                  ),
                )
              else
                Icon(Icons.edit_note, size: 18, color: style.accent),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                // "Changes not sent — tap to retry": the line itself retries
                // the SAME identity (the footer's Send does too).
                child: failed && !conflict
                    ? InkWell(
                        key: const Key('pos-order-edit-retry'),
                        onTap: onRetry,
                        child: message,
                      )
                    : message,
              ),
              if (applied)
                TextButton(
                  key: const Key('pos-order-edit-retry-refresh'),
                  onPressed: onRetryRefresh,
                  child: Text(l10n.posOrdersRefresh),
                )
              else
                TextButton(
                  key: const Key('pos-order-edit-discard'),
                  onPressed: edit.canDiscard ? onDiscard : null,
                  child: Text(l10n.posOrderEditDiscard),
                ),
            ],
          ),
          if (removalNotAllowed)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 18 + RestoflowSpacing.sm,
              ),
              child: Text(
                l10n.posOrderEditRemovalNotAllowedHint,
                key: const Key('pos-order-edit-removal-hint'),
                style: theme.textTheme.bodySmall?.copyWith(color: style.accent),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The reason chips.
// ---------------------------------------------------------------------------

/// The one-tap reason chips (design §7.1 point 5), shown only when the plan
/// removes, reduces or modifies something: the five codes labelled by the
/// shared `orderEditReasonLabel`, and an "Other" text field (≤ 200).
class OrderEditReasonChips extends StatefulWidget {
  const OrderEditReasonChips({
    required this.selected,
    required this.otherText,
    required this.onSelected,
    required this.onOtherChanged,
    this.enabled = true,
    super.key,
  });

  /// The effective chip (the cashier's, or the preselect).
  final String? selected;
  final String otherText;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String> onOtherChanged;
  final bool enabled;

  @override
  State<OrderEditReasonChips> createState() => _OrderEditReasonChipsState();
}

class _OrderEditReasonChipsState extends State<OrderEditReasonChips> {
  late final TextEditingController _other = TextEditingController(
    text: widget.otherText,
  );

  @override
  void didUpdateWidget(covariant OrderEditReasonChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.otherText != _other.text) _other.text = widget.otherText;
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      key: const Key('order-edit-reasons'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.posOrderEditReasonTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: kRestoflowInk,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        Wrap(
          spacing: RestoflowSpacing.xs,
          runSpacing: RestoflowSpacing.xs,
          children: [
            for (final code in kOrderEditReasonCodes)
              ChoiceChip(
                key: Key('order-edit-reason-$code'),
                label: Text(orderEditReasonLabel(l10n, code) ?? ''),
                selected: widget.selected == code,
                onSelected: widget.enabled
                    ? (on) => widget.onSelected(on ? code : null)
                    : null,
              ),
          ],
        ),
        if (widget.selected == 'other') ...[
          const SizedBox(height: RestoflowSpacing.xs),
          TextField(
            key: const Key('order-edit-reason-other'),
            controller: _other,
            enabled: widget.enabled,
            maxLength: kOrderEditReasonTextMaxLength,
            decoration: InputDecoration(
              hintText: l10n.posOrderEditReasonOtherHint,
              isDense: true,
            ),
            onChanged: widget.onOtherChanged,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The footer.
// ---------------------------------------------------------------------------

/// The edit-mode footer (design §7.1 point 4): the planned subtotal, "Discount
/// ₪10.00 kept", the tax recomputed with the server's rule, "Was ₪85.00 → Now
/// ₪78.00 (−₪7.00)", the ONE reason Send is disabled (with "Cancel order" /
/// "Lower discount" where they resolve it), the reason chips, and "Send
/// changes".
///
/// Every figure is the live plan's ([orderEditPlanProvider]) — the same
/// function, with the same inputs, as the payload's `expected` totals. Each
/// money run inside the localized phrase is an LTR isolate, so ar/he (←) never
/// reorder a sign, a symbol or a digit.
class OrderEditFooter extends StatelessWidget {
  const OrderEditFooter({
    required this.plan,
    required this.currencyCode,
    required this.onSend,
    this.block,
    this.taxRateBp = 0,
    this.sending = false,
    this.onCancelOrder,
    this.onLowerDiscount,
    this.reasons,
    super.key,
  });

  final OrderEditPlan plan;
  final String currencyCode;
  final int taxRateBp;

  /// Why Send is disabled, or null.
  final OrderEditSendBlock? block;

  /// Null = Send disabled.
  final VoidCallback? onSend;
  final bool sending;

  /// "Cancel order" — offered with [OrderEditSendBlock.wouldEmpty].
  final VoidCallback? onCancelOrder;

  /// "Lower discount" — offered with [OrderEditSendBlock.discountExceeds].
  final VoidCallback? onLowerDiscount;

  /// The reason chips, when the plan removes something.
  final Widget? reasons;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String money(int minor) => MoneyFormatter.formatMinor(minor, currencyCode);
    final totals = l10n.posOrderEditTotalsChange(
      ltrIsolate(money(plan.beforeGrandMinor)),
      ltrIsolate(money(plan.grandMinor)),
      ltrIsolate(
        MoneyFormatter.formatSignedDeltaMinor(plan.deltaMinor, currencyCode),
      ),
    );
    final reason = block;
    final warning = RestoflowTone.warning.styleOf(theme);
    final reasonAction = switch (reason) {
      OrderEditSendBlock.wouldEmpty when onCancelOrder != null => TextButton(
        key: const Key('order-edit-cancel-order'),
        onPressed: onCancelOrder,
        child: Text(l10n.posCancelOrderAction),
      ),
      OrderEditSendBlock.discountExceeds when onLowerDiscount != null =>
        TextButton(
          key: const Key('order-edit-lower-discount'),
          onPressed: onLowerDiscount,
          child: Text(l10n.posOrderEditLowerDiscount),
        ),
      _ => null,
    };
    return Container(
      key: const Key('order-edit-footer'),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: BorderDirectional(top: BorderSide(color: kRestoflowHairline)),
      ),
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: kPosTotalsBed,
                borderRadius: BorderRadius.circular(RestoflowRadii.md),
                border: Border.all(color: kPosRowSeparator),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EditAmountRow(
                    label: l10n.posCartSubtotal,
                    value: money(plan.subtotalMinor),
                    valueKey: const Key('order-edit-subtotal'),
                  ),
                  if (plan.discountMinor > 0) ...[
                    const SizedBox(height: RestoflowSpacing.xs),
                    Text(
                      l10n.posOrderEditDiscountKept(
                        ltrIsolate(money(plan.discountMinor)),
                      ),
                      key: const Key('order-edit-discount-kept'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: kRestoflowInk2,
                      ),
                    ),
                  ],
                  if (plan.taxMinor > 0) ...[
                    const SizedBox(height: RestoflowSpacing.xs),
                    _EditAmountRow(
                      label: taxRateBp > 0
                          ? taxLineLabel(l10n, taxRateBp)
                          : l10n.posTaxLabel,
                      value: money(plan.taxMinor),
                      valueKey: const Key('order-edit-tax'),
                    ),
                  ],
                  const Divider(
                    height: 13,
                    thickness: 1,
                    color: kPosRowSeparator,
                  ),
                  Text(
                    totals,
                    key: const Key('order-edit-totals-change'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: kRestoflowInk,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            if (reason != null) ...[
              Row(
                key: const Key('order-edit-send-block'),
                children: [
                  Icon(
                    reason == OrderEditSendBlock.noChanges
                        ? Icons.info_outline
                        : Icons.warning_amber_rounded,
                    size: RestoflowIconSizes.sm,
                    color: reason == OrderEditSendBlock.noChanges
                        ? kRestoflowInk3
                        : warning.accent,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      orderEditSendBlockMessage(l10n, reason),
                      key: const Key('order-edit-send-block-text'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: reason == OrderEditSendBlock.noChanges
                            ? kRestoflowInk3
                            : warning.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (reasonAction != null) reasonAction,
                ],
              ),
              const SizedBox(height: RestoflowSpacing.xs),
            ],
            if (reasons case final chips?) ...[
              chips,
              const SizedBox(height: RestoflowSpacing.sm),
            ],
            FilledButton.icon(
              key: const Key('order-edit-send'),
              onPressed: onSend,
              icon: sending
                  ? RestoflowInlineSpinner(color: theme.colorScheme.primary)
                  : const Icon(Icons.send_rounded),
              label: Text(l10n.posOrderEditSendChanges),
              style: RestoflowButtonStyles.accent(context)
                  .merge(RestoflowButtonStyles.big(context))
                  .copyWith(
                    minimumSize: WidgetStateProperty.all(
                      const Size.fromHeight(kPosSendHeight),
                    ),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kPosSendRadius),
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditAmountRow extends StatelessWidget {
  const _EditAmountRow({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: kRestoflowInk2),
          ),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        // Standalone money: an LTR island, the string byte-identical.
        Text(
          value,
          key: valueKey,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFamily: kPosMoneyFontFamily,
            fontFamilyFallback: kPosMoneyFontFallbacks,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The finished-food confirm.
// ---------------------------------------------------------------------------

/// The ONE confirm before a send that takes food the kitchen already finished
/// (design §7.1 point 6): a Ready / Served KDS line removed, reduced, or
/// remade. Lists those lines and the old → new total. Resolves true only on
/// "Send changes"; dismissing sends nothing.
class OrderEditFinishedFoodSheet extends StatelessWidget {
  const OrderEditFinishedFoodSheet({
    required this.plan,
    required this.currencyCode,
    super.key,
  });

  final OrderEditPlan plan;
  final String currencyCode;

  static Future<bool> show(
    BuildContext context, {
    required OrderEditPlan plan,
    required String currencyCode,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          OrderEditFinishedFoodSheet(plan: plan, currencyCode: currencyCode),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String money(int minor) => MoneyFormatter.formatMinor(minor, currencyCode);
    return SafeArea(
      child: Padding(
        key: const Key('order-edit-finished-food-sheet'),
        padding: const EdgeInsets.fromLTRB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.posOrderEditAlreadyCookedTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            Text(l10n.posOrderEditAlreadyCookedBody),
            const SizedBox(height: RestoflowSpacing.md),
            for (final change in plan.finishedFoodChanges)
              Padding(
                padding: const EdgeInsets.only(bottom: RestoflowSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        change.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (change.source?.stage case final stage?) ...[
                      const SizedBox(width: RestoflowSpacing.sm),
                      OrderEditStageChip(stage: stage),
                    ],
                    const SizedBox(width: RestoflowSpacing.sm),
                    Text(
                      l10n.posCartQtyUnit(
                        _finishedDishes(change),
                        money(change.source?.configuredUnitMinor ?? 0),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: kRestoflowInk3,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: RestoflowSpacing.sm),
            Text(
              l10n.posOrderEditTotalsChange(
                ltrIsolate(money(plan.beforeGrandMinor)),
                ltrIsolate(money(plan.grandMinor)),
                ltrIsolate(
                  MoneyFormatter.formatSignedDeltaMinor(
                    plan.deltaMinor,
                    currencyCode,
                  ),
                ),
              ),
              key: const Key('order-edit-finished-food-totals'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('order-edit-finished-food-cancel'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.adminCancel),
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: FilledButton(
                    key: const Key('order-edit-finished-food-confirm'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(l10n.posOrderEditSendChanges),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The finished dishes a change takes: every dish of a removed line, the
  /// units a reduction drops, and the dishes a modify remakes.
  static int _finishedDishes(OrderEditPlannedChange c) => switch (c.kind) {
    OrderEditChangeKind.remove => c.quantityBefore,
    OrderEditChangeKind.reduce => c.quantityBefore - c.quantityAfter,
    _ => c.remakeDishes,
  };
}

// ---------------------------------------------------------------------------
// The cart-not-empty prompt.
// ---------------------------------------------------------------------------

/// What the cashier chose when "Edit order" met a cart holding other work.
enum OrderEditCartChoice { park, clear }

/// "Park or clear the current cart before editing this order." — instead of
/// a dead end (design §7.1 point 2). Null when the cashier cancels. Park is
/// offered only when the cart can be parked.
Future<OrderEditCartChoice?> showOrderEditCartNotEmptyPrompt(
  BuildContext context, {
  required bool canPark,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<OrderEditCartChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('order-edit-cart-prompt'),
      title: Text(l10n.posParkedActiveCartTitle),
      content: Text(l10n.posOrderEditCartNotEmptyBody),
      actions: [
        TextButton(
          key: const Key('order-edit-cart-prompt-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.adminCancel),
        ),
        TextButton(
          key: const Key('order-edit-cart-prompt-clear'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(OrderEditCartChoice.clear),
          child: Text(l10n.posClearCart),
        ),
        if (canPark)
          FilledButton(
            key: const Key('order-edit-cart-prompt-park'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(OrderEditCartChoice.park),
            child: Text(l10n.posOrderEditParkCurrentCart),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Result messages.
// ---------------------------------------------------------------------------

/// Shows what a send, retry or refresh came to: the result toast (with
/// "Refresh orders" when the applied edit still needs its authoritative
/// refresh — [onRefresh]; ORDER-EDIT-001F: with "Print again" when a paper
/// change slip did not reach the printer — [onPrintSlipAgain]), then, when
/// the payload told the server a pre-bill had been presented (D7), "Bill
/// changed: print new bill?" with [onPrintBill].
void showOrderEditResult(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  OrderEditResult result, {
  VoidCallback? onRefresh,
  VoidCallback? onPrintBill,
  VoidCallback? onPrintSlipAgain,
}) {
  final message = orderEditResultMessage(l10n, result);
  final applied = result.status == OrderEditSubmitStatus.applied;
  if (message != null) {
    messenger.showSnackBar(
      SnackBar(
        key: orderEditSlipNotPrinted(result)
            ? const Key('order-edit-slip-not-printed-toast')
            : null,
        content: Text(message),
        action: applied && result.refreshRequired && onRefresh != null
            ? SnackBarAction(label: l10n.posOrdersRefresh, onPressed: onRefresh)
            : orderEditSlipNotPrinted(result) && onPrintSlipAgain != null
            ? SnackBarAction(
                key: const Key('order-edit-slip-not-printed-print-again'),
                label: l10n.posOrderEditPrintAgain,
                onPressed: onPrintSlipAgain,
              )
            : null,
      ),
    );
  }
  if (applied && result.billPresented && onPrintBill != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.posOrderEditBillChanged),
        action: SnackBarAction(
          label: l10n.posPrintBillAction,
          onPressed: onPrintBill,
        ),
      ),
    );
  }
}

/// Reads the bill-presented instant for [orderId] from this session's print
/// jobs (D7). Here so the send path and its tests share one reading.
DateTime? orderEditBillPresentedAtFor(
  ProviderContainer container,
  String orderId,
) => orderEditBillPresentedAt(
  container
      .read(receiptPrintControllerProvider.notifier)
      .jobFor(orderEditBillJobKey(orderId)),
);
