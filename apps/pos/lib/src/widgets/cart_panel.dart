import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../data/demo_tables.dart';
import '../design/pos_motion.dart';
import '../design/pos_visual_tokens.dart';
import '../data/kitchen_mode_readiness.dart';
import '../data/outbox_repository.dart';
import '../format/money_format.dart';
import '../format/payment_method_label.dart';
import '../format/tax_math.dart';
import '../pos_palette.dart';
import '../data/order_submission.dart' show OrderDispatchMode, OutboxSyncState;
import '../data/round_print_claim_store.dart'
    show PosRoundPrintClaimState, posLocalKitchenDispatchClaimKey;
import '../print/pos_kitchen_ticket_printer.dart'
    show
        kdsTicketViewFromCartLines,
        kitchenTicketPrintLabelsFromL10n,
        posAdditionKitchenPrintGuardKey,
        posAutoKitchenPrintGuardProvider,
        posRoundPrintClaimStoreProvider,
        runAutoKitchenTicketPrintOnSubmit,
        runOfflineDirectPrintKitchenTicket;
import '../state/addition_controller.dart';
import '../state/cart_controller.dart';
import '../state/parked_carts_controller.dart';
import '../state/draft_recovery_controller.dart';
import '../state/order_setup_controller.dart';
import '../state/outbox_controller.dart';
import '../state/pos_branch_tax.dart';
import '../state/pos_device_context.dart';
import '../state/pos_menu_provider.dart';
import '../state/pos_offline_session_policy.dart';
import '../state/pos_offline_state.dart';
import '../state/recent_orders_controller.dart';
import '../state/pos_sync_scope_provider.dart';
import 'modifier_selection_sheet.dart';
import 'order_confirmation.dart';
import 'quantity_stepper.dart';
import 'parked_orders_sheet.dart';
import 'order_setup_section.dart';
import 'shift_context_bar.dart';

/// The live cart/order side panel (DESIGN-004): the shift-context bar over the
/// shared [CartPanelContent] (header + order setup + lines + Send footer, or the
/// in-place [OrderConfirmation] after submit). Used as the desktop/tablet side
/// cart; the phone slide-up sheet hosts the SAME [CartPanelContent].
///
/// Reads/mutates the in-memory [cartControllerProvider]. Chrome is localized;
/// item names are data; amounts are formatted integer minor-unit money.
/// POS-VISUAL-REDESIGN-PHASE-1-007 Step 2 — the cart line's modifier summary as
/// ONE string.
///
/// A four-modifier line used to be four separate rows and ~124px tall, with the
/// important numbers the same size as the option names. Joining them costs
/// nothing: this keeps the modifiers in their CONFIGURED ORDER, keeps each
/// option quantity (`displayName` already carries `xN`), and keeps every paid
/// delta inline through the same `MoneyFormatter` the rows used. Nothing is
/// dropped to make the string shorter — the RENDERING is clamped to two lines,
/// the DATA never is, and the full string stays reachable through the line's
/// Semantics label and its Tooltip.
String posCartModifierSummary(
  Iterable<SelectedModifier> modifiers,
  String currencyCode,
) => [
  for (final modifier in modifiers)
    modifier.totalDeltaMinor == 0
        ? modifier.displayName
        : '${modifier.displayName} '
              '${MoneyFormatter.formatSignedDeltaMinor(modifier.totalDeltaMinor, currencyCode)}',
].join(' \u00b7 ');

/// A formatted amount with the DIGITS promoted and the currency symbol demoted
/// (spec §9.3). The plain text is byte-identical to [formatted], so the money
/// value, its formatting and every `find.text(amount)` contract survive.
class PosAmountText extends StatelessWidget {
  const PosAmountText({
    required this.formatted,
    required this.digitSize,
    required this.symbolSize,
    this.color = kRestoflowInk,
    this.letterSpacing,
    this.amountKey,
    super.key,
  });

  final String formatted;
  final double digitSize;
  final double symbolSize;
  final Color color;
  final double? letterSpacing;
  final Key? amountKey;

