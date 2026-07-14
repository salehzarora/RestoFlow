import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../data/outbox_repository.dart';
import '../format/money_format.dart';
import '../format/payment_method_label.dart';
import '../format/tax_math.dart';
import '../pos_palette.dart';
import '../state/cart_controller.dart';
import '../state/order_setup_controller.dart';
import '../state/outbox_controller.dart';
import '../state/pos_branch_tax.dart';
import '../state/pos_menu_provider.dart';
import '../state/recent_orders_controller.dart';
import '../state/pos_sync_scope_provider.dart';
import 'modifier_selection_sheet.dart';
import 'order_confirmation.dart';
import 'order_setup_section.dart';
import 'shift_context_bar.dart';

/// The live cart/order side panel (DESIGN-004): the shift-context bar over the
/// shared [CartPanelContent] (header + order setup + lines + Send footer, or the
/// in-place [OrderConfirmation] after submit). Used as the desktop/tablet side
/// cart; the phone slide-up sheet hosts the SAME [CartPanelContent].
///
/// Reads/mutates the in-memory [cartControllerProvider]. Chrome is localized;
/// item names are data; amounts are formatted integer minor-unit money.
class CartPanel extends StatelessWidget {
  const CartPanel({this.compact = false, super.key});

  /// A narrower side cart (tablet / compact-landscape) — tightens paddings.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: BorderDirectional(start: BorderSide(color: kRestoflowHairline)),
      ),
      child: Column(
        children: [
          const ShiftContextBar(),
          const Divider(height: 1),
          Expanded(child: CartPanelContent(compact: compact)),
        ],
      ),
    );
  }
}

/// The shared cart content (DESIGN-004): everything below the shift bar. Reads
/// the same providers whether it is embedded in the [CartPanel] side panel or
/// the phone slide-up sheet — no cart logic is duplicated.
class CartPanelContent extends ConsumerStatefulWidget {
  const CartPanelContent({
    this.isSheet = false,
    this.compact = false,
    this.onClose,
    super.key,
  });

  /// Rendered inside the phone slide-up sheet: adds a drag handle + close row.
  final bool isSheet;

  /// Narrower placement — tightens horizontal paddings.
  final bool compact;

  /// The sheet's close callback (dismiss); null hides the close affordance.
  final VoidCallback? onClose;

  @override
  ConsumerState<CartPanelContent> createState() => _CartPanelContentState();
}

class _CartPanelContentState extends ConsumerState<CartPanelContent> {
  // POS-SUBMIT-GUARD-001: true while an order submit is in flight (the enqueue
  // and, in real mode, the awaited sync_push round-trip). While set, the Send
  // button is disabled AND shows an inline spinner, so a double-tap on slow
  // Wi-Fi cannot enqueue a SECOND order — each submit mints fresh
  // order/operation UUIDs that server idempotency (D-022) cannot dedupe.
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cart = ref.watch(cartControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);
    final setup = ref.watch(orderSetupControllerProvider);
    final setupController = ref.read(orderSetupControllerProvider.notifier);
    // TABLET-UX-001 (A): the ACTIVE menu resolves the item + its modifier groups
    // when the cashier edits a cart line. Null (still loading) falls back to a
    // note-only edit built from the line itself.
    final menu = ref.watch(posMenuProvider).valueOrNull;
    // TABLET-UX-001 (B): the side cart (two-pane tablet/landscape) uses compact,
    // denser line rows so more of the order is visible at once; the phone
    // slide-up sheet keeps its roomier rows.
    final dense = !widget.isSheet;

