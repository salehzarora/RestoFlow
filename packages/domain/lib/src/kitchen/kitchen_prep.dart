/// KITCHEN-PREP-001 — configurable kitchen prep metadata + the order rollup.
///
/// A restaurant configures, per menu item, the physical components a chef
/// assembles for ONE unit (e.g. a "Double Burger" needs 2 لحم برجر + 1 خبز
/// برجر). The KDS then shows an aggregated PREP SUMMARY across the whole order
/// so the kitchen never has to decode item names/modifiers by hand.
///
/// This is DISPLAY / PREP metadata only — NEVER money (DECISION D-007):
/// [KitchenPrepComponent.quantity] is a COUNT and [KitchenPrepComponent.unit]
/// is free text. There is no price/`_minor`/total field here and none may ever
/// be added. It is NOT inventory, costing, or a production recipe — just what
/// the chef reads.
///
/// Nothing here is derived from a product NAME or a PRICE — components are only
/// what the owner explicitly configured (or the empty list). No burger logic is
/// hardcoded; the vocabulary ("قطع", "خبز", …) is per-restaurant data.
library;

/// A single configurable prep component for ONE unit of a menu item.
class KitchenPrepComponent {
  const KitchenPrepComponent({
    required this.name,
    required this.quantity,
    this.unit = '',
    this.classifierOptionId = '',
    this.classifierOptionName = '',
    this.classifierSelected,
  });

  /// Component display name (data — rendered as-is, never a localized string).
  /// Supports Arabic/Hebrew/English text.
  final String name;

  /// How many [unit]s ONE unit of the item needs. A count (num permits a
  /// genuine half-portion where a product needs it), never money (D-007).
  final num quantity;

  /// Free-text unit ("قطع", "حبة", "g", …), or '' when a bare count reads fine.
  final String unit;

  /// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 — CONFIG: the id of the modifier
  /// option that CLASSIFIES this resource (e.g. "Cheese" splitting "Meat
  /// pieces" into with/without). `''` = no classifier, the historical default.
  ///
  /// A product-scoped id by construction: `modifiers.menu_item_id` ties every
  /// modifier group — and so every option — to ONE menu item, and modifier
  /// TEMPLATES are copy-on-attach, so a stored id can never address another
  /// product's option.
  ///
  /// It NEVER contributes a quantity. The owner-configured [quantity] above
  /// stays the sole source of how much of this resource a unit needs; the
  /// option only decides WHICH BUCKET that quantity lands in.
  final String classifierOptionId;

  /// CONFIG: the classifying option's display name, captured beside
  /// [classifierOptionId] so a ticket can label the "without" bucket too — the
  /// option is by definition absent from an unselected line, so its name cannot
  /// be recovered from the order's modifiers. `''` = no classifier.
  final String classifierOptionName;

  /// ORDER-TIME (D-008) resolution: whether the classifying option was selected
  /// on THIS order line. `null` = unresolved (menu config, legacy order, or no
  /// classifier) and the resource is then counted UNSPLIT, exactly as before.
  ///
  /// Presence-based: selecting the option twice, or with a modifier quantity
  /// above one, still yields `true` — never a second helping of the resource.
  final bool? classifierSelected;

  /// True when this component carries a RESOLVED classification the kitchen
  /// summary must split on (a named classifier + an order-time answer).
  bool get isClassified =>
      classifierSelected != null && classifierOptionName.isNotEmpty;

  /// This component with the order-time [selected] answer applied. Config
  /// (name/quantity/unit/classifier) is carried through untouched.
  KitchenPrepComponent withClassifierSelected(bool selected) =>
      KitchenPrepComponent(
        name: name,
        quantity: quantity,
        unit: unit,
        classifierOptionId: classifierOptionId,
        classifierOptionName: classifierOptionName,
        classifierSelected: selected,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'quantity': quantity,
    'unit': unit,
    // ADDITIVE (016): emitted only when configured/resolved, so an unclassified
    // component serializes byte-identically to every stored record and wire
    // payload written before this feature existed.
    if (classifierOptionId.isNotEmpty)
      'classifier_option_id': classifierOptionId,
    if (classifierOptionName.isNotEmpty)
      'classifier_option_name': classifierOptionName,
    if (classifierSelected != null) 'classifier_selected': classifierSelected,
  };

