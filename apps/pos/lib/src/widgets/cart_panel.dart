import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../data/demo_tables.dart';
import '../data/outbox_repository.dart';
import '../format/money_format.dart';
import '../format/payment_method_label.dart';
import '../format/tax_math.dart';
import '../pos_palette.dart';
import '../state/addition_controller.dart';
import '../state/cart_controller.dart';
import '../state/draft_recovery_controller.dart';
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
      // PSC-001C: ADDITION MODE — the cart's lines are a pending addition to
      // an EXISTING order. The parent already owns its type/table, so the
      // order-setup gate does not apply; the banner below names the target.
      final addition = ref.watch(additionControllerProvider);
      // Finding 4: while APPLIED-AWAITING-REFRESH the send button stays off —
      // the operation must never be dispatched again; the banner offers the
      // refresh retry instead.
      final canSend =
          !cart.isEmpty &&
          (addition.active || setup.isReadyToSubmit) &&
          !_submitting &&
          !addition.sending &&
          !addition.awaitingRefresh;
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
              // Cart-safety: a frozen addition attempt owns the cart — the
              // Clear control is disabled (the controller refuses regardless).
              onClear: cart.isEmpty || cart.lockedByAddition
                  ? null
                  : controller.clear,
            ),
            const Divider(height: 1),
            // PSC-001C: while ADDING to an existing order the setup section
            // (type/table) is replaced by the target banner — the parent
            // order's context is fixed and must stay visible.
            if (addition.active)
              _AdditionBanner(
                l10n: l10n,
                orderCode: addition.target!.orderCode,
                tableLabel: addition.target!.tableLabel,
                failed: addition.failed,
                awaitingRefresh: addition.awaitingRefresh,
                // Finding 2: cancel is DISABLED while the attempt is on the
                // wire or applied-awaiting-refresh — the controller refuses
                // it anyway (defense in depth); the banner is honest about it.
                canCancel: addition.canCancel,
                onCancel: () =>
                    ref.read(additionControllerProvider.notifier).exit(),
                // Finding 4: the ONLY retry offered after applied is the
                // authoritative refresh — never a second dispatch.
                onRetryRefresh: () => ref
                    .read(additionControllerProvider.notifier)
                    .retryRefresh(),
              )
            else
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
                        // Cart-safety: while a frozen addition attempt owns
                        // the cart, every line control is disabled — the
                        // visible lines ARE the frozen payload.
                        final locked = cart.lockedByAddition;
                        return _CartLineTile(
                          line: line,
                          l10n: l10n,
                          dense: dense,
                          onIncrease: locked
                              ? null
                              : () => controller.increaseQuantity(line.lineId),
                          onDecrease: locked
                              ? null
                              : () => controller.decreaseQuantity(line.lineId),
                          onRemove: locked
                              ? null
                              : () => controller.removeLine(line.lineId),
                          onEdit: locked
                              ? null
                              : () =>
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
              showNeedsTableHint:
                  cart.isNotEmpty &&
                  setup.needsTableWarning &&
                  !addition.active,
              sendLabelOverride: addition.active
                  ? l10n.posSubmitAddition
                  : null,
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
      await submitOrderFromCart(
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
///
/// PUBLIC (visible for testing): this is the Send button's handler, and the
/// delayed-result scope race it guards can only be proven by driving THIS seam.
@visibleForTesting
Future<void> submitOrderFromCart({
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
  // PSC-001C: ADDITION MODE routes the SAME send action to one
  // `order.items_add` operation for the target order — the original items are
  // never re-sent, a failure keeps the pending lines local + retryable, and
  // the cart clears only after the server applied the addition (inside the
  // controller, together with the authoritative refresh).
  final additionState = ref.read(additionControllerProvider);
  if (additionState.active) {
    final result = await ref.read(additionControllerProvider.notifier).submit();
    // Finding 4: applied-but-not-refreshed is its own honest message — the
    // addition IS saved; only the authoritative view still needs a reload.
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.applied
              ? (result.refreshRequired
                    ? l10n.posAdditionSavedRefreshNeeded
                    : l10n.posAdditionApplied)
              : l10n.posAdditionFailedRetry,
        ),
      ),
    );
    return;
  }
  final outbox = ref.read(outboxControllerProvider.notifier);
  // Captured BEFORE the await: the widget's ref dies with the tree (an unpair
  // unmounts the POS), but the container and the notifiers it owns do not.
  final container = ProviderScope.containerOf(context, listen: false);
  // PILOT-OPERATIONS-CORRECTIONS-001 (Finding 1A): the COMPLETE submit-attempt identity,
  // captured BEFORE the first await. The FULL operational binding — org/restaurant/branch/
  // device scope AND the PIN session — not the scope alone, plus the exact draft, order
  // type, table, and customer name being submitted. A PIN handover on the SAME till keeps
  // the scope but changes the binding; the old scope-only guard missed it and applied
  // employee A's delayed result under employee B. The container and the notifiers it owns
  // outlive the widget's ref, so the result is resolved against the container.
  final bindingBefore = container.read(posRecoveryBindingProvider);
  final scopeKeyBefore = container.read(posSyncScopeProvider)?.key;
  final draftBefore = cartController.captureDraft();
  final orderTypeBefore = setup.orderType;
  final tableBefore = setup.assignedTable;
  final customerNameBefore = setup.customerName;
  try {
    final result = await outbox.submit(
      lines: cart.lines,
      subtotalMinor: cart.subtotalMinor,
      currencyCode: cart.currencyCode,
      orderType: orderTypeBefore,
      tableId: tableBefore?.tableId,
      tableLabel: tableBefore?.label,
      taxTotalMinor: taxTotalMinor,
      // ORDER-CUSTOMER-001: the optional customer name (null when not entered).
      customerName: customerNameBefore,
    );
    // Finding 1B — THE FULL-IDENTITY MUTATION BOUNDARY. Everything below this line mutates
    // state the CURRENT session would see — the cart's submitted-order view, the
    // confirmation screen, the order-setup reset, the recent-orders row, the recovery
    // binding. If the BINDING changed while the submit was in flight — a PIN handover
    // (same till, new employee) OR a re-pair — NONE of it may run for the current session:
    // do NOT clear its cart / setup / customer name, do NOT show a confirmation, do NOT
    // navigate, do NOT apply the result to its UI, do NOT attach recovery to its binding.
    // The departed session's result is handled separately and is never fabricated or
    // rolled back — the outbox entry is durable, and the original session re-discovers an
    // accepted order through its own authoritative window pull.
    if (container.read(posRecoveryBindingProvider) != bindingBefore) {
      _retainDepartedSessionResult(
        container: container,
        cartController: cartController,
        result: result,
        scopeKeyBefore: scopeKeyBefore,
        bindingBefore: bindingBefore,
        draft: draftBefore,
        orderType: orderTypeBefore,
        table: tableBefore,
        customerName: customerNameBefore,
        taxTotalMinor: taxTotalMinor,
        taxRateBp: taxRateBp,
      );
      return; // Finding 1C: never a generic current-cart clear after a session switch.
    }

    // SAME SESSION. PILOT-OPERATIONS-CORRECTIONS-001: capture the draft (taken BEFORE the
    // await, keyed to THIS submit's outbox entry) bound to THE SUBMITTING session's exact
    // binding. If the server permanently rejects it (item_unavailable), the confirmation
    // offers "Back to cart" to restore this exact draft; an accepted order clears it.
    container
        .read(posDraftRecoveryProvider.notifier)
        .capture(
          PosDraftRecovery(
            draft: draftBefore,
            orderType: orderTypeBefore,
            table: tableBefore,
            customerName: customerNameBefore,
            outboxEntryId: result.entry.id,
            // A2: bind to THIS exact context (scope + PIN session) so a later employee /
            // branch / device can never see or restore this draft.
            binding: bindingBefore,
          ),
        );

    cartController.submitOrder(
      orderType: orderTypeBefore,
      tableLabel: tableBefore?.label,
      customerName: customerNameBefore,
      orderNumber: result.orderNumber,
      outboxEntryId: result.entry.id,
      localOperationId: result.entry.localOperationId,
      orderId: result.entry.targetId,
      taxTotalMinor: taxTotalMinor,
      taxRateBp: taxRateBp,
    );
    // POS-ORDERS-AND-PAYMENT-001: record the just-submitted order in the local
    // recent/unpaid-orders list (UNPAID — no payment yet). Best-effort: this
    // never affects the submit/outbox result above. Scope-safe by the boundary
    // guard above; read through the container so a mid-flight unmount cannot
    // throw ref-after-dispose.
    final submitted = container.read(cartControllerProvider).submittedOrder;
    if (submitted != null) {
      final recent = container.read(posRecentOrdersControllerProvider.notifier);
      recent.recordSubmitted(submitted);
      // PILOT-OPERATIONS-CORRECTIONS-001 (A3): in REAL mode the submit auto-pushed
      // INSIDE outbox.submit, so a permanent rejection (item_unavailable) may have
      // ALREADY landed before this row was recorded. If so, retire it to a
      // non-actionable rejected shell immediately — a locally-generated order id is
      // never proof the server accepted it.
      final entry = container
          .read(outboxControllerProvider.notifier)
          .entryById(result.entry.id);
      if (entry != null && entry.isPermanentBusinessRejection) {
        recent.markLocallyRejected(submitted.identity);
      }
    }
    setupController.reset();
  } on OrderSubmissionException {
    // A failure that belongs to a session we have LEFT is not this session's failure;
    // showing it here would blame the new employee/branch for the old one's submit.
    if (container.read(posRecoveryBindingProvider) != bindingBefore) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.posSubmitFailed)));
  }
}

