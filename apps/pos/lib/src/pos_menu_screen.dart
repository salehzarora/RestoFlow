import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'design/pos_motion.dart';
import 'design/pos_visual_tokens.dart';
import 'data/order_center_view.dart' show PosOrderSection, sectionContains;
import 'pos_palette.dart';
import 'state/cart_controller.dart';
import 'state/discount_controller.dart' show staffCapabilitiesProvider;
import 'state/menu_filter.dart';
import 'state/pos_device_accent.dart';
import 'state/pos_menu_provider.dart';
import 'state/pos_offline_state.dart';
import 'state/recent_orders_controller.dart'
    show posRecentOrdersControllerProvider;
import 'widgets/category_chips.dart';
import 'widgets/cart_panel.dart';
import 'widgets/device_settings_menu.dart';
import 'widgets/language_selector.dart';
import 'widgets/menu_availability_sheet.dart';
import 'widgets/menu_item_card.dart';
import 'widgets/modifier_selection_sheet.dart';
import 'widgets/open_orders_strip.dart';
import 'widgets/outbox_status_indicator.dart';
import 'widgets/pos_identity_title.dart';
import 'widgets/pos_bottom_bar.dart';
import 'widgets/ready_alert_overlay.dart';
import 'widgets/ready_notification_bell.dart';
import 'widgets/recent_orders_sheet.dart';

