import 'package:flutter/material.dart';

import '../semantic_colors.dart';
import '../tokens.dart';

/// The RestoFlow brand mark (design-polish sprint): a rounded gradient tile
/// with the restaurant glyph, optionally locked up with the (caller-localized)
/// product name and a tagline. Gives login, onboarding, and device pairing —
/// the product's first impressions — an identity beyond a bare form.
class RestoflowBrandMark extends StatelessWidget {
  const RestoflowBrandMark({
    this.title,
    this.tagline,
    this.size = 56,
    super.key,
  });

  /// Product name next to the mark (pass the localized app name). Null renders
  /// the tile alone.
  final String? title;

  /// Muted line under [title].
  final String? tagline;

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<RestoflowSemanticColors>();
    final accent = semantic?.accent ?? theme.colorScheme.tertiary;
    final titleText = title;
    final taglineText = tagline;

    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [theme.colorScheme.primary, accent],
        ),
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
      ),
      child: Icon(
        Icons.restaurant_menu,
        size: size * 0.55,
        color: Colors.white,
      ),
    );

    if (titleText == null) return tile;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        const SizedBox(width: RestoflowSpacing.md),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titleText, style: theme.textTheme.titleLarge),
            if (taglineText != null)
              Text(
                taglineText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
