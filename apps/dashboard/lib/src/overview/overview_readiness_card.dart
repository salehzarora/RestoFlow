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
                      color: OverviewVisuals.deep,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        ready ? Icons.check_rounded : Icons.tune_rounded,
                        color: Colors.white,
                        size: 24,
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
                            color: OverviewVisuals.deep,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          heading,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18,
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
              IconButtonTheme(
                data: IconButtonThemeData(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: OverviewVisuals.deep,
                  ),
                ),
                child: trailing!,
              ),
          ],
        ),
        const SizedBox(height: 8),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [OverviewVisuals.softMint, Color(0xFFF1FCF6)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OverviewVisuals.mint),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final wide = constraints.maxWidth >= 800 * scale;
          final statColumns = constraints.maxWidth >= 276 * scale + 24 ? 3 : 1;
          final tiles = Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final stat in stats)
                SizedBox(
                  width: wide
                      ? (constraints.maxWidth * 0.58 - 24) / 3
                      : (constraints.maxWidth - (statColumns - 1) * 12) /
                            statColumns,
                  child: _ReadinessStat(stat: stat),
                ),
            ],
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 4, child: completion),
                if (stats.isNotEmpty) ...[
                  const SizedBox(width: 24),
                  Expanded(flex: 6, child: tiles),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              completion,
              if (stats.isNotEmpty) ...[const SizedBox(height: 12), tiles],
            ],
          );
        },
      ),
    );
  }
}

class _ReadinessStat extends StatelessWidget {
  const _ReadinessStat({required this.stat});
  final RestoflowReadinessStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = stat.complete ? RestoflowTone.success : RestoflowTone.warning;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final compact = constraints.maxWidth < 150 * scale;
        final icon = Icon(
          stat.icon,
          color: tone.styleOf(theme).accent,
          size: 22,
        );
        final count = Text(
          '${stat.done}/${stat.total}',
          style: theme.textTheme.titleLarge?.copyWith(
            color: OverviewVisuals.ink,
            fontWeight: FontWeight.w800,
          ),
        );
        final text = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              stat.label,
              style: theme.textTheme.labelLarge,
              textAlign: compact ? TextAlign.center : TextAlign.start,
            ),
            const SizedBox(height: 2),
            count,
          ],
        );
        return Padding(
          padding: const EdgeInsets.all(10),
          child: compact
              ? Column(
                  children: [
                    Text(
                      stat.label,
                      style: theme.textTheme.labelLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [icon, count],
                    ),
                  ],
                )
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(child: text),
                  ],
                ),
        );
      },
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
