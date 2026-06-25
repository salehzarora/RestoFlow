import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/menu_validation.dart';
import '../data/minor_money.dart';
import '../models/menu_category.dart';
import '../models/menu_field_error.dart';
import '../models/menu_write_failure.dart';
import '../state/menu_providers.dart';
import 'menu_l10n.dart';

/// The structurally-identical priced child entities (name + signed price delta).
enum PricedChildKind { size, variant, option }

/// A soft-delete confirmation dialog. Returns true if the user confirms.
Future<bool> showMenuDeleteConfirm(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.delete_outline, color: scheme.error),
      title: Text(l10n.menuDeleteConfirmTitle),
      content: Text(l10n.menuDeleteConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.menuCancelAction),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.menuConfirmDelete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Shows the create/edit form for a category. Returns true on a successful save.
Future<bool> showCategoryFormDialog(
  BuildContext context, {
  MenuCategory? existing,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _CategoryFormDialog(existing: existing),
  );
  return saved ?? false;
}

/// Shows the create/edit form for a size / variant / modifier option.
Future<bool> showPricedChildFormDialog(
  BuildContext context, {
  required PricedChildKind kind,
  required String parentId,
  required String currencyCode,
  String? id,
  String initialName = '',
  int initialDeltaMinor = 0,
  int initialDisplayOrder = 0,
  bool initialActive = true,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _PricedChildFormDialog(
      kind: kind,
      parentId: parentId,
      currencyCode: currencyCode,
      id: id,
      initialName: initialName,
      initialDeltaMinor: initialDeltaMinor,
      initialDisplayOrder: initialDisplayOrder,
      initialActive: initialActive,
    ),
  );
  return saved ?? false;
}

/// Shows the create/edit form for a modifier group.
Future<bool> showModifierFormDialog(
  BuildContext context, {
  required String menuItemId,
  String? id,
  String initialName = '',
  String initialSelectionType = 'single',
  int initialMinSelect = 0,
  int? initialMaxSelect,
  bool initialRequired = false,
  int initialDisplayOrder = 0,
  bool initialActive = true,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _ModifierFormDialog(
      menuItemId: menuItemId,
      id: id,
      initialName: initialName,
      initialSelectionType: initialSelectionType,
      initialMinSelect: initialMinSelect,
      initialMaxSelect: initialMaxSelect,
      initialRequired: initialRequired,
      initialDisplayOrder: initialDisplayOrder,
      initialActive: initialActive,
    ),
  );
  return saved ?? false;
}

/// Shared dialog chrome: a scrollable form with a write-error banner and
/// Cancel/Save actions.
class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.title,
    required this.fields,
    required this.submitting,
    required this.writeError,
    required this.onSave,
  });

  final String title;
  final List<Widget> fields;
  final bool submitting;
  final MenuWriteFailure? writeError;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final field in fields) ...[
                field,
                const SizedBox(height: RestoflowSpacing.md),
              ],
              if (writeError != null)
                Container(
                  padding: const EdgeInsets.all(RestoflowSpacing.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                  ),
                  child: Text(
                    l10n.menuWriteFailureText(writeError!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.menuCancelAction),
        ),
        FilledButton(
          onPressed: submitting ? null : onSave,
          child: Text(l10n.menuSaveAction),
        ),
      ],
    );
  }
}

class _CategoryFormDialog extends ConsumerStatefulWidget {
  const _CategoryFormDialog({this.existing});

  final MenuCategory? existing;

  @override
  ConsumerState<_CategoryFormDialog> createState() =>
      _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<_CategoryFormDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _order = TextEditingController(
    text: (widget.existing?.displayOrder ?? 0).toString(),
  );
  late bool _active = widget.existing?.isActive ?? true;
  MenuFieldError? _nameError;
  MenuWriteFailure? _writeError;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = validateName(_name.text);
    setState(() {
      _nameError = nameError;
      _writeError = null;
    });
    if (nameError != null) return;

