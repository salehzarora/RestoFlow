import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../format/money_format.dart';
import '../pos_palette.dart';

/// The band-pill display priority (menu/media sprint, Part F): the two
/// sell-with tags first. These are the FIXED wire values — an unknown tag is
/// never rendered raw (it is simply skipped).
const List<String> _kTagPillPriority = [
  'spicy',
  'popular',
  'vegetarian',
  'new',
];

/// At most this many tag pills fit tastefully on the card's image band.
const int _kMaxTagPills = 2;

/// The localized display label for a KNOWN tag wire value.
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

/// A POS menu tile (DESIGN-004 Warm/Bento): a white [Card] with a fixed 4:3
/// cover-image band (tinted category fallback on null/error), up to two tag
/// pills, an in-cart badge, the item name, an options indicator when
/// configurable, a brand-green price, and a 44px filled add button. The whole
/// tile is tappable.
///
/// Pure presentation — the add action is delegated to [onAdd]. FROZEN contracts
/// (widget-test corpus): the tile is a [Card]; tag pills are
/// [RestoflowStatusPill]; the has-options indicator is `Icons.tune` + the group
/// count; the single canonical add gesture per card is `Icons.add_shopping_cart`
/// (no `Icons.add`). The item name is DATA; the price is formatted integer
/// minor-unit money.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    required this.item,
    required this.onAdd,
    this.category,
    this.currencyCode = kDemoCurrencyCode,
    this.optionGroupCount = 0,
    this.inCartQuantity = 0,
    this.onManageAvailability,
    super.key,
  });

  final DemoMenuItem item;

  /// The add gesture. Null = adding is DISABLED (PSC-001C cart-safety: a
  /// frozen addition attempt owns the cart) — the tap gate closes and the add
  /// button renders disabled, exactly like the unavailable gate but without
  /// the sold-out/paused labeling (the cart banner explains the state).
  final VoidCallback? onAdd;

  /// PILOT-OPERATIONS-CORRECTIONS-001: a DELIBERATE (long-press) availability
  /// management action, shown ONLY to an operator with `manage_menu_availability`.
  /// Null hides it. It is INDEPENDENT of the add gate — an unavailable item (whose
  /// normal tap is disabled) can still be reopened to make it Available again.
  final VoidCallback? onManageAvailability;

  /// The owning category of the ACTIVE menu (real categories carry their own
  /// palette entry); null falls back to the demo lookup.
  final DemoCategory? category;

  /// The ACTIVE menu currency (ISO 4217); demo default preserved.
  final String currencyCode;

  /// How many modifier (option) groups the ACTIVE menu attaches to this item.
  /// 0 = plain one-tap add, no indicator.
  final int optionGroupCount;

  /// The total quantity of this item already in the cart (computed by the grid
  /// — presentation only). 0 hides the in-cart badge.
  final int inCartQuantity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final category = this.category ?? categoryById(item.categoryId);
    final priceText = MoneyFormatter.formatMinor(item.priceMinor, currencyCode);
    final bandTags = [
      for (final tag in _kTagPillPriority)
        if (item.tags.contains(tag)) tag,
    ].take(_kMaxTagPills).toList();
    // RESTAURANT-OPERATIONS-V1-001: an unavailable item stays VISIBLE (staff
    // must see WHY it cannot be sold) but takes no tap and offers no add
    // button. The server refuses the sale again at acceptance, so this gate is
    // honesty, not security.
    final unavailable = item.isUnavailable;
    // Accessibility: the unavailable state (and its reason) is announced, not just
    // shown as a colour scrim + pill (A3 — not colour alone).
    final unavailableLabel = unavailable
        ? (item.availabilityReason == 'paused'
              ? l10n.posMenuItemPaused
              : l10n.posMenuItemSoldOut)
        : null;

    return Semantics(
      container: true,
      label: unavailableLabel == null
          ? item.name
          : '${item.name}, $unavailableLabel',
      child: _buildCard(
        context,
        l10n,
        theme,
        category,
        priceText,
        bandTags,
        unavailable,
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    DemoCategory category,
    String priceText,
    List<String> bandTags,
    bool unavailable,
  ) {
    return Card(
      elevation: 1.5,
      color: theme.colorScheme.surface,
      shadowColor: const Color(0x1410201A),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        side: const BorderSide(color: kRestoflowHairline),
      ),
      child: InkWell(
        key: Key('menu-item-${item.id}'),
        onTap: unavailable ? null : onAdd,
        // Deliberate management gesture — capability-gated by the caller (null =
        // hidden). Independent of the disabled add tap, so an unavailable item can
        // still be reopened to make it Available.
        onLongPress: onManageAvailability,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The fixed 4:3 image band: cover-fit photo (with cacheWidth) that
            // never stretches, or the tinted category band on null/error.
            AspectRatio(
              aspectRatio: 4 / 3,
              child: _ImageBand(
                item: item,
                category: category,
                l10n: l10n,
                bandTags: bandTags,
                inCartQuantity: inCartQuantity,
                unavailable: unavailable,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(RestoflowSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: kRestoflowInk,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        if (optionGroupCount > 0) ...[
                          _OptionsIndicator(
                            count: optionGroupCount,
                            tooltip: l10n.menuModifierGroupCount(
                              optionGroupCount,
                            ),
                          ),
                          const SizedBox(width: RestoflowSpacing.sm),
                        ],
                        Expanded(
                          child: Text(
                            priceText,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: kRestoflowBrandDark,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!unavailable) ...[
                          const SizedBox(width: RestoflowSpacing.sm),
                          // The canonical add gesture: a 44px filled green
                          // button (disabled while the cart is locked).
                          _AddButton(onAdd: onAdd, tooltip: l10n.posAddToCart),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 4:3 band: cover photo (with a device-pixel `cacheWidth`) or the tinted
/// category fallback, overlaid by up to two tag pills (top) and an in-cart
/// badge (bottom-start).
class _ImageBand extends StatelessWidget {
  const _ImageBand({
    required this.item,
    required this.category,
    required this.l10n,
    required this.bandTags,
    required this.inCartQuantity,
    required this.unavailable,
  });

  final DemoMenuItem item;
  final DemoCategory category;
  final AppLocalizations l10n;
  final List<String> bandTags;
  final int inCartQuantity;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.imageUrl == null)
          _CategoryBand(category: category)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final dpr = MediaQuery.devicePixelRatioOf(context);
              final cacheW = (constraints.maxWidth * dpr).round();
              return Image.network(
                item.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                cacheWidth: cacheW > 0 ? cacheW : null,
                errorBuilder: (context, error, stackTrace) =>
                    _CategoryBand(category: category),
              );
            },
          ),
        if (bandTags.isNotEmpty)
          PositionedDirectional(
            top: RestoflowSpacing.sm,
            start: RestoflowSpacing.sm,
            end: RestoflowSpacing.sm,
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
        if (inCartQuantity > 0)
          PositionedDirectional(
            bottom: RestoflowSpacing.sm,
            start: RestoflowSpacing.sm,
            child: _InCartBadge(quantity: inCartQuantity),
          ),
        // RESTAURANT-OPERATIONS-V1-001: the not-sellable treatment — a dimming
        // scrim + a centred reason pill (Sold out / Temporarily unavailable).
        // Text, never colour alone.
        if (unavailable) ...[
          const ColoredBox(color: Color(0x99FFFFFF)),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.sm,
              ),
              // Scale down rather than overflow: "Temporarily unavailable" (and
              // its ar/he translations) must survive the narrowest tile.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RestoflowStatusPill(
                  key: Key('menu-item-unavailable-${item.id}'),
                  label: item.availabilityReason == 'paused'
                      ? l10n.posMenuItemPaused
                      : l10n.posMenuItemSoldOut,
                  tone: RestoflowTone.danger,
                  icon: Icons.do_not_disturb_on_outlined,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The dark in-cart badge (cart icon + ×N) on the band's bottom-start corner.
class _InCartBadge extends StatelessWidget {
  const _InCartBadge({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.sm,
        RestoflowSpacing.xxs,
        RestoflowSpacing.sm,
        RestoflowSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: kRestoflowInk,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shopping_cart,
            size: RestoflowIconSizes.xs,
            color: Colors.white,
          ),
          const SizedBox(width: RestoflowSpacing.xxs),
          Text(
            '×$quantity',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The neutral options indicator (tune icon + group count) shown when an item's
/// add opens the modifier sheet (FROZEN contract: tune icon + count + tooltip).
class _OptionsIndicator extends StatelessWidget {
  const _OptionsIndicator({required this.count, required this.tooltip});

  final int count;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RestoflowSpacing.sm,
          vertical: RestoflowSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: kPosChipBg,
          borderRadius: BorderRadius.circular(RestoflowRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune,
              size: RestoflowIconSizes.xs,
              color: kRestoflowInk2,
            ),
            const SizedBox(width: RestoflowSpacing.xxs),
            Text(
              count.toString(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: kRestoflowInk2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 44px filled brand-green add button with the green CTA glow.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onAdd, required this.tooltip});

  final VoidCallback? onAdd;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(13)),
        boxShadow: kPosGreenGlow,
      ),
      child: IconButton.filled(
        onPressed: onAdd,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(13)),
          ),
        ),
        icon: const Icon(Icons.add_shopping_cart, size: RestoflowIconSizes.md),
      ),
    );
  }
}

/// The category-tinted icon band — the imageless default AND the fallback for
/// a failed image load.
class _CategoryBand extends StatelessWidget {
  const _CategoryBand({required this.category});

  final DemoCategory category;

  @override
  Widget build(BuildContext context) {
    return Ink(
      color: category.color.withValues(alpha: 0.10),
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