  /// Tolerantly parses ONE wire object. Returns null for a blank name or a
  /// non-positive quantity, so a bad row is DROPPED (never shown as "×0" and
  /// never invented).
  static KitchenPrepComponent? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final rawQty = raw['quantity'];
    final quantity = rawQty is num ? rawQty : num.tryParse('${rawQty ?? ''}');
    if (quantity == null || quantity <= 0) return null;
    // 017 (Codex HIGH #2): the classifier triple is read STRICTLY BY TYPE. A
    // non-string id/name or a non-boolean answer is DROPPED, never stringified
    // — otherwise `{"classifier_option_id": {"x": 1}}` would arrive as the
    // literal text "{x: 1}" and be carried as if it were an identifier. A
    // dropped field simply leaves the resource UNSPLIT; the resource itself
    // (name/quantity/unit) is never lost to malformed classifier metadata.
    final rawId = raw['classifier_option_id'];
    final rawName = raw['classifier_option_name'];
    final selected = raw['classifier_selected'];
    final classifierOptionId = rawId is String ? rawId.trim() : '';
    final classifierOptionName = rawName is String ? rawName.trim() : '';
    return KitchenPrepComponent(
      name: name,
      quantity: quantity,
      unit: (raw['unit'] ?? '').toString().trim(),
      // ADDITIVE (016): absent on every record written before this feature, so
      // those decode to the unclassified default and stay UNSPLIT.
      classifierOptionId: classifierOptionId,
      classifierOptionName: classifierOptionName,
      // An answer without a usable link is meaningless — drop it so a
      // half-decoded element can never present itself as classified.
      classifierSelected: selected is bool && classifierOptionId.isNotEmpty
          ? selected
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KitchenPrepComponent &&
      other.name == name &&
      other.quantity == quantity &&
      other.unit == unit &&
      other.classifierOptionId == classifierOptionId &&
      other.classifierOptionName == classifierOptionName &&
      other.classifierSelected == classifierSelected;

  @override
  int get hashCode => Object.hash(
    name,
    quantity,
    unit,
    classifierOptionId,
    classifierOptionName,
    classifierSelected,
  );

  @override
  String toString() =>
      'KitchenPrepComponent($name, $quantity, $unit'
      '${classifierOptionName.isEmpty ? '' : ', by $classifierOptionName'}'
      '${classifierSelected == null ? '' : '=$classifierSelected'})';
}

/// 017 (Codex HIGH #2) — THE trusted classifier boundary.
///
/// A stored `classifier_option_id` is only ever an *assertion*: the attributes
/// bag is edited over time, options get deleted, and a snapshot may be replayed
/// long after. This is the ONE place that assertion is checked against reality —
/// [optionNamesById] must be the option id → name map of the SAME menu item the
/// [components] belong to, read from the live menu at capture time.
///
/// A link survives ONLY when its id is a non-empty string naming an option of
/// THAT item. Anything else — an id from another product, a deleted option, an
/// empty id, a link whose target has no usable name — is STRIPPED, and the
/// resource keeps its ordinary unsplit line. The resource itself (name,
/// quantity, unit) is never touched: invalid classification must never remove a
/// preparation resource the kitchen needs.
///
/// The display name is always taken from the trusted map, never from the stored
/// pair, so a stale or hostile name in JSON can never be printed and a renamed
/// option refreshes automatically. Nothing here queries anything: the caller
/// supplies its own item's options, so no cross-tenant lookup is possible.
///
/// Because this is the only writer of a surviving link, a component that still
/// carries one downstream has, by construction, been validated here.
List<KitchenPrepComponent> resolveTrustedPrepClassifiers(
  List<KitchenPrepComponent> components,
  Map<String, String> optionNamesById,
) {
  if (components.isEmpty) return components;
  var changed = false;
  final out = <KitchenPrepComponent>[];
  for (final component in components) {
    final id = component.classifierOptionId;
    final trustedName = id.isEmpty ? null : optionNamesById[id]?.trim();
    if (trustedName == null || trustedName.isEmpty) {
      // Unknown / foreign / deleted / nameless target -> unsplit resource.
      if (id.isEmpty &&
          component.classifierOptionName.isEmpty &&
          component.classifierSelected == null) {
        out.add(component);
        continue;
      }
      changed = true;
      out.add(
        KitchenPrepComponent(
          name: component.name,
          quantity: component.quantity,
          unit: component.unit,
        ),
      );
      continue;
    }
    if (component.classifierOptionName == trustedName &&
        component.classifierSelected == null) {
      out.add(component);
      continue;
    }
    changed = true;
    out.add(
      KitchenPrepComponent(
        name: component.name,
        quantity: component.quantity,
        unit: component.unit,
        classifierOptionId: id,
        classifierOptionName: trustedName,
      ),
    );
  }
  return changed ? out : components;
}

/// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 — the SINGLE place a menu item's
/// configured prep [components] acquire their ORDER-TIME (D-008) classification
/// answer, so the wire payload, the durable journal, the direct kitchen print
/// and the manual reprint can never disagree about which bucket a resource
/// belongs to.
///
/// 017: this answers WHICH BUCKET only. Whether the link may exist at all is
/// decided upstream by [resolveTrustedPrepClassifiers] against the item's own
/// options — so a link reaching here has already been proven, and this function
/// never promotes an unproven id/name pair into a classification.
///
/// A component with no configured classifier is returned UNCHANGED (identity,
/// not a copy) — the historical unsplit behaviour, byte-identical on the wire.
/// A configured one records whether its target option id appears in
/// [selectedOptionIds]: PRESENCE only, so selecting the option twice, or with a
/// modifier quantity above one, still classifies the resource once and never
/// multiplies the owner-configured [KitchenPrepComponent.quantity].
///
/// Idempotent: re-running it on already-resolved components (a parked cart
/// restored, then submitted) recomputes the same answer from the same config.
/// Money-free (D-007).
List<KitchenPrepComponent> classifyPrepComponents(
  List<KitchenPrepComponent> components,
  Set<String> selectedOptionIds,
) {
  if (components.isEmpty) return components;
  var changed = false;
  final out = <KitchenPrepComponent>[];
  for (final component in components) {
    // Fail safe (016 §9): an unnamed target cannot be labelled on a ticket, so
    // the resource keeps its existing unsplit line rather than printing a
    // half-configured bucket. Admin configuration surfaces the error.
    if (component.classifierOptionId.isEmpty ||
        component.classifierOptionName.isEmpty) {
      out.add(component);
      continue;
    }
    final selected = selectedOptionIds.contains(component.classifierOptionId);
    if (component.classifierSelected == selected) {
      out.add(component);
      continue;
    }
    changed = true;
    out.add(component.withClassifierSelected(selected));
  }
  return changed ? out : components;
}

/// Parses a wire `prep_components` value — the menu item's configured list
/// (from `menu_items.attributes.prep_components`) or an order item's
/// `prep_snapshot` — into a clean list. Tolerant of nulls / wrong types;
/// blank-name and non-positive rows are dropped (never faked).
List<KitchenPrepComponent> parseKitchenPrepComponents(Object? raw) {
  if (raw is! List) return const <KitchenPrepComponent>[];
  final out = <KitchenPrepComponent>[];
  for (final element in raw) {
    final component = KitchenPrepComponent.tryFromJson(element);
    if (component != null) out.add(component);
  }
  return out;
}

/// One order line's contribution to the prep rollup: the item's PER-UNIT
/// [components] and how many units were ordered ([quantity]).
class KitchenPrepLine {
  const KitchenPrepLine({required this.components, required this.quantity});

