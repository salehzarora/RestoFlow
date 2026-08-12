import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
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
    // POS-DESIGN-HANDOFF-IMPLEMENTATION-004 ladder: the fixed description
    // slot yields first; the name is ONE ellipsizing line beside the price on
    // the approved shared baseline row; the price and the 44px action row
    // never compress.
    final showDescriptionSlot = textScale <= 1.15;
    final hasDescription = description != null && showDescriptionSlot;
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
            // 004: the approved INSET 4:3 photo band — floated 6px inside the
            // card edge on its own r10 clip (no longer edge-to-edge). Cover-
            // fit photo (with cacheWidth) that never stretches, or the tinted
            // category scene on null/error.
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                kPosCardImageInset,
                kPosCardImageInset,
                kPosCardImageInset,
                0,
              ),
              child: AspectRatio(
                aspectRatio: kPosCardImageAspect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kPosTrackRadius),
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
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 004: the approved shared baseline row — a one-line
                        // ellipsizing name at the start, the ember price at
                        // the end — so every card in a row aligns at image,
                        // title+price and action.
                        LayoutBuilder(
                          builder: (context, rowBox) => Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // The NAME takes the true remainder and
                              // ellipsizes (the approved mockup truncates
                              // long names the same way). The PRICE is never
                              // truncated: it keeps its intrinsic width up
                              // to 55% of the row, and only when genuinely
                              // starved (extreme text scales) the complete
                              // figure scales down inside that cap.
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: RestoflowSpacing.sm,
                                  ),
                                  child: Text(
                                    item.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: kRestoflowInk,
                                      fontSize: 13.5,
                                      height: 1.25,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: rowBox.maxWidth * 0.55,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: _PriceText(
                                    priceKey: Key('menu-item-price-${item.id}'),
                                    formatted: priceText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // POS-PRODUCT-DESCRIPTIONS-001 → 004: ONE subdued
                        // description line in a FIXED-HEIGHT slot (empty when
                        // the item has none) so all cards in a row keep their
                        // action footers aligned. No tap target, no tooltip.
                        // `letterSpacing: 0` — the ambient tracking breaks
                        // Arabic/Hebrew shaping.
                        if (showDescriptionSlot) ...[
                          const SizedBox(height: RestoflowSpacing.xxs),
                          SizedBox(
                            height: 15,
                            child: hasDescription
                                ? Text(
                                    description,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: kPosMutedBodyInk,
                                      fontSize: 11,
                                      height: 1.3,
                                      letterSpacing: 0,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                          ),
                        ],
                      ],
                    ),
                    // The FULL-WIDTH action footer — Add / Add more /
                    // unavailable bar all occupy the same fixed zone.
                    _CardAction(
                      onAdd: unavailable ? null : onAdd,
                      l10n: l10n,
                      itemId: item.id,
                      inCart: inCartQuantity > 0,
                      inCartQuantity: inCartQuantity,
                      unavailableLabel: unavailable
                          ? _unavailableLabel(l10n, item.availabilityReason)
                          : null,
                      interactionAccent: interactionAccent,
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
        // 004: the approved hover-lift timing (states/motion §7: 220ms).
        duration: const Duration(milliseconds: 220),
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
          // 004: the approved thin COOL outline (#DEE5F0) — constant across
          // rest and hover; the hover cue is the lift shadow alone.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kPosCardRadius),
            side: const BorderSide(color: kPosCardOutline),
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
    //
    // 004: the digits are the approved EMBER action figures in Inter tabular
    // (tokens §8/§10); the demoted symbol stays muted ink. Values/formatting
    // are untouched — MoneyFormatter output remains byte-identical.
    final (lead, core, trail) = posSplitFormattedMoney(formatted);
    const symbolStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      color: kRestoflowInk3,
      letterSpacing: 0,
      fontFamily: kPosMoneyFontFamily,
      fontFamilyFallback: kPosMoneyFontFallbacks,
    );
    final digitStyle = TextStyle(
      fontSize: 15.5,
      fontWeight: FontWeight.w800,
      color: PosThemePair.of(context).action,
      letterSpacing: -0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontFamily: kPosMoneyFontFamily,
      fontFamilyFallback: kPosMoneyFontFallbacks,
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
        // 004 band overlays (component specs §3/§8): the always-on
        // availability pill leads the band's inline-START beside at most one
        // tag pill; the ember ×N in-cart mark holds the inline-END; the
        // options chip keeps the bottom inline-END. One shared top row, so on
        // a narrow cell the pills yield width instead of overlapping.
        PositionedDirectional(
          top: RestoflowSpacing.sm,
          start: RestoflowSpacing.sm,
          end: RestoflowSpacing.sm,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // A pill cannot shrink below its own label, so on the very
                // narrowest approved cell a long tag beside the in-cart mark
                // could still overrun the band by a fraction of a pixel.
                // scaleDown is self-limiting — it does nothing while the pill
                // fits, and shrinks it only by the margin actually missing.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: RestoflowSpacing.xs,
                    runSpacing: RestoflowSpacing.xs,
                    children: [
                      // The approved always-on reassurance on SELLABLE cards
                      // (presentation-only; the sale gate is unchanged).
                      if (!unavailable)
                        RestoflowStatusPill(
                          label: l10n.posMenuItemAvailable,
                          tone: RestoflowTone.success,
                        ),
                      // One highest-priority tag beside it. Priority order and
                      // the unknown-tag skip are unchanged.
                      for (final tag in bandTags.take(1))
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
        // RESTAURANT-OPERATIONS-V1-001 → 004: the approved not-sellable
        // treatment (states board 1e) — an ivory 62% scrim with the KEYED
        // danger reason pill centered ON the photo, echoed by the muted
        // footer bar below. Text, never colour alone; the sale gate is the
        // same server-backed refusal.
        if (unavailable) ...[
          const ColoredBox(color: Color(0x9EF7F5F1)),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.xs,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RestoflowStatusPill(
                  key: Key('menu-item-unavailable-${item.id}'),
                  label: _unavailableLabel(l10n, item.availabilityReason),
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

/// 004: the approved EMBER ×N in-cart mark on the band's top inline-END
/// (tokens §8: r8, Inter 800, forced-LTR run). Presentation-only count.
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
        color: PosThemePair.of(context).actionMark,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x470B1526),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Text(
        '×$quantity',
        textDirection: TextDirection.ltr,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontFamily: kPosMoneyFontFamily,
          fontFamilyFallback: kPosMoneyFontFallbacks,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
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

/// POS-DESIGN-HANDOFF-IMPLEMENTATION-004 — the card's FULL-WIDTH action
/// footer, the signature element (approved v4, tokens §10):
///  * available          → PRIMARY GRADIENT bar + soft primary glow, white
///                          icon + Alexandria 700 label (Add);
///  * already in cart    → TONAL bar (cool tonal bed, navy label — Add more
///                          with the ×N chip; shadowless);
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
    required this.inCartQuantity,
    required this.unavailableLabel,
    this.interactionAccent,
  });

  final VoidCallback? onAdd;
  final AppLocalizations l10n;
  final String itemId;
  final bool inCart;

  /// The ×N chip inside the tonal "Add more" treatment (0 hides it).
  final int inCartQuantity;

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
      // The muted full-width bar echoing the band's keyed reason pill
      // (states board 1e). Plain text — the pill on the photo carries the
      // key + danger tone + icon; this bar keeps the reason beside where the
      // add action would be, so the footer zone never reads as tappable.
      return Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: RestoflowSpacing.xs),
        decoration: BoxDecoration(
          color: const Color(0xFFF1EEE7),
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            unavailableLabel!,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8A8377),
            ),
          ),
        ),
      );
    }
    final pair = PosThemePair.of(context);
    final accent =
        interactionAccent ??
        RestoflowBrandPalette.of(theme.brightness).accentOrange;
    final enabled = onAdd != null;
    // The gradient + glow live on a wrapper (a FilledButton cannot paint a
    // gradient); the button itself goes transparent over it. Tonal and
    // disabled bars are flat and shadowless per the approved spec.
    final showGradient = enabled && !inCart;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        gradient: showGradient ? pair.primaryGradient : null,
        color: showGradient
            ? null
            : !enabled
            ? kPosDisabledBg
            : kPosTonalAddBg,
        boxShadow: showGradient
            ? [
                BoxShadow(
                  color: pair.primary.withValues(alpha: 0.22),
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: FilledButton(
          onPressed: onAdd,
          // A custom child instead of FilledButton.icon: the stock icon
          // variant lays its label out INFLEXIBLY, which overflows the
          // narrow approved cells at 2x text scale. Same canonical glyph,
          // same label strings — the label just ellipsizes honestly.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_shopping_cart,
                size: RestoflowIconSizes.sm + 2,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  inCart ? l10n.posAddMore : l10n.posAddToCart,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (inCart && inCartQuantity > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '×$inCartQuantity',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: pair.primary,
                      fontFamily: kPosMoneyFontFamily,
                      fontFamilyFallback: kPosMoneyFontFallbacks,
                    ),
                  ),
                ),
              ],
            ],
          ),
          style:
              FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: inCart ? pair.primary : Colors.white,
                shadowColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                disabledForegroundColor: kPosDisabledFg,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(
                  horizontal: RestoflowSpacing.sm,
                ),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 13.5,
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
                    return inCart
                        ? accent.withValues(alpha: 0.12)
                        : pair.primaryDeep.withValues(alpha: 0.55);
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