    final submittedOrder = cart.submittedOrder;
    final Widget body;
    if (submittedOrder != null) {
      body = OrderConfirmation(
        key: const ValueKey('order-confirmation-view'),
        order: submittedOrder,
        onNewOrder: () {
          controller.startNewOrder();
          setupController.reset();
        },
      );
    } else {
      final canSend = !cart.isEmpty && setup.isReadyToSubmit && !_submitting;
      final pendingSync = ref
          .watch(outboxControllerProvider)
          .where((e) => e.syncState.isPending)
          .length;

      // RF-117: the branch tax setting (default OFF). When it adds tax we show a
      // Tax line + grand total in the footer and thread the integer tax into the
      // submitted order. Exclusive mode, integer minor units, no float.
      final tax =
          ref.watch(posBranchTaxProvider).valueOrNull ?? BranchTax.disabled;
      final taxMinor = tax.addsTax
          ? taxMinorExclusive(cart.subtotalMinor, tax.rateBp)
          : 0;

      body = Material(
        key: const ValueKey('cart-view'),
        color: Colors.white,
        child: Column(
          children: [
            _CartHeader(
              l10n: l10n,
              itemCount: cart.itemCount,
              pendingSync: pendingSync,
              onClear: cart.isEmpty ? null : controller.clear,
            ),
            const Divider(height: 1),
            const OrderSetupSection(),
            const Divider(height: 1),
            Expanded(
              child: cart.isEmpty
                  ? _EmptyCart(message: l10n.posCartEmpty)
                  : ListView.separated(
                      padding: EdgeInsets.symmetric(
                        vertical: dense
                            ? RestoflowSpacing.xs
                            : RestoflowSpacing.sm,
                        horizontal: RestoflowSpacing.sm,
                      ),
                      itemCount: cart.lines.length,
                      separatorBuilder: (_, _) => SizedBox(
                        height: dense
                            ? RestoflowSpacing.xs
                            : RestoflowSpacing.sm,
                      ),
                      itemBuilder: (context, index) {
                        final line = cart.lines[index];
                        return _CartLineTile(
                          line: line,
                          l10n: l10n,
                          dense: dense,
                          onIncrease: () =>
                              controller.increaseQuantity(line.lineId),
                          onDecrease: () =>
                              controller.decreaseQuantity(line.lineId),
                          onRemove: () => controller.removeLine(line.lineId),
                          onEdit: () =>
                              _editLine(context, menu, line, controller),
                        );
                      },
                    ),
            ),
            _CartFooter(
              l10n: l10n,
              subtotalMinor: cart.subtotalMinor,
              taxMinor: taxMinor,
              taxRateBp: taxMinor > 0 ? tax.rateBp : 0,
              currencyCode: cart.currencyCode,
              orderType: setup.orderType,
              tableLabel: setup.assignedTable?.label,
              showNeedsTableHint: cart.isNotEmpty && setup.needsTableWarning,
              // POS-SUBMIT-GUARD-001: the spinner + disabled state while a submit
              // is in flight.
              submitting: _submitting,
              onSend: canSend
                  ? () => _handleSend(
                      cart: cart,
                      setup: setup,
                      cartController: controller,
                      setupController: setupController,
                      l10n: l10n,
                      taxTotalMinor: taxMinor,
                      taxRateBp: taxMinor > 0 ? tax.rateBp : 0,
                    )
                  : null,
            ),
          ],
        ),
      );
    }

    // RF-141D: a short, subtle fade softens the cart <-> confirmation swap.
    final swapped = AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: body,
    );

    if (!widget.isSheet) return swapped;
    return Column(
      children: [
        _SheetGrip(l10n: l10n, onClose: widget.onClose),
        Expanded(child: swapped),
      ],
    );
  }

  /// POS-SUBMIT-GUARD-001: the guarded Send handler. A second tap while a submit
  /// is already running is ignored two ways — the `_submitting` re-entry gate
  /// below and the disabled Send button (`canSend` clears while submitting) — so
  /// no duplicate order can be enqueued. The spinner stays until the enqueue
  /// (and, in real mode, the push) settles, then Send re-enables only if the
  /// submit failed and left the cart intact.
  Future<void> _handleSend({
    required CartViewState cart,
    required OrderSetupState setup,
    required CartController cartController,
    required OrderSetupController setupController,
    required AppLocalizations l10n,
    required int taxTotalMinor,
    required int taxRateBp,
  }) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await _submitOrder(
        ref: ref,
        context: context,
        cart: cart,
        setup: setup,
        cartController: cartController,
        setupController: setupController,
        l10n: l10n,
        taxTotalMinor: taxTotalMinor,
        taxRateBp: taxRateBp,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

/// The phone sheet's drag handle + close row (DESIGN-004 §6.8).
class _SheetGrip extends StatelessWidget {
  const _SheetGrip({required this.l10n, required this.onClose});

  final AppLocalizations l10n;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: kRestoflowHairline,
              borderRadius: BorderRadius.circular(RestoflowRadii.pill),
            ),
          ),
          if (onClose != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                key: const Key('cart-sheet-close'),
                onPressed: onClose,
                icon: const Icon(Icons.close),
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ),
        ],
      ),
    );
  }
}