  final List<KitchenPrepComponent> components;
  final int quantity;
}

/// Aggregates prep across a whole order/ticket (KITCHEN-PREP-001 §3): each
/// component's quantity is multiplied by its line's ordered [quantity] and
/// SUMMED into groups keyed by (trimmed name + trimmed unit). Blank names and
/// non-positive quantities are skipped; groups are returned in STABLE order of
/// first appearance. Non-money throughout (D-007).
///
/// Modifier-added prep (KITCHEN-PREP-001 §4, e.g. an "extra patty" option that
/// adds لحم برجر) is supported by passing it as additional [KitchenPrepLine]s
/// (its per-selection components × how many of that item carried the option).
List<KitchenPrepComponent> aggregateKitchenPrep(
  Iterable<KitchenPrepLine> lines,
) {
  final order = <String>[];
  final names = <String, String>{};
  final units = <String, String>{};
  final sums = <String, num>{};
  for (final line in lines) {
    if (line.quantity <= 0) continue;
    for (final component in line.components) {
      final name = component.name.trim();
      if (name.isEmpty || component.quantity <= 0) continue;
      final unit = component.unit.trim();
      // Length-prefixed name so ("A B","C") and ("A","B C") can never collapse
      // into one group.
      final key = '${name.length}:$name:$unit';
      if (!sums.containsKey(key)) {
        order.add(key);
        names[key] = name;
        units[key] = unit;
        sums[key] = 0;
      }
      sums[key] = sums[key]! + component.quantity * line.quantity;
    }
  }
  return <KitchenPrepComponent>[
    for (final key in order)
      KitchenPrepComponent(
        name: names[key]!,
        quantity: sums[key]!,
        unit: units[key]!,
      ),
  ];
}

/// The whole-order COUNT resource label for an item-base prep [component]: its
/// [KitchenPrepComponent.name], plus the [KitchenPrepComponent.unit] when the
/// owner set one (e.g. "خبز" / "Fish pcs"). This is the key the whole-order
/// kitchen counts group by, so an item-base count and a modifier-option count
/// that share a label merge into ONE total. Single source of truth for BOTH the
/// KDS mapper (`sync_pull` rows) and the POS direct kitchen print (cart lines),
/// so the two can never label the same resource differently. Money-free.
String kitchenPrepCountLabel(KitchenPrepComponent component) {
  final unit = component.unit.trim();
  return unit.isEmpty ? component.name : '${component.name} $unit';
}

/// Formats a prep [quantity] for display: a whole number drops its `.0`
/// (`6`, not `6.0`); a genuine fraction keeps up to 2 dp with trailing zeros
/// trimmed. A count, never a money amount.
String formatPrepQuantity(num quantity) {
  if (quantity == quantity.roundToDouble()) return quantity.toInt().toString();
  return quantity
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
