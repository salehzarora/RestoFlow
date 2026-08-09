/// DASHBOARD-VISUAL-RANGE-REFRESH-F2 — the custom From/To sheet.
///
/// Everything here operates on the DRAFT. Nothing in this file writes the
/// committed window except [_apply], and nothing issues a request: picking a
/// From date has to be free, or the Dashboard would reload on every tap while
/// the owner is still deciding.
///
/// NO ENGLISH LITERALS REACH THE PLATFORM PICKER. `showDateRangePicker` takes a
/// dozen label overrides (`helpText`, `saveText`, `confirmText`, …) that the
/// repo's hardcoded-string guard does not scan, so passing "Save" here would
/// ship untranslated into an Arabic RTL sheet and CI would stay green. They are
/// all left unset, which makes Flutter use MaterialLocalizations for the active
/// locale — already wired, already translated, and impossible to forget to
/// update later.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/dashboard_providers.dart';
import 'analytics_window.dart';
import 'custom_range_draft.dart';

/// Opens the custom-range sheet, seeded from the last valid selection.
///
/// Returns the committed window when Apply was pressed, or null for Cancel /
/// dismiss — so a caller can tell "the owner chose" from "the owner backed out".
Future<CustomAnalyticsWindow?> showCustomRangeSheet(
  BuildContext context,
  WidgetRef ref, {
  DateTime Function()? clock,
}) {
  // SEEDING, in order: the window currently committed, else the last one
  // committed this session, else empty. Reopening after a detour through a
  // preset therefore offers the dates the owner last chose instead of a blank
  // sheet, without that memory ever being part of a query key.
  final seed =
      ref.read(customAnalyticsWindowProvider) ??
      ref.read(lastCustomAnalyticsWindowProvider);
  ref.read(customRangeDraftProvider.notifier).state = seed == null
      ? CustomRangeDraft.empty
      : CustomRangeDraft.fromWindow(seed);

  return showDialog<CustomAnalyticsWindow>(
    context: context,
    builder: (_) => _CustomRangeDialog(clock: clock ?? DateTime.now),
  );
}

class _CustomRangeDialog extends ConsumerWidget {
  const _CustomRangeDialog({required this.clock});

  final DateTime Function() clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final draft = ref.watch(customRangeDraftProvider);
    final error = draft.error;
    // Apply is gated on the DOMAIN's answer, not on a second opinion: if
    // CustomAnalyticsWindow refuses to build it, the button stays disabled.
    final canApply = draft.isValid;

    String formatted(DateTime? d) =>
        d == null ? '—' : material.formatShortDate(d);

    return AlertDialog(
      key: const Key('custom-range-dialog'),
      title: Text(l10n.dashboardRangeCustomTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Bound(
                  label: l10n.dashboardRangeCustomFrom,
                  value: formatted(draft.startDay),
                  valueKey: const Key('custom-range-from'),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: _Bound(
                  label: l10n.dashboardRangeCustomTo,
                  value: formatted(draft.endDay),
                  valueKey: const Key('custom-range-to'),
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.md),
          OutlinedButton.icon(
            key: const Key('custom-range-choose'),
            onPressed: () => _pick(context, ref, draft),
            icon: const Icon(Icons.date_range),
            label: Text(l10n.dashboardRangeCustomChoose),
          ),
          if (error != null) ...[
            const SizedBox(height: RestoflowSpacing.md),
            Text(
              key: const Key('custom-range-error'),
              switch (error) {
                CustomRangeDraftError.incomplete =>
                  l10n.dashboardRangeCustomEmpty,
                CustomRangeDraftError.reversed =>
                  l10n.dashboardRangeCustomReversed,
                CustomRangeDraftError.tooLong =>
                  l10n.dashboardRangeCustomTooLong(kMaxCustomWindowDays),
              },
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color:
                    (Theme.of(context).extension<RestoflowSemanticColors>() ??
                            RestoflowSemanticColors.of(
                              Theme.of(context).brightness,
                            ))
                        .danger,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('custom-range-clear'),
          // CLEARS THE DRAFT ONLY. It does not fall back to Today — tapping
          // Clear is "let me re-pick", not "abandon my range", and the committed
          // window keeps showing until Apply or Cancel decides its fate.
          onPressed: draft.isEmpty
              ? null
              : () => ref.read(customRangeDraftProvider.notifier).state =
                    CustomRangeDraft.empty,
          child: Text(l10n.dashboardRangeCustomClear),
        ),
        TextButton(
          key: const Key('custom-range-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.dashboardRangeCustomCancel),
        ),
        FilledButton(
          key: const Key('custom-range-apply'),
          onPressed: canApply ? () => _apply(context, ref, draft) : null,
          child: Text(l10n.dashboardRangeCustomApply),
        ),
      ],
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    CustomRangeDraft draft,
  ) async {
    final today = CustomAnalyticsWindow.normalizeDay(clock());
    final initial = draft.window;
    final picked = await showDateRangePicker(
      context: context,
      // A generous lower bound: the server imposes none, and pinning it to the
      // last N days would tell the owner history they do have is unavailable.
      firstDate: DateTime.utc(2020),
      // No future: there is nothing to report there.
      lastDate: today,
      initialDateRange: initial == null
          ? null
          : DateTimeRange(start: initial.startDay, end: initial.endDay),
      // Every label is intentionally left to MaterialLocalizations — see the
      // library comment.
    );
    if (picked == null) return;
    // The platform picker enforces firstDate/lastDate but NOT our 92-day span,
    // so an over-long selection is accepted here and then REFUSED by the draft,
    // with the reason shown. Silently trimming it to 92 days would answer a
    // question the owner did not ask.
    ref.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
      startDay: picked.start,
      endDay: picked.end,
    );
  }

  void _apply(BuildContext context, WidgetRef ref, CustomRangeDraft draft) {
    final window = draft.window;
    if (window == null) return;
    final navigator = Navigator.of(context);
    commitCustomAnalyticsWindow(ref, window);
    navigator.pop(window);
  }
}

class _Bound extends StatelessWidget {
  const _Bound({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: kRestoflowInk3),
        ),
        const SizedBox(height: RestoflowSpacing.xxs),
        Text(value, key: valueKey, style: theme.textTheme.titleSmall),
      ],
    );
  }
}
