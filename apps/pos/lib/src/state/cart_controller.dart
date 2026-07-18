import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_money/restoflow_money.dart';

import '../data/demo_menu.dart';
import 'pos_menu_provider.dart';
import 'submitted_order_view.dart';

/// One SELECTED modifier option on a cart line (demo-readiness sprint) — the
/// order-time snapshot (D-008) the payload sends as an `order_item_modifiers`
/// entry: option id + group/option name snapshots + a SIGNED minor-unit price
/// delta. [quantity] (modifier-quantity sprint) is how many units of THIS
/// option the cashier took (extra cheese ×2) — the frozen RF-052 total
/// formula the server recomputes is
/// `line_total = qty × unit + Σ(delta × modifier_qty) − discount`.
class SelectedModifier {
  const SelectedModifier({
    required this.optionId,
    required this.groupName,
    required this.optionName,
    required this.priceDeltaMinor,
    this.quantity = 1,
    this.kitchenMeat,
  });

  final String optionId;
  final String groupName;
  final String optionName;

  /// UNIT price delta (signed integer minor units, D-007).
  final int priceDeltaMinor;

  /// Units of this option (>= 1; quantity-enabled groups may exceed 1).
  final int quantity;

  /// KITCHEN-MEAT-001: the option's per-selection meat contribution (carried
  /// from its [PosModifierOption]), snapshotted into the order so the KDS can
  /// compute the whole-order meat total. Non-money; null when the option has no
  /// configured meat.
  final KitchenMeat? kitchenMeat;

  /// The delta this selection contributes to the line total (unit × units).
  int get totalDeltaMinor => priceDeltaMinor * quantity;

  /// The option name as rendered on cart/receipt/kitchen lines: the bare
  /// snapshot for a single unit, `name ×N` beyond (matches the KDS format).
  String get displayName =>
      quantity > 1 ? '$optionName ×$quantity' : optionName;
}

/// Immutable view of a single cart line for the POS UI.
///
/// Money fields are integer minor units (DECISION D-007); [unitPrice] and
/// [lineTotal] expose them as [Money] for type-safe display formatting.
/// [lineTotalMinor] uses the SERVER's formula: `qty × unit + Σmodifiers`.
class CartLineView {
  const CartLineView({
    required this.lineId,
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.currencyCode,
    this.modifiers = const <SelectedModifier>[],
    this.note,
  });

  final String lineId;
  final String menuItemId;
  final String name;
  final int quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;
  final String currencyCode;
  final List<SelectedModifier> modifiers;

  /// Optional per-item kitchen note the cashier typed ("بدون بصل") — shown
  /// under the cart line and sent as the payload item's `notes` (non-money).
  final String? note;

  Money get unitPrice => Money(unitPriceMinor, currencyCode);
  Money get lineTotal => Money(lineTotalMinor, currencyCode);
}

/// PSC-001C cart-safety — the immutable OWNER identity of the frozen addition
/// attempt that holds the cart mutation lock. A lock is never a bare boolean:
/// the token binds the lock to ONE exact attempt (its entry generation, parent
/// order and idempotency id), so a stale callback from an earlier attempt can
/// never clear or unlock a cart owned by a later one.
class CartLockOwner {
  const CartLockOwner({
    required this.generation,
    required this.orderId,
    required this.localOperationId,
  });

  final int generation;
  final String orderId;
  final String localOperationId;

  bool matches(CartLockOwner? other) =>
      other != null &&
      other.generation == generation &&
      other.orderId == orderId &&
      other.localOperationId == localOperationId;
}

/// The typed outcome of a normal cart mutation call — a refused mutation is
/// REPORTED, never silently ignored while the UI implies success.
enum CartMutationResult {
  applied,

  /// A frozen addition attempt owns the cart (sending / retryable failure /
  /// applied-awaiting-refresh): its payload is immutable, so the visible cart
  /// must stay exactly what was frozen. The UI shows the existing pending /
  /// refresh-required messaging and disables the controls.
  lockedByAddition,
}

/// Immutable snapshot of the cart for the POS UI (the Riverpod state value).
class CartViewState {
  const CartViewState({
    required this.lines,
    required this.subtotalMinor,
    required this.currencyCode,
    this.submittedOrder,
    this.lockedByAddition = false,
  });

