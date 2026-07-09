/// KITCHEN-MEAT-001 — the owner-configured MEAT contribution of a modifier
/// option + the whole-order meat rollup shown at the top of the KDS.
///
/// A restaurant configures, per modifier option (e.g. a Size group's Single /
/// Double, or an "extra patty" add), how much meat ONE selection contributes
/// ([KitchenMeat] = {quantity, unit}). The KDS then shows a compact WHOLE-ORDER
/// meat total ("Meat total: 9 patties") as a quick chef note — distinct from the
/// generic [KitchenPrepComponent] prep summary (KITCHEN-PREP-001).
///
/// DISPLAY / PREP metadata only — NEVER money (DECISION D-007): [quantity] is a
/// COUNT and [unit] is free text. Nothing is derived from an option NAME or a
/// PRICE — only what the owner explicitly configured. No burger logic is
/// hardcoded; the unit ("قطع", "g", …) is per-restaurant data.
library;

/// The configured meat contribution of ONE selection of a modifier option.
class KitchenMeat {
  const KitchenMeat({required this.quantity, this.unit = ''});

  /// How much meat one selection adds (a count — a Double is 2, a 300g patty is
  /// 300). A num permits a genuine fraction; never money (D-007).
  final num quantity;

  /// Free-text unit ("قطع" / "patties" / "g" / …), or '' for a bare count.
  final String unit;

  Map<String, Object?> toJson() => <String, Object?>{
    'quantity': quantity,
    'unit': unit,
  };

  /// Tolerantly parses ONE wire object (`modifier_options.kitchen_meat` or an
  /// `order_item_modifiers.meat_snapshot`). Returns null for a non-object or a
  /// non-positive quantity — so a disabled/blank option contributes nothing and
  /// is never faked.
  static KitchenMeat? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawQty = raw['quantity'];
    final quantity = rawQty is num ? rawQty : num.tryParse('${rawQty ?? ''}');
    if (quantity == null || quantity <= 0) return null;
    return KitchenMeat(
      quantity: quantity,
      unit: (raw['unit'] ?? '').toString().trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KitchenMeat && other.quantity == quantity && other.unit == unit;

  @override
  int get hashCode => Object.hash(quantity, unit);

  @override
  String toString() => 'KitchenMeat($quantity, $unit)';
}

/// One order line's meat contribution: the selected option's per-selection
/// [meat] applied [factor] times (= modifier units × ordered item quantity).
class MeatContribution {
  const MeatContribution({required this.meat, required this.factor});

  final KitchenMeat meat;
  final int factor;
}

/// The whole-order meat total (KITCHEN-MEAT-001), grouped by UNIT and summed:
/// each contribution's `meat.quantity × factor`. Different units yield SEPARATE
/// totals (e.g. `9 قطع` and `1200 g`); same unit sums. Groups are returned in
/// STABLE first-appearance order. Blank/non-positive contributions are skipped.
/// Non-money throughout (D-007).
List<KitchenMeat> aggregateMeatByUnit(
  Iterable<MeatContribution> contributions,
) {
  final order = <String>[];
  final units = <String, String>{};
  final sums = <String, num>{};
  for (final contribution in contributions) {
    if (contribution.factor <= 0 || contribution.meat.quantity <= 0) continue;
    final unit = contribution.meat.unit.trim();
    if (!sums.containsKey(unit)) {
      order.add(unit);
      units[unit] = unit;
      sums[unit] = 0;
    }
    sums[unit] = sums[unit]! + contribution.meat.quantity * contribution.factor;
  }
  return <KitchenMeat>[
    for (final unit in order)
      KitchenMeat(quantity: sums[unit]!, unit: units[unit]!),
  ];
}
