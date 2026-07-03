import 'package:flutter/material.dart';

import '../tokens.dart';

/// A monospace code/config block (design-polish sprint): used by the
/// real-mode help pages, the one-time pairing secret, and the menu image path
/// preview. ALWAYS laid out LTR — code, env vars, and config snippets keep
/// their machine order even under ar/he (the two intentional
/// `TextDirection.ltr` overrides the RTL audit found live here now).
class RestoflowCodeBlock extends StatelessWidget {
  const RestoflowCodeBlock({required this.lines, this.trailing, super.key});

  /// The code/config lines, rendered one per row.
  final List<String> lines;

  /// Optional trailing widget (e.g. a copy button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailingWidget = trailing;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Text(
                    line,
                    // Code/config text is always LTR, even under ar/he.
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailingWidget != null) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            trailingWidget,
          ],
        ],
      ),
    );
  }
}