/// PILOT-OPERATIONS-CORRECTIONS-001 (Finding 1B/1C): a submit RESULT that returned AFTER
/// the submitting session departed — a PIN handover (same till, new employee) or a re-pair
/// — belongs to the ORIGINAL session, never to whoever holds the till now. This NEVER
/// touches the current session's cart, setup, or confirmation.
///
/// It retains the departed session's recovery under ITS ORIGINAL [bindingBefore] +
/// outbox identity, so the draft is inaccessible to the current operator (binding
/// mismatch) yet recoverable when its owner returns. `capture` no-ops when the order
/// already applied (accepted → nothing to recover); an accepted order's recovery is
/// additionally cleared by the controller-seam acceptance listeners.
///
/// Only when the till is still in the SAME operational scope (a PIN handover, so the
/// scope-keyed recent-orders list is SHARED with the original session) does it record the
/// departed order's row — built from the captured draft WITHOUT mutating the live cart —
/// so its owner finds it on return; a permanent rejection is retired to a non-actionable
/// shell now. A scope CHANGE (re-pair) means a different branch's list, so recording is
/// skipped to avoid leaking the order across branches — the original scope re-discovers an
/// accepted order through its own authoritative window pull.
void _retainDepartedSessionResult({
  required ProviderContainer container,
  required CartController cartController,
  required OrderSubmitResult result,
  required String? scopeKeyBefore,
  required PosRecoveryBinding bindingBefore,
  required CartDraftSnapshot draft,
  required OrderType orderType,
  required DemoTable? table,
  required String? customerName,
  required int taxTotalMinor,
  required int taxRateBp,
}) {
  container
      .read(posDraftRecoveryProvider.notifier)
      .capture(
        PosDraftRecovery(
          draft: draft,
          orderType: orderType,
          table: table,
          customerName: customerName,
          outboxEntryId: result.entry.id,
          binding:
              bindingBefore, // the ORIGINAL session's binding, never the current one
        ),
      );

  // A scope change means the recent-orders list is a DIFFERENT branch's world — recording
  // would leak the order across branches. Retain only the (scope-independent) recovery.
  if (container.read(posSyncScopeProvider)?.key != scopeKeyBefore) return;

  final recent = container.read(posRecentOrdersControllerProvider.notifier);
  final view = cartController.viewFromDraft(
    draft: draft,
    orderType: orderType,
    tableLabel: table?.label,
    customerName: customerName,
    orderNumber: result.orderNumber,
    outboxEntryId: result.entry.id,
    localOperationId: result.entry.localOperationId,
    orderId: result.entry.targetId,
    taxTotalMinor: taxTotalMinor,
    taxRateBp: taxRateBp,
  );
  recent.recordSubmitted(view);
  final entry = container
      .read(outboxControllerProvider.notifier)
      .entryById(result.entry.id);
  if (entry != null && entry.isPermanentBusinessRejection) {
    recent.markLocallyRejected(view.identity);
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

  /// Null = the control is DISABLED (cart-safety: a frozen addition attempt
  /// owns the cart and the visible lines are its immutable payload).
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;

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
  final VoidCallback? onPressed;
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
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;
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
  final VoidCallback? onPressed;
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
        child: Opacity(
          // A disabled stepper must LOOK disabled, not just refuse the tap.
          opacity: onPressed == null ? 0.4 : 1.0,
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

/// PSC-001C: the ADDITION-MODE banner — names the order being extended (and
/// its table), surfaces an honest retryable failure line, and offers Cancel
/// (which leaves the pending lines in the cart; discarding work is the
/// cashier's explicit choice via the cart's own Clear).
///
/// Correction pass: Cancel is DISABLED while it cannot actually happen
/// (sending / applied-awaiting-refresh — Finding 2), and the applied-but-not-
/// refreshed state shows its own honest line with a REFRESH retry instead of
/// Cancel (Finding 4 — the addition is saved; only the view needs a reload).
class _AdditionBanner extends StatelessWidget {
  const _AdditionBanner({
    required this.l10n,
    required this.orderCode,
    required this.tableLabel,
    required this.failed,
    required this.awaitingRefresh,
    required this.canCancel,
    required this.onCancel,
    required this.onRetryRefresh,
  });

  final AppLocalizations l10n;
  final String orderCode;
  final String? tableLabel;
  final bool failed;
  final bool awaitingRefresh;
  final bool canCancel;
  final VoidCallback onCancel;
  final VoidCallback onRetryRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = failed
        ? RestoflowTone.danger
        : awaitingRefresh
        ? RestoflowTone.warning
        : RestoflowTone.info;
    final style = tone.styleOf(theme);
    final table = tableLabel;
    return Container(
      key: const Key('pos-addition-banner'),
      width: double.infinity,
      color: style.container,
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.playlist_add, size: 18, color: style.accent),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              failed
                  ? l10n.posAdditionFailedRetry
                  : awaitingRefresh
                  ? l10n.posAdditionSavedRefreshNeeded
                  : table != null
                  ? '${l10n.posAddingToOrderBanner(orderCode)} · ${l10n.posTableLabel} $table'
                  : l10n.posAddingToOrderBanner(orderCode),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: style.accent,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (awaitingRefresh)
            TextButton(
              key: const Key('pos-addition-retry-refresh'),
              onPressed: onRetryRefresh,
              child: Text(l10n.posOrdersRefresh),
            )
          else
            TextButton(
              key: const Key('pos-addition-cancel'),
              onPressed: canCancel ? onCancel : null,
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
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
    this.sendLabelOverride,
  });

  /// PSC-001C: addition mode relabels the send button ("Submit addition") —
  /// the same handler routes to `order.items_add` instead of a new order.
  final String? sendLabelOverride;

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
                  label: Text(sendLabelOverride ?? l10n.posSendOrder),
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
