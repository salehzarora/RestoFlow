import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/menu_config_copy.dart';
import '../data/menu_validation.dart';
import '../data/minor_money.dart';
import '../models/menu_field_error.dart';
import 'menu_badges.dart';
import 'menu_l10n.dart';

/// OPS-043 Phase 4 — the LOCAL editor for copied modifier groups and options.
///
/// Everything the persisted Modifiers section offers, on rows that do not exist
/// yet. It is deliberately and completely inert: no provider, no controller, no
/// repository, no writer, no id from any server. It mutates the in-memory
/// [MenuCopiedConfig] and calls [onChanged] so the host can rebuild — which is
/// why "editing the copied configuration performs zero writes" is a property of
/// the type signature here, not of a code path someone has to keep honest.
///
/// It exists because the persisted `_ModifiersSection` cannot help: every row it
/// renders is a server row, addressed by a server id, edited through dialogs
/// that write immediately. Before Save there is no such row, so a copied
/// configuration had nothing to render itself in — the operator had to save
/// first and edit afterwards, which is exactly what a DRAFT is supposed to avoid.
class MenuCopiedModifiersDraftEditor extends StatelessWidget {
  const MenuCopiedModifiersDraftEditor({
    required this.config,
    required this.currencyCode,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final MenuCopiedConfig config;
  final String currencyCode;

  /// Called after any mutation, so the host rebuilds. Never a write.
  final VoidCallback onChanged;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (config.groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
        child: Text(
          '—',
          key: const ValueKey('menu-copy-draft-empty'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      key: const ValueKey('menu-copy-draft-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in config.groups) ...[
          _DraftGroupCard(
            config: config,
            group: group,
            currencyCode: currencyCode,
            onChanged: onChanged,
            enabled: enabled,
          ),
          const SizedBox(height: RestoflowSpacing.sm),
        ],
        Text(
          l10n.menuCopyDraftEditHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DraftGroupCard extends StatelessWidget {
  const _DraftGroupCard({
    required this.config,
    required this.group,
    required this.currencyCode,
    required this.onChanged,
    required this.enabled,
  });

  final MenuCopiedConfig config;
  final CopiedGroupDraft group;
  final String currencyCode;
  final VoidCallback onChanged;
  final bool enabled;

  String _summary(AppLocalizations l10n) {
    final parts = <String>[
      group.selectionType == 'multiple'
          ? l10n.menuSelectionMultiple
          : l10n.menuSelectionSingle,
      '${l10n.menuMinSelectLabel} ${group.minSelect}',
      if (group.maxSelect != null)
        '${l10n.menuMaxSelectLabel} ${group.maxSelect}',
      if (group.isRequired) l10n.menuRequiredLabel,
      if (group.allowQuantity)
        group.maxQuantity == null
            ? l10n.menuAllowQuantityLabel
            : '${l10n.menuAllowQuantityLabel} ≤ ${group.maxQuantity}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('menu-copy-draft-group-${group.sourceModifierId}'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      padding: const EdgeInsets.all(RestoflowSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.layers_outlined,
                size: RestoflowIconSizes.sm,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: theme.textTheme.titleSmall),
                    Text(
                      _summary(l10n),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!group.isActive)
                MenuPill(
                  label: l10n.menuInactiveBadge,
                  background: theme.colorScheme.surfaceContainerHighest,
                  foreground: theme.colorScheme.onSurfaceVariant,
                ),
              IconButton(
                key: ValueKey(
                  'menu-copy-draft-group-edit-${group.sourceModifierId}',
                ),
                tooltip: l10n.menuEditAction,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: enabled
                    ? () async {
                        if (await showCopiedGroupDraftDialog(context, group)) {
                          onChanged();
                        }
                      }
                    : null,
              ),
              IconButton(
                key: ValueKey(
                  'menu-copy-draft-group-delete-${group.sourceModifierId}',
                ),
                tooltip: l10n.menuDeleteAction,
                icon: const Icon(Icons.close, size: 18),
                onPressed: enabled
                    ? () async {
                        final linked = group.options.any(
                          (o) => _isClassifierTarget(config, o),
                        );
                        if (await showCopiedDraftRemoveConfirm(
                          context,
                          clearsLinks: linked,
                        )) {
                          config.removeGroup(group);
                          onChanged();
                        }
                      }
                    : null,
              ),
            ],
          ),
          const Divider(height: RestoflowSpacing.md),
          for (final option in group.options)
            _DraftOptionRow(
              config: config,
              option: option,
              currencyCode: currencyCode,
              onChanged: onChanged,
              enabled: enabled,
            ),
          if (group.options.isEmpty)
            Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.sm),
              child: Text(
                '—',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

bool _isClassifierTarget(MenuCopiedConfig config, CopiedOptionDraft option) =>
    config.classifierTargetSourceIds.contains(option.sourceOptionId);

class _DraftOptionRow extends StatelessWidget {
  const _DraftOptionRow({
    required this.config,
    required this.option,
    required this.currencyCode,
    required this.onChanged,
    required this.enabled,
  });

  final MenuCopiedConfig config;
  final CopiedOptionDraft option;
  final String currencyCode;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final classifierName = config.optionNameBySourceId(
      option.classifierSourceOptionId,
    );
    final notes = <String>[
      if (option.hasKitchenMeat)
        '${l10n.menuKitchenMeatSection}: ${formatPrepQuantityText(option.kitchenMeatQuantity)}'
            '${option.kitchenMeatUnit.isEmpty ? '' : ' ${option.kitchenMeatUnit}'}',
      if (classifierName != null && classifierName.isNotEmpty)
        '${l10n.menuPrepClassifierLabel}: $classifierName',
    ];
    return Padding(
      key: ValueKey('menu-copy-draft-option-${option.sourceOptionId}'),
      padding: const EdgeInsetsDirectional.only(
        start: RestoflowSpacing.sm,
        bottom: RestoflowSpacing.xxs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        option.name,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!option.isActive) ...[
                      const SizedBox(width: RestoflowSpacing.xs),
                      MenuPill(
                        label: l10n.menuInactiveBadge,
                        background: theme.colorScheme.surfaceContainerHighest,
                        foreground: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                if (notes.isNotEmpty)
                  Text(
                    notes.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            formatMinorUnits(option.priceDeltaMinor, currencyCode),
            style: theme.textTheme.bodySmall,
          ),
          IconButton(
            key: ValueKey(
              'menu-copy-draft-option-edit-${option.sourceOptionId}',
            ),
            tooltip: l10n.menuEditAction,
            icon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: enabled
                ? () async {
                    if (await showCopiedOptionDraftDialog(
                      context,
                      config: config,
                      option: option,
                      currencyCode: currencyCode,
                    )) {
                      onChanged();
                    }
                  }
                : null,
          ),
          IconButton(
            key: ValueKey(
              'menu-copy-draft-option-delete-${option.sourceOptionId}',
            ),
            tooltip: l10n.menuDeleteAction,
            icon: const Icon(Icons.close, size: 16),
            onPressed: enabled
                ? () async {
                    if (await showCopiedDraftRemoveConfirm(
                      context,
                      clearsLinks: _isClassifierTarget(config, option),
                    )) {
                      config.removeOption(option);
                      onChanged();
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// Renders a kitchen-count quantity without a spurious `.0` on a whole number.
String formatPrepQuantityText(num? quantity) {
  if (quantity == null) return '';
  if (quantity is int) return '$quantity';
  return quantity == quantity.roundToDouble()
      ? '${quantity.round()}'
      : '$quantity';
}

/// Confirms removing a DRAFT row. Nothing has been written, so the wording says
/// so rather than borrowing the persisted "you can restore it later" copy —
/// there is nothing to restore and nothing to delete.
Future<bool> showCopiedDraftRemoveConfirm(
  BuildContext context, {
  required bool clearsLinks,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('menu-copy-draft-remove-confirm'),
      icon: const Icon(Icons.close),
      title: Text(l10n.menuCopyDraftRemoveTitle),
      content: Text(
        clearsLinks
            ? '${l10n.menuCopyDraftRemoveBody}\n\n'
                  '${l10n.menuCopyDraftRemoveLinked}'
            : l10n.menuCopyDraftRemoveBody,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.menuCancelAction),
        ),
        FilledButton(
          key: const ValueKey('menu-copy-draft-remove-accept'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.menuConfirmDelete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Edits a copied GROUP in place. Pure: it mutates the draft and pops true.
Future<bool> showCopiedGroupDraftDialog(
  BuildContext context,
  CopiedGroupDraft group,
) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CopiedGroupDraftDialog(group: group),
  );
  return saved ?? false;
}

/// Edits a copied OPTION in place, including its kitchen count and its split-by
/// link. Pure: it mutates the draft and pops true.
Future<bool> showCopiedOptionDraftDialog(
  BuildContext context, {
  required MenuCopiedConfig config,
  required CopiedOptionDraft option,
  required String currencyCode,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CopiedOptionDraftDialog(
      config: config,
      option: option,
      currencyCode: currencyCode,
    ),
  );
  return saved ?? false;
}

class _CopiedGroupDraftDialog extends StatefulWidget {
  const _CopiedGroupDraftDialog({required this.group});

  final CopiedGroupDraft group;

  @override
  State<_CopiedGroupDraftDialog> createState() =>
      _CopiedGroupDraftDialogState();
}

class _CopiedGroupDraftDialogState extends State<_CopiedGroupDraftDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.group.name,
  );
  late final TextEditingController _minSelect = TextEditingController(
    text: '${widget.group.minSelect}',
  );
  late final TextEditingController _maxSelect = TextEditingController(
    text: widget.group.maxSelect?.toString() ?? '',
  );
  late final TextEditingController _displayOrder = TextEditingController(
    text: '${widget.group.displayOrder}',
  );
  late final TextEditingController _maxQuantity = TextEditingController(
    text: widget.group.maxQuantity?.toString() ?? '',
  );
  late String _selectionType = widget.group.selectionType;
  late bool _isRequired = widget.group.isRequired;
  late bool _isActive = widget.group.isActive;
  late bool _allowQuantity = widget.group.allowQuantity;

  MenuFieldError? _nameError;
  MenuFieldError? _minError;
  MenuFieldError? _maxError;
  MenuFieldError? _maxQuantityError;

  @override
  void dispose() {
    _name.dispose();
    _minSelect.dispose();
    _maxSelect.dispose();
    _displayOrder.dispose();
    _maxQuantity.dispose();
    super.dispose();
  }

  void _save() {
    // Mirrors the persisted form AND the server rule: the backend rejects
    // `single` + allow_quantity, so a draft can never be built into one.
    final allowQuantity = _selectionType == 'multiple' && _allowQuantity;
    final minSelect = int.tryParse(_minSelect.text.trim()) ?? -1;
    final maxSelectText = _maxSelect.text.trim();
    final maxSelect = maxSelectText.isEmpty
        ? null
        : int.tryParse(maxSelectText);
    final maxQuantityText = _maxQuantity.text.trim();
    final maxQuantity = maxQuantityText.isEmpty
        ? null
        : int.tryParse(maxQuantityText);
    final nameError = validateName(_name.text);
    final minError = validateMinSelect(minSelect);
    final maxError = maxSelectText.isNotEmpty && maxSelect == null
        ? MenuFieldError.notAnInteger
        : validateMaxSelect(maxSelect, minSelect);
    final maxQuantityError = !allowQuantity
        ? null
        : (maxQuantityText.isNotEmpty && maxQuantity == null
              ? MenuFieldError.notAnInteger
              : validateMaxQuantity(maxQuantity));
    setState(() {
      _nameError = nameError;
      _minError = minError;
      _maxError = maxError;
      _maxQuantityError = maxQuantityError;
    });
    if (nameError != null ||
        minError != null ||
        maxError != null ||
        maxQuantityError != null) {
      return;
    }
    final group = widget.group
      ..name = _name.text.trim()
      ..selectionType = _selectionType
      ..minSelect = minSelect
      ..maxSelect = maxSelect
      ..isRequired = _isRequired
      ..isActive = _isActive
      ..allowQuantity = allowQuantity
      ..maxQuantity = allowQuantity ? maxQuantity : null;
    final order = int.tryParse(_displayOrder.text.trim());
    if (order != null && order >= 0) group.displayOrder = order;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('menu-copy-draft-group-dialog'),
      title: Text(l10n.menuEditTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('menu-copy-draft-group-name'),
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
              DropdownButtonFormField<String>(
                key: const ValueKey('menu-copy-draft-group-selection'),
                initialValue: _selectionType,
                decoration: InputDecoration(
                  labelText: l10n.menuSelectionTypeLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'single',
                    child: Text(l10n.menuSelectionSingle),
                  ),
                  DropdownMenuItem(
                    value: 'multiple',
                    child: Text(l10n.menuSelectionMultiple),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _selectionType = value ?? 'single'),
              ),
              const SizedBox(height: RestoflowSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('menu-copy-draft-group-min'),
                      controller: _minSelect,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.menuMinSelectLabel,
                        border: const OutlineInputBorder(),
                        errorText: _minError == null
                            ? null
                            : l10n.menuFieldErrorText(_minError!),
                      ),
                    ),
                  ),
                  const SizedBox(width: RestoflowSpacing.md),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('menu-copy-draft-group-max'),
                      controller: _maxSelect,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.menuMaxSelectLabel,
                        border: const OutlineInputBorder(),
                        errorText: _maxError == null
                            ? null
                            : l10n.menuFieldErrorText(_maxError!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.md),
              TextField(
                key: const ValueKey('menu-copy-draft-group-order'),
                controller: _displayOrder,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.menuDisplayOrderLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                key: const ValueKey('menu-copy-draft-group-required'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.menuRequiredLabel),
                value: _isRequired,
                onChanged: (value) => setState(() => _isRequired = value),
              ),
              SwitchListTile(
                key: const ValueKey('menu-copy-draft-group-active'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.menuActiveLabel),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              if (_selectionType == 'multiple')
                SwitchListTile(
                  key: const ValueKey('menu-copy-draft-group-allow-quantity'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.menuAllowQuantityLabel),
                  subtitle: Text(l10n.menuAllowQuantityHelp),
                  value: _allowQuantity,
                  onChanged: (value) => setState(() => _allowQuantity = value),
                ),
              if (_selectionType == 'multiple' && _allowQuantity)
                TextField(
                  key: const ValueKey('menu-copy-draft-group-max-quantity'),
                  controller: _maxQuantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.menuMaxQuantityLabel,
                    border: const OutlineInputBorder(),
                    errorText: _maxQuantityError == null
                        ? null
                        : l10n.menuFieldErrorText(_maxQuantityError!),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.menuCancelAction),
        ),
        FilledButton(
          key: const ValueKey('menu-copy-draft-group-save'),
          onPressed: _save,
          child: Text(l10n.menuSaveAction),
        ),
      ],
    );
  }
}

class _CopiedOptionDraftDialog extends StatefulWidget {
  const _CopiedOptionDraftDialog({
    required this.config,
    required this.option,
    required this.currencyCode,
  });

  final MenuCopiedConfig config;
  final CopiedOptionDraft option;
  final String currencyCode;

  @override
  State<_CopiedOptionDraftDialog> createState() =>
      _CopiedOptionDraftDialogState();
}

class _CopiedOptionDraftDialogState extends State<_CopiedOptionDraftDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.option.name,
  );
  late final TextEditingController _delta = TextEditingController(
    text: formatMinorUnits(widget.option.priceDeltaMinor, widget.currencyCode),
  );
  late final TextEditingController _displayOrder = TextEditingController(
    text: '${widget.option.displayOrder}',
  );
  late final TextEditingController _meatQuantity = TextEditingController(
    text: formatPrepQuantityText(widget.option.kitchenMeatQuantity),
  );
  late final TextEditingController _meatUnit = TextEditingController(
    text: widget.option.kitchenMeatUnit,
  );
  late bool _isActive = widget.option.isActive;
  late bool _meatEnabled = widget.option.hasKitchenMeat;

  /// The SOURCE id of the classifying draft option, '' = not split. A stable
  /// identity, so renaming either option leaves the link intact.
  late String _classifierSourceId = widget.option.classifierSourceOptionId;

  MenuFieldError? _nameError;
  MenuFieldError? _deltaError;
  MenuFieldError? _meatError;

  @override
  void dispose() {
    _name.dispose();
    _delta.dispose();
    _displayOrder.dispose();
    _meatQuantity.dispose();
    _meatUnit.dispose();
    super.dispose();
  }

  void _save() {
    final nameError = validateName(_name.text);
    final deltaMinor = parseMajorToMinor(_delta.text, widget.currencyCode);
    final deltaError = validatePriceDeltaMinor(deltaMinor);
    final quantity = _meatEnabled
        ? num.tryParse(_meatQuantity.text.trim())
        : null;
    final meatError = _meatEnabled && (quantity == null || quantity <= 0)
        ? MenuFieldError.notAnInteger
        : null;
    setState(() {
      _nameError = nameError;
      _deltaError = deltaError;
      _meatError = meatError;
    });
    if (nameError != null || deltaError != null || meatError != null) return;
    final option = widget.option
      ..name = _name.text.trim()
      ..priceDeltaMinor = deltaMinor!
      ..isActive = _isActive
      ..kitchenMeatQuantity = _meatEnabled ? quantity : null
      ..kitchenMeatUnit = _meatEnabled ? _meatUnit.text.trim() : ''
      // A link without a count classifies nothing, so it is dropped with it.
      ..classifierSourceOptionId = _meatEnabled ? _classifierSourceId : '';
    final order = int.tryParse(_displayOrder.text.trim());
    if (order != null && order >= 0) option.displayOrder = order;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final candidates = widget.config.classifierCandidatesFor(
      widget.option.sourceOptionId,
    );
    // A link whose target left the draft cannot be shown as selected.
    final selected =
        candidates.any((c) => c.sourceOptionId == _classifierSourceId)
        ? _classifierSourceId
        : '';
    return AlertDialog(
      key: const ValueKey('menu-copy-draft-option-dialog'),
      title: Text(l10n.menuEditTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('menu-copy-draft-option-name'),
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
                key: const ValueKey('menu-copy-draft-option-delta'),
                controller: _delta,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.menuPriceDeltaLabel,
                  suffixText: widget.currencyCode,
                  border: const OutlineInputBorder(),
                  errorText: _deltaError == null
                      ? null
                      : l10n.menuFieldErrorText(_deltaError!),
                ),
              ),
              const SizedBox(height: RestoflowSpacing.md),
              TextField(
                key: const ValueKey('menu-copy-draft-option-order'),
                controller: _displayOrder,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.menuDisplayOrderLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                key: const ValueKey('menu-copy-draft-option-active'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.menuActiveLabel),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              const Divider(),
              Text(
                l10n.menuKitchenMeatSection,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SwitchListTile(
                key: const ValueKey('menu-copy-draft-option-meat-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.menuKitchenMeatEnabledLabel),
                value: _meatEnabled,
                onChanged: (value) => setState(() => _meatEnabled = value),
              ),
              if (_meatEnabled) ...[
                TextField(
                  key: const ValueKey('menu-copy-draft-option-meat-quantity'),
                  controller: _meatQuantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.menuKitchenMeatQuantityLabel,
                    border: const OutlineInputBorder(),
                    errorText: _meatError == null
                        ? null
                        : l10n.menuFieldErrorText(_meatError!),
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.md),
                TextField(
                  key: const ValueKey('menu-copy-draft-option-meat-unit'),
                  controller: _meatUnit,
                  decoration: InputDecoration(
                    labelText: l10n.menuKitchenMeatUnitLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.md),
                // 019: split by ANOTHER option of this draft. The value is the
                // other option's SOURCE id — its stable identity — so renaming
                // either side before Save cannot break the link, and the flush
                // still maps it to the row's real id.
                DropdownButtonFormField<String>(
                  key: const ValueKey('menu-copy-draft-option-classifier'),
                  initialValue: selected,
                  decoration: InputDecoration(
                    labelText: l10n.menuPrepClassifierLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(l10n.menuPrepClassifierNone),
                    ),
                    for (final candidate in candidates)
                      DropdownMenuItem(
                        value: candidate.sourceOptionId,
                        child: Text(candidate.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _classifierSourceId = value ?? ''),
                ),
                const SizedBox(height: RestoflowSpacing.xs),
                Text(
                  l10n.menuPrepClassifierHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.menuCancelAction),
        ),
        FilledButton(
          key: const ValueKey('menu-copy-draft-option-save'),
          onPressed: _save,
          child: Text(l10n.menuSaveAction),
        ),
      ],
    );
  }
}