/// The RestoFlow POS cashier screen (DESIGN-004 Warm/Bento): a warm-canvas
/// menu grid + search beside a live cart. Responsive from the ACTUAL available
/// width (never the platform): desktop/tablet/compact-landscape show a side
/// cart; phone shows a full-width menu with a dark bottom cart bar + slide-up
/// sheet. Sells from the ACTIVE menu ([posMenuProvider]) with honest
/// loading/error/empty states — all chrome is localized; item names are data.
class PosMenuScreen extends StatelessWidget {
  const PosMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      // POS-PREMIUM-VISUAL-POLISH-001: the menu canvas is the one warm note
      // on the screen (ivory — restaurant, not SaaS). Controls stay on the
      // white deck and cool fills; the cart paints its own white plane.
      backgroundColor: kPosIvorySurface,
      // POS-DESIGN-HANDOFF-IMPLEMENTATION-004 — the approved CONNECTED brand
      // navbar (component specs §8): one full-bleed primary bar carrying the
      // brand plate at the start edge, the centered restaurant-identity chip
      // and the action cluster on a translucent bed. Same five action
      // widgets, same order, same behaviors — only the clothing changed.
      // POS-NAVBAR-BRAND-LOCKUP: the plate now carries the OFFICIAL BIZBOT
      // symbol + English wordmark artwork and the bar is one step taller
      // (ladder in pos_visual_tokens.dart).
      appBar: AppBar(
        backgroundColor: PosThemePair.of(context).primary,
        surfaceTintColor: PosThemePair.of(context).primary,
        scrolledUnderElevation: 0,
        toolbarHeight: posTopBarMetricsFor(
          MediaQuery.sizeOf(context).width,
        ).height,
        // POS-CUSTOM-DEVICE-THEME-010: the navbar chrome ink rides the pair —
        // byte-identical kPosNavbarInk on every preset, a derived dark ink
        // when a CUSTOM pair picks a light primary bar.
        iconTheme: IconThemeData(color: PosThemePair.of(context).navInk),
        actionsIconTheme: IconThemeData(color: PosThemePair.of(context).navInk),
        titleSpacing: RestoflowSpacing.lg,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final metrics = posTopBarMetricsFor(
              MediaQuery.sizeOf(context).width,
            );
            // The plate is bounded by the title slot (never the unbounded
            // Row slot), so the lockup shrinks gracefully — wordmark image
            // contained, tagline ellipsized — instead of overflowing the bar
            // when the five actions and their full outbox label take the
            // room on a 480–820 px bar.
            final plateMax =
                (constraints.maxWidth * kPosNavbarBrandPlateMaxShare)
                    .clamp(
                      metrics.markSize +
                          kPosNavbarBrandPlateCompactInsets.horizontal,
                      kPosNavbarBrandPlateMaxWidth,
                    )
                    .toDouble();
            final showWordmark =
                metrics.wordmark &&
                plateMax >= posNavbarWordmarkMinPlateWidth(metrics.markSize);
            return Row(
              children: [
                // POS-NAVBAR-BRAND-LOCKUP: the official BIZBOT lockup — the
                // shared RestoflowBrandMark (final symbol + the official
                // English wordmark PNG, never typed) on a Light Neutral brand
                // plate, so the charcoal `BIZ` reads on the dark device-theme
                // bar exactly as on the identity board. Always visible, every
                // width; below kPosCompactAppBarWidth the wordmark yields to
                // the five operational actions (PSC-001A) and the symbol
                // keeps the identity. Artwork is never mirrored in RTL (the
                // mark pins matchTextDirection=false); the Row itself flips
                // so the symbol stays at the bar's START edge in both
                // directions.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: plateMax),
                  child: _PosBrandPlate(
                    markSize: metrics.markSize,
                    wordmark: showWordmark,
                    tagline: l10n.posBrandTagline,
                  ),
                ),
                // POS-TOPBAR-RESTAURANT-IDENTITY-009: the connected
                // restaurant's identity fills the empty middle. `Expanded` is
                // what makes this safe — the identity can only ever use the
                // space the left block and the actions did NOT take, so it
                // cannot overlap either, at any width or in either text
                // direction. The left block above is unchanged and keeps its
                // natural size.
                const Expanded(child: PosIdentityTitle()),
              ],
            );
          },
        ),
        actions: [
          // The v4 action cluster: the SAME five operational actions riding
          // one translucent bed. IconTheme above lights their glyphs for the
          // dark bar; each widget's behavior, tooltip and keys are untouched.
          Container(
            // Vertical margin 5: the polished bar ladder (68/62/56) must
            // leave the five operational actions a >=44dp touch height
            // (56-10=46; 62-10=52; 68-10=58) — the bar heights never buy
            // their looks with sub-floor targets (pinned in
            // pos_appbar_compact_test).
            margin: const EdgeInsetsDirectional.only(
              end: RestoflowSpacing.sm,
              top: 5,
              bottom: 5,
            ),
            decoration: BoxDecoration(
              color: PosThemePair.of(context).navBed,
              borderRadius: BorderRadius.circular(11),
            ),
            // Light glyph ink for the dark bar, applied INSIDE the cluster
            // (a plain Theme wrapper here re-installed the ambient dark
            // IconTheme and silently defeated `actionsIconTheme`), plus the
            // approved white-16% hover wash where M3 IconButtons actually
            // read it: their ButtonStyle overlay. Every action keeps its own
            // widget, tooltip, keys and behavior.
            // POS-CUSTOM-DEVICE-THEME-010: ink + washes ride the pair's
            // onPrimary (white on every preset — identical bytes; dark on a
            // light custom bar).
            child: IconTheme.merge(
              data: IconThemeData(color: PosThemePair.of(context).navInk),
              child: IconButtonTheme(
                data: IconButtonThemeData(
                  style: ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(
                      PosThemePair.of(context).navInk,
                    ),
                    overlayColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? PosThemePair.of(
                              context,
                            ).onPrimary.withValues(alpha: 0.14)
                          : states.contains(WidgetState.hovered) ||
                                states.contains(WidgetState.focused)
                          ? PosThemePair.of(
                              context,
                            ).onPrimary.withValues(alpha: 0.16)
                          : null,
                    ),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // PSC-001A: the ready-notification bell leads the action
                    // group.
                    ReadyNotificationBell(),
                    RecentOrdersButton(),
                    OutboxStatusIndicator(),
                    LanguageSelector(),
                    DeviceSettingsMenu(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // PSC-001A: the body hosts the ONE ready-alert banner above whichever
      // responsive layout is active — same overlay on phone and tablet.
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // POS-PHASE1-FOLLOWUP-FIXES-008: the mode comes from the DEVICE
              // viewport, not from the body constraints.
              //
              // The body shrinks while the on-screen keyboard is up, and on an
              // 11" landscape tablet (1280x800) a ~400dp keyboard pushed the
              // remaining height under `kPosCompactHeight`. The mode then
              // flipped tablet -> compactLandscape MID-TYPING, the cart went
              // 360 -> 320, that crossed the paired-fields threshold, and the
              // customer field the cashier was typing into was rebuilt into a
              // different parent — losing its controller, its focus and the
              // keyboard. A transient keyboard is not a change of form factor.
              //
              // `posMenuGridGeometryOf` already resolved from `MediaQuery`, so
              // this also stops the cart width and the column count disagreeing
              // while the keyboard is open.
              final viewport = MediaQuery.sizeOf(context);
              // PERF-110: posture (side cart vs bottom bar) is decided by
              // ORIENTATION first — portrait is always single pane; landscape
              // keeps the frozen PosLayoutMode contract.
              final posture = posShellPostureFor(
                width: viewport.width,
                height: viewport.height,
              );

              if (posture == PosShellPosture.singlePane) {
                // 007 FRAMELESS: the phone pane paints its own WHITE base.
                // The frameless cards rely on the workspace surface being
                // white; without this they would sit transparently on the
                // ivory Scaffold (no hover exists on a touch phone to
                // restore any boundary), and the muted unavailable bar
                // would vanish into the canvas.
                return const Column(
                  children: [
                    Expanded(
                      child: ColoredBox(
                        color: Colors.white,
                        child: _MenuPane(),
                      ),
                    ),
                    PosBottomBar(),
                  ],
                );
              }

              final compact = posCompactDensityFor(
                width: viewport.width,
                height: viewport.height,
              );
              // POS-REFERENCE-VISUAL-SURGERY-003: TWO floating surfaces on
              // the ivory canvas — the rounded white menu WORKSPACE and the
              // rounded white ORDER SUMMARY panel — separated by real
              // gutters. The SizedBox still measures exactly
              // posCartWidthFor(mode) (frozen width contract).
              final gutter = compact ? 12.0 : kPosShellGutter;
              final gap = compact ? 10.0 : kPosShellGap;
              return Padding(
                padding: EdgeInsets.all(gutter),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(child: _ShellSurface(child: _MenuPane())),
                    SizedBox(width: gap),
                    SizedBox(
                      width: posShellCartWidthFor(
                        width: viewport.width,
                        height: viewport.height,
                      ),
                      child: _ShellSurface(child: CartPanel(compact: compact)),
                    ),
                  ],
                ),
              );
            },
          ),
          const ReadyAlertOverlay(),
        ],
      ),
    );
  }
}

