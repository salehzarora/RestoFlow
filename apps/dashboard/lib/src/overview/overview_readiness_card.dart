import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import 'overview_visuals.dart';

/// Renders setup's existing answer; this widget neither reads nor calculates it.
class OverviewReadinessCard extends RestoflowReadinessStrip {
  const OverviewReadinessCard({
    required super.ready,
    required super.readyLabel,
    required super.pendingLabel,
    required super.stats,
    required super.percent,
    super.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = ready ? readyLabel : pendingLabel;
    final completion = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.topStart,
                        end: AlignmentDirectional.bottomEnd,
                        colors: [OverviewVisuals.primary, OverviewVisuals.deep],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Icon(
                        ready ? Icons.check_rounded : Icons.tune_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${percent.clamp(0, 100)}%',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontSize: 32,
                            height: 1.1,
                            color: OverviewVisuals.deep,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          heading,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            height: 1.2,
                            color: OverviewVisuals.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              SizedBox.square(
                dimension: 48,
                child: IconButtonTheme(
                  data: IconButtonThemeData(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: OverviewVisuals.deep,
                    ),
                  ),
                  child: trailing!,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percent.clamp(0, 100) / 100,
            minHeight: 4,
            color: OverviewVisuals.deep,
            backgroundColor: Colors.white,
            semanticsLabel: heading,
            semanticsValue: '${percent.clamp(0, 100)}%',
          ),
        ),
      ],
    );
    return Container(
      key: const Key('overview-readiness-card'),
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color(0xFFDCF8E8), Color(0xFFEEFBF2), Color(0xFFF6FCF5)],
        ),
        borderRadius: OverviewVisuals.radius,
        border: Border.all(color: OverviewVisuals.mint),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08047857),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final wide = constraints.maxWidth >= 800 * scale;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (stats.isNotEmpty) ...[
                  Expanded(
                    flex: 5,
                    child: _ReadinessStats(stats: stats, wide: true),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(flex: 6, child: completion),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              completion,
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ReadinessStats(stats: stats, wide: false),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Tile widths come from their own available column, including the wide layout.
/// Enlarged text uses full-width rows instead of squeezing three labels.
class _ReadinessStats extends StatelessWidget {
  const _ReadinessStats({required this.stats, required this.wide});
  final List<RestoflowReadinessStat> stats;
  final bool wide;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = wide || constraints.maxWidth >= 300 * scale
          ? stats.length.clamp(1, 3)
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final stat in stats)
            SizedBox(
              width: width,
              child: _ReadinessStat(stat: stat, inline: columns == 1),
            ),
        ],
      );
    },
  );
}

class _ReadinessStat extends StatelessWidget {
  const _ReadinessStat({required this.stat, required this.inline});
  final RestoflowReadinessStat stat;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = stat.complete ? RestoflowTone.success : RestoflowTone.warning;
    final icon = Icon(stat.icon, color: tone.styleOf(theme).accent, size: 20);
    final count = Text(
      '${stat.done}/${stat.total}',
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        height: 1.15,
        color: OverviewVisuals.ink,
        fontWeight: FontWeight.w800,
      ),
    );
    final label = Text(
      stat.label,
      style: theme.textTheme.labelLarge?.copyWith(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      textAlign: inline ? TextAlign.start : TextAlign.center,
    );
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: inline
            ? Row(
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Expanded(child: label),
                  const SizedBox(width: 8),
                  Flexible(child: count),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  label,
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [icon, count],
                  ),
                ],
              ),
      ),
    );
    return Material(
      color: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: OverviewVisuals.radius,
        side: BorderSide(color: OverviewVisuals.border),
      ),
      child: stat.onTap == null
          ? content
          : InkWell(
              key: stat.tapKey,
              onTap: stat.onTap,
              borderRadius: OverviewVisuals.radius,
              child: content,
            ),
    );
  }
}
