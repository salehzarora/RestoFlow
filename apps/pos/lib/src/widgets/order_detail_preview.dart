import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_actions.dart';
import '../data/order_preview_model.dart';
import '../data/recent_order.dart';
import '../format/money_format.dart';
import '../format/payment_method_label.dart';
import '../state/order_preview_controller.dart';
import 'order_action_row.dart';
import 'order_status_pills.dart';

/// ORDER-DETAIL-PREVIEW-001 — the READ-ONLY order detail preview.
///
/// Opened by tapping an Orders row. It renders what the server already stored —
/// the order-time item snapshots, the authoritative header totals and, when one
/// exists, the real completed payment — and it changes NOTHING by being opened,
/// scrolled, retried or closed. The only controls that can ever mutate anything
/// are the EXISTING action buttons, rendered through the shared
/// [OrderActionRow] with the SAME eligibility object and the SAME handlers the
/// Orders sheet uses.
///
/// This is NOT a receipt: it does not render printer bytes, ESC/POS output or a
/// raster preview. It is a screen for a cashier, and it stays responsive and
/// RTL-safe on a phone as well as a till.
class OrderDetailPreview extends ConsumerWidget {
  const OrderDetailPreview({
    super.key,
    required this.order,
    required this.actions,
  });

  final PosRecentOrder order;

  /// The CENTRAL policy result, resolved once by the Orders sheet and passed
  /// straight through. Eligibility is never recomputed here.
  final PosOrderActions actions;