  @override
  Widget build(BuildContext context) {
    final (lead, core, trail) = posSplitFormattedMoney(formatted);
    // 004: money digits render in Inter (true tabular figures) per the
    // approved type trio — the STRING stays byte-identical MoneyFormatter
    // output; only the rendering family changed.
    final symbolStyle = TextStyle(
      fontSize: symbolSize,
      fontWeight: FontWeight.w700,
      color: kRestoflowInk3,
      letterSpacing: 0,
      fontFamily: kPosMoneyFontFamily,
      fontFamilyFallback: kPosMoneyFontFallbacks,
    );
    final digitStyle = TextStyle(
      fontSize: digitSize,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontFamily: kPosMoneyFontFamily,
      fontFamilyFallback: kPosMoneyFontFallbacks,
    );
    return Text.rich(
      TextSpan(
        children: [
          if (lead.isNotEmpty) TextSpan(text: lead, style: symbolStyle),
          TextSpan(text: core, style: digitStyle),
          if (trail.isNotEmpty) TextSpan(text: trail, style: symbolStyle),
        ],
      ),
      key: amountKey,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class CartPanel extends StatelessWidget {
  const CartPanel({this.compact = false, super.key});

  /// A narrower side cart (tablet / compact-landscape) — tightens paddings.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // SURGERY-003: the panel's frame (rounded white surface + hairline) is
    // owned by the shell's _ShellSurface wrapper now — no attached-edge
    // border of its own.
    return ColoredBox(
      color: Colors.white,
      // POS-VISUAL-REDESIGN-PHASE-1-007 Step 2: the shift/drawer strip is no
      // longer a separate slab above a divider — it rides INSIDE the cart's one
      // dark operational block, which the content builds. It is still a real
      // ShiftContextBar with its own provider reads, still inside CartPanel.
      child: CartPanelContent(compact: compact, withShiftContext: true),
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
    this.withShiftContext = false,
    this.onClose,
    super.key,
  });

  /// Include the shift/drawer strip in the dark operational block. Only the
  /// side cart passes true — the phone sheet has never shown it, and Step 2
  /// does not add it there.
  final bool withShiftContext;

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
    // POS-REFERENCE-REDESIGN-002: presentation-only thumbnail lookup for the
    // order rows (reference anatomy: small photo, name, meta, total). Purely
    // visual — the line's own snapshots stay the data of record.
    final thumbByItemId = <String, String?>{
      if (menu != null)
        for (final item in menu.items) item.id: item.imageUrl,
    };
    // TABLET-UX-001 (B): the side cart (two-pane tablet/landscape) uses compact,
    // denser line rows so more of the order is visible at once; the phone
    // slide-up sheet keeps its roomier rows.
    final dense = !widget.isSheet;

    final submittedOrder = cart.submittedOrder;
    final Widget body;
    if (submittedOrder != null) {
      final confirmation = OrderConfirmation(
        key: const ValueKey('order-confirmation-view'),
        order: submittedOrder,
        onNewOrder: () {
          controller.startNewOrder();
          setupController.reset();
        },
      );
      // The shift / drawer strip stays visible on the confirmation too — it was
      // always visible before Step 2 moved it into the cart's dark block, and
      // the drawer figure is exactly what a cashier checks straight after
      // taking payment. Same widget, same provider reads, same key.
      // 004: the approved cart chrome is LIGHT — the shift context rides its
      // own warm status pill on the white panel (same widget, same provider
      // reads, same key).
      body = widget.withShiftContext
          ? Column(
              key: const ValueKey('order-confirmation-view-wrapper'),
              children: [
                const ColoredBox(
                  color: Colors.white,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: EdgeInsets.only(top: RestoflowSpacing.sm),
                      child: ShiftContextBar(),
                    ),
                  ),
                ),
                Expanded(child: confirmation),
              ],
            )
          : confirmation;
    } else {
      // PSC-001C: ADDITION MODE — the cart's lines are a pending addition to
      // an EXISTING order. The parent already owns its type/table, so the
      // order-setup gate does not apply; the banner below names the target.
      final addition = ref.watch(additionControllerProvider);
      // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): the ONE shared submission
      // decision — Send-eligibility and the emitted dispatch_mode both derive from
      // it, so they can never disagree. A NEW order may only be sent once the
      // verified kitchen workflow mode has RESOLVED; while it is loading/unavailable
      // Send is blocked (never a guessed KDS that would strand a printer_only
      // dine-in order). Additions ride the parent order's already-decided mode.
      final submissionDecision = resolvePosSubmissionDecision(
        ref.watch(posKitchenModeReadinessProvider),
      );
      // [POS-OFFLINE-OPERATIONS-002] (C6): may THIS session still submit?
      // Blocks ONLY a restored-offline session whose hard trust window ended —
      // the cached menu stays browsable, Send explains itself below.
      final offlineSessionPolicy = ref.watch(posOfflineSessionPolicyProvider);
      // [POS-OFFLINE-OPERATIONS-002] (C7): while selling from the offline
      // snapshot, an UNAVAILABLE kitchen mode means the cached mode's 2-hour
      // trust window has ended (a within-window capture would have resolved
      // it) — the hint below then says so instead of the generic retry copy.
      final offlinePhase = ref.watch(posOfflineModeProvider).phase;
      // Finding 4: while APPLIED-AWAITING-REFRESH the send button stays off —
      // the operation must never be dispatched again; the banner offers the
      // refresh retry instead.
      final canSend =
          !cart.isEmpty &&
          (addition.active || setup.isReadyToSubmit) &&
          (addition.active || submissionDecision.canSubmit) &&
          offlineSessionPolicy.canSubmit &&
          // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: a NON-EMPTY malformed phone blocks
          // Send (the field shows the localized inline error); an empty or valid
          // phone never does. Defence-in-depth is re-checked in _handleSend.
          !setup.hasBlockingCustomerPhone &&
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

      // POS-CART-VERTICAL-FIT-001: the totals/actions footer is built ONCE and
      // placed by whichever branch below owns the remaining space.
      final footer = _CartFooter(
        l10n: l10n,
        subtotalMinor: cart.subtotalMinor,
        taxMinor: taxMinor,
        taxRateBp: taxMinor > 0 ? tax.rateBp : 0,
        currencyCode: cart.currencyCode,
        orderType: setup.orderType,
        tableLabel: setup.assignedTable?.label,
        showNeedsTableHint:
            cart.isNotEmpty && setup.needsTableWarning && !addition.active,
        sendLabelOverride: addition.active ? l10n.posSubmitAddition : null,
        // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): the workflow-mode
        // loading/unavailable reason (new orders only); a retry appears for
        // the retryable unavailable case.
        //
        // [POS-OFFLINE-OPERATIONS-002] Two additions, same hint row idiom:
        //  * C7 — unavailable WHILE selling from the offline snapshot means
        //    the cached kitchen mode aged past its 2h trust window: the copy
        //    says that (posOfflineKitchenModeStale) instead of the generic
        //    retry line. The Retry affordance is unchanged.
        //  * C6 — with the kitchen row silent, a session blocked by the
        //    offline policy (restored session past its 8h window) claims the
        //    row with its own reason. Kitchen reasons deliberately outrank
        //    the session reason so the cashier never sees two banners.
        kitchenModeHint: (!addition.active && !submissionDecision.canSubmit)
            ? (submissionDecision.blockReason ==
                      PosSubmissionBlockReason.kitchenModeUnavailable
                  ? (offlinePhase == PosOfflinePhase.offlineCached
                        ? l10n.posOfflineKitchenModeStale
                        : l10n.posCloseWorkflowUnavailable)
                  : l10n.posKitchenModeLoading)
            : (!offlineSessionPolicy.canSubmit
                  ? l10n.posOfflineSendBlockedSession
                  : null),
        onRetryKitchenMode:
            (!addition.active &&
                submissionDecision.blockReason ==
                    PosSubmissionBlockReason.kitchenModeUnavailable)
            ? () => ref
                  .read(posKitchenModeReadinessProvider.notifier)
                  .requestResolution()
            : null,
        // PARKED-CARTS-001: Park is offered only when the controller says
        // this cart is parkable — not empty, no submit/confirmation in
        // flight, and no amendment owning it. The controller re-checks
        // every condition regardless, so this is honesty, not the gate.
        onPark:
            (!_submitting &&
                ref.watch(parkedCartsControllerProvider.notifier).canPark)
            ? () => handleParkFromCart(ref: ref, context: context, l10n: l10n)
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
      );

      // POS-CART-VERTICAL-FIT-001 — the cart body is ONE scroll view.
      //
      // It used to be a plain Column: a RIGID header, a RIGID order-setup
      // section (measured 240px) and a RIGID totals/actions footer around a
      // single `Expanded` holding the lines. As soon as those rigid children
      // exceeded the panel the `Expanded` clamped to zero and the Column
      // overflowed — at 800x480 by 244px — and nothing in it could ever scroll.
      //
      // Now the whole body is a CustomScrollView, so at short heights every
      // part of it scrolls instead of overflowing, while at normal heights it
      // looks exactly as before:
      //
      //   * the lines are a SliverList, NOT a nested ListView — there is only
      //     ever ONE scrollable here, so no nested-scroll conflict;
      //   * the footer rides in a trailing SliverFillRemaining, which lays its
      //     child out with a TIGHT height of max(remaining, intrinsic). When
      //     there is room left it is pinned to the bottom exactly as the old
      //     Column pinned it; when there is not, it simply scrolls into reach
      //     rather than overflowing. That also means `Expanded` still works
      //     inside it, which is how the empty state stays vertically centred.
      //
      // No fixed heights, no viewport-specific conditions, nothing clipped, and
      // no control is ever removed — only reached by scrolling when the screen
      // is genuinely too short to show everything at once.
      body = Material(
        key: const ValueKey('cart-view'),
        color: Colors.white,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 004: ONE LIGHT operational block heads the cart (the
                  // approved v4 screens moved the dark plane to the top app
                  // bar): title + ember glyph + count chip + the sync chip +
                  // Clear, with the collapsible shift-status pill below.
                  // Same key, same operational elements, same gating.
                  DecoratedBox(
                    key: const Key('pos-cart-operational-header'),
                    decoration: const BoxDecoration(color: Colors.white),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CartHeader(
                          l10n: l10n,
                          itemCount: cart.itemCount,
                          pendingSync: pendingSync,
                          // POS-PREMIUM-VISUAL-POLISH-001: the SIDE cart's
                          // glyph is the fly-to-cart landing point; the phone
                          // sheet never carries it (the bottom bar does), so
                          // the GlobalKey stays unique by construction.
                          attachFlyTarget: !widget.isSheet,
                          // Cart-safety: a frozen addition attempt owns the
                          // cart — the Clear control is disabled (the
                          // controller refuses regardless).
                          onClear: cart.isEmpty || cart.lockedByAddition
                              ? null
                              : controller.clear,
                        ),
                        if (widget.withShiftContext) const ShiftContextBar(),
                      ],
                    ),
                  ),
                  // PSC-001C: while ADDING to an existing order the setup
                  // section (type/table) is replaced by the target banner — the
                  // parent order's context is fixed and must stay visible.
                  if (addition.active)
                    _AdditionBanner(
                      l10n: l10n,
                      orderCode: addition.target!.orderCode,
                      tableLabel: addition.target!.tableLabel,
                      failed: addition.failed,
                      awaitingRefresh: addition.awaitingRefresh,
                      // Finding 2: cancel is DISABLED while the attempt is on
                      // the wire or applied-awaiting-refresh — the controller
                      // refuses it anyway (defense in depth); the banner is
                      // honest about it.
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
                  // A softer edge than a full-width divider — the dark header
                  // above already does the separating (spec §6).
                  const Divider(height: 1, color: kPosSetupEdge),
                ],
              ),
            ),
            if (cart.isEmpty)
              // The empty state keeps its centred placement: SliverFillRemaining
              // gives a TIGHT height, so the Expanded below resolves exactly as
              // it did inside the old Column.
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    Expanded(child: _EmptyCart(message: l10n.posCartEmpty)),
                    footer,
                  ],
                ),
              )
            else ...[
              // SURGERY-003: order rows are FLAT rows on the white panel,
              // separated by subtle hairline dividers — no more warm track
              // with a card per line.
              DecoratedSliver(
                decoration: const BoxDecoration(color: Colors.white),
                sliver: SliverPadding(
                  padding: EdgeInsets.symmetric(
                    vertical: dense ? RestoflowSpacing.xs : RestoflowSpacing.sm,
                    horizontal: dense ? 10 : RestoflowSpacing.md,
                  ),
                  sliver: SliverList.separated(
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 9,
                      thickness: 1,
                      color: kRestoflowHairline,
                    ),
                    itemBuilder: (context, index) {
                      final line = cart.lines[index];
                      // Cart-safety: while a frozen addition attempt owns the
                      // cart, every line control is disabled — the visible lines
                      // ARE the frozen payload.
                      final locked = cart.lockedByAddition;
                      return _CartLineTile(
                        line: line,
                        l10n: l10n,
                        dense: dense,
                        thumbnailUrl: thumbByItemId[line.menuItemId],
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
                            : () => _editLine(context, menu, line, controller),
                      );
                    },
                  ),
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Align(alignment: Alignment.bottomCenter, child: footer),
              ),
            ],
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

