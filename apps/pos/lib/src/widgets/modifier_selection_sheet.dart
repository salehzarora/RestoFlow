import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../format/money_format.dart';
import '../pos_palette.dart';
import '../state/cart_controller.dart';
import '../state/pos_menu_provider.dart';

/// Wraps a formatted money run in Unicode LTR ISOLATES (LRI...PDI) so bidi
/// reordering inside an RTL phrase can never split the sign, currency symbol
/// and digits (`+₪3.00` stays exactly that, never `₪3.00+`). Applied ONLY to
/// the money run embedded in a localized phrase - the surrounding Arabic or
/// Hebrew text keeps its natural direction, and MoneyFormatter output itself
/// is unchanged. Standalone money [Text]s force `textDirection: ltr` instead,
/// so their strings stay byte-identical.
String ltrIsolate(String money) => '\u2066$money\u2069';

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
///
/// POS customization V2 carries the CONTENT redesign — a fixed header, the
/// responsive option grids (single-choice cards 3/2/1, additions 2/1,
/// full-width quantity-stepper rows), and a sticky footer over the one
/// scrolling body. The PRESENTATION is a modal bottom sheet at every width
/// (see [show]): the cashier's item customization always slides up from the
/// bottom edge, on a phone and on a wide cashier screen alike.
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

  /// The widest the sheet is allowed to grow. Past this the option cards would
  /// stretch into unusable line lengths on a large cashier screen; the sheet
  /// then stays centered on the bottom edge. Below it the sheet simply takes
  /// the width it is given (Material clamps it against the LIVE viewport).
  static const double _maxSheetWidth = 1200;

  /// The share of the viewport height the sheet CONTENT may take. The sheet is
  /// deliberately large (a cashier works inside it), but the scrim above it
  /// always stays visible — it must read as a bottom sheet, never a page. The
  /// Material drag handle adds its own 48dp band above this content, and an
  /// open keyboard shrinks it further (the body scrolls).
  static const double _maxHeightFactor = 0.85;

  /// Below this much usable content height the fixed header no longer earns its
  /// space: a short landscape tablet with the on-screen keyboard up can leave
  /// under 200dp, and a 72dp header plus the sticky footer would squeeze the
  /// body to a slit — or overflow it. There the header SCROLLS with the body
  /// (the drag handle stays as the stable top) so the note field the cashier is
  /// typing into remains reachable, and the footer's padding tightens. The
  /// total + confirm footer always stays sticky.
  static const double _compactHeightBelow = 360;

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

  /// Presents the picker as a MODAL BOTTOM SHEET at EVERY width — the cashier
  /// workflow the POS is built around: it slides up from the bottom edge over
  /// the dimmed POS, with rounded top corners and a Material drag handle, and
  /// it stays attached to that edge (never a floating centered dialog).
  ///
  /// The sheet takes the full width it is given, up to [_maxSheetWidth]; past
  /// that it stays centered on the bottom edge (a 2560px cashier screen must
  /// not stretch an option row into an unreadable line). The cap is a CONSTANT,
  /// never a snapshot of the viewport: [BottomSheet] clamps it against the live
  /// viewport on every layout, so the sheet re-flows when the browser window is
  /// resized or the tablet is rotated WHILE it is open. Deriving the width from
  /// `MediaQuery` here instead would freeze it at its open-time value.
  ///
  /// Same widget, same behavior, same keys at every width. Dismissal: drag
  /// down, tap the scrim, press Escape, or use the explicit close button —
  /// none of which confirms.
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
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // The sheet sizes itself to its content (up to the height cap) and the
      // body is the only scrolling region.
      isScrollControlled: true,
      showDragHandle: true,
      // Keep the sheet clear of the status bar / notch (SafeArea(bottom:false)
      // around the sheet — it stays attached to the bottom edge).
      useSafeArea: true,
      // Most of the available width on a cashier screen — well past Material's
      // 640dp default — while a wide desktop keeps it centered and capped.
      constraints: const BoxConstraints(maxWidth: _maxSheetWidth),
      // Rounded TOP corners, square bottom: the sheet is attached to the
      // bottom edge. Mirrors the design system's bottomSheetTheme, stated at
      // the call site so the presentation does not depend on the host theme.
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RestoflowRadii.xl),
        ),
      ),
      clipBehavior: Clip.antiAlias,
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
  }

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
    _applyInitialState();
  }

  @override
  void didUpdateWidget(ModifierSelectionSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // POS customization V2 (Codex review): when the SAME widget position is
    // reused for a genuinely different product / modifier configuration, the
    // previous selections and note are stale - rebuild from the NEW widget's
    // initial payload. Ordinary rebuilds of the same product (locale, theme,
    // MediaQuery, parent setState) keep the cashier's in-progress input: the
    // item id and the group identities are unchanged there.
    if (_configSignature(oldWidget) != _configSignature(widget)) {
      _applyInitialState();
    }
  }

  /// A deterministic signature of everything that makes a customization
  /// CONFIGURATION distinct — i.e. every field that can change which
  /// selections are valid, what they cost, or how the cashier interacts:
  ///
  ///  * the item id;
  ///  * per group, IN ORDER: id, owning item, single-vs-multi, min/max
  ///    selections, required-ness, quantity support and the per-option cap;
  ///  * per option, IN ORDER: id and its SIGNED price delta.
  ///
  /// Deliberately EXCLUDED (they cannot make an in-progress selection stale,
  /// so a change there must not throw the cashier's work away): the item's
  /// price, the group/option display NAMES and the option's kitchen-meat
  /// data. Those are read from the LIVE `widget.groups` at render time and
  /// snapshotted at confirm time, so they can never go stale in [_selected].
  ///
  /// Equivalent-but-newly-allocated model objects (a parent rebuild handing
  /// down fresh instances with the same configuration) produce the SAME
  /// signature, so ordinary locale / theme / MediaQuery / parent rebuilds
  /// preserve the in-progress selections and note.
  static String _configSignature(ModifierSelectionSheet w) {
    final buffer = StringBuffer(w.item.id);
    for (final group in w.groups) {
      buffer
        ..write('|g:')
        ..write(group.id)
        ..write(':')
        ..write(group.menuItemId)
        ..write(':')
        ..write(group.singleSelect)
        ..write(':')
        ..write(group.minSelect)
        ..write(':')
        ..write(group.maxSelect)
        ..write(':')
        ..write(group.isRequired)
        ..write(':')
        ..write(group.allowQuantity)
        ..write(':')
        ..write(group.maxQuantity);
      for (final option in group.options) {
        buffer
          ..write('|o:')
          ..write(option.id)
          ..write(':')
          ..write(option.priceDeltaMinor);
      }
    }
    return buffer.toString();
  }

  /// TABLET-UX-001 (A): prefill from the cart line being edited. Each initial
  /// selection is matched back to its group by option id (a SelectedModifier
  /// snapshot carries the option id + its taken quantity), so re-picking works
  /// against the live groups. The note is restored verbatim. This is also the
  /// reset path when the represented product genuinely changes.
  void _applyInitialState() {
    _selected.clear();
    for (final selection in widget.initialSelections) {
      for (final group in widget.groups) {
        if (group.options.any((o) => o.id == selection.optionId)) {
          (_selected[group.id] ??= <String, int>{})[selection.optionId] =
              selection.quantity;
          break;
        }
      }
    }
    _noteController.text = widget.initialNote ?? '';
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

  /// Whether an option in [group] can be activated right now. A selected
  /// option always can (deselecting is never blocked); a single-select choice
  /// always can (it swaps); an unselected option in a multi-select group at
  /// its distinct-option capacity cannot — the existing behaviour makes that
  /// tap a no-op, and the semantics/affordance now say so truthfully.
  bool _canActivate(PosModifierGroup group, bool selected) {
    if (selected || group.singleSelect) return true;
    final max = group.effectiveMax;
    return max == null || _groupSelection(group.id).length < max;
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

    // POS customization V2 composition: the item header, the modifier body as
    // the ONLY scrolling region, and a sticky hairline-topped footer (total +
    // confirm) that never scrolls away. The header is fixed above the body at
    // any normal height, and joins the scrolling body when the sheet is squeezed
    // (see [_compactHeightBelow]).
    //
    // Part E header: thumbnail + name + BASE price, so the cashier reads base
    // vs the running total at the bottom. NOTE: the base price is a DIFFERENT
    // money string than the running total once any paid option is picked —
    // tests pin the total's render count. (No description line: the menu item
    // model carries no description field, and nothing is ever fabricated.)
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
                // The money run rides inside the localized phrase as an
                // LTR isolate: stable under Arabic/Hebrew bidi.
                l10n.posModifierBasePrice(ltrIsolate(basePriceText)),
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
        const SizedBox(width: RestoflowSpacing.sm),
        // An explicit close, alongside the sheet's drag handle, scrim and
        // Escape: keyboard-reachable, a 48dp target, and localized for
        // screen readers through the Material tooltip. Closing never
        // confirms — the cart is untouched.
        IconButton(
          key: const Key('modifier-close-button'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );

    // The one scrolling region: every modifier group, then the item note.
    final bodyChildren = <Widget>[
      for (final group in widget.groups) ...[
        Padding(
          padding: const EdgeInsets.only(
            top: RestoflowSpacing.md,
            bottom: RestoflowSpacing.xs,
          ),
          child: _GroupHeader(
            title: Text(
              group.name,
              // Long group names may take a second line before
              // ellipsizing (large text scales / long strings).
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            pills: [
              // Live selected-count pill: n/m (or open-ended n).
              RestoflowStatusPill(
                label: _countLabel(
                  l10n,
                  group,
                  _groupSelection(group.id).length,
                ),
                tone: _countTone(group, _groupSelection(group.id).length),
              ),
              if (group.effectiveMin > 0)
                RestoflowStatusPill(
                  label: l10n.posModifierRequired,
                  tone: RestoflowTone.warning,
                  icon: Icons.priority_high,
                )
              else
                // Quiet counterpart so "no pill" never has to be
                // interpreted: this group may be skipped.
                RestoflowStatusPill(label: l10n.posModifierOptional),
            ],
          ),
        ),
        // V2 helper line: required single-choice groups say what to do
        // ("Choose one option") — derived from the group's real rules.
        if (group.singleSelect && group.effectiveMin > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              bottom: RestoflowSpacing.xs,
            ),
            child: Text(
              l10n.posModifierChooseOne,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        _groupOptions(group),
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
    ];

    // Sticky footer: a hairline-topped strip holding the running total and the
    // confirm action — visible however long the modifier body grows. Its
    // padding tightens when the sheet is squeezed (keyboard on a short
    // landscape tablet); the total and the confirm button themselves never
    // shrink — a cashier must still read the price and hit a full-size target.
    Widget footer({required bool compact}) {
      final gap = compact ? RestoflowSpacing.sm : RestoflowSpacing.md;
      return Container(
        margin: EdgeInsetsDirectional.only(top: gap),
        padding: EdgeInsetsDirectional.only(top: gap),
        decoration: const BoxDecoration(
          border: BorderDirectional(top: BorderSide(color: kRestoflowHairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Design-polish: a visible running total ABOVE the confirm
            // button, so the price consequence of each pick is readable
            // without parsing the button label.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    l10n.posReceiptTotal,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                Flexible(
                  child: Text(
                    totalText,
                    // Standalone money run: forced LTR so RTL locales never
                    // reorder currency/digits (the string is unchanged).
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
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
                      // LTR-isolated money inside the localized phrase.
                      : l10n.posAddToCartWithTotal(ltrIsolate(totalText)),
                ),
                style: RestoflowButtonStyles.big(context),
              ),
            ),
          ],
        ),
      );
    }

    // ONE presentation at every width — the bottom sheet. The Material drag
    // handle supplies the top band, so the content adds no top padding of its
    // own; the height cap keeps the scrim visible above the sheet.
    return SafeArea(
      // The on-screen keyboard (note field) pushes the sheet content up
      // instead of covering it (isScrollControlled sheets don't auto-inset),
      // and the body — the only scrolling region — shrinks to fit.
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height *
                ModifierSelectionSheet._maxHeightFactor,
          ),
          // The REAL height the sheet gets (the cap, clamped by the route and
          // by an open keyboard) decides whether the header can stay fixed.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxHeight <
                  ModifierSelectionSheet._compactHeightBelow;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact) ...[
                    header,
                    const SizedBox(height: RestoflowSpacing.sm),
                  ],
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Squeezed: the header scrolls WITH the body rather
                        // than eating the little height that is left.
                        if (compact) ...[
                          header,
                          const SizedBox(height: RestoflowSpacing.sm),
                        ],
                        ...bodyChildren,
                      ],
                    ),
                  ),
                  footer(compact: compact),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The options of one group in their V2 responsive layout (real ordering,
  /// selection rules, and keys unchanged):
  ///  * single-choice groups: equal-width selectable CARDS — up to three per
  ///    row on a wide modal, two on medium widths, a single column when
  ///    narrow (never a horizontal scroller, never overflow);
  ///  * multi-choice checkbox groups: compact tiles, two columns when the
  ///    modal is wide enough, one otherwise;
  ///  * quantity-stepper groups keep the full-width row so the −/+ pill and
  ///    label never cramp.
  Widget _groupOptions(PosModifierGroup group) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final int columns;
        if (group.singleSelect) {
          columns = width >= 520 ? 3 : (width >= 340 ? 2 : 1);
        } else if (group.hasQuantitySteppers) {
          columns = 1;
        } else {
          columns = width >= 560 ? 2 : 1;
        }

        Widget tile(PosModifierOption option, {required bool compactCard}) {
          final picked = _groupSelection(group.id);
          final selected = picked.containsKey(option.id);
          // The ONLY real reason an option cannot be activated right now (the
          // models carry no disabled/unavailable flag): a multi-select group
          // already at its distinct-option capacity — tapping an unselected
          // option there is, and stays, a no-op. A single-select group always
          // activates (the tap SWAPS the choice), and an ALREADY-selected
          // option always stays deselectable.
          final canActivate = _canActivate(group, selected);
          return _OptionTile(
            key: ValueKey('modifier-option-${option.id}'),
            group: group,
            option: option,
            currencyCode: widget.currencyCode,
            selected: selected,
            quantity: picked[option.id] ?? 0,
            compactCard: compactCard,
            canActivate: canActivate,
            onToggle: canActivate ? () => _toggle(group, option) : null,
            onIncrement: group.hasQuantitySteppers
                ? () => _increment(group, option)
                : null,
            onDecrement: group.hasQuantitySteppers
                ? () => _decrement(group, option)
                : null,
          );
        }

        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in group.options)
                tile(option, compactCard: false),
            ],
          );
        }
        const gap = RestoflowSpacing.sm;
        final itemWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: RestoflowSpacing.xs,
          children: [
            for (final option in group.options)
              SizedBox(
                width: itemWidth,
                child: tile(option, compactCard: group.singleSelect),
              ),
          ],
        );
      },
    );
  }
}

