import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/kiosk_chrome.dart';

/// 01 · Attract / idle — full-bleed cinematic media behind a scrim, brand
/// block, language pills, one glass CTA card, the live "Now preparing #NNN"
/// pill and the discreet ••• staff target (triple-tap). The whole screen is
/// a tap target. Media in Phase 1: the fixture Ken-Burns photo loop, a
/// LOCAL placeholder for the promo-image mode, and a placeholder frame for
/// the video mode (real media management arrives with device settings).
class KioskAttractScreen extends ConsumerStatefulWidget {
  const KioskAttractScreen({super.key});

  @override
  ConsumerState<KioskAttractScreen> createState() => _KioskAttractScreenState();
}

class _KioskAttractScreenState extends ConsumerState<KioskAttractScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _kenBurns = AnimationController(
    vsync: this,
    duration: KioskMotion.kenBurns,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _kenBurns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);
    final rtl = state.rtl;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: controller.startFromAttract,
      child: Stack(
        fit: StackFit.expand,
        children: [
          switch (state.settings.attractMode) {
            KioskAttractMode.photos => AnimatedBuilder(
              animation: _kenBurns,
              builder: (context, child) => Transform.scale(
                scale: 1.03 + .13 * _kenBurns.value,
                child: child,
              ),
              child: Image.asset(kioskAttractAssets.first, fit: BoxFit.cover),
            ),
            KioskAttractMode.promo => Image.asset(
              kioskAttractAssets.last,
              fit: BoxFit.cover,
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
                        child: const Center(
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
          // V2 scrim: heavy top, open middle, heavy floor.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .34, .58, .88],
                colors: [
                  Color(0xD9060A14),
                  Color(0x4D060A14),
                  Color(0x73070E1B),
                  Color(0xF2070E1B),
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
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 220,
                          child: Transform.rotate(
                            angle: -3 * 3.1415926535 / 180,
                            child: Text(
                              l10n.kioskTagline,
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
                      Text(
                        '${KioskBrand.wordmark}${KioskBrand.wordmarkSuffix}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontFamily: KioskType.latinDisplayFamily,
                          fontWeight: FontWeight.w400,
                          fontSize: 176,
                          height: .94,
                          color: Colors.white,
                          shadows: const [
                            Shadow(
                              color: Color(0x8C000000),
                              offset: Offset(0, 8),
                              blurRadius: 60,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        KioskBrand.subtitle,
                        textDirection: TextDirection.ltr,
                        style: KioskType.body(
                          44,
                          FontWeight.w800,
                          letterSpacing: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        l10n.kioskTagline,
                        style: KioskType.body(
                          27,
                          FontWeight.w600,
                          color: KioskColors.textSoft,
                        ),
                      ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: KioskColors.glass(.08),
                        border: Border.all(
                          color: KioskColors.glass(.16),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text.rich(
                        TextSpan(
                          text: '${l10n.kioskNowPreparing} ',
                          children: [
                            TextSpan(
                              text:
                                  '#${state.dailySeq.toString().padLeft(3, '0')}',
                              style: const TextStyle(
                                color: KioskColors.accentTop,
                              ),
                            ),
                          ],
                        ),
                        style: KioskType.body(22, FontWeight.w700),
                      ),
                    ),
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
                  l10n.kioskPoweredBy(KioskBrand.deviceLabel),
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
