/// KITCHEN-MEAT-001 — the owner-configured kitchen-COUNT contribution of a
/// modifier option + the whole-order count rollup shown at the top of the KDS.
///
/// KITCHEN-COUNT-001: the INTERNAL names ([KitchenMeat], `kitchen_meat`,
/// `meat_snapshot`) are kept for backwards compatibility, but the feature is a
/// GENERIC kitchen count — the owner writes any unit (قطع لحم / حبات سمك / خبز /
/// سيخ / patties / buns / skewers …) and the USER-FACING copy is "Kitchen total"
/// (l10n `kdsMeatTotalLabel`), not meat-specific.
///
/// A restaurant configures, per modifier option (e.g. a Size group's Single /
/// Double, or an "extra patty" add), how much ONE selection contributes
/// ([KitchenMeat] = {quantity, unit}). The KDS then shows a compact WHOLE-ORDER
/// count total ("Kitchen total: 9 قطع لحم") as a quick chef note — distinct from
/// the generic [KitchenPrepComponent] prep summary (KITCHEN-PREP-001).
///
/// DISPLAY / PREP metadata only — NEVER money (DECISION D-007): [quantity] is a
/// COUNT and [unit] is free text. Nothing is derived from an option NAME or a
/// PRICE — only what the owner explicitly configured. No burger logic is
/// hardcoded; the unit ("قطع لحم", "حبات سمك", "g", …) is per-restaurant data.
library;

/// The configured kitchen-count contribution of ONE selection of a modifier
/// option (internal name kept as *Meat*; user-facing copy is a generic count).
class KitchenMeat {
  const KitchenMeat({
    required this.quantity,
    this.unit = '',
    this.classifierOptionId = '',
    this.classifierOptionName = '',
    this.classifierSelected,
  });

  /// How much meat one selection adds (a count — a Double is 2, a 300g patty is
  /// 300). A num permits a genuine fraction; never money (D-007).
  final num quantity;

  /// Free-text unit ("قطع" / "patties" / "g" / …), or '' for a bare count.
  final String unit;

  /// KITCHEN-MODIFIER-PREP-CLASSIFIER-019 — CONFIG: the id of ANOTHER option on
  /// the SAME menu item that classifies THIS option's contribution.
  ///
  /// Saleh's real menu shape: the meat quantity is not a fixed product-level
  /// resource — it comes from the selected SIZE option (120g → 1 Meat piece,
  /// 240g → 2, …). A separate Cheese option decides whether those pieces are
  /// reported as "with Cheese" or "without Cheese". So the classifier belongs
  /// beside the contribution it re-buckets, not on the product's general
  /// preparation rows.
  ///
  /// Product-scoped by construction: `modifiers.menu_item_id` ties every group —
  /// and so every option — to ONE menu item, and modifier TEMPLATES are
  /// copy-on-attach, so a stored id can never address another product's option.
  ///
  /// It NEVER contributes a quantity. [quantity] above stays the sole source of
  /// how much this option adds; the classifier only decides WHICH BUCKET.
  final String classifierOptionId;

  /// CONFIG: the classifying option's display name, captured beside
  /// [classifierOptionId] so a ticket can label the "without" bucket too — that
  /// option is by definition absent from an unclassified line, so its name
  /// cannot be recovered from the order's modifiers. `''` = no classifier.
  final String classifierOptionName;

  /// ORDER-TIME (D-008) resolution: whether the classifying option was selected
  /// on THIS order line. `null` = unresolved (menu config, legacy order, or no
  /// classifier) and the contribution is counted UNSPLIT, exactly as before.
  ///
  /// Presence-based: selecting the classifier twice, or with a modifier quantity
  /// above one, still yields `true` — never a second helping.
  final bool? classifierSelected;

  /// True when this contribution carries a RESOLVED classification the kitchen
  /// summary must split on (a named classifier + an order-time answer).
  bool get isClassified =>
      classifierSelected != null && classifierOptionName.isNotEmpty;

  /// This contribution with the order-time [selected] answer applied. Config
  /// (quantity/unit/classifier) is carried through untouched.
  KitchenMeat withClassifierSelected(bool selected) => KitchenMeat(
    quantity: quantity,
    unit: unit,
    classifierOptionId: classifierOptionId,
    classifierOptionName: classifierOptionName,
    classifierSelected: selected,
  );