/// PARKED-CARTS-001 — the Park handler.
///
/// Sets the current UNSENT cart aside as a local draft. It sends nothing,
/// prints nothing, takes no payment and claims no table; the controller
/// persists the draft and only then resets the cart, so a failed write leaves
/// the cashier exactly where they were.
///
/// PUBLIC (visible for testing): this is the Park button's handler, and the
/// atomic persist-then-reset ordering can only be proven by driving THIS seam.
@visibleForTesting
Future<void> handleParkFromCart({
  required WidgetRef ref,
  required BuildContext context,
  required AppLocalizations l10n,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await ref.read(parkedCartsControllerProvider.notifier).park();
  final message = switch (result) {
    ParkResult.parked => l10n.posParkedParkSucceeded,
    ParkResult.blockedByAddition => l10n.posParkedBlockedByAddition,
    // cartEmpty / busy / noScope are states the disabled button already
    // prevents; if one is somehow reached, say the honest thing rather than
    // implying the cart was stored.
    _ => l10n.posParkedParkFailed,
  };
  messenger.showSnackBar(SnackBar(content: Text(message)));
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
    // Captured BEFORE the await: the widget's ref dies with the tree, the
    // container and the notifiers it owns do not.
    final additionContainer = ProviderScope.containerOf(context, listen: false);
    final result = await ref.read(additionControllerProvider.notifier).submit();
    // Finding 4: applied-but-not-refreshed is its own honest message — the
    // addition IS saved; only the authoritative view still needs a reload.
    // KITCHEN-MODIFIER-PREP-CLASSIFIER-STALE-SNAPSHOT-FIX-021: a stale
    // preparation snapshot is NOT "tap to retry" — the server refused this
    // frozen round deterministically and the same operation can only be refused
    // again. The pending lines are still in the cart (the controller clears them
    // only on a reconciled success), so the honest instruction is to refresh the
    // menu and re-pick the affected line, which sends a NEW operation.
    final additionFailure = result.applied
        ? null
        : (result.error == 'modifier_prep_snapshot_stale'
              ? l10n.posPrepSnapshotStale
              : l10n.posAdditionFailedRetry);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          additionFailure ??
              (result.refreshRequired
                  ? l10n.posAdditionSavedRefreshNeeded
                  : l10n.posAdditionApplied),
        ),
      ),
    );
    // DEFERRED-ORDER-AMENDMENTS-001: print ONE kitchen ADDITION ticket for the
    // round the server just applied — the DELTA only, never the whole parent
    // order (the kitchen already has that paper, and reprinting it would get the
    // original food cooked twice). Best-effort and fully decoupled: the amendment
    // is ALREADY applied server-side, so a print failure never resends
    // `order.items_add` and never turns the applied addition into a failure — the
    // guard releases the round so only the PRINT can be retried. Guarded on the
    // round-scoped identity, so each round prints exactly once while the parent's
    // initial ticket keeps its own separate claim.
    final payload = result.printPayload;
    final additionOrderType = payload?.orderType;
    if (payload != null && additionOrderType != null) {
      unawaited(
        runAutoKitchenTicketPrintOnSubmit(
          container: additionContainer,
          orderId: payload.orderId,
          guardKey: posAdditionKitchenPrintGuardKey(
            orderId: payload.orderId,
            roundId: payload.roundId,
          ),
          isDemoMode: additionContainer.read(runtimeConfigProvider).isDemoMode,
          // The frozen delta lines + the ONE order-time prep snapshot the wire
          // payload used, plus the parent's PRESERVED identity, type and table
          // (null for takeaway — no table is invented). The round id/number make
          // this an addition ticket, so the shared builder prints the localized
          // "Addition · Round N" marker under the original order code.
          ticket: kdsTicketViewFromCartLines(
            orderCode: payload.orderCode,
            orderType: additionOrderType,
            lines: payload.lines,
            prepByItemId: payload.prepByItemId,
            tableLabel: payload.tableLabel,
            customerName: payload.customerName,
            customerPhone: payload.customerPhone,
            roundId: payload.roundId,
            roundNumber: payload.roundNumber,
          ),
          labels: kitchenTicketPrintLabelsFromL10n(l10n),
        ),
      );
    }
    return;
  }
  final outbox = ref.read(outboxControllerProvider.notifier);
  // Captured BEFORE the await: the widget's ref dies with the tree (an unpair
  // unmounts the POS), but the container and the notifiers it owns do not.
  final container = ProviderScope.containerOf(context, listen: false);
  // KITCHEN-PRINT-DUAL-001D: every order ALWAYS uses the normal KDS workflow — no
  // dispatch_mode decision, no printer gate. The auto-print toggle drives only the
  // additive post-submit kitchen print (resolved AFTER submit inside
  // runAutoKitchenTicketPrintOnSubmit); it never blocks or reroutes the order.
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
  // MENU-ORDER-001 (Codex correction-ownership): if this cart was RESTORED from a durable
  // recovery (Back to cart), the active correction source names it — but this is treated
  // as a correction ONLY when that source is OWNED by the CURRENT signed-in worker + POS
  // scope AND its recovery is still live. A stale source (a departed worker, a re-pair, or
  // an already-resolved recovery) is inert: this submit is then an ordinary, unlinked
  // order — it can never re-link someone else's, or a dead, recovery. Captured before the
  // await (the widget ref dies with the tree; the container + notifiers outlive it).
  final activeSourceBefore = container.read(posActiveCorrectionSourceProvider);
  final correctionSource =
      (activeSourceBefore != null &&
          activeSourceBefore.ownedBy(
            scopeKey: bindingBefore.scopeKey,
            employeeProfileId: bindingBefore.employeeProfileId,
          ) &&
          container
              .read(posDraftRecoveryProvider.notifier)
              .hasRecoveryFor(activeSourceBefore.sourceOutboxEntryId))
      ? activeSourceBefore
      : null;
  final orderTypeBefore = setup.orderType;
  final tableBefore = setup.assignedTable;
  final customerNameBefore = setup.customerName;
  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL phone (normalized; null when
  // not entered / invalid). Captured pre-await like the name.
  final customerPhoneBefore = setup.customerPhone;
  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): the dispatch mode comes from the
  // ONE shared submission decision (the SAME one the Send button gated on), so the
  // UI and the emitted payload can never disagree. Defence in depth: if the
  // verified mode became unresolved between the tap and here, REFUSE — never guess
  // KDS (which would strand a printer_only dine-in order). direct_print is emitted
  // only for a trusted printer_only branch; that same resolution drives
  // close-eligibility.
  final submissionDecision = resolvePosSubmissionDecision(
    container.read(posKitchenModeReadinessProvider),
  );
  if (!submissionDecision.canSubmit) return;
  // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 1E): the mode was verified for a
  // SPECIFIC restaurant/branch/device scope. If that scope changed between the
  // Send tap and this exact moment of payload construction (a re-pair / branch
  // switch), the verified mode no longer applies — REFUSE (create zero outbox
  // operations) rather than dispatch an old-scope mode (a guessed KDS on a
  // printer_only branch, or direct_print on a KDS branch). Read the live scope
  // from the SAME authoritative source the readiness binds to; demo has no
  // backend scope to verify against. The Send button already re-gates on the
  // readiness (which resets to Loading on a scope change), so this is the
  // deterministic belt-and-suspenders at the construction point.
  if (!container.read(runtimeConfigProvider).isDemoMode &&
      submissionDecision.scope !=
          PosKitchenModeScopeKey.fromContext(
            container.read(posDeviceContextProvider),
          )) {
    return;
  }
  final dispatchModeBefore = submissionDecision.dispatchMode;
  // KITCHEN-PRINT-DUAL-001B (snapshot-race fix): capture the ORDER-TIME (D-008)
  // prep snapshot ONCE, HERE — BEFORE the first await — from the SAME live menu
  // the outbox payload is built from. This exact immutable map feeds BOTH the
  // authoritative submission payload (passed into outbox.submit below) AND the
  // post-submit POS kitchen ticket, so a menu/prep edit while the submit is in
  // flight can never make the printed ticket disagree with what the KDS receives.
  // Money-free; empty for unconfigured items.
  final kitchenPrepByItemId = <String, List<KitchenPrepComponent>>{
    if (container.read(posMenuProvider).valueOrNull case final menu?)
      for (final item in menu.items)
        if (item.prepComponents.isNotEmpty) item.id: item.prepComponents,
  };
  // MENU-ORDER-001 (Codex correction-ownership §4/§5): for a CORRECTION submit, the
  // pre-dispatch link callback. It runs INSIDE outbox.submit — after the submit's exact
  // ids are minted, BEFORE the order is enqueued/pushed — and durably supersedes the
  // source recovery with THIS submit's entry id + the corrected cart (awaited, atomic,
  // owner-revalidated). A false result (not owned, or the durable write failed) makes
  // outbox.submit throw before any dispatch, so no order is sent while the association is
  // in-memory-only. Null for an ordinary (non-correction) submit.
  final beforeDispatch = correctionSource == null
      ? null
      : (String orderId, String localOperationId, String entryId) => container
            .read(posDraftRecoveryProvider.notifier)
            .linkCorrectedSubmit(
              sourceOutboxEntryId: correctionSource.sourceOutboxEntryId,
              correctedOutboxEntryId: entryId,
              binding: bindingBefore,
              correctedDraft: draftBefore,
              orderType: orderTypeBefore,
              table: tableBefore,
              customerName: customerNameBefore,
              customerPhone: customerPhoneBefore,
            );
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
      // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the optional customer phone + the
      // resolved dispatch mode (direct_print for a verified printer_only branch).
      customerPhone: customerPhoneBefore,
      dispatchMode: dispatchModeBefore,
      // The ONE immutable prep snapshot (captured above, pre-await) — the same
      // map the POS kitchen ticket reuses below.
      prepByItemId: kitchenPrepByItemId,
      // §4 pre-dispatch correction link (null for a normal submit).
      beforeDispatch: beforeDispatch,
    );
    // MENU-ORDER-001 (Codex correction-result settlement §2): the IMMUTABLE settlement
    // context for a CORRECTED submit, built from the OWNER-VALIDATED pre-await source +
    // the ORIGINAL submit's exact entry id (result.entry.id is the id THIS submit created,
    // never the current session's). It is the single authority for settling this result
    // onto the one source recovery — whether the submitting session is still current or
    // has departed — so neither result path ever captures a standalone corrected recovery.
    // Null for an ordinary (non-correction) submit, which keeps the two cases distinct.
    final settlement = correctionSource == null
        ? null
        : CorrectionSettlementContext(
            sourceOutboxEntryId: correctionSource.sourceOutboxEntryId,
            submittedOutboxEntryId: result.entry.id,
            originalBinding: PosRecoveryBinding(
              scopeKey: correctionSource.scopeKey,
              employeeProfileId: correctionSource.employeeProfileId,
            ),
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
        customerPhone: customerPhoneBefore,
        taxTotalMinor: taxTotalMinor,
        taxRateBp: taxRateBp,
        // 018 (Codex HIGH #2): the SAME immutable prep snapshot the outbox
        // payload and the automatic ticket were built from. The captured draft
        // holds each line's ADD-TIME prep, so without this a PIN handover
        // rewound the departed worker's retained order (and every reprint from
        // it) to a configuration the server never accepted.
        submittedPrepByItemId: kitchenPrepByItemId,
        // MENU-ORDER-001 (§3): when this was a CORRECTION, the departed-session path must
        // settle onto the SINGLE source recovery (already superseded + linked before
        // dispatch), NEVER capture a standalone recovery keyed by the corrected entry.
        settlement: settlement,
      );
      return; // Finding 1C: never a generic current-cart clear after a session switch.
    }

    // SAME SESSION. PILOT-OPERATIONS-CORRECTIONS-001: capture the draft (taken BEFORE the
    // await, keyed to THIS submit's outbox entry) bound to THE SUBMITTING session's exact
    // binding. If the server permanently rejects it (item_unavailable), the confirmation
    // offers "Back to cart" to restore this exact draft; an accepted order clears it.
    //
    // MENU-ORDER-001 (Codex correction-ownership §3.F/§8.D): SKIP this for a CORRECTION
    // resubmit. The pre-dispatch link already superseded the SINGLE source recovery with
    // this corrected cart + this entry id — capturing a second recovery here would leave
    // two records for one logical order. The source recovery IS the corrected order's
    // record; it is cleared only on that order's authoritative acceptance.
    if (correctionSource == null) {
      container
          .read(posDraftRecoveryProvider.notifier)
          .capture(
            PosDraftRecovery(
              draft: draftBefore,
              orderType: orderTypeBefore,
              table: tableBefore,
              customerName: customerNameBefore,
              customerPhone: customerPhoneBefore,
              outboxEntryId: result.entry.id,
              // A2: bind to THIS exact context (scope + PIN session) so a later employee /
              // branch / device can never see or restore this draft.
              binding: bindingBefore,
            ),
          );
    }

    // [POS-OFFLINE-OPERATIONS-002] C9 — the DURABLE PRINT-JOB COMMIT for an
    // offline direct_print order, BEFORE the cart clears. On a printer_only
    // branch the POS ticket IS the kitchen dispatch, so once the cart is gone
    // the printed ticket is the only path this food has into the kitchen. The
    // required ordering is: outbox commit (above) → durable print-job commit
    // (HERE, awaited) → cart clear + queued confirmation (below) → physical
    // attempt (after, fire-and-forget) → server sync later. The claim key is
    // the LOCAL dispatch identity `local:v1:<deviceId>:<localOperationId>:kitchen`
    // (D-022 — globally unique, collision-free with server dispatch UUIDs),
    // so a crash/restart in any window reads the durable claim and can never
    // re-print the ticket. Pass C (B1): a REFUSED claim write no longer
    // withholds the physical attempt — see the policy at the catch below.
    // Applies ONLY when the submit did not reach the server (not applied) and
    // was not definitively refused; an ONLINE direct_print submit keeps the
    // existing post-confirmation auto-print path byte-identically.
    final directPrintEntry = container
        .read(outboxControllerProvider.notifier)
        .entryById(result.entry.id);
    final offlineDirectPrint =
        dispatchModeBefore == OrderDispatchMode.directPrint &&
        !container.read(runtimeConfigProvider).isDemoMode &&
        directPrintEntry != null &&
        directPrintEntry.syncState != OutboxSyncState.applied &&
        !directPrintEntry.isDefinitiveNoServerOrder;
    String? offlineDirectPrintClaimKey;
    if (offlineDirectPrint) {
      offlineDirectPrintClaimKey = posLocalKitchenDispatchClaimKey(
        deviceId: result.entry.deviceId,
        localOperationId: result.entry.localOperationId,
      );
      final claims = container.read(posRoundPrintClaimStoreProvider);
      if (claims != null) {
        try {
          await claims.record(
            offlineDirectPrintClaimKey,
            PosRoundPrintClaimState.claimed,
          );
        } on Object {
          // [POS-OFFLINE-OPERATIONS-002] Pass C (B1) — POLICY: the durable
          // commit was REFUSED, and the physical print still runs, guarded
          // IN-MEMORY only. Withholding it looked safe ("fail toward not
          // printing") and was in fact silent kitchen loss: the order is
          // committed, the auto print fires ONLY on a fresh submit (a restart
          // cannot re-attempt it), and with no claim recorded the confirmation
          // showed no pending line either — food nobody would ever cook, told
          // to nobody. The duplicate direction stays covered without the
          // durable record: the in-memory guard dedupes this session, and the
          // drain-side defence is the mirror-claim consult (C1) — whose
          // absence when the store is broken is the DOCUMENTED residual,
          // while the claim store is already screaming storage-unhealthy at
          // indicator priority 1. The session-only overlay below keeps the
          // pending/failed outcome visible on the confirmation exactly like
          // the durable claim would have (B3).
          container
              .read(posAutoKitchenPrintGuardProvider)
              .noteDurableClaimRefused(offlineDirectPrintClaimKey);
        }
      }
    }

    cartController.submitOrder(
      orderType: orderTypeBefore,
      tableLabel: tableBefore?.label,
      customerName: customerNameBefore,
      customerPhone: customerPhoneBefore,
      orderNumber: result.orderNumber,
      outboxEntryId: result.entry.id,
      localOperationId: result.entry.localOperationId,
      orderId: result.entry.targetId,
      taxTotalMinor: taxTotalMinor,
      taxRateBp: taxRateBp,
      // 017 (Codex HIGH #3): the SAME immutable prep snapshot the authoritative
      // outbox payload above was built from — so the confirmation view, the
      // automatic kitchen ticket and every later MANUAL REPRINT describe the
      // operation that was actually submitted, not the (possibly older) menu
      // configuration captured when the lines first entered the cart.
      submittedPrepByItemId: kitchenPrepByItemId,
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
      if (entry != null && entry.isDefinitiveNoServerOrder) {
        recent.markLocallyRejected(submitted.identity);
      }
    }
    // MENU-ORDER-001 (Codex correction-ownership §6): if this submit was the corrected
    // resubmit of a RESTORED recovery, the pre-dispatch link already superseded the SINGLE
    // source recovery (draft = this corrected cart, correctionOutboxEntryId = this entry) —
    // BEFORE the order was sent. NOTHING is cleared here: cleanup happens ONLY when the
    // corrected order is authoritatively ACCEPTED, via the controller-seam acceptance
    // listener matching the link (so an accept-then-crash still reconciles on the next
    // startup). A rejected / retryable / network / timeout result NEVER clears the source.
    if (settlement != null &&
        settlement.sourceOutboxEntryId != result.entry.id) {
      // SETTLE onto the SINGLE source recovery through the one owner-bound settlement API
      // (same path the departed-session branch uses). The pre-dispatch link already
      // superseded the source (corrected draft + link to this entry); this only retires a
      // DUPLICATE rejected shell for the corrected entry so one logical order keeps one
      // shell — never a standalone capture, never cleared on a non-accepted result.
      final correctedEntry = container
          .read(outboxControllerProvider.notifier)
          .entryById(result.entry.id);
      unawaited(
        container
            .read(posDraftRecoveryProvider.notifier)
            .settleCorrectedResult(
              originalBinding: settlement.originalBinding,
              sourceOutboxEntryId: settlement.sourceOutboxEntryId,
              submittedOutboxEntryId: settlement.submittedOutboxEntryId,
              submittedWasPermanentlyRejected:
                  correctedEntry != null &&
                  correctedEntry.isDefinitiveNoServerOrder,
            ),
      );
      // This correction attempt is done — the cart was submitted (emptied) above. Drop the
      // in-memory active source so no unrelated later submit re-links the (retained) source
      // recovery; a further "Back to cart" re-establishes it. The DURABLE source recovery
      // is untouched (retained unless/until its corrected order is accepted or discarded).
      container.read(posActiveCorrectionSourceProvider.notifier).clear();
    }
    // KITCHEN-PRINT-DUAL-001: optionally print the money-free KITCHEN ticket for
    // the just-created order. Best-effort + fully decoupled — it prints to the
    // INDEPENDENT kitchen printer, never touches the cashier receipt, and a
    // kitchen-print failure can NEVER turn this successful submit into a
    // failure. Inert unless the per-device "auto-print kitchen ticket" setting
    // is on; the in-memory guard makes a double-tap/rebuild print at most once.
    final kitchenPrintEntry = container
        .read(outboxControllerProvider.notifier)
        .entryById(result.entry.id);
    // KITCHEN-PRINT-DUAL-001B (snapshot-race fix): the POS kitchen ticket is built
    // from the SAME immutable pre-await snapshot the authoritative payload used —
    // the cart lines captured before the await (immutable; carry the modifier
    // names/quantities + SelectedModifier.kitchenMeat + item notes) and the ONE
    // [kitchenPrepByItemId] map. NOTHING here re-reads a menu/prep/modifier
    // provider after the await, so the printed ticket cannot diverge from what the
    // KDS receives.
    // [POS-OFFLINE-OPERATIONS-002] C9: the OFFLINE direct_print order takes the
    // pre-claimed path — its durable print-job commit landed BEFORE the cart
    // cleared (or, B1, its REFUSED commit was noted on the in-memory guard),
    // so the physical attempt runs under THAT claim, settled truthfully to
    // sent/failed. The guarantee this seam actually makes is stated on
    // [runOfflineDirectPrintKitchenTicket]: at-most-once AUTOMATIC physical
    // send per submit; `sent` is transport acceptance, never paper (ESC/POS
    // gives no reliable acknowledgement, so a deliberate manual reprint after
    // an ambiguous acknowledgement can duplicate); an owed ticket stays
    // recoverable from the confirmation AND the recent-orders surfaces,
    // surviving restart via the durable claim + durable outbox entry.
    // Everything else (online direct_print, kds, demo) keeps the existing call
    // byte-identically.
    if (offlineDirectPrint) {
      unawaited(
        runOfflineDirectPrintKitchenTicket(
          container: container,
          orderId: result.entry.targetId,
          // Non-null by construction: assigned unconditionally above whenever
          // offlineDirectPrint holds.
          localDispatchClaimKey: offlineDirectPrintClaimKey!,
          isDemoMode: container.read(runtimeConfigProvider).isDemoMode,
          ticket: kdsTicketViewFromCartLines(
            orderCode: result.orderNumber,
            orderType: orderTypeBefore,
            lines: cart.lines,
            prepByItemId: kitchenPrepByItemId,
            tableLabel: tableBefore?.label,
            customerName: customerNameBefore,
            customerPhone: customerPhoneBefore,
          ),
          labels: kitchenTicketPrintLabelsFromL10n(l10n),
        ),
      );
    } else {
      unawaited(
        runAutoKitchenTicketPrintOnSubmit(
          container: container,
          orderId: result.entry.targetId,
          // Shared eligibility: a permanently-rejected or demo order never cooks.
          isDemoMode: container.read(runtimeConfigProvider).isDemoMode,
          // 024: the AUTHORITATIVE suppression, evaluated on the entry whose
          // verdict the push just recorded — an auth refusal or an unrecognised
          // structured refusal must not reach the kitchen printer either.
          definitivelyRejected:
              kitchenPrintEntry?.isDefinitiveNoServerOrder ?? false,
          rejectionCode: kitchenPrintEntry?.lastErrorCode,
          // KITCHEN-PRINT-DUAL-001D: purely ADDITIVE — `enabled` omitted so the print
          // resolves the persisted auto-print toggle itself AFTER submit (it may
          // await). ON prints one detailed ticket; OFF prints nothing; a failure or a
          // missing printer is best-effort and NEVER alters the already-submitted KDS
          // order. Manual "Print kitchen ticket" on the confirmation stays available.
          ticket: kdsTicketViewFromCartLines(
            orderCode: result.orderNumber,
            orderType: orderTypeBefore,
            lines: cart.lines,
            prepByItemId: kitchenPrepByItemId,
            tableLabel: tableBefore?.label,
            customerName: customerNameBefore,
            customerPhone: customerPhoneBefore,
          ),
          labels: kitchenTicketPrintLabelsFromL10n(l10n),
        ),
      );
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
  required String? customerPhone,
  required int taxTotalMinor,
  required int taxRateBp,

  /// 018 (Codex HIGH #2): the submitted operation's authoritative prep snapshot,
  /// carried into BOTH departed-session views below so the retained row and its
  /// manual reprint describe the accepted operation, not the pre-submit draft.
  required Map<String, List<KitchenPrepComponent>> submittedPrepByItemId,
  CorrectionSettlementContext? settlement,
}) {
  final entry = container
      .read(outboxControllerProvider.notifier)
      .entryById(result.entry.id);
  final permanentlyRejected = entry != null && entry.isDefinitiveNoServerOrder;

  // MENU-ORDER-001 (Codex correction-result settlement §3): a CORRECTED submission that
  // settles after the submitting worker/scope departed must NEVER be captured as a second
  // standalone recovery keyed by the corrected entry — that is the confirmed defect
  // (e1 linked to e2 PLUS an independent e2). Its SINGLE source recovery (e1) was already
  // superseded in place (corrected draft + link to this exact entry) under its ORIGINAL
  // owner, and awaited to disk, BEFORE dispatch. So settle by that original context:
  // verify the link + retire only a duplicate shell; capture NOTHING here.
  if (settlement != null) {
    // Same scope + NOT permanently rejected -> record the (accepted/pending) row so the
    // original scope re-discovers its order; a permanent rejection records NO competing
    // shell (the source recovery's own shell surfaces the one logical order). A scope
    // change records nothing (a different branch's list). An accepted order additionally
    // clears the source recovery through its link via the controller-seam listeners.
    if (container.read(posSyncScopeProvider)?.key == scopeKeyBefore &&
        !permanentlyRejected) {
      container
          .read(posRecentOrdersControllerProvider.notifier)
          .recordSubmitted(
            cartController.viewFromDraft(
              draft: draft,
              orderType: orderType,
              tableLabel: table?.label,
              customerName: customerName,
              customerPhone: customerPhone,
              orderNumber: result.orderNumber,
              outboxEntryId: result.entry.id,
              localOperationId: result.entry.localOperationId,
              orderId: result.entry.targetId,
              taxTotalMinor: taxTotalMinor,
              taxRateBp: taxRateBp,
              submittedPrepByItemId: submittedPrepByItemId,
            ),
          );
    }
    unawaited(
      container
          .read(posDraftRecoveryProvider.notifier)
          .settleCorrectedResult(
            originalBinding: settlement.originalBinding,
            sourceOutboxEntryId: settlement.sourceOutboxEntryId,
            submittedOutboxEntryId: settlement.submittedOutboxEntryId,
            submittedWasPermanentlyRejected: permanentlyRejected,
          ),
    );
    return;
  }

  // ORDINARY new order (no source recovery): retain ONE standalone recovery under the
  // ORIGINAL session's binding, so the draft is inaccessible to the current operator
  // (binding mismatch) yet recoverable when its owner returns. `capture` no-ops when the
  // order already applied (accepted -> nothing to recover); an accepted order's recovery
  // is additionally cleared by the controller-seam acceptance listeners.
  container
      .read(posDraftRecoveryProvider.notifier)
      .capture(
        PosDraftRecovery(
          draft: draft,
          orderType: orderType,
          table: table,
          customerName: customerName,
          customerPhone: customerPhone,
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
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 3): the ORDINARY departed-
    // session/PIN-handover path retained the phone in the recovery (above) but
    // dropped it here when building the recent-order row, so a returning worker's
    // recent-order detail + receipt/kitchen reprints lost the phone. Carry the
    // SAME authoritative captured phone through, exactly like the settlement path.
    customerPhone: customerPhone,
    orderNumber: result.orderNumber,
    outboxEntryId: result.entry.id,
    localOperationId: result.entry.localOperationId,
    orderId: result.entry.targetId,
    taxTotalMinor: taxTotalMinor,
    taxRateBp: taxRateBp,
    submittedPrepByItemId: submittedPrepByItemId,
  );
  recent.recordSubmitted(view);
  if (permanentlyRejected) {
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
  // MONEY-MODIFIER-PRICING-INTEGRITY-001 — the money-safe edit routing.
  //
  // When no authoritative groups resolve (menu unavailable/loading, item gone)
  // the sheet CANNOT represent the line's stored modifiers. Confirming used to
  // call `updateLineModifiers(lineId, [])`, which deleted the paid snapshots
  // and silently re-priced the line down to its base — the reported
  // under-charge. The old comment claimed "note only"; nothing enforced it.
  //
  // Now the fallback is note-only BY CONSTRUCTION: it is routed to
  // `updateLineNote`, which has no access to `_lineModifiers` at all, so this
  // path cannot change money even if the sheet handed back an empty list. The
  // sheet separately explains why options are missing, and blocks Save when
  // groups DID resolve but a stored selection cannot be represented.
  final noteOnly = groups.isEmpty && line.modifiers.isNotEmpty;
  ModifierSelectionSheet.show(
    context,
    item: item,
    groups: groups,
    currencyCode: currency,
    category: category,
    initialSelections: line.modifiers,
    initialNote: line.note,
    isEdit: true,
    // POS-MODIFIER-SHEET-QUANTITY-003: reopen ON the line's current quantity so
    // Save cannot silently reset a line of 4 back to 1.
    initialQuantity: line.quantity,
    // MONEY-EDIT-INTEGRITY-002C (Codex Blocker 5): the sheet must price this
    // edit against the line's FROZEN base (D-008), not against whatever the
    // Dashboard charges for the product today. `updateLineModifiers` keeps the
    // snapshot, so showing the live price meant showing one amount and saving
    // another. `CartLineView.unitPriceMinor` is the BARE per-unit base — the
    // modifier deltas are carried separately and the sheet adds them itself.
    displayBasePriceMinor: line.unitPriceMinor,
    onConfirm: noteOnly
        ? (selections, note, quantity) =>
              controller.updateLineNote(line.lineId, note)
        : (selections, note, quantity) => controller.updateLineModifiers(
            line.lineId,
            selections,
            note: note,
            quantity: quantity,
          ),
  );
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({
    required this.l10n,
    required this.itemCount,
    required this.pendingSync,
    required this.onClear,
    this.attachFlyTarget = false,
  });

  final AppLocalizations l10n;
  final int itemCount;
  final int pendingSync;
  final VoidCallback? onClear;

  /// True on the SIDE cart only: its glyph carries [posCartFlyTargetKey].
  final bool attachFlyTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pair = PosThemePair.of(context);
    // 004: the approved LIGHT header — the cart glyph wears the action ember,
    // the title reads in ink, and the live count is an ember chip.
    final glyph = Icon(Icons.shopping_cart, color: pair.action, size: 20);

    return SizedBox(
      // A slim band, not a slab — the header keeps every operational element
      // (title, count, sync chip, Park, Clear) at 48px; the shift-status
      // pill below is its own row.
      height: 48,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          14,
          0,
          RestoflowSpacing.xs,
          0,
        ),
        child: Row(
          children: [
            if (attachFlyTarget)
              KeyedSubtree(key: posCartFlyTargetKey, child: glyph)
            else
              glyph,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.posCartTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: kRestoflowInk,
                ),
              ),
            ),
            if (itemCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                key: const Key('cart-item-count'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: RestoflowSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: pair.action,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  itemCount.toString(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            if (pendingSync > 0) ...[
              const SizedBox(width: 6),
              _PendingSyncChip(
                count: pendingSync,
                tooltip: l10n.posSyncPendingCount(pendingSync),
              ),
            ],
            const Spacer(),
            // PARKED-CARTS-001: the parked-orders list lives BESIDE Clear in
            // the cart header rather than as another global app-bar action. It
            // hides itself at zero, so a till that never parks sees no new
            // chrome.
            const ParkedOrdersButton(compact: true),
            // Destructive, so rank 4: a quiet ghost, never filled and never
            // louder than the title.
            //
            // ABSENT, not disabled, when it does not apply (empty cart, or a
            // frozen addition owning the cart) — that is the existing gating
            // and it is deliberately preserved over the mockup's disabled
            // depiction, because Clear's VISIBILITY is behaviour that other
            // suites pin.
            if (onClear != null)
              TextButton.icon(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: kRestoflowInk2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: RestoflowSpacing.sm,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                label: Text(
                  l10n.posClearCart,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
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
    // 004: the header is LIGHT now, so the pending chip reads in the shared
    // semantic WARNING tone — no shared status component is modified. It is
    // never hidden while work is outstanding, and it keeps its localized
    // tooltip + semantic label.
    final warning = RestoflowTone.warning.styleOf(Theme.of(context));
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: RestoflowSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: warning.container,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_queue,
                size: RestoflowIconSizes.xs,
                color: warning.onContainer,
              ),
              const SizedBox(width: RestoflowSpacing.xxs),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: warning.onContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // 004: the approved empty state — a 64px rounded-ivory glyph, the l10n
    // message (rendered verbatim so existing text finders keep working) and
    // ONE helper line telling the cashier how to begin. No large void, no
    // bordered card; the business condition is untouched.
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RestoflowSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFF4F2EC),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 28,
                color: Color(0xFFB4AD9F),
              ),
            ),
            const SizedBox(height: RestoflowSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: kRestoflowInk,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              l10n.posCartEmptyHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: kRestoflowInk3,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
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
    this.thumbnailUrl,
  });

  final CartLineView line;
  final AppLocalizations l10n;

  /// POS-REFERENCE-REDESIGN-002: the product photo for the row's leading
  /// thumbnail (presentation only; a quiet tinted glyph stands in when the
  /// item has no photo or it fails to load).
  final String? thumbnailUrl;

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

    // SURGERY-003: a FLAT order row (reference anatomy) — thumbnail, name +
    // meta, line total — with no card chrome of its own; the list's hairline
    // separators carry the rhythm.
    final summary = posCartModifierSummary(line.modifiers, line.currencyCode);
    return Padding(
      padding: dense
          ? const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.xs,
              RestoflowSpacing.xs,
              2,
              RestoflowSpacing.xs,
            )
          : const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.sm,
              RestoflowSpacing.sm,
              RestoflowSpacing.xs,
              RestoflowSpacing.sm,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // REFERENCE-REDESIGN-002 row anatomy: small photo, then name +
              // meta, then the line total. The thumbnail is presentation
              // only and never displaces the name (Expanded owns the width).
              _LineThumb(url: thumbnailUrl, dense: dense),
              SizedBox(width: dense ? RestoflowSpacing.sm : 10),
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
              // Prominent, but a step below the grand total's figure — 004:
              // the line total reads in the approved EMBER action colour
              // (money string byte-identical; only the ink changed).
              PosAmountText(
                formatted: lineTotalText,
                digitSize: 15,
                symbolSize: 11,
                color: PosThemePair.of(context).action,
              ),
            ],
          ),
          // Roomy: the meta on its own line. Dense: folded into the controls row.
          if (!dense) qtyUnit,
          // The selected modifiers (order-time snapshots) as ONE wrapped line
          // instead of one row each. The RENDERING clamps at two lines; the
          // DATA never does — the full string is the line's Semantics label and
          // its Tooltip, and Edit reopens the sheet listing every option.
          if (summary.isNotEmpty)
            Tooltip(
              message: summary,
              child: Semantics(
                container: true,
                label: summary,
                child: ExcludeSemantics(
                  child: Text(
                    summary,
                    key: Key('cart-line-modifiers-${line.lineId}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: kPosMutedBodyInk,
                      height: 1.35,
                      letterSpacing: 0,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
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
              PosQuantityStepper(
                quantity: line.quantity,
                l10n: l10n,
                dense: dense,
                // Cart-only: the minus and plus read as ONE control here. The
                // modifier sheet keeps its current appearance (Phase 3).
                onTrack: true,
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
              // 004: edit stays a neutral ghost; remove earns the approved
              // danger-TINTED bed (still quiet — a tint, not a filled danger
              // button). Both stay visible and tappable at their existing
              // targets.
              _LineActionButton(
                buttonKey: Key('cart-edit-${line.lineId}'),
                icon: Icons.edit_outlined,
                tooltip: l10n.posCartEditItem,
                color: kPosGhostIcon,
                dense: dense,
                onPressed: onEdit,
              ),
              _LineActionButton(
                buttonKey: Key('cart-remove-${line.lineId}'),
                icon: Icons.delete_outline,
                tooltip: l10n.posRemoveItem,
                color: RestoflowTone.danger.styleOf(theme).onContainer,
                background: RestoflowTone.danger.styleOf(theme).container,
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
/// POS-REFERENCE-REDESIGN-002 — the order row's leading thumbnail: the
/// product photo when one exists, else a quiet navy-tinted dish glyph. Fixed
/// square, smaller than the row, purely decorative (ExcludeSemantics — the
/// row already announces the item by name).
class _LineThumb extends StatelessWidget {
  const _LineThumb({required this.url, required this.dense});

  final String? url;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // 004: the approved 46px row thumbnail (48 in the roomier phone sheet).
    final side = dense ? 46.0 : 48.0;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: kPosSelectedTint,
        borderRadius: BorderRadius.circular(kPosTrackRadius),
      ),
      child: Icon(
        Icons.restaurant_menu,
        size: RestoflowIconSizes.sm,
        color: kRestoflowInk3,
      ),
    );
    // cacheWidth caps the decode at the thumbnail's device-pixel size (same
    // rule as the menu card's band image).
    final cacheW = (side * MediaQuery.devicePixelRatioOf(context)).round();
    return ExcludeSemantics(
      child: SizedBox(
        width: side,
        height: side,
        child: url == null
            ? fallback
            : ClipRRect(
                borderRadius: BorderRadius.circular(kPosTrackRadius),
                child: Image.network(
                  url!,
                  fit: BoxFit.cover,
                  cacheWidth: cacheW > 0 ? cacheW : null,
                  errorBuilder: (context, error, stackTrace) => fallback,
                ),
              ),
      ),
    );
  }
}

class _LineActionButton extends StatelessWidget {
  const _LineActionButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.background,
    this.dense = false,
  });

  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final Color color;

  /// 004: an optional tinted bed (the approved danger-tinted trash). The tap
  /// target and key are unchanged.
  final Color? background;

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
      style: background == null
          ? null
          : IconButton.styleFrom(
              backgroundColor: background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RestoflowRadii.sm),
              ),
            ),
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints(minWidth: side, minHeight: side),
      padding: EdgeInsets.zero,
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
    this.kitchenModeHint,
    this.onRetryKitchenMode,
    this.onPark,
  });

  /// PARKED-CARTS-001: sets the current unsent cart aside as a local draft.
  /// Null when parking does not apply (nothing to park, or an amendment owns
  /// the cart) — the action is then absent rather than shown disabled.
  final VoidCallback? onPark;

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): a localized reason shown while
  /// the kitchen workflow mode is not yet verified (Send is blocked). Null once
  /// resolved. [onRetryKitchenMode] is non-null only for the retryable
  /// (unavailable) case.
  final String? kitchenModeHint;
  final VoidCallback? onRetryKitchenMode;

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
            // REFERENCE-REDESIGN-002: the money block is ONE visually grouped
            // panel (quiet track fill) so subtotal/tax/total read as a unit.
            // POS-PREMIUM-VISUAL-POLISH-001: rows count up/down on change and
            // ALWAYS settle on the exact formatted amount (integer minor
            // units throughout — D-007). Keys and the final plain text are
            // byte-identical to the static rendering.
            Container(
              width: double.infinity,
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: kPosTotalsBed,
                borderRadius: BorderRadius.circular(RestoflowRadii.md),
                border: Border.all(color: kPosRowSeparator),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 004: the approved totals hierarchy — quiet subtotal (and
                  // tax when the branch adds one), a hairline rule, then ONE
                  // dominant الإجمالي row. The grand total is always present
                  // and always EQUALS subtotal+tax from the same integer
                  // math; with tax off that is exactly the subtotal (no
                  // invented figures — see tax_display_test).
                  PosAnimatedAmount(
                    minor: subtotalMinor,
                    builder: (context, minor) => _SummaryRow(
                      label: l10n.posCartSubtotal,
                      value: MoneyFormatter.formatMinor(minor, currencyCode),
                      valueKey: const Key('cart-subtotal'),
                    ),
                  ),
                  if (taxMinor > 0) ...[
                    const SizedBox(height: RestoflowSpacing.xs),
                    PosAnimatedAmount(
                      minor: taxMinor,
                      builder: (context, minor) => _SummaryRow(
                        label: taxLineLabel(l10n, taxRateBp),
                        value: MoneyFormatter.formatMinor(minor, currencyCode),
                        valueKey: const Key('cart-tax'),
                      ),
                    ),
                  ],
                  const Divider(
                    height: 13,
                    thickness: 1,
                    color: kPosRowSeparator,
                  ),
                  PosAnimatedAmount(
                    minor: subtotalMinor + taxMinor,
                    builder: (context, minor) => _TotalRow(
                      label: l10n.posGrandTotal,
                      value: MoneyFormatter.formatMinor(minor, currencyCode),
                      valueKey: const Key('cart-grand-total'),
                    ),
                  ),
                ],
              ),
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
            if (kitchenModeHint case final hint?) ...[
              Row(
                key: const Key('send-kitchen-mode-hint'),
                children: [
                  Icon(
                    Icons.sync,
                    size: RestoflowIconSizes.sm,
                    color: RestoflowTone.warning.styleOf(theme).accent,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: RestoflowTone.warning.styleOf(theme).accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onRetryKitchenMode != null)
                    TextButton(
                      key: const Key('kitchen-mode-retry'),
                      onPressed: onRetryKitchenMode,
                      child: Text(l10n.posKitchenModeRetry),
                    ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.xs),
            ],
            SizedBox(
              width: double.infinity,
              // POS-PREMIUM-VISUAL-POLISH-001: ONE shimmer on this screen —
              // a single sweep each time Send becomes actionable. One-shot
              // (never looping), clipped to Send's own radius, and skipped
              // entirely under reduced motion.
              child: PosShimmerSweep(
                trigger: onSend != null,
                borderRadius: BorderRadius.circular(kPosSendRadius),
                // 004: the approved EMBER GRADIENT + glow — the ONE glowing
                // control on screen (states/motion §4). Disabled drops both
                // for the flat muted bed.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kPosSendRadius),
                    gradient: onSend != null
                        ? PosThemePair.of(context).actionGradient
                        : null,
                    color: onSend != null ? null : kPosDisabledBg,
                    boxShadow: onSend != null
                        ? PosThemePair.of(context).actionGlow
                        : null,
                  ),
                  child: FilledButton.icon(
                    onPressed: onSend,
                    // POS-SUBMIT-GUARD-001: an explicit primary-tinted spinner (the
                    // disabled foreground would otherwise wash it out) marks the
                    // in-flight submit until the confirmation replaces the cart.
                    // POS-THEME-NAVBAR-POLISH-001: the rounded send glyph —
                    // softer, matching the rounded visual system; still the
                    // unmistakable "send" symbol, auto-mirrored inline-forward
                    // in RTL exactly like the sharp variant. Spinner and
                    // disabled states unchanged.
                    icon: submitting
                        ? RestoflowInlineSpinner(
                            color: theme.colorScheme.primary,
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(sendLabelOverride ?? l10n.posSendOrder),
                    // POS-LOCAL: the shared `RestoflowButtonStyles.big` is NOT
                    // modified — Send is simply the one control on this screen
                    // with a 54px height, an 800 weight and a glow, so it reads
                    // as the primary path without diluting the shared style.
                    //
                    // UI-ORANGE-BALANCE-POLISH-001: Send is THE next step on this
                    // screen, so it takes the brand accent fill. It is the only
                    // orange fill in the cart — Park stays a ghost, and the
                    // payment actions live on a different surface — which is what
                    // keeps the accent meaning "do this next" rather than merely
                    // "this is a button". Disabled still resolves to the POS grey
                    // below, so an unsendable cart never looks actionable.
                    style: RestoflowButtonStyles.accent(context)
                        .merge(RestoflowButtonStyles.big(context))
                        .copyWith(
                          minimumSize: WidgetStateProperty.all(
                            const Size.fromHeight(kPosSendHeight),
                          ),
                          // REFERENCE-REDESIGN-002: extend the THEME label
                          // style (a bare TextStyle dropped the display
                          // family, so Send never wore Tajawal).
                          textStyle: WidgetStateProperty.all(
                            theme.textTheme.labelLarge?.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          shape: WidgetStateProperty.all(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                kPosSendRadius,
                              ),
                            ),
                          ),
                          // 004: the fill moved to the GRADIENT wrapper (a
                          // FilledButton cannot paint a gradient), so the
                          // button itself is transparent in every state —
                          // the wrapper's decoration is what swaps between
                          // the ember gradient and the disabled bed.
                          backgroundColor: WidgetStateProperty.all(
                            Colors.transparent,
                          ),
                          shadowColor: WidgetStateProperty.all(
                            Colors.transparent,
                          ),
                          // The label ink comes from the PAIR: white on the
                          // dark actions, near-black on the light gold — so
                          // the CTA clears contrast under every preset.
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.disabled)
                                ? kPosDisabledFg
                                : PosThemePair.of(context).onAction,
                          ),
                        ),
                  ),
                ),
              ),
            ),
            // PARKED-CARTS-001: Park sits directly BELOW Send, as a secondary
            // (outlined) action — Send keeps its size, glow and primary filled
            // treatment, so the main path is never diluted. Absent entirely
            // when parking is not applicable (empty cart, amendment mode),
            // rather than shown as a dead control.
            if (onPark != null) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              SizedBox(
                width: double.infinity,
                // Ghost, not outlined: a full-width outlined button directly
                // under Send read as a second primary action. Applicability and
                // the callback are unchanged — it is still ABSENT, never
                // disabled, when parking does not apply.
                child: TextButton.icon(
                  key: const Key('park-cart-button'),
                  onPressed: onPark,
                  style: TextButton.styleFrom(
                    foregroundColor: kRestoflowInk2,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 17),
                  label: Text(
                    l10n.posParkOrder,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
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
        // 004: the ONE dominant figure — 21/800 EMBER digits per the
        // approved totals hierarchy. The formatted string itself is
        // unchanged (byte-identical MoneyFormatter output).
        PosAmountText(
          formatted: value,
          amountKey: valueKey,
          digitSize: 21,
          symbolSize: 13,
          letterSpacing: -0.4,
          color: PosThemePair.of(context).action,
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
        // Money stays an LTR island whatever the ambient direction (the
        // formatted string is byte-identical MoneyFormatter output).
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
