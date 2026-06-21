/// Immutable price/name SNAPSHOTS captured when a line is added to the cart
/// (RF-031, DECISION D-008). Each snapshot copies plain values out of the menu
/// at add-to-cart time; it holds **no live reference** to any menu row, so a
/// later menu price/name change never alters an existing cart line.
///
/// All money is integer MINOR units (DECISION D-007) — there is no `double` /
/// `num` / `float` / `decimal` anywhere in this file. These are pure-Dart value
/// objects: no Flutter, no Drift, no `data_local` imports.
library;

import 'cart_exceptions.dart';

/// Snapshot of the chosen menu item at add-to-cart time (DECISION D-008).
class ItemSnapshot {
  ItemSnapshot({
    required this.menuItemId,
    required this.nameSnapshot,
    required this.basePriceMinorSnapshot,
    required this.currencyCodeSnapshot,
  }) {
    if (currencyCodeSnapshot.isEmpty) {
      throw const CurrencyMismatchException('item snapshot has empty currency');
    }
  }

  /// Reference to the source menu item (id only; price comes from the snapshot).
  final String menuItemId;

  /// Display name captured at add time (immutable for the line's life).
  final String nameSnapshot;

  /// Base price in integer MINOR units, snapshotted (DECISION D-007/D-008).
  final int basePriceMinorSnapshot;

  /// ISO 4217 currency in effect for this line; the whole cart is single-currency.
  final String currencyCodeSnapshot;

  @override
  bool operator ==(Object other) =>
      other is ItemSnapshot &&
      other.menuItemId == menuItemId &&
      other.nameSnapshot == nameSnapshot &&
      other.basePriceMinorSnapshot == basePriceMinorSnapshot &&
      other.currencyCodeSnapshot == currencyCodeSnapshot;

  @override
  int get hashCode => Object.hash(
    menuItemId,
    nameSnapshot,
    basePriceMinorSnapshot,
    currencyCodeSnapshot,
  );
}

/// Snapshot of the chosen size (its price delta in MINOR units), if any.
class SizeSnapshot {
  const SizeSnapshot({
    required this.sizeId,
    required this.nameSnapshot,
    required this.priceDeltaMinorSnapshot,
  });

  final String sizeId;
  final String nameSnapshot;

  /// Price delta in integer MINOR units, snapshotted (DECISION D-007/D-008).
  final int priceDeltaMinorSnapshot;

  @override
  bool operator ==(Object other) =>
      other is SizeSnapshot &&
      other.sizeId == sizeId &&
      other.nameSnapshot == nameSnapshot &&
      other.priceDeltaMinorSnapshot == priceDeltaMinorSnapshot;

  @override
  int get hashCode =>
      Object.hash(sizeId, nameSnapshot, priceDeltaMinorSnapshot);
}

/// Snapshot of the chosen variant (its price delta in MINOR units), if any.
class VariantSnapshot {
  const VariantSnapshot({
    required this.variantId,
    required this.nameSnapshot,
    required this.priceDeltaMinorSnapshot,
  });

  final String variantId;
  final String nameSnapshot;

  /// Price delta in integer MINOR units, snapshotted (DECISION D-007/D-008).
  final int priceDeltaMinorSnapshot;

  @override
  bool operator ==(Object other) =>
      other is VariantSnapshot &&
      other.variantId == variantId &&
      other.nameSnapshot == nameSnapshot &&
      other.priceDeltaMinorSnapshot == priceDeltaMinorSnapshot;

  @override
  int get hashCode =>
      Object.hash(variantId, nameSnapshot, priceDeltaMinorSnapshot);
}

/// Snapshot of a selected modifier option (DECISION D-008), mirroring
/// `order_item_modifiers` (docs/DOMAIN_MODEL.md §6.3). [quantity] counts how
/// many of this option were chosen (e.g. 3 × extra cheese) and defaults to 1.
class ModifierOptionSnapshot {
  ModifierOptionSnapshot({
    required this.modifierId,
    required this.modifierNameSnapshot,
    required this.optionId,
    required this.optionNameSnapshot,
    required this.priceDeltaMinorSnapshot,
    this.quantity = 1,
  }) {
    if (quantity < 1) {
      throw InvalidQuantityException(quantity);
    }
  }

  /// Owning modifier group (reference + name snapshot).
  final String modifierId;
  final String modifierNameSnapshot;

  /// The chosen option (reference + name snapshot).
  final String optionId;
  final String optionNameSnapshot;

  /// Option price delta in integer MINOR units, snapshotted (D-007/D-008).
  final int priceDeltaMinorSnapshot;

  /// How many of this option were selected (integer count; defaults to 1).
  final int quantity;

  /// Contribution of this option to the unit price, in integer MINOR units.
  int get extendedPriceMinor => priceDeltaMinorSnapshot * quantity;

  @override
  bool operator ==(Object other) =>
      other is ModifierOptionSnapshot &&
      other.modifierId == modifierId &&
      other.modifierNameSnapshot == modifierNameSnapshot &&
      other.optionId == optionId &&
      other.optionNameSnapshot == optionNameSnapshot &&
      other.priceDeltaMinorSnapshot == priceDeltaMinorSnapshot &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(
    modifierId,
    modifierNameSnapshot,
    optionId,
    optionNameSnapshot,
    priceDeltaMinorSnapshot,
    quantity,
  );
}

/// A minimal selection rule for a modifier group, used for pure-Dart
/// min/max/required validation at add-to-cart time. RF-030 stores these rules
/// on `modifiers` but does NOT enforce them; enforcement is RF-031.
///
/// [maxSelect] of `0` (or less) means "no upper bound". A required group has an
/// effective minimum of at least 1, regardless of [minSelect].
class ModifierRule {
  const ModifierRule({
    required this.modifierId,
    required this.modifierName,
    this.isRequired = false,
    this.minSelect = 0,
    this.maxSelect = 1,
  });

  final String modifierId;
  final String modifierName;
  final bool isRequired;
  final int minSelect;
  final int maxSelect;

  /// The smallest number of options that must be chosen for this group.
  int get effectiveMin => isRequired && minSelect < 1 ? 1 : minSelect;

  /// Whether an upper bound applies (a [maxSelect] of `0`/negative = unbounded).
  bool get hasUpperBound => maxSelect > 0;
}
