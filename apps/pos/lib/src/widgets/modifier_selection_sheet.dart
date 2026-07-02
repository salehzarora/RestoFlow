import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../format/money_format.dart';
import '../state/cart_controller.dart';
import '../state/pos_menu_provider.dart';

/// The modifier/option picker shown when an item with modifier groups is added
/// (demo-readiness sprint): one section per group — radios for single-select,
/// checkboxes for multi-select with min/max enforcement — with live SIGNED
/// price deltas and a running total. The Add button stays disabled until every
/// required group meets its minimum; nothing is ever auto-selected for paid
/// options. Returns the selected modifiers via [onConfirm]; money is integer
/// minor units throughout (D-007).
class ModifierSelectionSheet extends StatefulWidget {
  const ModifierSelectionSheet({
    required this.item,
    required this.groups,
    required this.currencyCode,
    required this.onConfirm,
    super.key,
  });

  final DemoMenuItem item;
  final List<PosModifierGroup> groups;
  final String currencyCode;
  final void Function(List<SelectedModifier> selections) onConfirm;

  static Future<void> show(
    BuildContext context, {
    required DemoMenuItem item,
    required List<PosModifierGroup> groups,
    required String currencyCode,
    required void Function(List<SelectedModifier> selections) onConfirm,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ModifierSelectionSheet(
      item: item,
      groups: groups,
      currencyCode: currencyCode,
      onConfirm: onConfirm,
    ),
  );

  @override
  State<ModifierSelectionSheet> createState() => _ModifierSelectionSheetState();
}

class _ModifierSelectionSheetState extends State<ModifierSelectionSheet> {
  /// Selected option ids per group id.
  final Map<String, Set<String>> _selected = {};

  Set<String> _groupSelection(String groupId) => _selected[groupId] ?? const {};

  bool get _satisfied => widget.groups.every(
    (g) => _groupSelection(g.id).length >= g.effectiveMin,
  );

  int get _deltaTotal {
    var total = 0;
    for (final group in widget.groups) {
      final picked = _groupSelection(group.id);
      for (final option in group.options) {
        if (picked.contains(option.id)) total += option.priceDeltaMinor;
      }
    }
    return total;
  }

  void _toggle(PosModifierGroup group, PosModifierOption option) {
    setState(() {
      final picked = _selected.putIfAbsent(group.id, () => <String>{});
      if (group.singleSelect) {
        picked
          ..clear()
          ..add(option.id);
        return;
      }
      if (picked.contains(option.id)) {
        picked.remove(option.id);
        return;
      }
      final max = group.effectiveMax;
      if (max != null && picked.length >= max) return; // at capacity
      picked.add(option.id);
    });
  }

  List<SelectedModifier> _selections() => [
    for (final group in widget.groups)
      for (final option in group.options)
        if (_groupSelection(group.id).contains(option.id))
          SelectedModifier(
            optionId: option.id,
            groupName: group.name,
            optionName: option.name,
            priceDeltaMinor: option.priceDeltaMinor,
          ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final totalMinor = widget.item.priceMinor + _deltaTotal;
    final totalText = MoneyFormatter.formatMinor(
      totalMinor,
      widget.currencyCode,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (group.effectiveMin > 0)
                              RestoflowStatusPill(
                                label: l10n.posModifierRequired,
                                tone: RestoflowTone.warning,
                                icon: Icons.priority_high,
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
                          ).contains(option.id),
                          onToggle: () => _toggle(group, option),
                        ),
                    ],
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
                          widget.onConfirm(_selections());
                          Navigator.of(context).pop();
                        }
                      : null,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(l10n.posAddToCartWithTotal(totalText)),
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

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.group,
    required this.option,
    required this.currencyCode,
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final PosModifierGroup group;
  final PosModifierOption option;
  final String currencyCode;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A SIGNED delta renders as +/− money; a free option shows no price.
    final delta = option.priceDeltaMinor;
    final deltaText = delta == 0
        ? null
        : (delta > 0 ? '+' : '−') +
              MoneyFormatter.formatMinor(delta.abs(), currencyCode);

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
          color: selected ? scheme.primaryContainer : scheme.surface,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
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
                    if (deltaText != null) ...[
                      const SizedBox(width: RestoflowSpacing.sm),
                      Text(
                        deltaText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
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