  /// Builds an immutable view from the mutable domain [Cart], optionally
  /// carrying the last locally-submitted order snapshot (RF-101).
  /// [lineModifiers] adds each line's selected modifier snapshots (each delta
  /// counted × its own modifier quantity — RF-052) and [lineNotes] each
  /// line's optional cashier note.
  factory CartViewState.fromCart(
    Cart cart, {
    SubmittedOrderView? submittedOrder,
    Map<String, List<SelectedModifier>> lineModifiers = const {},
    Map<String, String> lineNotes = const {},
    bool lockedByAddition = false,
  }) {
    var modifiersTotal = 0;
    final views = cart.lines
        .map((line) {
          final mods = lineModifiers[line.lineId] ?? const <SelectedModifier>[];
          final modSum = mods.fold<int>(0, (sum, m) => sum + m.totalDeltaMinor);
          modifiersTotal += modSum;
          return CartLineView(
            lineId: line.lineId,
            menuItemId: line.menuItemId,
            name: line.itemNameSnapshot,
            quantity: line.quantity,
            unitPriceMinor: line.unitPriceMinor,
            lineTotalMinor: line.lineTotalMinor + modSum,
            currencyCode: line.currencyCodeSnapshot,
            modifiers: mods,
            note: lineNotes[line.lineId],
          );
        })
        .toList(growable: false);
    return CartViewState(
      lines: views,
      subtotalMinor: cart.subtotalMinor + modifiersTotal,
      currencyCode: cart.currencyCode,
      submittedOrder: submittedOrder,
      lockedByAddition: lockedByAddition,
    );
  }

  final List<CartLineView> lines;
  final int subtotalMinor;
  final String currencyCode;

  /// Snapshot of the last locally-submitted demo order, or null when none is
  /// being confirmed (RF-101). When non-null, the cart UI shows the confirmation.
  final SubmittedOrderView? submittedOrder;

  /// PSC-001C cart-safety: a frozen addition attempt owns the cart — every
  /// visible mutation control must be disabled (the controller refuses the
  /// mutation regardless).
  final bool lockedByAddition;

  bool get hasSubmittedOrder => submittedOrder != null;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// Total number of physical items (sum of line quantities).
  int get itemCount => lines.fold(0, (count, line) => count + line.quantity);

  /// Non-authoritative subtotal preview as [Money] (no tax/discounts; the
  /// authoritative total is the server/money engine's job — RF-032/RF-036).
  Money get subtotal => Money(subtotalMinor, currencyCode);
}

/// Riverpod controller holding the in-memory POS draft [Cart] (RF-031) and
/// exposing an immutable [CartViewState].
///
/// The domain [Cart] is mutable with `void` mutators, so after each mutation we
/// re-emit a fresh [CartViewState] for Riverpod to diff. In-memory demo only —
/// no Supabase, no auth, no order submission, no payments, no persistence.
/// PILOT-OPERATIONS-CORRECTIONS-001 — an immutable snapshot of a cart draft,
/// captured at submit time so a rejected (item_unavailable) attempt can be
/// restored for deliberate correction. Carries the rebuildable truth per line.
class CartDraftSnapshot {
  const CartDraftSnapshot({required this.currencyCode, required this.lines});

  final String currencyCode;
  final List<CartDraftLine> lines;

  bool get isEmpty => lines.isEmpty;
}

class CartDraftLine {
  const CartDraftLine({
    required this.menuItemId,
    required this.name,
    required this.basePriceMinor,
    required this.quantity,
    this.modifiers = const <SelectedModifier>[],
    this.note,
  });

  final String menuItemId;
  final String name;
  final int basePriceMinor;
  final int quantity;
  final List<SelectedModifier> modifiers;
  final String? note;
}

class CartController extends Notifier<CartViewState> {
  late Cart _cart;
  int _lineSeq = 0;
  int _orderSeq = 0;
  SubmittedOrderView? _submittedOrder;

  /// PSC-001C cart-safety: the frozen addition attempt currently owning the
  /// cart, or null when the cart is freely editable. While held, EVERY normal
  /// mutation entry point refuses ([CartMutationResult.lockedByAddition]) —
  /// the frozen payload and the visible cart must stay identical, and no
  /// unrelated line may be introduced only to be cleared on reconciliation.
  CartLockOwner? _lockOwner;

  bool get _locked => _lockOwner != null;

  /// Selected modifier snapshots per line id (the domain [Cart] predates
  /// modifiers; the app carries them alongside — D-008 snapshots).
  final Map<String, List<SelectedModifier>> _lineModifiers = {};

