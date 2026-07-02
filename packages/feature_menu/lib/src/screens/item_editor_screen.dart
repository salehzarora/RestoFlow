import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/menu_validation.dart';
import '../data/minor_money.dart';
import '../models/menu_category.dart';
import '../models/menu_entity_type.dart';
import '../models/menu_field_error.dart';
import '../models/menu_item.dart';
import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';
import '../models/modifier.dart';
import '../models/modifier_option.dart';
import '../state/menu_providers.dart';
import '../widgets/menu_badges.dart';
import '../widgets/menu_components.dart';
import '../widgets/menu_entity_forms.dart';
import '../widgets/menu_image_panel.dart';
import '../widgets/menu_l10n.dart';

/// What the item editor is editing: an existing [item], or a new item in
/// [categoryId].
class MenuEditorTarget {
  const MenuEditorTarget({this.item, this.categoryId});

  final MenuItem? item;
  final String? categoryId;

  bool get isExisting => item != null;
}

/// The in-place item editor (RF-111). Rendered inside the menu surface subtree
/// (NOT a pushed route) so it stays under the feature ProviderScope overrides.
/// Structured as sectioned cards: details, sizes, variants, modifiers (+ options),
/// and the gated image panel. New items show the details only; existing items
/// show every section.
class ItemEditorView extends ConsumerStatefulWidget {
  const ItemEditorView({
    required this.snapshot,
    required this.scope,
    required this.target,
    required this.onClose,
    super.key,
  });

  final MenuSnapshot snapshot;
  final MenuScope scope;
  final MenuEditorTarget target;
  final VoidCallback onClose;

  @override
  ConsumerState<ItemEditorView> createState() => _ItemEditorViewState();
}

class _ItemEditorViewState extends ConsumerState<ItemEditorView> {
  late final MenuItem? _item = widget.target.item;
  late final TextEditingController _name = TextEditingController(
    text: _item?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: _item?.description ?? '',
  );
  late final TextEditingController _price = TextEditingController(
    text: _item == null
        ? ''
        : formatMinorUnits(_item.basePriceMinor, _item.currencyCode),
  );
  late final TextEditingController _currency = TextEditingController(
    text: _item?.currencyCode ?? widget.scope.currencyCode,
  );
  late final TextEditingController _order = TextEditingController(
    text: (_item?.displayOrder ?? 0).toString(),
  );
  late String? _categoryId = _item?.menuCategoryId ?? widget.target.categoryId;
  late bool _active = _item?.isActive ?? true;

