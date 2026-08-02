import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/demo_menu.dart';
import 'menu_availability_controller.dart';
import 'pos_session.dart';

/// The menu the POS sells from: categories + items + the currency.
///
/// DEMO mode (default): the in-memory demo menu, unchanged. REAL mode: the
/// backend menu via `public.pos_menu` (session-scoped; prices integer minor —
/// D-007), fetched ONLY once an authenticated PIN session exists. Fail-closed:
/// real mode with no session/transport throws [PosMenuUnavailable] — the POS
/// never sells from a fake menu in real mode.
class PosMenuData {
  const PosMenuData({
    required this.categories,
    required this.items,
    required this.currencyCode,
    this.modifierGroups = const <PosModifierGroup>[],
  });

  final List<DemoCategory> categories;
  final List<DemoMenuItem> items;
  final String currencyCode;

  /// Modifier groups across all items (demo-readiness sprint) — burger
  /// toppings, doneness, extras. Price deltas are integer minor units (D-007;
  /// SIGNED — a delta may be free or paid).
  final List<PosModifierGroup> modifierGroups;

  DemoCategory? categoryOf(String categoryId) {
    for (final category in categories) {
      if (category.id == categoryId) return category;
    }
    return null;
  }

  /// The (display-ordered) modifier groups attached to [menuItemId].
  List<PosModifierGroup> groupsForItem(String menuItemId) => [
    for (final group in modifierGroups)
      if (group.menuItemId == menuItemId && group.options.isNotEmpty) group,
  ];

  /// 017 (Codex HIGH #2) — THE trusted classifier boundary for the POS.
  ///
  /// A menu item's stored `attributes.prep_components` may assert that a
  /// preparation resource is classified by some modifier option id. That
  /// assertion is checked HERE, once, against the item's OWN options, and the
  /// resulting items replace the raw ones — so every downstream consumer (the
  /// cart's add-time snapshot, the submit-time map the outbox and the kitchen
  /// ticket share, the Add-items snapshot, a parked draft) can only ever see a
  /// link that was proven against the same product.
  ///
  /// An id naming another product's option, a deleted option, an empty id or a
  /// nameless target is stripped and the resource keeps its ordinary unsplit
  /// line; the resource's name/quantity/unit are never touched. The printed
  /// option name always comes from THIS item's live option, never from the
  /// stored pair, so a stale or hostile name cannot reach a ticket and a
  /// renamed option refreshes on the next menu read. Nothing is queried: the
  /// data is already in hand, so no cross-tenant lookup is possible.
  static PosMenuData withTrustedPrepClassifiers(PosMenuData menu) {
    /// Every option of one menu item, across ALL of its modifier groups — the
    /// only ids a link on that item may legitimately name.
    Map<String, String> optionNamesFor(String menuItemId) => <String, String>{
      for (final group in menu.modifierGroups)
        if (group.menuItemId == menuItemId)
          for (final option in group.options) option.id: option.name,
    };

    var changed = false;
    final items = <DemoMenuItem>[];
    for (final item in menu.items) {
      final configured = item.prepComponents;
      if (configured.isEmpty) {
        items.add(item);
        continue;
      }
      final trusted = resolveTrustedPrepClassifiers(
        configured,
        optionNamesFor(item.id),
      );
      if (identical(trusted, configured)) {
        items.add(item);
        continue;
      }
      changed = true;
      items.add(
        item.copyWith(
          attributes: <String, dynamic>{
            ...item.attributes,
            'prep_components': [for (final c in trusted) c.toJson()],
          },
        ),
      );
    }

    // 019: the SAME boundary for a MODIFIER OPTION's own preparation
    // contribution — which is where Saleh's meat actually lives (the size
    // option contributes the Meat pieces; Cheese classifies them). A link
    // survives only when it names a DIFFERENT option of the SAME item; a
    // foreign, deleted, empty, malformed or self-referencing target is stripped
    // and the contribution keeps its ordinary unsplit line. Quantity and unit
    // are never touched.
    final groups = <PosModifierGroup>[];
    for (final group in menu.modifierGroups) {
      final names = optionNamesFor(group.menuItemId);
      var groupChanged = false;
      final options = <PosModifierOption>[];
      for (final option in group.options) {
        final meat = option.kitchenMeat;
        final trusted = resolveTrustedMeatClassifier(
          meat,
          optionNamesById: names,
          selfOptionId: option.id,
        );
        if (identical(trusted, meat)) {
          options.add(option);
          continue;
        }
        groupChanged = true;
        changed = true;
        options.add(
          PosModifierOption(
            id: option.id,
            name: option.name,
            priceDeltaMinor: option.priceDeltaMinor,
            kitchenMeat: trusted,
          ),
        );
      }
      groups.add(
        groupChanged
            ? PosModifierGroup(
                id: group.id,
                menuItemId: group.menuItemId,
                name: group.name,
                options: options,
                singleSelect: group.singleSelect,
                minSelect: group.minSelect,
                maxSelect: group.maxSelect,
                isRequired: group.isRequired,
                allowQuantity: group.allowQuantity,
                maxQuantity: group.maxQuantity,
              )
            : group,
      );
    }

    if (!changed) return menu;
    return PosMenuData(
      categories: menu.categories,
      items: items,
      currencyCode: menu.currencyCode,
      modifierGroups: groups,
    );
  }
}

