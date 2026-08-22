import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_appearance.dart';
import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';

/// Shared V2 chrome: the fixed 1080×1920 stage, glass surfaces, pills, the
/// brand badge, the language capsule and the accent underline — the pieces
/// that repeat identically on attract, service and menu per the design lock.

/// Uniform-scale stage. All layout inside is authored in the canonical
/// 1080×1920 design space; the stage letterboxes into whatever portrait
/// viewport it gets (FittedBox.contain preserves the approved composition
/// instead of reflowing into a generic responsive page). Pointer events are
/// transformed by the render tree, so children receive design-space
/// coordinates — gesture math needs no manual zoom factor.
class KioskStage extends StatelessWidget {
  const KioskStage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF05080F),
    child: SafeArea(
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: kioskDesignSize,
            // Transparent Material: text fields/ink need a Material ancestor;
            // the kiosk paints every surface itself.
            child: Material(
              type: MaterialType.transparency,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [KioskColors.canvasTop, KioskColors.canvasBottom],
                  ),
                ),
                child: Stack(
                  children: [
                    // V2 canvas depth: navy bloom top-end + faint ember floor.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(.64, -.92),
                              radius: 1.0,
                              colors: [
                                KioskColors.canvasGlow,
                                KioskColors.canvasGlow.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(-.84, 1.0),
                              radius: 1.1,
                              colors: [
                                KioskColors.ring.withValues(alpha: .09),
                                KioskColors.ring.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Fixture image with the kiosk's no-broken-image guarantee: a null asset or
/// a failed decode renders [fallback] instead of an exception (V2 rule; also
/// keeps widget tests portable when the asset bundle is unavailable).
class KioskFixtureImage extends StatelessWidget {
  const KioskFixtureImage({
    super.key,
    required this.asset,
    required this.fallback,
    this.fit = BoxFit.cover,
  });
  final String? asset;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => asset == null
      ? fallback
      : Image.asset(asset!, fit: fit, errorBuilder: (_, _, _) => fallback);
}

/// Product photo with the same no-broken-image guarantee, now for LIVE menus
/// (KIOSK-001-PREREQ-083): a resolved short-lived signed [url] renders with a
/// V2-consistent fade-in over [fallback]; no URL falls back to the fixture
/// [asset] path (demo mode), and a live no-photo/failed-photo state lands on
/// [fallback] (the approved dark image well carrying the item name). Photos
/// are an enhancement, never load-bearing.
///
/// KIOSK-001-PREREQ-086: a fixture ASSET that fails to load renders
/// [assetErrorFallback] — the pre-083 PLAIN dark well, deliberately without
/// the item name (the card/sheet already shows it once; a name-bearing well
/// here would duplicate the label, which is exactly what the repo-root CI
/// environment surfaced). The premium name-well stays reserved for the LIVE
/// no-photo cases.
class KioskMenuImage extends StatelessWidget {
  const KioskMenuImage({
    super.key,
    this.url,
    this.asset,
    required this.fallback,
    this.assetErrorFallback,
    this.fit = BoxFit.cover,
  });
  final String? url;
  final String? asset;
  final Widget fallback;

  /// Rendered when [asset] itself fails to load (never for live URLs).
  /// Defaults to [fallback] when not provided.
  final Widget? assetErrorFallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null) {
      if (asset == null) return fallback;
      return KioskFixtureImage(
        asset: asset,
        fallback: assetErrorFallback ?? fallback,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        Image.network(
          url,
          fit: fit,
          // A dead/expired URL quietly leaves the well visible underneath.
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
          frameBuilder: (context, child, frame, wasSync) => wasSync
              ? child
              : AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: KioskMotion.screenFade,
                  curve: KioskMotion.curve,
                  child: child,
                ),
        ),
      ],
    );
  }
}

/// Press feedback: V2 `style-active="transform:scale(.97)"`.
class KioskPressable extends StatefulWidget {
  const KioskPressable({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.pressedScale = .97,
  });
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double pressedScale;

  @override
  State<KioskPressable> createState() => _KioskPressableState();
}

class _KioskPressableState extends State<KioskPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
    onTapCancel: () => setState(() => _down = false),
    onTapUp: (_) => setState(() => _down = false),
    onTap: widget.enabled ? widget.onTap : null,
    child: AnimatedScale(
      scale: _down ? widget.pressedScale : 1,
      duration: KioskMotion.pressFeedback,
      child: widget.child,
    ),
  );
}

