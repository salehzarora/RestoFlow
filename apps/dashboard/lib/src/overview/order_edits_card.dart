/// ORDER-EDIT-001G — the Overview "Order edits" card (`owner_order_edits`,
/// API_CONTRACT §4.47; MONEY_AND_TAX_SPEC §13 M13).
///
/// What an owner reads here, in order:
///   * the headline counts (edits, edited orders);
///   * the GROSS removed value, always, beside the derived net change — the net
///     figure never replaces the gross one (MONEY §12.2);
///   * the four component figures (removed, replaced before / after, added);
///   * the breakdown by reason, and by staff member when the caller may see
///     names (`staff_visible`, manager and above);
///   * the newest edits, with "Load more" following the server's keyset cursor.
///
/// Every amount is an `int` in minor units formatted by [MoneyFormatter]
/// (D-007), in the WINDOW's currency handed down by the Overview. When the
/// counted edits are in another currency, or in more than one, the card shows
/// the counts only: amounts are never relabelled or added across currencies.
/// No wire token (a reason code, a status) ever reaches the screen raw.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_currency/restoflow_currency.dart'
    show formatSignedCurrencyMinor;
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../analytics/owner_order_edits_query_key.dart';
import '../data/owner_order_edits.dart';
import '../format/money_format.dart';
import '../state/dashboard_providers.dart';
import '../state/order_edits_pages_controller.dart';
import 'overview_visuals.dart';

/// The Overview "Order edits" card for one request identity.
class OrderEditsCard extends ConsumerWidget {
  const OrderEditsCard({
    required this.queryKey,
    required this.currencyCode,
    super.key,
  });

  /// The request this card describes — the Overview's CURRENT key.
  final OwnerOrderEditsQueryKey queryKey;

  /// The WINDOW's currency (the Overview's single label authority, OPS-043).
  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(ownerOrderEditsForKeyProvider(queryKey));
    return OverviewSectionCard(
      key: const Key('order-edits-card'),
      icon: Icons.edit_note_outlined,
      title: l10n.dashboardOrderEditsTitle,
      subtitle: l10n.dashboardOrderEditsSubtitle,
      children: [
        const SizedBox(height: RestoflowSpacing.sm),
        async.when(
          loading: () => const Padding(
            key: Key('order-edits-loading'),
            padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RestoflowSkeleton(height: 18),
                SizedBox(height: RestoflowSpacing.sm),
                RestoflowSkeleton(height: 18),
              ],
            ),
          ),
          error: (_, _) => RestoflowStateView(
            key: const Key('order-edits-error'),
            icon: Icons.error_outline,
            tone: RestoflowTone.danger,
            message: l10n.dashboardReportsError,
          ),
          data: (data) => _OrderEditsBody(
            queryKey: queryKey,
            data: data,
            currencyCode: currencyCode,
          ),
        ),
      ],
    );
  }
}

class _OrderEditsBody extends ConsumerWidget {
  const _OrderEditsBody({
    required this.queryKey,
    required this.data,
    required this.currencyCode,
  });

  final OwnerOrderEditsQueryKey queryKey;
  final OwnerOrderEdits data;
  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (!data.supported) {
      return RestoflowStateView(
        key: const Key('order-edits-unavailable'),
        icon: Icons.event_busy_outlined,
        message: l10n.dashboardRangeUnavailable,
      );
    }
    if (data.isEmpty) {
      return RestoflowStateView(
        key: const Key('order-edits-empty'),
        icon: Icons.inbox_outlined,
        message: l10n.dashboardOrderEditsEmpty,
      );
    }

    final showMoney = data.moneyRenderableIn(currencyCode);
    String money(int minor) => MoneyFormatter.formatMinor(minor, currencyCode);
    // Signed and neutral: a net change is neither good nor bad news, so it is
    // never tinted. Zero is unsigned, so nothing reads "+₪0.00".
    String signed(int minor) =>
        minor == 0 ? money(0) : formatSignedCurrencyMinor(minor, currencyCode);

    final summary = data.summary;
    final pages = ref.watch(orderEditsPagesControllerProvider(queryKey));
    final rows = pages.rows;

