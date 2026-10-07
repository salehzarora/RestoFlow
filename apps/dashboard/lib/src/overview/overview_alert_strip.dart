import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import 'overview_visuals.dart';

/// Dashboard-only notice chrome. Conditions, text and actions belong to callers.
/// This component owns no setup state or disclosure behavior.
class OverviewAlertStrip extends RestoflowNoticeBanner {
  const OverviewAlertStrip({
    required super.body,
    super.title,
    super.tone,
    super.icon,
    super.action,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = tone.styleOf(theme);
    final phone = OverviewVisuals.isPhone(context);
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Text(
            title!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: semantic.onContainer,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        Text(
          body,
          style: theme.textTheme.bodySmall?.copyWith(
            color: semantic.onContainer,
            height: 1.35,
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      constraints: phone ? const BoxConstraints(minHeight: 48) : null,
      padding: EdgeInsets.symmetric(
        horizontal: phone ? 10 : 12,
        vertical: phone ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          semantic.container.withValues(alpha: 0.16),
          Colors.white,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: semantic.accent.withValues(alpha: 0.12)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final inline = constraints.maxWidth >= 560 * scale;
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon ?? semantic.icon, size: 18, color: semantic.accent),
              const SizedBox(width: 8),
              Expanded(child: text),
              if (action != null && inline) ...[
                const SizedBox(width: 12),
                action!,
              ],
            ],
          );
          if (action == null || inline) return content;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              const SizedBox(height: 4),
              Align(alignment: AlignmentDirectional.centerEnd, child: action!),
            ],
          );
        },
      ),
    );
  }
}