/// POS-NAVBAR-BRAND-LOCKUP — the brand plate at the bar's start edge: the
/// shared [RestoflowBrandMark] (official symbol; + the official English
/// wordmark artwork over the localized product line when the bar is wide
/// enough) on a Light Neutral plate. Keyed `pos-brand-tile` — the same key
/// the former white tile carried, so every existing top-bar test keeps
/// finding the brand block where it always was.
class _PosBrandPlate extends StatelessWidget {
  const _PosBrandPlate({
    required this.markSize,
    required this.wordmark,
    required this.tagline,
  });

  final double markSize;
  final bool wordmark;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pos-brand-tile'),
      padding: wordmark
          ? kPosNavbarBrandPlateInsets
          : kPosNavbarBrandPlateCompactInsets,
      decoration: BoxDecoration(
        color: kBizbotSurface,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      // The plate is the light identity surface; the lockup's tagline ink
      // must read on IT, not on whatever the device-theme bar is.
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(onSurfaceVariant: kRestoflowInk2),
        ),
        child: wordmark
            ? RestoflowBrandMark(
                size: markSize,
                wordmark: BizbotWordmark.latin,
                tagline: tagline,
              )
            : RestoflowBrandMark(size: markSize),
      ),
    );
  }
}

/// POS-DESIGN-HANDOFF-IMPLEMENTATION-004 — one floating rounded white surface
/// of the two-plane shell. BORDERLESS per the approved v4 panels: r18 on a
/// soft floating shadow instead of a warm hairline. Purely presentational.
class _ShellSurface extends StatelessWidget {
  const _ShellSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kPosShellRadius),
        boxShadow: kPosPanelFloatShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kPosShellRadius),
        child: child,
      ),
    );
  }
}

/// The menu side: a header (title + item count + search) and the filtered grid.
class _MenuPane extends ConsumerWidget {
  const _MenuPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(posMenuProvider);

    final menu = menuAsync.valueOrNull;
    // POS-VISUAL-REDESIGN-PHASE-1-007: the category rail is built HERE, beside
    // the heading and the search, so one deck can contain the whole menu
    // navigation. It used to be built inside `_MenuGrid`, which put a control
    // on the same plane as the merchandise. It stays in this same high-level
    // menu Column and the grid keeps owning its own scroll.
    final Widget? rail = menu == null || menu.items.isEmpty
        ? null
        : CategoryChips(
            categories: menu.categories,
            itemCounts: _categoryCounts(menu),
          );

    // POS-OPEN-ORDERS-STRIP-011: the strip needs the denser band exactly where
    // the grid itself goes compact (the 1024x600 class of viewports).
    final viewport = MediaQuery.sizeOf(context);
    final compactStrip = posCompactDensityFor(
      width: viewport.width,
      height: viewport.height,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MenuDeck(
          itemCount: menu?.items.length,
          rail: menuAsync.isLoading ? const _CategoryRailSkeleton() : rail,
        ),
        // POS-OPEN-ORDERS-STRIP-011: every currently-open order, one tap from
        // its existing detail/actions surface. Renders NOTHING when no order
        // is open.
        // POS-OPEN-ORDERS-SCROLL-POLISH-017: while the GRID is showing, the
        // strip lives INSIDE the grid's own vertical scroll (its first,
        // NON-PINNED element) so it scrolls away naturally with the products
        // and returns at the top — see [_MenuScrollBody]. Every OTHER menu
        // state (skeleton / load error / setup-required) has no vertical
        // scroll, so the strip keeps its fixed spot above the state view
        // here, exactly as before. The two mounts are mutually exclusive:
        // this guard is the same test `when` uses to pick the data branch.
        if (menuAsync is! AsyncData<PosMenuData>)
          OpenOrdersStrip(compact: compactStrip),
        Expanded(
          child: menuAsync.when(
            loading: () => const _MenuSkeleton(),
            // [POS-OFFLINE-OPERATIONS-002] A menu error while the offline
            // phase is SETUP-REQUIRED means this till has never completed its
            // one-time online bootstrap — that gets its own explanation
            // instead of the generic load error. `offlineCached` never lands
            // here: the provider returned cached DATA, so the normal grid
            // (with the slim offline banner) renders below.
            error: (_, _) =>
                ref.watch(posOfflineModeProvider).phase ==
                    PosOfflinePhase.setupRequired
                ? _OfflineSetupRequired(
                    onRetry: () => ref.invalidate(posMenuProvider),
                  )
                : _MenuLoadError(
                    onRetry: () => ref.invalidate(posMenuProvider),
                  ),
            data: (menu) => _MenuGrid(menu: menu, stripCompact: compactStrip),
          ),
        ),
      ],
    );
  }

  /// Per-category counts for the chip badges (All = total) — unchanged rule,
  /// lifted with the rail so the deck can render the same numbers.
  static Map<String, int> _categoryCounts(PosMenuData menu) {
    final counts = <String, int>{kAllCategoriesId: menu.items.length};
    for (final category in menu.categories) {
      counts[category.id] = menu.items
          .where((i) => i.categoryId == category.id)
          .length;
    }
    return counts;
  }
}

