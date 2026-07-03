import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// The shared empty / loading / error / denied state (design-polish sprint).
///
/// Replaces the five hand-rolled variants the audit found (AdminStateView,
/// MenuStateView, KdsStateMessage, AuthMessageView, per-screen _EmptyState
/// classes): a hero icon inside a soft tone-tinted circle (or a spinner while
/// loading), a title, an optional explanation, and recovery [actions]. Not
/// Card-based on purpose (some empty-state tests assert `find.byType(Card)`
/// findsNothing). Tone-aware: pass [RestoflowTone.danger] for failures so the
/// icon stops rendering in brand green. RTL-safe (centered Column; actions in
/// a mirroring Wrap). All strings are caller-localized.
class RestoflowStateView extends StatelessWidget {
  const RestoflowStateView({
    this.icon,
    this.title,
    this.message,
    this.tone,
    this.showSpinner = false,
    this.actions = const <Widget>[],
    this.maxWidth = RestoflowPanelWidths.statePanel,
    super.key,
  }) : assert(
         icon != null || showSpinner || title != null || message != null,
         'A state view needs an icon, a spinner, or text.',
       );

  /// Hero icon (ignored while [showSpinner] is true).
  final IconData? icon;

  /// Bold lead line.
  final String? title;

  /// Muted explanation under [title].
  final String? message;

  /// Semantic accent for the icon circle. Null => neutral surface tint with
  /// the brand primary icon (the quiet default for empty states).
  final RestoflowTone? tone;

  /// Renders a progress indicator instead of the icon circle. NOTE: several
  /// test harnesses assert exactly ONE CircularProgressIndicator per screen —
  /// don't stack a spinner state over another live spinner.
  final bool showSpinner;

  /// Recovery actions (buttons). Rendered in a Wrap; mirrors under RTL.
  final List<Widget> actions;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = tone?.styleOf(theme);
    final titleText = title;
    final messageText = message;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpinner)
                const CircularProgressIndicator()
              else if (icon != null)
                Container(
                  width: RestoflowIconSizes.hero,
                  height: RestoflowIconSizes.hero,
                  decoration: BoxDecoration(
                    color: style?.container ?? scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: RestoflowIconSizes.xl,
                    color: style?.onContainer ?? scheme.primary,
                  ),
                ),
              if (titleText != null) ...[
                const SizedBox(height: RestoflowSpacing.lg),
                Text(
                  titleText,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              if (messageText != null) ...[
                const SizedBox(height: RestoflowSpacing.sm),
                Text(
                  messageText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: RestoflowSpacing.lg),
                Wrap(
                  spacing: RestoflowSpacing.sm,
                  runSpacing: RestoflowSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A static skeleton placeholder block (loading layouts).
///
/// Deliberately NOT animated: shimmer loops never settle, and large parts of
/// the widget-test corpus drive screens with `pumpAndSettle`. A quiet muted
/// block still reads as "content loading here" without the risk.
class RestoflowSkeleton extends StatelessWidget {
  const RestoflowSkeleton({
    this.width,
    this.height = 14,
    this.radius = RestoflowRadii.sm,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
