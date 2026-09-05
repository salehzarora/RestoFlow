import 'package:flutter/material.dart';

import '../tokens.dart';

/// The BIZBOT brand mark: a TEMPORARY typographic `B` monogram on a navy tile,
/// optionally locked up with the (caller-localized) product name and tagline.
/// Gives login, onboarding, and device pairing — the product's first
/// impressions — its identity.
///
/// BIZBOT-REBRAND: no owner-approved BIZBOT logo exists yet, so this mark is a
/// deliberately plain monogram derived from the design-system typography and
/// the frozen navy/orange palette — NOT an invented symbol. It is the same
/// glyph as the temporary launcher/PWA icons, so the tile users see in the app
/// matches the icon on their home screen. Replace this widget's tile (and the
/// icon set) with the approved asset when the owner provides a final logo.
///
/// The class keeps its historical name (`RestoflowBrandMark`) so the public
/// rebrand does not force an internal refactor across every call site
/// (public brand changes, internal symbol names retained).
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

  /// The public brand token. Always Latin uppercase, never localized or
  /// transliterated (the surrounding copy is localized instead).
  static const String brand = 'BIZBOT';

  /// The monogram glyph drawn on the tile.
  static const String monogram = 'B';

  /// The tile ground — the brand navy (matches the temporary icon set).
  static const Color tileColor = kRestoflowSeedColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = title;
    final taglineText = tagline;

    // A single Latin glyph on a navy tile. The tile is pinned to LTR so the
    // mark renders identically under RTL — a brand mark never mirrors; only
    // the surrounding text/lockup follows the ambient direction.
    final tile = Semantics(
      image: true,
      label: brand,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(RestoflowRadii.lg),
            // A hairline keeps the navy tile legible when it sits on a
            // navy/dark surface (KDS, dark rails).
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ExcludeSemantics(
            child: Text(
              monogram,
              textAlign: TextAlign.center,
              style: TextStyle(
                // ~60% of the tile: the same optical weight as the icon set.
                fontSize: size * 0.6,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: Colors.white,
                fontFamilyFallback: const <String>[
                  'Segoe UI',
                  'Tahoma',
                  'Arial',
                  'sans-serif',
                ],
              ),
            ),
          ),
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
