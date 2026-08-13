import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'design/pos_motion.dart';
import 'design/pos_visual_tokens.dart';
import 'pos_palette.dart';
import 'state/cart_controller.dart';
import 'state/discount_controller.dart' show staffCapabilitiesProvider;
import 'state/menu_filter.dart';
import 'state/pos_device_accent.dart';
import 'state/pos_menu_provider.dart';
import 'state/pos_offline_state.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      // POS-PREMIUM-VISUAL-POLISH-001: the menu canvas is the one warm note
      // on the screen (ivory — restaurant, not SaaS). Controls stay on the
      // white deck and cool fills; the cart paints its own white plane.
      backgroundColor: kPosIvorySurface,
      // POS-DESIGN-HANDOFF-IMPLEMENTATION-004 — the approved CONNECTED brand
      // navbar (component specs §8): one full-bleed primary bar carrying the
      // white brand tile, the centered restaurant-identity chip and the
      // action cluster on a translucent bed. Same five action widgets, same
      // order, same behaviors — only the clothing changed.
      appBar: AppBar(
        backgroundColor: PosThemePair.of(context).primary,
        surfaceTintColor: PosThemePair.of(context).primary,
        scrolledUnderElevation: 0,
        toolbarHeight: _posTopBarHeight(MediaQuery.sizeOf(context).width),
        // POS-CUSTOM-DEVICE-THEME-010: the navbar chrome ink rides the pair —
        // byte-identical kPosNavbarInk on every preset, a derived dark ink
        // when a CUSTOM pair picks a light primary bar.
        iconTheme: IconThemeData(color: PosThemePair.of(context).navInk),
        actionsIconTheme: IconThemeData(color: PosThemePair.of(context).navInk),
        titleSpacing: RestoflowSpacing.lg,
        title: Row(
          children: [
            // The brand tile — WHITE with the action-colored POS mark (v4),
            // always visible, every width.
            Container(
              key: const Key('pos-brand-tile'),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.point_of_sale,
                color: PosThemePair.of(context).action,
                size: RestoflowIconSizes.md,
              ),
            ),
            // PSC-001A compact app bar: on narrow phones the TEXT brand yields
            // its width to the five operational actions (the brand tile keeps
            // the identity); wider bars carry the STACKED wordmark
            // (POS-THEME-NAVBAR-POLISH-001): the brand name over a smaller
            // product line, deliberate and uncrowded.
            if (MediaQuery.sizeOf(context).width >= kPosCompactAppBarWidth) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.posBrandName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        height: 1.1,
                        color: PosThemePair.of(context).onPrimary,
                      ),
                    ),
                    Text(
                      l10n.posBrandTagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                        height: 1.2,
                        letterSpacing: 0,
                        color: PosThemePair.of(context).actionSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // POS-TOPBAR-RESTAURANT-IDENTITY-009: the connected restaurant's
            // identity fills the empty middle. `Expanded` is what makes this
            // safe — the identity can only ever use the space the left block
            // and the actions did NOT take, so it cannot overlap either, at
            // any width or in either text direction. The left block above is
            // unchanged and keeps its natural size.
            const Expanded(child: PosIdentityTitle()),
          ],
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
              final mode = posLayoutModeFor(
                width: viewport.width,
                height: viewport.height,
              );

              if (mode == PosLayoutMode.phone) {
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

              final compact = mode == PosLayoutMode.compactLandscape;
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
                      width: posCartWidthFor(mode),
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

/// The top-bar height ladder. POS-THEME-NAVBAR-POLISH-001 raises it a step
/// (68 / 62 / 56) so the stacked brand and the identity chip breathe; the
/// action cluster's 5px vertical margins keep every action ≥46dp tall.
double _posTopBarHeight(double width) => width >= 1100
    ? 68
    : width >= RestoflowBreakpoints.posTwoPane
    ? 62
    : 56;

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
    final compactStrip =
        posLayoutModeFor(width: viewport.width, height: viewport.height) ==
        PosLayoutMode.compactLandscape;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MenuDeck(
          itemCount: menu?.items.length,
          rail: menuAsync.isLoading ? const _CategoryRailSkeleton() : rail,
        ),
        // POS-OPEN-ORDERS-STRIP-011: every currently-open order, one tap from
        // its existing detail/actions surface. Renders NOTHING when no order
        // is open, sits above every menu state (grid/skeleton/error), and
        // never changes the grid's own geometry (width-driven only).
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
            data: (menu) => _MenuGrid(menu: menu),
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

  /// Resolves the geometry for the [availableWidth] the grid is given.
  factory PosMenuGridGeometry.of(
    double availableWidth,
    double availableHeight,
  ) {
    final mode = posLayoutModeFor(
      width: availableWidth,
      height: availableHeight,
    );
    final compact = mode == PosLayoutMode.compactLandscape;
    final padding = compact ? 12.0 : RestoflowSpacing.lg;
    // 007 FRAMELESS: with the card box gone, the GAP is what separates
    // products — one step wider (14) on roomy modes; compact keeps 10.
    final spacing = compact ? 10.0 : 14.0;
    final columns = posMenuColumnsFor(mode);
    final content = availableWidth - 2 * padding;
    final cellWidth = (content - (columns - 1) * spacing) / columns;
    return PosMenuGridGeometry(
      columns: columns,
      padding: padding,
      spacing: spacing,
      cellWidth: cellWidth,
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
  final mode = posLayoutModeFor(width: size.width, height: size.height);
  final compact = mode == PosLayoutMode.compactLandscape;
  final padding = compact ? 12.0 : RestoflowSpacing.lg;
  // 007: matches PosMenuGridGeometry.of — the gap separates products now.
  final spacing = compact ? 10.0 : 14.0;
  final columns = posMenuColumnsFor(mode);
  final content = availableWidth - 2 * padding;
  return PosMenuGridGeometry(
    columns: columns,
    padding: padding,
    spacing: spacing,
    cellWidth: (content - (columns - 1) * spacing) / columns,
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
  const _MenuGrid({required this.menu});

  final PosMenuData menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    // PILOT-OPERATIONS-CORRECTIONS-001: the deliberate availability-management
    // action is shown ONLY to an operator the SERVER says holds
    // manage_menu_availability (unknown => hidden; the server enforces anyway).
    final canManageAvailability =
        ref
            .watch(staffCapabilitiesProvider)
            .valueOrNull
            ?.manageMenuAvailability ??
        false;
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final query = ref.watch(searchQueryProvider);
    final items = filterMenuItems(menu.items, selectedCategory, query);

    // In-cart quantities per item id (presentation only — for the card badge).
    final cart = ref.watch(cartControllerProvider);
    final inCart = <String, int>{};
    for (final line in cart.lines) {
      inCart[line.menuItemId] = (inCart[line.menuItemId] ?? 0) + line.quantity;
    }
    // PSC-001C cart-safety: while a frozen addition attempt owns the cart the
    // add gestures are DISABLED (the controller refuses the mutation
    // regardless; the cart banner explains the pending/refresh state).
    final cartLocked = cart.lockedByAddition;

    if (menu.items.isEmpty) {
      return RestoflowStateView(
        icon: Icons.restaurant_menu_outlined,
        title: l10n.posMenuEmptyTitle,
        message: l10n.posMenuEmptyBody,
      );
    }
    // POS-PREMIUM-VISUAL-POLISH-001: this terminal's secondary accent, for
    // the add button's interaction layer (hover/press wash + focus ring).
    final accent = ref.watch(posDeviceAccentColorProvider);
    // The category rail now lives in the deck (`_MenuPane`); the grid is only
    // the merchandise plane.
    final Widget grid = items.isEmpty
        ? RestoflowStateView(
            icon: Icons.search_off_outlined,
            title: l10n.posSearchNoResults,
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              // The approved column count for the resolved layout mode —
              // a fixed 4:3 image band + the fixed card body fit exactly.
              final geometry = posMenuGridGeometryOf(
                context,
                constraints.maxWidth,
              );
              return GridView.builder(
                padding: EdgeInsets.all(geometry.padding),
                gridDelegate: geometry.delegate,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final groups = menu.groupsForItem(item.id);
                  // Entrance stagger + tap bump are paint-only (opacity /
                  // transform): the grid's measured geometry, the card's keys
                  // and every tap target are untouched, and both render the
                  // final state immediately under reduced motion.
                  return PosEntrance(
                    index: index,
                    child: PosTapBump(
                      enabled: !cartLocked && !item.isUnavailable,
                      child: MenuItemCard(
                        item: item,
                        category: menu.categoryOf(item.categoryId),
                        currencyCode: menu.currencyCode,
                        optionGroupCount: groups.length,
                        inCartQuantity: inCart[item.id] ?? 0,
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

    // [POS-OFFLINE-OPERATIONS-002] The slim offline banner sits ABOVE the
    // merchandise, on the same warm canvas, ONLY while the menu being sold
    // from is the durable snapshot (phase == offlineCached). No full-screen
    // treatment: the cache exists precisely so the cashier keeps the ordinary
    // grid. The lead line names the mode; the body names the data's age from
    // the snapshot's server fetch time (locale-formatted, never hand-rolled).
    // SURGERY-003: the grid sits directly on the white workspace surface;
    // the ivory canvas (the ambience) lives in the shell gutters around it.
    final offline = ref.watch(posOfflineModeProvider);
    if (offline.phase != PosOfflinePhase.offlineCached) {
      return grid;
    }
    final fetchedAt = offline.snapshotFetchedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
                : l10n.posOfflineDataAge(_snapshotAgeLabel(context, fetchedAt)),
          ),
        ),
        Expanded(child: grid),
      ],
    );
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
    final phone =
        posLayoutModeFor(width: size.width, height: size.height) ==
        PosLayoutMode.phone;
    if (phone) {
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

// (SURGERY-003 removed the ambient grid washes: the ivory canvas now lives
// in the shell gutters AROUND the floating white surfaces, which carries the
// warmth without painting under merchandise.)