/// The sheet header's item thumbnail (Part E): the product photo when the menu
/// resolved a signed [DemoMenuItem.imageUrl] (real menus only), otherwise —
/// and on ANY load failure — the category-tinted icon, mirroring the menu
/// card's fallback. Images are never load-bearing.
class _ItemThumbnail extends StatelessWidget {
  const _ItemThumbnail({required this.item, required this.category});

  /// Thumbnail edge (56–72dp band; square, rounded). V2: top of the band so
  /// the product reads instantly.
  static const double _size = 72;

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

/// A modifier-group header: the group title with its live count + required or
/// optional pills at the reading end. When the modal is narrow or the OS text
/// scale is large, the pills drop to their own wrapped line instead of being
/// squeezed until they overflow.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.pills});

  final Widget title;
  final List<Widget> pills;

  @override
  Widget build(BuildContext context) {
    final pillCluster = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: RestoflowSpacing.xs,
      runSpacing: RestoflowSpacing.xs,
      children: pills,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure the pills: when they need more than half of the header they
        // get their own line (the title keeps the full width above them).
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final roomy = constraints.maxWidth >= 360 * scale;
        if (roomy) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: title),
              const SizedBox(width: RestoflowSpacing.sm),
              Flexible(child: pillCluster),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            title,
            const SizedBox(height: RestoflowSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: pillCluster,
            ),
          ],
        );
      },
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
    this.compactCard = false,
    this.canActivate = true,
    super.key,
  });

  final PosModifierGroup group;
  final PosModifierOption option;
  final String currencyCode;
  final bool selected;

  /// Toggles this option; NULL when it cannot be activated right now (a
  /// multi-select group at capacity), which keeps the existing no-op
  /// behaviour while removing the ink/keyboard affordance.
  final VoidCallback? onToggle;

  /// Selected units of this option (0 = unselected; only ever > 1 on a
  /// quantity-enabled group).
  final int quantity;

  /// Non-null only on quantity-enabled groups — renders the −/+ stepper.
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  /// V2: true renders the single-choice CARD layout (radio + name over the
  /// price delta, centred) used by the responsive card grid; false keeps the
  /// full-width row layout. Same tap target, key, and states either way.
  final bool compactCard;

  /// Whether this option can be activated right now (see
  /// `_ModifierSelectionSheetState._canActivate`). False only for an
  /// unselected option in a multi-select group at its capacity: the tile is
  /// then inert (as it already was) and announces itself as disabled.
  final bool canActivate;

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

    final nameStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
    );
    final deltaStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
    );
    final freeStyle = theme.textTheme.bodySmall?.copyWith(
      color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
    );
    // "free" stays the single localized zero-delta label (included at no
    // charge) in BOTH layouts — one Text per zero-delta option, as pinned.
    // A signed delta is a standalone money run: forced LTR so RTL locales
    // never reorder it (the string itself is unchanged). A zero delta keeps
    // the single localized 'free' label.
    final priceLabel = deltaText != null
        ? Text(deltaText, textDirection: TextDirection.ltr, style: deltaStyle)
        : Text(l10n.posModifierFree, style: freeStyle);
    final hasStepper = onIncrement != null && onDecrement != null;
    // ONE useful semantic node per option (Codex review): the FULL option
    // name + its real price/free label, whatever the visual text does.
    final semanticLabel =
        '${option.name}, ${deltaText ?? l10n.posModifierFree}';

    // V2 card layout for single-choice grids: radio + name over the price
    // delta, centred, taller touch target. The row layout below is unchanged.
    final Widget body = compactCard
        ? ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.md,
                vertical: RestoflowSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      control,
                      const SizedBox(width: RestoflowSpacing.xs),
                      Flexible(
                        child: Text(
                          option.name,
                          // Long real option names WRAP (up to three lines)
                          // instead of ellipsizing; the price sits on its own
                          // line below, so they can never collide.
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: nameStyle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RestoflowSpacing.xxs),
                  priceLabel,
                ],
              ),
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.md,
                vertical: RestoflowSpacing.sm,
              ),
              child: Row(
                children: [
                  // The decorative parts are excluded from semantics: the
                  // tile's single node already carries name + price via its
                  // label, so nothing announces twice. A live stepper keeps
                  // its own actionable buttons (below).
                  ExcludeSemantics(child: control),
                  const SizedBox(width: RestoflowSpacing.md),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(option.name, style: nameStyle),
                    ),
                  ),
                  const SizedBox(width: RestoflowSpacing.sm),
                  ExcludeSemantics(child: priceLabel),
                  if (hasStepper) ...[
                    const SizedBox(width: RestoflowSpacing.sm),
                    _OptionQuantityStepper(
                      l10n: l10n,
                      optionId: option.id,
                      quantity: quantity,
                      // + is disabled (an honest no-op) at the per-option cap
                      // AND when adding this option at all is blocked by the
                      // group's distinct-option capacity; − is disabled at 0.
                      canIncrement: quantity == 0
                          ? canActivate
                          : (group.maxQuantity == null ||
                                quantity < group.maxQuantity!),
                      onIncrement: onIncrement!,
                      onDecrement: onDecrement!,
                    ),
                  ],
                ],
              ),
            ),
          );

    // Design-polish: options are >=48dp bordered tiles with an unmistakable
    // selected state (primary tint + accent border) instead of dense,
    // zero-padding ListTiles. The ValueKey stays on the tappable InkWell.
    final tile = AnimatedContainer(
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
          // Null when the option cannot be activated: no ripple, no keyboard
          // activation - matching the (already) inert behaviour.
          onTap: onToggle,
          // The ink/hover/keyboard-focus behaviour stays; its semantics do
          // NOT, so the option's single annotated node below owns the tap
          // action instead of a second, unlabelled node duplicating it.
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          // The whole card/tile stays the tap target in both layouts. Compact
          // cards exclude their whole visual subtree (the annotation's label
          // carries it); stepper rows exclude per part, above, so the -/+
          // buttons remain separately actionable semantic children.
          child: compactCard ? ExcludeSemantics(child: body) : body,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xxs),
      // The option's semantics: full name + real price/free label, a
      // checked state, and radio-group behaviour for single-choice groups.
      // The InkWell's tap/focus folds into the SAME node (MergeSemantics),
      // except where a live stepper must keep its own child buttons.
      child: Semantics(
        container: true,
        // The REAL interactive state: an option that cannot be activated right
        // now (multi-select group at capacity) announces itself disabled and
        // exposes NO tap action. The checked state stays truthful either way,
        // so an existing edit payload still reads as selected.
        enabled: onToggle != null,
        checked: selected,
        inMutuallyExclusiveGroup: group.singleSelect,
        label: semanticLabel,
        // The option itself is the tap target (mirrors the full-tile InkWell).
        // A quantity stepper's -/+ stay separate actionable children below.
        onTap: onToggle,
        child: tile,
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
      // The swallow-guard is a HIT-TEST device, not an action: keep it out of
      // the semantics tree so it cannot leak a phantom tap action (or merge
      // the quantity text) into the OPTION's node — which would otherwise
      // announce an available action on a blocked/disabled option.
      excludeFromSemantics: true,
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
