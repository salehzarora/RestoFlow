import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
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
  bool initialKitchenMeatEnabled = false,
  num? initialKitchenMeatQuantity,
  String initialKitchenMeatUnit = '',
  String initialKitchenMeatClassifierOptionId = '',
  List<({String id, String name})> classifierOptions =
      const <({String id, String name})>[],
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
      initialKitchenMeatEnabled: initialKitchenMeatEnabled,
      initialKitchenMeatQuantity: initialKitchenMeatQuantity,
      initialKitchenMeatUnit: initialKitchenMeatUnit,
      initialKitchenMeatClassifierOptionId:
          initialKitchenMeatClassifierOptionId,
      classifierOptions: classifierOptions,
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
  // MENU-ORDER-001 (Codex #6): display_order is owned by drag reorder — a normal
  // edit sends NO order (null); the DB guard trigger preserves the live order.
  late bool _active = widget.existing?.isActive ?? true;
  MenuFieldError? _nameError;
  MenuWriteFailure? _writeError;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
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
      displayOrder:
          null, // Codex #6: edit sends no order; guard trigger preserves it
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
    required this.initialKitchenMeatEnabled,
    required this.initialKitchenMeatQuantity,
    required this.initialKitchenMeatUnit,
    this.initialKitchenMeatClassifierOptionId = '',
    this.classifierOptions = const <({String id, String name})>[],
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

  /// KITCHEN-MEAT-001: the option's current meat metadata (only meaningful when
  /// [kind] is [PricedChildKind.option]).
  final bool initialKitchenMeatEnabled;
  final num? initialKitchenMeatQuantity;
  final String initialKitchenMeatUnit;

  /// KITCHEN-MODIFIER-PREP-CLASSIFIER-019: the id of ANOTHER option on the SAME
  /// menu item that classifies THIS option's preparation contribution (Cheese
  /// splitting the size option's Meat pieces). '' = no split.
  final String initialKitchenMeatClassifierOptionId;

  /// The options this contribution may be split by: every option of the SAME
  /// menu item, across all of its modifier groups. Supplied by the item editor,
  /// which owns the item's snapshot — so another product's options can never
  /// appear, and no name is ever parsed as an identifier.
  final List<({String id, String name})> classifierOptions;

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
  // KITCHEN-MEAT-001 (option kind only): the meat-summary section state.
  late bool _meatEnabled = widget.initialKitchenMeatEnabled;
  late final TextEditingController _meatQuantity = TextEditingController(
    text: widget.initialKitchenMeatQuantity == null
        ? ''
        : formatPrepQuantity(widget.initialKitchenMeatQuantity!),
  );
  late final TextEditingController _meatUnit = TextEditingController(
    text: widget.initialKitchenMeatUnit,
  );
  MenuFieldError? _meatQuantityError;

  /// 019: the currently-picked classifier option id ('' = No split).
  late String _meatClassifierOptionId =
      widget.initialKitchenMeatClassifierOptionId;
  MenuFieldError? _nameError;
  MenuFieldError? _deltaError;
  MenuWriteFailure? _writeError;
  bool _submitting = false;

  bool get _showMeat => widget.kind == PricedChildKind.option;

  /// 019: the options THIS contribution may be split by — the same item's
  /// options minus the one being edited (a contribution cannot classify
  /// itself). Ids are stable; names are display only.
  List<({String id, String name})> get _classifierChoices => [
    for (final o in widget.classifierOptions)
      if (o.id != widget.id) o,
  ];

  /// The picker's value, or '' when the stored target no longer exists.
  String get _resolvedClassifierId =>
      _classifierChoices.any((o) => o.id == _meatClassifierOptionId)
      ? _meatClassifierOptionId
      : '';

  /// True when a link is stored but its target is not a live sibling option.
  bool get _classifierDangling =>
      _meatClassifierOptionId.isNotEmpty && _resolvedClassifierId.isEmpty;

  @override
  void dispose() {
    _name.dispose();
    _delta.dispose();
    _order.dispose();
    _meatQuantity.dispose();
    _meatUnit.dispose();
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
    // KITCHEN-MEAT-001: the meat quantity is a positive count, validated only
    // when the meat toggle is on (option kind). A count, never money (D-007).
    num? meatQuantity;
    MenuFieldError? meatError;
    if (_showMeat && _meatEnabled) {
      meatQuantity = num.tryParse(_meatQuantity.text.trim());
      if (meatQuantity == null || meatQuantity <= 0) {
        meatError = MenuFieldError.notAnInteger;
      }
    }
    setState(() {
      _nameError = nameError;
      _deltaError = deltaError;
      _meatQuantityError = meatError;
      _writeError = null;
    });
    if (nameError != null || deltaError != null || meatError != null) return;

    setState(() => _submitting = true);
    final controller = widget.controller;
    final name = _name.text.trim();
    final order = int.tryParse(_order.text.trim()) ?? 0;
    // Full-state: an enabled toggle sends {quantity,unit}; disabled sends null
    // (clears any previously-configured meat on the option).
    // 019: the classifier rides INSIDE the option's own contribution object, at
    // the narrowest product-specific scope. It is resolved against the SAME
    // item's live options here, so a stale / deleted / foreign / self id is
    // dropped rather than persisted, and the stored NAME is always refreshed
    // from the live option. Disabling the contribution clears the relation on
    // Save — there is nothing left to classify — which is why the picker state
    // is not destroyed before then.
    final classifierName = <String, String>{
      for (final o in _classifierChoices) o.id: o.name,
    }[_meatClassifierOptionId];
    final kitchenMeat = (_showMeat && _meatEnabled)
        ? <String, dynamic>{
            'quantity': meatQuantity,
            'unit': _meatUnit.text.trim(),
            if (classifierName != null) ...<String, dynamic>{
              'classifier_option_id': _meatClassifierOptionId,
              'classifier_option_name': classifierName,
            },
          }
        : null;
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
        // MENU-ORDER-001 (Codex #6): options are drag-reordered — a normal edit
        // sends NO order (null); the DB guard trigger preserves the live order.
        displayOrder: null,
        isActive: _active,
        kitchenMeat: kitchenMeat,
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
    final theme = Theme.of(context);
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
        // MENU-ORDER-001 (Codex): modifier OPTIONS are drag-reordered, so their
        // numeric field is removed (it competed with drag). Sizes/variants are not
        // drag-reorderable in this ticket, so they keep the numeric field.
        if (widget.kind != PricedChildKind.option)
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
        // KITCHEN-MEAT-001 / KITCHEN-COUNT-001: the optional GENERIC kitchen
        // COUNT section (user-facing copy: "Kitchen count summary"; the owner
        // writes any unit — قطع لحم / حبات سمك / خبز / سيخ / …) — ONLY on modifier
        // options (size/variant dialogs share this form but never show it). When
        // enabled, this option counts toward the KDS whole-order count total.
        // (Internal state/field names kept as *Meat* for compatibility.)
        if (_showMeat) ...[
          const Divider(),
          Text(
            l10n.menuKitchenMeatSection,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SwitchListTile(
            key: const ValueKey('menu-option-meat-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.menuKitchenMeatEnabledLabel),
            value: _meatEnabled,
            onChanged: (value) => setState(() => _meatEnabled = value),
          ),
          if (_meatEnabled) ...[
            TextField(
              key: const ValueKey('menu-option-meat-quantity'),
              controller: _meatQuantity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.menuKitchenMeatQuantityLabel,
                errorText: _meatQuantityError == null
                    ? null
                    : l10n.menuFieldErrorText(_meatQuantityError!),
              ),
            ),
            TextField(
              key: const ValueKey('menu-option-meat-unit'),
              controller: _meatUnit,
              decoration: InputDecoration(
                labelText: l10n.menuKitchenMeatUnitLabel,
              ),
            ),
            // 019: split THIS contribution by another option of the same item —
            // the 240g size contributes 2 Meat pieces, and Cheese decides
            // whether they are reported with or without it. Shown only when the
            // contribution is enabled (there is nothing to classify otherwise)
            // and only when the item actually has another option to split by.
            if (_classifierChoices.isNotEmpty) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              DropdownButtonFormField<String>(
                key: const ValueKey('menu-option-meat-classifier'),
                initialValue: _resolvedClassifierId,
                isDense: true,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.menuPrepClassifierLabel,
                  errorText: _classifierDangling
                      ? l10n.menuPrepClassifierMissing
                      : null,
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(l10n.menuPrepClassifierNone),
                  ),
                  for (final option in _classifierChoices)
                    DropdownMenuItem<String>(
                      value: option.id,
                      child: Text(option.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _meatClassifierOptionId = value ?? ''),
              ),
              Text(
                l10n.menuPrepClassifierHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            // A link whose target is gone is surfaced even when there is no
            // picker left to show it in; Save then clears it.
            if (_classifierChoices.isEmpty && _classifierDangling)
              Text(
                l10n.menuPrepClassifierMissing,
                key: const ValueKey('menu-option-meat-classifier-dangling'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ],
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
  // MENU-ORDER-001 (Codex #6): modifier groups are drag-reordered — a normal edit
  // sends NO order (null); the DB guard trigger preserves the live order.
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
      displayOrder:
          null, // Codex #6: edit sends no order; guard trigger preserves it
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
      ],
    );
  }
}
