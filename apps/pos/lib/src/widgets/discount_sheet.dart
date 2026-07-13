import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/discount.dart';
import '../data/discount_repository.dart';
import '../data/staff_capabilities.dart';
import '../format/cash_input.dart';
import '../format/tax_math.dart';
import '../state/cart_controller.dart';
import '../state/discount_controller.dart';

/// Modal order-level discount entry (RF-117 part C): a FIXED ₪ amount OR a
/// PERCENTAGE, plus a REQUIRED reason. On apply it pushes the SERVER-AUTHORITATIVE
/// `order.discount` op (real mode) or applies locally (demo mode) via
/// [DiscountRepository], then updates the confirmed order's total from the
/// RESULT — never a fake local total in real mode. A cashier without the
/// `apply_discount` permission sees an HONEST "ask a manager" message.
///
/// Client-side validation (before any backend call): a non-empty reason, a
/// positive value, a fixed amount that does not exceed the subtotal, and a
/// percentage of at most 100%. Money is integer minor units throughout — the
/// value is parsed via [parseCashToMinor] (₪ minor units for fixed; basis points
/// for percentage, where "17.5" → 1750 bp). No float.
class DiscountSheet extends ConsumerStatefulWidget {
  const DiscountSheet({
    required this.orderId,
    required this.subtotalMinor,
    required this.taxTotalMinor,
    required this.currencyCode,
    this.expectedRevision,
    super.key,
  });

  /// The submitted order id a real `order.discount` references (empty in demo).
  final String orderId;
  final int subtotalMinor;
  final int taxTotalMinor;
  final String currencyCode;

  /// The order revision for optimistic concurrency, or null when the client
  /// does not track it (this build does not — see the known-limitation note).
  final int? expectedRevision;

