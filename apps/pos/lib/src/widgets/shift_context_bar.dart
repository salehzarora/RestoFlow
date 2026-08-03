import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../format/money_format.dart';
import '../pos_palette.dart';
import '../state/payment_controller.dart';

/// A slim, persistent shift / cash-drawer context bar at the top of the cart
/// panel (RF-116). DEMO shows the demo shift, drawer state, running cash and
/// last payment — clearly labelled demo. REAL mode shows the honest truth: a
/// real shift was opened on the server at PIN sign-in (RF-055 auto-open), and
/// cash totals live THERE — this bar never invents local drawer figures for a
/// real shift (the reconciliation UI is a later ticket).
class ShiftContextBar extends ConsumerWidget {
  const ShiftContextBar({this.onDark = false, super.key});

  /// POS-VISUAL-REDESIGN-PHASE-1-007 Step 2: render for the cart's dark
  /// operational block — transparent container, on-dark foregrounds, tighter
  /// vertical padding. PRESENTATION ONLY: the provider reads, the demo/real
  /// split, the `cash-in-drawer` key and the single-Text label are untouched,
  /// and the default keeps every other placement byte-identical.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    if (!isDemo) {
      return Container(
        width: double.infinity,
        color: onDark
            ? Colors.transparent
            : theme.colorScheme.surfaceContainerHigh,
        padding: onDark
            ? const EdgeInsetsDirectional.fromSTEB(
                14,
                0,
                14,
                RestoflowSpacing.sm,
              )
            : const EdgeInsetsDirectional.fromSTEB(
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
            _ShiftItem(
              icon: Icons.badge_outlined,
              label: l10n.posShiftRealName,
              strong: true,
              onDark: onDark,
            ),
            Text(
              l10n.posShiftRealNote,
              style: theme.textTheme.labelSmall?.copyWith(
                color: onDark
                    ? kPosOnDarkMuted
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

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
      color: onDark
          ? Colors.transparent
          : theme.colorScheme.surfaceContainerHigh,
      padding: onDark
          ? const EdgeInsetsDirectional.fromSTEB(14, 0, 14, RestoflowSpacing.sm)
          : const EdgeInsetsDirectional.fromSTEB(
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
          _ShiftItem(
            icon: Icons.badge_outlined,
            label: l10n.posShiftDemoName,
            onDark: onDark,
          ),
          _ShiftItem(
            icon: Icons.point_of_sale,
            label: drawerLine,
            onDark: onDark,
          ),
          // Design-polish: the figure a cashier actually checks reads at a
          // glance (larger, heavier type) instead of matching the meta rows.
          _ShiftItem(
            key: const Key('cash-in-drawer'),
            icon: Icons.account_balance_wallet_outlined,
            label: cashLine,
            strong: true,
            prominent: true,
            onDark: onDark,
          ),
          if (lastLine != null)
            _ShiftItem(
              icon: Icons.payments_outlined,
              label: lastLine,
              onDark: onDark,
            ),
          Text(
            l10n.posShiftDemoNote,
            style: theme.textTheme.labelSmall?.copyWith(
              color: onDark
                  ? kPosOnDarkMuted
                  : theme.colorScheme.onSurfaceVariant,
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
    this.prominent = false,
    this.onDark = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool strong;
  final bool onDark;

  /// Larger at-a-glance type for the figure the cashier actually reads
  /// (cash in drawer); the label stays a single Text so descendant
  /// text-equality finders keep working.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onDark
        ? (strong ? kPosOnDarkPrimary : kPosOnDarkMuted)
        : (strong
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant);
    final textStyle = prominent
        ? theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          )
        : theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: prominent ? RestoflowIconSizes.sm : RestoflowIconSizes.xs,
          color: color,
        ),
        const SizedBox(width: RestoflowSpacing.xs),
        // FINAL-NEW-MODIFICATIONS-COMBINED-001: the label MUST be flexible.
        // The enclosing Wrap offers each item the panel's width as a maximum,
        // but a Row whose Text is inflexible keeps its full intrinsic width and
        // overflows whatever it is given. The cash-in-drawer line intrinsically
        // wants ~344px, so it overflowed by ~36px in EVERY side cart narrower
        // than that — the whole tablet band (340px cart), not just 1024px, and
        // the compact-landscape cart (304px) by even more. Flexible lets the
        // label reflow inside the width the panel actually has, at every width
        // and in every locale: nothing is width-special-cased, nothing is
        // clipped, and the text is not ellipsised (it softwraps), so the figure
        // a cashier reads is never truncated. It stays ONE Text so descendant
        // text-equality finders keep working.
        Flexible(child: Text(label, style: textStyle)),
      ],
    );
  }
}
