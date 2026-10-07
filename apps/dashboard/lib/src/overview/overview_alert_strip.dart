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
    final heading = title == null
        ? null
        : Text(
            title!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: semantic.onContainer,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          );
    final message = Text(
      body,
      style: theme.textTheme.bodySmall?.copyWith(
        color: semantic.onContainer,
        height: 1.3,
      ),
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: phone ? 10 : 12,
        vertical: phone ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          semantic.container.withValues(alpha: 0.06),
          Colors.white,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: semantic.accent.withValues(alpha: 0.12)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final inline =
              constraints.maxWidth >= 560 * scale ||
              (phone && scale <= 1.1 && constraints.maxWidth >= 320);
          final text = LayoutBuilder(
            builder: (context, messageConstraints) {
              if (heading == null) return message;
              if (messageConstraints.maxWidth >= 800 * scale) {
                return Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: messageConstraints.maxWidth * 0.4,
                      ),
                      child: heading,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: message),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, message],
              );
            },
          );
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon ?? semantic.icon, size: 16, color: semantic.accent),
              const SizedBox(width: 6),
              Expanded(child: text),
              if (action != null && inline) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * (phone ? 0.46 : 0.35),
                  ),
                  child: action!,
                ),
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