    Widget heading(String text, String key) => Padding(
      padding: const EdgeInsets.only(
        top: RestoflowSpacing.md,
        bottom: RestoflowSpacing.xs,
      ),
      child: Text(
        text,
        key: Key(key),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    // The signed amount sits inside a sentence in the ambient direction, so it
    // is wrapped in a left-to-right isolate (LRI U+2066 … PDI U+2069): in
    // Arabic and Hebrew the sign then stays on the left of the amount, as in
    // the forced-LTR value column, instead of drifting to its right.
    String breakdownSecondary(OrderEditFigures f) => showMoney
        ? '${f.editCount} · ${l10n.dashboardOrderEditsEditCount} · '
              '${l10n.dashboardOrderEditsNetChange} '
              '\u2066${signed(f.netChangeMinor)}\u2069'
        : '${f.editCount} · ${l10n.dashboardOrderEditsEditCount}';

    return Column(
      key: const Key('order-edits-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FigureRow(
          key: const Key('order-edits-edit-count'),
          label: l10n.dashboardOrderEditsEditCount,
          value: '${summary.editCount}',
        ),
        _FigureRow(
          key: const Key('order-edits-edited-orders'),
          label: l10n.dashboardOrderEditsEditedOrders,
          value: '${summary.editedOrderCount}',
        ),
        if (showMoney) ...[
          _FigureRow(
            key: const Key('order-edits-gross'),
            label: l10n.dashboardOrderEditsGrossRemoved,
            value: money(summary.grossRetiredMinor),
            emphasis: true,
          ),
          _FigureRow(
            key: const Key('order-edits-net'),
            label: l10n.dashboardOrderEditsNetChange,
            value: signed(summary.netChangeMinor),
            emphasis: true,
          ),
          _FigureRow(
            key: const Key('order-edits-removed'),
            label: l10n.dashboardOrderEditsRemoved,
            value: money(summary.removedMinor),
          ),
          _FigureRow(
            key: const Key('order-edits-replaced-out'),
            label: l10n.dashboardOrderEditsReplacedOut,
            value: money(summary.replacedOutMinor),
          ),
          _FigureRow(
            key: const Key('order-edits-replaced-in'),
            label: l10n.dashboardOrderEditsReplacedIn,
            value: money(summary.replacedInMinor),
          ),
          _FigureRow(
            key: const Key('order-edits-added'),
            label: l10n.dashboardOrderEditsAdded,
            value: money(summary.addedMinor),
          ),
        ] else
          Padding(
            key: const Key('order-edits-currency-mixed'),
            padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: RestoflowSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.dashboardCurrencyMixedTitle,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (data.byReason.isNotEmpty) ...[
          heading(l10n.dashboardOrderEditsByReason, 'order-edits-by-reason'),
          for (final r in data.byReason)
            _FigureRow(
              key: Key('order-edits-reason-${r.reasonCode ?? 'none'}'),
              // A null reason is the add-only bucket: edits that only added
              // items or raised a quantity, which need no reason.
              label:
                  orderEditReasonLabel(l10n, r.reasonCode) ??
                  l10n.dashboardOrderEditsAdded,
              secondary: breakdownSecondary(r.figures),
              value: showMoney
                  ? money(r.figures.grossRetiredMinor)
                  : '${r.figures.editCount}',
            ),
        ],
        if (data.staffVisible && data.byStaff.isNotEmpty) ...[
          heading(l10n.dashboardOrderEditsByStaff, 'order-edits-by-staff'),
          for (var i = 0; i < data.byStaff.length; i++)
            _FigureRow(
              key: Key('order-edits-staff-$i'),
              label: data.byStaff[i].staffName ?? '—',
              secondary: breakdownSecondary(data.byStaff[i].figures),
              value: showMoney
                  ? money(data.byStaff[i].figures.grossRetiredMinor)
                  : '${data.byStaff[i].figures.editCount}',
            ),
        ],
        if (rows.isNotEmpty) ...[
          heading(l10n.ordersEditTimelineTitle, 'order-edits-latest'),
          for (final row in rows)
            _FigureRow(
              key: Key('order-edits-row-${row.orderEditId}'),
              label:
                  '${row.orderCode} · ${l10n.kitchenEditChangeNumber(row.editNumber)}',
              secondary: [
                row.createdAtLabel,
                ?orderEditReasonLabel(l10n, row.reasonCode),
                if (data.staffVisible) ?row.staffName,
                if (row.orderVoided) l10n.ordersStatusVoided,
              ].where((s) => s.isNotEmpty).join(' · '),
              value: showMoney ? signed(row.figures.netChangeMinor) : null,
            ),
          Padding(
            padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
            child: Text(
              l10n.adminShowingRange(1, rows.length, data.matching),
              key: const Key('order-edits-showing'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (pages.loadMoreFailed)
            Text(
              l10n.dashboardReportsError,
              key: const Key('order-edits-load-more-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          if (pages.hasMore)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('order-edits-load-more'),
                onPressed: pages.loadingMore
                    ? null
                    : () => ref
                          .read(
                            orderEditsPagesControllerProvider(
                              queryKey,
                            ).notifier,
                          )
                          .loadMore(),
                child: Text(l10n.ordersLoadMore),
              ),
            ),
        ],
      ],
    );
  }
}

/// One labelled figure: the label (and an optional muted second line) at the
/// start, the value at the end. Stacks on narrow widths through
/// [OverviewValueRow], so nothing overflows at 390px or at 2x text.
class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.label,
    this.value,
    this.secondary,
    this.emphasis = false,
    super.key,
  });

  final String label;
  final String? value;
  final String? secondary;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value;
    final labelColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: emphasis
              ? theme.textTheme.titleSmall
              : theme.textTheme.bodyMedium,
        ),
        if (secondary != null && secondary!.isNotEmpty)
          Text(
            secondary!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OverviewVisuals.border),
      ),
      child: text == null
          ? labelColumn
          : OverviewValueRow(
              label: labelColumn,
              value: Text(
                text,
                // Amounts and counts read left-to-right in every locale, so a
                // signed figure never shows its minus at the wrong end in RTL.
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.end,
                style:
                    (emphasis
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
              ),
            ),
    );
  }
}
