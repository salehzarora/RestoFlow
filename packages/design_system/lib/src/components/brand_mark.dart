import 'package:flutter/material.dart';

import '../tokens.dart';

/// The VEYRO brand mark: the approved navy+orange VEYRO symbol on a clean
/// white tile (a neutral ground that keeps the full-colour mark legible on
/// both light and dark/navy surfaces without inventing a recoloured logo),
/// optionally locked up with the (caller-localized) product name and tagline.
/// Gives login, onboarding, and device pairing — the product's first
/// impressions — its identity.
///
/// The class keeps its historical name (`RestoflowBrandMark`) so the public
/// rebrand does not force an internal refactor across every call site
/// (VEYRO-REBRAND: public brand changes, internal symbol names retained).
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

  /// The shared VEYRO mark asset (design-system-owned; one canonical copy).
  static const String markAsset = 'assets/brand/veyro_mark.png';
  static const String _package = 'restoflow_design_system';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = title;
    final taglineText = tagline;

    // The full-colour VEYRO symbol on a clean white tile. `Image` is never
    // direction-aware, so the mark does NOT mirror under RTL — only the
    // surrounding text/lockup follows the ambient direction.
    final tile = Semantics(
      image: true,
      label: 'VEYRO',
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(RestoflowRadii.lg),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: const Image(
          image: AssetImage(markAsset, package: _package),
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );

    if (titleText == null) return tile;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        const SizedBox(width: RestoflowSpacing.md),
        // Flexible + ellipsis: the lockup must degrade gracefully in narrow
        // parents (sidebar, 440px auth cards) instead of overflowing.
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleText,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (taglineText != null)
                Text(
                  taglineText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