  /// Optional cashier note per line id ("بدون بصل") — carried alongside like
  /// the modifiers; sent as the payload item's `notes`.
  final Map<String, String> _lineNotes = {};

  /// The ACTIVE menu currency (real backend currency in real mode; the demo
  /// constant otherwise). Read at cart (re)creation so price snapshots and the
  /// cart currency always agree with the menu being sold from (D-007/D-008).
  String _activeCurrency() =>
      ref.read(posMenuProvider).valueOrNull?.currencyCode ?? kDemoCurrencyCode;

  Cart _freshCart() => Cart(
    orderId: 'demo-order',
    organizationId: 'demo-org',
    restaurantId: 'demo-restaurant',
    branchId: 'demo-branch',
    currencyCode: _activeCurrency(),
  );

  @override
  CartViewState build() {
    _cart = _freshCart();
    _submittedOrder = null;
    _lineModifiers.clear();
    _lineNotes.clear();
    _lockOwner = null;
    return CartViewState.fromCart(_cart);
  }

  // -------------------------------------------------------------------------
  // PSC-001C cart-safety — the addition mutation lock (owner-token, never a
  // bare boolean). Acquired atomically with the payload freeze by the
  // AdditionController; released ONLY by the matching owner (explicit cancel
  // of a retryable failure, or the privileged post-reconciliation clear).
  // -------------------------------------------------------------------------

  /// Acquires the mutation lock for [owner]. Fails (false, nothing changes)
  /// when a DIFFERENT attempt already owns the cart; re-acquiring with the
  /// SAME identity is an idempotent success (a retry of the frozen attempt).
  bool lockForAddition(CartLockOwner owner) {
    final current = _lockOwner;
    if (current != null && !owner.matches(current)) return false;
    _lockOwner = owner;
    _emit();
    return true;
  }

  /// Releases the lock with the matching [owner] token, leaving the cart
  /// lines INTACT (an explicit cancel keeps the cashier's work). Fails closed
  /// (false, still locked) on a token mismatch; a no-op success when nothing
  /// is locked.
  bool unlockForAddition(CartLockOwner owner) {
    final current = _lockOwner;
    if (current == null) return true;
    if (!owner.matches(current)) return false;
    _lockOwner = null;
    _emit();
    return true;
  }

  /// PRIVILEGED owner-token cleanup: clears the submitted cart state AND
  /// releases the lock in one step — only for the matching [owner], after the
  /// authoritative reconciliation verified the addition. Fails closed (false,
  /// cart and lock untouched) on any mismatch: a stale attempt-A callback can
  /// never clear a cart owned by attempt B.
  bool clearForAddition(CartLockOwner owner) {
    final current = _lockOwner;
    if (current == null || !owner.matches(current)) return false;
    _lockOwner = null;
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    _emit();
    return true;
  }

  /// Adds [item] to the cart. If a PLAIN line (no modifiers) for the same menu
  /// item already exists, its quantity is incremented instead of adding a
  /// duplicate line. Adding an item while a confirmation is showing dismisses
  /// it and starts a fresh order.
  CartMutationResult addItem(DemoMenuItem item) {
    if (_locked) return CartMutationResult.lockedByAddition;
    _submittedOrder = null;
    // An EMPTY cart re-binds to the active menu currency before its first line
    // (the menu can finish loading after the cart was first built).
    if (_cart.lines.isEmpty && _cart.currencyCode != _activeCurrency()) {
      _cart = _freshCart();
    }
    final existing = _lineForMenuItem(item.id);
    if (existing != null &&
        !(_lineModifiers[existing.lineId]?.isNotEmpty ?? false) &&
        !_lineNotes.containsKey(existing.lineId)) {
      _cart.changeQuantity(existing.lineId, existing.quantity + 1);
    } else {
      _cart.addLine(
        CartLine.snapshot(
          lineId: 'line-${_lineSeq++}',
          menuItemId: item.id,
          itemNameSnapshot: item.name,
          basePriceMinorSnapshot: item.priceMinor,
          currencyCodeSnapshot: _cart.currencyCode,
        ),
      );
    }
    _emit();
    return CartMutationResult.applied;
  }

