import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Restaurant modifier templates (menu/media sprint, Part D).
///
/// A template is a CLIENT-SIDE recipe: applying one to the item being edited
/// creates ONE modifier group + its options through the EXISTING per-item
/// write seam (`menu_upsert_modifier` + `menu_upsert_modifier_option`) —
/// copy-on-attach over the frozen D-031 per-item schema (NO reusable group
/// tables, NO new RPCs, zero schema change). After applying, the created rows
/// are ordinary per-item modifiers the owner edits/deletes with the existing
/// UI; nothing links them back to the template.
///
/// Names are resolved through l10n AT APPLY TIME and inserted as tenant DATA
/// in the ACTIVE locale's strings — an Arabic-default dashboard seeds Arabic
/// group/option names. The l10n keys only carry the translations; the stored
/// rows are plain text like any manually typed name.
///
/// Money is integer MINOR units end to end (D-007) — `priceDeltaMinor` maps
/// straight onto the bigint `p_price_delta_minor` RPC argument. Selection
/// types are the exact wire values 'single' | 'multiple' (backend CHECK).
class ModifierTemplate {
  const ModifierTemplate({
    required this.id,
    required this.name,
    required this.selectionType,
    required this.minSelect,
    this.maxSelect,
    required this.isRequired,
    this.allowQuantity = false,
    this.maxQuantity,
    required this.options,
  });

  /// Stable template id — also the widget-key suffix ('menu-template-<id>').
  final String id;

  /// Resolves the localized group name (becomes the modifier row's name).
  final String Function(AppLocalizations l10n) name;

  /// Wire value: 'single' | 'multiple' (exact backend CHECK values).
  final String selectionType;

  final int minSelect;
  final int? maxSelect;
  final bool isRequired;

  /// Whether the POS may add the SAME option more than once (quantity
  /// stepper). Only meaningful for 'multiple' selection — the server rejects
  /// 'single' + allow_quantity (product-rescue quantity settings).
  final bool allowQuantity;

  /// Per-option units cap while [allowQuantity] is on; null = no cap.
  final int? maxQuantity;
  final List<ModifierTemplateOption> options;
}

/// One option of a [ModifierTemplate]: a localized name resolver + a signed
/// integer-minor price delta (0 = free).
class ModifierTemplateOption {
  const ModifierTemplateOption({required this.name, this.priceDeltaMinor = 0});

  /// Resolves the localized option name (becomes the option row's name).
  final String Function(AppLocalizations l10n) name;

  /// Signed price delta in integer MINOR units (D-007; ILS pilot).
  final int priceDeltaMinor;
}

// Top-level tear-off targets so the template list below stays const-friendly
// data (closures in a const list are not const; these are).
String _burgerToppings(AppLocalizations l10n) =>
    l10n.menuTemplateBurgerToppings;
String _lettuce(AppLocalizations l10n) => l10n.menuTemplateOptLettuce;
String _tomato(AppLocalizations l10n) => l10n.menuTemplateOptTomato;
String _onion(AppLocalizations l10n) => l10n.menuTemplateOptOnion;
String _pickles(AppLocalizations l10n) => l10n.menuTemplateOptPickles;
String _cheese(AppLocalizations l10n) => l10n.menuTemplateOptCheese;
String _doneness(AppLocalizations l10n) => l10n.menuTemplateDoneness;
String _rare(AppLocalizations l10n) => l10n.menuTemplateOptRare;
String _mediumDoneness(AppLocalizations l10n) =>
    l10n.menuTemplateOptMediumDoneness;
