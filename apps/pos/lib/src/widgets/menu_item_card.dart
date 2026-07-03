import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../format/money_format.dart';

/// A POS menu tile: a category-tinted icon band, the item name, a prominent
/// price, and a filled add-to-cart button. The whole tile is tappable.
///
/// Pure presentation — the add action is delegated to [onAdd]. The item name is
/// DATA (rendered via a variable) and the price is formatted integer minor-unit
/// money; only the add action's tooltip is localized chrome.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    required this.item,
    required this.onAdd,
    this.category,
    this.currencyCode = kDemoCurrencyCode,
    super.key,
  });

  final DemoMenuItem item;
  final VoidCallback onAdd;

  /// The owning category of the ACTIVE menu (real categories carry their own
  /// palette entry); null falls back to the demo lookup.
  final DemoCategory? category;

  /// The ACTIVE menu currency (ISO 4217); demo default preserved.
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final category = this.category ?? categoryById(item.categoryId);
    final priceText = MoneyFormatter.formatMinor(item.priceMinor, currencyCode);

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
              // so demo rendering is unchanged.
              child: item.imageUrl == null
                  ? _CategoryBand(category: category)
                  : Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) =>
                          _CategoryBand(category: category),
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
