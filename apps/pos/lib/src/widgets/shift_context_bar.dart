import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../format/money_format.dart';
import '../state/payment_controller.dart';

/// A slim, persistent shift / cash-drawer context bar at the top of the cart
/// panel (RF-116). Shows the demo shift, the drawer state, the running cash in
/// the drawer, and the last cash payment — updating after each cash payment.
/// Clearly labelled demo (not synced). Reads [paymentControllerProvider].
class ShiftContextBar extends ConsumerWidget {
  const ShiftContextBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shift = ref.watch(paymentControllerProvider.select((s) => s.shift));
    final currency = shift.currencyCode;

    final drawerLine =
        '${l10n.posDrawerLabel}: '
        '${shift.drawerOpen ? l10n.posDrawerOpen : l10n.posDrawerClosed}';
    final cashLine =
        '${l10n.posCashInDrawer}: '
        '${MoneyFormatter.formatMinor(shift.cashInDrawerMinor, currency)}';
    final lastLine = shift.lastPaymentMinor == null
        ? null
        : '${l10n.posLastCashPayment}: '
              '${MoneyFormatter.formatMinor(shift.lastPaymentMinor!, currency)}';

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
      ),
      child: Wrap(
        spacing: RestoflowSpacing.md,
        runSpacing: RestoflowSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ShiftItem(icon: Icons.badge_outlined, label: l10n.posShiftDemoName),
          _ShiftItem(icon: Icons.point_of_sale, label: drawerLine),
          _ShiftItem(
            key: const Key('cash-in-drawer'),
            icon: Icons.account_balance_wallet_outlined,
            label: cashLine,
            strong: true,
          ),
          if (lastLine != null)
            _ShiftItem(icon: Icons.payments_outlined, label: lastLine),
          Text(
            l10n.posShiftDemoNote,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftItem extends StatelessWidget {
  const _ShiftItem({
    required this.icon,
    required this.label,
    this.strong = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = strong
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: RestoflowSpacing.xs),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
