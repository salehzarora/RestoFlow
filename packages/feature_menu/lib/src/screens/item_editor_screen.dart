import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_currency/restoflow_currency.dart'
    show currencySelectorLabel, normalizeCurrencyCode;
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/menu_config_copy.dart';
import '../data/menu_validation.dart';
import '../data/menu_writer.dart';
import '../data/minor_money.dart';
import '../models/menu_category.dart';
import '../models/menu_entity_type.dart';
import '../models/menu_field_error.dart';
import '../models/menu_item.dart';
import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';
import '../models/menu_write_failure.dart';
import '../models/modifier.dart';
import '../models/modifier_option.dart';
import '../state/menu_providers.dart';
import '../widgets/menu_badges.dart';
import '../widgets/menu_components.dart';
import '../widgets/menu_copied_modifiers_draft_editor.dart';
import '../widgets/menu_copy_source_picker.dart';
import '../widgets/menu_entity_forms.dart';
import '../widgets/menu_image_panel.dart';
import '../widgets/menu_item_thumbnail.dart';
import '../widgets/menu_l10n.dart';
import '../widgets/menu_reorder.dart';

/// What the item editor is editing: an existing [item], or a new item in
/// [categoryId].
class MenuEditorTarget {
  const MenuEditorTarget({this.item, this.categoryId});

  final MenuItem? item;
  final String? categoryId;

  bool get isExisting => item != null;
}