/// One selectable option inside a [PosModifierGroup]. [priceDeltaMinor] is a
/// SIGNED integer minor-unit delta (0 = free).
class PosModifierOption {
  const PosModifierOption({
    required this.id,
    required this.name,
    required this.priceDeltaMinor,
    this.kitchenMeat,
  });

  final String id;
  final String name;
  final int priceDeltaMinor;

  /// KITCHEN-MEAT-001: the owner-configured meat contribution of ONE selection
  /// of this option (from `modifier_options.kitchen_meat`). Non-money; null when
  /// the option contributes no meat. Snapshotted into the order at selection so
  /// the KDS can compute the whole-order meat total.
  final KitchenMeat? kitchenMeat;
}

/// A modifier group on a menu item (mirrors the RF-109 `modifiers` +
/// `modifier_options` rows the backend serves through `pos_menu`).
class PosModifierGroup {
  const PosModifierGroup({
    required this.id,
    required this.menuItemId,
    required this.name,
    required this.options,
    this.singleSelect = false,
    this.minSelect = 0,
    this.maxSelect,
    this.isRequired = false,
    this.allowQuantity = false,
    this.maxQuantity,
  });

  final String id;
  final String menuItemId;
  final String name;
  final List<PosModifierOption> options;

  /// `selection_type == 'single'` — exactly one choice (radio behaviour).
  final bool singleSelect;
  final int minSelect;
  final int? maxSelect;
  final bool isRequired;

  /// `allow_quantity` (modifier-quantity sprint): the cashier may take the
  /// SAME option more than once (extra cheese ×2) via a stepper. Only ever
  /// true on multi-select groups — the backend rejects it for 'single'.
  final bool allowQuantity;

  /// `max_quantity`: units cap for ONE option when [allowQuantity] (null =
  /// no cap). [minSelect]/[maxSelect] keep counting DISTINCT options.
  final int? maxQuantity;

  /// The minimum selections the cashier must make before adding the item.
  int get effectiveMin =>
      singleSelect ? 1 : (isRequired && minSelect == 0 ? 1 : minSelect);

  /// The maximum selections allowed (single => 1; null => unlimited).
  int? get effectiveMax => singleSelect ? 1 : maxSelect;

  /// Whether option tiles in this group carry a quantity stepper.
  bool get hasQuantitySteppers => allowQuantity && !singleSelect;
}

/// Real mode without a transport/session (or a rejected response) — the POS
/// shows a safe error state instead of a fake menu.
class PosMenuUnavailable implements Exception {
  const PosMenuUnavailable();
}