/// POS-VISUAL-REDESIGN-PHASE-1-007 — the coordinated menu deck: ONE elevated
/// white plane carrying the heading, the live item count, the search field and
/// the category rail, with the product grid left on the warm canvas below it.
///
/// The point is plane separation. Before this, search, chips and product cards
/// were all white rounded boxes with the same hairline on the same canvas, so
/// the cashier had to READ the screen to find its structure. Two planes and a
/// single downward shadow replace a pile of extra borders.
class _MenuDeck extends StatelessWidget {
  const _MenuDeck({required this.itemCount, required this.rail});

  final int? itemCount;

  /// The category rail (or its loading placeholder). Null while the menu is
  /// empty or failed — exactly as no chips rendered before.
  final Widget? rail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // SURGERY-003: the deck lives INSIDE the floating workspace surface now —
    // no shadow of its own; a soft bottom seam separates controls from
    // merchandise.
    return DecoratedBox(
      key: const Key('pos-menu-deck'),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: BorderDirectional(
          bottom: BorderSide(color: kRestoflowHairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            // 004: the approved deck inner padding (tokens §5: deck inner 18).
            padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 18, 0),
            child: Row(
              children: [
                // THE HEADING CLUSTER CAN GIVE GROUND.
                //
                // The heading and the live item count were both NON-FLEX
                // children beside an Expanded search field, so each measured
                // its full intrinsic width however little the deck had left —
                // and at 2x text scale in Arabic and Hebrew the row ran past
                // the deck (50px and 37px). A Flexible-bounded Wrap caps the
                // pair and lets the count drop under the heading instead of
                // pushing the search off the screen. Nothing is ellipsised at
                // ordinary sizes, and the count never disappears.
                Flexible(
                  child: Wrap(
                    spacing: RestoflowSpacing.sm,
                    runSpacing: RestoflowSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.posMenuHeading,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: kRestoflowInk,
                        ),
                      ),
                      if (itemCount != null)
                        Text(
                          l10n.posMenuItemCount(itemCount!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: kRestoflowInk3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.md),
                // The search never stretches the full deck on a wide screen —
                // a 900px-wide input reads as a banner, not a field.
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ConstrainedBox(
                      // 004: a compact field, not a banner (spec §2: search
                      // ~300 wide, max 520) — quiet beside the food.
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: const _MenuSearchField(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (rail != null) rail!,
        ],
      ),
    );
  }
}

/// A lightweight client-side search field (§6.2) — filters the ALREADY-LOADED
/// menu by name via [searchQueryProvider]. No backend call.
class _MenuSearchField extends ConsumerStatefulWidget {
  const _MenuSearchField();

  @override
  ConsumerState<_MenuSearchField> createState() => _MenuSearchFieldState();
}

class _MenuSearchFieldState extends ConsumerState<_MenuSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasText = _controller.text.isNotEmpty;
    // POS-PREMIUM-VISUAL-POLISH-001: the focus ring wears this terminal's
    // secondary accent (a non-critical highlight by contract).
    final accent = ref.watch(posDeviceAccentColorProvider);
    return SizedBox(
      height: 44,
      child: TextField(
        key: const Key('menu-search-field'),
        controller: _controller,
        textInputAction: TextInputAction.search,
        onChanged: (value) =>
            ref.read(searchQueryProvider.notifier).state = value,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.posMenuSearchHint,
          prefixIcon: const Icon(Icons.search, size: RestoflowIconSizes.md),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close, size: RestoflowIconSizes.sm),
                  tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                  onPressed: () {
                    _controller.clear();
                    ref.read(searchQueryProvider.notifier).state = '';
                    setState(() {});
                  },
                )
              : null,
          // FILLED, not white: inside a white deck a white field has no edge
          // of its own, so it stops reading as an input.
          filled: true,
          fillColor: kPosChipBg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: RestoflowSpacing.md,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            borderSide: const BorderSide(color: kPosInputBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            borderSide: const BorderSide(color: kPosInputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            borderSide: BorderSide(color: accent, width: 2),
          ),
        ),
      ),
    );
  }
}

