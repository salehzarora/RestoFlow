import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../design/pos_visual_tokens.dart' show kPosTotalsBed, kPosRowSeparator;
import '../format/money_format.dart';
import '../pos_palette.dart';
import '../state/payment_controller.dart';

/// The shift / cash-drawer context at the top of the cart panel (RF-116).
///
/// POS-DESIGN-HANDOFF-IMPLEMENTATION-004: the approved v4 presentation is a
/// COLLAPSED status pill (shift name + drawer chip + the prominent cash
/// figure + chevron) that expands in place into the context block with the
/// remaining facts (last payment + demo note). ALL previous facts stay one
/// tap away and the cash figure never leaves the collapsed row.
/// PRESENTATION ONLY: the provider reads, the demo/real split and the frozen
/// `cash-in-drawer` key (one readable Text) are untouched.
///
/// DEMO shows the demo shift; REAL mode shows the honest truth: a real shift
/// was opened on the server at PIN sign-in (RF-055 auto-open) and cash totals
/// live THERE. This bar never invents local drawer figures for a real shift.
class ShiftContextBar extends ConsumerStatefulWidget {
  const ShiftContextBar({this.onDark = false, super.key});

  /// Legacy on-dark FOREGROUNDS (kept for API compatibility; the approved v4
  /// cart header is light and the POS passes false now). NOTE: the container
  /// beds are always the light warm pill — a dark host would need its own
  /// bed treatment before flipping this back on.
  final bool onDark;

  @override
  ConsumerState<ShiftContextBar> createState() => _ShiftContextBarState();
}

class _ShiftContextBarState extends ConsumerState<ShiftContextBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;

    if (!isDemo) {
      // REAL mode: name + honest note; nothing to expand.
      return Container(
        width: double.infinity,
        margin: const EdgeInsetsDirectional.fromSTEB(12, 2, 12, 8),
        padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: kPosTotalsBed,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          border: Border.all(color: kPosRowSeparator),
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
              onDark: widget.onDark,
            ),
            Text(
              l10n.posShiftRealNote,
              style: theme.textTheme.labelSmall?.copyWith(
                color: widget.onDark
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

    final drawerStyle =
        (shift.drawerOpen ? RestoflowTone.success : RestoflowTone.neutral)
            .styleOf(theme);

    // The COLLAPSED status row; always visible, tap toggles the details.
    // Semantics: a real BUTTON with an expanded state, so a screen-reader
    // user knows more shift context is one activation away.
    final collapsed = Semantics(
      button: true,
      expanded: _expanded,
      child: InkWell(
        key: const Key('shift-context-toggle'),
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 6, 7),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: RestoflowSpacing.md,
                  runSpacing: RestoflowSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ShiftItem(
                      icon: Icons.badge_outlined,
                      label: l10n.posShiftDemoName,
                      onDark: widget.onDark,
                    ),
                    // The drawer state as a compact semantic chip.
                    Container(
                      padding: const EdgeInsetsDirectional.fromSTEB(6, 1, 6, 1),
                      decoration: BoxDecoration(
                        color: drawerStyle.container,
                        borderRadius: BorderRadius.circular(
                          RestoflowRadii.pill,
                        ),
                      ),
                      child: Text(
                        drawerLine,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: drawerStyle.onContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // The figure a cashier actually checks: prominent, ONE
                    // readable Text under its frozen key, always visible even
                    // while collapsed (approved v4 rule).
                    _ShiftItem(
                      key: const Key('cash-in-drawer'),
                      icon: Icons.account_balance_wallet_outlined,
                      label: cashLine,
                      strong: true,
                      prominent: true,
                      onDark: widget.onDark,
                    ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : RestoflowDurations.base,
                child: Icon(
                  Icons.expand_more,
                  size: RestoflowIconSizes.md,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // The EXPANDED details: the remaining facts, one tap away.
    final expandedGrid = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 10, thickness: 1, color: kPosRowSeparator),
          if (lastLine != null) ...[
            _ShiftItem(
              icon: Icons.payments_outlined,
              label: lastLine,
              onDark: widget.onDark,
            ),
            const SizedBox(height: RestoflowSpacing.xxs),
          ],
          Text(
            l10n.posShiftDemoNote,
            style: theme.textTheme.labelSmall?.copyWith(
              color: widget.onDark
                  ? kPosOnDarkMuted
                  : theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.fromSTEB(12, 2, 12, 8),
      decoration: BoxDecoration(
        color: kPosTotalsBed,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: kPosRowSeparator),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          collapsed,
          // AnimatedSize keeps the reveal finite and reduced-motion safe.
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : RestoflowDurations.base,
            curve: Curves.easeOutCubic,
            alignment: AlignmentDirectional.topCenter,
            child: _expanded
                ? expandedGrid
                : const SizedBox(width: double.infinity),
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
        : (strong ? kRestoflowInk : theme.colorScheme.onSurfaceVariant);
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
        // but a Row whose Text is inflexible keeps its full intrinsic width
        // and overflows whatever it is given. Flexible lets the label reflow
        // inside the width the panel actually has, at every width and in
        // every locale: nothing is clipped, and the text is not ellipsised
        // (it softwraps), so the figure a cashier reads is never truncated.
        // It stays ONE Text so descendant text-equality finders keep working.
        Flexible(child: Text(label, style: textStyle)),
      ],
    );
  }
}
