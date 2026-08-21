import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../data/kiosk_menu_data.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/category_wheel.dart';
import '../widgets/kiosk_chrome.dart';

/// 04 · Menu — the primary visual acceptance screen. Header (brand badge,
/// tagline, language capsule, back pill, display headline + orange stroke,
/// service chip) · the category wheel on the screen's inline-END side
/// (right in AR/HE, mirrored left in EN — Directionality places it) · the
/// two-column product grid that alone scrolls · the fixed bottom action bar
/// (orange cart pill + glass checkout pill carrying the running total).
class KioskMenuScreen extends ConsumerWidget {
  const KioskMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);
    final rtl = state.rtl;
    final menu = ref.watch(kioskMenuDataProvider);
    final status = ref.watch(kioskMenuStatusProvider);
    final hasMenu =
        status == KioskMenuStatus.ready && menu.categories.isNotEmpty;
    final category = hasMenu
        ? menu.categories[state.categoryIndex.clamp(
            0,
            menu.categories.length - 1,
          )]
        : null;
    final serviceBase = switch (state.service) {
      KioskServiceType.dineIn => l10n.kioskDineIn,
      KioskServiceType.takeaway => l10n.kioskTakeaway,
      null => '—',
    };
    final serviceChip = state.selectedTable != null
        ? '$serviceBase · ${state.selectedTable}'
        : serviceBase;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(52, 44, 52, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const KioskBrandBadge(),
                      const SizedBox(width: 18),
                      SizedBox(
                        width: 190,
                        child: Transform.rotate(
                          angle: -3 * 3.1415926535 / 180,
                          child: Text(
                            l10n.kioskTagline,
                            style: KioskType.body(
                              19,
                              FontWeight.w700,
                              color: KioskColors.accentTop,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      KioskLanguageCapsule(
                        lang: state.lang,
                        onSelect: controller.setLanguage,
                        pillHeight: 54,
                        pillMinWidth: 84,
                        fontSize: 20,
                      ),
                      const SizedBox(width: 12),
                      KioskBackPill(
                        onTap: controller.backFromMenu,
                        height: 68,
                        fontSize: 23,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 34),
              Text(
                l10n.kioskMenuTitle,
                style: KioskType.display(rtl, 84, height: 1.02),
              ),
              const SizedBox(height: 10),
              const KioskUnderline(width: 320, strokeWidth: 6),
              const SizedBox(height: 12),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      l10n.kioskTagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KioskType.body(
                        24,
                        FontWeight.w500,
                        color: KioskColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  KioskPressable(
                    onTap: controller.changeService,
                    child: Container(
                      key: const Key('kiosk-service-chip'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: KioskColors.glass(.06),
                        border: Border.all(
                          color: KioskColors.glass(.14),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        serviceChip,
                        style: KioskType.body(
                          20,
                          FontWeight.w700,
                          color: KioskColors.accentTop,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            // V2: the rail is the row's FIRST child under the frame's writing
            // direction — inline-start puts the wheel on the RIGHT in AR/HE
            // and mirrors it to the LEFT in EN, exactly like the artifact.
            padding: const EdgeInsetsDirectional.fromSTEB(30, 10, 30, 0),
            child: !hasMenu
                ? _MenuStatepanel(status: status)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KioskCategoryWheel(
                        categories: menu.categories,
                        activeIndex: state.categoryIndex.clamp(
                          0,
                          menu.categories.length - 1,
                        ),
                        onSelect: controller.setCategoryIndex,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                          child: AnimatedSwitcher(
                            duration: KioskMotion.gridSwap,
                            switchInCurve: KioskMotion.curve,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, .02),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: GridView.builder(
                              key: ValueKey(category!.id),
                              padding: const EdgeInsets.only(bottom: 170),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 24,
                                    crossAxisSpacing: 24,
                                    mainAxisExtent: 536,
                                  ),
                              itemCount: category.items.length,
                              itemBuilder: (context, i) => _ProductCard(
                                item: category.items[i],
                                lang: state.lang,
                                onTap: () =>
                                    controller.openItem(category.items[i].id),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// The V2-styled honest state panel replacing the wheel + grid while the live
/// menu is loading, unreachable, unusable, or genuinely empty. Header, bottom
/// bar and the whole composition stay exactly V2 around it.
class _MenuStatepanel extends StatelessWidget {
  const _MenuStatepanel({required this.status});
  final KioskMenuStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, body) = switch (status) {
      KioskMenuStatus.loading => (l10n.kioskMenuLoadingTitle, ''),
      KioskMenuStatus.reconnect => (
        l10n.kioskReconnectTitle,
        l10n.kioskReconnectBody,
      ),
      KioskMenuStatus.empty => (
        l10n.kioskMenuEmptyTitle,
        l10n.kioskMenuEmptyBody,
      ),
      _ => (l10n.kioskMenuUnavailableTitle, l10n.kioskMenuUnavailableBody),
    };
    return Center(
      child: KioskGlass(
        radius: 36,
        padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == KioskMenuStatus.loading)
              const SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  strokeWidth: 5,
                  color: KioskColors.accentTop,
                ),
              )
            else
              Icon(
                status == KioskMenuStatus.reconnect
                    ? Icons.wifi_off_rounded
                    : Icons.restaurant_menu_rounded,
                size: 84,
                color: KioskColors.textMuted,
              ),
            const SizedBox(height: 34),
            Text(
              title,
              textAlign: TextAlign.center,
              style: KioskType.body(34, FontWeight.w800),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                body,
                textAlign: TextAlign.center,
                style: KioskType.body(
                  24,
                  FontWeight.w500,
                  color: KioskColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.lang,
    required this.onTap,
  });
  final KioskFixtureItem item;
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KioskPressable(
    // A sold-out/unreadable item stays VISIBLE (the customer sees the truth)
    // but never opens the configurator — V2's disabled treatment.
    onTap: item.available ? onTap : null,
    child: Opacity(
      opacity: item.available ? 1 : .45,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [KioskColors.glass(.06), KioskColors.glass(.02)],
          ),
          border: Border.all(color: KioskColors.glass(.1), width: 1.5),
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              offset: Offset(0, 18),
              blurRadius: 44,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo block: 284 tall, radius 22, cover crop; the approved
            // no-photo treatment is the dark image well with the item name.
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 284,
                width: double.infinity,
                child: item.imageAsset != null
                    ? KioskFixtureImage(
                        asset: item.imageAsset,
                        fallback: const ColoredBox(
                          color: KioskColors.imageWell,
                        ),
                      )
                    : ColoredBox(
                        color: KioskColors.imageWell,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              item.name.of(lang),
                              textAlign: TextAlign.center,
                              style: KioskType.body(
                                24,
                                FontWeight.w800,
                                color: KioskColors.textDisabled,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 62,
                    child: Text(
                      item.name.of(lang),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: KioskType.body(28, FontWeight.w800, height: 1.12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.description.of(lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KioskType.body(
                      20,
                      FontWeight.w500,
                      color: KioskColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    kioskFormatMinor(item.basePriceMinor, lang),
                    textDirection: TextDirection.ltr,
                    style: KioskType.body(32, FontWeight.w900),
                  ),
                  if (!item.available)
                    Flexible(
                      child: Container(
                        key: Key('kiosk-item-unavailable-${item.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: KioskColors.glass(.1),
                          border: Border.all(
                            color: KioskColors.glass(.16),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          AppLocalizations.of(
                            context,
                          ).kioskItemUnavailableBadge.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KioskType.body(
                            19,
                            FontWeight.w800,
                            color: KioskColors.textMuted,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: kioskAccentGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: KioskColors.ring.withValues(alpha: .4),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.add, size: 40, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The fixed bottom action bar (rendered by the shell above every menu-level
/// surface): orange Cart pill with the count badge + the glass summary /
/// checkout pill with the running total inside it.
class KioskBottomBar extends ConsumerWidget {
  const KioskBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);
    final rtl = state.rtl;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 26),
      decoration: BoxDecoration(
        color: KioskColors.barGlass,
        border: Border(
          top: BorderSide(color: KioskColors.glass(.09), width: 1.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 95,
            child: KioskPressable(
              onTap: controller.openCart,
              pressedScale: .97,
              child: Container(
                key: const Key('kiosk-cart-pill'),
                height: 118,
                decoration: BoxDecoration(
                  gradient: kioskAccentGradient,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: KioskColors.ring.withValues(alpha: .38),
                      blurRadius: 44,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.shopping_cart_outlined,
                      size: 34,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 18),
                    Text(
                      l10n.kioskCart.toUpperCase(),
                      style: KioskType.body(
                        30,
                        FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    if (state.cartCount > 0) ...[
                      const SizedBox(width: 18),
                      Container(
                        constraints: const BoxConstraints(minWidth: 50),
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0x73070E1B),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${state.cartCount}',
                          textDirection: TextDirection.ltr,
                          style: KioskType.body(
                            25,
                            FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 125,
            child: KioskPressable(
              onTap: state.cart.isEmpty ? null : controller.openCart,
              enabled: state.cart.isNotEmpty,
              child: Opacity(
                opacity: state.cart.isEmpty ? .55 : 1,
                child: Container(
                  key: const Key('kiosk-checkout-pill'),
                  height: 118,
                  decoration: BoxDecoration(
                    color: KioskColors.glass(.05),
                    border: Border.all(
                      color: KioskColors.glass(.18),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: l10n.kioskItemsCount(state.cartCount),
                            ),
                            const TextSpan(text: ' · '),
                            TextSpan(text: context.money(state.cartTotalMinor)),
                          ],
                        ),
                        style: KioskType.body(
                          20,
                          FontWeight.w600,
                          color: KioskColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.kioskCheckout.toUpperCase(),
                            style: KioskType.body(28, FontWeight.w900),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            rtl
                                ? Icons.arrow_back_rounded
                                : Icons.arrow_forward_rounded,
                            size: 30,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
