import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../format/money_format.dart';
import '../pos_palette.dart';
import '../state/cart_controller.dart';
import '../state/pos_menu_provider.dart';

/// The modifier/option picker shown when an item with modifier groups is added
/// (demo-readiness sprint): one section per group — radios for single-select,
/// checkboxes for multi-select with min/max enforcement — with live SIGNED
/// price deltas and a running total. The Add button stays disabled until every
/// required group meets its minimum; nothing is ever auto-selected for paid
/// options. Returns the selected modifiers via [onConfirm]; money is integer
/// minor units throughout (D-007).
///
/// Menu/media sprint (Part E, cashier flow polish): the header carries the item
/// image thumbnail (category-icon fallback) + the BASE price so base vs running
/// total is readable; every group header shows a Required/Optional pill AND a
/// live selected-count pill (danger while a required minimum is unmet, warning
/// when a multi group is at capacity); zero-delta options say "free" instead of
/// showing nothing.
///
/// Modifier-quantity sprint: options in a quantity-enabled group carry a
/// −/+ stepper (0 = unselected; up to the group's per-option max); the delta
/// counts × quantity in the running total. An optional per-item note field
/// ("بدون بصل") rides the bottom of the sheet and is returned alongside the
/// selections — min/max selection rules and single-select behaviour are
/// unchanged.
class ModifierSelectionSheet extends StatefulWidget {
  const ModifierSelectionSheet({
    required this.item,
    required this.groups,
    required this.currencyCode,
    required this.onConfirm,
    this.category,
    this.initialSelections = const <SelectedModifier>[],
    this.initialNote,
    this.isEdit = false,
    super.key,
  });

  final DemoMenuItem item;
  final List<PosModifierGroup> groups;
  final String currencyCode;

  /// Called with the selected modifier snapshots and the cashier's optional
  /// per-item note (null when left blank).
  final void Function(List<SelectedModifier> selections, String? note)
  onConfirm;

  /// The owning category of the ACTIVE menu — the header thumbnail's icon
  /// fallback (real categories carry their own palette entry); null falls back
  /// to the demo lookup, mirroring [MenuItemCard].
  final DemoCategory? category;

  /// TABLET-UX-001 (A): when EDITING an existing cart line, its current selected
  /// modifiers (matched back to [groups] by option id) prefill the sheet. Empty
  /// (the default) is the normal add flow — nothing preselected.
  final List<SelectedModifier> initialSelections;

  /// TABLET-UX-001 (A): the cart line's current per-item note to prefill (edit).
  final String? initialNote;

  /// TABLET-UX-001 (A): true when reopened to EDIT a cart line — the confirm
  /// button reads "Save changes" (saving REPLACES the line, never duplicates it).
  final bool isEdit;

  static Future<void> show(
    BuildContext context, {
    required DemoMenuItem item,
    required List<PosModifierGroup> groups,
    required String currencyCode,
    required void Function(List<SelectedModifier> selections, String? note)
    onConfirm,
    DemoCategory? category,
    List<SelectedModifier> initialSelections = const <SelectedModifier>[],
    String? initialNote,
    bool isEdit = false,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ModifierSelectionSheet(
      item: item,
      groups: groups,
      currencyCode: currencyCode,
      onConfirm: onConfirm,
      category: category,
      initialSelections: initialSelections,
      initialNote: initialNote,
      isEdit: isEdit,
    ),
  );

  @override
  State<ModifierSelectionSheet> createState() => _ModifierSelectionSheetState();
}

class _ModifierSelectionSheetState extends State<ModifierSelectionSheet> {
  /// Selected quantity per option id, per group id (>= 1; an absent option is
  /// unselected). Non-quantity selections are simply quantity 1.
  final Map<String, Map<String, int>> _selected = {};

