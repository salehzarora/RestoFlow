/// A single line in the local POS cart (RF-031): an item-level entry holding
/// immutable price/name SNAPSHOTS (DECISION D-008) and an integer quantity.
///
/// All money math is integer MINOR units (DECISION D-007) — no `double` / `num`
/// / `float` / `decimal`. Pure Dart: no Flutter, no Drift, no `data_local`.
library;

import 'cart_exceptions.dart';
import 'cart_snapshots.dart';

class CartLine {
  /// Builds a line from already-captured snapshot objects.
  ///
  /// [quantity] must be a positive integer. The modifier list is copied and
  /// exposed read-only so the line's snapshots stay immutable.
  CartLine({
    required this.lineId,
    required this.item,
    this.size,
    this.variant,
    List<ModifierOptionSnapshot> modifiers = const [],
    this.quantity = 1,
    this.note,
  }) : modifiers = List.unmodifiable(modifiers) {
    if (quantity < 1) {
      throw InvalidQuantityException(quantity);
    }
  }

  /// Convenience factory that snapshots plain values (ints/strings) at
  /// add-to-cart time, so callers never construct snapshot objects by hand and
  /// the cart never holds a live menu reference.
  ///
  /// When [modifierRules] is provided, the selected options are validated
  /// against each group's min/max/required rule (RF-031 enforcement) before the
  /// line is created.
  factory CartLine.snapshot({
    required String lineId,
    required String menuItemId,
    required String itemNameSnapshot,
    required int basePriceMinorSnapshot,
    required String currencyCodeSnapshot,
    String? sizeId,
    String? sizeNameSnapshot,
    int? sizePriceDeltaMinorSnapshot,
    String? variantId,
    String? variantNameSnapshot,
    int? variantPriceDeltaMinorSnapshot,
    List<ModifierOptionSnapshot> modifiers = const [],
    List<ModifierRule> modifierRules = const [],
    int quantity = 1,
    String? note,
  }) {
    final SizeSnapshot? size = sizeId == null
        ? null
        : SizeSnapshot(
            sizeId: sizeId,
            nameSnapshot: sizeNameSnapshot ?? '',
            priceDeltaMinorSnapshot: sizePriceDeltaMinorSnapshot ?? 0,
          );
    final VariantSnapshot? variant = variantId == null
        ? null
        : VariantSnapshot(
            variantId: variantId,
            nameSnapshot: variantNameSnapshot ?? '',
            priceDeltaMinorSnapshot: variantPriceDeltaMinorSnapshot ?? 0,
          );

    if (modifierRules.isNotEmpty) {
      validateModifierSelection(modifiers, modifierRules);
    }

    return CartLine(
      lineId: lineId,
      item: ItemSnapshot(
        menuItemId: menuItemId,
        nameSnapshot: itemNameSnapshot,
        basePriceMinorSnapshot: basePriceMinorSnapshot,
        currencyCodeSnapshot: currencyCodeSnapshot,
      ),
      size: size,
      variant: variant,
      modifiers: modifiers,
      quantity: quantity,
      note: note,
    );
  }

  /// Local identity of this line within its cart.
  final String lineId;

  /// Immutable item snapshot (price/name captured at add time).
  final ItemSnapshot item;

  /// Immutable size snapshot, if a size was chosen.
  final SizeSnapshot? size;

  /// Immutable variant snapshot, if a variant was chosen.
  final VariantSnapshot? variant;

  /// Immutable, read-only selected modifier-option snapshots.
  final List<ModifierOptionSnapshot> modifiers;

  /// Positive integer count of this line.
  final int quantity;

  /// Optional per-line kitchen note (free text captured at add time, e.g.
  /// "no salt"). Display data only — never money (additive, product-rescue
  /// sprint; null for every existing caller).
  final String? note;

  // Snapshot convenience accessors (mirror the required RF-031 field names).
  String get menuItemId => item.menuItemId;
  String get itemNameSnapshot => item.nameSnapshot;
  int get basePriceMinorSnapshot => item.basePriceMinorSnapshot;
  String get currencyCodeSnapshot => item.currencyCodeSnapshot;

  /// Unit price in integer MINOR units: base + size delta + variant delta +
  /// the sum of modifier-option deltas (each times its own quantity).
  int get unitPriceMinor {
    var total = basePriceMinorSnapshot;
    total += size?.priceDeltaMinorSnapshot ?? 0;
    total += variant?.priceDeltaMinorSnapshot ?? 0;
    for (final m in modifiers) {
      total += m.extendedPriceMinor;
    }
    return total;
  }

  /// Line total in integer MINOR units: [unitPriceMinor] × [quantity].
  int get lineTotalMinor => unitPriceMinor * quantity;

  /// Returns a copy of this line with a new [quantity], preserving every
  /// snapshot unchanged (so prices/names stay immutable across quantity edits).
  CartLine withQuantity(int newQuantity) => CartLine(
    lineId: lineId,
    item: item,
    size: size,
    variant: variant,
    modifiers: modifiers,
    quantity: newQuantity,
    note: note,
  );

  /// Validates [selected] modifier options against [rules]: a required group
  /// (or one with `minSelect > 0`) must have at least its effective minimum,
  /// and a bounded group must not exceed `maxSelect`. Throws
  /// [InvalidModifierSelectionException] on the first violation.
  static void validateModifierSelection(
    List<ModifierOptionSnapshot> selected,
    List<ModifierRule> rules,
  ) {
    for (final rule in rules) {
      final count = selected
          .where((o) => o.modifierId == rule.modifierId)
          .length;
      if (count < rule.effectiveMin) {
        throw InvalidModifierSelectionException(
          'modifier "${rule.modifierName}" requires at least '
          '${rule.effectiveMin} selection(s), got $count',
        );
      }
      if (rule.hasUpperBound && count > rule.maxSelect) {
        throw InvalidModifierSelectionException(
          'modifier "${rule.modifierName}" allows at most '
          '${rule.maxSelect} selection(s), got $count',
        );
      }
    }
  }
}