    setState(() => _submitting = true);
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .upsertCategory(
          id: widget.existing?.id,
          name: _name.text.trim(),
          displayOrder: int.tryParse(_order.text.trim()) ?? 0,
          isActive: _active,
        );
    if (!mounted) return;
    outcome.fold(
      (_) => Navigator.of(context).pop(true),
      (failure) => setState(() {
        _submitting = false;
        _writeError = failure;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _DialogShell(
      title: widget.existing == null
          ? l10n.menuAddCategory
          : l10n.menuEditTitle,
      submitting: _submitting,
      writeError: _writeError,
      onSave: _save,
      fields: [
        TextField(
          key: const ValueKey('menu-category-name'),
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.menuNameLabel,
            errorText: _nameError == null
                ? null
                : l10n.menuFieldErrorText(_nameError!),
          ),
        ),
        TextField(
          controller: _order,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.menuDisplayOrderLabel),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.menuActiveLabel),
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
      ],
    );
  }
}

class _PricedChildFormDialog extends ConsumerStatefulWidget {
  const _PricedChildFormDialog({
    required this.kind,
    required this.parentId,
    required this.currencyCode,
    required this.id,
    required this.initialName,
    required this.initialDeltaMinor,
    required this.initialDisplayOrder,
    required this.initialActive,
  });

  final PricedChildKind kind;
  final String parentId;
  final String currencyCode;
  final String? id;
  final String initialName;
  final int initialDeltaMinor;
  final int initialDisplayOrder;
  final bool initialActive;

  @override
  ConsumerState<_PricedChildFormDialog> createState() =>
      _PricedChildFormDialogState();
}

class _PricedChildFormDialogState
    extends ConsumerState<_PricedChildFormDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _delta = TextEditingController(
    text: formatMinorUnits(widget.initialDeltaMinor, widget.currencyCode),
  );
  late final TextEditingController _order = TextEditingController(
    text: widget.initialDisplayOrder.toString(),
  );
  late bool _active = widget.initialActive;
  MenuFieldError? _nameError;
  MenuFieldError? _deltaError;
  MenuWriteFailure? _writeError;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _delta.dispose();
    _order.dispose();
    super.dispose();
  }

  String _title(AppLocalizations l10n) {
    if (widget.id != null) return l10n.menuEditTitle;
    return switch (widget.kind) {
      PricedChildKind.size => l10n.menuAddSize,
      PricedChildKind.variant => l10n.menuAddVariant,
      PricedChildKind.option => l10n.menuAddOption,
    };
  }

  Future<void> _save() async {
    final nameError = validateName(_name.text);
    final deltaMinor = parseMajorToMinor(_delta.text, widget.currencyCode);
    final deltaError = validatePriceDeltaMinor(deltaMinor);
    setState(() {
      _nameError = nameError;
      _deltaError = deltaError;
      _writeError = null;
    });
    if (nameError != null || deltaError != null) return;

    setState(() => _submitting = true);
    final controller = ref.read(menuWriteControllerProvider);
    final name = _name.text.trim();
    final order = int.tryParse(_order.text.trim()) ?? 0;
    final outcome = await switch (widget.kind) {
      PricedChildKind.size => controller.upsertSize(
        id: widget.id,
        menuItemId: widget.parentId,
        name: name,
        priceDeltaMinor: deltaMinor!,
        displayOrder: order,
        isActive: _active,
      ),
      PricedChildKind.variant => controller.upsertVariant(
        id: widget.id,
        menuItemId: widget.parentId,
        name: name,
        priceDeltaMinor: deltaMinor!,
        displayOrder: order,
        isActive: _active,
      ),
      PricedChildKind.option => controller.upsertModifierOption(
        id: widget.id,
        modifierId: widget.parentId,
        name: name,
        priceDeltaMinor: deltaMinor!,
        displayOrder: order,
        isActive: _active,
      ),
    };
    if (!mounted) return;
    outcome.fold(
      (_) => Navigator.of(context).pop(true),
      (failure) => setState(() {
        _submitting = false;
        _writeError = failure;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _DialogShell(
      title: _title(l10n),
      submitting: _submitting,
      writeError: _writeError,
      onSave: _save,
      fields: [
        TextField(
          key: const ValueKey('menu-child-name'),
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.menuNameLabel,
            errorText: _nameError == null
                ? null
                : l10n.menuFieldErrorText(_nameError!),
          ),
        ),
        TextField(
          controller: _delta,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          decoration: InputDecoration(
            labelText: l10n.menuPriceDeltaLabel,
            suffixText: widget.currencyCode,
            errorText: _deltaError == null
                ? null
                : l10n.menuFieldErrorText(_deltaError!),
          ),
        ),
        TextField(
          controller: _order,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.menuDisplayOrderLabel),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.menuActiveLabel),
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
      ],
    );
  }
}

