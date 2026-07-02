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
              // RF-141D: Ink (not Container) so the InkWell tap/hover ripple
              // renders OVER the tinted band, not hidden behind an opaque layer.
              child: Ink(
                color: category.color.withValues(alpha: 0.12),
                child: Center(
                  child: Icon(category.icon, size: 40, color: category.color),
                ),
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
                  const SizedBox(height: RestoflowSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          priceText,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton.filled(
                        onPressed: onAdd,
                        tooltip: l10n.posAddToCart,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_shopping_cart, size: 20),
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
