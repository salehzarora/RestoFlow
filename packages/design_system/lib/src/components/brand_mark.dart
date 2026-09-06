import 'package:flutter/material.dart';

import '../tokens.dart';

/// Which official wordmark artwork a [RestoflowBrandMark] lockup renders.
enum BizbotWordmark {
  /// `BIZBOT` — `BIZ` in Charcoal, `BOT` in Emerald. The default lockup: the
  /// brand token is Latin uppercase in every locale.
  latin,

  /// `بِزبط` — the approved Arabic artwork. A visual/marketing lockup only, for
  /// surfaces whose design explicitly calls for it; it never replaces the
  /// technical/public product names.
  arabic,
}

/// The BIZBOT brand mark: the OFFICIAL standalone symbol (the stylised `B`
/// with the receipt), optionally locked up with either the official wordmark
/// artwork or a caller-localized product name + tagline. Gives login,
/// onboarding, device pairing and the dashboard rail — the product's first
/// impressions — their identity.
///
/// BIZBOT OFFICIAL IDENTITY (2026-09-05): the artwork is the owner's master,
/// installed as bundled PNG derivatives by
/// `tools/brand/generate_bizbot_official_icons.py` (background removed
/// algorithmically; geometry and colours untouched). The temporary typographic
/// letter tile this widget drew during the rename is gone; nothing here draws
/// a letter.
///
/// The class keeps its historical name (`RestoflowBrandMark`) so the public
/// rebrand does not force an internal refactor across every call site
/// (public brand changes, internal symbol names retained).
class RestoflowBrandMark extends StatelessWidget {
  const RestoflowBrandMark({
    this.title,
    this.tagline,
    this.wordmark,
    this.size = 56,
    super.key,
  });

  /// Product name next to the symbol (pass the localized app name, e.g.
  /// "BIZBOT POS"). Ignored when [wordmark] is set. Null (and no [wordmark])
  /// renders the symbol alone.
  final String? title;

  /// Muted line under the title / wordmark.
  final String? tagline;

  /// Render the official wordmark artwork instead of a text title.
  final BizbotWordmark? wordmark;

  /// Symbol side in logical pixels. The wordmark scales with it.
  final double size;

  /// The public brand token. Always Latin uppercase, never localized or
  /// transliterated (the surrounding copy is localized instead).
  static const String brand = BizbotBrand.name;

  /// The package the brand assets ship in.
  static const String package = 'restoflow_design_system';

  /// Official standalone symbol — square RGBA (848x848), the final approved
  /// mark centred at native scale, transparent background.
  static const String symbolAsset = 'assets/brand/bizbot/bizbot_symbol.png';

  /// Official English wordmark — trimmed RGBA (≈5.2:1).
  static const String wordmarkLatinAsset =
      'assets/brand/bizbot/bizbot_wordmark_en.png';

  /// Official Arabic wordmark — trimmed RGBA (≈2:1).
  static const String wordmarkArabicAsset =
      'assets/brand/bizbot/bizbot_wordmark_ar.png';

  static String assetFor(BizbotWordmark wordmark) => switch (wordmark) {
    BizbotWordmark.latin => wordmarkLatinAsset,
    BizbotWordmark.arabic => wordmarkArabicAsset,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = title;
    final taglineText = tagline;
    final mark = wordmark;

    // The symbol is artwork: it is NEVER mirrored under RTL
    // (`matchTextDirection` stays false), and it carries the exact public
    // brand token as its accessible label. It sits directly on the surface —
    // no tile, no border — exactly as on the identity board.
    final symbol = Semantics(
      image: true,
      label: brand,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          symbolAsset,
          package: package,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) =>
              _SymbolFallback(size: size),
        ),
      ),
    );

    if (titleText == null && mark == null) return symbol;

    final Widget headline;
    if (mark != null) {
      // Wordmark heights are tuned to the artwork's own proportions so the
      // Latin cap height and the Arabic body sit optically level with the
      // symbol. The image is excluded from semantics: the symbol already
      // announces the brand once.
      final height = switch (mark) {
        BizbotWordmark.latin => size * 0.40,
        BizbotWordmark.arabic => size * 0.60,
      };
      headline = Image.asset(
        assetFor(mark),
        package: package,
        height: height,
        fit: BoxFit.contain,
        alignment: AlignmentDirectional.centerStart,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) => Text(
          brand,
          style: theme.textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    } else {
      headline = Text(
        titleText!,
        style: theme.textTheme.titleLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        symbol,
        const SizedBox(width: RestoflowSpacing.md),
        // Flexible + ellipsis: the lockup must degrade gracefully in narrow
        // parents (sidebar, 440px auth cards) instead of overflowing.
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headline,
              if (taglineText != null)
                Padding(
                  padding: EdgeInsets.only(
                    top: mark != null ? RestoflowSpacing.xs : 0,
                  ),
                  child: Text(
                    taglineText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Rendered only if the bundled symbol cannot be decoded (a broken build, not
/// a runtime state): a plain emerald tile with a neutral receipt glyph — never
/// a letter, never the retired artwork — so the layout keeps its footprint.
class _SymbolFallback extends StatelessWidget {
  const _SymbolFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kBizbotPrimary,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(
        Icons.receipt_long_rounded,
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }
}