/// The card's FIXED content zone — the one-baseline name+price row, the
/// fixed description slot, and the 44px action ZONE (006: the zone hosts a
/// 38px VISIBLE bar with 3px transparent insets; the hit box stays 44).
/// Measured at scale 1 (007 raised the image-to-title pad to 10):
/// 10 + ~21 (name/price baseline row) + 2 + 30 (TWO description lines) +
/// 44 (action zone) + 10 = 117; the tightest bucket is textScale 1.6 (one
/// 19px line + a taller row, ~118); at 2x the slot is gone and the row
/// grows to ~35 → 99 — so 122 holds every bucket (scale-bucket coverage in
/// pos_card_polish_006_test A4).
const double kPosMenuCardBodyHeight = 122;

/// The cell height for a card [cellWidth] wide: the INSET 4:3 image band
/// (see [kPosCardImageInset] / [kPosCardImageAspect] in pos_palette.dart)
/// plus the fixed content zone.
double posMenuCardExtent(double cellWidth) =>
    (cellWidth - 2 * kPosCardImageInset) / kPosCardImageAspect +
    kPosCardImageInset +
    kPosMenuCardBodyHeight;

/// POS-VISUAL-REDESIGN-PHASE-1-007 — the ONE resolved grid geometry, derived
/// from the layout mode rather than from a max-extent formula, and shared
/// verbatim by the loaded grid and the loading skeleton so the two can never
/// drift and the menu's arrival cannot make the grid jump.
class PosMenuGridGeometry {
  const PosMenuGridGeometry({
    required this.columns,
    required this.padding,
    required this.spacing,
    required this.cellWidth,
  });

  /// Resolves the geometry for a grid [availableWidth] wide on a device whose
  /// WHOLE viewport is [viewportWidth]×[viewportHeight]. (PERF-110: the
  /// former `.of(availableWidth, availableHeight)` derived the layout class
  /// from the PANE — the exact disagreement POS-PHASE1-FOLLOWUP-008 removed —
  /// and had no callers; the viewport-based rule is now the only one.)
  factory PosMenuGridGeometry.forViewport({
    required double availableWidth,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    final compact = posCompactDensityFor(
      width: viewportWidth,
      height: viewportHeight,
    );
    final padding = compact ? 12.0 : RestoflowSpacing.lg;
    // 007 FRAMELESS: with the card box gone, the GAP is what separates
    // products — one step wider (14) on roomy modes; compact keeps 10.
    final spacing = compact ? 10.0 : 14.0;
    final columns = posMenuColumnsForViewport(
      width: viewportWidth,
      height: viewportHeight,
    );
    final content = availableWidth - 2 * padding;
    return PosMenuGridGeometry(
      columns: columns,
      padding: padding,
      spacing: spacing,
      cellWidth: (content - (columns - 1) * spacing) / columns,
    );
  }

  final int columns;
  final double padding;
  final double spacing;
  final double cellWidth;

  double get mainAxisExtent => posMenuCardExtent(cellWidth);

  SliverGridDelegateWithFixedCrossAxisCount get delegate =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: mainAxisExtent,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      );
}

/// The menu pane's own width is the SCREEN width minus the side cart, so the
/// grid must resolve its mode from the whole viewport rather than from the
/// width it was handed — otherwise a 1440px desktop, whose menu pane is only
/// 1040px wide, would resolve as a small tablet.
PosMenuGridGeometry posMenuGridGeometryOf(
  BuildContext context,
  double availableWidth,
) {
  final size = MediaQuery.sizeOf(context);
  return PosMenuGridGeometry.forViewport(
    availableWidth: availableWidth,
    viewportWidth: size.width,
    viewportHeight: size.height,
  );
}

/// The deck's category-rail placeholder while the menu loads — the same 56px
/// band the real rail occupies, so the deck does not change height when the
/// categories arrive.
class _CategoryRailSkeleton extends StatelessWidget {
  const _CategoryRailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: RestoflowSpacing.lg,
          vertical: RestoflowSpacing.sm,
        ),
        child: Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              const RestoflowSkeleton(
                width: 96,
                height: 40,
                radius: RestoflowRadii.md,
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/// A static skeleton of the chips strip + item grid while the menu loads.
class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();

  @override
  Widget build(BuildContext context) {
    // The chips placeholder now lives in the DECK, so the skeleton is purely
    // the grid — and it computes its cells with the SAME resolved geometry the
    // loaded grid uses, so the placeholders occupy exactly the space the real
    // cards will and nothing shifts when the menu resolves.
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = posMenuGridGeometryOf(context, constraints.maxWidth);
        return GridView.builder(
          padding: EdgeInsets.all(geometry.padding),
          gridDelegate: geometry.delegate,
          itemCount: 8,
          itemBuilder: (_, _) => RestoflowSkeleton(
            height: geometry.mainAxisExtent,
            radius: kPosCardRadius,
          ),
        );
      },
    );
  }
}

class _MenuLoadError extends StatelessWidget {
  const _MenuLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RestoflowStateView(
      icon: Icons.cloud_off_outlined,
      tone: RestoflowTone.danger,
      message: l10n.posMenuLoadError,
      actions: [
        FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.authTryAgain),
        ),
      ],
    );
  }
}

