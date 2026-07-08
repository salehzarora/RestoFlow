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
  });

  /// Component display name (data — rendered as-is, never a localized string).
  /// Supports Arabic/Hebrew/English text.
  final String name;

  /// How many [unit]s ONE unit of the item needs. A count (num permits a
  /// genuine half-portion where a product needs it), never money (D-007).
  final num quantity;

  /// Free-text unit ("قطع", "حبة", "g", …), or '' when a bare count reads fine.
  final String unit;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'quantity': quantity,
    'unit': unit,
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
    return KitchenPrepComponent(
      name: name,
      quantity: quantity,
      unit: (raw['unit'] ?? '').toString().trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KitchenPrepComponent &&
      other.name == name &&
      other.quantity == quantity &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(name, quantity, unit);

  @override
  String toString() => 'KitchenPrepComponent($name, $quantity, $unit)';
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
