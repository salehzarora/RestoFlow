import 'package:flutter/material.dart';

import '../semantic_colors.dart';
import '../tokens.dart';

/// One step in a guided checklist (design-polish sprint): a numbered circle
/// that turns into a green check when [done], a title, an optional
/// description, and an optional trailing [action].
///
/// Used by the dashboard setup checklist and the device "no staff PINs yet"
/// guidance. RTL-safe (Row mirrors; directional padding only). All strings
/// are caller-localized.
class RestoflowStepTile extends StatelessWidget {
  const RestoflowStepTile({
    required this.index,
    required this.title,
    this.description,
    this.action,
    this.done = false,
    super.key,
  });

  /// 1-based step number shown while not [done].
  final int index;

  final String title;
  final String? description;

  /// Optional trailing action (e.g. a button that jumps to the fixing tab).
  final Widget? action;

  /// Completed steps render a success check instead of the number.
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<RestoflowSemanticColors>();
    final successBg = semantic?.successContainer ?? scheme.secondaryContainer;
    final successFg =
        semantic?.onSuccessContainer ?? scheme.onSecondaryContainer;
    final descriptionText = description;
    final trailing = action;

    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: RestoflowSpacing.sm,
        bottom: RestoflowSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: done ? successBg : scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: done
                ? Icon(
                    Icons.check,
                    size: RestoflowIconSizes.sm,
                    color: successFg,
                  )
                : Text('$index', style: theme.textTheme.labelLarge),
          ),
          const SizedBox(width: RestoflowSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? scheme.onSurfaceVariant : null,
                  ),
                ),
                if (descriptionText != null) ...[
                  const SizedBox(height: RestoflowSpacing.xxs),
                  Text(
                    descriptionText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            trailing,
          ],
        ],
      ),
    );
  }
}
