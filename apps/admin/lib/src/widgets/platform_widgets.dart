import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import '../data/platform_overview.dart';

/// A KPI metric tile: a small label, a prominent value, and an optional caption.
/// Pure presentation — [value]/[caption] are pre-built data strings; [label] is
/// localized chrome. (Admin-local mirror of the dashboard MetricCard.)
class PlatformMetricCard extends StatelessWidget {
  const PlatformMetricCard({
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: RestoflowSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (caption != null) ...[
              const SizedBox(height: RestoflowSpacing.xs),
              Text(
                caption!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A titled section card holding a vertical list of rows (organizations / branch
/// health / recent activity).
class PlatformSectionCard extends StatelessWidget {
  const PlatformSectionCard({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            const Divider(height: 1),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A leading-label / trailing-value row for a [PlatformSectionCard]. [label] and
/// [trailingValue] are pre-built data strings; [secondary] is an optional muted
/// sub-line; [trailing] is an optional widget (e.g. a warning chip) shown after
/// the value.
class PlatformSectionRow extends StatelessWidget {
  const PlatformSectionRow({
    required this.label,
    this.trailingValue,
    this.secondary,
    this.trailing,
    super.key,
  });

  final String label;
  final String? trailingValue;
  final String? secondary;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (secondary != null)
                  Text(
                    secondary!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailingValue != null) ...[
            const SizedBox(width: RestoflowSpacing.md),
            Text(
              trailingValue!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A small rounded status pill. [tone] tints it: [PillTone.neutral] for ordinary
/// status, [PillTone.warning] for items that need attention.
enum PillTone { neutral, warning }

class PlatformStatusPill extends StatelessWidget {
  const PlatformStatusPill({
    required this.label,
    this.tone = PillTone.neutral,
    super.key,
  });

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warn = tone == PillTone.warning;
    final bg = warn ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final fg = warn ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The visual tone of a [PlatformNoticeBanner].
enum NoticeTone {
  /// The demo-data notice (informational).
  info,

  /// The real-mode "live but limited" notice (cautionary, read-only/limited).
  caution,
}

/// A full-width notice banner that keeps the platform overview honest about its
/// data source: an [NoticeTone.info] tone for the demo-data notice (RF-120) and
/// an [NoticeTone.caution] tone for the real-mode "live but limited" notice
/// (RF-134). Pure presentation — [message] is localized chrome.
class PlatformNoticeBanner extends StatelessWidget {
  const PlatformNoticeBanner({
    required this.message,
    this.tone = NoticeTone.info,
    super.key,
  });

  final String message;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caution = tone == NoticeTone.caution;
    final bg = caution ? scheme.secondaryContainer : scheme.tertiaryContainer;
    final fg = caution
        ? scheme.onSecondaryContainer
        : scheme.onTertiaryContainer;
    final icon = caution ? Icons.warning_amber_outlined : Icons.info_outline;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// One recent-activity row: an action chip + the readable summary on the first
/// line, with the timestamp muted beneath.
class PlatformActivityTile extends StatelessWidget {
  const PlatformActivityTile({required this.event, super.key});

  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = event.isWarning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlatformStatusPill(
                label: event.action,
                tone: warn ? PillTone.warning : PillTone.neutral,
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Text(
                  event.summary,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          Text(
            event.timestampLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
