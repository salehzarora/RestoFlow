import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_appearance.dart';
import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../state/kiosk_live_runtime.dart';
import '../state/kiosk_staff_access.dart';
import '../widgets/attract_media_background.dart';
import '../widgets/kiosk_chrome.dart';

/// 01 · Attract / idle — full-bleed cinematic media behind a scrim, brand
/// block, language pills, one glass CTA card and the discreet ••• staff
/// target (triple-tap). The whole screen is a tap target.
///
/// KIOSK-001-102: REAL mode renders a LIVE MENU photo carousel — clear,
/// recognizable product photography with slow Ken-Burns motion and a scrim
/// tuned for text contrast, never a blur; branding (logo badge, wordmark +
/// accent, tagline) comes from the device's appearance settings; the fixture
/// "Now preparing #NNN" chip is gone (it was fabricated data on a real
/// tenant). Demo keeps the Phase-1 fixture photo loop and EMBER identity.
class KioskAttractScreen extends ConsumerStatefulWidget {
  const KioskAttractScreen({super.key});

  @override
  ConsumerState<KioskAttractScreen> createState() => _KioskAttractScreenState();
}

class _KioskAttractScreenState extends ConsumerState<KioskAttractScreen>
    with SingleTickerProviderStateMixin {
  // Lazily created ONLY by the demo fixture branch that animates it.
  // KIOSK-001-103: a nullable backing field (not `late final`) so dispose()
  // never instantiates a ticker on an already-deactivated element when the
  // REAL branches never touched it.
  AnimationController? _kenBurnsController;
  AnimationController get _kenBurns =>
      _kenBurnsController ??= AnimationController(
        vsync: this,
        duration: KioskMotion.kenBurns,
      )..repeat(reverse: true);

  @override
  void dispose() {
    _kenBurnsController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);
    final rtl = state.rtl;
    final appearance = ref.watch(kioskAppearanceProvider);
    final live = ref.watch(kioskLiveProvider);
    // §7 (102) + KIOSK-001-103 §3: the carousel rotates the operator's
    // CURATED hero photos when a selection exists (stored ids mapped to the
    // CURRENT live menu — stale entries skipped, never substituted); an
    // uncurated device keeps the 102 automatic category-diverse pick. All
    // URLs come from the shared signed-URL cache (never signed per frame).
    final carouselUrls = live.menu == null
        ? const <String>[]
        : (appearance.featuredMenuItemIds.isNotEmpty
              ? kioskFeaturedCarouselUrls(
                  live.menu!,
                  live.imageUrls,
                  appearance.featuredMenuItemIds,
                )
              : kioskAttractCarouselUrls(live.menu!, live.imageUrls));
    // Editable copy with honest fallbacks: demo keeps the fixture l10n
    // strings; real collapses an empty tagline instead of faking one.
    final isReal = ref.watch(kioskRealModeProvider);
    final taglineText = appearance.tagline.of(state.lang).isNotEmpty
        ? appearance.tagline.of(state.lang)
        : (isReal ? '' : l10n.kioskTagline);
    // The footer identity: the server session carries no device label, so in
    // REAL mode the owner-set restaurant display name is the honest value
    // ("Kiosk Burger House"), never the null-fallback "Kiosk Kiosk".
    final deviceLabel = isReal
        ? (appearance.restaurantDisplayName.isNotEmpty
              ? appearance.restaurantDisplayName
              : (ref.watch(kioskDeviceContextProvider)?.displayName ?? ''))
        : KioskBrand.deviceLabel;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: controller.startFromAttract,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // KIOSK-001-103 §7: in REAL mode the operator's saved media MODE is
          // the routing authority — curated photo rotation, ONE static custom
          // image (no timer), or ONE looping muted custom video (no photo
          // timer). Each branch is its own widget subtree, so switching modes
          // disposes the previous timer/controller. Demo keeps the fixture
          // attract modes untouched.
          if (isReal)
            switch (appearance.attractMediaMode) {
              KioskAttractMediaMode.selectedMenuPhotos
                  when carouselUrls.isNotEmpty =>
                _LiveAttractCarousel(
                  urls: carouselUrls,
                  holdSeconds: appearance.attractIntervalSeconds,
                ),
              KioskAttractMediaMode.selectedMenuPhotos => ColoredBox(
                color: KioskColors.canvasBottom,
              ),
              KioskAttractMediaMode.customImage => KioskCustomImageBackground(
                mediaRef: appearance.customImageRef,
              ),
              KioskAttractMediaMode.customVideo => KioskCustomVideoBackground(
                mediaRef: appearance.customVideoRef,
              ),
            }
          else
            switch (state.settings.attractMode) {
              KioskAttractMode.photos when carouselUrls.isNotEmpty =>
                _LiveAttractCarousel(
                  urls: carouselUrls,
                  holdSeconds: appearance.attractIntervalSeconds,
                ),
              KioskAttractMode.photos => AnimatedBuilder(
                animation: _kenBurns,
                builder: (context, child) => Transform.scale(
                  scale: 1.03 + .13 * _kenBurns.value,
                  child: child,
                ),
                child: KioskFixtureImage(
                  asset: kioskAttractAssets.first,
                  fallback: ColoredBox(color: KioskColors.canvasBottom),
                ),
              ),
              KioskAttractMode.promo => KioskFixtureImage(
                asset: kioskAttractAssets.last,
                fallback: ColoredBox(color: KioskColors.canvasBottom),
              ),
              KioskAttractMode.video => ColoredBox(
                color: KioskColors.canvasBottom,
                child: Center(
                  child: Opacity(
                    opacity: .75,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: KioskColors.frameLine,
                              width: 5,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 64,
                              color: KioskColors.accentTop,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l10n.kioskSettingsAttractVideo,
                          style: KioskType.body(
                            24,
                            FontWeight.w500,
                            color: KioskColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            },
          // §7 scrim: photo first, cinematic darkening second. The middle
          // band stays nearly open so the meal reads unmistakably as a
          // photo; only the header and CTA floor keep deep contrast.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .30, .62, .90],
                colors: [
                  Color(0xB3060A14),
                  Color(0x21060A14),
                  KioskColors.canvasTint(0x3D / 255),
                  KioskColors.canvasTint(0xE6 / 255),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 56, 56, 48),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const KioskBrandBadge(size: 118),
                        if (taglineText.isNotEmpty) ...[
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 220,
                            child: Transform.rotate(
                              angle: -3 * 3.1415926535 / 180,
                              child: Text(
                                taglineText,
                                style: KioskType.body(
                                  21,
                                  FontWeight.w700,
                                  color: KioskColors.accentTop,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    KioskLanguageCapsule(
                      lang: state.lang,
                      onSelect: controller.setLanguage,
                      pillHeight: 60,
                      pillMinWidth: 100,
                      fontSize: 23,
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // §9: editable wordmark — primary + optionally accented
                      // segment (a dot, a second word) in configurable colors,
                      // auto display face per script (Anton never forced onto
                      // Arabic/Hebrew).
                      if (appearance.brandTitlePrimary.isNotEmpty)
                        Text.rich(
                          TextSpan(
                            text: appearance.brandTitlePrimary,
                            style:
                                kioskBrandTitleStyle(
                                  appearance.brandTitlePrimary,
                                  176,
                                  color: appearance.brandPrimaryColor,
                                  height: .94,
                                ).copyWith(
                                  shadows: const [
                                    Shadow(
                                      color: Color(0x8C000000),
                                      offset: Offset(0, 8),
                                      blurRadius: 60,
                                    ),
                                  ],
                                ),
                            children: [
                              if (appearance.brandTitleAccent.isNotEmpty)
                                TextSpan(
                                  text: appearance.brandTitleAccent,
                                  style: TextStyle(
                                    color: appearance.brandAccentColor,
                                  ),
                                ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (appearance.restaurantDisplayName.isNotEmpty)
                        Text(
                          appearance.restaurantDisplayName.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KioskType.body(
                            44,
                            FontWeight.w800,
                            letterSpacing:
                                kioskLatinDisplayFits(
                                  appearance.restaurantDisplayName,
                                )
                                ? 14
                                : 0,
                            color: Colors.white,
                          ),
                        ),
                      if (taglineText.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          taglineText,
                          textAlign: TextAlign.center,
                          style: KioskType.body(
                            27,
                            FontWeight.w600,
                            color: KioskColors.textSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // CTA glass card.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(48, 50, 48, 44),
                  decoration: BoxDecoration(
                    color: KioskColors.cardGlass,
                    border: Border.all(
                      color: KioskColors.glass(.13),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x8C000000),
                        offset: Offset(0, 40),
                        blurRadius: 90,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        l10n.kioskStart,
                        textAlign: TextAlign.center,
                        style: KioskType.display(rtl, 60),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        l10n.kioskTouchStart,
                        style: KioskType.body(
                          25,
                          FontWeight.w500,
                          color: KioskColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 26),
                      _PulsingStartPill(label: l10n.kioskStart, rtl: rtl),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // §8: the fixture "Now preparing #NNN" chip is DELETED — a
                // real tenant must never advertise a fabricated operational
                // number, and no replacement fake metric takes its place.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Staff target: triple-tap (must NOT start an order).
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: controller.staffTap,
                      child: Container(
                        key: const Key('kiosk-staff-dots'),
                        width: 76,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: KioskColors.glass(.06),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '•••',
                          style: KioskType.body(
                            26,
                            FontWeight.w800,
                            color: KioskColors.textGhost,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.kioskPoweredBy(deviceLabel),
                  style: KioskType.body(
                    18,
                    FontWeight.w500,
                    color: KioskColors.textGhost,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The glowing start pill (V2 kfGlow: a 2.4s expanding orange halo).
class _PulsingStartPill extends StatefulWidget {
  const _PulsingStartPill({required this.label, required this.rtl});
  final String label;
  final bool rtl;

  @override
  State<_PulsingStartPill> createState() => _PulsingStartPillState();
}

class _PulsingStartPillState extends State<_PulsingStartPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _glow,
    builder: (context, child) => Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: KioskColors.ring.withValues(alpha: .5 * (1 - _glow.value)),
            spreadRadius: 30 * _glow.value,
          ),
          BoxShadow(
            color: KioskColors.ring.withValues(alpha: .4),
            blurRadius: 50,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    ),
    child: Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 74),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: kioskAccentGradient,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            style: KioskType.body(
              32,
              FontWeight.w900,
              color: Colors.white,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(width: 18),
          // Rubik carries no arrow glyphs; the icon mirrors with the
          // ambient direction exactly like the artifact's flipped arrow.
          Icon(
            widget.rtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
            size: 38,
            color: Colors.white,
          ),
        ],
      ),
    ),
  );
}

/// KIOSK-001-102 §7 — the LIVE menu-photo attract background.
///
/// A slow cinematic carousel over the pre-resolved signed URLs: each slide
/// holds [holdSeconds], crossfades ~900ms into the next, and runs its own
/// Ken-Burns zoom (1.0 → 1.08 with a gentle pan) for the slide's full life.
/// `BoxFit.cover`, NO blur — the food stays unmistakably recognizable; text
/// contrast comes from the screen's gradient scrim alone. Failed loads fall
/// back to the dark branded canvas (never a broken-image glyph); the timer
/// lives in local state so unrelated rebuilds never restart the motion.
class _LiveAttractCarousel extends StatefulWidget {
  const _LiveAttractCarousel({required this.urls, required this.holdSeconds});
  final List<String> urls;
  final int holdSeconds;

  @override
  State<_LiveAttractCarousel> createState() => _LiveAttractCarouselState();
}

class _LiveAttractCarouselState extends State<_LiveAttractCarousel> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_LiveAttractCarousel old) {
    super.didUpdateWidget(old);
    if (old.holdSeconds != widget.holdSeconds ||
        old.urls.length != widget.urls.length) {
      _index = _index % (widget.urls.isEmpty ? 1 : widget.urls.length);
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    if (widget.urls.length < 2) return;
    _timer = Timer.periodic(Duration(seconds: widget.holdSeconds), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.urls.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.urls[_index % widget.urls.length];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 900),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: _KenBurnsPhoto(
        key: ValueKey(url),
        url: url,
        lifeSeconds: widget.holdSeconds + 1,
      ),
    );
  }
}

class _KenBurnsPhoto extends StatelessWidget {
  const _KenBurnsPhoto({
    super.key,
    required this.url,
    required this.lifeSeconds,
  });
  final String url;
  final int lifeSeconds;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(seconds: lifeSeconds),
    curve: Curves.linear,
    builder: (context, t, child) => ClipRect(
      child: Transform.translate(
        offset: Offset(-14 * t, -10 * t), // subtle pan
        child: Transform.scale(scale: 1.0 + .08 * t, child: child),
      ),
    ),
    child: Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(color: KioskColors.canvasBottom),
    ),
  );
}