/// The in-place item editor (RF-111 + menu/media sprint). Rendered inside the
/// menu surface subtree (NOT a pushed route) so it stays under the feature
/// ProviderScope overrides.
///
/// Sectioned cards, in order: 1 basic info (name/description/category/type/
/// tags), 2 image (existing items only), 3 copy settings from an existing item,
/// 4 pricing, 5 kitchen setup, 6 modifiers + options (existing items only —
/// every modifier row is a server row, so there is nothing to render until the
/// item exists). Save and Cancel live in the always-visible top bar.
///
/// OPS-043 Phase 3 retired Sizes, Types, the two Preparation inputs and the
/// Advanced panel from this form; their COLUMNS and values are untouched and
/// carried through on every save. Phase 4 replaced the six hardcoded modifier
/// templates with the copy-from-item card.
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
  // OPS-043 D1: formatted in the RESTAURANT's operating currency, which is the
  // same code the save sends and the same exponent the parse uses. Three
  // different currencies in one card is how a 3-decimal tenant ends up typing
  // 1.234 into a field that stores 12.34.
  late final TextEditingController _price = TextEditingController(
    text: _item == null
        ? ''
        : formatMinorUnits(_item.basePriceMinor, _currencyCode),
  );
  // MENU-ORDER-001 (Codex #6): items are drag-reordered in the items panel — a
  // normal edit sends NO display_order (null); the DB guard trigger preserves the
  // live order, so nothing is hand-tracked here.
  // OPS-043 Phase 3: the controllers for prep time, kitchen note, SKU,
  // portion label, patty count and patty weight are gone with their inputs.
  // The VALUES are not — see `_builtAttributes` and the carry-through in
  // `_saveFields`.

  /// KITCHEN-PREP-001: the editable kitchen prep component rows, seeded from the
  /// item's configured `attributes.prep_components`. Inline-editable (mirrors how
  /// `_tags` is edited then serialized on save) — an empty list means no prep.
  late final List<_PrepRow> _prepRows = [
    for (final component
        in _item?.prepComponents ?? const <KitchenPrepComponent>[])
      _PrepRow(
        name: component.name,
        quantity: formatPrepQuantity(component.quantity),
        unit: component.unit,
        // KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: the stored classifier link.
        // The NAME is re-resolved from the live option on save, so renaming an
        // option in the Dashboard refreshes the label the kitchen prints.
        classifierOptionId: component.classifierOptionId,
      ),
  ];

  /// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: every modifier option of THIS
  /// item, in Dashboard order — the candidates a prep resource may be split by.
  ///
  /// Product-scoped by construction: `modifiers.menu_item_id` ties each group to
  /// one item, and modifier TEMPLATES are copy-on-attach, so a reusable template
  /// can never carry another product's option id into this list. Empty on a
  /// not-yet-created item (no options exist yet) — the picker is then hidden.
  List<({String id, String name})> get _classifierOptions {
    final item = _item;
    if (item == null) return const <({String id, String name})>[];
    return <({String id, String name})>[
      for (final modifier in widget.snapshot.modifiersForItem(item.id))
        for (final option in widget.snapshot.optionsForModifier(modifier.id))
          (id: option.id, name: option.name),
    ];
  }

  late String? _categoryId = _item?.menuCategoryId ?? widget.target.categoryId;
  late String? _itemType = _item?.itemType;
  late final Set<String> _tags = {...?_item?.tags};
  late bool _active = _item?.isActive ?? true;

  MenuFieldError? _nameError;
  MenuFieldError? _priceError;
  MenuFieldError? _currencyError;
  bool _submitting = false;

  /// OPS-043 Phase 4: the configuration copied from another item, held ONLY
  /// here. Applying a copy writes nothing; this field IS the draft, and the
  /// normal Save is the one and only moment it becomes real (D7).
  MenuCopiedConfig? _copy;

  /// OPS-043 Phase 4: the id of the item a previous Save created before the
  /// copy flush stopped. Without it a retry would create a SECOND item — the
  /// one thing a blind retry of a non-atomic sequence gets catastrophically
  /// wrong.
  String? _createdItemId;

  /// OPS-043 Phase 4: how far the copy flush has got, for the progress note.
  /// The flush is ~20 ordinary RPCs for a burger-shaped item; a save that long
  /// must say what it is doing.
  ({int done, int total})? _flushProgress;

  /// OPS-043 Phase 4B: the operator's OWN values from immediately before the
  /// copy was applied, so Discard can put them back.
  ///
  /// Applying a copy overwrites the price field and replaces the Kitchen setup
  /// rows. Dropping `_copy` alone would leave those overwritten values sitting
  /// in the form as if the operator had typed them — a "discard" that discards
  /// the wrong half. Captured only when no copy is applied yet, so changing the
  /// source mid-draft still restores the ORIGINAL values rather than the
  /// previous copy's.
  ({String priceText, List<_PrepRowValues> prepRows})? _preCopyState;

  /// The item this editor writes to: the edited row, or the one it created on a
  /// previous, partly-failed Save.
  String? get _targetItemId => _item?.id ?? _createdItemId;

  /// OPS-043 Phase 4: true when copying would DUPLICATE live configuration.
  ///
  /// The per-entity write path can only ADD a modifier group. There is no bulk
  /// replace, and `menu_soft_delete` tombstones exactly ONE row without
  /// cascading to its children — so "replacing" an item's modifiers would mean
  /// deleting every option and every group one call at a time, with no
  /// transaction, destroying live configuration that a mid-way failure could
  /// not restore. The copy is therefore offered only where it can be performed
  /// by creation alone; on an item that already has groups it is refused, in
  /// words, before anything happens.
  bool get _copyBlockedByExistingModifiers {
    final id = _targetItemId;
    if (id == null) return false;
    return widget.snapshot.modifiersForItem(id).isNotEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    for (final row in _prepRows) {
      row.dispose();
    }
    super.dispose();
  }

  /// OPS-043 D1: the restaurant's operating currency — the ONE currency this
  /// editor works in.
  ///
  /// The SCOPE is the authority, not the item. Items inherit the restaurant
  /// setting, so a legacy row stored under an older code is re-stamped on the
  /// next save; that is denomination only, because D2 forbids FX conversion and
  /// the stored NUMBER never changes. It falls back to the item's own code only
  /// when the scope has none, so nothing can be saved with a blank currency.
  String get _currencyCode =>
      normalizeCurrencyCode(widget.scope.currencyCode) ??
      normalizeCurrencyCode(_item?.currencyCode) ??
      widget.scope.currencyCode;

  /// The FRESHEST snapshot row for the edited item (the editor target is
  /// captured when the editor opens, but the snapshot reloads after every
  /// write — e.g. an image upload — and the save below must send the item's
  /// full CURRENT state, or it would silently clear a just-saved image).
  MenuItem? get _freshItem {
    final item = _item;
    if (item == null) return null;
    for (final row in widget.snapshot.items) {
      if (row.id == item.id) return row;
    }
    return item;
  }

  /// The tags to persist: the fixed vocabulary in canonical order, plus any
  /// unknown (newer-backend) tags the item already carried — never dropped.
  List<String> _selectedTags() => [
    for (final tag in kMenuItemTags)
      if (_tags.contains(tag)) tag,
    for (final tag in _tags)
      if (!kMenuItemTags.contains(tag)) tag,
  ];

  /// The attributes to persist.
  ///
  /// OPS-043 Phase 3: this editor now owns exactly ONE key —
  /// `prep_components` (Kitchen setup). Everything else the row carries is
  /// passed through untouched: the retired advanced keys (`portion_label`,
  /// `patty_count`, `patty_weight_grams`) and any key a future ticket adds.
  ///
  /// It used to `remove` those three and re-add them from controllers. That was
  /// safe only while the controllers existed to re-supply them; with the
  /// Advanced panel gone the removes alone would have wiped stored values on
  /// the next ordinary save. Not removing them is the fix — a key nobody edits
  /// is a key nobody should touch.
  ///
  /// `prep_components` keeps the drop-then-re-add dance on purpose: clearing
  /// every row in the UI must clear the stored list, which an unconditional
  /// merge could not express.
  Map<String, dynamic> _builtAttributes({
    required List<Map<String, Object?>> prepComponents,
  }) {
    final attributes = <String, dynamic>{...?_freshItem?.attributes}
      ..remove(kMenuAttrPrepComponents);
    if (prepComponents.isNotEmpty) {
      attributes[kMenuAttrPrepComponents] = prepComponents;
    }
    return attributes;
  }

  /// KITCHEN-PREP-001: validates + serializes the prep rows. A FULLY-blank row
  /// is dropped; a partially-filled row must have a non-blank name AND a
  /// positive integer quantity, else its fields are flagged. Returns the wire
  /// list (`[{name, quantity, unit}]`) and whether any row is in error.
  ///
  /// OPS-043 Phase 4: when [copySource] is given, a row that came from a COPY
  /// also emits its classifier pair, using the SOURCE option id. That id is
  /// never written as-is — `remapPrepComponents` swaps it for the new option's
  /// id on the way to the writer — but emitting it here is what lets the link
  /// follow the row through renames, additions and deletions the operator makes
  /// before saving. With [copySource] null (every ordinary save, and the copy's
  /// own first pass) a copied link emits nothing at all, so no source id can
  /// reach the server even for one write.
  ({List<Map<String, Object?>> components, bool hasError}) _collectPrepRows({
    MenuCopiedConfig? copySource,
  }) {
    final components = <Map<String, Object?>>[];
    var hasError = false;
    // KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: resolve each classifier link
    // against the item's LIVE options, so the stored option name is refreshed on
    // every save and a link to a deleted option is dropped rather than persisted.
    final optionNames = <String, String>{
      for (final option in _classifierOptions) option.id: option.name,
    };
    for (final row in _prepRows) {
      row.nameError = null;
      row.quantityError = null;
      row.classifierMissing = false;
      // OPS-043 Phase 4: a copied link resolves against the DRAFT, not against
      // the item's live options — the options it names do not exist yet.
      final copiedName = copySource?.optionNameBySourceId(
        row.copiedClassifierOptionId,
      );
      final name = row.name.text.trim();
      final quantityText = row.quantity.text.trim();
      final unit = row.unit.text.trim();
      if (name.isEmpty && quantityText.isEmpty && unit.isEmpty) {
        continue; // an untouched/blank row is simply ignored
      }
      // A prep quantity is a positive COUNT that MAY be fractional (the domain
      // types it as num for a genuine half-portion) — parse as num so a stored
      // "0.5" the editor seeds stays saveable. num.tryParse('2') stays an int,
      // so a whole count still serializes as 2, not 2.0.
      final quantity = num.tryParse(quantityText);
      if (name.isEmpty) {
        row.nameError = MenuFieldError.blank;
        hasError = true;
      }
      if (quantity == null || quantity <= 0) {
        row.quantityError = MenuFieldError.notAnInteger;
        hasError = true;
      }
      // 016: a dangling target is surfaced as a validation error but never
      // BLOCKS the save — the resource simply keeps its existing single total,
      // which is the safe behaviour the kitchen already understands.
      final classifierName = optionNames[row.classifierOptionId];
      if (row.classifierOptionId.isNotEmpty && classifierName == null) {
        row.classifierMissing = true;
      }
      if (name.isNotEmpty && quantity != null && quantity > 0) {
        components.add(<String, Object?>{
          'name': name,
          'quantity': quantity,
          'unit': unit,
          // ADDITIVE: written only for a resolved link, so an unsplit resource
          // serializes exactly as it always did.
          if (classifierName != null) ...<String, Object?>{
            'classifier_option_id': row.classifierOptionId,
            'classifier_option_name': classifierName,
          } else if (copiedName != null) ...<String, Object?>{
            // The SOURCE id, remapped before it is written (see the doc above).
            'classifier_option_id': row.copiedClassifierOptionId,
            'classifier_option_name': copiedName,
          },
        });
      }
    }
    return (components: components, hasError: hasError);
  }

  /// The FULL-STATE item payload — ONE builder, used by the ordinary save AND
  /// by the copy flush's classifier pass.
  ///
  /// `menu_upsert_item` clears whatever it is not sent, so two writes of the
  /// same item must agree on every field: a second write that forgot the image,
  /// the SKU or the kitchen note would erase what the first one just saved.
  /// Sharing the builder makes that impossible rather than merely unlikely —
  /// the two calls differ in exactly one argument, the prep rows.
  Future<MenuWriteOutcome> _upsertItem({
    required String? id,
    required String categoryId,
    required int basePriceMinor,
    required String currencyCode,
    required List<Map<String, Object?>> prepComponents,
  }) {
    return ref
        .read(menuWriteControllerProvider)
        .upsertItem(
          id: id,
          menuCategoryId: categoryId,
          name: _name.text.trim(),
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          basePriceMinor: basePriceMinor,
          currencyCode: currencyCode,
          displayOrder:
              null, // Codex #6: edit sends no order; guard trigger preserves it
          isActive: _active,
          // Full-state upsert: null p_image_path CLEARS the image server-side,
          // so a details save must carry the item's current image through.
          imagePath: _freshItem?.imagePath,
          itemType: _itemType,
          tags: _selectedTags(),
          // OPS-043 Phase 3 - NO-WIPE CARRY-THROUGH. These three left the UI;
          // they did NOT leave the row. `menu_upsert_item` is a full-state
          // upsert, so a field this editor stops sending is CLEARED on the
          // server - an operator renaming an item would silently erase its SKU,
          // prep time and kitchen note. They are now read back verbatim from
          // the freshest snapshot row, exactly as `imagePath` above already is
          // and as MenuImagePanel does on its own save/remove paths.
          prepMinutes: _freshItem?.prepMinutes,
          sku: _freshItem?.sku,
          kitchenNote: _freshItem?.kitchenNote,
          attributes: _builtAttributes(prepComponents: prepComponents),
        );
  }

  Future<void> _saveFields() async {
    // OPS-043 D1: no typed currency any more. The inherited operating currency
    // is what the price is parsed AS and what p_currency_code is sent AS — the
    // two can no longer disagree.
    final currencyText = _currencyCode;
    final nameError = validateName(_name.text);
    final priceMinor = parseMajorToMinor(_price.text, currencyText);
    final priceError = validateBasePriceMinor(priceMinor);
    final currencyError = validateCurrencyCode(currencyText);
    // KITCHEN-PREP-001: validate + serialize the prep rows (mutates per-row
    // errors, read back in build via the setState below).
    //
    // OPS-043 Phase 4: NO copySource here on purpose. This first write must
    // carry the Kitchen setup rows WITHOUT their copied classifier links — the
    // options those links name do not exist yet, and writing a source id, even
    // for one write, is exactly what this whole feature exists to avoid.
    final prep = _collectPrepRows();
    final categoryId = _categoryId;
    setState(() {
      _nameError = nameError;
      _priceError = priceError;
      _currencyError = currencyError;
    });
    if (nameError != null ||
        priceError != null ||
        currencyError != null ||
        prep.hasError ||
        categoryId == null) {
      return;
    }
    final basePriceMinor = priceMinor!;

    setState(() => _submitting = true);
    final l10n = AppLocalizations.of(context);
    final outcome = await _upsertItem(
      id: _targetItemId,
      categoryId: categoryId,
      basePriceMinor: basePriceMinor,
      currencyCode: currencyText,
      prepComponents: prep.components,
    );
    if (!mounted) return;

    final failure = outcome.fold<MenuWriteFailure?>((_) => null, (f) => f);
    if (failure != null) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.menuWriteFailureText(failure))),
      );
      return;
    }
    final itemId = outcome.fold<String>((result) => result.id, (_) => '');
    // The item EXISTS now. Remember its id so that if the copy flush below
    // stops halfway, pressing Save again UPDATES this item instead of creating
    // a second one.
    if (_item == null) _createdItemId = itemId;

    // 017 (Codex MEDIUM #5): the save DROPPED every dangling link from the
    // payload, so the in-memory row must stop claiming one — otherwise the
    // editor keeps showing a stale id and a warning for a link that is no
    // longer persisted. Resource name/quantity/unit and every unrelated
    // field are untouched; a link that RESOLVED is left exactly as it is.
    final cleared = _prepRows.where((r) => r.classifierMissing).toList();
    if (cleared.isNotEmpty) {
      setState(() {
        for (final row in cleared) {
          row.classifierOptionId = '';
          row.classifierMissing = false;
        }
      });
    }

    final copy = _copy;
    if (copy != null) {
      await _flushCopy(
        copy: copy,
        l10n: l10n,
        itemId: itemId,
        categoryId: categoryId,
        basePriceMinor: basePriceMinor,
        currencyCode: currencyText,
      );
      return;
    }

    setState(() => _submitting = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.menuSavedSnack)));
    if (!widget.target.isExisting) widget.onClose();
  }

  /// OPS-043 Phase 4: turns the copied draft into real rows, AFTER the item
  /// itself has been saved.
  ///
  /// The sequence is not atomic and is not presented as if it were: on a
  /// failure it says exactly how much was created, leaves it in place, and
  /// keeps the operator in this editor with the draft intact so pressing Save
  /// again RESUMES. The editor closes only after the whole copy has landed —
  /// closing on the item write alone would dispose this State mid-flush and
  /// abandon the groups it was still creating.
  Future<void> _flushCopy({
    required MenuCopiedConfig copy,
    required AppLocalizations l10n,
    required String itemId,
    required String categoryId,
    required int basePriceMinor,
    required String currencyCode,
  }) async {
    final report = await flushMenuCopiedConfig(
      config: copy,
      sink: _EditorCopySink(
        controller: ref.read(menuWriteControllerProvider),
        menuItemId: itemId,
        rewritePrep: (remap) => _upsertItem(
          id: itemId,
          categoryId: categoryId,
          basePriceMinor: basePriceMinor,
          currencyCode: currencyCode,
          // The rows the operator is looking at NOW (they may have edited,
          // added or deleted some since applying the copy), with the copied
          // links swapped from source ids to the new options' ids.
          prepComponents: remapPrepComponents(
            _collectPrepRows(copySource: copy).components,
            remap,
          ),
        ),
      ),
      onProgress: (done, total) {
        if (mounted) {
          setState(() => _flushProgress = (done: done, total: total));
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _flushProgress = null;
    });
    if (!report.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.menuWriteFailureText(report.failure!)}\n'
            '${l10n.menuCopyFlushPartial(report.groupsCreated, report.optionsCreated)}',
          ),
        ),
      );
      return;
    }
    // The copy is real. Re-point the Kitchen setup rows at the options that now
    // exist, so an ordinary later save keeps those links instead of dropping
    // ids that only ever meant anything to the draft.
    final remap = copy.remap;
    setState(() {
      for (final row in _prepRows) {
        if (row.copiedClassifierOptionId.isEmpty) continue;
        row.classifierOptionId = remap[row.copiedClassifierOptionId] ?? '';
        row.copiedClassifierOptionId = '';
      }
      _copy = null;
      // The copy is persisted; there is no longer a pre-copy form to return to.
      _preCopyState = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.menuCopySavedSummary(
            report.groupsCreated,
            report.optionsCreated,
          ),
        ),
      ),
    );
    if (!widget.target.isExisting) widget.onClose();
  }

  /// OPS-043 Phase 4: picks a source and applies it to the LOCAL draft.
  ///
  /// Nothing here writes. The picker returns a plain object, this method puts
  /// it in a field and seeds two visible controls from it — that is the entire
  /// "apply".
  Future<void> _pickCopySource() async {
    final config = await showMenuCopySourcePicker(
      context,
      snapshot: widget.snapshot,
      currencyCode: _currencyCode,
      // An item can never be its own source.
      excludeItemId: _targetItemId,
    );
    if (config == null || !mounted) return;
    if (_formHoldsValues() && !await _confirmReplaceDraft()) return;
    if (!mounted) return;
    _applyCopy(config);
  }

  /// Whether the form already holds values a copy would overwrite.
  bool _formHoldsValues() =>
      _copy != null ||
      _price.text.trim().isNotEmpty ||
      _prepRows.any(
        (row) =>
            row.name.text.trim().isNotEmpty ||
            row.quantity.text.trim().isNotEmpty ||
            row.unit.text.trim().isNotEmpty,
      );

  Future<bool> _confirmReplaceDraft() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('menu-copy-replace-confirm'),
        icon: const Icon(Icons.content_copy_outlined),
        title: Text(l10n.menuCopyReplaceTitle),
        content: Text(l10n.menuCopyReplaceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.menuCancelAction),
          ),
          FilledButton(
            key: const ValueKey('menu-copy-replace-accept'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.menuCopyReplaceConfirm),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Seeds the form from [config]. Zero writes — the price field and the
  /// Kitchen setup rows are ordinary editable controls, and the copied modifier
  /// groups are edited in place, so the operator reviews and adjusts everything
  /// before the copy becomes real.
  void _applyCopy(MenuCopiedConfig config) {
    final retired = List<_PrepRow>.of(_prepRows);
    // Capture what the operator had BEFORE the first copy of this session.
    _preCopyState ??= (
      priceText: _price.text,
      prepRows: [for (final row in _prepRows) row.values],
    );
    setState(() {
      _copy = config;
      // D5: the source base price, prefilled and editable.
      _price.text = formatMinorUnits(config.basePriceMinor, _currencyCode);
      _priceError = null;
      _prepRows
        ..clear()
        ..addAll([
          for (final row in config.prepComponents)
            _PrepRow(
              name: (row['name'] ?? '').toString(),
              quantity: formatPrepQuantity(
                row['quantity'] is num ? row['quantity']! as num : 0,
              ),
              unit: (row['unit'] ?? '').toString(),
              // The SOURCE id, kept apart from `classifierOptionId` so nothing
              // can mistake it for a live link on this item and write it.
              copiedClassifierOptionId: (row['classifier_option_id'] ?? '')
                  .toString(),
            ),
        ]);
    });
    // Dispose the replaced rows AFTER the frame, once their TextFields have
    // left the tree (no use-after-dispose).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in retired) {
        row.dispose();
      }
    });
  }

  /// Drops the draft AND puts the form back the way the operator left it.
  ///
  /// Nothing was ever written, so there is nothing to delete on the server —
  /// but the price field and the Kitchen setup rows were overwritten by the
  /// copy, and leaving those behind would be a discard that only half discards.
  void _discardCopy() {
    final before = _preCopyState;
    final retired = List<_PrepRow>.of(_prepRows);
    setState(() {
      _copy = null;
      _preCopyState = null;
      if (before == null) return;
      _price.text = before.priceText;
      _priceError = null;
      _prepRows
        ..clear()
        ..addAll([for (final values in before.prepRows) values.toRow()]);
    });
    if (before == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in retired) {
        row.dispose();
      }
    });
  }

  /// OPS-043 Phase 4B: drops Kitchen setup links whose draft option is gone.
  ///
  /// A prep row is classified by a DRAFT option, so removing that option would
  /// otherwise leave the row pointing at something the flush can no longer map
  /// — a link that silently stops working after Save. Clearing it here means
  /// the editor shows the truth instead.
  void _reconcileCopiedPrepLinks() {
    final copy = _copy;
    if (copy == null) return;
    for (final row in _prepRows) {
      if (row.copiedClassifierOptionId.isEmpty) continue;
      if (copy.optionNameBySourceId(row.copiedClassifierOptionId) == null) {
        row.copiedClassifierOptionId = '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = widget.snapshot.visibleCategories();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Save/Cancel live HERE (always visible — the sectioned form below
        // scrolls, and a save action must never sit below the fold).
        _EditorTopBar(
          title: _item?.name ?? l10n.menuAddItem,
          onClose: widget.onClose,
          actions: [
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
                    if (_item != null) ...[
                      // Part F: a compact product banner for EXISTING items —
                      // the PERSISTED state from the freshest snapshot row
                      // (visual only; never claims unsaved edits).
                      _ProductSummaryStrip(item: _freshItem ?? _item),
                      const SizedBox(height: RestoflowSpacing.lg),
                    ],
                    // 1. Basic info.
                    _basicInfoCard(context, l10n, categories),
                    if (_item != null) ...[
                      const SizedBox(height: RestoflowSpacing.lg),
                      // 2. Image — needs the FRESHEST row: imagePath changes
                      // after uploads/removals reload the snapshot.
                      MenuImagePanel(item: _freshItem ?? _item),
                    ],
                    const SizedBox(height: RestoflowSpacing.lg),
                    // 3. Copy settings from an existing item — it fills the two
                    // cards below, so it sits above them.
                    _copySettingsCard(context, l10n),
                    const SizedBox(height: RestoflowSpacing.lg),
                    // 4. Pricing (base price).
                    _pricingCard(context, l10n),
                    const SizedBox(height: RestoflowSpacing.lg),
                    // 5. Kitchen setup (what the chef assembles per unit).
                    _kitchenSetupCard(context, l10n),
                    if (_item != null) ...[
                      const SizedBox(height: RestoflowSpacing.lg),
                      // 6. Options & modifiers.
                      _ModifiersSection(
                        item: _item,
                        modifiers: widget.snapshot.modifiersForItem(_item.id),
                        snapshot: widget.snapshot,
                        currencyCode: _currencyCode,
                      ),
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

  /// 1. Basic info: identity + categorization (name, description, category,
  /// item type, tags) and the listing controls (order, active).
  Widget _basicInfoCard(
    BuildContext context,
    AppLocalizations l10n,
    List<MenuCategory> categories,
  ) {
    final theme = Theme.of(context);
    return MenuSectionCard(
      title: l10n.menuBasicInfoSection,
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
                child: DropdownButtonFormField<String>(
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
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: const ValueKey('menu-item-type'),
                  initialValue: _itemType,
                  decoration: InputDecoration(
                    labelText: l10n.menuItemTypeLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.menuItemTypeUnspecified),
                    ),
                    for (final type in kMenuItemTypes)
                      DropdownMenuItem<String?>(
                        value: type,
                        child: Text(l10n.menuItemTypeText(type)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _itemType = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.md),
          Text(
            l10n.menuTagsLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Wrap(
            spacing: RestoflowSpacing.sm,
            runSpacing: RestoflowSpacing.sm,
            children: [
              for (final tag in kMenuItemTags)
                FilterChip(
                  key: ValueKey('menu-item-tag-$tag'),
                  label: Text(l10n.menuTagText(tag)),
                  selected: _tags.contains(tag),
                  onSelected: (selected) => setState(() {
                    selected ? _tags.add(tag) : _tags.remove(tag);
                  }),
                ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.md),
          // MENU-ORDER-001 (Codex #6): the item's display_order is owned by drag
          // reorder — the numeric field is gone and a normal edit sends NO order
          // (null); the DB guard trigger preserves the live order.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.menuActiveLabel),
            value: _active,
            onChanged: (value) => setState(() => _active = value),
          ),
        ],
      ),
    );
  }

  /// 3. OPS-043 Phase 4 — copy settings from an existing item.
  ///
  /// This REPLACES the six hardcoded modifier templates. A template could only
  /// ever offer a generic guess at a menu it had never seen (its deltas were
  /// hardcoded ILS, and it carried no kitchen counts and no prep rows at all);
  /// the restaurant's own items are the real templates, and they already carry
  /// every field the kitchen consumes.
  ///
  /// The card is the whole draft surface: the copied base price lands in the
  /// price field and the copied Kitchen setup in the prep card — both ordinary
  /// editable controls — while the modifier groups are listed READ-ONLY here,
  /// because every modifier widget in this package renders a server row and
  /// there is nothing to render until the item exists. They become fully
  /// editable in the Modifiers section the moment Save creates them.
  Widget _copySettingsCard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final copy = _copy;
    final blocked = _copyBlockedByExistingModifiers;
    final progress = _flushProgress;
    return MenuSectionCard(
      key: const ValueKey('menu-copy-card'),
      title: l10n.menuCopyFromItemTitle,
      icon: Icons.content_copy_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            blocked
                ? l10n.menuCopyBlockedHasModifiers
                : l10n.menuCopyFromItemHint,
            key: blocked
                ? const ValueKey('menu-copy-blocked')
                : const ValueKey('menu-copy-hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: blocked
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (copy != null) ...[
            const SizedBox(height: RestoflowSpacing.md),
            _copySummary(context, l10n, copy),
          ],
          if (progress != null) ...[
            const SizedBox(height: RestoflowSpacing.md),
            Text(
              l10n.menuCopySavingProgress(progress.done, progress.total),
              key: const ValueKey('menu-copy-progress'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            LinearProgressIndicator(
              value: progress.total == 0
                  ? null
                  : progress.done / progress.total,
            ),
          ],
          const SizedBox(height: RestoflowSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: RestoflowSpacing.sm,
              runSpacing: RestoflowSpacing.xs,
              children: [
                TextButton.icon(
                  key: const ValueKey('menu-copy-choose-source'),
                  onPressed: blocked || _submitting ? null : _pickCopySource,
                  icon: const Icon(
                    Icons.library_add_outlined,
                    size: RestoflowIconSizes.sm,
                  ),
                  label: Text(
                    copy == null
                        ? l10n.menuCopyFromItemAction
                        : l10n.menuCopyFromItemChange,
                  ),
                ),
                if (copy != null)
                  TextButton.icon(
                    key: const ValueKey('menu-copy-discard'),
                    onPressed: _submitting ? null : _discardCopy,
                    icon: const Icon(Icons.close, size: RestoflowIconSizes.sm),
                    label: Text(l10n.menuCopyFromItemRemove),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What the copy brought over, so the operator reviews it before Save.
  Widget _copySummary(
    BuildContext context,
    AppLocalizations l10n,
    MenuCopiedConfig copy,
  ) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('menu-copy-summary'),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.menuCopyAppliedFrom(copy.sourceItemName),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: RestoflowSpacing.xxs),
          Text(
            <String>[
              l10n.menuCopyPreviewGroups(copy.groupCount),
              l10n.menuCopyPreviewOptions(copy.optionCount),
              l10n.menuCopyPreviewPrepRows(copy.prepComponents.length),
              if (copy.classifierLinkCount > 0)
                l10n.menuCopyPreviewClassifiers(copy.classifierLinkCount),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          // OPS-043 Phase 4B: the copied groups and options are EDITABLE right
          // here. They used to be a read-only list, because every modifier
          // widget in this package renders a server row — so reviewing a copy
          // meant saving it first and fixing it afterwards, on live rows, which
          // is precisely what a draft is for.
          MenuCopiedModifiersDraftEditor(
            config: copy,
            currencyCode: _currencyCode,
            enabled: !_submitting,
            onChanged: () => setState(_reconcileCopiedPrepLinks),
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Text(
            l10n.menuCopyDraftNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// 4. Pricing: the base price. Money integer minor only (D-007).
  ///
  /// OPS-043 D1: there is NO per-item currency selector any more. One
  /// restaurant operates in one currency — `coalesce(currency_override,
  /// default_currency)` — and every item inherits it, so the currency is shown
  /// READ-ONLY beside the price and changed only in Dashboard Settings. The
  /// upsert still sends `p_currency_code` (the server argument is NOT NULL);
  /// it now sends the inherited value instead of a typed one.
  Widget _pricingCard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return MenuSectionCard(
      title: l10n.menuPricingSection,
      icon: Icons.sell_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('menu-item-price'),
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.menuPriceLabel,
              // The inherited currency, on the field itself: the number the
              // cashier types is in THIS currency and nothing else.
              suffixText: currencySelectorLabel(_currencyCode),
              border: const OutlineInputBorder(),
              errorText: _priceError == null
                  ? null
                  : l10n.menuFieldErrorText(_priceError!),
            ),
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          // The inherited currency, and — when the scope has no usable one —
          // the fail-closed error that blocks the save. The validator survived
          // the selector's removal on purpose: without it a blank scope
          // currency would reach the server as an opaque 42501.
          Row(
            key: const ValueKey('menu-item-currency-inherited'),
            children: [
              Icon(
                _currencyError == null
                    ? Icons.lock_outline
                    : Icons.error_outline,
                size: RestoflowIconSizes.sm,
                color: _currencyError == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: RestoflowSpacing.xs),
              Expanded(
                child: Text(
                  _currencyError == null
                      ? '${l10n.menuCurrencyLabel}: '
                            '${currencySelectorLabel(_currencyCode)} — '
                            '${l10n.menuCurrencyInherited}'
                      : l10n.menuFieldErrorText(_currencyError!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _currencyError == null
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 5. Kitchen setup — what the chef assembles for ONE unit of the item,
  /// aggregated on the KDS (KITCHEN-PREP-001).
  ///
  /// OPS-043 Phase 3 emptied the old "Preparation" card of its two inputs
  /// (prep minutes, kitchen note): neither was read by any POS, KDS, ticket,
  /// submit payload or report, so they were asking a restaurant for data
  /// nothing consumed. The COLUMNS and their stored values are untouched and
  /// carried through on every save. What is left is the part the kitchen
  /// actually uses, so it is now the card itself rather than a sub-section.
  Widget _kitchenSetupCard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return MenuSectionCard(
      title: l10n.menuKitchenPrepSection,
      icon: Icons.restaurant_menu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.menuKitchenPrepHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          for (var i = 0; i < _prepRows.length; i++) _prepRowField(i, l10n),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('menu-item-add-prep-component'),
              onPressed: () => setState(() => _prepRows.add(_PrepRow())),
              icon: const Icon(Icons.add),
              label: Text(l10n.menuAddPrepComponent),
            ),
          ),
        ],
      ),
    );
  }

  /// One editable prep-component row: name / quantity / unit + a remove button.
  ///
  /// KITCHEN-MODIFIER-PREP-CLASSIFIER-019: the 016 "Split by option" picker was
  /// REMOVED from here. Saleh's meat quantity is not a fixed product resource —
  /// it comes from the selected SIZE option — so the classifier now lives beside
  /// the modifier option's own preparation contribution. A legacy 016 link
  /// already stored on a product resource keeps decoding and printing (and is
  /// carried through Save untouched); it is simply no longer offered here, so
  /// nobody is encouraged to configure the relation in the wrong place.
  Widget _prepRowField(int index, AppLocalizations l10n) {
    final row = _prepRows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  key: ValueKey('menu-item-prep-name-$index'),
                  controller: row.name,
                  decoration: InputDecoration(
                    labelText: l10n.menuPrepComponentNameLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: row.nameError == null
                        ? null
                        : l10n.menuFieldErrorText(row.nameError!),
                  ),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                flex: 2,
                child: TextField(
                  key: ValueKey('menu-item-prep-qty-$index'),
                  controller: row.quantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.menuPrepComponentQuantityLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: row.quantityError == null
                        ? null
                        : l10n.menuFieldErrorText(row.quantityError!),
                  ),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                flex: 2,
                child: TextField(
                  key: ValueKey('menu-item-prep-unit-$index'),
                  controller: row.unit,
                  decoration: InputDecoration(
                    labelText: l10n.menuPrepComponentUnitLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('menu-item-prep-remove-$index'),
                tooltip: l10n.menuRemovePrepComponent,
                icon: const Icon(Icons.close),
                onPressed: () {
                  final removed = _prepRows[index];
                  setState(() => _prepRows.removeAt(index));
                  // Dispose AFTER the frame so the removed row's TextFields are gone
                  // from the tree first (no use-after-dispose).
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => removed.dispose(),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditorTopBar extends StatelessWidget {
  const _EditorTopBar({
    required this.title,
    required this.onClose,
    this.actions = const [],
  });

  final String title;
  final VoidCallback onClose;

  /// Trailing actions (Cancel/Save) — kept in the bar so the primary save
  /// action stays visible while the sectioned form scrolls.
  final List<Widget> actions;

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
          ...actions,
        ],
      ),
    );
  }
}

/// A compact product summary banner at the top of the editor (menu/media
/// sprint, Part F): thumbnail + name + price + active pill + tag preview in
/// one strip, so an existing item reads like a product page. VISUAL ONLY — it
/// renders the item's PERSISTED snapshot state (not the in-edit fields) via
/// data the editor already holds; there is no new plumbing.
class _ProductSummaryStrip extends StatelessWidget {
  const _ProductSummaryStrip({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stateTone = item.isActive
        ? RestoflowTone.success
        : RestoflowTone.neutral;
    final stateStyle = stateTone.styleOf(theme);
    return Container(
      key: const ValueKey('menu-item-summary'),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
      ),
      child: Row(
        children: [
          MenuItemThumbnail(item: item, size: 56),
          const SizedBox(width: RestoflowSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: RestoflowSpacing.xxs),
                Text(
                  formatMinorUnits(item.basePriceMinor, item.currencyCode),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: RestoflowSpacing.md),
          // State + tag preview; wraps instead of overflowing when narrow.
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: RestoflowSpacing.xs,
              runSpacing: RestoflowSpacing.xs,
              children: [
                MenuPill(
                  label: item.isActive
                      ? l10n.menuFilterActive
                      : l10n.menuInactiveBadge,
                  icon: item.isActive
                      ? Icons.check_circle_outline
                      : Icons.visibility_off_outlined,
                  background: stateStyle.container,
                  foreground: stateStyle.onContainer,
                ),
                ...buildMenuTagPills(context, item.tags),
              ],
            ),
          ),
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
    this.displayOrder = 0,
    this.kitchenMeatEnabled = false,
    this.kitchenMeatQuantity,
    this.kitchenMeatUnit = '',
    this.kitchenMeatClassifierOptionId = '',
  });

  final String id;
  final String name;
  final int deltaMinor;
  final bool isActive;
  final String? branchId;

  /// MENU-ORDER-001 (Codex): the row's current display_order, carried so an edit
  /// PRESERVES it (options are drag-reordered, not hand-numbered; sizes/variants
  /// keep their numeric field but must still open showing the current value).
  final int displayOrder;

  /// KITCHEN-MEAT-001: the option's current meat metadata (options only;
  /// size/variant rows leave these at their defaults).
  final bool kitchenMeatEnabled;
  final num? kitchenMeatQuantity;
  final String kitchenMeatUnit;

  /// 019: the stored classifier link on this option's own contribution.
  final String kitchenMeatClassifierOptionId;
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
    this.classifierOptions = const <({String id, String name})>[],
    this.embedded = false,
  });

  final String title;
  final IconData icon;
  final String addLabel;
  final PricedChildKind kind;
  final String parentId;
  final String currencyCode;
  final List<_PricedChildVm> rows;

  /// 019: every option of the SAME menu item — the split-by candidates offered
  /// inside a modifier option's edit dialog. Empty for size/variant sections,
  /// which have no preparation contribution to classify.
  final List<({String id, String name})> classifierOptions;

  /// When true the section renders WITHOUT its own card chrome (a plain
  /// header row + rows) — used inside the modifier tiles so options stop
  /// being a card-in-card-in-card.
  final bool embedded;

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    final l10n = AppLocalizations.of(context);
    if (!await showMenuDeleteConfirm(context)) return;
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .softDelete(
          entity: _entityForKind(kind),
          id: id,
          // A priced child's sibling owner is [parentId] (the item for a
          // size/variant, the modifier group for an option) — refuse the delete
          // while THAT list is mid-reorder.
          parentId: parentId,
        );
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

  /// MENU-ORDER-001 (Codex): the exact sibling scope this section reorders — the
  /// options of THIS modifier group ([parentId] is the modifier id). Distinct per
  /// modifier, so reordering one group's options never blocks another's.
  MenuReorderScope _reorderScope(WidgetRef ref) {
    final s = ref.read(menuScopeProvider);
    return MenuReorderScope(
      organizationId: s.organizationId,
      restaurantId: s.restaurantId,
      branchId: s.branchId,
      entity: _entityForKind(kind),
      parentId: parentId,
    );
  }

  void _reorder(
    BuildContext context,
    WidgetRef ref,
    int oldIndex,
    int newIndex,
  ) {
    final l10n = AppLocalizations.of(context);
    final ids = menuReorderedIds(
      [for (final r in rows) r.id],
      oldIndex,
      newIndex,
    );
    // MENU-ORDER-001 (Codex #4): controller-owned lifecycle on the provider Ref
    // — no WidgetRef-after-await, no latch leak on disposal.
    ref
        .read(menuWriteControllerProvider)
        .reorderScoped(scope: _reorderScope(ref), orderedIds: ids)
        .then((outcome) {
          if (outcome != null && !outcome.isSuccess && context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.menuWriteProblem)));
          }
        });
  }

  _PricedChildRow _row(
    BuildContext context,
    WidgetRef ref,
    int i, {
    int? reorderIndex,
  }) {
    return _PricedChildRow(
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
        // MENU-ORDER-001 (Codex): open showing the CURRENT display_order so a
        // details-save preserves it (options hide the field; size/variant keep it).
        initialDisplayOrder: rows[i].displayOrder,
        initialActive: rows[i].isActive,
        // KITCHEN-MEAT-001: carry the option's current meat metadata.
        initialKitchenMeatEnabled: rows[i].kitchenMeatEnabled,
        initialKitchenMeatQuantity: rows[i].kitchenMeatQuantity,
        initialKitchenMeatUnit: rows[i].kitchenMeatUnit,
        // 019: the option's own classifier link + the same-item candidates it
        // may point at (the dialog excludes the option being edited).
        initialKitchenMeatClassifierOptionId:
            rows[i].kitchenMeatClassifierOptionId,
        classifierOptions: classifierOptions,
      ),
      onDelete: () => _delete(context, ref, rows[i].id),
      reorderIndex: reorderIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // MENU-ORDER-001: modifier OPTIONS are drag-reorderable. Sizes/variants keep
    // their number-field ordering (out of this ticket's scope). Nested inside the
    // scrolling editor -> shrinkWrap + non-scrolling physics.
    final reorderable = kind == PricedChildKind.option && rows.length > 1;
    // MENU-ORDER-001 (Codex #5/#7): disable this option list while ITS reorder
    // persists (options only; size/variant never reorder here).
    final reordering =
        reorderable &&
        ref.watch(menuReorderInFlightProvider(_reorderScope(ref)));
    // Codex #5: the ADD control is outside the list IgnorePointer — disable it too
    // while the reorder persists (null onPressed => the button reads as disabled;
    // zero write calls).
    final addButton = TextButton.icon(
      onPressed: reordering
          ? null
          : () => showPricedChildFormDialog(
              context,
              kind: kind,
              parentId: parentId,
              currencyCode: currencyCode,
              // 020 (Codex MEDIUM #5): the CREATE path gets the same same-item
              // candidates as Edit, so an owner adding a new size option can
              // set its preparation contribution AND its "Split by option" in
              // ONE save instead of saving, reopening and editing. The option
              // being created has no id yet, so it cannot appear in its own
              // list — self-reference is impossible here by construction.
              classifierOptions: classifierOptions,
            ),
      icon: const Icon(Icons.add, size: RestoflowIconSizes.sm),
      label: Text(addLabel),
    );
    final body = rows.isEmpty
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
        : reorderable
        ? ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: rows.length,
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) =>
                _reorder(context, ref, oldIndex, newIndex),
            itemBuilder: (context, i) => KeyedSubtree(
              key: ValueKey(rows[i].id),
              child: _row(context, ref, i, reorderIndex: i),
            ),
          )
        : Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _row(context, ref, i),
              ],
            ],
          );
    final content = IgnorePointer(
      ignoring: reordering,
      child: Opacity(opacity: reordering ? 0.6 : 1.0, child: body),
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
    this.reorderIndex,
  });

  final _PricedChildVm row;
  final String currencyCode;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// MENU-ORDER-001: when non-null this row is inside a reorderable option list
  /// and shows a leading drag handle bound to this index.
  final int? reorderIndex;

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
          if (reorderIndex != null) ...[
            ReorderableDragStartListener(
              index: reorderIndex!,
              child: Icon(
                Icons.drag_indicator,
                size: RestoflowIconSizes.sm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
          ],
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
        .softDelete(
          entity: MenuEntityType.modifier,
          id: id,
          // Modifier groups' sibling owner is their item — refuse the delete
          // while this item's modifier-group list is mid-reorder.
          parentId: item.id,
        );
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

  /// MENU-ORDER-001 (Codex): the exact sibling scope this section reorders — the
  /// modifier groups of THIS item. Distinct per item.
  MenuReorderScope _reorderScope(WidgetRef ref) {
    final s = ref.read(menuScopeProvider);
    return MenuReorderScope(
      organizationId: s.organizationId,
      restaurantId: s.restaurantId,
      branchId: s.branchId,
      entity: MenuEntityType.modifier,
      parentId: item.id, // the groups' sibling owner is their item
    );
  }

  void _reorderModifiers(
    BuildContext context,
    WidgetRef ref,
    int oldIndex,
    int newIndex,
  ) {
    final l10n = AppLocalizations.of(context);
    final ids = menuReorderedIds(
      [for (final m in modifiers) m.id],
      oldIndex,
      newIndex,
    );
    // MENU-ORDER-001 (Codex #4): controller-owned lifecycle on the provider Ref
    // — no WidgetRef-after-await, no latch leak on disposal.
    ref
        .read(menuWriteControllerProvider)
        .reorderScoped(scope: _reorderScope(ref), orderedIds: ids)
        .then((outcome) {
          if (outcome != null && !outcome.isSuccess && context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.menuWriteProblem)));
          }
        });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // MENU-ORDER-001 (Codex #5/#7): disable this item's modifier-group controls
    // while ITS reorder persists.
    final reordering =
        modifiers.length > 1 &&
        ref.watch(menuReorderInFlightProvider(_reorderScope(ref)));
    final itemClassifierOptions = <({String id, String name})>[
      for (final group in modifiers)
        for (final option in snapshot.optionsForModifier(group.id))
          (id: option.id, name: option.name),
    ];
    Widget cardFor(int index, {int? reorderIndex}) {
      final modifier = modifiers[index];
      return _ModifierCard(
        modifier: modifier,
        item: item,
        currencyCode: currencyCode,
        options: snapshot.optionsForModifier(modifier.id),
        // 019: every option of THIS item, across ALL of its modifier groups —
        // the candidates a contribution may be split by (a size option in the
        // Size group split by Cheese in the Extras group). Product-scoped by
        // construction: `modifiers.menu_item_id` ties each group to one item,
        // so another product's options are unreachable from here.
        classifierOptions: itemClassifierOptions,
        onDelete: () => _deleteModifier(context, ref, modifier.id),
        reorderIndex: reorderIndex,
      );
    }

    return MenuSectionCard(
      title: l10n.menuModifiersHeading,
      icon: Icons.layers_outlined,
      contentPadding: EdgeInsets.zero,
      // OPS-043 Phase 4: the "Add template" entry point is gone. The six
      // hardcoded Dart templates it opened are superseded by "copy settings
      // from an existing item" at the top of this editor, which copies the
      // restaurant's OWN configuration — kitchen counts, classifiers and real
      // prices included — instead of a generic guess with hardcoded ILS deltas.
      // Codex #5: the ADD control sits in the header (outside the list
      // IgnorePointer) — disable it while THIS item's group reorder persists.
      trailing: TextButton.icon(
        onPressed: reordering
            ? null
            : () => showModifierFormDialog(context, menuItemId: item.id),
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
              // MENU-ORDER-001: modifier GROUPS are drag-reorderable. Nested in
              // the scrolling editor -> shrinkWrap + non-scrolling physics.
              // Codex #5/#7: inert + dimmed while this item's group reorder persists.
              child: IgnorePointer(
                ignoring: reordering,
                child: Opacity(
                  opacity: reordering ? 0.6 : 1.0,
                  child: modifiers.length > 1
                      ? ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: modifiers.length,
                          // ignore: deprecated_member_use
                          onReorder: (oldIndex, newIndex) => _reorderModifiers(
                            context,
                            ref,
                            oldIndex,
                            newIndex,
                          ),
                          itemBuilder: (context, index) => Padding(
                            key: ValueKey(modifiers[index].id),
                            padding: const EdgeInsets.only(
                              bottom: RestoflowSpacing.md,
                            ),
                            child: cardFor(index, reorderIndex: index),
                          ),
                        )
                      : Column(
                          children: [
                            for (
                              var index = 0;
                              index < modifiers.length;
                              index++
                            )
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: RestoflowSpacing.md,
                                ),
                                child: cardFor(index),
                              ),
                          ],
                        ),
                ),
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
    required this.classifierOptions,
    required this.onDelete,
    this.reorderIndex,
  });

  final Modifier modifier;
  final MenuItem item;
  final String currencyCode;
  final List<ModifierOption> options;

  /// 019: every option of the SAME menu item (all groups) — the split-by
  /// candidates offered inside each option's edit dialog.
  final List<({String id, String name})> classifierOptions;
  final VoidCallback onDelete;

  /// MENU-ORDER-001: when non-null this card is inside a reorderable group list
  /// and shows a leading drag handle bound to this index.
  final int? reorderIndex;

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
              if (reorderIndex != null) ...[
                ReorderableDragStartListener(
                  index: reorderIndex!,
                  child: Icon(
                    Icons.drag_indicator,
                    size: RestoflowIconSizes.md,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
              ],
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
                      initialAllowQuantity: modifier.allowQuantity,
                      initialMaxQuantity: modifier.maxQuantity,
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
            // 019: every option of THIS menu item, across all of its modifier
            // groups — the only ids a contribution on this item may be split
            // by. Built from the item's own snapshot, so another product's
            // options can never appear.
            classifierOptions: classifierOptions,
            rows: options
                .map(
                  (o) => _PricedChildVm(
                    id: o.id,
                    name: o.name,
                    deltaMinor: o.priceDeltaMinor,
                    isActive: o.isActive,
                    branchId: o.branchId,
                    displayOrder: o.displayOrder,
                    // KITCHEN-MEAT-001: pre-fill the option's meat metadata so the
                    // edit dialog shows the current values.
                    kitchenMeatEnabled: o.hasKitchenMeat,
                    kitchenMeatQuantity: o.kitchenMeatQuantity,
                    kitchenMeatUnit: o.kitchenMeatUnit,
                    // 019: the option's own classifier link.
                    kitchenMeatClassifierOptionId:
                        o.kitchenMeatClassifierOptionId,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// KITCHEN-PREP-001: one editable kitchen prep component row (name / quantity /
/// unit) held by the item editor. Owns its controllers; the editor disposes it.
class _PrepRow {
  _PrepRow({
    String name = '',
    String quantity = '',
    String unit = '',
    this.classifierOptionId = '',
    this.copiedClassifierOptionId = '',
  }) : name = TextEditingController(text: name),
       quantity = TextEditingController(text: quantity),
       unit = TextEditingController(text: unit);

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController unit;

  /// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016: the id of the modifier option
  /// this resource is split by; `''` = not split (the default, and what every
  /// existing row keeps). Never a quantity — only which bucket the configured
  /// quantity is counted in.
  String classifierOptionId;

  /// OPS-043 Phase 4: the SOURCE option id this row was copied with, held
  /// apart from [classifierOptionId] on purpose.
  ///
  /// A source id in [classifierOptionId] would resolve against THIS item's live
  /// options, find nothing, be flagged missing, be dropped from the payload —
  /// and then be CLEARED by the post-save cleanup, destroying the link before
  /// the flush could ever remap it. Kept here it is invisible to all of that,
  /// travels with the row through renames and reordering, and is swapped for
  /// the new option's id on the copy's second pass. Emptied once that lands.
  String copiedClassifierOptionId;

  /// Inline validation errors surfaced on save (blank name / non-positive qty).
  MenuFieldError? nameError;
  MenuFieldError? quantityError;

  /// 016: set when [classifierOptionId] no longer matches a live option of this
  /// item (the option was deleted). Saving then CLEARS the link and the resource
  /// falls back to its single unsplit total.
  bool classifierMissing = false;

  /// A plain snapshot of this row's text, so the editor can restore it after a
  /// discard without holding on to disposed controllers.
  _PrepRowValues get values => _PrepRowValues(
    name: name.text,
    quantity: quantity.text,
    unit: unit.text,
    classifierOptionId: classifierOptionId,
    copiedClassifierOptionId: copiedClassifierOptionId,
  );

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
  }
}

/// OPS-043 Phase 4B: the controller-free form of a [_PrepRow], used to remember
/// the Kitchen setup the operator had before a copy overwrote it.
class _PrepRowValues {
  const _PrepRowValues({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.classifierOptionId,
    required this.copiedClassifierOptionId,
  });

  final String name;
  final String quantity;
  final String unit;
  final String classifierOptionId;
  final String copiedClassifierOptionId;

  _PrepRow toRow() => _PrepRow(
    name: name,
    quantity: quantity,
    unit: unit,
    classifierOptionId: classifierOptionId,
    copiedClassifierOptionId: copiedClassifierOptionId,
  );
}

/// OPS-043 Phase 4: the editor's bridge from the copy pipeline to the scoped
/// write controller. It holds no state of its own — every decision about WHAT
/// to write lives in `flushMenuCopiedConfig`; this only knows HOW.
class _EditorCopySink implements MenuCopyWriteSink {
  _EditorCopySink({
    required this.controller,
    required this.menuItemId,
    required this.rewritePrep,
  });

  final MenuWriteController controller;
  final String menuItemId;

  /// Re-sends the item's full state with the prep rows' classifier ids resolved
  /// through the old -> new option map.
  final Future<MenuWriteOutcome> Function(Map<String, String> remap)
  rewritePrep;

  @override
  Future<MenuWriteOutcome> createGroup(CopiedGroupDraft group) =>
      controller.upsertModifier(
        menuItemId: menuItemId,
        name: group.name,
        selectionType: group.selectionType,
        minSelect: group.minSelect,
        maxSelect: group.maxSelect,
        isRequired: group.isRequired,
        // A CREATE keeps the copied order: the MENU-ORDER-001 guard trigger is
        // BEFORE UPDATE only, so an insert honours the value it is given.
        displayOrder: group.displayOrder,
        isActive: group.isActive,
        // Copied together on purpose — the server rejects `single` +
        // allow_quantity, so splitting them would invent an invalid group.
        allowQuantity: group.allowQuantity,
        maxQuantity: group.maxQuantity,
      );

  @override
  Future<MenuWriteOutcome> upsertOption({
    String? id,
    required String modifierId,
    required CopiedOptionDraft option,
    required Map<String, dynamic>? kitchenMeat,
  }) => controller.upsertModifierOption(
    id: id,
    modifierId: modifierId,
    name: option.name,
    priceDeltaMinor: option.priceDeltaMinor,
    // Create: the copied order. Update (the classifier pass): null, so the
    // guard trigger preserves whatever order the row has — sending a value
    // there is how a drag-set order gets silently overwritten.
    displayOrder: id == null ? option.displayOrder : null,
    isActive: option.isActive,
    // The FULL object, always: `p_kitchen_meat` is omitted when this is null
    // and the RPC then writes NULL, so a pass that forgot the count would
    // destroy it.
    kitchenMeat: kitchenMeat,
  );

  @override
  Future<MenuWriteOutcome> rewritePrepClassifiers(Map<String, String> remap) =>
      rewritePrep(remap);
}