/// [POS-OFFLINE-OPERATIONS-002] — the SETUP-REQUIRED state: the menu fetch
/// failed AND no operational snapshot exists for this till's scope, so there
/// is nothing safe to sell from until it has been online once. WARNING tone,
/// not danger: nothing is broken — the till is simply not bootstrapped yet —
/// and the retry reuses the same invalidate idiom as the ordinary load error.
class _OfflineSetupRequired extends StatelessWidget {
  const _OfflineSetupRequired({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RestoflowStateView(
      icon: Icons.cloud_off_outlined,
      tone: RestoflowTone.warning,
      title: l10n.posOfflineSetupRequiredTitle,
      message: l10n.posOfflineSetupRequiredBody,
      actions: [
        FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.authTryAgain),
        ),
      ],
    );
  }
}

class _MenuGrid extends ConsumerWidget {
  const _MenuGrid({required this.menu, required this.stripCompact});

  final PosMenuData menu;

  /// Forwarded to the in-scroll [OpenOrdersStrip] (017): the pane resolves
  /// the compact flag once from the viewport, same as before.
  final bool stripCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    // PILOT-OPERATIONS-CORRECTIONS-001: the deliberate availability-management
    // action is shown ONLY to an operator the SERVER says holds
    // manage_menu_availability (unknown => hidden; the server enforces anyway).
    // PERF-110: a bool select — the capability envelope re-emits for many
    // unrelated reasons; the grid only cares about this one flag.
    final canManageAvailability = ref.watch(
      staffCapabilitiesProvider.select(
        (caps) => caps.valueOrNull?.manageMenuAvailability ?? false,
      ),
    );
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final query = ref.watch(searchQueryProvider);
    final items = filterMenuItems(menu.items, selectedCategory, query);

    // PSC-001C cart-safety: while a frozen addition attempt owns the cart the
    // add gestures are DISABLED (the controller refuses the mutation
    // regardless; the cart banner explains the pending/refresh state).
    //
    // PERF-110: the grid used to watch the WHOLE cart state (no value
    // equality) — every add/remove/note/quantity change rebuilt every visible
    // product card. Now the grid selects only the lock flag; each card's
    // in-cart badge selects its OWN quantity (`_inCartQuantityOf`), so an add
    // rebuilds exactly the card whose count changed.
    final cartLocked = ref.watch(
      cartControllerProvider.select((c) => c.lockedByAddition),
    );

