import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/customer_phone.dart';
import '../data/order_submission.dart' show kCustomerNameMaxLength;
import '../design/pos_visual_tokens.dart' show PosThemePair;
import '../pos_palette.dart';
import '../state/order_setup_controller.dart';
import 'table_picker_sheet.dart';

/// The active order's service-mode controls in the cart (RF-114): an order-type
/// selector (Dine-in / Takeaway) and, for dine-in, the table-assignment row with
/// validation. Reads/mutates [orderSetupControllerProvider]. In-memory demo only.
class OrderSetupSection extends ConsumerWidget {
  const OrderSetupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final setup = ref.watch(orderSetupControllerProvider);
    final controller = ref.read(orderSetupControllerProvider.notifier);

    // Design-polish: a denser idle footprint (tighter paddings) with a
    // full-width, >=44dp-tall segmented control.
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.posOrderTypeLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          // POS-DESIGN-HANDOFF-IMPLEMENTATION-004: the approved SLIDING-THUMB
          // segmented control (tokens §10) — a warm track whose navy-gradient
          // thumb slides to the active option. Selection is still carried by
          // ≥3 non-colour signals (thumb geometry, icon only on the active
          // option, label weight) and the full POS-ORDER-TYPE-SELECTOR-UI-001
          // semantics contract (button + selected state per segment).
          // Re-tapping the active option is already a no-op in the controller
          // (setOrderType returns early on an equal value).
          _PosOrderTypeSegmented(
            l10n: l10n,
            selected: setup.orderType,
            onSelected: controller.setOrderType,
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          if (setup.orderType == OrderType.dineIn)
            _TableRow(setup: setup, controller: controller)
          else
            _TakeawayHint(message: l10n.posTableNotNeeded),
          const SizedBox(height: RestoflowSpacing.sm),
          // ORDER-CUSTOMER-001 / POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the two
          // OPTIONAL customer fields. Neither gates submit, except that a
          // non-empty MALFORMED phone still blocks Send exactly as before.
          //
          // POS-VISUAL-REDESIGN-PHASE-1-007 Step 2: they were the two tallest,
          // loudest elements in the cart despite being optional and rarely
          // used, pushing the actual order below the fold. They now SHARE one
          // row wherever the cart is at least kPosCartPairedFieldsMinWidth
          // wide, and stack below it — each keeping its full height, its key,
          // its onChanged, its maxLength and its errorText.
          LayoutBuilder(
            builder: (context, constraints) {
              final name = _CustomerNameField(
                setup: setup,
                controller: controller,
              );
              final phone = _CustomerPhoneField(
                setup: setup,
                controller: controller,
              );
              // The threshold is the SECTION's width, so add back the
              // horizontal padding this LayoutBuilder sits inside.
              final sectionWidth =
                  constraints.maxWidth + 2 * RestoflowSpacing.lg;
              if (sectionWidth < kPosCartPairedFieldsMinWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [name, phone],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: name),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Expanded(child: phone),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// POS-DESIGN-HANDOFF-IMPLEMENTATION-004 — the approved sliding-thumb
/// order-type control (tokens §10): warm track (#F1EFE9, r14, 4px pad),
/// h46 cells, a navy-gradient thumb that slides to the active option on the
/// approved spring curve (320ms; instant under reduced motion).
///
/// The POS-ORDER-TYPE-SELECTOR-UI-001 contract is preserved: each segment is
/// a real button with `selected` semantics under its frozen key, the icon
/// renders ONLY on the active option, the active label is w700 vs w600, and
/// every cell keeps a ≥44dp target. Only the fill MECHANISM changed (a
/// sliding thumb instead of per-cell fills).
class _PosOrderTypeSegmented extends StatelessWidget {
  const _PosOrderTypeSegmented({
    required this.l10n,
    required this.selected,
    required this.onSelected,
  });

  final AppLocalizations l10n;
  final OrderType selected;
  final ValueChanged<OrderType> onSelected;

  static const _trackColor = Color(0xFFF1EFE9);

  @override
  Widget build(BuildContext context) {
    final pair = PosThemePair.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final dineInSelected = selected == OrderType.dineIn;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _trackColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        height: 46,
        child: Stack(
          children: [
            // The sliding thumb — dine-in is the FIRST (inline-start) cell.
            AnimatedAlign(
              alignment: dineInSelected
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.centerEnd,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: const Cubic(0.34, 1.56, 0.64, 1),
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Container(
                  key: const Key('order-type-thumb'),
                  decoration: BoxDecoration(
                    gradient: pair.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: pair.primary.withValues(alpha: 0.28),
                        offset: const Offset(0, 3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _SegmentCell(
                    key: const Key('order-type-dine-in'),
                    label: l10n.posOrderTypeDineIn,
                    icon: Icons.restaurant,
                    selected: dineInSelected,
                    onTap: () => onSelected(OrderType.dineIn),
                  ),
                ),
                Expanded(
                  child: _SegmentCell(
                    key: const Key('order-type-takeaway'),
                    label: l10n.posOrderTypeTakeaway,
                    icon: Icons.takeout_dining,
                    selected: !dineInSelected,
                    onTap: () => onSelected(OrderType.takeaway),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentCell extends StatelessWidget {
  const _SegmentCell({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected ? Colors.white : kRestoflowInk2;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The icon renders ONLY on the active option — one of the
              // pinned non-colour selection signals.
              if (selected) ...[
                Icon(icon, size: RestoflowIconSizes.sm, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The OPTIONAL customer-name input (ORDER-CUSTOMER-001). A stateful field so it
/// owns a [TextEditingController] whose text is cleared when the order-setup
/// state resets (customer name -> null) after a successful submit / new order.
class _CustomerNameField extends ConsumerStatefulWidget {
  const _CustomerNameField({required this.setup, required this.controller});

  final OrderSetupState setup;
  final OrderSetupController controller;

  @override
  ConsumerState<_CustomerNameField> createState() => _CustomerNameFieldState();
}

class _CustomerNameFieldState extends ConsumerState<_CustomerNameField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.setup.customerName ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Clear the field when the order-setup state resets (name -> null) after a
    // successful submit / new order — without disturbing the cashier's typing.
    ref.listen(orderSetupControllerProvider, (previous, next) {
      if (next.customerName == null && _text.text.isNotEmpty) {
        _text.clear();
      }
    });
    return TextField(
      key: const Key('customer-name-field'),
      controller: _text,
      // A display name is free text (ar/he/en + digits + spaces + punctuation);
      // we only cap the length and normalize (trim/empty->null) on read — no
      // charset filter that could reject a valid Arabic/Hebrew name.
      maxLength: kCustomerNameMaxLength,
      textInputAction: TextInputAction.done,
      onChanged: widget.controller.setCustomerName,
      // REFERENCE-REDESIGN-002: the optional customer fields wear the same
      // quiet filled treatment as the menu search (decoration ONLY — the
      // field widgets, focus behaviour and 008 keyboard identity are
      // untouched).
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        prefixIcon: const Icon(Icons.person_outline),
        labelText: l10n.customerNameLabel,
        hintText: l10n.customerNamePlaceholder,
        filled: true,
        fillColor: kPosInnerSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          borderSide: const BorderSide(color: kPosInputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          borderSide: const BorderSide(color: kPosInputBorder),
        ),
      ),
    );
  }
}

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL customer-phone input. A
/// stateful field owning a [TextEditingController] so its text is cleared when the
/// order-setup state resets after a submit / new order, and FILLED when a draft is
/// restored from recovery into an empty field (without disturbing active typing).
/// Shows a localized inline error for a non-empty malformed value; a valid or empty
/// phone never blocks submit.
class _CustomerPhoneField extends ConsumerStatefulWidget {
  const _CustomerPhoneField({required this.setup, required this.controller});

  final OrderSetupState setup;
  final OrderSetupController controller;

  @override
  ConsumerState<_CustomerPhoneField> createState() =>
      _CustomerPhoneFieldState();
}

class _CustomerPhoneFieldState extends ConsumerState<_CustomerPhoneField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.setup.customerPhoneInput,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? _errorFor(CustomerPhoneError? error, AppLocalizations l10n) {
    switch (error) {
      case CustomerPhoneError.unsupportedCharacters:
        return l10n.customerPhoneErrorChars;
      case CustomerPhoneError.tooFewDigits:
        return l10n.customerPhoneErrorDigits;
      case CustomerPhoneError.tooLong:
        return l10n.customerPhoneErrorInvalid;
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Sync the controller to the setup state on RESET (input -> '') and on a
    // recovery RESTORE (input -> a value while the field is empty), never while
    // the cashier is actively typing (both non-empty => leave the field alone, so
    // a stale async restore can never overwrite a newer in-progress draft).
    ref.listen(orderSetupControllerProvider, (previous, next) {
      final want = next.customerPhoneInput;
      if (want.isEmpty && _text.text.isNotEmpty) {
        _text.clear();
      } else if (want.isNotEmpty && _text.text.isEmpty) {
        _text.text = want;
      }
    });
    return TextField(
      key: const Key('customer-phone-field'),
      controller: _text,
      keyboardType: TextInputType.phone,
      // The 32-char cap is enforced here AND server-side; digits/space/+-() only
      // are validated on read (normalizeCustomerPhone) — no input formatter that
      // could fight an RTL keyboard or a legitimate paste.
      maxLength: kCustomerPhoneMaxLength,
      textInputAction: TextInputAction.done,
      onChanged: widget.controller.setCustomerPhone,
      // REFERENCE-REDESIGN-002: same quiet filled treatment (decoration
      // ONLY; behaviour, validation and identity untouched).
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        prefixIcon: const Icon(Icons.phone_outlined),
        labelText: l10n.customerPhoneLabel,
        hintText: l10n.customerPhonePlaceholder,
        errorText: _errorFor(widget.setup.customerPhoneError, l10n),
        filled: true,
        fillColor: kPosInnerSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          borderSide: const BorderSide(color: kPosInputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          borderSide: const BorderSide(color: kPosInputBorder),
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.setup, required this.controller});

  final OrderSetupState setup;
  final OrderSetupController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final table = setup.assignedTable;

    if (table == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WarningRow(message: l10n.posTableRequiredWarning),
          const SizedBox(height: RestoflowSpacing.sm),
          // 004: the approved amber assign-table CTA (tokens §10) — the
          // SEMANTIC WARNING family as a gradient (#C4670E→#B45309, the
          // shared warning accent), never the brand/action orange. Same key,
          // same TablePickerSheet flow, ≥44dp target.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [Color(0xFFC4670E), Color(0xFFB45309)],
              ),
              borderRadius: BorderRadius.circular(RestoflowRadii.md),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40B45309),
                  offset: Offset(0, 3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: FilledButton.icon(
              key: const Key('assign-table-button'),
              onPressed: () => TablePickerSheet.show(context),
              icon: const Icon(Icons.table_restaurant, size: 18),
              label: Text(
                l10n.posAssignTable,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                minimumSize: const Size(44, 44),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(RestoflowRadii.md),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Design-polish: the confirmed assignment reads as a SUCCESS state (true
    // green tone) rather than a generic primary tint.
    final success = RestoflowTone.success.styleOf(theme);
    return Container(
      key: const Key('assigned-table-card'),
      // Step 3: the horizontal padding gives up 8px so BOTH actions can keep a
      // real 40px touch target at the 320px compact cart without overflowing.
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
        RestoflowSpacing.xs,
        RestoflowSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: success.container,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: success.accent),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_seat,
            size: RestoflowIconSizes.md,
            color: success.onContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.posTableLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: success.onContainer,
                  ),
                ),
                Text(
                  table.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: success.onContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (table.seats != null)
                  Text(
                    l10n.posTableSeats(table.seats!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: success.onContainer,
                    ),
                  ),
              ],
            ),
          ),
          // POS-VISUAL-REDESIGN-PHASE-1-007 Step 3: the final matrix caught this
          // row overflowing by 20px in the 320px COMPACT cart (ar, assigned
          // table). The stock TextButton/IconButton paddings are what did not
          // fit; both actions are kept, both stay >=40px tall, and the label
          // ellipsises rather than forcing the row wider.
          TextButton(
            onPressed: () => TablePickerSheet.show(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.sm,
              ),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              l10n.posChangeTable,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: controller.clearTable,
            icon: const Icon(Icons.close, size: RestoflowIconSizes.md),
            tooltip: l10n.posClearTableAssignment,
            color: success.onContainer,
            // STANDARD, not compact: a compact density silently subtracts 8px
            // from the constraint below and rendered this target at 32.
            visualDensity: VisualDensity.standard,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // DESIGN-004: an AMBER "choose a table" prompt (warning tone) — a needed
    // step, not a hard error.
    final warning = RestoflowTone.warning.styleOf(theme);
    return Container(
      key: const Key('table-required-warning'),
      width: double.infinity,
      padding: const EdgeInsets.all(RestoflowSpacing.sm),
      decoration: BoxDecoration(
        color: warning.container,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: warning.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.event_seat,
            size: RestoflowIconSizes.sm,
            color: warning.onContainer,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: warning.onContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TakeawayHint extends StatelessWidget {
  const _TakeawayHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: RestoflowIconSizes.sm,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