/// Demo modifier groups (demo-readiness sprint) so the modifier flow is
/// visible without a backend (attached to the Cheeseburger so the FIRST
/// grid item stays a plain one-tap add): toppings (free + paid), a REQUIRED
/// single-select doneness, and paid extras. Names are demo DATA (not chrome).
const List<PosModifierGroup> kDemoModifierGroups = <PosModifierGroup>[
  PosModifierGroup(
    id: 'demo-mod-toppings',
    menuItemId: 'cheeseburger',
    name: 'Toppings',
    options: [
      PosModifierOption(
        id: 'demo-opt-onion',
        name: 'Onion',
        priceDeltaMinor: 0,
      ),
      PosModifierOption(
        id: 'demo-opt-lettuce',
        name: 'Lettuce',
        priceDeltaMinor: 0,
      ),
      PosModifierOption(
        id: 'demo-opt-tomato',
        name: 'Tomato',
        priceDeltaMinor: 0,
      ),
      PosModifierOption(
        id: 'demo-opt-cheese',
        name: 'Cheese',
        priceDeltaMinor: 300,
      ),
    ],
  ),
  PosModifierGroup(
    id: 'demo-mod-doneness',
    menuItemId: 'cheeseburger',
    name: 'Doneness',
    singleSelect: true,
    isRequired: true,
    options: [
      PosModifierOption(id: 'demo-opt-rare', name: 'Rare', priceDeltaMinor: 0),
      PosModifierOption(
        id: 'demo-opt-medium',
        name: 'Medium',
        priceDeltaMinor: 0,
      ),
      PosModifierOption(
        id: 'demo-opt-well',
        name: 'Well done',
        priceDeltaMinor: 0,
      ),
    ],
  ),
  PosModifierGroup(
    id: 'demo-mod-extras',
    menuItemId: 'cheeseburger',
    name: 'Extras',
    maxSelect: 2,
    // Quantity-enabled (modifier-quantity sprint): the demo shows the same
    // stepper flow the real Extras template configures (extra cheese ×2).
    allowQuantity: true,
    maxQuantity: 5,
    options: [
      PosModifierOption(
        id: 'demo-opt-extra-cheese',
        name: 'Extra cheese',
        priceDeltaMinor: 300,
      ),
      PosModifierOption(
        id: 'demo-opt-extra-patty',
        name: 'Extra patty',
        priceDeltaMinor: 900,
        // KITCHEN-MEAT-001 demo: an extra patty adds 1 to the meat total. Unit
        // is demo DATA (a real restaurant configures its own). Money-free.
        kitchenMeat: KitchenMeat(quantity: 1, unit: 'patty'),
      ),
    ],
  ),
];

/// A stable, data-driven icon/colour palette for REAL categories (the backend
/// carries no iconography). Assigned by category order — presentation only.
const List<(IconData, Color)> _kCategoryPalette = [
  (Icons.lunch_dining, RestoflowCategoryPalette.terracotta),
  (Icons.dinner_dining, RestoflowCategoryPalette.teal),
  (Icons.fastfood, RestoflowCategoryPalette.amber),
  (Icons.local_bar, RestoflowCategoryPalette.blue),
  (Icons.local_cafe, RestoflowCategoryPalette.coffee),
  (Icons.icecream, RestoflowCategoryPalette.berry),
];