  /// This contribution scaled to [units] selections, preserving the classifier.
  /// The classifier is PRESENCE-based, so scaling never touches it.
  KitchenMeat scaledBy(int units) => KitchenMeat(
    quantity: quantity * units,
    unit: unit,
    classifierOptionId: classifierOptionId,
    classifierOptionName: classifierOptionName,
    classifierSelected: classifierSelected,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'quantity': quantity,
    'unit': unit,
    // ADDITIVE (019): emitted only when configured/resolved, so an unclassified
    // contribution serializes byte-identically to every stored record and wire
    // payload written before this feature existed.
    if (classifierOptionId.isNotEmpty)
      'classifier_option_id': classifierOptionId,
    if (classifierOptionName.isNotEmpty)
      'classifier_option_name': classifierOptionName,
    if (classifierSelected != null) 'classifier_selected': classifierSelected,
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
    // 019: the classifier triple is read STRICTLY BY TYPE. A non-string id/name
    // or a non-boolean answer is DROPPED, never stringified — otherwise
    // `{"classifier_option_id": {"x": 1}}` would arrive as the literal text
    // "{x: 1}" and be carried as if it were an identifier. A dropped field
    // leaves the contribution UNSPLIT; the contribution itself (quantity/unit)
    // is never lost to malformed classifier metadata.
    final rawId = raw['classifier_option_id'];
    final rawName = raw['classifier_option_name'];
    final selected = raw['classifier_selected'];
    final classifierOptionId = rawId is String ? rawId.trim() : '';
    final classifierOptionName = rawName is String ? rawName.trim() : '';
    return KitchenMeat(
      quantity: quantity,
      unit: (raw['unit'] ?? '').toString().trim(),
      // ADDITIVE (019): absent on every record written before this feature, so
      // those decode to the unclassified default and stay UNSPLIT.
      classifierOptionId: classifierOptionId,
      classifierOptionName: classifierOptionName,
      // An answer without a usable link is meaningless — drop it so a
      // half-decoded snapshot can never present itself as classified.
      classifierSelected: selected is bool && classifierOptionId.isNotEmpty
          ? selected
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KitchenMeat &&
      other.quantity == quantity &&
      other.unit == unit &&
      other.classifierOptionId == classifierOptionId &&
      other.classifierOptionName == classifierOptionName &&
      other.classifierSelected == classifierSelected;

  @override
  int get hashCode => Object.hash(
    quantity,
    unit,
    classifierOptionId,
    classifierOptionName,
    classifierSelected,
  );

  @override
  String toString() =>
      'KitchenMeat($quantity, $unit'
      '${classifierOptionName.isEmpty ? '' : ', by $classifierOptionName'}'
      '${classifierSelected == null ? '' : '=$classifierSelected'})';
}

/// 019 — THE trusted classifier boundary for a MODIFIER OPTION's kitchen
/// preparation contribution.
///
/// A stored `classifier_option_id` is only ever an *assertion*. This is the ONE
/// place it is checked against reality: [optionNamesById] must be the option
/// id → name map of the SAME menu item the contribution belongs to, read from
/// the live menu, and [selfOptionId] is the option carrying the contribution.
///
/// A link survives ONLY when its id names a DIFFERENT option of THAT item.
/// Anything else — an id from another product, a deleted option, an empty or
/// malformed id, a self-reference, a target with no usable name — is STRIPPED
/// and the contribution keeps its ordinary unsplit line. The contribution
/// itself (quantity, unit) is never touched: invalid classification must never
/// remove preparation the kitchen needs.
///
/// The display name always comes from the trusted map, never from the stored
/// pair, so a stale or hostile name can never be printed and a renamed option
/// refreshes automatically. Nothing is queried: the caller supplies its own
/// item's options, so no cross-tenant lookup is possible.
///
/// Because this is the only writer of a surviving link, a contribution that
/// still carries one downstream has, by construction, been validated here.
KitchenMeat? resolveTrustedMeatClassifier(
  KitchenMeat? meat, {
  required Map<String, String> optionNamesById,
  required String selfOptionId,
}) {
  if (meat == null) return null;
  final id = meat.classifierOptionId;
  final trustedName = id.isEmpty || id == selfOptionId
      ? null
      : optionNamesById[id]?.trim();
  if (trustedName == null || trustedName.isEmpty) {
    if (id.isEmpty &&
        meat.classifierOptionName.isEmpty &&
        meat.classifierSelected == null) {
      return meat;
    }
    return KitchenMeat(quantity: meat.quantity, unit: meat.unit);
  }
  if (meat.classifierOptionName == trustedName &&
      meat.classifierSelected == null) {
    return meat;
  }
  return KitchenMeat(
    quantity: meat.quantity,
    unit: meat.unit,
    classifierOptionId: id,
    classifierOptionName: trustedName,
  );
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
