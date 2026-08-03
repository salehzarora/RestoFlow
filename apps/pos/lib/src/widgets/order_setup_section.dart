import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/customer_phone.dart';
import '../data/order_submission.dart' show kCustomerNameMaxLength;
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
          // POS-ORDER-TYPE-SELECTOR-UI-001: the Material 3 SegmentedButton read
          // BACKWARDS — the unselected side carried the warm filled surface
          // while the selected side turned white and dissolved into the white
          // cart panel, with the icon on both sides and only a subtle
          // foreground-colour difference to tell them apart. The shared RF-132
          // control inverts that correctly: a solid brand-green fill with a
          // white label, heavier weight, and the icon ONLY on the active
          // option, so selection is carried by four independent signals rather
          // than colour alone. minSegmentHeight keeps the 44dp touch target the
          // old `minimumSize` provided (the control's own default is 38).
          SizedBox(
            width: double.infinity,
            child: RestoflowSegmentedControl<OrderType>(
              expand: true,
              minSegmentHeight: 44,
              segments: [
                RestoflowSegment<OrderType>(
                  key: const Key('order-type-dine-in'),
                  value: OrderType.dineIn,
                  icon: Icons.restaurant,
                  label: l10n.posOrderTypeDineIn,
                ),
                RestoflowSegment<OrderType>(
                  key: const Key('order-type-takeaway'),
                  value: OrderType.takeaway,
                  icon: Icons.takeout_dining,
                  label: l10n.posOrderTypeTakeaway,
                ),
              ],
              selected: setup.orderType,
              // Re-tapping the active option is already a no-op in the
              // controller (setOrderType returns early on an equal value), so
              // the table/name/phone state is untouched.
              onSelected: controller.setOrderType,
            ),
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
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        prefixIcon: const Icon(Icons.person_outline),
        labelText: l10n.customerNameLabel,
        hintText: l10n.customerNamePlaceholder,
        border: const OutlineInputBorder(),
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
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        prefixIcon: const Icon(Icons.phone_outlined),
        labelText: l10n.customerPhoneLabel,
        hintText: l10n.customerPhonePlaceholder,
        errorText: _errorFor(widget.setup.customerPhoneError, l10n),
        border: const OutlineInputBorder(),
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
          OutlinedButton.icon(
            key: const Key('assign-table-button'),
            onPressed: () => TablePickerSheet.show(context),
            icon: const Icon(Icons.table_restaurant),
            label: Text(l10n.posAssignTable),
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