    if (menu.items.isEmpty) {
      // 017: no vertical scroll here either — the strip keeps its fixed spot
      // above the state view (and renders nothing when no order is open).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenOrdersStrip(compact: stripCompact),
          Expanded(
            child: RestoflowStateView(
              icon: Icons.restaurant_menu_outlined,
              title: l10n.posMenuEmptyTitle,
              message: l10n.posMenuEmptyBody,
            ),
          ),
        ],
      );
    }
    // POS-PREMIUM-VISUAL-POLISH-001: this terminal's secondary accent, for
    // the add button's interaction layer (hover/press wash + focus ring).
    final accent = ref.watch(posDeviceAccentColorProvider);
    // The category rail now lives in the deck (`_MenuPane`); the grid is only
    // the merchandise plane.
    final Widget grid = items.isEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 017: the no-results state has no vertical scroll — fixed strip.
              OpenOrdersStrip(compact: stripCompact),
              Expanded(
                child: RestoflowStateView(
                  icon: Icons.search_off_outlined,
                  title: l10n.posSearchNoResults,
                ),
              ),
            ],
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              // The approved column count for the resolved layout mode —
              // a fixed 4:3 image band + the fixed card body fit exactly.
              final geometry = posMenuGridGeometryOf(
                context,
                constraints.maxWidth,
              );
              // 017: the strip + grid share ONE vertical scroll — the strip
              // is the first, non-pinned sliver and scrolls away naturally.
              return _MenuScrollBody(
                stripCompact: stripCompact,
                gridPadding: EdgeInsets.all(geometry.padding),
                gridDelegate: geometry.delegate,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final groups = menu.groupsForItem(item.id);
                  // Entrance stagger + tap bump are paint-only (opacity /
                  // transform): the grid's measured geometry, the card's keys
                  // and every tap target are untouched, and both render the
                  // final state immediately under reduced motion.
                  return Consumer(
                    builder: (context, ref, _) {
                      // PERF-110: this card's badge count only.
                      final inCartQuantity = ref.watch(
                        cartControllerProvider.select(
                          (c) => _inCartQuantityOf(c, item.id),
                        ),
                      );
                      return PosEntrance(
                        index: index,
                        child: PosTapBump(
                          enabled: !cartLocked && !item.isUnavailable,
                          child: MenuItemCard(
                            item: item,
                            category: menu.categoryOf(item.categoryId),
                            currencyCode: menu.currencyCode,
                            optionGroupCount: groups.length,
                            inCartQuantity: inCartQuantity,
                            interactionAccent: accent,
                            onManageAvailability: canManageAvailability
                                ? () => MenuAvailabilitySheet.show(
                                    context,
                                    item: item,
                                  )
                                : null,
                            onAdd: cartLocked
                                ? null
                                : groups.isEmpty
                                ? () {
                                    // Celebrate ONLY an APPLIED mutation: if the
                                    // addition freeze lands between frame build
                                    // and tap, the controller refuses — no fly
                                    // ghost, no "added" toast for a refused add.
                                    if (controller.addItem(item) ==
                                        CartMutationResult.applied) {
                                      _celebrateAdd(
                                        context,
                                        l10n,
                                        item.name,
                                        accent,
                                      );
                                    }
                                  }
                                : () => ModifierSelectionSheet.show(
                                    context,
                                    item: item,
                                    groups: groups,
                                    currencyCode: menu.currencyCode,
                                    category: menu.categoryOf(item.categoryId),
                                    // POS-QUICK-NOTES-124: the ACTIVE menu's
                                    // presets. Empty on a backend without the
                                    // feature — the sheet then renders exactly
                                    // as it did before.
                                    quickNotes: menu.quickNotePresets,
                                    onConfirm: (selections, note, quantity) {
                                      if (controller.addItemWithModifiers(
                                            item,
                                            selections,
                                            note: note,
                                            quantity: quantity,
                                          ) ==
                                          CartMutationResult.applied) {
                                        _celebrateAdd(
                                          context,
                                          l10n,
                                          item.name,
                                          accent,
                                        );
                                      }
                                    },
                                  ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );

    // [POS-OFFLINE-OPERATIONS-002] The slim offline banner sits ABOVE the
    // merchandise, on the same warm canvas, ONLY while the menu being sold
    // from is the durable snapshot (phase == offlineCached). No full-screen
    // treatment: the cache exists precisely so the cashier keeps the ordinary
    // grid. The lead line names the mode; the body names the data's age from
    // the snapshot's server fetch time (locale-formatted, never hand-rolled).
    // SURGERY-003: the grid sits directly on the white workspace surface;
    // the ivory canvas (the ambience) lives in the shell gutters around it.
    // PERF-110: the grid selects ONLY the phase bit. The 25-second reconnect
    // probe flips `probing` and `snapshotFetchedAt` on every tick — those now
    // rebuild the slim banner alone (`_OfflineCachedBanner`), never the
    // product grid.
    final offlineCached = ref.watch(
      posOfflineModeProvider.select(
        (o) => o.phase == PosOfflinePhase.offlineCached,
      ),
    );
    if (!offlineCached) {
      return grid;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OfflineCachedBanner(),
        Expanded(child: grid),
      ],
    );
  }

  /// PERF-110: the quantity of [itemId] currently in the cart (the card's
  /// badge). Summed per card on demand — lines are few, cards are many, and
  /// selecting an int means only the touched card rebuilds.
  static int _inCartQuantityOf(CartViewState cart, String itemId) {
    var total = 0;
    for (final line in cart.lines) {
      if (line.menuItemId == itemId) total += line.quantity;
    }
    return total;
  }

  /// POS-PREMIUM-VISUAL-POLISH-001: the add celebration — a FLIP ghost flying
  /// from the tapped card to the cart glyph, plus (phones only, where the
  /// cart itself is off-screen) a spring toast naming what was added. Both
  /// are fire-and-forget, finite, and reduced-motion-aware; the add already
  /// happened through the ordinary controller path either way.
  static void _celebrateAdd(
    BuildContext cardContext,
    AppLocalizations l10n,
    String itemName,
    Color accent,
  ) {
    if (!cardContext.mounted) return;
    posFlyToCart(cardContext, color: accent);
    final size = MediaQuery.sizeOf(cardContext);
    // PERF-110: the toast exists because the cart is OFF-SCREEN — that is the
    // single-pane posture (phones AND portrait tablets), not the phone band.
    final cartOffScreen =
        posShellPostureFor(width: size.width, height: size.height) ==
        PosShellPosture.singlePane;
    if (cartOffScreen) {
      showPosSpringToast(
        cardContext,
        message: l10n.posItemAddedToast(itemName),
        icon: Icons.add_shopping_cart,
        accent: accent,
      );
    }
  }

  /// The locale-formatted moment the served snapshot was fetched: the time of
  /// day when it was saved today, otherwise the (medium) date — both through
  /// [MaterialLocalizations], so ar/he/en each read their own convention.
  static String _snapshotAgeLabel(BuildContext context, DateTime fetchedAt) {
    final local = fetchedAt.toLocal();
    final now = DateTime.now();
    final material = MaterialLocalizations.of(context);
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay
        ? material.formatTimeOfDay(TimeOfDay.fromDateTime(local))
        : material.formatMediumDate(local);
  }
}

/// [POS-OFFLINE-OPERATIONS-002] The slim offline banner that sits ABOVE the
/// merchandise ONLY while the menu being sold from is the durable snapshot
/// (phase == offlineCached). PERF-110 moved it into its own consumer so the
/// reconnect probe's `probing` / `snapshotFetchedAt` flips repaint THIS strip
/// only — the product grid below never hears about them.
class _OfflineCachedBanner extends ConsumerWidget {
  const _OfflineCachedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final offline = ref.watch(
      posOfflineModeProvider.select(
        (o) => (probing: o.probing, fetchedAt: o.snapshotFetchedAt),
      ),
    );
    final fetchedAt = offline.fetchedAt;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
        RestoflowSpacing.lg,
        0,
      ),
      child: RestoflowNoticeBanner(
        key: const Key('pos-offline-banner'),
        tone: RestoflowTone.warning,
        icon: Icons.cloud_off_outlined,
        title: fetchedAt == null ? null : l10n.posOfflineModeBanner,
        // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] While a
        // reconnect PROBE's fetch is in flight the body says so, then
        // reverts to the snapshot age when that attempt lands (each
        // `record*` outcome clears `probing`). The PHASE is untouched, so
        // this is honest: the POS is still offline and every server-backed
        // action stays refused until a fetch genuinely succeeds. The
        // banner's key is unchanged so nothing keyed on it moves.
        body: offline.probing
            ? l10n.posOfflineBannerReconnecting
            : fetchedAt == null
            ? l10n.posOfflineModeBanner
            : l10n.posOfflineDataAge(
                _MenuGrid._snapshotAgeLabel(context, fetchedAt),
              ),
      ),
    );
  }
}