  MenuFieldError? _nameError;
  MenuFieldError? _priceError;
  MenuFieldError? _currencyError;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _currency.dispose();
    _order.dispose();
    super.dispose();
  }

  String get _currencyCode => _item?.currencyCode ?? widget.scope.currencyCode;

  Future<void> _saveFields() async {
    final currencyText = _currency.text.trim().toUpperCase();
    final nameError = validateName(_name.text);
    final priceMinor = parseMajorToMinor(_price.text, currencyText);
    final priceError = validateBasePriceMinor(priceMinor);
    final currencyError = validateCurrencyCode(currencyText);
    final categoryId = _categoryId;
    setState(() {
      _nameError = nameError;
      _priceError = priceError;
      _currencyError = currencyError;
    });
    if (nameError != null ||
        priceError != null ||
        currencyError != null ||
        categoryId == null) {
      return;
    }

    setState(() => _submitting = true);
    final l10n = AppLocalizations.of(context);
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .upsertItem(
          id: _item?.id,
          menuCategoryId: categoryId,
          name: _name.text.trim(),
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          basePriceMinor: priceMinor!,
          currencyCode: currencyText,
          displayOrder: int.tryParse(_order.text.trim()) ?? 0,
          isActive: _active,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    outcome.fold(
      (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.menuSavedSnack)));
        if (!widget.target.isExisting) widget.onClose();
      },
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.menuWriteFailureText(failure))),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = widget.snapshot.visibleCategories();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorTopBar(
          title: _item?.name ?? l10n.menuAddItem,
          onClose: widget.onClose,
        ),
        const Divider(height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(RestoflowSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _detailsCard(context, l10n, categories),
                    if (_item != null) ...[
                      const SizedBox(height: RestoflowSpacing.lg),
                      _PricedChildSection(
                        title: l10n.menuSizesHeading,
                        icon: Icons.straighten,
                        addLabel: l10n.menuAddSize,
                        kind: PricedChildKind.size,
                        parentId: _item.id,
                        currencyCode: _currencyCode,
                        rows: widget.snapshot
                            .sizesForItem(_item.id)
                            .map(
                              (s) => _PricedChildVm(
                                id: s.id,
                                name: s.name,
                                deltaMinor: s.priceDeltaMinor,
                                isActive: s.isActive,
                                branchId: s.branchId,
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: RestoflowSpacing.lg),
                      _PricedChildSection(
                        title: l10n.menuVariantsHeading,
                        icon: Icons.tune,
                        addLabel: l10n.menuAddVariant,
                        kind: PricedChildKind.variant,
                        parentId: _item.id,
                        currencyCode: _currencyCode,
                        rows: widget.snapshot
                            .variantsForItem(_item.id)
                            .map(
                              (v) => _PricedChildVm(
                                id: v.id,
                                name: v.name,
                                deltaMinor: v.priceDeltaMinor,
                                isActive: v.isActive,
                                branchId: v.branchId,
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: RestoflowSpacing.lg),
                      _ModifiersSection(
                        item: _item,
                        modifiers: widget.snapshot.modifiersForItem(_item.id),
                        snapshot: widget.snapshot,
                        currencyCode: _currencyCode,
                      ),
                      const SizedBox(height: RestoflowSpacing.lg),
                      MenuImagePanel(item: _item),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailsCard(
    BuildContext context,
    AppLocalizations l10n,
    List<MenuCategory> categories,
  ) {
    return MenuSectionCard(
      title: l10n.menuItemDetailsSection,
      icon: Icons.info_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('menu-item-name'),
            controller: _name,
            decoration: InputDecoration(
              labelText: l10n.menuNameLabel,
              border: const OutlineInputBorder(),
              errorText: _nameError == null
                  ? null
                  : l10n.menuFieldErrorText(_nameError!),
            ),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: l10n.menuDescriptionLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('menu-item-price'),
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.menuPriceLabel,
                    border: const OutlineInputBorder(),
                    errorText: _priceError == null
                        ? null
                        : l10n.menuFieldErrorText(_priceError!),
                  ),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: TextField(
                  controller: _currency,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: l10n.menuCurrencyLabel,
                    border: const OutlineInputBorder(),
                    errorText: _currencyError == null
                        ? null
                        : l10n.menuFieldErrorText(_currencyError!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: InputDecoration(
              labelText: l10n.menuCategoryFieldLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final category in categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: (value) => setState(() => _categoryId = value),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _order,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.menuDisplayOrderLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.menuActiveLabel),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _submitting ? null : widget.onClose,
                child: Text(l10n.menuCancelAction),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              FilledButton.icon(
                key: const ValueKey('menu-item-save'),
                onPressed: _submitting ? null : _saveFields,
                icon: const Icon(Icons.check, size: 18),
                label: Text(l10n.menuSaveAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditorTopBar extends StatelessWidget {
  const _EditorTopBar({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: onClose,
            icon: const BackButtonIcon(),
          ),
          const SizedBox(width: RestoflowSpacing.md),
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
        ],
      ),
    );
  }
}

/// A view-model for the structurally-identical priced children.
class _PricedChildVm {
  const _PricedChildVm({
    required this.id,
    required this.name,
    required this.deltaMinor,
    required this.isActive,
    required this.branchId,
  });

  final String id;
  final String name;
  final int deltaMinor;
  final bool isActive;
  final String? branchId;
}

MenuEntityType _entityForKind(PricedChildKind kind) => switch (kind) {
  PricedChildKind.size => MenuEntityType.size,
  PricedChildKind.variant => MenuEntityType.variant,
  PricedChildKind.option => MenuEntityType.modifierOption,
};

class _PricedChildSection extends ConsumerWidget {
  const _PricedChildSection({
    required this.title,
    required this.icon,
    required this.addLabel,
    required this.kind,
    required this.parentId,
    required this.currencyCode,
    required this.rows,
    this.embedded = false,
  });

  final String title;
  final IconData icon;
  final String addLabel;
  final PricedChildKind kind;
  final String parentId;
  final String currencyCode;
  final List<_PricedChildVm> rows;

  /// When true the section renders WITHOUT its own card chrome (a plain
  /// header row + rows) — used inside the modifier tiles so options stop
  /// being a card-in-card-in-card.
  final bool embedded;

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    final l10n = AppLocalizations.of(context);
    if (!await showMenuDeleteConfirm(context)) return;
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .softDelete(entity: _entityForKind(kind), id: id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome.fold(
            (_) => l10n.menuDeletedSnack,
            (_) => l10n.menuWriteProblem,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final addButton = TextButton.icon(
      onPressed: () => showPricedChildFormDialog(
        context,
        kind: kind,
        parentId: parentId,
        currencyCode: currencyCode,
      ),
      icon: const Icon(Icons.add, size: RestoflowIconSizes.sm),
      label: Text(addLabel),
    );
    final content = rows.isEmpty
        ? Padding(
            padding: EdgeInsets.all(
              embedded ? RestoflowSpacing.sm : RestoflowSpacing.lg,
            ),
            child: Text(
              '—',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _PricedChildRow(
                  row: rows[i],
                  currencyCode: currencyCode,
                  onEdit: () => showPricedChildFormDialog(
                    context,
                    kind: kind,
                    parentId: parentId,
                    currencyCode: currencyCode,
                    id: rows[i].id,
                    initialName: rows[i].name,
                    initialDeltaMinor: rows[i].deltaMinor,
                    initialActive: rows[i].isActive,
                  ),
                  onDelete: () => _delete(context, ref, rows[i].id),
                ),
              ],
            ],
          );
    if (embedded) {
      // Chrome-free variant for nesting inside a modifier tile: a light
      // header row + the option rows, no extra card/border/divider layers.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: RestoflowIconSizes.sm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              addButton,
            ],
          ),
          content,
        ],
      );
    }
    return MenuSectionCard(
      title: title,
      icon: icon,
      contentPadding: EdgeInsets.zero,
      trailing: addButton,
      child: content,
    );
  }
}

class _PricedChildRow extends StatelessWidget {
  const _PricedChildRow({
    required this.row,
    required this.currencyCode,
    required this.onEdit,
    required this.onDelete,
  });

  final _PricedChildVm row;
  final String currencyCode;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.xs,
        RestoflowSpacing.sm,
        RestoflowSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(row.name, style: theme.textTheme.bodyLarge),
                ),
                if (!row.isActive) ...[
                  const SizedBox(width: RestoflowSpacing.sm),
                  MenuPill(
                    label: l10n.menuInactiveBadge,
                    background: theme.colorScheme.surfaceContainerHighest,
                    foreground: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
          Text(
            formatMinorUnits(row.deltaMinor, currencyCode),
            style: theme.textTheme.titleSmall,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'edit', child: Text(l10n.menuEditAction)),
              PopupMenuItem(
                value: 'delete',
                child: Text(l10n.menuDeleteAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModifiersSection extends ConsumerWidget {
  const _ModifiersSection({
    required this.item,
    required this.modifiers,
    required this.snapshot,
    required this.currencyCode,
  });

  final MenuItem item;
  final List<Modifier> modifiers;
  final MenuSnapshot snapshot;
  final String currencyCode;

  Future<void> _deleteModifier(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (!await showMenuDeleteConfirm(context)) return;
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .softDelete(entity: MenuEntityType.modifier, id: id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome.fold(
            (_) => l10n.menuDeletedSnack,
            (_) => l10n.menuWriteProblem,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return MenuSectionCard(
      title: l10n.menuModifiersHeading,
      icon: Icons.layers_outlined,
      contentPadding: EdgeInsets.zero,
      trailing: TextButton.icon(
        onPressed: () => showModifierFormDialog(context, menuItemId: item.id),
        icon: const Icon(Icons.add, size: 18),
        label: Text(l10n.menuAddModifier),
      ),
      child: modifiers.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.lg),
              child: Text(
                '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.md),
              child: Column(
                children: [
                  for (final modifier in modifiers)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: RestoflowSpacing.md,
                      ),
                      child: _ModifierCard(
                        modifier: modifier,
                        item: item,
                        currencyCode: currencyCode,
                        options: snapshot.optionsForModifier(modifier.id),
                        onDelete: () =>
                            _deleteModifier(context, ref, modifier.id),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ModifierCard extends StatelessWidget {
  const _ModifierCard({
    required this.modifier,
    required this.item,
    required this.currencyCode,
    required this.options,
    required this.onDelete,
  });

  final Modifier modifier;
  final MenuItem item;
  final String currencyCode;
  final List<ModifierOption> options;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // A soft tinted tile, not another bordered card: the options list inside
    // renders chrome-free (embedded), so the editor stops stacking three
    // nested card borders.
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.layers_outlined,
                size: RestoflowIconSizes.md,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Text(modifier.name, style: theme.textTheme.titleMedium),
              ),
              MenuEntityBadges(
                isActive: modifier.isActive,
                branchId: modifier.branchId,
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    showModifierFormDialog(
                      context,
                      menuItemId: item.id,
                      id: modifier.id,
                      initialName: modifier.name,
                      initialSelectionType: modifier.selectionType,
                      initialMinSelect: modifier.minSelect,
                      initialMaxSelect: modifier.maxSelect,
                      initialRequired: modifier.isRequired,
                      initialDisplayOrder: modifier.displayOrder,
                      initialActive: modifier.isActive,
                    );
                  }
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(l10n.menuEditAction),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n.menuDeleteAction),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: RestoflowSpacing.sm),
          _PricedChildSection(
            title: l10n.menuOptionsHeading,
            icon: Icons.tonality,
            addLabel: l10n.menuAddOption,
            kind: PricedChildKind.option,
            parentId: modifier.id,
            currencyCode: currencyCode,
            embedded: true,
            rows: options
                .map(
                  (o) => _PricedChildVm(
                    id: o.id,
                    name: o.name,
                    deltaMinor: o.priceDeltaMinor,
                    isActive: o.isActive,
                    branchId: o.branchId,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
