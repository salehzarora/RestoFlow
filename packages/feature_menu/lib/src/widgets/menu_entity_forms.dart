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

/// Resolves the caller's scoped write controller for a dialog.
///
/// `showDialog` builds its child under the ROOT navigator's overlay — ABOVE
/// the menu feature's nested `ProviderScope` (the dashboard wires the scope +
/// read/write seams per surface). A provider lookup from INSIDE a dialog
/// therefore resolves against the wrong (root) container, where the menu
/// seams throw `UnimplementedError` ("must be overridden") mid-save — the bug
/// that left the Save button stuck forever in real mode. The controller is
/// read HERE, from the caller's context (inside the scope), and handed to a
/// plain dialog that performs no provider lookups of its own.
MenuWriteController _controllerOf(BuildContext callerContext) =>
    ProviderScope.containerOf(callerContext).read(menuWriteControllerProvider);

/// Shows the create/edit form for a category. Returns true on a successful save.
Future<bool> showCategoryFormDialog(
  BuildContext context, {
  MenuCategory? existing,
}) async {
  final controller = _controllerOf(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _CategoryFormDialog(controller: controller, existing: existing),
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
  final controller = _controllerOf(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _PricedChildFormDialog(
      controller: controller,
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
  bool initialAllowQuantity = false,
  int? initialMaxQuantity,
}) async {
  final controller = _controllerOf(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ModifierFormDialog(
      controller: controller,
      menuItemId: menuItemId,
      id: id,
      initialName: initialName,
      initialSelectionType: initialSelectionType,
      initialMinSelect: initialMinSelect,
      initialMaxSelect: initialMaxSelect,
      initialRequired: initialRequired,
      initialDisplayOrder: initialDisplayOrder,
      initialActive: initialActive,
      initialAllowQuantity: initialAllowQuantity,
      initialMaxQuantity: initialMaxQuantity,
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

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({required this.controller, this.existing});

  /// The CALLER's scoped write controller (see [_controllerOf]) — the dialog
  /// itself performs no provider lookups (it lives above the nested scope).
  final MenuWriteController controller;
  final MenuCategory? existing;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
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
    final outcome = await widget.controller.upsertCategory(
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

class _PricedChildFormDialog extends StatefulWidget {
  const _PricedChildFormDialog({
    required this.controller,
    required this.kind,
    required this.parentId,
    required this.currencyCode,
    required this.id,
    required this.initialName,
    required this.initialDeltaMinor,
    required this.initialDisplayOrder,
    required this.initialActive,
  });

  /// The CALLER's scoped write controller (see [_controllerOf]).
  final MenuWriteController controller;
  final PricedChildKind kind;
  final String parentId;
  final String currencyCode;
  final String? id;
  final String initialName;
  final int initialDeltaMinor;
  final int initialDisplayOrder;
  final bool initialActive;

  @override
  State<_PricedChildFormDialog> createState() => _PricedChildFormDialogState();
}

class _PricedChildFormDialogState extends State<_PricedChildFormDialog> {
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
    final controller = widget.controller;
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

class _ModifierFormDialog extends StatefulWidget {
  const _ModifierFormDialog({
    required this.controller,
    required this.menuItemId,
    required this.id,
    required this.initialName,
    required this.initialSelectionType,
    required this.initialMinSelect,
    required this.initialMaxSelect,
    required this.initialRequired,
    required this.initialDisplayOrder,
    required this.initialActive,
    required this.initialAllowQuantity,
    required this.initialMaxQuantity,
  });

  /// The CALLER's scoped write controller (see [_controllerOf]).
  final MenuWriteController controller;
  final String menuItemId;
  final String? id;
  final String initialName;
  final String initialSelectionType;
  final int initialMinSelect;
  final int? initialMaxSelect;
  final bool initialRequired;
  final int initialDisplayOrder;
  final bool initialActive;
  final bool initialAllowQuantity;
  final int? initialMaxQuantity;

  @override
  State<_ModifierFormDialog> createState() => _ModifierFormDialogState();
}

class _ModifierFormDialogState extends State<_ModifierFormDialog> {
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
  // Pre-fill a friendly cap of 5 for a new group (or when no cap is stored) —
  // the owner clears the field for "no cap" (blank => null).
  late final TextEditingController _maxQuantity = TextEditingController(
    text: (widget.initialMaxQuantity ?? 5).toString(),
  );
  late String _selectionType = widget.initialSelectionType;
  late bool _required = widget.initialRequired;
  late bool _active = widget.initialActive;
  late bool _allowQuantity = widget.initialAllowQuantity;
  MenuFieldError? _nameError;
  MenuFieldError? _minError;
  MenuFieldError? _maxError;
  MenuFieldError? _maxQuantityError;
  MenuWriteFailure? _writeError;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    _order.dispose();
    _maxQuantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = validateName(_name.text);

    // min_select: blank => 0; non-empty must parse to an integer; then it must
    // be >= 0. Never silently clamp negative/invalid operator input.
    final minText = _min.text.trim();
    final int? minSelect = minText.isEmpty ? 0 : int.tryParse(minText);
    final MenuFieldError? minError = minSelect == null
        ? MenuFieldError.notAnInteger
        : validateMinSelect(minSelect);

    // max_select: blank => null (no maximum); non-empty must parse; then it
    // must be >= min (and >= 0), per validateMaxSelect.
    final maxText = _max.text.trim();
    final bool maxProvided = maxText.isNotEmpty;
    final int? maxSelect = maxProvided ? int.tryParse(maxText) : null;
    final MenuFieldError? maxError = (maxProvided && maxSelect == null)
        ? MenuFieldError.notAnInteger
        : validateMaxSelect(maxSelect, minSelect ?? 0);

    // allow_quantity is only meaningful for multi-select groups: flipping the
    // dropdown back to 'single' hides the toggle and saves false (the server
    // rejects single + allow_quantity).
    final bool allowQuantity = _selectionType == 'multiple' && _allowQuantity;

    // max_quantity (per-option units cap): blank => null (no cap); non-empty
    // must parse to an integer > 0. Only validated while quantity is allowed
    // (the field is hidden otherwise) and never sent without it.
    final maxQuantityText = _maxQuantity.text.trim();
    final bool maxQuantityProvided = maxQuantityText.isNotEmpty;
    final int? maxQuantity = maxQuantityProvided
        ? int.tryParse(maxQuantityText)
        : null;
    final MenuFieldError? maxQuantityError = !allowQuantity
        ? null
        : (maxQuantityProvided && maxQuantity == null)
        ? MenuFieldError.notAnInteger
        : validateMaxQuantity(maxQuantity);

    setState(() {
      _nameError = nameError;
      _minError = minError;
      _maxError = maxError;
      _maxQuantityError = maxQuantityError;
      _writeError = null;
    });
    if (nameError != null ||
        minError != null ||
        maxError != null ||
        maxQuantityError != null) {
      return;
    }

    setState(() => _submitting = true);
    final outcome = await widget.controller.upsertModifier(
      id: widget.id,
      menuItemId: widget.menuItemId,
      name: _name.text.trim(),
      selectionType: _selectionType,
      minSelect: minSelect!,
      maxSelect: maxSelect,
      isRequired: _required,
      displayOrder: int.tryParse(_order.text.trim()) ?? 0,
      isActive: _active,
      allowQuantity: allowQuantity,
      maxQuantity: allowQuantity ? maxQuantity : null,
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
                key: const ValueKey('menu-modifier-min'),
                controller: _min,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.menuMinSelectLabel,
                  errorText: _minError == null
                      ? null
                      : l10n.menuFieldErrorText(_minError!),
                ),
              ),
            ),
            const SizedBox(width: RestoflowSpacing.md),
            Expanded(
              child: TextField(
                key: const ValueKey('menu-modifier-max'),
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
        // Quantity settings — multi-select only (a single-select group can
        // never repeat an option; the server rejects it). Flipping the
        // dropdown to 'single' hides both and saves allow_quantity=false.
        if (_selectionType == 'multiple')
          SwitchListTile(
            key: const ValueKey('menu-modifier-allow-quantity'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.menuAllowQuantityLabel),
            subtitle: Text(l10n.menuAllowQuantityHelp),
            value: _allowQuantity,
            onChanged: (value) => setState(() => _allowQuantity = value),
          ),
        if (_selectionType == 'multiple' && _allowQuantity)
          TextField(
            key: const ValueKey('menu-modifier-max-quantity'),
            controller: _maxQuantity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.menuMaxQuantityLabel,
              errorText: _maxQuantityError == null
                  ? null
                  : l10n.menuFieldErrorText(_maxQuantityError!),
            ),
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
