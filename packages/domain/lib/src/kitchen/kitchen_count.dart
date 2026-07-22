import 'kitchen_meat.dart';
import 'kitchen_prep.dart';

/// A single aggregated whole-order kitchen COUNT total (KDS-ALERTS-AND-KITCHEN-
/// COUNTS-002).
///
/// The generic, money-free "how many {resource}" the kitchen needs for the whole
/// order. Generalizes the earlier meat/prep-specific summaries into ONE model:
/// any owner-configured counted kitchen resource — burger patties, buns, fish
/// pieces, skewers, chicken pieces, tortillas, … — rolls up here, grouped by its
/// resource [label]. Multiple resource totals can appear together on one ticket.
/// NEVER money (D-007): [quantity] is a count, and counts are only ever the
/// explicit values the owner configured (no inference from names or prices).
class KitchenCount {
  const KitchenCount({required this.quantity, required this.label});

  /// The aggregated count (integer or fractional; never money).
  final num quantity;

  /// The resource label the owner configured (free text, e.g. "قطع لحم" / "خبز"
  /// / "patties" / "buns"). May be empty when the owner left it blank.
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
    'quantity': quantity,
    'label': label,
  };

  @override
  bool operator ==(Object other) =>
      other is KitchenCount &&
      other.quantity == quantity &&
      other.label == label;

  @override
  int get hashCode => Object.hash(quantity, label);

  @override
  String toString() => 'KitchenCount($quantity, $label)';
}

/// One per-source contribution to an aggregated [KitchenCount]: [quantity] units
/// of [label], applied [factor] times.
///
/// [factor] is the number of ordered units the contribution applies to:
///  * a MODIFIER-OPTION count (e.g. Double patty → 2 قطع لحم): factor = the
///    modifier's own quantity × the ordered item quantity.
///  * an ITEM-BASE count (e.g. every burger → 1 خبز): factor = the ordered item
///    quantity.
/// Money-free.
class KitchenCountContribution {
  const KitchenCountContribution({
    required this.quantity,
    required this.label,
    required this.factor,
  });

  final num quantity;
  final String label;
  final int factor;
}

/// Aggregates [contributions] into whole-order [KitchenCount] totals, grouped by
/// the trimmed resource [label] and summed as `quantity × factor`. Preserves the
/// first-appearance order of labels; skips non-positive quantity/factor. Two
/// distinct labels can never merge (length-prefixed grouping key). Money-free.
List<KitchenCount> aggregateKitchenCounts(
  Iterable<KitchenCountContribution> contributions,
) {
  final order = <String>[];
  final labels = <String, String>{};
  final sums = <String, num>{};
  for (final c in contributions) {
    if (c.factor <= 0 || c.quantity <= 0) continue;
    final label = c.label.trim();
    // Length-prefixed so ("AB") and ("A","B") style labels can never collapse.
    final key = '${label.length}:$label';
    if (!sums.containsKey(key)) {
      order.add(key);
      labels[key] = label;
      sums[key] = 0;
    }
    sums[key] = sums[key]! + c.quantity * c.factor;
  }
  return <KitchenCount>[
    for (final key in order)
      KitchenCount(quantity: sums[key]!, label: labels[key]!),
  ];
}

/// One order line's contribution to the whole-order kitchen COUNT rollup, in the
/// neutral shape BOTH the KDS mapper and the POS direct kitchen print can build:
///  * [quantity] — the ordered item quantity (the count FACTOR).
///  * [meats] — the item's per-option meat contributions, each ALREADY
///    multiplied by its modifier units (so only × the item quantity remains).
///  * [prepComponents] — the item's per-unit prep components (buns, wraps, …).
/// Money-free (D-007).
class KitchenCountItemInput {
  const KitchenCountItemInput({
    required this.quantity,
    this.meats = const <KitchenMeat>[],
    this.prepComponents = const <KitchenPrepComponent>[],
  });

  final int quantity;
  final List<KitchenMeat> meats;
  final List<KitchenPrepComponent> prepComponents;
}

/// Rolls a whole order's [items] up into [KitchenCount] totals — the SINGLE
/// contribution mapping shared by the KDS live board and the POS direct kitchen
/// print, so a ticket printed from either surface shows the SAME counts. Each
/// meat contributes `meat.quantity × item.quantity` under its `unit` label; each
/// prep component contributes `prep.quantity × item.quantity` under its
/// [kitchenPrepCountLabel]. The actual summing/grouping is the existing
/// [aggregateKitchenCounts]. Money-free (D-007); owner-configured counts only.
List<KitchenCount> aggregateOrderKitchenCounts(
  Iterable<KitchenCountItemInput> items,
) {
  final contributions = <KitchenCountContribution>[];
  for (final item in items) {
    if (item.quantity <= 0) continue;
    for (final meat in item.meats) {
      contributions.add(
        KitchenCountContribution(
          quantity: meat.quantity,
          label: meat.unit,
          factor: item.quantity,
        ),
      );
    }
    for (final prep in item.prepComponents) {
      contributions.add(
        KitchenCountContribution(
          quantity: prep.quantity,
          label: kitchenPrepCountLabel(prep),
          factor: item.quantity,
        ),
      );
    }
  }
  return aggregateKitchenCounts(contributions);
}
