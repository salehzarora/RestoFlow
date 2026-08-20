import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';

/// KIOSK-001 — the V2 gesture-driven vertical category wheel.
///
/// This is the design's HIGHEST-PRIORITY component and follows the artifact's
/// interaction model exactly (`Kiosk Prototype v2.dc.html`):
///
///  * rows are [KioskWheel.rowExtent] (172) tall; the whole column is
///    translated by `railShift = 550 − activeIndex·172 (+ live drag delta)`;
///  * while the finger drags, the column FOLLOWS it with no animation;
///  * on release the wheel snaps to `round(activeIndex − dragDy/172)`,
///    clamped to the category range, animating 450ms on cubic(.22,.9,.26,1);
///  * disc size / label size / opacity fall off with distance from the
///    active index (150/98/78/64 · 24/20/17 · 1/.78/.5/.32), each disc
///    animating its style change over 400ms;
///  * the active disc carries the 3.5px #F97316 ring, the dual orange glow
///    halo and a navy radial fill;
///  * a tap selects a category ONLY when the gesture moved ≤ 8 design px —
///    farther means it was a drag;
///  * the rail owns ONLY its own vertical gesture region, so it never
///    conflicts with the product grid's scrolling;
///  * in RTL the rail sits on the RIGHT with the arc hugging its outer edge;
///    LTR mirrors the whole assembly (Directionality handles placement, the
///    arc flips).
///
/// Layout inside [KioskStage] is in design pixels, so gesture deltas arrive
/// already scaled — no manual zoom factor (unlike the web artifact's /zoom).
class KioskCategoryWheel extends StatefulWidget {
  const KioskCategoryWheel({
    super.key,
    required this.categories,
    required this.activeIndex,
    required this.onSelect,
    this.height,
  });

  final List<KioskFixtureCategory> categories;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final double? height;

  @override
  State<KioskCategoryWheel> createState() => _KioskCategoryWheelState();
}

class _KioskCategoryWheelState extends State<KioskCategoryWheel> {
  bool _dragging = false;
  double _dragDy = 0;
  bool _moved = false;

  int get _clampedIndex =>
      widget.activeIndex.clamp(0, widget.categories.length - 1);

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _dragDy = 0;
      _moved = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final dy = _dragDy + details.delta.dy;
    if (dy.abs() > KioskWheel.tapSlop) _moved = true;
    setState(() => _dragDy = dy);
  }

  void _onDragEnd(DragEndDetails details) {
    final snapped = (_clampedIndex - _dragDy / KioskWheel.rowExtent)
        .round()
        .clamp(0, widget.categories.length - 1);
    setState(() {
      _dragging = false;
      _dragDy = 0;
    });
    if (snapped != _clampedIndex) widget.onSelect(snapped);
  }

  void _onDiscTap(int index) {
    if (_moved) {
      _moved = false;
      return;
    }
    widget.onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final shift =
        KioskWheel.centerShift -
        _clampedIndex * KioskWheel.rowExtent +
        (_dragging ? _dragDy : 0);

    return SizedBox(
      width: KioskWheel.railWidth,
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The vertical orange arc hugging the rail's outer edge. In the V2
          // frame it sits at inset-inline-end −6 (the screen edge side).
          PositionedDirectional(
            end: -6,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(120, double.infinity),
                painter: _WheelArcPainter(
                  // V2 arcFlip: the belly turns toward the discs in RTL.
                  flip: Directionality.of(context) == TextDirection.rtl,
                ),
              ),
            ),
          ),
          Column(
            children: [
              _SwipeHint(text: l10n.kioskSwipeMore, pointsUp: true),
              Expanded(
                child: ClipRect(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedPositioned(
                          duration: _dragging
                              ? Duration.zero
                              : KioskWheel.snapDuration,
                          curve: KioskWheel.curve,
                          top: shift,
                          left: 0,
                          right: 0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < widget.categories.length; i++)
                                _WheelRow(
                                  key: ValueKey(widget.categories[i].id),
                                  category: widget.categories[i],
                                  distance: (i - _clampedIndex).abs(),
                                  lang: lang,
                                  onTap: () => _onDiscTap(i),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _SwipeHint(text: l10n.kioskSwipeMore, pointsUp: false),
            ],
          ),
        ],
      ),
    );
  }
}