/// POS-OPEN-ORDERS-SCROLL-POLISH-017 — the merchandise scroll view with the
/// open-orders strip as its FIRST, NON-PINNED element: the strip scrolls away
/// naturally with the products and returns when the cashier scrolls back to
/// the top. Never sticky, never floating; the strip's own horizontal card
/// list is untouched (a horizontal scrollable inside a vertical one competes
/// with nothing). Geometry parity with the old `GridView.builder`: the same
/// grid delegate and the same all-round padding, now as a padded sliver.
///
/// This widget also owns the ONE piece of scroll bookkeeping the arrangement
/// needs. The band's height is COUNT-INDEPENDENT (a fixed 74/90dp × bounded
/// text scale, see [OpenOrdersStrip]), so ordinary realtime updates (N→M
/// cards, status repaints) never change the leading extent. Only the band's
/// mount (0→N open orders) or unmount (N→0) does — and if that lands while
/// the cashier is scrolled into the grid, the content under their finger
/// would visibly shift by the band height. The fix: compensate the scroll
/// offset by that known height in the same frame, so the viewport stays
/// visually stationary (acceptance: a realtime update while the strip is
/// off-screen must NOT jump the user's scroll position). At the very top
/// (offset 0) no compensation runs — the strip simply appears in place.
class _MenuScrollBody extends ConsumerStatefulWidget {
  const _MenuScrollBody({
    required this.stripCompact,
    required this.gridPadding,
    required this.gridDelegate,
    required this.itemCount,
    required this.itemBuilder,
  });

  final bool stripCompact;
  final EdgeInsetsGeometry gridPadding;
  final SliverGridDelegate gridDelegate;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  ConsumerState<_MenuScrollBody> createState() => _MenuScrollBodyState();
}

class _MenuScrollBodyState extends ConsumerState<_MenuScrollBody> {
  final ScrollController _controller = ScrollController();
  bool? _hadOpenOrders;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The strip's deterministic band height — mirrors [OpenOrdersStrip.build]
  /// (74/90 by the compact flag, grown with the bounded text scale).
  double _bandHeight(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return (widget.stripCompact ? 74.0 : 90.0) * textScale.clamp(1.0, 1.5);
  }

  @override
  Widget build(BuildContext context) {
    // Band PRESENCE, by the strip's own canonical predicate — watched here
    // ONLY to keep the viewport stationary across the band's mount/unmount
    // while scrolled. Membership stays entirely the strip's business.
    final hasOpenOrders = ref.watch(
      posRecentOrdersControllerProvider.select(
        (orders) => orders.any((o) => sectionContains(PosOrderSection.open, o)),
      ),
    );
    final had = _hadOpenOrders;
    if (had != null &&
        had != hasOpenOrders &&
        _controller.hasClients &&
        _controller.offset > 0) {
      final target =
          _controller.offset + (hasOpenOrders ? 1 : -1) * _bandHeight(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpTo(
          target
              .clamp(
                _controller.position.minScrollExtent,
                _controller.position.maxScrollExtent,
              )
              .toDouble(),
        );
      });
    }
    _hadOpenOrders = hasOpenOrders;

    // Keys: the scroll viewport + the product sliver keep stable handles for
    // the layout/responsive contracts that used to pin `GridView` directly.
    return CustomScrollView(
      key: const Key('pos-menu-scroll'),
      controller: _controller,
      slivers: [
        SliverToBoxAdapter(
          child: OpenOrdersStrip(compact: widget.stripCompact),
        ),
        SliverPadding(
          padding: widget.gridPadding,
          sliver: SliverGrid(
            key: const Key('pos-product-grid'),
            gridDelegate: widget.gridDelegate,
            delegate: SliverChildBuilderDelegate(
              widget.itemBuilder,
              childCount: widget.itemCount,
            ),
          ),
        ),
      ],
    );
  }
}

// (SURGERY-003 removed the ambient grid washes: the ivory canvas now lives
// in the shell gutters AROUND the floating white surfaces, which carries the
// warmth without painting under merchandise.)