  /// Adds a CONFIGURED [item] with its selected [modifiers] and optional
  /// cashier [note] as its OWN line (never merged — each configured item is
  /// priced/kitchen-routed on its own; the RF-052 formula counts each
  /// modifier's delta × its quantity once per line).
  CartMutationResult addItemWithModifiers(
    DemoMenuItem item,
    List<SelectedModifier> modifiers, {
    String? note,
  }) {
    if (_locked) return CartMutationResult.lockedByAddition;
    final trimmedNote = note?.trim();
    final hasNote = trimmedNote != null && trimmedNote.isNotEmpty;
    if (modifiers.isEmpty && !hasNote) return addItem(item);
    _submittedOrder = null;
    if (_cart.lines.isEmpty && _cart.currencyCode != _activeCurrency()) {
      _cart = _freshCart();
    }
    final lineId = 'line-${_lineSeq++}';
    _cart.addLine(
      CartLine.snapshot(
        lineId: lineId,
        menuItemId: item.id,
        itemNameSnapshot: item.name,
        basePriceMinorSnapshot: item.priceMinor,
        currencyCodeSnapshot: _cart.currencyCode,
      ),
    );
    _lineModifiers[lineId] = List.unmodifiable(modifiers);
    if (hasNote) _lineNotes[lineId] = trimmedNote;
    _emit();
    return CartMutationResult.applied;
  }