/// RF-115 Send Order: enqueue the order to the client outbox FIRST, and only on
/// a successful enqueue materialize the confirmation + clear the cart + reset the
/// order setup. If the enqueue fails the cart is left intact and a message is
/// shown — the order is never silently lost.
Future<void> _submitOrder({
  required WidgetRef ref,
  required BuildContext context,
  required CartViewState cart,
  required OrderSetupState setup,
  required CartController cartController,
  required OrderSetupController setupController,
  required AppLocalizations l10n,
  int taxTotalMinor = 0,
  int taxRateBp = 0,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final outbox = ref.read(outboxControllerProvider.notifier);
  // The scope this order is being submitted IN — captured before the await, the same
  // guard payCash carries. If the till is re-paired while the push is in flight, the
  // order is real and queued, but its local recent-orders record belongs to the
  // branch that took it, not to whichever branch the till lands in next.
  final scopeKey = ref.read(posSyncScopeProvider)?.key;
  try {
    final result = await outbox.submit(
      lines: cart.lines,
      subtotalMinor: cart.subtotalMinor,
      currencyCode: cart.currencyCode,
      orderType: setup.orderType,
      tableId: setup.assignedTable?.tableId,
      tableLabel: setup.assignedTable?.label,
      taxTotalMinor: taxTotalMinor,
      // ORDER-CUSTOMER-001: the optional customer name (null when not entered).
      customerName: setup.customerName,
    );
    cartController.submitOrder(
      orderType: setup.orderType,
      tableLabel: setup.assignedTable?.label,
      customerName: setup.customerName,
      orderNumber: result.orderNumber,
      outboxEntryId: result.entry.id,
      localOperationId: result.entry.localOperationId,
      orderId: result.entry.targetId,
      taxTotalMinor: taxTotalMinor,
      taxRateBp: taxRateBp,
    );
    // POS-ORDERS-AND-PAYMENT-001: record the just-submitted order in the local
    // recent/unpaid-orders list (UNPAID — no payment yet). Best-effort: this
    // never affects the submit/outbox result above.
    //
    // ONLY under the scope it was submitted in. A scope that moved mid-flight means
    // this record belongs to the previous branch's bucket, which is no longer ours
    // to write — that branch re-discovers the order from its own feed.
    final submitted = ref.read(cartControllerProvider).submittedOrder;
    if (submitted != null && ref.read(posSyncScopeProvider)?.key == scopeKey) {
      ref
          .read(posRecentOrdersControllerProvider.notifier)
          .recordSubmitted(submitted);
    }
    setupController.reset();
  } on OrderSubmissionException {
    messenger.showSnackBar(SnackBar(content: Text(l10n.posSubmitFailed)));
  }
}

/// TABLET-UX-001 (A): opens the SAME customization sheet used when adding an
/// item, prefilled with [line]'s current modifiers + note, to EDIT it in place.
/// Saving calls [CartController.updateLineModifiers] — it replaces the existing
/// line (never a duplicate) and the total recomputes through the live cart
/// pricing. Cancel (dismiss) leaves the cart unchanged. The item + its groups
/// come from the ACTIVE [menu]; if unavailable, a note-only edit is built from
/// the cart line so the action still works.
void _editLine(
  BuildContext context,
  PosMenuData? menu,
  CartLineView line,
  CartController controller,
) {
  DemoMenuItem? item;
  var groups = const <PosModifierGroup>[];
  DemoCategory? category;
  var currency = line.currencyCode;
  if (menu != null) {
    for (final candidate in menu.items) {
      if (candidate.id == line.menuItemId) {
        item = candidate;
        break;
      }
    }
    if (item != null) {
      groups = menu.groupsForItem(item.id);
      category = menu.categoryOf(item.categoryId);
      currency = menu.currencyCode;
    }
  }
  // Fallback item from the cart line (menu still loading / item not found):
  // the sheet then edits the note only, never inventing a price.
  item ??= DemoMenuItem(
    id: line.menuItemId,
    name: line.name,
    priceMinor: line.unitPriceMinor,
    categoryId: '',
    categoryName: '',
  );
  ModifierSelectionSheet.show(
    context,
    item: item,
    groups: groups,
    currencyCode: currency,
    category: category,
    initialSelections: line.modifiers,
    initialNote: line.note,
    isEdit: true,
    onConfirm: (selections, note) =>
        controller.updateLineModifiers(line.lineId, selections, note: note),
  );
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({
    required this.l10n,
    required this.itemCount,
    required this.pendingSync,
    required this.onClear,
  });

  final AppLocalizations l10n;
  final int itemCount;
  final int pendingSync;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.shopping_cart_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: RestoflowSpacing.sm),
          Flexible(
            child: Text(
              l10n.posCartTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: kRestoflowInk,
              ),
            ),
          ),
          if (itemCount > 0) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.sm,
                vertical: RestoflowSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(RestoflowRadii.pill),
              ),
              child: Text(
                itemCount.toString(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (pendingSync > 0) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            _PendingSyncChip(
              count: pendingSync,
              tooltip: l10n.posSyncPendingCount(pendingSync),
            ),
          ],
          const Spacer(),
          if (onClear != null)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text(l10n.posClearCart),
            ),
        ],
      ),
    );
  }
}

