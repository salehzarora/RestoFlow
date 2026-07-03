import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/shift_repository.dart';
import '../format/cash_input.dart';
import '../format/money_format.dart';
import '../state/shift_close_controller.dart';

/// The POS shift close / cash reconciliation panel (RF-113).
///
/// A touch-friendly, HONEST close flow for the supervised local demo: it shows
/// the current shift, takes the counted cash, and — on close — shows the
/// SERVER-authoritative expected vs counted vs difference (real mode) or a clearly
/// labelled local computation (demo). No cash-drawer hardware is opened, no
/// printing happens, and a failure surfaces the real server reason — nothing is
/// faked. All money is integer minor units (DECISION D-007); ILS/₪ display.
class PosShiftCloseSheet extends ConsumerStatefulWidget {
  const PosShiftCloseSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const PosShiftCloseSheet(),
    );
  }

  @override
  ConsumerState<PosShiftCloseSheet> createState() => _PosShiftCloseSheetState();
}

class _PosShiftCloseSheetState extends ConsumerState<PosShiftCloseSheet> {
  final _counted = TextEditingController();
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Fresh panel each open (drop any previous result).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(shiftCloseControllerProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    super.dispose();
  }

  int? get _countedMinor => parseCashToMinor(_counted.text);

  Future<void> _submit(CurrentShiftView view) async {
    final counted = _countedMinor;
    if (counted == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.posShiftCloseConfirmTitle),
        content: Text(l10n.posShiftCloseConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.posShiftCancelAction),
          ),
          FilledButton(
            key: const Key('shift-close-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.posShiftCloseAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(shiftCloseControllerProvider.notifier)
        .close(countedMinor: counted, reason: _reason.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(currentShiftViewProvider);
    final closeState = ref.watch(shiftCloseControllerProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: RestoflowSpacing.lg,
          right: RestoflowSpacing.lg,
          top: RestoflowSpacing.md,
          bottom:
              MediaQuery.of(context).viewInsets.bottom + RestoflowSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('shift-close-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.posShiftCloseTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: RestoflowSpacing.md),
              if (closeState.value != null)
                _result(context, l10n, closeState.value!)
              else if (!view.isOpen)
                _noOpenShift(context, l10n)
              else
                _closeForm(context, l10n, view, closeState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noOpenShift(BuildContext context, AppLocalizations l10n) {
    return Column(
      key: const Key('shift-close-none'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RestoflowNoticeBanner(
          tone: RestoflowTone.info,
          icon: Icons.info_outline,
          body: l10n.posShiftNoOpenShift,
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Text(
          l10n.posShiftNoOpenShiftHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: RestoflowSpacing.lg),
        FilledButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(l10n.posShiftDoneAction),
        ),
      ],
    );
  }

  Widget _closeForm(
    BuildContext context,
    AppLocalizations l10n,
    CurrentShiftView view,
    AsyncValue<ShiftCloseOutcome?> closeState,
  ) {
    final theme = Theme.of(context);
    final currency = view.currencyCode;
    final counted = _countedMinor;
    final expected = view.expectedSoFarMinor;
    final estimatedDiff = (counted != null && expected != null)
        ? counted - expected
        : null;
    final reasonRequired = estimatedDiff != null && estimatedDiff != 0;
    final reasonMissing = reasonRequired && _reason.text.trim().isEmpty;
    final canSubmit =
        counted != null && !reasonMissing && !closeState.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.isDemo)
          Padding(
            padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
            child: RestoflowNoticeBanner(
              tone: RestoflowTone.info,
              icon: Icons.science_outlined,
              body: l10n.posShiftDemoNote,
            ),
          ),
        // Current shift state (opened time if known; opening float; estimate).
        if (view.openedAt != null)
          _row(context, l10n.posShiftOpenedAt, _hhmm(view.openedAt!)),
        _row(
          context,
          l10n.posShiftOpeningFloat,
          MoneyFormatter.formatMinor(view.openingFloatMinor, currency),
        ),
        if (expected != null)
          _row(
            context,
            l10n.posShiftExpectedCash,
            MoneyFormatter.formatMinor(expected, currency),
            strong: true,
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
            child: Text(
              l10n.posShiftExpectedAtClose,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const Divider(height: RestoflowSpacing.lg),
        // Counted cash.
        TextField(
          key: const Key('counted-cash-input'),
          controller: _counted,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.posShiftCountedLabel,
            prefixIcon: const Icon(Icons.payments_outlined),
            errorText: (_counted.text.isNotEmpty && counted == null)
                ? l10n.posShiftInvalidAmount
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        // Live difference vs the estimate.
        if (estimatedDiff != null) ...[
          const SizedBox(height: RestoflowSpacing.sm),
          _differenceLine(context, l10n, estimatedDiff, currency),
        ],
        const SizedBox(height: RestoflowSpacing.md),
        // Reason (required when there is a difference).
        TextField(
          key: const Key('shift-close-reason'),
          controller: _reason,
          decoration: InputDecoration(
            labelText: l10n.posShiftReasonLabel,
            prefixIcon: const Icon(Icons.sticky_note_2_outlined),
            errorText: reasonMissing ? l10n.posShiftReasonRequired : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (closeState.hasError) ...[
          const SizedBox(height: RestoflowSpacing.md),
          RestoflowNoticeBanner(
            key: const Key('shift-close-error'),
            tone: RestoflowTone.danger,
            icon: Icons.error_outline,
            body: _errorMessage(l10n, closeState.error),
          ),
        ],
        const SizedBox(height: RestoflowSpacing.lg),
        FilledButton.icon(
          key: const Key('shift-close-submit'),
          onPressed: canSubmit ? () => _submit(view) : null,
          icon: closeState.isLoading
              ? const RestoflowInlineSpinner(size: 18)
              : const Icon(Icons.lock_outline),
          label: Text(l10n.posShiftCloseAction),
        ),
      ],
    );
  }

  Widget _result(
    BuildContext context,
    AppLocalizations l10n,
    ShiftCloseOutcome outcome,
  ) {
    final currency = outcome.currencyCode;
    return Column(
      key: const Key('shift-close-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RestoflowNoticeBanner(
          tone: RestoflowTone.success,
          icon: Icons.check_circle_outline,
          body: l10n.posShiftClosedTitle,
        ),
        const SizedBox(height: RestoflowSpacing.md),
        _row(
          context,
          l10n.posShiftExpectedCash,
          MoneyFormatter.formatMinor(outcome.expectedMinor, currency),
        ),
        _row(
          context,
          l10n.posShiftCountedLabel,
          MoneyFormatter.formatMinor(outcome.countedMinor, currency),
        ),
        _differenceLine(context, l10n, outcome.varianceMinor, currency),
        const SizedBox(height: RestoflowSpacing.lg),
        FilledButton(
          key: const Key('shift-close-done'),
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(l10n.posShiftDoneAction),
        ),
      ],
    );
  }

  Widget _differenceLine(
    BuildContext context,
    AppLocalizations l10n,
    int varianceMinor,
    String currency,
  ) {
    final theme = Theme.of(context);
    final (label, color) = switch (varianceMinor) {
      0 => (l10n.posShiftBalanced, theme.colorScheme.onSurfaceVariant),
      > 0 => (l10n.posShiftOver, theme.colorScheme.primary),
      _ => (l10n.posShiftShort, theme.colorScheme.error),
    };
    final amount = MoneyFormatter.formatMinor(varianceMinor.abs(), currency);
    return Row(
      key: const Key('shift-close-difference'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l10n.posShiftDifference, style: theme.textTheme.titleSmall),
        Text(
          varianceMinor == 0 ? label : '$label $amount',
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool strong = false,
  }) {
    final theme = Theme.of(context);
    final style = strong
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(value, style: style),
        ],
      ),
    );
  }

  /// A locale-independent HH:mm of a local timestamp (no intl dependency).
  static String _hhmm(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _errorMessage(AppLocalizations l10n, Object? error) {
    final code = error is ShiftException ? error.code : 'rejected';
    if (code == 'unavailable') return l10n.posShiftCloseUnavailable;
    if (code == 'permission_denied') return l10n.posShiftClosePermissionDenied;
    if (code == 'not_open') return l10n.posShiftNoOpenShift;
    if (code == 'invalid_amount') return l10n.posShiftInvalidAmount;
    if (code == 'rejected_42501') return l10n.posShiftCloseServerRejected;
    return l10n.posShiftCloseFailed;
  }
}