class _ModifierFormDialog extends ConsumerStatefulWidget {
  const _ModifierFormDialog({
    required this.menuItemId,
    required this.id,
    required this.initialName,
    required this.initialSelectionType,
    required this.initialMinSelect,
    required this.initialMaxSelect,
    required this.initialRequired,
    required this.initialDisplayOrder,
    required this.initialActive,
  });

  final String menuItemId;
  final String? id;
  final String initialName;
  final String initialSelectionType;
  final int initialMinSelect;
  final int? initialMaxSelect;
  final bool initialRequired;
  final int initialDisplayOrder;
  final bool initialActive;

  @override
  ConsumerState<_ModifierFormDialog> createState() =>
      _ModifierFormDialogState();
}

class _ModifierFormDialogState extends ConsumerState<_ModifierFormDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _min = TextEditingController(
    text: widget.initialMinSelect.toString(),
  );
  late final TextEditingController _max = TextEditingController(
    text: widget.initialMaxSelect?.toString() ?? '',
  );
  late final TextEditingController _order = TextEditingController(
    text: widget.initialDisplayOrder.toString(),
  );
  late String _selectionType = widget.initialSelectionType;
  late bool _required = widget.initialRequired;
  late bool _active = widget.initialActive;
  MenuFieldError? _nameError;
  MenuFieldError? _maxError;
  MenuWriteFailure? _writeError;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = validateName(_name.text);
    final minSelect = int.tryParse(_min.text.trim()) ?? 0;
    final maxSelect = _max.text.trim().isEmpty
        ? null
        : int.tryParse(_max.text.trim());
    final maxError = validateMaxSelect(maxSelect, minSelect);
    setState(() {
      _nameError = nameError;
      _maxError = maxError;
      _writeError = null;
    });
    if (nameError != null || maxError != null) return;

    setState(() => _submitting = true);
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .upsertModifier(
          id: widget.id,
          menuItemId: widget.menuItemId,
          name: _name.text.trim(),
          selectionType: _selectionType,
          minSelect: minSelect < 0 ? 0 : minSelect,
          maxSelect: maxSelect,
          isRequired: _required,
          displayOrder: int.tryParse(_order.text.trim()) ?? 0,
          isActive: _active,
        );
    if (!mounted) return;
    outcome.fold(
      (_) => Navigator.of(context).pop(true),
      (failure) => setState(() {
        _submitting = false;
        _writeError = failure;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _DialogShell(
      title: widget.id == null ? l10n.menuAddModifier : l10n.menuEditTitle,
      submitting: _submitting,
      writeError: _writeError,
      onSave: _save,
      fields: [
        TextField(
          key: const ValueKey('menu-modifier-name'),
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.menuNameLabel,
            errorText: _nameError == null
                ? null
                : l10n.menuFieldErrorText(_nameError!),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: _selectionType,
          decoration: InputDecoration(labelText: l10n.menuSelectionTypeLabel),
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _min,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.menuMinSelectLabel),
              ),
            ),
            const SizedBox(width: RestoflowSpacing.md),
            Expanded(
              child: TextField(
                controller: _max,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.menuMaxSelectLabel,
                  errorText: _maxError == null
                      ? null
                      : l10n.menuFieldErrorText(_maxError!),
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.menuRequiredLabel),
          value: _required,
          onChanged: (value) => setState(() => _required = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.menuActiveLabel),
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
        TextField(
          controller: _order,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.menuDisplayOrderLabel),
        ),
      ],
    );
  }
}
