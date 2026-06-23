import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_money/restoflow_money.dart';

import '../data/demo_menu.dart';

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
  });

  /// Builds an immutable view from the mutable domain [Cart].
  factory CartViewState.fromCart(Cart cart) {
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
    );
  }

  final List<CartLineView> lines;
  final int subtotalMinor;
  final String currencyCode;

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
    return CartViewState.fromCart(_cart);
  }

  /// Adds [item] to the cart. If a line for the same menu item already exists,
  /// its quantity is incremented instead of adding a duplicate line.
  void addItem(DemoMenuItem item) {
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

  void _emit() => state = CartViewState.fromCart(_cart);
}

/// Provider for the in-memory POS cart controller (demo-only).
final cartControllerProvider = NotifierProvider<CartController, CartViewState>(
  CartController.new,
);
