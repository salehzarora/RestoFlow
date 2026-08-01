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
  const KitchenCount({
    required this.quantity,
    required this.label,
    this.classifier = '',
    this.classifierSelected = false,
  });

  /// The aggregated count (integer or fractional; never money).
  final num quantity;

  /// The resource label the owner configured (free text, e.g. "قطع لحم" / "خبز"
  /// / "patties" / "buns"). May be empty when the owner left it blank.
  final String label;

  /// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: the name of the modifier option
  /// this total is classified BY (e.g. "جبنة"), or `''` for an ordinary
  /// unsplit total — the historical shape.
  ///
  /// Kept STRUCTURED rather than folded into [label] because "with"/"without"
  /// are localized ticket words: the two renderers compose the display string
  /// through [kitchenCountDisplayLabel] with their own l10n patterns, so no
  /// Arabic/Hebrew wording is ever hardcoded in shared logic.
  final String classifier;

  /// Whether this total is the WITH-[classifier] bucket (`true`) or the
  /// WITHOUT one (`false`). Meaningless while [classifier] is empty.
  final bool classifierSelected;

  /// True when this total is one half of a classified resource split.
  bool get isClassified => classifier.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'quantity': quantity,
    'label': label,
    if (classifier.isNotEmpty) ...<String, Object?>{
      'classifier': classifier,
      'classifier_selected': classifierSelected,
    },
  };

  @override
  bool operator ==(Object other) =>
      other is KitchenCount &&
      other.quantity == quantity &&
      other.label == label &&
      other.classifier == classifier &&
      other.classifierSelected == classifierSelected;

  @override
  int get hashCode =>
      Object.hash(quantity, label, classifier, classifierSelected);

  @override
  String toString() =>
      'KitchenCount($quantity, $label'
      '${classifier.isEmpty ? '' : ', ${classifierSelected ? 'with' : 'without'} $classifier'})';
}

/// Composes ONE kitchen-count row's display string: the plain resource [label]
/// when unsplit, else the localized "{resource} with {option}" /
/// "{resource} without {option}" pattern supplied by the caller.
///
/// The connector wording lives in the callers' l10n (ar "مع"/"بدون",
/// he "עם"/"בלי", en "with"/"without") and the WHOLE pattern is theirs, so a
/// locale may reorder the parts. Shared logic contributes no natural-language
/// word of its own. Money-free.
String kitchenCountDisplayLabel(
  KitchenCount count, {
  required String Function(String resource, String option) withOption,
  required String Function(String resource, String option) withoutOption,
}) {
  if (!count.isClassified) return count.label;
  final pattern = count.classifierSelected ? withOption : withoutOption;
  return pattern(count.label, count.classifier);
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
    this.classifier = '',
    this.classifierSelected = false,
  });

  final num quantity;
  final String label;
  final int factor;

  /// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: the classifying option's name
  /// ('' = unclassified) and which bucket this contribution belongs to. A
  /// modifier-option COUNT contribution never sets these — the classifier
  /// re-buckets an item-base resource, it does not reclassify itself.
  final String classifier;
  final bool classifierSelected;
}

/// Aggregates [contributions] into whole-order [KitchenCount] totals, grouped by
/// the trimmed resource [label] — and, since
/// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016, by its classification bucket —
/// summed as `quantity × factor`. Skips non-positive quantity/factor. Two
/// distinct labels can never merge (length-prefixed grouping key). Money-free.
///
/// ORDERING: rows keep the first-appearance order of their RESOURCE, and a
/// split resource's buckets stay together in the slot the unsplit resource
/// would have occupied — with-bucket first, then without. So a burger ordered
/// without cheese followed by one with cheese still prints
/// `Bread / Meat with Cheese / Meat without Cheese`, never interleaved with an
/// unrelated resource that happened to be counted in between. With no
/// classifier configured every resource has exactly one bucket and the result
/// is identical to the historical first-appearance list.
///
/// A bucket that sums to nothing is never created, so an all-selected order
/// prints no empty "without" row and vice versa.
List<KitchenCount> aggregateKitchenCounts(
  Iterable<KitchenCountContribution> contributions,
) {
  final labelOrder = <String, int>{};
  final buckets = <String, _CountBucket>{};
  var seq = 0;
  for (final c in contributions) {
    if (c.factor <= 0 || c.quantity <= 0) continue;
    final label = c.label.trim();
    final classifier = c.classifier.trim();
    // Length-prefixed so ("AB") and ("A","B") style labels can never collapse.
    final labelKey = '${label.length}:$label';
    labelOrder.putIfAbsent(labelKey, () => labelOrder.length);
    // rank 0 = unsplit, 1 = with the classifier, 2 = without it.
    final rank = classifier.isEmpty ? 0 : (c.classifierSelected ? 1 : 2);
    final key = '$labelKey|$rank|${classifier.length}:$classifier';
    final bucket = buckets.putIfAbsent(
      key,
      () => _CountBucket(
        labelIndex: labelOrder[labelKey]!,
        rank: rank,
        sequence: seq++,
        label: label,
        classifier: classifier,
        classifierSelected: c.classifierSelected,
      ),
    );
    bucket.sum += c.quantity * c.factor;
  }
  final ordered = buckets.values.toList()
    ..sort((a, b) {
      final byLabel = a.labelIndex.compareTo(b.labelIndex);
      if (byLabel != 0) return byLabel;
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      // Deterministic final tie-break (List.sort is not stable).
      return a.sequence.compareTo(b.sequence);
    });
  return <KitchenCount>[
    for (final bucket in ordered)
      KitchenCount(
        quantity: bucket.sum,
        label: bucket.label,
        classifier: bucket.classifier,
        classifierSelected: bucket.classifierSelected,
      ),
  ];
}

/// One accumulating group inside [aggregateKitchenCounts].
class _CountBucket {
  _CountBucket({
    required this.labelIndex,
    required this.rank,
    required this.sequence,
    required this.label,
    required this.classifier,
    required this.classifierSelected,
  });

  final int labelIndex;
  final int rank;
  final int sequence;
  final String label;
  final String classifier;
  final bool classifierSelected;
  num sum = 0;
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
          // KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: the ORDER-TIME
          // classification decides only WHICH BUCKET this resource lands in.
          // quantity and factor are untouched, so a classified resource totals
          // exactly what it always did — merely split across two rows.
          classifier: prep.isClassified ? prep.classifierOptionName : '',
          classifierSelected: prep.classifierSelected ?? false,
        ),
      );
    }
  }
  return aggregateKitchenCounts(contributions);
}