String _wellDone(AppLocalizations l10n) => l10n.menuTemplateOptWellDone;
String _pattyCount(AppLocalizations l10n) => l10n.menuTemplatePattyCount;
String _singlePatty(AppLocalizations l10n) => l10n.menuTemplateOptSinglePatty;
String _doublePatty(AppLocalizations l10n) => l10n.menuTemplateOptDoublePatty;
String _triplePatty(AppLocalizations l10n) => l10n.menuTemplateOptTriplePatty;
String _extras(AppLocalizations l10n) => l10n.menuTemplateExtras;
String _extraCheese(AppLocalizations l10n) => l10n.menuTemplateOptExtraCheese;
String _extraPatty(AppLocalizations l10n) => l10n.menuTemplateOptExtraPatty;
String _fries(AppLocalizations l10n) => l10n.menuTemplateOptFries;
String _drink(AppLocalizations l10n) => l10n.menuTemplateOptDrink;
String _drinkSize(AppLocalizations l10n) => l10n.menuTemplateDrinkSize;
String _small(AppLocalizations l10n) => l10n.menuTemplateOptSmall;
String _mediumSize(AppLocalizations l10n) => l10n.menuTemplateOptMediumSize;
String _large(AppLocalizations l10n) => l10n.menuTemplateOptLarge;
String _spiciness(AppLocalizations l10n) => l10n.menuTemplateSpiciness;
String _mild(AppLocalizations l10n) => l10n.menuTemplateOptMild;
String _mediumSpicy(AppLocalizations l10n) => l10n.menuTemplateOptMediumSpicy;
String _hot(AppLocalizations l10n) => l10n.menuTemplateOptHot;

/// The six built-in restaurant modifier templates, in picker order.
///
/// Deltas are ILS integer minor units (e.g. +900 = 9.00 ILS). All are plain
/// data; nothing is auto-applied to any item.
const List<ModifierTemplate> kMenuModifierTemplates = [
  // 1. Burger toppings — optional multi-select, all free.
  ModifierTemplate(
    id: 'burger-toppings',
    name: _burgerToppings,
    selectionType: 'multiple',
    minSelect: 0,
    maxSelect: null,
    isRequired: false,
    options: [
      ModifierTemplateOption(name: _lettuce),
      ModifierTemplateOption(name: _tomato),
      ModifierTemplateOption(name: _onion),
      ModifierTemplateOption(name: _pickles),
      ModifierTemplateOption(name: _cheese),
    ],
  ),
  // 2. Doneness — REQUIRED single choice.
  ModifierTemplate(
    id: 'doneness',
    name: _doneness,
    selectionType: 'single',
    minSelect: 1,
    maxSelect: 1,
    isRequired: true,
    options: [
      ModifierTemplateOption(name: _rare),
      ModifierTemplateOption(name: _mediumDoneness),
      ModifierTemplateOption(name: _wellDone),
    ],
  ),
  // 3. Patty count — REQUIRED single choice with paid upgrades.
  ModifierTemplate(
    id: 'patty-count',
    name: _pattyCount,
    selectionType: 'single',
    minSelect: 1,
    maxSelect: 1,
    isRequired: true,
    options: [
      ModifierTemplateOption(name: _singlePatty),
      ModifierTemplateOption(name: _doublePatty, priceDeltaMinor: 900),
      ModifierTemplateOption(name: _triplePatty, priceDeltaMinor: 1800),
    ],
  ),
  // 4. Extras — optional multi-select, all paid, quantity-capable (the
  // cashier can add extra cheese ×2 etc., up to 5 units per option).
  ModifierTemplate(
    id: 'extras',
    name: _extras,
    selectionType: 'multiple',
    minSelect: 0,
    maxSelect: null,
    isRequired: false,
    allowQuantity: true,
    maxQuantity: 5,
    options: [
      ModifierTemplateOption(name: _extraCheese, priceDeltaMinor: 300),
      ModifierTemplateOption(name: _extraPatty, priceDeltaMinor: 900),
      ModifierTemplateOption(name: _fries, priceDeltaMinor: 700),
      ModifierTemplateOption(name: _drink, priceDeltaMinor: 500),
    ],
  ),
  // 5. Drink size — REQUIRED single choice with paid upgrades.
  ModifierTemplate(
    id: 'drink-size',
    name: _drinkSize,
    selectionType: 'single',
    minSelect: 1,
    maxSelect: 1,
    isRequired: true,
    options: [
      ModifierTemplateOption(name: _small),
      ModifierTemplateOption(name: _mediumSize, priceDeltaMinor: 200),
      ModifierTemplateOption(name: _large, priceDeltaMinor: 400),
    ],
  ),
  // 6. Spiciness — optional single choice (min 0, max 1), all free.
  ModifierTemplate(
    id: 'spiciness',
    name: _spiciness,
    selectionType: 'single',
    minSelect: 0,
    maxSelect: 1,
    isRequired: false,
    options: [
      ModifierTemplateOption(name: _mild),
      ModifierTemplateOption(name: _mediumSpicy),
      ModifierTemplateOption(name: _hot),
    ],
  ),
];