/// A compact pending-sync indicator in the cart header (RF-115).
class _PendingSyncChip extends StatelessWidget {
  const _PendingSyncChip({required this.count, required this.tooltip});

  final int count;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: RestoflowStatusPill(
        label: count.toString(),
        tone: RestoflowTone.warning,
        icon: Icons.cloud_queue,
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // The shared state view (l10n message rendered verbatim — tests find it by
    // text).
    return RestoflowStateView(
      icon: Icons.remove_shopping_cart_outlined,
      title: message,
    );
  }
}

/// A warm inner-surface line card (DESIGN-004 §6.5).
///
/// TABLET-UX-001: an Edit action reopens the customization sheet prefilled with
/// this line's modifiers/note (Part A), and a [dense] variant (Part B) packs the
/// meta + controls onto fewer rows so more of the order fits in the landscape
/// side cart. The item name stays a standalone exact-match Text, and the
/// '× qty · unit' composite keeps its OWN Text (frozen widget-test contracts).
class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.l10n,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onEdit,
    this.dense = false,
  });

  final CartLineView line;
  final AppLocalizations l10n;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  /// TABLET-UX-001 (B): tighter paddings + the '× qty · unit' meta folded into
  /// the controls row, so the landscape side cart shows several lines at once.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitPriceText = MoneyFormatter.format(line.unitPrice);
    final lineTotalText = MoneyFormatter.format(line.lineTotal);

    // '× qty · unit price' — its OWN Text (the name stays an exact-match
    // standalone string per the test contract). In dense mode it rides the
    // controls row; otherwise it keeps its own line under the name.
    final qtyUnit = Text(
      l10n.posCartQtyUnit(line.quantity, unitPriceText),
      style: theme.textTheme.bodySmall?.copyWith(
        color: kRestoflowInk3,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return Container(
      decoration: BoxDecoration(
        color: kPosInnerSurface,
        borderRadius: BorderRadius.circular(RestoflowRadii.md + 2),
        border: Border.all(color: kRestoflowHairline),
      ),
      padding: dense
          ? const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.sm,
              RestoflowSpacing.xs,
              RestoflowSpacing.xs,
              RestoflowSpacing.xs,
            )
          : const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.md,
              RestoflowSpacing.sm,
              RestoflowSpacing.sm,
              RestoflowSpacing.sm,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: kRestoflowInk,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Text(
                lineTotalText,
                textAlign: TextAlign.end,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: kRestoflowInk,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          // Roomy: the meta on its own line. Dense: folded into the controls row.
          if (!dense) qtyUnit,
          // Selected modifiers (order-time snapshots) as compact sub-lines.
          for (final modifier in line.modifiers)
            Row(
              children: [
                Flexible(
                  child: Text(
                    '+ ${modifier.displayName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: kRestoflowInk2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (modifier.totalDeltaMinor != 0) ...[
                  const SizedBox(width: RestoflowSpacing.xs),
                  Text(
                    MoneyFormatter.formatSignedDeltaMinor(
                      modifier.totalDeltaMinor,
                      line.currencyCode,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: kRestoflowInk2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          if (line.note != null)
            Text(
              '${l10n.posItemNoteLabel}: ${line.note}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: kRestoflowInk2,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          SizedBox(height: dense ? RestoflowSpacing.xxs : RestoflowSpacing.xs),
          Row(
            children: [
              _QuantityStepper(
                quantity: line.quantity,
                l10n: l10n,
                dense: dense,
                onIncrease: onIncrease,
                onDecrease: onDecrease,
              ),
              // Dense folds the '× qty · unit' meta into this row (Expanded so
              // it uses all free width and ellipsises only when truly cramped);
              // roomy keeps it on its own line above and just spaces the actions.
              if (dense) ...[
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(child: qtyUnit),
              ] else
                const Spacer(),
              _LineActionButton(
                buttonKey: Key('cart-edit-${line.lineId}'),
                icon: Icons.edit_outlined,
                tooltip: l10n.posCartEditItem,
                color: theme.colorScheme.primary,
                dense: dense,
                onPressed: onEdit,
              ),
              _LineActionButton(
                buttonKey: Key('cart-remove-${line.lineId}'),
                icon: Icons.delete_outline,
                tooltip: l10n.posRemoveItem,
                color: RestoflowTone.danger.styleOf(theme).accent,
                dense: dense,
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact >=40/44dp cart-line action (edit / remove). Dense trims the tap
/// target to 40dp so the controls row stays tidy in the narrow side cart.
class _LineActionButton extends StatelessWidget {
  const _LineActionButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.dense = false,
  });

  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final side = dense ? 40.0 : 44.0;
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      icon: Icon(icon, size: RestoflowIconSizes.md),
      tooltip: tooltip,
      color: color,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints(minWidth: side, minHeight: side),
      padding: EdgeInsets.zero,
    );
  }
}

/// A minus (white/hairline) + qty + plus (filled green) stepper (DESIGN-004).
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.l10n,
    required this.onIncrease,
    required this.onDecrease,
    this.dense = false,
  });

  final int quantity;
  final AppLocalizations l10n;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          tooltip: l10n.posDecreaseQuantity,
          filled: false,
          dense: dense,
          onPressed: onDecrease,
        ),
        SizedBox(
          width: dense ? 30 : 40,
          child: Text(
            quantity.toString(),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: kRestoflowInk,
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          tooltip: l10n.posIncreaseQuantity,
          filled: true,
          dense: dense,
          onPressed: onIncrease,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.filled,
    required this.onPressed,
    this.dense = false,
  });

  final IconData icon;
  final String tooltip;
  final bool filled;
  final VoidCallback onPressed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A control inside a >=40/44dp tap target (fast, gloved cashier fingers);
    // dense trims it a touch so the landscape side cart packs more lines.
    final tap = dense ? 40.0 : 44.0;
    final inner = dense ? 34.0 : 38.0;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: dense ? 24 : 26,
        child: Container(
          width: tap,
          height: tap,
          alignment: Alignment.center,
          child: Container(
            width: inner,
            height: inner,
            decoration: BoxDecoration(
              color: filled ? theme.colorScheme.primary : Colors.white,
              borderRadius: BorderRadius.circular(RestoflowRadii.sm + 2),
              border: filled ? null : Border.all(color: kRestoflowHairline),
            ),
            child: Icon(
              icon,
              size: RestoflowIconSizes.md,
              color: filled ? theme.colorScheme.onPrimary : kRestoflowInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// The active order's service-mode summary shown right above Send (RF-114).
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.l10n,
    required this.orderType,
    required this.tableLabel,
  });

  final AppLocalizations l10n;
  final OrderType orderType;
  final String? tableLabel;

  @override
  Widget build(BuildContext context) {
    final dineIn = orderType == OrderType.dineIn;
    final typeLabel = dineIn
        ? l10n.posOrderTypeDineIn
        : l10n.posOrderTypeTakeaway;
    final tableChipLabel = tableLabel == null
        ? null
        : '${l10n.posTableLabel} $tableLabel';

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: RestoflowSpacing.sm,
        runSpacing: RestoflowSpacing.xs,
        children: [
          RestoflowStatusPill(
            key: const Key('summary-order-type'),
            icon: dineIn ? Icons.restaurant : Icons.takeout_dining,
            label: typeLabel,
          ),
          if (tableChipLabel != null)
            RestoflowStatusPill(
              key: const Key('summary-table'),
              icon: Icons.event_seat,
              label: tableChipLabel,
            ),
        ],
      ),
    );
  }
}

class _CartFooter extends StatelessWidget {
  const _CartFooter({
    required this.l10n,
    required this.subtotalMinor,
    required this.taxMinor,
    required this.taxRateBp,
    required this.currencyCode,
    required this.orderType,
    required this.tableLabel,
    required this.onSend,
    this.showNeedsTableHint = false,
    this.submitting = false,
  });

  final AppLocalizations l10n;
  final int subtotalMinor;
  final int taxMinor;
  final int taxRateBp;
  final String currencyCode;
  final OrderType orderType;
  final String? tableLabel;
  final VoidCallback? onSend;
  final bool showNeedsTableHint;

  /// POS-SUBMIT-GUARD-001: a submit is in flight — swap the Send icon for an
  /// inline spinner (the button is also disabled via a null [onSend]).
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: BorderDirectional(top: BorderSide(color: kRestoflowHairline)),
      ),
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SelectionSummary(
              l10n: l10n,
              orderType: orderType,
              tableLabel: tableLabel,
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            if (taxMinor > 0) ...[
              _SummaryRow(
                label: l10n.posCartSubtotal,
                value: MoneyFormatter.formatMinor(subtotalMinor, currencyCode),
                valueKey: const Key('cart-subtotal'),
              ),
              const SizedBox(height: RestoflowSpacing.xs),
              _SummaryRow(
                label: taxLineLabel(l10n, taxRateBp),
                value: MoneyFormatter.formatMinor(taxMinor, currencyCode),
                valueKey: const Key('cart-tax'),
              ),
              const SizedBox(height: RestoflowSpacing.xs),
              _TotalRow(
                label: l10n.posGrandTotal,
                value: MoneyFormatter.formatMinor(
                  subtotalMinor + taxMinor,
                  currencyCode,
                ),
                valueKey: const Key('cart-grand-total'),
              ),
            ] else
              _TotalRow(
                label: l10n.posCartSubtotal,
                value: MoneyFormatter.formatMinor(subtotalMinor, currencyCode),
                valueKey: const Key('cart-subtotal'),
              ),
            const SizedBox(height: RestoflowSpacing.sm),
            if (showNeedsTableHint) ...[
              Row(
                key: const Key('send-needs-table-hint'),
                children: [
                  Icon(
                    Icons.event_seat,
                    size: RestoflowIconSizes.sm,
                    color: RestoflowTone.warning.styleOf(theme).accent,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.posSendNeedsTableHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: RestoflowTone.warning.styleOf(theme).accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.xs),
            ],
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: onSend == null ? null : kPosGreenGlow,
                ),
                child: FilledButton.icon(
                  onPressed: onSend,
                  // POS-SUBMIT-GUARD-001: an explicit primary-tinted spinner (the
                  // disabled foreground would otherwise wash it out) marks the
                  // in-flight submit until the confirmation replaces the cart.
                  icon: submitting
                      ? RestoflowInlineSpinner(color: theme.colorScheme.primary)
                      : const Icon(Icons.send),
                  label: Text(l10n.posSendOrder),
                  style: RestoflowButtonStyles.big(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The loud subtotal / grand-total row: a big brand-green figure the cashier
/// reads aloud. The label flexes + ellipsises so a narrow (compact-landscape)
/// side cart never overflows.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Text(
          value,
          key: valueKey,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

/// A compact label/value summary row for the cart footer breakdown (RF-117).
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: kRestoflowInk2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Text(
          value,
          key: valueKey,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
