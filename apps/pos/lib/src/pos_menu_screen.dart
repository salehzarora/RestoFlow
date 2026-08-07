import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'pos_palette.dart';
import 'state/cart_controller.dart';
import 'state/discount_controller.dart' show staffCapabilitiesProvider;
import 'state/menu_filter.dart';
import 'state/pos_menu_provider.dart';
import 'state/pos_offline_state.dart';
import 'widgets/category_chips.dart';
import 'widgets/cart_panel.dart';
import 'widgets/device_settings_menu.dart';
import 'widgets/language_selector.dart';
import 'widgets/menu_availability_sheet.dart';
import 'widgets/menu_item_card.dart';
import 'widgets/modifier_selection_sheet.dart';
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
      backgroundColor: kRestoflowCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: kRestoflowHairline)),
        titleSpacing: RestoflowSpacing.lg,
        title: Row(
          children: [
            // The gradient brand tile (§6.1) — always visible, every width.
            Container(
              key: const Key('pos-brand-tile'),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: kRestoflowBrandGradient,
                borderRadius: BorderRadius.circular(RestoflowRadii.md),
              ),
              child: const Icon(
                Icons.point_of_sale,
                color: Colors.white,
                size: RestoflowIconSizes.md,
              ),
            ),
            // PSC-001A compact app bar: on narrow phones the TEXT title yields
            // its width to the five operational actions (the brand tile keeps
            // the identity); wider bars keep the ellipsizing title.
            if (MediaQuery.sizeOf(context).width >= kPosCompactAppBarWidth) ...[
              const SizedBox(width: RestoflowSpacing.sm),
              Flexible(
                child: Text(
                  l10n.posAppTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: kRestoflowInk,
                  ),
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
        actions: const [
          // PSC-001A: the ready-notification bell leads the action group.
          ReadyNotificationBell(),
          RecentOrdersButton(),
          OutboxStatusIndicator(),
          LanguageSelector(),
          DeviceSettingsMenu(),
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
                return const Column(
                  children: [
                    Expanded(child: _MenuPane()),
                    PosBottomBar(),
                  ],
                );
              }

              final compact = mode == PosLayoutMode.compactLandscape;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: _MenuPane()),
                  SizedBox(
                    width: posCartWidthFor(mode),
                    child: CartPanel(compact: compact),
                  ),
                ],
              );
            },
          ),
          const ReadyAlertOverlay(),
        ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MenuDeck(
          itemCount: menu?.items.length,
          rail: menuAsync.isLoading ? const _CategoryRailSkeleton() : rail,
        ),
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
    return DecoratedBox(
      key: const Key('pos-menu-deck'),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: BorderDirectional(
          bottom: BorderSide(color: kRestoflowHairline),
        ),
        boxShadow: kPosDeckShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.lg,
              RestoflowSpacing.md,
              RestoflowSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                Text(
                  l10n.posMenuHeading,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: kRestoflowInk,
                  ),
                ),
                if (itemCount != null) ...[
                  const SizedBox(width: RestoflowSpacing.sm),
                  Text(
                    l10n.posMenuItemCount(itemCount!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: kRestoflowInk3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(width: RestoflowSpacing.md),
                // The search never stretches the full deck on a wide screen —
                // a 900px-wide input reads as a banner, not a field.
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ConstrainedBox(
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
        ),
      ),
    );
  }
}

/// POS-PRODUCT-DESCRIPTIONS-001 — the ONE grid geometry, shared by the loaded
/// grid and the loading skeleton so the two can never drift apart (a skeleton
/// that is a different height than the cards it stands in for makes the whole
/// grid jump the moment the menu arrives).
///
/// [kPosMenuCardBodyHeight] rose from 104 to 140 to fit up to TWO description
/// lines under the product name.
///
/// MEASURED, not guessed. At the narrowest real cell (173px, a 390px viewport)
/// the body content is 120px in en, ar AND he alike: 12+12 padding, a 20px
/// title line, a 2px gap, a 30px two-line description (bodySmall at height
/// 1.25) and the unchanged 44px price/add row. 140 keeps ~20px of headroom, so
/// a larger accessibility text scale does not immediately clip the price row
/// and the description is not jammed against it. Note that a too-small value
/// would NOT throw: the body uses `spaceBetween`, which quietly compresses
/// rather than overflowing — which is exactly why this number is measured from
/// the rendered content instead of inferred from the absence of an exception.
///
/// Cards stay a FIXED height — no IntrinsicHeight, no variable extents — so the
/// grid keeps scanning cleanly in rows.
const double kPosMenuCardMaxExtent = 230;
const double kPosMenuCardBodyHeight = 140;

/// The cell height for a card [cellWidth] wide: the fixed 4:3 image band plus
/// the card body.
double posMenuCardExtent(double cellWidth) =>
    cellWidth * 3 / 4 + kPosMenuCardBodyHeight;

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
    final spacing = compact ? 10.0 : RestoflowSpacing.md;
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
  final spacing = compact ? 10.0 : RestoflowSpacing.md;
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
                  return MenuItemCard(
                    item: item,
                    category: menu.categoryOf(item.categoryId),
                    currencyCode: menu.currencyCode,
                    optionGroupCount: groups.length,
                    inCartQuantity: inCart[item.id] ?? 0,
                    onManageAvailability: canManageAvailability
                        ? () => MenuAvailabilitySheet.show(context, item: item)
                        : null,
                    onAdd: cartLocked
                        ? null
                        : groups.isEmpty
                        ? () => controller.addItem(item)
                        : () => ModifierSelectionSheet.show(
                            context,
                            item: item,
                            groups: groups,
                            currencyCode: menu.currencyCode,
                            category: menu.categoryOf(item.categoryId),
                            onConfirm: (selections, note, quantity) =>
                                controller.addItemWithModifiers(
                                  item,
                                  selections,
                                  note: note,
                                  quantity: quantity,
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
    final offline = ref.watch(posOfflineModeProvider);
    if (offline.phase != PosOfflinePhase.offlineCached) return grid;
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
