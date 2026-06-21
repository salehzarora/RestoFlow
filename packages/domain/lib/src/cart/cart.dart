/// The local POS draft-order aggregate (RF-031): the order-level entry that
/// holds the tenant/currency context and a list of item-level [CartLine]s.
///
/// This is an IN-MEMORY draft only — it is **not** submitted, persisted, synced,
/// or a backend order (that is RF-032). Money is integer MINOR units throughout
/// (DECISION D-007). Pure Dart: no Flutter, no Drift, no `data_local`.
library;

import 'cart_exceptions.dart';
import 'cart_line.dart';

class Cart {
  /// Creates an empty draft cart.
  ///
  /// [orderId] is injected by the caller (a client UUID per DECISION D-010);
  /// this package adds no UUID dependency. [currencyCode] fixes the cart's
  /// single currency — every line added must match it.
  Cart({
    required this.orderId,
    required this.organizationId,
    required this.restaurantId,
    required this.currencyCode,
    this.branchId,
  }) {
    if (currencyCode.isEmpty) {
      throw const CurrencyMismatchException('cart currency must not be empty');
    }
  }

  /// Injected client-generated order id (DECISION D-010); stable for RF-032.
  final String orderId;

  /// Tenant scope (DECISION D-001/D-002). `branchId` may be null.
  final String organizationId;
  final String restaurantId;
  final String? branchId;

  /// The cart's single ISO 4217 currency (Q-007: one currency per order).
  final String currencyCode;

  final List<CartLine> _lines = [];

  /// Read-only view of the item-level lines.
  List<CartLine> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;
  int get lineCount => _lines.length;

  /// Adds an item-level [line]. Enforces the single-currency invariant and
  /// rejects a duplicate `lineId`.
  void addLine(CartLine line) {
    if (line.currencyCodeSnapshot != currencyCode) {
      throw CurrencyMismatchException.between(
        currencyCode,
        line.currencyCodeSnapshot,
      );
    }
    if (_lines.any((l) => l.lineId == line.lineId)) {
      throw DuplicateLineException(line.lineId);
    }
    _lines.add(line);
  }

  /// Removes the line with [lineId]. Throws [LineNotFoundException] if absent.
  void removeLine(String lineId) {
    final index = _lines.indexWhere((l) => l.lineId == lineId);
    if (index < 0) {
      throw LineNotFoundException(lineId);
    }
    _lines.removeAt(index);
  }

  /// Changes the [quantity] of the line with [lineId], preserving its
  /// snapshots. Throws [LineNotFoundException] if absent and
  /// [InvalidQuantityException] if [quantity] is not positive.
  void changeQuantity(String lineId, int quantity) {
    final index = _lines.indexWhere((l) => l.lineId == lineId);
    if (index < 0) {
      throw LineNotFoundException(lineId);
    }
    _lines[index] = _lines[index].withQuantity(quantity);
  }

  /// The cart subtotal in integer MINOR units: the sum of every line total.
  ///
  /// This is a non-authoritative preview only. Discounts, tax, service charge,
  /// rounding, and the authoritative total are the money engine's job (RF-036);
  /// the server recomputes and validates on submission (RF-032).
  int get subtotalMinor =>
      _lines.fold(0, (sum, line) => sum + line.lineTotalMinor);
}