/// Glass panel (V2: white 5–7% fill, 10–22% border, blur behind).
class KioskGlass extends StatelessWidget {
  const KioskGlass({
    super.key,
    required this.child,
    this.fillOpacity = .05,
    this.borderOpacity = .11,
    this.borderWidth = 1.5,
    this.radius = 26,
    this.padding = EdgeInsets.zero,
    this.color,
  });
  final Widget child;
  final double fillOpacity;
  final double borderOpacity;
  final double borderWidth;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? KioskColors.glass(fillOpacity),
      border: Border.all(
        color: KioskColors.glass(borderOpacity),
        width: borderWidth,
      ),
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}

/// KIOSK-001-102: true when [text] should use the Latin display face
/// (Anton). Arabic/Hebrew wordmarks get Rubik 900 with zero letter-spacing —
/// forcing Anton onto RTL text is a typography bug, not a style choice.
bool kioskLatinDisplayFits(String text) => !RegExp(r'[֐-׿؀-ۿ]').hasMatch(text);

/// Display style for a BRAND wordmark segment (auto per script).
TextStyle kioskBrandTitleStyle(
  String text,
  double size, {
  required Color color,
  double height = 1,
}) {
  final latin = kioskLatinDisplayFits(text);
  return TextStyle(
    fontFamily: latin ? KioskType.latinDisplayFamily : KioskType.family,
    fontWeight: latin ? FontWeight.w400 : FontWeight.w900,
    letterSpacing: latin ? 1 : 0,
    fontSize: size,
    height: height,
    color: color,
  );
}

