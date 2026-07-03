import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../format/money_format.dart';

/// The band-pill display priority (menu/media sprint, Part F): the two
/// sell-with tags first. These are the FIXED wire values — an unknown tag is
/// never rendered raw (it is simply skipped).
const List<String> _kTagPillPriority = [
  'spicy',
  'popular',
  'vegetarian',
  'new',
];

/// At most this many tag pills fit tastefully on a 188px tile's band.
const int _kMaxTagPills = 2;

/// The localized display label for a KNOWN tag wire value. Callers iterate
/// [_kTagPillPriority], so the verbatim arm is unreachable — it exists only
/// for switch exhaustiveness.
String _tagLabel(AppLocalizations l10n, String tag) => switch (tag) {
  'spicy' => l10n.menuTagSpicy,
  'popular' => l10n.menuTagPopular,
  'vegetarian' => l10n.menuTagVegetarian,
  'new' => l10n.menuTagNew,
  _ => tag,
};

/// The semantic tone for a tag pill — mirrors the dashboard catalog mapping
/// (spicy reads hot, vegetarian reads healthy, popular/new are accents).
RestoflowTone _tagTone(String tag) => switch (tag) {
  'spicy' => RestoflowTone.danger,
  'vegetarian' => RestoflowTone.success,
  'popular' => RestoflowTone.info,
  'new' => RestoflowTone.info,
  _ => RestoflowTone.neutral,
};

/// A POS menu tile: a category-tinted icon band, the item name, a prominent
/// price, and a filled add-to-cart button. The whole tile is tappable.
///
/// Pure presentation — the add action is delegated to [onAdd]. The item name is
/// DATA (rendered via a variable) and the price is formatted integer minor-unit
/// money; only the add action's tooltip is localized chrome. Part F: up to two
/// localized tag pills overlay the band, and a compact tune-icon indicator by
/// the price marks items whose add opens the options sheet.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    required this.item,
    required this.onAdd,
    this.category,
    this.currencyCode = kDemoCurrencyCode,
    this.optionGroupCount = 0,
    super.key,
  });

  final DemoMenuItem item;
  final VoidCallback onAdd;

  /// The owning category of the ACTIVE menu (real categories carry their own
  /// palette entry); null falls back to the demo lookup.
  final DemoCategory? category;

  /// The ACTIVE menu currency (ISO 4217); demo default preserved.
  final String currencyCode;

  /// How many modifier (option) groups the ACTIVE menu attaches to this item
  /// (the grid already computes them to pick the add path). 0 = plain one-tap
  /// add, no indicator.
  final int optionGroupCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final category = this.category ?? categoryById(item.categoryId);
    final priceText = MoneyFormatter.formatMinor(item.priceMinor, currencyCode);
    // Up to two KNOWN tags, spicy/popular first; localized labels only.
    final bandTags = [
      for (final tag in _kTagPillPriority)
        if (item.tags.contains(tag)) tag,
    ].take(_kMaxTagPills).toList();

    return Card(
      child: InkWell(
        onTap: onAdd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // Menu/media sprint: when the real menu resolved a signed image
              // URL, the band renders the product photo (cover-fit, layout
              // neutral — same Expanded slot); ANY load failure falls back to
              // the tinted category-icon band below. Demo items carry no URL,
              // so demo rendering is unchanged. Tag pills overlay the band
              // (image or icon) without spending tile height.
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.imageUrl == null)
                    _CategoryBand(category: category)
                  else
                    Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) =>
                          _CategoryBand(category: category),
                    ),
                  if (bandTags.isNotEmpty)
                    PositionedDirectional(
                      top: RestoflowSpacing.xs,
                      start: RestoflowSpacing.xs,
                      end: RestoflowSpacing.xs,
                      child: Wrap(
                        spacing: RestoflowSpacing.xs,
                        runSpacing: RestoflowSpacing.xs,
                        children: [
                          for (final tag in bandTags)
                            RestoflowStatusPill(
                              label: _tagLabel(l10n, tag),
                              tone: _tagTone(tag),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: RestoflowSpacing.xxs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          priceText,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (optionGroupCount > 0) ...[
                        const SizedBox(width: RestoflowSpacing.xs),
                        // Has-options indicator: this add opens the option
                        // sheet. NOT Icons.add / a second add_shopping_cart —
                        // both are load-bearing test gestures.
                        Tooltip(
                          message: l10n.menuModifierGroupCount(
                            optionGroupCount,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune,
                                size: RestoflowIconSizes.sm,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: RestoflowSpacing.xxs),
                              Text(
                                optionGroupCount.toString(),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(width: RestoflowSpacing.xs),
                      // The cashier's main affordance: a >=48dp filled add
                      // button (the icon is the canonical add gesture in the
                      // widget-test corpus — never change it).
                      IconButton.filled(
                        onPressed: onAdd,
                        tooltip: l10n.posAddToCart,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: const Icon(
                          Icons.add_shopping_cart,
                          size: RestoflowIconSizes.md,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The category-tinted icon band — the imageless default AND the fallback for
/// a failed image load.
///
/// RF-141D: Ink (not Container) so the InkWell tap/hover ripple renders OVER
/// the tinted band, not hidden behind an opaque layer. Design-polish: a subtler
/// tint + smaller glyph so the band reads as category colour-coding, not the
/// tile's main content.
class _CategoryBand extends StatelessWidget {
  const _CategoryBand({required this.category});

  final DemoCategory category;

  @override
  Widget build(BuildContext context) {
    return Ink(
      color: category.color.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          category.icon,
          size: RestoflowIconSizes.xl,
          color: category.color.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