  /// Opens the preview as a responsive modal sheet.
  static Future<void> show(
    BuildContext context, {
    required PosRecentOrder order,
    required PosOrderActions actions,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    // Capped so the sheet stays a readable column on a wide till instead of
    // stretching an order across a metre of glass.
    constraints: const BoxConstraints(maxWidth: 720),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => OrderDetailPreview(order: order, actions: actions),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(orderPreviewControllerProvider(order));

    return ConstrainedBox(
      key: const Key('order-detail-preview'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(l10n: l10n, order: order, actions: actions),
          const Divider(height: 1),
          Flexible(
            child: switch (state.phase) {
              OrderPreviewPhase.loading => _Skeleton(l10n: l10n),
              OrderPreviewPhase.failed => _Failure(l10n: l10n, order: order),
              OrderPreviewPhase.ready => _Body(
                l10n: l10n,
                model: state.model!,
                order: order,
                staleLocalCopy: state.staleLocalCopy,
              ),
            },
          ),
          // The actions stay reachable no matter how long the item list is:
          // they sit OUTSIDE the scroll area, pinned to the bottom.
          if (!actions.isEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.md),
              child: OrderActionRow(
                order: order,
                l10n: l10n,
                actions: actions,
                keyPrefix: 'preview',
                // POS-OPEN-ORDER-PAYMENT-DISMISS-019: a GENUINE payment success
                // retires this preview immediately — its [actions] were
                // resolved when the card was tapped and are stale the moment
                // the money is recorded (a still-visible "Collect payment"
                // on a paid order is a double-charge invitation). The normal
                // Navigator pop keeps the standard sheet slide-down; whether
                // the strip card then stays or goes belongs to the
                // authoritative refresh + the canonical Open predicate,
                // NEVER to this callback. Cancel/failure/refusal keep the
                // cashier here with today's error behavior.
                onPaymentSuccess: () {
                  final route = ModalRoute.of(context);
                  // Pop ONLY while this sheet still owns the top of the stack
                  // — never yank a route out from under something newer.
                  if (route != null && route.isCurrent) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          ],
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    ).withThemeGuard(theme);
  }
}

/// A tiny extension so the build reads top-down; it does nothing but return the
/// child (kept explicit rather than silently dropping the theme reference).
extension on Widget {
  Widget withThemeGuard(ThemeData _) => this;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.l10n,
    required this.order,
    required this.actions,
  });

  final AppLocalizations l10n;
  final PosRecentOrder order;
  final PosOrderActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = <String>[
      if (order.orderType case final t?)
        t == OrderType.dineIn
            ? l10n.posOrderTypeDineIn
            : l10n.posOrderTypeTakeaway,
      if (order.tableLabel case final t? when t.trim().isNotEmpty)
        '${l10n.posTableLabel} $t',
      // POS-OPEN-ORDERS-STRIP-011: the locally-known customer joins the
      // header meta (same order as the Orders-row meta line), so customer +
      // table read together at a glance. The authoritative name (incl. for
      // branch-discovered orders) still renders in the body's customer block
      // after the detail fetch — this line invents nothing.
      if (order.order?.customerName case final c? when c.trim().isNotEmpty)
        c.trim(),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RestoflowSpacing.lg,
        RestoflowSpacing.md,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.orderNumber,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('order-detail-preview-close'),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (meta.isNotEmpty)
            Text(
              meta,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: RestoflowSpacing.sm),
          Wrap(
            spacing: RestoflowSpacing.xs,
            runSpacing: RestoflowSpacing.xs,
            children: [
              // The SAME shared lifecycle + settlement vocabulary the Orders row
              // and the confirmation screen speak, including the order-type-aware
              // wording for a completed takeaway.
              OrderStatusPills(
                serverStatus: order.serverStatus,
                settlement: order.settlement,
                keySuffix: 'preview-${order.orderNumber}',
                orderType: order.orderType,
              ),
              // THIS device's queued work, reported separately from the order's
              // own lifecycle.
              if (actions.pendingKind case final p?)
                RestoflowStatusPill(
                  key: Key('preview-pending-${order.orderNumber}'),
                  label: _pendingLabel(l10n, p),
                  tone: RestoflowTone.info,
                  icon: Icons.sync,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _pendingLabel(AppLocalizations l10n, PosPendingKind k) => switch (k) {
  PosPendingKind.submit ||
  PosPendingKind.payment => l10n.posOrdersPendingPayment,
  PosPendingKind.discount => l10n.posOrdersPendingDiscount,
  PosPendingKind.cancellation => l10n.posOrdersPendingCancellation,
  PosPendingKind.itemsAdd => l10n.posAdditionPending,
};

/// A STATIC skeleton: an indeterminate spinner never settles, so a widget test
/// that pumps to settle would hang on it, and a cashier gets no more
/// information from a spinning circle than from a calm placeholder.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('order-detail-preview-loading'),
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.posOrderPreviewLoading,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          for (var i = 0; i < 3; i++) ...[
            Container(
              height: 14,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(RestoflowRadii.sm),
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _Failure extends ConsumerWidget {
  const _Failure({required this.l10n, required this.order});

  final AppLocalizations l10n;
  final PosRecentOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('order-detail-preview-error'),
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            color: RestoflowTone.danger.styleOf(theme).accent,
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Text(
            l10n.posOrderPreviewLoadFailedTitle,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          Text(
            l10n.posOrderPreviewLoadFailedBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RestoflowSpacing.md),
          FilledButton(
            key: const Key('order-detail-preview-retry'),
            // Retry re-reads the DETAIL and nothing else. It can never resend a
            // payment, a print or a status change.
            onPressed: () =>
                ref.read(orderPreviewControllerProvider(order).notifier).load(),
            child: Text(l10n.posOrderPreviewRetry),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.l10n,
    required this.model,
    required this.order,
    required this.staleLocalCopy,
  });

  final AppLocalizations l10n;
  final OrderDetailPreviewModel model;
  final PosRecentOrder order;
  final bool staleLocalCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('order-detail-preview-body'),
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      children: [
        if (staleLocalCopy) ...[
          _Notice(
            key: const Key('order-detail-preview-local-copy'),
            label: l10n.posOrderPreviewLocalCopy,
            onRetry: () =>
                ref.read(orderPreviewControllerProvider(order).notifier).load(),
            retryLabel: l10n.posOrderPreviewRetry,
          ),
          const SizedBox(height: RestoflowSpacing.md),
        ],
        if (model.hasCustomer) ...[
          _CustomerBlock(l10n: l10n, model: model),
          const SizedBox(height: RestoflowSpacing.md),
        ],
        Text(
          l10n.posOrderPreviewItems,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        for (final line in model.lines)
          _LineRow(l10n: l10n, line: line, currencyCode: model.currencyCode),
        const SizedBox(height: RestoflowSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: RestoflowSpacing.sm),
        _Totals(l10n: l10n, model: model),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.label,
    required this.onRetry,
    required this.retryLabel,
  });

  final String label;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = RestoflowTone.warning.styleOf(theme);
    return Container(
      padding: const EdgeInsets.all(RestoflowSpacing.sm),
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off,
            size: RestoflowIconSizes.sm,
            color: tone.accent,
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tone.onContainer,
              ),
            ),
          ),
          TextButton(
            key: const Key('order-detail-preview-retry'),
            onPressed: onRetry,
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}

class _CustomerBlock extends StatelessWidget {
  const _CustomerBlock({required this.l10n, required this.model});

  final AppLocalizations l10n;
  final OrderDetailPreviewModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (model.customerName case final name?)
          Text(
            '${l10n.customerNameLabel}: $name',
            key: const Key('order-detail-preview-customer'),
            style: theme.textTheme.bodyMedium,
          ),
        // Preview-only, by design: the phone is deliberately not added to the
        // Orders list, and there is no copy/export affordance for it.
        if (model.customerPhone case final phone?)
          Text(
            '${l10n.customerPhoneLabel}: $phone',
            key: const Key('order-detail-preview-customer-phone'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.l10n,
    required this.line,
    required this.currencyCode,
  });

  final AppLocalizations l10n;
  final OrderPreviewLine line;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${line.quantity} × ${line.name}',
                  // Long Arabic / Hebrew names WRAP rather than clipping.
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              if (line.lineTotalMinor case final total?)
                Text(
                  MoneyFormatter.formatMinor(total, currencyCode),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (line.unitPriceMinor case final unit?)
            Text(
              MoneyFormatter.formatMinor(unit, currencyCode),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          // PSC-001C: a line that arrived as a later ADDITION says so, using the
          // SAME localized vocabulary the KDS board uses.
          if (line.roundNumber case final round?)
            Padding(
              padding: const EdgeInsets.only(top: RestoflowSpacing.xxs),
              child: RestoflowStatusPill(
                key: Key('preview-line-round-$round-${line.name}'),
                label:
                    '${l10n.kdsAdditionLabel} · ${l10n.kdsRoundLabel(round)}',
                tone: RestoflowTone.info,
                icon: Icons.playlist_add,
              ),
            ),
          // Modifiers are indented with EdgeInsetsDirectional, so the indent
          // flips correctly in RTL instead of being faked with spaces.
          for (final modifier in line.modifiers)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: RestoflowSpacing.md,
                top: RestoflowSpacing.xxs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _modifierLabel(modifier),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (modifier.priceDeltaMinor case final delta? when delta > 0)
                    Text(
                      MoneyFormatter.formatMinor(delta, currencyCode),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          if (line.note case final note?)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: RestoflowSpacing.md,
                top: RestoflowSpacing.xxs,
              ),
              child: Text(
                '» $note',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `name ×N` when the source knows the quantity; the stored display string
  /// otherwise (a local copy already has the ×N folded in).
  static String _modifierLabel(OrderPreviewModifier modifier) {
    final quantity = modifier.quantity;
    if (quantity != null && quantity > 1) {
      return '+ ${modifier.name} ×$quantity';
    }
    return '+ ${modifier.name}';
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.l10n, required this.model});

  final AppLocalizations l10n;
  final OrderDetailPreviewModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = model.currencyCode;
    final payment = model.payment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.subtotalMinor case final subtotal?)
          _Row(
            label: l10n.posCartSubtotal,
            value: subtotal,
            currency: currency,
          ),
        if (model.discountTotalMinor case final discount? when discount > 0)
          _Row(
            label: l10n.posApplyDiscount,
            value: discount,
            currency: currency,
          ),
        if (model.taxTotalMinor case final tax? when tax > 0)
          _Row(label: l10n.posTaxLabel, value: tax, currency: currency),
        if (model.grandTotalMinor case final grand?) ...[
          const SizedBox(height: RestoflowSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.posGrandTotal,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                MoneyFormatter.formatMinor(grand, currency),
                key: const Key('order-detail-preview-total'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: RestoflowSpacing.sm),
        if (payment == null) ...[
          // UNPAID: what is still owed, and NOTHING that would imply money was
          // taken - no method, no paid amount, no tendered, no change, no
          // fabricated timestamp.
          if (model.amountDueMinor case final due?)
            Row(
              key: const Key('order-detail-preview-amount-due'),
              children: [
                Expanded(
                  child: Text(
                    l10n.posOrdersSettlementUnpaid,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: RestoflowTone.warning.styleOf(theme).accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  MoneyFormatter.formatMinor(due, currency),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ] else ...[
          Text(
            l10n.posOrdersSettlementPaid,
            key: const Key('order-detail-preview-paid'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: RestoflowTone.success.styleOf(theme).accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          _Row(
            label: l10n.posPaymentMethodLabel,
            value: payment.amountMinor,
            currency: currency,
            leadingNote: paymentMethodLabel(l10n, payment.method),
          ),
          if (payment.tenderedMinor case final tendered?)
            _Row(
              label: l10n.posReceiptPaid,
              value: tendered,
              currency: currency,
            ),
          if (payment.changeMinor case final change?)
            _Row(
              label: l10n.posReceiptChange,
              value: change,
              currency: currency,
            ),
          if (payment.receiptNumber case final receipt?)
            Text(
              '${l10n.posReceiptNumberLabel}: $receipt',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.currency,
    this.leadingNote,
  });

  final String label;
  final int value;
  final String currency;
  final String? leadingNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RestoflowSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              leadingNote == null ? label : '$label: $leadingNote',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Text(
            MoneyFormatter.formatMinor(value, currency),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
