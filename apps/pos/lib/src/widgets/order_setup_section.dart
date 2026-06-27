import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RestoflowSpacing.lg,
        RestoflowSpacing.md,
        RestoflowSpacing.lg,
        RestoflowSpacing.md,
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
          const SizedBox(height: RestoflowSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<OrderType>(
              segments: [
                ButtonSegment<OrderType>(
                  value: OrderType.dineIn,
                  icon: const Icon(Icons.restaurant),
                  label: Text(l10n.posOrderTypeDineIn),
                ),
                ButtonSegment<OrderType>(
                  value: OrderType.takeaway,
                  icon: const Icon(Icons.takeout_dining),
                  label: Text(l10n.posOrderTypeTakeaway),
                ),
              ],
              selected: {setup.orderType},
              onSelectionChanged: (selection) =>
                  controller.setOrderType(selection.first),
            ),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          if (setup.orderType == OrderType.dineIn)
            _TableRow(setup: setup, controller: controller)
          else
            _TakeawayHint(message: l10n.posTableNotNeeded),
        ],
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

    return Container(
      key: const Key('assigned-table-card'),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: theme.colorScheme.primary),
      ),
      child: Row(
        children: [
          Icon(Icons.event_seat, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.posTableLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  table.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (table.seats != null)
                  Text(
                    l10n.posTableSeats(table.seats!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => TablePickerSheet.show(context),
            child: Text(l10n.posChangeTable),
          ),
          IconButton(
            onPressed: controller.clearTable,
            icon: const Icon(Icons.close),
            tooltip: l10n.posClearTableAssignment,
            color: theme.colorScheme.onPrimaryContainer,
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
    return Row(
      key: const Key('table-required-warning'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
