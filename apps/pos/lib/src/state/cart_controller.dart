import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_money/restoflow_money.dart';

import '../data/demo_menu.dart';
import 'submitted_order_view.dart';

/// Immutable view of a single cart line for the POS UI.
///
/// Money fields are integer minor units (DECISION D-007); [unitPrice] and
/// [lineTotal] expose them as [Money] for type-safe display formatting.
class CartLineView {
  const CartLineView({
    required this.lineId,
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.currencyCode,
  });

  final String lineId;
  final String menuItemId;
  final String name;
  final int quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;
  final String currencyCode;

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
  factory CartViewState.fromCart(
    Cart cart, {
    SubmittedOrderView? submittedOrder,
  }) {
    final views = cart.lines
        .map(
          (line) => CartLineView(
            lineId: line.lineId,
            menuItemId: line.menuItemId,
            name: line.itemNameSnapshot,
            quantity: line.quantity,
            unitPriceMinor: line.unitPriceMinor,
            lineTotalMinor: line.lineTotalMinor,
            currencyCode: line.currencyCodeSnapshot,
          ),
        )
        .toList(growable: false);
    return CartViewState(
      lines: views,
      subtotalMinor: cart.subtotalMinor,
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

  Cart _freshCart() => Cart(
    orderId: 'demo-order',
    organizationId: 'demo-org',
    restaurantId: 'demo-restaurant',
    branchId: 'demo-branch',
    currencyCode: kDemoCurrencyCode,
  );

  @override
  CartViewState build() {
    _cart = _freshCart();
    _submittedOrder = null;
    return CartViewState.fromCart(_cart);
  }

  /// Adds [item] to the cart. If a line for the same menu item already exists,
  /// its quantity is incremented instead of adding a duplicate line. Adding an
  /// item while a confirmation is showing dismisses it and starts a fresh order.
  void addItem(DemoMenuItem item) {
    _submittedOrder = null;
    final existing = _lineForMenuItem(item.id);
    if (existing != null) {
      _cart.changeQuantity(existing.lineId, existing.quantity + 1);
    } else {
      _cart.addLine(
        CartLine.snapshot(
          lineId: 'line-${_lineSeq++}',
          menuItemId: item.id,
          itemNameSnapshot: item.name,
          basePriceMinorSnapshot: item.priceMinor,
          currencyCodeSnapshot: kDemoCurrencyCode,
        ),
      );
    }
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
    _emit();
  }

  /// Clears the cart by rebuilding a fresh draft (the domain Cart has no
  /// `clear()`); line ids keep advancing so they stay unique.
  void clear() {
    _cart = _freshCart();
    _emit();
  }

  /// Locally "submits" the current cart (RF-101): materializes an in-memory
  /// [LocalOrder] from the cart, snapshots it into a [SubmittedOrderView] with a
  /// local/provisional demo number, then empties the cart so the confirmation
  /// stands on its own. No backend, RPC, payment, kitchen, printer, or
  /// persistence — purely a visible demo confirmation. No-op on an empty cart.
  void submitOrder({OrderType orderType = OrderType.takeaway}) {
    if (_cart.isEmpty) return;
    final order = LocalOrder.submitFromCart(_cart, orderType: orderType);
    _orderSeq++;
    final orderNumber = 'DEMO-${_orderSeq.toString().padLeft(4, '0')}';
    _submittedOrder = SubmittedOrderView(
      orderNumber: orderNumber,
      currencyCode: order.currencyCode,
      subtotalMinor: order.subtotalMinorPreview,
      lines: order.items
          .map(
            (item) => SubmittedLineView(
              name: item.itemNameSnapshot,
              quantity: item.quantity,
              lineTotalMinor: item.lineTotalMinorPreview,
              currencyCode: item.currencyCodeSnapshot,
            ),
          )
          .toList(growable: false),
    );
    _cart = _freshCart();
    _emit();
  }

  /// Dismisses the confirmation and returns to an empty cart (RF-101).
  void startNewOrder() {
    _submittedOrder = null;
    _cart = _freshCart();
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

  void _emit() =>
      state = CartViewState.fromCart(_cart, submittedOrder: _submittedOrder);
}

/// Provider for the in-memory POS cart controller (demo-only).
final cartControllerProvider = NotifierProvider<CartController, CartViewState>(
  CartController.new,
);