class _WheelRow extends StatelessWidget {
  const _WheelRow({
    super.key,
    required this.category,
    required this.distance,
    required this.lang,
    required this.onTap,
  });
  final KioskFixtureCategory category;
  final int distance;
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = distance == 0;
    final disc =
        KioskWheel.discByDistance[distance.clamp(
          0,
          KioskWheel.discByDistance.length - 1,
        )];
    final labelSize =
        KioskWheel.labelSizeByDistance[distance.clamp(
          0,
          KioskWheel.labelSizeByDistance.length - 1,
        )];
    final opacity =
        KioskWheel.opacityByDistance[distance.clamp(
          0,
          KioskWheel.opacityByDistance.length - 1,
        )];

    // V2 rows are a fixed 172px with the active disc+label deliberately
    // taller — CSS lets the content overflow the row visually; OverflowBox
    // reproduces that without a layout error.
    return SizedBox(
      height: KioskWheel.rowExtent,
      child: OverflowBox(
        maxHeight: KioskWheel.rowExtent + 60,
        alignment: Alignment.center,
        child: GestureDetector(
          // The whole row (disc + label) is the tap target — kiosk-safe touch
          // area; the rail's drag detector still owns vertical drags.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedOpacity(
                duration: KioskWheel.discDuration,
                curve: KioskWheel.curve,
                opacity: opacity,
                child: AnimatedContainer(
                  duration: KioskWheel.discDuration,
                  curve: KioskWheel.curve,
                  width: disc,
                  height: disc,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: active
                        ? const RadialGradient(
                            colors: [
                              KioskColors.wheelActiveTop,
                              KioskColors.imageWell,
                            ],
                          )
                        : null,
                    color: active ? null : KioskColors.glass(.05),
                    border: Border.all(
                      color: active ? KioskColors.ring : KioskColors.glass(.14),
                      width: active ? 3.5 : 2,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: KioskColors.ring.withValues(alpha: .5),
                              blurRadius: 46,
                            ),
                            BoxShadow(
                              color: KioskColors.ring.withValues(alpha: .14),
                              spreadRadius: 9,
                            ),
                          ]
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: category.thumbAsset != null
                      ? Image.asset(category.thumbAsset!, fit: BoxFit.cover)
                      : Center(
                          child: Icon(
                            category.iconKind == 'drink'
                                ? Icons.local_drink_outlined
                                : Icons.icecream_outlined,
                            size: disc * .46,
                            color: KioskColors.textSoft,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 9),
              AnimatedOpacity(
                duration: KioskWheel.discDuration,
                opacity: opacity,
                child: AnimatedDefaultTextStyle(
                  duration: KioskWheel.discDuration,
                  style: KioskType.body(
                    labelSize,
                    FontWeight.w800,
                    color: active ? Colors.white : KioskColors.wheelLabel,
                    height: 1.15,
                  ),
                  child: Text(
                    category.name.of(lang),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.text, required this.pointsUp});
  final String text;
  final bool pointsUp;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: .75,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pointsUp)
            const Icon(
              Icons.keyboard_arrow_up,
              size: 26,
              color: KioskColors.accentTop,
            ),
          SizedBox(
            width: 150,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: KioskType.body(
                16,
                FontWeight.w600,
                color: KioskColors.textMuted,
                height: 1.25,
              ),
            ),
          ),
          if (!pointsUp)
            const Icon(
              Icons.keyboard_arrow_down,
              size: 26,
              color: KioskColors.accentTop,
            ),
        ],
      ),
    ),
  );
}

/// The tall orange gradient arc beside the rail (V2: a 120×1200 SVG path with
/// a vertical fade-in/out gradient stroke, flipped horizontally in LTR).
class _WheelArcPainter extends CustomPainter {
  const _WheelArcPainter({required this.flip});
  final bool flip;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height.isFinite ? size.height : 1200.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          KioskColors.ring.withValues(alpha: 0),
          KioskColors.ring,
          KioskColors.ring.withValues(alpha: 0),
        ],
        stops: const [0, .5, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, h));
    if (flip) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final path = Path()
      ..moveTo(112, 0)
      ..cubicTo(30, h * (320 / 1200), 30, h * (880 / 1200), 112, h);
    // (the artifact's container opacity .9 is folded into the gradient stops)
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WheelArcPainter oldDelegate) => oldDelegate.flip != flip;
}
