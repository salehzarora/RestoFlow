import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../design/pos_motion.dart';
import '../design/pos_visual_tokens.dart';
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
    this.interactionAccent,
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

  /// POS-PREMIUM-VISUAL-POLISH-001: this terminal's secondary accent for the
  /// add button's hover wash / pressed wash / focus ring (non-critical
  /// highlights by contract). Null falls back to the shared brand accent, so
  /// existing call sites render exactly as before.
  final Color? interactionAccent;

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
    // MONEY-LOCAL-ATOMICITY-003A: a THIRD reason. `sold_out` / `paused` are
    // operator stock decisions; `configuration_unreadable` means the POS could
    // not read the item's modifier configuration and so cannot price it — a
    // different fact, which must not be reported as "Sold out".
    final unavailableLabel = unavailable
        ? _unavailableLabel(l10n, item.availabilityReason)
        : null;
    // POS-PRODUCT-DESCRIPTIONS-001: the operator's description, already
    // normalized at the parse boundary. Re-checked for blankness here only so a
    // caller that hands the card raw text cannot produce an empty line — this
    // is a guard, not a second normalization.
    final description = item.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;

    return Semantics(
      container: true,
      // ONE semantic node for the card, extended in reading order: product
      // name, then its description, then the availability status. A second
      // node here would make every tile announce itself twice.
      label: [
        item.name,
        if (hasDescription) description,
        if (unavailableLabel != null) unavailableLabel,
      ].join(', '),
      child: _buildCard(
        context,
        l10n,
        theme,
        category,
        priceText,
        bandTags,
        unavailable,
        hasDescription ? description : null,
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

    /// Already trimmed and proven non-empty by [build]; null = render nothing.
    String? description,
  ) {
    // THE DESCRIPTION AND THE NAME'S SECOND LINE YIELD TO TEXT SCALE; THE
    // PRICE AND THE ACTION ROW NEVER DO.
    //
    // The card content zone is a FIXED [kPosMenuCardBodyHeight] because the
    // grid computes cell height from it, but everything inside it scales with
    // the user's text setting, so larger scales must shed presentational
    // lines instead of overflowing (POS-PRODUCT-DESCRIPTIONS-001: the
    // description has no tap target, no tooltip, no placeholder when absent).
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    // POS-REFERENCE-REDESIGN-002 ladder: the description (max ONE subdued
    // line now) yields first, the name's SECOND line yields next; the price
    // and the 44px action row never compress.
    final descriptionLines = textScale <= 1.15 ? 1 : 0;
    final nameLines = textScale <= 1.4 ? 2 : 1;
    final hasDescription = description != null && descriptionLines > 0;
    // POS-VISUAL-REDESIGN-PHASE-1-007: a WHITE card, not `colorScheme.surface`
    // — the green-tinted surface sat within three values of the hairline and
    // dissolved the card's own edge. r14 (the biggest object on screen) and the
    // single-layer e1 shadow; the second layer of the old two-layer shadow was
    // invisible at card size and doubled the paint cost across ~19 cards.
    // POS-PREMIUM-VISUAL-POLISH-001: the shell gains a pointer hover lift
    // (e1 -> hover shadow + a firmer border) — paint-only, geometry frozen.
    return _CardShell(
      hoverable: !unavailable,
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
            // The fixed 10:9 image band (REFERENCE-REDESIGN-002: the
            // photograph is the top ~60% of the card): cover-fit photo (with
            // cacheWidth) that never stretches, or the tinted category band
            // on null/error.
            AspectRatio(
              aspectRatio: 1 / kPosMenuCardImageHeightFactor,
              child: _ImageBand(
                item: item,
                category: category,
                l10n: l10n,
                bandTags: bandTags,
                inCartQuantity: inCartQuantity,
                optionGroupCount: optionGroupCount,
                unavailable: unavailable,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: kRestoflowInk,
                            height: 1.25,
                          ),
                          // REFERENCE-REDESIGN-002: up to TWO confident name
                          // lines (the ladder drops the second at large text
                          // scales — never the price row).
                          maxLines: nameLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // POS-PRODUCT-DESCRIPTIONS-001: the description sits
                        // directly under the name, in the secondary ink, and is
                        // purely presentational — no tap target, no tooltip, no
                        // placeholder when absent. `letterSpacing` is
                        // deliberately left alone: forcing one breaks
                        // Arabic/Hebrew shaping. Ambient Directionality and the
                        // directional start alignment handle RTL.
                        if (hasDescription) ...[
                          const SizedBox(height: RestoflowSpacing.xxs),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: kPosMutedBodyInk,
                              height: 1.25,
                              // EXPLICITLY zero: the ambient bodySmall carries
                              // a 0.4 tracking that pulls Arabic and Hebrew
                              // glyphs apart and breaks their shaping.
                              letterSpacing: 0,
                            ),
                            maxLines: descriptionLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    // SURGERY-003 anatomy: a start-aligned price line, then
                    // the FULL-WIDTH action footer — Add / Add more /
                    // unavailable bar all occupy the same fixed zone, so
                    // every card in a row aligns at image, title, price and
                    // action.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PriceText(
                          priceKey: Key('menu-item-price-${item.id}'),
                          formatted: priceText,
                        ),
                        const SizedBox(height: 6),
                        _CardAction(
                          onAdd: unavailable ? null : onAdd,
                          l10n: l10n,
                          itemId: item.id,
                          inCart: inCartQuantity > 0,
                          unavailableLabel: unavailable
                              ? _unavailableLabel(l10n, item.availabilityReason)
                              : null,
                          interactionAccent: interactionAccent,
                        ),
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

/// The card shell: white, r14, hairline, e1 at rest; on pointer hover it
/// lifts to the premium hover shadow with a slightly firmer cool border.
/// Purely decorative — layout, radius and the InkWell child are untouched,
/// and touch-only devices simply never hover.
class _CardShell extends StatefulWidget {
  const _CardShell({required this.hoverable, required this.child});

  final bool hoverable;
  final Widget child;

  @override
  State<_CardShell> createState() => _CardShellState();
}

class _CardShellState extends State<_CardShell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hover = _hover && widget.hoverable;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: PosMotionDurations.base,
        curve: Curves.easeOutCubic,
        // SURGERY-003: shadow ON HOVER ONLY — at rest the card is a calm
        // white surface with a 1px border, like the reference.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kPosCardRadius),
          boxShadow: hover ? kPosCardHoverShadow : null,
        ),
        child: Card(
          elevation: 0,
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kPosCardRadius),
            side: BorderSide(
              color: hover ? kPosInputBorder : kRestoflowHairline,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// POS-VISUAL-REDESIGN-PHASE-1-007 — the price with the SYMBOL demoted and the
/// DIGITS promoted (spec §9.3).
///
/// The formatted string is NOT altered: [MoneyFormatter]'s output is split into
/// its leading/trailing non-digit runs and its numeric core, rendered as spans
/// of one `Text.rich` whose plain text is byte-identical to the input. The money
/// value, its formatting and every `find.text(price)` contract therefore
/// survive — only the rendering changes. Forced LTR so a price never re-orders
/// inside Arabic or Hebrew.
class _PriceText extends StatelessWidget {
  const _PriceText({required this.priceKey, required this.formatted});

  final Key priceKey;
  final String formatted;

  @override
  Widget build(BuildContext context) {
    // POS-VISUAL-REDESIGN-PHASE-1-007 Step 3: this carried a private copy of
    // the split. Step 2 added the identical POS-local helper for the cart, so
    // both surfaces now share ONE implementation. The output is unchanged —
    // lead + core + trail still reconstruct the MoneyFormatter string exactly.
    final (lead, core, trail) = posSplitFormattedMoney(formatted);
    const symbolStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: kRestoflowInk3,
      letterSpacing: 0,
    );
    const digitStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: kRestoflowInk,
      letterSpacing: -0.2,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Text.rich(
      TextSpan(
        children: [
          if (lead.isNotEmpty) TextSpan(text: lead, style: symbolStyle),
          TextSpan(text: core, style: digitStyle),
          if (trail.isNotEmpty) TextSpan(text: trail, style: symbolStyle),
        ],
      ),
      key: priceKey,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
    required this.optionGroupCount,
    required this.unavailable,
  });

  final DemoMenuItem item;
  final DemoCategory category;
  final AppLocalizations l10n;
  final List<String> bandTags;
  final int inCartQuantity;
  final int optionGroupCount;
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
        // POS-PREMIUM-VISUAL-POLISH-001: a soft navy-ink top scrim over real
        // photos only, so tag pills and the in-cart badge stay legible on a
        // bright photograph. Decorative; the tinted category band needs none.
        if (item.imageUrl != null)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x2E0B1526), Color(0x000B1526)],
                stops: [0.0, 0.45],
              ),
            ),
          ),
        // Spec §12/§16.4: tag pills at the band's inline-START, the in-cart
        // badge at the inline-END, the options chip at the bottom inline-END.
        // The tags and the badge share ONE top row rather than being placed
        // independently, so on a narrow cell the tags yield width instead of
        // running under the badge — no magic reservation, no overlap.
        if (bandTags.isNotEmpty || inCartQuantity > 0)
          PositionedDirectional(
            top: RestoflowSpacing.sm,
            start: RestoflowSpacing.sm,
            end: RestoflowSpacing.sm,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  // A pill cannot shrink below its own label, so on the very
                  // narrowest approved cell (148px) a long tag beside the
                  // in-cart badge could still overrun the band by a fraction of
                  // a pixel. scaleDown is self-limiting — it does nothing while
                  // the pill fits, and shrinks it only by the margin actually
                  // missing, so the label never wraps, clips or overflows.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: RestoflowSpacing.xs,
                      runSpacing: RestoflowSpacing.xs,
                      children: [
                        // When the in-cart badge shares this row the band shows
                        // the single highest-priority tag instead of squeezing
                        // two. Priority order and the unknown-tag skip are
                        // unchanged.
                        for (final tag
                            in inCartQuantity > 0 ? bandTags.take(1) : bandTags)
                          RestoflowStatusPill(
                            label: _tagLabel(l10n, tag),
                            tone: _tagTone(tag),
                          ),
                      ],
                    ),
                  ),
                ),
                if (inCartQuantity > 0) ...[
                  const SizedBox(width: RestoflowSpacing.xs),
                  _InCartBadge(quantity: inCartQuantity),
                ],
              ],
            ),
          ),
        if (optionGroupCount > 0)
          PositionedDirectional(
            bottom: RestoflowSpacing.sm,
            end: RestoflowSpacing.sm,
            child: _OptionsIndicator(
              count: optionGroupCount,
              tooltip: l10n.menuModifierGroupCount(optionGroupCount),
            ),
          ),
        // RESTAURANT-OPERATIONS-V1-001 → SURGERY-003: the not-sellable
        // treatment keeps the dimming scrim on the photo; the keyed reason
        // pill now lives in the card's full-width footer bar (one place,
        // text never colour alone).
        if (unavailable) const ColoredBox(color: Color(0x99FFFFFF)),
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
        color: kRestoflowBrandDark,
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x470B1526),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
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
        // Flat translucent ink over the photo — the spec's one backdrop-blur is
        // deliberately NOT ported: it reads the same and costs a layer.
        decoration: BoxDecoration(
          color: const Color(0xB80B1526),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.tune,
              size: RestoflowIconSizes.xs,
              color: Colors.white,
            ),
            const SizedBox(width: RestoflowSpacing.xxs),
            Text(
              count.toString(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// POS-REFERENCE-VISUAL-SURGERY-003 — the card's FULL-WIDTH action footer,
/// the signature element:
///  * available          → filled NAVY bar, white icon + label (Add);
///  * already in cart    → TONAL bar (navy container, navy label — Add more;
///                          the band badge carries the count);
///  * cart-locked        → the same bar, disabled (onAdd == null);
///  * unavailable        → a muted disabled BAR carrying the reason text —
///                          no icon, no tap (the canonical add glyph never
///                          renders on an unsellable card).
/// The add gesture, its 44px floor and its single `Icons.add_shopping_cart`
/// per card are the frozen contracts; only the clothing changed.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.onAdd,
    required this.l10n,
    required this.itemId,
    required this.inCart,
    required this.unavailableLabel,
    this.interactionAccent,
  });

  final VoidCallback? onAdd;
  final AppLocalizations l10n;
  final String itemId;
  final bool inCart;

  /// Non-null = the item cannot be sold; the footer renders the reason.
  final String? unavailableLabel;

  /// POS-PREMIUM-VISUAL-POLISH-001: the terminal's secondary accent for
  /// hover/pressed washes and the focus ring. Null keeps the shared brand
  /// accent (pre-existing behaviour and test contract).
  final Color? interactionAccent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (unavailableLabel != null) {
      // The keyed reason pill (danger tone + icon — text never colour alone)
      // rides inside the muted full-width bar; scale-down keeps the longest
      // ar/he wording inside the narrowest cell.
      return Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: RestoflowSpacing.xs),
        decoration: BoxDecoration(
          color: kPosDisabledBg,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: RestoflowStatusPill(
            key: Key('menu-item-unavailable-$itemId'),
            label: unavailableLabel!,
            tone: RestoflowTone.danger,
            icon: Icons.do_not_disturb_on_outlined,
          ),
        ),
      );
    }
    final accent =
        interactionAccent ??
        RestoflowBrandPalette.of(theme.brightness).accentOrange;
    // Add stays NAVY (or tonal once in cart) and earns the terminal accent
    // only on interaction — an orange wash on hover, a deeper one on press,
    // and an accent focus ring. Send keeps the single dominant CTA role.
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(
          Icons.add_shopping_cart,
          size: RestoflowIconSizes.sm + 2,
        ),
        label: Text(
          inCart ? l10n.posAddMore : l10n.posAddToCart,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style:
            FilledButton.styleFrom(
              backgroundColor: inCart
                  ? kRestoflowNavyContainer
                  : theme.colorScheme.primary,
              foregroundColor: inCart
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onPrimary,
              disabledBackgroundColor: const Color(0xFFE9EEF5),
              disabledForegroundColor: const Color(0xFFA8B2C1),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.sm,
              ),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(RestoflowRadii.md),
                ),
              ),
              animationDuration: RestoflowDurations.fast,
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return accent.withValues(alpha: 0.30);
                }
                if (states.contains(WidgetState.hovered)) {
                  return accent.withValues(alpha: 0.18);
                }
                return null;
              }),
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return BorderSide(color: accent, width: 2);
                }
                return null;
              }),
            ),
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
    // SURGERY-003: no flat pastel slab — the imageless band is a composed
    // tinted scene: two soft offset discs in the category hue behind the
    // category glyph. Same data, same fallback semantics, premium at rest.
    final tint = category.color;
    return Ink(
      color: tint.withValues(alpha: 0.08),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              PositionedDirectional(
                top: -w * 0.28,
                end: -w * 0.22,
                child: Container(
                  width: w * 0.78,
                  height: w * 0.78,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: -w * 0.16,
                start: -w * 0.10,
                child: Container(
                  width: w * 0.42,
                  height: w * 0.42,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: w * 0.30,
                  height: w * 0.30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    category.icon,
                    size: RestoflowIconSizes.xl,
                    color: tint.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// MONEY-LOCAL-ATOMICITY-003A — the ONE place an availability reason becomes a
/// label, so the scrim pill and the accessibility announcement can never
/// disagree about WHY an item cannot be sold.
String _unavailableLabel(AppLocalizations l10n, String? reason) =>
    switch (reason) {
      'paused' => l10n.posMenuItemPaused,
      DemoMenuItem.configurationUnavailableReason =>
        l10n.posMenuItemConfigurationUnavailable,
      _ => l10n.posMenuItemSoldOut,
    };