/// POS-PRODUCT-DESCRIPTIONS-001: the ONE normalization for an optional free-text
/// wire field, applied at the parsing boundary so no widget ever normalizes
/// during a build.
///
/// A non-String value (an integer, an object, a list — anything a future schema
/// or a bad row might carry) is NOT content, and neither is whitespace. Both
/// become null, which the UI renders as "no description" rather than failing the
/// item: one bad optional field must never drop a sellable product off the menu.
String? _optionalText(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

final posMenuProvider = FutureProvider<PosMenuData>((ref) async {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) {
    // PILOT-OPERATIONS-CORRECTIONS-001: apply the in-memory demo availability
    // overlay so a demo cashier's Sold-out/Paused change is honestly reflected.
    final overrides = ref.watch(demoAvailabilityOverridesProvider);
    final items = overrides.isEmpty
        ? kDemoMenu
        : <DemoMenuItem>[
            for (final item in kDemoMenu)
              if (overrides[item.id] case final o?)
                item.withAvailability(o.availability, o.reason)
              else
                item,
          ];
    // 017: the demo menu goes through the SAME trusted classifier boundary as
    // the real one, so demo and real mode can never diverge on what a valid
    // classifier link is.
    return PosMenuData.withTrustedPrepClassifiers(
      PosMenuData(
        categories: kDemoCategories,
        items: items,
        currencyCode: kDemoCurrencyCode,
        modifierGroups: kDemoModifierGroups,
      ),
    );
  }
  final transport = ref.watch(posAuthTransportProvider);
  final session = ref.watch(posSyncSessionProvider);
  if (transport == null || session == null) {
    throw const PosMenuUnavailable();
  }
  final Object? raw;
  try {
    raw = await transport.invoke('pos_menu', <String, dynamic>{
      'p_pin_session_id': session.pinSessionId,
      'p_device_id': session.deviceId,
    });
  } on SyncTransportException {
    throw const PosMenuUnavailable();
  }
  if (raw is! Map || raw['ok'] != true) throw const PosMenuUnavailable();

  final categories = <DemoCategory>[];
  var paletteIndex = 0;
  final names = <String, String>{};
  // MENU-ORDER-001: category id -> its Dashboard display order, so each item can
  // carry its category rank (the PRIMARY print-order key) onto the cart line.
  final catDisplayOrder = <String, int>{};
  for (final row in (raw['categories'] as List?) ?? const []) {
    if (row is! Map) continue;
    final id = (row['id'] ?? '').toString();
    final name = (row['name'] ?? '').toString();
    final (icon, color) =
        _kCategoryPalette[paletteIndex % _kCategoryPalette.length];
    paletteIndex++;
    names[id] = name;
    catDisplayOrder[id] = menuPrintOrderInt(row['display_order']);
    categories.add(DemoCategory(id: id, name: name, icon: icon, color: color));
  }

  var items = <DemoMenuItem>[];
  for (final row in (raw['items'] as List?) ?? const []) {
    if (row is! Map) continue;
    // base_price_minor is present for cashier/manager sessions (a POS is never
    // a kitchen_staff surface); if it is ever absent, skip the item rather
    // than inventing a zero price.
    final price = row['base_price_minor'];
    if (price is! int) continue;
    final categoryId = (row['menu_category_id'] ?? '').toString();
    final imagePath = row['image_path'];
    // Rich attributes (menu/media sprint) — STORAGE ONLY this part (display
    // lands in later parts). Tolerant parse: a wrong-typed value degrades to
    // unset rather than dropping the sellable item. All non-money (D-007);
    // sku is never served to devices, so it is never parsed here.
    final itemType = row['item_type'];
    final rawTags = row['tags'];
    final prepMinutes = row['prep_minutes'];
    final kitchenNote = row['kitchen_note'];
    final rawAttributes = row['attributes'];
    // RESTAURANT-OPERATIONS-V1-001: the SESSION-BRANCH availability override.
    // FAIL-OPEN to 'available' on a missing/wrong-typed key: availability is a
    // display + cart gate only — the SERVER re-refuses an unavailable item at
    // acceptance (item_unavailable), so a lenient parse can never oversell.
    final availability = row['availability'];
    final availabilityReason = row['availability_reason'];
    // POS-PRODUCT-DESCRIPTIONS-001: the operator's product description, served
    // by `pos_menu` for both the cashier and the kitchen-redacted object.
    // Normalized ONCE, here at the parsing boundary — never in a card build.
    // Tolerant like every other optional field: a wrong-typed or blank value
    // degrades to "no description" rather than dropping a sellable product.
    final description = _optionalText(row['description']);
    items.add(
      DemoMenuItem(
        id: (row['id'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        priceMinor: price,
        categoryId: categoryId,
        categoryName: names[categoryId] ?? '',
        // MENU-ORDER-001: the item's Dashboard print-order ranks (category rank
        // denormalized from its category; item rank from this row) so the cart
        // line, and hence every POS print surface, can order by menu config.
        categoryDisplayOrder: catDisplayOrder[categoryId] ?? 0,
        itemDisplayOrder: menuPrintOrderInt(row['display_order']),
        imagePath: imagePath is String && imagePath.isNotEmpty
            ? imagePath
            : null,
        itemType: itemType is String && itemType.isNotEmpty ? itemType : null,
        tags: rawTags is List
            ? <String>[
                for (final tag in rawTags)
                  if (tag is String && tag.isNotEmpty) tag,
              ]
            : const <String>[],
        prepMinutes: prepMinutes is int && prepMinutes >= 0
            ? prepMinutes
            : null,
        kitchenNote: kitchenNote is String && kitchenNote.isNotEmpty
            ? kitchenNote
            : null,
        attributes: rawAttributes is Map
            ? Map<String, dynamic>.from(rawAttributes)
            : const <String, dynamic>{},
        availability: availability == 'unavailable'
            ? 'unavailable'
            : 'available',
        availabilityReason:
            availabilityReason is String && availabilityReason.isNotEmpty
            ? availabilityReason
            : null,
        description: description,
      ),
    );
  }

  // Menu/media sprint: batch-resolve signed URLs for the item images ONCE per
  // menu load (the device's read-only storage capability). FAIL-SOFT: any
  // resolution failure (no resolver, transport error, per-key policy denial)
  // leaves items imageless and the cards fall back to the tinted icon band —
  // no error spam, images are never load-bearing.
  final resolver = ref.watch(posImageUrlResolverProvider);
  final imagePaths = <String>[
    for (final item in items)
      if (item.imagePath != null) item.imagePath!,
  ];
  if (resolver != null && imagePaths.isNotEmpty) {
    Map<String, String> urls;
    try {
      urls = await resolver.signedUrlsFor(imagePaths);
    } catch (_) {
      urls = const {};
    }
    if (urls.isNotEmpty) {
      items = [
        for (final item in items)
          item.imagePath != null && urls.containsKey(item.imagePath)
              // PILOT-OPERATIONS-CORRECTIONS-001: attach the resolved signed URL
              // with a FIELD-PRESERVING copy. A partial DemoMenuItem() rebuild
              // here silently reset availability to 'available', turning a
              // Sold-out/Paused item back into a sellable tile once its image
              // resolved — copyWith carries every authoritative field through.
              ? item.copyWith(imageUrl: urls[item.imagePath])
              : item,
      ];
    }
  }

  // Modifier groups + their options (pos_menu v2, demo-readiness sprint).
  // price_delta_minor is present for cashier/manager sessions; an option
  // without one is skipped rather than sold at an invented price.
  // MONEY-LOCAL-ATOMICITY-003A — THE SOURCE BOUNDARY FAILS CLOSED.
  //
  // Every identifier here used to be coerced with `(row['x'] ?? '').toString()`,
  // and the consequence was not that a broken group vanished loudly — it was
  // that the PRODUCT SILENTLY BECAME PLAIN-ADDABLE. A group row with a blank id
  // was still constructed (id: ''), its options orphaned under their real
  // `modifier_id`, `groupsForItem` then dropped it for having no options, and
  // the add handler took the `groups.isEmpty -> addItem` branch: a required
  // PAID modifier group disappeared and the item sold at its base price with no
  // indicator that anything was lost.
  //
  // Identifiers are now exact. A row we cannot read does not produce a
  // half-group — it marks its MENU ITEM as having unreadable configuration, and
  // the item is served UNAVAILABLE through the existing availability mechanism
  // so the card refuses the tap and says why. An undercharged sale is a worse
  // outcome than a temporarily unsellable product.
  // MONEY-CODEX-FINAL-CORRECTIONS-004 (F3): CANONICAL, not merely validated.
  //
  // This used to validate with `.trim()` but return the RAW value, so a padded
  // `' grp-1 '` passed the check and was then stored uncanonicalised. Every
  // later comparison is byte-exact, so that option never matched the group
  // `grp-1` it belongs to: the group silently lost a choice, and if it lost its
  // only one, `groupsForItem` dropped the whole group and the product became
  // plain-addable at base price. Trimming ONCE here makes every reference in
  // the menu envelope agree.
  String? exactId(Object? v) {
    if (v is! String) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // Menu items whose modifier configuration cannot be trusted.
  final brokenConfigItemIds = <String>{};
  final optionsByGroup = <String, List<PosModifierOption>>{};
  // Groups that lost an option we could still ATTRIBUTE to them — their owning
  // item is known, so only that item stops selling.
  final orphanedOptionGroupIds = <String>{};
  // MONEY-CODEX-FINAL-CLOSURE-005 (F3): rows we could not attribute to any
  // declared group AT ALL. See the payload-level decision below for why these
  // cannot be narrowed to one product.
  var hasUnattributableOption = false;

  // ---- GROUP PRE-SCAN --------------------------------------------------
  // Every group id declared in this payload, so an option naming an UNDECLARED
  // parent is recognised as unattributable rather than silently discarded.
  final declaredGroupIds = <String>{};
  // A group row that is not an object AT ALL. It loses a WHOLE configured group
  // and names nothing, so an item whose only group it was appears with no
  // configuration and keeps selling plain at base price. Strictly worse than
  // losing one option — which already fails the payload — so the pre-005
  // asymmetry (silent `continue` for groups, fail-closed for options) favoured
  // the more dangerous case.
  var hasUnreadableGroupRow = false;
  // Two rows claiming ONE group id both render, both read the same selection
  // map, and one tap emits the modifier twice — a real OVER-charge that reaches
  // the receipt and the wire. `groupsForItem` does not dedupe, so it is caught
  // here.
  final duplicateGroupIds = <String>{};
  // THE EXCUSE, bounded exactly. A group row we REJECTED but which named its
  // owner leaves that item unavailable, so an option we cannot match MAY be
  // accounted for by it — but only in the two shapes where that is actually
  // true:
  //
  //  * `rejectedGroupIds` — the row's ID was readable (only its name was not),
  //    so an option naming THAT id is provably the rejected group's;
  //  * `hasUnidentifiableOwnedGroup` — the row's ID was unreadable, so its
  //    options can name no id we hold and any unmatched option could be one of
  //    them.
  //
  // SELF-REVIEW CORRECTION: this began as a single payload-wide boolean, a hole
  // exactly as wide as the one F3 closed — ONE rejected group row anywhere
  // excused EVERY unmatched option in the payload, including options belonging
  // to a completely different item, which could then lose its only paid group
  // and go on selling plain at base price.
  final rejectedGroupIds = <String>{};
  var hasUnidentifiableOwnedGroup = false;
  for (final row in (raw['modifiers'] as List?) ?? const []) {
    if (row is! Map) {
      hasUnreadableGroupRow = true;
      continue;
    }
    final id = exactId(row['id']);
    final owner = exactId(row['menu_item_id']);
    final name = row['name'];
    final nameOk = name is String && name.trim().isNotEmpty;
    if (id != null && nameOk) {
      if (!declaredGroupIds.add(id)) duplicateGroupIds.add(id);
    } else if (owner != null) {
      if (id != null) {
        rejectedGroupIds.add(id);
      } else {
        hasUnidentifiableOwnedGroup = true;
      }
    }
  }

  // ---- OPTION LOOP -----------------------------------------------------
  // An option id that appears more than once is AMBIGUOUS — it could price two
  // different lines and we cannot tell which the operator meant. EVERY group
  // that claimed it is suspect, the first one included: blaming only the later
  // claimant would leave the first holding an ambiguous price, and if the
  // operator's real delta was the second, that is a silent undercharge.
  final firstClaimantByOptionId = <String, String>{};
  final duplicateOptionIds = <String>{};
  for (final row in (raw['modifier_options'] as List?) ?? const []) {
    if (row is! Map) {
      // Not even a row. Nothing identifies it, so nothing can be blamed.
      hasUnattributableOption = true;
      continue;
    }
    final groupId = exactId(row['modifier_id']);
    final optionId = exactId(row['id']);
    final delta = row['price_delta_minor'];
    final name = row['name'];
    if (groupId == null) {
      // UNATTRIBUTABLE: the parent id is unreadable, so the owning ITEM is
      // unknown and cannot be narrowed by anything else on the row.
      hasUnattributableOption = true;
      continue;
    }
    if (!declaredGroupIds.contains(groupId)) {
      // The parent group is not declared in this payload. EXCUSED only when
      // some group row named its item and was rejected — that item is being
      // marked unavailable, so the damage is contained to a product we can
      // name. Otherwise nothing accounts for this option and the affected
      // product cannot be identified at all.
      final excused =
          rejectedGroupIds.contains(groupId) || hasUnidentifiableOwnedGroup;
      if (!excused) hasUnattributableOption = true;
      continue;
    }
    if (optionId == null || delta is! int || name is! String) {
      // Attributable but unreadable: the group is known, so only its item is
      // marked. A skipped PAID option is exactly the silent under-charge this
      // boundary exists to stop.
      orphanedOptionGroupIds.add(groupId);
      continue;
    }
    if (!duplicateOptionIds.contains(optionId) &&
        firstClaimantByOptionId.containsKey(optionId)) {
      // Second sighting: blame BOTH claimants and drop this one.
      duplicateOptionIds.add(optionId);
      orphanedOptionGroupIds.add(firstClaimantByOptionId[optionId]!);
      orphanedOptionGroupIds.add(groupId);
      continue;
    }
    if (duplicateOptionIds.contains(optionId)) {
      orphanedOptionGroupIds.add(groupId);
      continue;
    }
    firstClaimantByOptionId[optionId] = groupId;
    (optionsByGroup[groupId] ??= <PosModifierOption>[]).add(
      PosModifierOption(
        id: optionId,
        name: name,
        priceDeltaMinor: delta,
        // KITCHEN-MEAT-001: tolerant parse of the option's meat metadata
        // (money-free {quantity,unit}); null when unset/disabled.
        kitchenMeat: KitchenMeat.tryFromJson(row['kitchen_meat']),
      ),
    );
  }

  final groups = <PosModifierGroup>[];
  for (final row in (raw['modifiers'] as List?) ?? const []) {
    if (row is! Map) continue;
    final id = exactId(row['id']);
    final menuItemId = exactId(row['menu_item_id']);
    final name = row['name'];
    if (menuItemId == null) {
      // MONEY-CODEX-FINAL-CLOSURE-005 (F3). This used to `continue`, reasoning
      // that a group naming no item "cannot make an item plain-addable". That
      // is exactly backwards: the group belonged to SOME item, and if it was
      // that item's only group, dropping it leaves the item looking PLAIN —
      // `groupsForItem` returns nothing and the add handler takes the
      // `groups.isEmpty -> addItem` branch, selling a configured product at base
      // price. The item most at risk is precisely the one we cannot name.
      hasUnattributableOption = true;
      continue;
    }
    if (id == null || name is! String || name.trim().isEmpty) {
      brokenConfigItemIds.add(menuItemId);
      continue;
    }
    final minSelect = row['min_select'];
    final maxSelect = row['max_select'];
    final maxQuantity = row['max_quantity'];
    // A group whose OPTIONS were unreadable is itself untrustworthy: the
    // cashier would be offered a subset of the real choices, at the real
    // prices, with no sign that one is missing.
    if (orphanedOptionGroupIds.contains(id)) {
      brokenConfigItemIds.add(menuItemId);
      continue;
    }
    // A group id claimed by TWO rows renders twice and double-counts every
    // selection made in it. Neither row can be trusted to be the one the
    // operator configured, so the product stops selling until the menu is
    // unambiguous.
    if (duplicateGroupIds.contains(id)) {
      brokenConfigItemIds.add(menuItemId);
      continue;
    }
    groups.add(
      PosModifierGroup(
        id: id,
        menuItemId: menuItemId,
        name: name,
        options: optionsByGroup[id] ?? const <PosModifierOption>[],
        singleSelect: row['selection_type'] == 'single',
        minSelect: minSelect is int ? minSelect : 0,
        maxSelect: maxSelect is int ? maxSelect : null,
        isRequired: row['is_required'] == true,
        // Quantity settings (modifier-quantity sprint). Tolerant parse: a
        // missing/wrong-typed value degrades to the no-stepper behaviour.
        allowQuantity: row['allow_quantity'] == true,
        maxQuantity: maxQuantity is int && maxQuantity > 0 ? maxQuantity : null,
      ),
    );
  }

  // MONEY-CODEX-FINAL-CORRECTIONS-004 (F3): A GROUP WITH NO OPTIONS IS BROKEN
  // CONFIGURATION, not an empty menu.
  //
  // This is the hole the 003A boundary left. An option whose `modifier_id` is
  // unreadable is unattributable, so nothing was blamed; an option whose
  // `modifier_id` names no declared group simply vanished. Either way the group
  // it belonged to could end up with ZERO options — and `groupsForItem` filters
  // empty groups out, so the product presented no choices at all and the add
  // handler took the `groups.isEmpty -> addItem` branch. A required PAID group
  // disappeared and the item sold at base price: precisely the silent
  // under-charge the boundary exists to prevent.
  //
  // A group the operator configured must offer something. Zero options means a
  // choice was lost, so its product stops selling until the menu is readable.
  for (final g in groups) {
    if (g.options.isEmpty) brokenConfigItemIds.add(g.menuItemId);
  }

  // MONEY-CODEX-FINAL-CLOSURE-005 (F3) — AN UNATTRIBUTABLE ROW FAILS THE WHOLE
  // PAYLOAD CLOSED.
  //
  // The per-item rule below can only protect items we can NAME. When an option's
  // parent cannot be read, or names a group this payload never declared, or a
  // group names no readable item, the owning product is genuinely unknown — and
  // `app.pos_menu` gives us no second path to it: a modifier row is
  // {id, menu_item_id, name, …} and an option row is
  // {id, modifier_id, name, display_order, price_delta_minor, kitchen_meat}.
  //
  // Marking "every item that has a group" would not be a safe superset either:
  // if the LOST group was an item's only one, that item appears in the payload
  // with no groups at all and would keep selling plain, at base price, missing a
  // choice the operator configured and charged for.
  //
  // So the affected set cannot be bounded, and a valid sibling option proves
  // nothing about what was lost. The POS refuses the whole menu and shows its
  // existing safe error state. That is recoverable — the operator fixes the row
  // and reloads; an undercharged sale is not.
  //
  // An unreadable group ROW is the same class and strictly worse: it loses a
  // WHOLE configured group and names nothing at all.
  if (hasUnattributableOption || hasUnreadableGroupRow) {
    throw const PosMenuUnavailable();
  }

  // THE CHOSEN RULE, stated: a product is unavailable when ANY group associated
  // with it cannot be interpreted safely — not merely the broken group dropped.
  // Dropping only the bad group would still sell the item, just without a
  // choice the operator configured and possibly charged for; the safe default
  // for money is to stop selling it until the configuration is readable.
  if (brokenConfigItemIds.isNotEmpty) {
    items = [
      for (final item in items)
        if (brokenConfigItemIds.contains(item.id))
          item.withAvailability(
            'unavailable',
            DemoMenuItem.configurationUnavailableReason,
          )
        else
          item,
    ];
  }

  // MENU-ORDER-001 (Codex #12): present categories AND items in the owner's
  // DASHBOARD order for browsing — categories by their display_order, items by
  // the COMPOSITE (category rank -> item rank -> stable input index). The RPC
  // does not guarantee row order, so without this the "All" view (and per-
  // category views) could interleave categories (a rank-1 item in category B
  // ahead of a rank-2 item in category A). Uses the SAME canonical sort the print
  // surfaces use, so browse order and print order agree.
  final orderedCategories = sortByMenuPrintOrder(
    categories,
    (c) => [catDisplayOrder[c.id] ?? 0],
  );
  final orderedItems = sortByMenuPrintOrder(
    items,
    (i) => [i.categoryDisplayOrder, i.itemDisplayOrder],
  );

  final currency = (raw['currency_code'] ?? '').toString();
  // 017 (Codex HIGH #2): every classifier link the server sent is proven
  // against the SAME item's own options before any consumer sees it.
  return PosMenuData.withTrustedPrepClassifiers(
    PosMenuData(
      categories: orderedCategories,
      items: orderedItems,
      currencyCode: currency.length == 3 ? currency : kDemoCurrencyCode,
      modifierGroups: groups,
    ),
  );
});