  /// TABLET-UX-001 (A): replaces the selected [modifiers] and optional [note] on
  /// an EXISTING cart line, in place — never a new/duplicate line. Preserves the
  /// line's position, quantity, base price snapshot, and currency; only its
  /// modifier snapshots + note change, so the line total recomputes through the
  /// same RF-052 formula. No-op when [lineId] is gone. Used by the cart's Edit
  /// action, which reopens the customization sheet prefilled with this line.
  CartMutationResult updateLineModifiers(
    String lineId,
    List<SelectedModifier> modifiers, {
    String? note,
  }) {
    if (_locked) return CartMutationResult.lockedByAddition;
    if (_lineById(lineId) == null) return CartMutationResult.applied;
    if (modifiers.isEmpty) {
      _lineModifiers.remove(lineId);
    } else {
      _lineModifiers[lineId] = List.unmodifiable(modifiers);
    }
    final trimmedNote = note?.trim();
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      _lineNotes[lineId] = trimmedNote;
    } else {
      _lineNotes.remove(lineId);
    }
    _emit();
    return CartMutationResult.applied;
  }

  /// Increases the quantity of [lineId] by one.
  CartMutationResult increaseQuantity(String lineId) {
    if (_locked) return CartMutationResult.lockedByAddition;
    final line = _lineById(lineId);
    if (line == null) return CartMutationResult.applied;
    _cart.changeQuantity(lineId, line.quantity + 1);
    _emit();
    return CartMutationResult.applied;
  }

  /// Decreases the quantity of [lineId] by one; removes the line at quantity 1.
  CartMutationResult decreaseQuantity(String lineId) {
    if (_locked) return CartMutationResult.lockedByAddition;
    final line = _lineById(lineId);
    if (line == null) return CartMutationResult.applied;
    if (line.quantity <= 1) {
      _cart.removeLine(lineId);
    } else {
      _cart.changeQuantity(lineId, line.quantity - 1);
    }
    _emit();
    return CartMutationResult.applied;
  }

  /// Removes the line [lineId] entirely.
  CartMutationResult removeLine(String lineId) {
    if (_locked) return CartMutationResult.lockedByAddition;
    if (_lineById(lineId) == null) return CartMutationResult.applied;
    _cart.removeLine(lineId);
    _lineModifiers.remove(lineId);
    _lineNotes.remove(lineId);
    _emit();
    return CartMutationResult.applied;
  }

  /// Clears the cart by rebuilding a fresh draft (the domain Cart has no
  /// `clear()`); line ids keep advancing so they stay unique. While a frozen
  /// addition attempt owns the cart this REFUSES — the privileged
  /// [clearForAddition] is the only clear a locked cart accepts.
  CartMutationResult clear() {
    if (_locked) return CartMutationResult.lockedByAddition;
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    _emit();
    return CartMutationResult.applied;
  }

  /// PILOT-OPERATIONS-CORRECTIONS-001: capture the current cart as an immutable
  /// draft snapshot BEFORE a submit clears it, so a permanently-rejected submit
  /// (item_unavailable) can be RESTORED for deliberate correction rather than
  /// forcing the cashier to re-key the whole order.
  CartDraftSnapshot captureDraft() => CartDraftSnapshot(
    currencyCode: _cart.currencyCode,
    lines: <CartDraftLine>[
      for (final line in _cart.lines)
        CartDraftLine(
          menuItemId: line.menuItemId,
          name: line.itemNameSnapshot,
          basePriceMinor: line.basePriceMinorSnapshot,
          quantity: line.quantity,
          modifiers: _lineModifiers[line.lineId] ?? const <SelectedModifier>[],
          note: _lineNotes[line.lineId],
        ),
    ],
  );

  /// PILOT-OPERATIONS-CORRECTIONS-001: rebuild the cart from a [CartDraftSnapshot]
  /// (products, quantities, modifiers, notes). Idempotent replacement — it always
  /// REPLACES the current cart, so a repeated "Back to cart" cannot duplicate
  /// lines. Line ids keep advancing so they stay unique.
  CartMutationResult restoreDraft(CartDraftSnapshot draft) {
    if (_locked) return CartMutationResult.lockedByAddition;
    _cart = Cart(
      orderId: 'demo-order',
      organizationId: 'demo-org',
      restaurantId: 'demo-restaurant',
      branchId: 'demo-branch',
      currencyCode: draft.currencyCode,
    );
    _lineModifiers.clear();
    _lineNotes.clear();
    for (final l in draft.lines) {
      final lineId = 'line-${_lineSeq++}';
      _cart.addLine(
        CartLine.snapshot(
          lineId: lineId,
          menuItemId: l.menuItemId,
          itemNameSnapshot: l.name,
          basePriceMinorSnapshot: l.basePriceMinor,
          currencyCodeSnapshot: draft.currencyCode,
        ),
      );
      if (l.quantity > 1) _cart.changeQuantity(lineId, l.quantity);
      if (l.modifiers.isNotEmpty) {
        _lineModifiers[lineId] = List.unmodifiable(l.modifiers);
      }
      final note = l.note;
      if (note != null && note.isNotEmpty) _lineNotes[lineId] = note;
    }
    _submittedOrder = null;
    _emit();
    return CartMutationResult.applied;
  }

  /// Locally "submits" the current cart (RF-101): materializes an in-memory
  /// [LocalOrder] from the cart, snapshots it into a [SubmittedOrderView] with a
  /// local/provisional demo number, then empties the cart so the confirmation
  /// stands on its own. No backend, RPC, payment, kitchen, printer, or
  /// persistence — purely a visible demo confirmation. No-op on an empty cart.
  CartMutationResult submitOrder({
    OrderType orderType = OrderType.takeaway,
    String? tableLabel,
    String? customerName,
    String? orderNumber,
    String? outboxEntryId,
    String? localOperationId,
    String? orderId,
    int taxTotalMinor = 0,
    int taxRateBp = 0,
  }) {
    if (_locked) return CartMutationResult.lockedByAddition;
    if (_cart.isEmpty) return CartMutationResult.applied;
    final order = LocalOrder.submitFromCart(_cart, orderType: orderType);
    _orderSeq++;
    // RF-115: the outbox controller is the numbering authority for the real
    // submit flow; fall back to a local number for the RF-101 in-memory path.
    final resolvedNumber =
        orderNumber ?? 'DEMO-${_orderSeq.toString().padLeft(4, '0')}';
    // Line totals mirror the RF-052 server formula (each modifier delta
    // counted × its own quantity, once per line).
    var modifiersTotal = 0;
    final lines = <SubmittedLineView>[];
    for (final item in order.items) {
      // LocalOrderItem.orderItemId carries the source cart line id.
      final mods =
          _lineModifiers[item.orderItemId] ?? const <SelectedModifier>[];
      final modSum = mods.fold<int>(0, (sum, m) => sum + m.totalDeltaMinor);
      modifiersTotal += modSum;
      lines.add(
        SubmittedLineView(
          name: item.itemNameSnapshot,
          quantity: item.quantity,
          lineTotalMinor: item.lineTotalMinorPreview + modSum,
          currencyCode: item.currencyCodeSnapshot,
          // `name ×N` snapshots — quantity rides the display string so the
          // confirmation/receipt/print paths all show it unchanged.
          modifiers: [for (final m in mods) m.displayName],
          note: _lineNotes[item.orderItemId],
        ),
      );
    }
    _submittedOrder = SubmittedOrderView(
      orderNumber: resolvedNumber,
      orderType: order.orderType,
      tableLabel: tableLabel,
      customerName: customerName,
      outboxEntryId: outboxEntryId,
      localOperationId: localOperationId,
      orderId: orderId,
      currencyCode: order.currencyCode,
      subtotalMinor: order.subtotalMinorPreview + modifiersTotal,
      // RF-117: tax computed at submit from the branch setting (0 when disabled).
      taxTotalMinor: taxTotalMinor,
      taxRateBp: taxRateBp,
      lines: lines,
    );
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    _emit();
    return CartMutationResult.applied;
  }

  /// Finding 1 (PILOT-OPERATIONS-CORRECTIONS-001): build a [SubmittedOrderView] from a
  /// previously-captured [CartDraftSnapshot] WITHOUT mutating the live cart. This is used
  /// only when a submit result lands AFTER a PIN handover on the same till: the ORIGINAL
  /// session's recent-orders row is materialized from ITS captured draft, so the CURRENT
  /// session's cart, setup, and confirmation are never touched. The money arithmetic
  /// mirrors [submitOrder] EXACTLY — integer minor units, base price × line quantity plus
  /// each modifier delta counted once per line (D-007) — so a recovered row shows the same
  /// figures it would have shown in its own session.
  SubmittedOrderView viewFromDraft({
    required CartDraftSnapshot draft,
    OrderType orderType = OrderType.takeaway,
    String? tableLabel,
    String? customerName,
    String? orderNumber,
    String? outboxEntryId,
    String? localOperationId,
    String? orderId,
    int taxTotalMinor = 0,
    int taxRateBp = 0,
  }) {
    var subtotal = 0;
    final lines = <SubmittedLineView>[];
    for (final l in draft.lines) {
      final modSum = l.modifiers.fold<int>(
        0,
        (sum, m) => sum + m.totalDeltaMinor,
      );
      final lineTotal = l.basePriceMinor * l.quantity + modSum;
      subtotal += lineTotal;
      lines.add(
        SubmittedLineView(
          name: l.name,
          quantity: l.quantity,
          lineTotalMinor: lineTotal,
          currencyCode: draft.currencyCode,
          modifiers: [for (final m in l.modifiers) m.displayName],
          note: l.note,
        ),
      );
    }
    return SubmittedOrderView(
      orderNumber: orderNumber ?? 'DEMO-0000',
      orderType: orderType,
      tableLabel: tableLabel,
      customerName: customerName,
      outboxEntryId: outboxEntryId,
      localOperationId: localOperationId,
      orderId: orderId,
      currencyCode: draft.currencyCode,
      subtotalMinor: subtotal,
      taxTotalMinor: taxTotalMinor,
      taxRateBp: taxRateBp,
      lines: lines,
    );
  }

  /// Updates the confirmed order's totals after an order-level discount is
  /// applied (RF-117 part C). In real mode the values are the
  /// SERVER-AUTHORITATIVE `discount_total_minor` (+ recomputed grand) from
  /// `apply_discount`; in demo mode they are computed locally with the same
  /// clamp. No-op when no order is being confirmed.
  void applyOrderDiscount({required int discountTotalMinor}) {
    final current = _submittedOrder;
    if (current == null) return;
    _submittedOrder = current.copyWith(discountTotalMinor: discountTotalMinor);
    _emit();
  }

  /// Dismisses the confirmation and returns to an empty cart (RF-101).
  CartMutationResult startNewOrder() {
    if (_locked) return CartMutationResult.lockedByAddition;
    _submittedOrder = null;
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    _emit();
    return CartMutationResult.applied;
  }

  CartLine? _lineById(String lineId) {
    for (final line in _cart.lines) {
      if (line.lineId == lineId) return line;
    }
    return null;
  }

  CartLine? _lineForMenuItem(String menuItemId) {
    for (final line in _cart.lines) {
      if (line.menuItemId == menuItemId) return line;
    }
    return null;
  }

  void _emit() => state = CartViewState.fromCart(
    _cart,
    submittedOrder: _submittedOrder,
    lineModifiers: _lineModifiers,
    lineNotes: _lineNotes,
    lockedByAddition: _locked,
  );
}

/// Provider for the in-memory POS cart controller (demo-only).
final cartControllerProvider = NotifierProvider<CartController, CartViewState>(
  CartController.new,
);
