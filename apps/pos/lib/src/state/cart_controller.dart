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
  });

  final String optionId;
  final String groupName;
  final String optionName;

  /// UNIT price delta (signed integer minor units, D-007).
  final int priceDeltaMinor;

  /// Units of this option (>= 1; quantity-enabled groups may exceed 1).
  final int quantity;

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

/// Immutable snapshot of the cart for the POS UI (the Riverpod state value).
class CartViewState {
  const CartViewState({
    required this.lines,
    required this.subtotalMinor,
    required this.currencyCode,
    this.submittedOrder,
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
    );
  }

  final List<CartLineView> lines;
  final int subtotalMinor;
  final String currencyCode;

  /// Snapshot of the last locally-submitted demo order, or null when none is
  /// being confirmed (RF-101). When non-null, the cart UI shows the confirmation.
  final SubmittedOrderView? submittedOrder;

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
class CartController extends Notifier<CartViewState> {
  late Cart _cart;
  int _lineSeq = 0;
  int _orderSeq = 0;
  SubmittedOrderView? _submittedOrder;

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
    return CartViewState.fromCart(_cart);
  }

  /// Adds [item] to the cart. If a PLAIN line (no modifiers) for the same menu
  /// item already exists, its quantity is incremented instead of adding a
  /// duplicate line. Adding an item while a confirmation is showing dismisses
  /// it and starts a fresh order.
  void addItem(DemoMenuItem item) {
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
  }

  /// Adds a CONFIGURED [item] with its selected [modifiers] and optional
  /// cashier [note] as its OWN line (never merged — each configured item is
  /// priced/kitchen-routed on its own; the RF-052 formula counts each
  /// modifier's delta × its quantity once per line).
  void addItemWithModifiers(
    DemoMenuItem item,
    List<SelectedModifier> modifiers, {
    String? note,
  }) {
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
  }

  /// Increases the quantity of [lineId] by one.
  void increaseQuantity(String lineId) {
    final line = _lineById(lineId);
    if (line == null) return;
    _cart.changeQuantity(lineId, line.quantity + 1);
    _emit();
  }

  /// Decreases the quantity of [lineId] by one; removes the line at quantity 1.
  void decreaseQuantity(String lineId) {
    final line = _lineById(lineId);
    if (line == null) return;
    if (line.quantity <= 1) {
      _cart.removeLine(lineId);
    } else {
      _cart.changeQuantity(lineId, line.quantity - 1);
    }
    _emit();
  }

  /// Removes the line [lineId] entirely.
  void removeLine(String lineId) {
    if (_lineById(lineId) == null) return;
    _cart.removeLine(lineId);
    _lineModifiers.remove(lineId);
    _lineNotes.remove(lineId);
    _emit();
  }

  /// Clears the cart by rebuilding a fresh draft (the domain Cart has no
  /// `clear()`); line ids keep advancing so they stay unique.
  void clear() {
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    _emit();
  }

  /// Locally "submits" the current cart (RF-101): materializes an in-memory
  /// [LocalOrder] from the cart, snapshots it into a [SubmittedOrderView] with a
  /// local/provisional demo number, then empties the cart so the confirmation
  /// stands on its own. No backend, RPC, payment, kitchen, printer, or
  /// persistence — purely a visible demo confirmation. No-op on an empty cart.
  void submitOrder({
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
    if (_cart.isEmpty) return;
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
  void startNewOrder() {
    _submittedOrder = null;
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    _emit();
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
  );
}

/// Provider for the in-memory POS cart controller (demo-only).
final cartControllerProvider = NotifierProvider<CartController, CartViewState>(
  CartController.new,
);