  /// The optional per-item cashier note ("بدون بصل").
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // TABLET-UX-001 (A): prefill from the cart line being edited. Each initial
    // selection is matched back to its group by option id (a SelectedModifier
    // snapshot carries the option id + its taken quantity), so re-picking works
    // against the live groups. The note is restored verbatim.
    for (final selection in widget.initialSelections) {
      for (final group in widget.groups) {
        if (group.options.any((o) => o.id == selection.optionId)) {
          (_selected[group.id] ??= <String, int>{})[selection.optionId] =
              selection.quantity;
          break;
        }
      }
    }
    if (widget.initialNote != null) {
      _noteController.text = widget.initialNote!;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Map<String, int> _groupSelection(String groupId) =>
      _selected[groupId] ?? const {};

  /// Min/max selection rules keep counting DISTINCT options — a quantity on
  /// one option never changes how many options are considered chosen.
  bool get _satisfied => widget.groups.every(
    (g) => _groupSelection(g.id).length >= g.effectiveMin,
  );

  int get _deltaTotal {
    var total = 0;
    for (final group in widget.groups) {
      final picked = _groupSelection(group.id);
      for (final option in group.options) {
        total += option.priceDeltaMinor * (picked[option.id] ?? 0);
      }
    }
    return total;
  }

  void _toggle(PosModifierGroup group, PosModifierOption option) {
    setState(() {
      final picked = _selected.putIfAbsent(group.id, () => <String, int>{});
      if (group.singleSelect) {
        picked
          ..clear()
          ..[option.id] = 1;
        return;
      }
      if (picked.containsKey(option.id)) {
        picked.remove(option.id);
        return;
      }
      final max = group.effectiveMax;
      if (max != null && picked.length >= max) return; // at capacity
      picked[option.id] = 1;
    });
  }

  /// + on a quantity-enabled option: selects it at 1, then counts up to the
  /// group's per-option [PosModifierGroup.maxQuantity] (null = no cap).
  /// Selecting a NEW option still respects the distinct-options capacity.
  void _increment(PosModifierGroup group, PosModifierOption option) {
    setState(() {
      final picked = _selected.putIfAbsent(group.id, () => <String, int>{});
      final current = picked[option.id] ?? 0;
      if (current == 0) {
        final max = group.effectiveMax;
        if (max != null && picked.length >= max) return; // at capacity
        picked[option.id] = 1;
        return;
      }
      final maxQuantity = group.maxQuantity;
      if (maxQuantity != null && current >= maxQuantity) return; // at cap
      picked[option.id] = current + 1;
    });
  }

  /// − on a quantity-enabled option: counts down; 0 unselects it.
  void _decrement(PosModifierGroup group, PosModifierOption option) {
    setState(() {
      final picked = _selected.putIfAbsent(group.id, () => <String, int>{});
      final current = picked[option.id] ?? 0;
      if (current <= 1) {
        picked.remove(option.id);
      } else {
        picked[option.id] = current - 1;
      }
    });
  }

  List<SelectedModifier> _selections() => [
    for (final group in widget.groups)
      for (final option in group.options)
        if (_groupSelection(group.id).containsKey(option.id))
          SelectedModifier(
            optionId: option.id,
            groupName: group.name,
            optionName: option.name,
            priceDeltaMinor: option.priceDeltaMinor,
            quantity: _groupSelection(group.id)[option.id] ?? 1,
            // KITCHEN-MEAT-001: carry the option's meat contribution into the
            // order-time snapshot (money-free; null when unconfigured).
            kitchenMeat: option.kitchenMeat,
          ),
  ];

  /// The trimmed note, or null when the field was left blank.
  String? get _note {
    final text = _noteController.text.trim();
    return text.isEmpty ? null : text;
  }

  /// The live "n/m" (or open-ended "n") selected-count label for a group.
  String _countLabel(AppLocalizations l10n, PosModifierGroup group, int count) {
    final max = group.effectiveMax;
    return max == null
        ? l10n.posModifierSelectedCountOpen(count)
        : l10n.posModifierSelectedCount(count, max);
  }

  /// The count pill's tone: DANGER while a required minimum is unmet (the
  /// blocked-Add culprit is marked before the cashier hunts for it), WARNING
  /// when a multi-select group is at capacity (further taps are no-ops), and
  /// quiet neutral otherwise. A satisfied single-select stays neutral — taps
  /// there swap the choice rather than being blocked.
  RestoflowTone _countTone(PosModifierGroup group, int count) {
    if (count < group.effectiveMin) return RestoflowTone.danger;
    final max = group.effectiveMax;
    if (!group.singleSelect && max != null && count >= max) {
      return RestoflowTone.warning;
    }
    return RestoflowTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final category = widget.category ?? categoryById(widget.item.categoryId);
    final basePriceText = MoneyFormatter.formatMinor(
      widget.item.priceMinor,
      widget.currencyCode,
    );
    final totalMinor = widget.item.priceMinor + _deltaTotal;
    final totalText = MoneyFormatter.formatMinor(
      totalMinor,
      widget.currencyCode,
    );

    return SafeArea(
      // The on-screen keyboard (note field) pushes the sheet content up
      // instead of covering it (isScrollControlled sheets don't auto-inset).
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Part E header: thumbnail + name + BASE price, so the cashier
              // reads base vs the running total at the bottom. NOTE: the base
              // price is a DIFFERENT money string than the running total once
              // any paid option is picked — tests pin the total's render count.
              Row(
                children: [
                  _ItemThumbnail(item: widget.item, category: category),
                  const SizedBox(width: RestoflowSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: RestoflowSpacing.xxs),
                        Text(
                          l10n.posModifierBasePrice(basePriceText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.sm),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final group in widget.groups) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: RestoflowSpacing.md,
                          bottom: RestoflowSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: RestoflowSpacing.sm),
                            // Live selected-count pill: n/m (or open-ended n).
                            RestoflowStatusPill(
                              label: _countLabel(
                                l10n,
                                group,
                                _groupSelection(group.id).length,
                              ),
                              tone: _countTone(
                                group,
                                _groupSelection(group.id).length,
                              ),
                            ),
                            const SizedBox(width: RestoflowSpacing.xs),
                            if (group.effectiveMin > 0)
                              RestoflowStatusPill(
                                label: l10n.posModifierRequired,
                                tone: RestoflowTone.warning,
                                icon: Icons.priority_high,
                              )
                            else
                              // Quiet counterpart so "no pill" never has to be
                              // interpreted: this group may be skipped.
                              RestoflowStatusPill(
                                label: l10n.posModifierOptional,
                              ),
                          ],
                        ),
                      ),
                      for (final option in group.options)
                        _OptionTile(
                          key: ValueKey('modifier-option-${option.id}'),
                          group: group,
                          option: option,
                          currencyCode: widget.currencyCode,
                          selected: _groupSelection(
                            group.id,
                          ).containsKey(option.id),
                          quantity: _groupSelection(group.id)[option.id] ?? 0,
                          onToggle: () => _toggle(group, option),
                          onIncrement: group.hasQuantitySteppers
                              ? () => _increment(group, option)
                              : null,
                          onDecrement: group.hasQuantitySteppers
                              ? () => _decrement(group, option)
                              : null,
                        ),
                    ],
                    // Part F: the optional per-item note ("بدون بصل") — sent
                    // with the order, shown under the cart line, on the KDS
                    // ticket, and on the receipt/print. Data, never money.
                    Padding(
                      padding: const EdgeInsets.only(top: RestoflowSpacing.md),
                      child: TextField(
                        key: const Key('modifier-item-note'),
                        controller: _noteController,
                        maxLength: 140,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l10n.posModifierItemNoteLabel,
                          hintText: l10n.posModifierItemNoteHint,
                          counterText: '',
                          prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: RestoflowSpacing.md),
              // Design-polish: a visible running total ABOVE the confirm
              // button, so the price consequence of each pick is readable
              // without parsing the button label.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.posReceiptTotal,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    totalText,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('modifier-add-button'),
                  // Disabled until every required group meets its minimum.
                  onPressed: _satisfied
                      ? () {
                          widget.onConfirm(_selections(), _note);
                          Navigator.of(context).pop();
                        }
                      : null,
                  // TABLET-UX-001 (A): "Save changes" when editing an existing
                  // cart line (it replaces the line); the add flow is unchanged.
                  icon: Icon(
                    widget.isEdit ? Icons.check : Icons.add_shopping_cart,
                  ),
                  label: Text(
                    widget.isEdit
                        ? l10n.posEditSaveChanges
                        : l10n.posAddToCartWithTotal(totalText),
                  ),
                  style: RestoflowButtonStyles.big(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet header's item thumbnail (Part E): the product photo when the menu
/// resolved a signed [DemoMenuItem.imageUrl] (real menus only), otherwise —
/// and on ANY load failure — the category-tinted icon, mirroring the menu
/// card's fallback. Images are never load-bearing.
class _ItemThumbnail extends StatelessWidget {
  const _ItemThumbnail({required this.item, required this.category});

  /// Thumbnail edge (56–72dp band; square, rounded).
  static const double _size = 64;

  final DemoMenuItem item;
  final DemoCategory category;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: category.color.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          category.icon,
          size: RestoflowIconSizes.lg,
          color: category.color.withValues(alpha: 0.85),
        ),
      ),
    );
    final url = item.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(RestoflowRadii.md),
      child: SizedBox(
        width: _size,
        height: _size,
        child: url == null
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.group,
    required this.option,
    required this.currencyCode,
    required this.selected,
    required this.onToggle,
    this.quantity = 0,
    this.onIncrement,
    this.onDecrement,
    super.key,
  });

