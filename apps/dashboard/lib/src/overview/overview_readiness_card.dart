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
  Widget build(BuildContext context) => Container(
    key: const Key('overview-readiness-card'),
    decoration: BoxDecoration(
      borderRadius: OverviewVisuals.radius,
      border: Border.all(color: const Color(0xFFB6E9D1)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18047857),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: OverviewVisuals.radius,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [Color(0xFFCFF2E0), Color(0xFFE5F8EE), Color(0xFFF1FCF5)],
            stops: [0, 0.55, 1],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final compact = OverviewVisuals.compactPhone(context);
            final wide = constraints.maxWidth >= 800 * scale;
            final completion = _CompletionPanel(
              ready: ready,
              heading: ready ? readyLabel : pendingLabel,
              percent: percent,
              trailing: trailing,
              wide: wide,
              compact: compact,
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (stats.isNotEmpty)
                    Expanded(
                      flex: 5,
                      child: _ReadinessStats(stats: stats, wide: true),
                    ),
                  Expanded(flex: 6, child: completion),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                completion,
                if (stats.isNotEmpty)
                  _ReadinessStats(stats: stats, wide: false, compact: compact),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _CompletionPanel extends StatelessWidget {
  const _CompletionPanel({
    required this.ready,
    required this.heading,
    required this.percent,
    required this.wide,
    this.compact = false,
    this.trailing,
  });

  final bool ready;
  final String heading;
  final int percent;
  final bool wide;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  Color(0xFF00724F),
                  Color(0xFF006B4E),
                  Color(0xFF005A43),
                ],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
        ),
        PositionedDirectional(
          end: wide ? 4 : -24,
          bottom: wide ? -20 : -36,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: Opacity(
                opacity: wide ? 0.18 : 0.12,
                child: RestoflowBrandMark(size: wide ? 184 : 156),
              ),
            ),
          ),
        ),
        if (wide)
          const PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            width: 1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0x50FFFFFF)),
              ),
            ),
          ),
        PositionedDirectional(
          start: -46,
          top: -92,
          width: 208,
          height: 208,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x18FFFFFF), width: 22),
                ),
              ),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: wide ? 136 : (compact ? 88 : 104),
          ),
          child: Padding(
            padding: EdgeInsets.all(wide ? 16 : (compact ? 8 : 12)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: wide ? 52 : (compact ? 40 : 44),
                      height: wide ? 52 : (compact ? 40 : 44),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFEDFFF6), Color(0xFFA8EBC9)],
                        ),
                        border: Border.all(color: const Color(0x99FFFFFF)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33003322),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        ready ? Icons.check_rounded : Icons.tune_rounded,
                        color: const Color(0xFF006448),
                        size: wide ? 30 : 26,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${percent.clamp(0, 100)}%',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontSize: wide ? 46 : 44,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            heading,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: wide ? 16 : 15,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFE4FFF0),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 4),
                      SizedBox.square(
                        dimension: 48,
                        child: IconButtonTheme(
                          data: IconButtonThemeData(
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: Colors.white,
                              backgroundColor: const Color(0x16FFFFFF),
                            ),
                          ),
                          child: trailing!,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: compact ? 6 : 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: percent.clamp(0, 100) / 100,
                    minHeight: 5,
                    color: const Color(0xFFB9F8D6),
                    backgroundColor: const Color(0x30FFFFFF),
                    semanticsLabel: heading,
                    semanticsValue: '${percent.clamp(0, 100)}%',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// These are the same readiness statistics and navigation targets as before;
/// their layout grows with text and uses full-width rows when space is narrow.
class _ReadinessStats extends StatelessWidget {
  const _ReadinessStats({
    required this.stats,
    required this.wide,
    this.compact = false,
  });
  final List<RestoflowReadinessStat> stats;
  final bool wide;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: wide ? 136 : 0),
    padding: EdgeInsets.all(wide ? 14 : (compact ? 6 : 10)),
    alignment: Alignment.center,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = wide || constraints.maxWidth >= 292 * scale
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
                child: _ReadinessStat(
                  stat: stat,
                  inline: columns == 1,
                  compact: compact,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _ReadinessStat extends StatelessWidget {
  const _ReadinessStat({
    required this.stat,
    required this.inline,
    required this.compact,
  });
  final RestoflowReadinessStat stat;
  final bool inline;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = stat.complete ? RestoflowTone.success : RestoflowTone.warning;
    final semantic = tone.styleOf(theme);
    final icon = Container(
      width: compact ? 26 : 30,
      height: compact ? 26 : 30,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            semantic.container,
            Color.alphaBlend(
              semantic.accent.withValues(alpha: 0.08),
              semantic.container,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: semantic.accent.withValues(alpha: 0.10)),
      ),
      child: Icon(stat.icon, color: semantic.accent, size: compact ? 18 : 19),
    );
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
    );
    final content = ConstrainedBox(
      constraints: BoxConstraints(minWidth: 48, minHeight: compact ? 56 : 64),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 6 : 8),
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
            : Row(
                children: [
                  icon,
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [label, const SizedBox(height: 3), count],
                    ),
                  ),
                ],
              ),
      ),
    );
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x20047857),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFC6E6D6)),
      ),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [Colors.white, Color(0xFFF2FAF6)],
          ),
        ),
        child: stat.onTap == null
            ? content
            : InkWell(
                key: stat.tapKey,
                onTap: stat.onTap,
                borderRadius: BorderRadius.circular(12),
                child: content,
              ),
      ),
    );
  }
}
