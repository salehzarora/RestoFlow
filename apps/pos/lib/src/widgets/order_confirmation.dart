import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../format/money_format.dart';
import '../state/submitted_order_view.dart';

/// In-place confirmation shown inside the cart panel after a local demo submit
/// (RF-101): success header, demo order number, a "Submitted" status chip, the
/// submitted item summary, the subtotal, a demo notice, and a New order action.
///
/// Pure presentation over an immutable [SubmittedOrderView]; the reset action is
/// delegated to [onNewOrder]. Nothing here calls a backend, kitchen, or printer.
class OrderConfirmation extends StatelessWidget {
  const OrderConfirmation({
    required this.order,
    required this.onNewOrder,
    super.key,
  });

  final SubmittedOrderView order;
  final VoidCallback onNewOrder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subtotalText = MoneyFormatter.format(order.subtotal);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(RestoflowSpacing.lg),
              children: [
                _SuccessHeader(title: l10n.posOrderSubmittedTitle),
                const SizedBox(height: RestoflowSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(RestoflowSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.posOrderNumberLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              order.orderNumber,
                              key: const Key('order-number'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: RestoflowSpacing.sm),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _StatusChip(
                            label: l10n.posOrderStatusSubmitted,
                          ),
                        ),
                        const SizedBox(height: RestoflowSpacing.sm),
                        _ServiceModeRow(order: order, l10n: l10n),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.md),
                for (final line in order.lines) _ConfirmationLine(line: line),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.posCartSubtotal,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      subtotalText,
                      key: const Key('confirmation-subtotal'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RestoflowSpacing.md),
                _DemoNotice(message: l10n.posDemoOrderNotice),
              ],
            ),
          ),
          Container(
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onNewOrder,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.posNewOrder),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessHeader extends StatelessWidget {
  const _SuccessHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle,
            size: 44,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The submitted order's service mode (RF-114): an order-type chip plus, for a
/// dine-in order, the assigned table chip.
class _ServiceModeRow extends StatelessWidget {
  const _ServiceModeRow({required this.order, required this.l10n});

  final SubmittedOrderView order;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final dineIn = order.orderType == OrderType.dineIn;
    final typeLabel = dineIn
        ? l10n.posOrderTypeDineIn
        : l10n.posOrderTypeTakeaway;
    final tableLabel = order.tableLabel;
    final tableChipLabel = tableLabel == null
        ? null
        : '${l10n.posTableLabel} $tableLabel';

    return Wrap(
      spacing: RestoflowSpacing.sm,
      runSpacing: RestoflowSpacing.xs,
      children: [
        _InfoChip(
          icon: dineIn ? Icons.restaurant : Icons.takeout_dining,
          label: typeLabel,
        ),
        if (tableChipLabel != null)
          _InfoChip(icon: Icons.event_seat, label: tableChipLabel),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ConfirmationLine extends StatelessWidget {
  const _ConfirmationLine({required this.line});

  final SubmittedLineView line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = '${line.quantity}× ${line.name}';
    final lineTotalText = MoneyFormatter.format(line.lineTotal);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            lineTotalText,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
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