/// The rotated circular brand badge (attract 118px, inner screens 104px).
///
/// KIOSK-001-102: appearance-driven — a device-local logo override renders
/// inside the orange V2 ring; otherwise the editable wordmark (primary +
/// accent segments in their configured colors) over the restaurant display
/// name; a logo-less, text-less identity falls back to an elegant monogram.
/// Demo defaults reproduce the Phase-1 EMBER badge byte for byte.
class KioskBrandBadge extends ConsumerWidget {
  const KioskBrandBadge({super.key, this.size = 104});
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(kioskAppearanceProvider);
    final wordmarkSize = size * (27 / 104);
    final subSize = size * (8.5 / 104);
    final logo = appearance.logoOverrideBytes;
    final primary = appearance.brandTitlePrimary;
    final Widget inner;
    if (logo != null) {
      inner = ClipOval(
        child: Image.memory(
          logo,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              appearance.monogram,
              style: kioskBrandTitleStyle(
                appearance.monogram,
                wordmarkSize,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    } else if (primary.isNotEmpty &&
        (primary + appearance.brandTitleAccent).characters.length <= 7) {
      // The full wordmark only fits the small ring for short brands (the V2
      // fixture "EMBER." shape). Longer wordmarks fall through to the
      // monogram instead of clipping mid-word.
      inner = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * (10 / 104)),
            child: Text.rich(
              TextSpan(
                text: primary,
                style: kioskBrandTitleStyle(
                  primary,
                  wordmarkSize,
                  color: appearance.brandPrimaryColor,
                ),
                children: [
                  if (appearance.brandTitleAccent.isNotEmpty)
                    TextSpan(
                      text: appearance.brandTitleAccent,
                      style: TextStyle(color: appearance.brandAccentColor),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (appearance.restaurantDisplayName.isNotEmpty) ...[
            SizedBox(height: size * (3 / 104)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: size * (8 / 104)),
              child: Text(
                appearance.restaurantDisplayName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KioskType.body(
                  subSize,
                  FontWeight.w700,
                  color: KioskColors.textSoft,
                  letterSpacing:
                      kioskLatinDisplayFits(appearance.restaurantDisplayName)
                      ? 2
                      : 0,
                ),
              ),
            ),
          ],
        ],
      );
    } else {
      inner = Center(
        child: Text(
          appearance.monogram,
          style: kioskBrandTitleStyle(
            appearance.monogram,
            size * (34 / 104),
            color: Colors.white,
          ),
        ),
      );
    }
    return Transform.rotate(
      angle: -8 * 3.1415926535 / 180,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xB8070E1B),
          border: Border.all(
            color: KioskColors.ring,
            width: size >= 118 ? 3.5 : 3,
          ),
          boxShadow: [
            BoxShadow(
              color: KioskColors.ring.withValues(alpha: .28),
              blurRadius: 30,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: inner,
      ),
    );
  }
}

/// Language capsule — three pills, active carries the orange gradient.
class KioskLanguageCapsule extends StatelessWidget {
  const KioskLanguageCapsule({
    super.key,
    required this.lang,
    required this.onSelect,
    this.pillHeight = 56,
    this.pillMinWidth = 88,
    this.fontSize = 21,
  });
  final String lang;
  final ValueChanged<String> onSelect;
  final double pillHeight;
  final double pillMinWidth;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: KioskColors.glass(.07),
      border: Border.all(color: KioskColors.glass(.14), width: 1.5),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final code in const ['en', 'he', 'ar'])
          KioskPressable(
            onTap: () => onSelect(code),
            child: Container(
              constraints: BoxConstraints(minWidth: pillMinWidth),
              height: pillHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: lang == code ? kioskAccentGradient : null,
                borderRadius: BorderRadius.circular(999),
                boxShadow: lang == code
                    ? [
                        BoxShadow(
                          color: KioskColors.ring.withValues(alpha: .4),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                switch (code) {
                  'en' => 'EN',
                  'he' => 'עברית',
                  _ => 'العربية',
                },
                style: KioskType.body(
                  fontSize,
                  FontWeight.w700,
                  color: lang == code ? Colors.white : KioskColors.textSoft,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Back pill (V2: glass pill, direction-aware arrow).
class KioskBackPill extends StatelessWidget {
  const KioskBackPill({
    super.key,
    required this.onTap,
    this.height = 72,
    this.fontSize = 24,
  });
  final VoidCallback onTap;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return KioskPressable(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 34),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: KioskColors.glass(.06),
          border: Border.all(color: KioskColors.glass(.22), width: 1.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              rtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              size: fontSize + 6,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Text(
              l10n.kioskBack,
              style: KioskType.body(fontSize, FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// The hand-drawn orange underline stroke under display headlines.
class KioskUnderline extends StatelessWidget {
  const KioskUnderline({super.key, this.width = 300, this.strokeWidth = 5});
  final double width;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, 16),
    painter: _UnderlinePainter(strokeWidth),
  );
}

class _UnderlinePainter extends CustomPainter {
  const _UnderlinePainter(this.strokeWidth);
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = KioskColors.ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(4, 11)
      ..cubicTo(size.width * .26, 3, size.width * .53, 15, size.width - 4, 5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_UnderlinePainter oldDelegate) =>
      oldDelegate.strokeWidth != strokeWidth;
}

/// Orange gradient primary pill (CTA).
class KioskAccentPill extends StatelessWidget {
  const KioskAccentPill({
    super.key,
    required this.child,
    this.onTap,
    this.height = 110,
    this.horizontalPadding = 64,
    this.enabled = true,
    this.glow = true,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double height;
  final double horizontalPadding;
  final bool enabled;
  final bool glow;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    enabled: enabled,
    child: Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: enabled ? kioskAccentGradient : null,
        color: enabled ? null : KioskColors.glass(.06),
        borderRadius: BorderRadius.circular(999),
        boxShadow: enabled && glow
            ? [
                BoxShadow(
                  color: KioskColors.ring.withValues(alpha: .4),
                  blurRadius: 44,
                  offset: const Offset(0, 16),
                ),
              ]
            : null,
      ),
      child: child,
    ),
  );
}

/// Localized fixture money text helpers bound to the active language.
extension KioskMoneyText on BuildContext {
  String money(int minor) =>
      kioskFormatMinor(minor, Localizations.localeOf(this).languageCode);
  String moneyDelta(int minor) =>
      kioskFormatDeltaMinor(minor, Localizations.localeOf(this).languageCode);
}