  static Future<void> show(
    BuildContext context, {
    required String orderId,
    required int subtotalMinor,
    required int taxTotalMinor,
    required String currencyCode,
    int? expectedRevision,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DiscountSheet(
      orderId: orderId,
      subtotalMinor: subtotalMinor,
      taxTotalMinor: taxTotalMinor,
      currencyCode: currencyCode,
      expectedRevision: expectedRevision,
    ),
  );

  @override
  ConsumerState<DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends ConsumerState<DiscountSheet> {
  final TextEditingController _valueController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  DiscountType _type = DiscountType.fixed;
  bool _submitting = false;

  /// The last apply failure message to show inline (permission_denied / failed),
  /// or null when there is none.
  String? _applyError;

  @override
  void dispose() {
    _valueController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  /// The parsed value in the op's unit: minor units for fixed, basis points for
  /// percentage (`parseCashToMinor` with 2 fraction digits gives both). Null on
  /// empty/malformed input.
  int? get _parsedValue =>
      parseCashToMinor(_valueController.text, fractionDigits: 2);

  /// The order total this entry WOULD leave, in integer minor units — the same
  /// arithmetic the server performs (`subtotal - discount + tax`, with the discount
  /// clamped to the subtotal). Used only to PREDICT a refusal, never to write:
  /// the applied total is always read back from the server's result.
  int _prospectiveGrandMinor(int value) {
    final raw = _type == DiscountType.fixed
        ? value
        : percentMinor(widget.subtotalMinor, value);
    final discount = raw > widget.subtotalMinor ? widget.subtotalMinor : raw;
    return widget.subtotalMinor - discount + widget.taxTotalMinor;
  }

  /// The client-side validation error key, or null when the entry is valid.
  ///
  /// [caps] are the operator's EFFECTIVE capabilities, or null when UNKNOWN. The
  /// full-comp pre-check fires ONLY when we positively know the right is absent —
  /// unknown capabilities fall through and let the SERVER decide, because blocking
  /// on a failed probe could wrongly stop a manager.
  String? _validate(AppLocalizations l10n, PosStaffCapabilities? caps) {
    final value = _parsedValue;
    if (value == null || value <= 0) return l10n.posDiscountValueInvalid;
    if (_type == DiscountType.percentage && value > 10000) {
      return l10n.posDiscountValueInvalid;
    }
    if (_type == DiscountType.fixed && value > widget.subtotalMinor) {
      return l10n.posDiscountExceedsSubtotal;
    }
    if (_reasonController.text.trim().isEmpty) {
      return l10n.posDiscountReasonRequired;
    }
    // FULL-COMP-PERMISSION-001 — predict the server's rule rather than guessing at
    // it. The refusal depends on the RESULTING TOTAL, so this checks the computed
    // total and NOT whether a "100%" preset was chosen: a FIXED amount that happens
    // to cover the order is caught by exactly the same test, which is why a
    // percentage-only client gate would have been a hole.
    if (caps != null &&
        !caps.applyFullComp &&
        _prospectiveGrandMinor(value) <= 0) {
      return l10n.posDiscountFullCompDenied;
    }
    return null;
  }

  Future<void> _apply(AppLocalizations l10n, PosStaffCapabilities? caps) async {
    final error = _validate(l10n, caps);
    if (error != null) {
      setState(() => _applyError = error);
      return;
    }
    final value = _parsedValue!;
    setState(() {
      _submitting = true;
      _applyError = null;
    });
    final navigator = Navigator.of(context);
    try {
      final result = await ref
          .read(discountRepositoryProvider)
          .applyOrderDiscount(
            orderId: widget.orderId,
            type: _type,
            value: value,
            reason: _reasonController.text.trim(),
            subtotalMinor: widget.subtotalMinor,
            taxTotalMinor: widget.taxTotalMinor,
            expectedRevision: widget.expectedRevision,
          );
      // SERVER-AUTHORITATIVE (real) / demo-local: reflect the result's discount.
      ref
          .read(cartControllerProvider.notifier)
          .applyOrderDiscount(discountTotalMinor: result.discountTotalMinor);
      navigator.pop();
    } on DiscountException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // TYPED dispatch on the server's contract — checked most-specific first,
        // because a full-comp refusal is ALSO a permission_denied and would
        // otherwise be flattened into the generic "ask a manager" message, hiding
        // the fact that ordinary discounts are still allowed.
        _applyError = switch (e) {
          DiscountException(fullCompRequired: true) =>
            l10n.posDiscountFullCompDenied,
          DiscountException(exceedsOrderTotal: true) =>
            l10n.posDiscountExceedsOrderTotal,
          DiscountException(permissionDenied: true) =>
            l10n.posDiscountPermissionDenied,
          _ => l10n.posDiscountFailed,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    // FULL-COMP-PERMISSION-001: null while loading/unknown. The discount controls
    // stay fully usable in that case — the server remains authoritative.
    final caps = ref.watch(staffCapabilitiesProvider).value;

    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.percent, color: theme.colorScheme.primary),
                const SizedBox(width: RestoflowSpacing.sm),
                Text(
                  l10n.posApplyDiscount,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            // Fixed ₪ amount vs. percentage.
            Wrap(
              spacing: RestoflowSpacing.sm,
              children: [
                ChoiceChip(
                  key: const Key('discount-type-fixed'),
                  label: Text(l10n.posDiscountFixedLabel),
                  selected: _type == DiscountType.fixed,
                  onSelected: _submitting
                      ? null
                      : (_) => setState(() {
                          _type = DiscountType.fixed;
                          _applyError = null;
                        }),
                ),
                ChoiceChip(
                  key: const Key('discount-type-percentage'),
                  label: Text(l10n.posDiscountPercentLabel),
                  selected: _type == DiscountType.percentage,
                  onSelected: _submitting
                      ? null
                      : (_) => setState(() {
                          _type = DiscountType.percentage;
                          _applyError = null;
                        }),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            TextField(
              key: const Key('discount-value-field'),
              controller: _valueController,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() => _applyError = null),
              decoration: InputDecoration(
                labelText: l10n.posDiscountValueLabel,
                suffixText: _type == DiscountType.percentage ? '%' : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            TextField(
              key: const Key('discount-reason-field'),
              controller: _reasonController,
              enabled: !_submitting,
              onChanged: (_) => setState(() => _applyError = null),
              decoration: InputDecoration(
                labelText: l10n.posDiscountReasonLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_applyError != null) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Row(
                key: const Key('discount-error'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: RestoflowIconSizes.sm,
                    color: RestoflowTone.danger.styleOf(theme).accent,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      _applyError!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: RestoflowTone.danger.styleOf(theme).accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (isDemo) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              RestoflowNoticeBanner(
                body: l10n.posDiscountDemoNote,
                tone: RestoflowTone.info,
              ),
            ],
            const SizedBox(height: RestoflowSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('discount-apply-button'),
                // NOT disabled when full-comp is denied: the cashier may still
                // apply ORDINARY discounts, and hiding the action entirely would
                // punish them for a right they never needed. The entry is judged on
                // its RESULT, at apply time.
                onPressed: _submitting ? null : () => _apply(l10n, caps),
                icon: const Icon(Icons.check),
                label: Text(l10n.posDiscountApplyAction),
                style: RestoflowButtonStyles.big(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