  final PosModifierGroup group;
  final PosModifierOption option;
  final String currencyCode;
  final bool selected;
  final VoidCallback onToggle;

  /// Selected units of this option (0 = unselected; only ever > 1 on a
  /// quantity-enabled group).
  final int quantity;

  /// Non-null only on quantity-enabled groups — renders the −/+ stepper.
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A SIGNED delta renders as +/− money; a zero delta says "free" (Part E)
    // instead of showing nothing, so included-at-no-charge is explicit.
    final delta = option.priceDeltaMinor;
    final deltaText = delta == 0
        ? null
        : MoneyFormatter.formatSignedDeltaMinor(delta, currencyCode);

    final control = group.singleSelect
        ? Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          )
        : Icon(
            selected ? Icons.check_box : Icons.check_box_outline_blank,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );

    // Design-polish: options are >=48dp bordered tiles with an unmistakable
    // selected state (primary tint + accent border) instead of dense,
    // zero-padding ListTiles. The ValueKey stays on the tappable InkWell.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xxs),
      // Subtle interaction polish: selection tint/border fades (finite
      // implicit animation; the ink ripple rides a transparent Material on
      // top so it stays visible).
      child: AnimatedContainer(
        duration: RestoflowDurations.fast,
        decoration: BoxDecoration(
          // DESIGN-004: selected = warm mint tint + a 1.5px brand-green border.
          color: selected ? kPosSelectedTint : scheme.surface,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          border: Border.all(
            color: selected ? scheme.primary : kRestoflowHairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: RestoflowSpacing.md,
                  vertical: RestoflowSpacing.sm,
                ),
                child: Row(
                  children: [
                    control,
                    const SizedBox(width: RestoflowSpacing.md),
                    Expanded(
                      child: Text(
                        option.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: RestoflowSpacing.sm),
                    if (deltaText != null)
                      Text(
                        deltaText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      // Quiet "free" label — lighter weight than a paid delta.
                      Text(
                        l10n.posModifierFree,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    if (onIncrement != null && onDecrement != null) ...[
                      const SizedBox(width: RestoflowSpacing.sm),
                      _OptionQuantityStepper(
                        l10n: l10n,
                        optionId: option.id,
                        quantity: quantity,
                        // At the per-option cap the + is disabled (honest
                        // no-op); − at 0 is disabled too.
                        canIncrement:
                            group.maxQuantity == null ||
                            quantity < group.maxQuantity!,
                        onIncrement: onIncrement!,
                        onDecrement: onDecrement!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The −/+ per-option quantity stepper (modifier-quantity sprint): a compact
/// bordered pill mirroring the cart's line stepper. 0 = unselected; + selects
/// at 1 and counts up to the group's per-option cap; − counts down to 0.
class _OptionQuantityStepper extends StatelessWidget {
  const _OptionQuantityStepper({
    required this.l10n,
    required this.optionId,
    required this.quantity,
    required this.canIncrement,
    required this.onIncrement,
    required this.onDecrement,
  });

  final AppLocalizations l10n;
  final String optionId;
  final int quantity;
  final bool canIncrement;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantityText = quantity.toString();

    // The pill swallows every tap it receives (including on a DISABLED −/+
    // at a bound): otherwise the tap falls through to the tile's InkWell and
    // silently toggles the whole option off — losing the counted quantity.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(RestoflowRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: ValueKey('modifier-qty-dec-$optionId'),
              onPressed: quantity > 0 ? onDecrement : null,
              icon: const Icon(Icons.remove, size: RestoflowIconSizes.sm),
              tooltip: l10n.posDecreaseQuantity,
              padding: EdgeInsets.zero,
              // DESIGN-001: raised to the product's 44dp touch floor (was 40).
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            SizedBox(
              width: 24,
              child: Text(
                quantityText,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              key: ValueKey('modifier-qty-inc-$optionId'),
              onPressed: canIncrement ? onIncrement : null,
              icon: const Icon(Icons.add, size: RestoflowIconSizes.sm),
              tooltip: l10n.posIncreaseQuantity,
              padding: EdgeInsets.zero,
              // DESIGN-001: raised to the product's 44dp touch floor (was 40).
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      ),
    );
  }
}
