import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../media/kiosk_media_image.dart';
import 'kiosk_chrome.dart';

/// KIOSK-001 — the V2 gesture-driven vertical category wheel.
///
/// This is the design's HIGHEST-PRIORITY component and follows the artifact's
/// interaction model exactly (`Kiosk Prototype v2.dc.html`):
///
///  * rows are [KioskWheel.rowExtent] tall; the whole column is translated
///    by `railShift = KioskWheel.baseShiftFor(activeIndex, N)
///    (+ live drag delta)` — KIOSK-CATEGORY-RAIL-115's Model B: the active
///    row rests at [KioskWheel.focusTop] and the stack translates on every
///    selection, clamping only at the list tail (never pinned, never
///    wrapping);
///  * while the finger drags, the column FOLLOWS it with no animation;
///  * on release the wheel snaps to `round(activeIndex − dragDy/rowExtent)`,
///    clamped to the category range, animating 450ms on cubic(.22,.9,.26,1);
///  * disc size / label size / opacity fall off with distance from the
///    active index ([KioskWheel.discByDistance] · [KioskWheel
///    .labelSizeByDistance] · [KioskWheel.opacityByDistance]), and each row
///    bows horizontally by [KioskWheel.xOffsetByDistance] (outward active,
///    receding neighbors — the curved-carousel silhouette), every style
///    morph animating over 400ms;
///  * the active disc carries the 5px #F97316 ring, the dual orange glow
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
    this.categoryImageUrls = const {},
  });

  final List<KioskFixtureCategory> categories;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final double? height;

  /// KIOSK-001-102 §11: category id → representative LIVE product photo
  /// (already signed + cached upstream). A category without an entry keeps
  /// its fixture thumb / registry icon — never a broken blank circle. Only
  /// the node ARTWORK changes; every gesture/snap/geometry constant stays.
  final Map<String, String> categoryImageUrls;

  @override
  State<KioskCategoryWheel> createState() => _KioskCategoryWheelState();
}

class _KioskCategoryWheelState extends State<KioskCategoryWheel> {
  bool _dragging = false;
  double _dragDy = 0;
  bool _moved = false;

  // KIOSK-CATEGORY-LOOP-116 — wrapping-mode wheel-local state: the
  // unbounded VIRTUAL active index (real = _virtualActive mod N) and the
  // strip window's recenter anchor. Pure UI state, like [_dragDy]; the
  // provider/menu contract keeps seeing only real indices.
  int _virtualActive = 0;
  int _windowBase = 0;

  int get _clampedIndex =>
      widget.activeIndex.clamp(0, widget.categories.length - 1);

  /// OWNER DECISION: loop only at [KioskWheel.wrapMinCount]+ categories.
  bool get _wrapping => widget.categories.length >= KioskWheel.wrapMinCount;

  @override
  void initState() {
    super.initState();
    _virtualActive = widget.categories.isEmpty ? 0 : _clampedIndex;
    _windowBase = _virtualActive;
  }

  @override
  void didUpdateWidget(KioskCategoryWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final n = widget.categories.length;
    if (n == 0) return;
    if (!_wrapping || n != oldWidget.categories.length) {
      // Finite mode (or a changed category set): keep the virtual mirrors
      // aligned with the real index so a later mode switch starts clean.
      _virtualActive = _clampedIndex;
      _windowBase = _virtualActive;
      return;
    }
    final real = _clampedIndex;
    final current = _virtualActive % n;
    if (real != current) {
      // External selection: travel the SHORTEST circular path (positive
      // bias on exact ties — N=4: 0 -> 2 goes +2). The lagging window
      // recenters after the settle.
      var delta = (real - current) % n;
      if (delta > n / 2) delta -= n;
      _virtualActive += delta;
    }
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _dragDy = 0;
      _moved = false;
      // 116: normalize the window before following the finger — the drag
      // build has zero duration, so this recenter is pixel-compensated.
      if (_wrapping) _windowBase = _virtualActive;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final dy = _dragDy + details.delta.dy;
    if (dy.abs() > KioskWheel.tapSlop) _moved = true;
    setState(() => _dragDy = dy);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_wrapping) {
      // 116: NO end clamp — the wheel loops. One gesture advances at most
      // wheelMaxRowsPerSwipe rows (no inertia; window coverage stays
      // provable).
      final d = (-(_dragDy / KioskWheel.rowExtent).round()).clamp(
        -KioskWheel.wheelMaxRowsPerSwipe,
        KioskWheel.wheelMaxRowsPerSwipe,
      );
      setState(() {
        _dragging = false;
        _dragDy = 0;
        _virtualActive += d;
      });
      if (d != 0) {
        widget.onSelect(_virtualActive % widget.categories.length);
      }
      return;
    }
    final snapped = (_clampedIndex - _dragDy / KioskWheel.rowExtent)
        .round()
        .clamp(0, widget.categories.length - 1);
    setState(() {
      _dragging = false;
      _dragDy = 0;
    });
    if (snapped != _clampedIndex) widget.onSelect(snapped);
  }

  /// Post-settle window recenter (wrapping mode): pixel-compensated — the
  /// content shifts by the lag while the configured top jumps the same
  /// amount the other way, and the rebuild's duration resolves to zero.
  void _recenterWindow() {
    if (!_wrapping || _dragging || _windowBase == _virtualActive) return;
    setState(() => _windowBase = _virtualActive);
  }

  void _onDiscTap(int index) {
    if (_moved) {
      _moved = false;
      return;
    }
    widget.onSelect(index);
  }

  /// 116: a tap on virtual slot [j] rotates toward THAT occurrence (circle
  /// semantics — tapping the wrapped copy above the first category turns
  /// the wheel upward to the last one).
  void _onWrappedTap(int j) {
    if (_moved) {
      _moved = false;
      return;
    }
    setState(() => _virtualActive = j);
    widget.onSelect(j % widget.categories.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final n = widget.categories.length;
    final wrapping = _wrapping;
    final k = KioskWheel.wheelWindowRadius;
    // 116 wrapping: the modulo strip window translates so the active
    // virtual slot rests at the focus; the whole stack still follows the
    // finger 1:1 and an unclamped one-row swipe settles exactly where the
    // finger left the rows (zero spring-back). There is NO tail — the
    // finite Model B (baseShiftFor) survives only for N < wrapMinCount.
    final shift = wrapping
        ? KioskWheel.focusTop -
              (k + _virtualActive - _windowBase) * KioskWheel.rowExtent +
              (_dragging ? _dragDy : 0)
        : KioskWheel.baseShiftFor(_clampedIndex, n) + (_dragging ? _dragDy : 0);
    // The orange guide's apex rides the active row: live with the finger
    // during a drag, easing onto the focus alongside the 450ms snap. In
    // wrapping mode the rest apex is the CONSTANT focus (320) — the finite
    // 420 tail state does not exist on a circle.
    final apexTarget = wrapping
        ? KioskWheel.focusTop +
              KioskWheel.rowExtent / 2 +
              (_dragging ? _dragDy : 0)
        : shift +
              _clampedIndex * KioskWheel.rowExtent +
              KioskWheel.rowExtent / 2;

    return SizedBox(
      width: KioskWheel.railWidth,
      height: widget.height,
      child: Column(
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
                    // 115/115A: the orange guide lives BEHIND the rows in
                    // the SAME clip-local coordinate space. 115A splits it:
                    // the base painter is the STATIC full-height spine
                    // (flip-only — a swipe can never translate it), and the
                    // foreground marker layer is the ONLY apex-driven paint,
                    // traveling ALONG the spine (live with the finger while
                    // dragging, easing onto the focus with the 450ms snap;
                    // complete at rest — zero animation frames, PERF-110).
                    PositionedDirectional(
                      end: -6,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: apexTarget),
                            duration: _dragging
                                ? Duration.zero
                                : KioskWheel.snapDuration,
                            curve: KioskWheel.curve,
                            builder: (context, apexY, _) {
                              final rtl =
                                  Directionality.of(context) ==
                                  TextDirection.rtl;
                              return CustomPaint(
                                size: const Size(120, double.infinity),
                                painter: _WheelRailPainter(flip: rtl),
                                foregroundPainter: _WheelMarkerPainter(
                                  flip: rtl,
                                  apexY: apexY,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      // 116: the recenter build (windowBase == virtual) is
                      // pixel-compensated and must not animate; drags stay
                      // zero-duration as always.
                      duration:
                          _dragging ||
                              (wrapping && _windowBase == _virtualActive)
                          ? Duration.zero
                          : KioskWheel.snapDuration,
                      onEnd: wrapping ? _recenterWindow : null,
                      curve: KioskWheel.curve,
                      top: shift,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (wrapping)
                            // 116: modulo strip — virtual slot j shows the
                            // real category j mod N. Keys are VIRTUAL (the
                            // same real category may occupy two slots at
                            // once on a small circle).
                            for (
                              var j = _windowBase - k;
                              j <= _windowBase + k;
                              j++
                            )
                              _WheelRow(
                                key: ValueKey('wrap-slot-$j'),
                                category: widget.categories[j % n],
                                imageUrl:
                                    widget.categoryImageUrls[widget
                                        .categories[j % n]
                                        .id],
                                distance: (j - _virtualActive).abs(),
                                lang: lang,
                                onTap: () => _onWrappedTap(j),
                              )
                          else
                            for (var i = 0; i < n; i++)
                              _WheelRow(
                                key: ValueKey(widget.categories[i].id),
                                category: widget.categories[i],
                                imageUrl: widget
                                    .categoryImageUrls[widget.categories[i].id],
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
    );
  }
}

class _WheelRow extends StatelessWidget {
  const _WheelRow({
    super.key,
    required this.category,
    required this.imageUrl,
    required this.distance,
    required this.lang,
    required this.onTap,
  });
  final KioskFixtureCategory category;
  final String? imageUrl;
  final int distance;
  final String lang;
  final VoidCallback onTap;

  Widget _iconFallback(double disc) => Center(
    child: Icon(
      // LIVE: the owner-chosen registry glyph rides along resolved;
      // fixtures keep the Phase-1 kind switch; unknown/null keys fall
      // back the same stable way.
      category.iconData ??
          (category.iconKind == 'drink'
              ? Icons.local_drink_outlined
              : Icons.icecream_outlined),
      size: disc * .46,
      color: KioskColors.textSoft,
    ),
  );

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

    final outward =
        KioskWheel.xOffsetByDistance[distance.clamp(
          0,
          KioskWheel.xOffsetByDistance.length - 1,
        )];
    // Outward = toward the screen edge: +x under the RTL right-side rail,
    // mirrored in LTR.
    final dxTarget = Directionality.of(context) == TextDirection.rtl
        ? outward
        : -outward;

    // V2 rows are fixed-extent with the active disc+label deliberately
    // taller — CSS lets the content overflow the row visually; OverflowBox
    // reproduces that without a layout error (115: +100 headroom hosts the
    // centered 210 active disc plus its label window).
    return SizedBox(
      height: KioskWheel.rowExtent,
      child: OverflowBox(
        maxHeight: KioskWheel.rowExtent + 100,
        alignment: Alignment.center,
        // 115: the horizontal bow — animated with the same cadence as the
        // disc morph. Transform.translate transforms hit-tests, so the tap
        // target follows the visual node. Idle between selections: the
        // tween is complete, zero animation frames.
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: dxTarget),
          duration: KioskWheel.discDuration,
          curve: KioskWheel.curve,
          builder: (context, dx, child) =>
              Transform.translate(offset: Offset(dx, 0), child: child),
          child: GestureDetector(
            // The whole row (disc + label) is the tap target — kiosk-safe
            // touch area; the rail's drag detector still owns vertical
            // drags.
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              height: KioskWheel.rowExtent + 100,
              child: Column(
                children: [
                  // 115: the disc's CENTER sits exactly on the row's center
                  // (focusTop + rowExtent/2 at rest), whatever the label
                  // wraps to — every disc rides the 200px bow grid and the
                  // path marker stays concentric with the active disc. The
                  // spacer animates with the disc morph (TweenAnimation-
                  // Builder, NOT a second AnimatedContainer, so the disc
                  // stays the row's unique AnimatedContainer).
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      end: (KioskWheel.rowExtent + 100) / 2 - disc / 2,
                    ),
                    duration: KioskWheel.discDuration,
                    curve: KioskWheel.curve,
                    builder: (context, h, _) => SizedBox(height: h),
                  ),
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
                            ? RadialGradient(
                                colors: [
                                  KioskColors.wheelActiveTop,
                                  KioskColors.imageWell,
                                ],
                              )
                            : null,
                        color: active ? null : KioskColors.glass(.05),
                        // 115: heavier active emphasis — 5px ring + stronger
                        // static glow (same BoxShadow primitive; no filters).
                        border: Border.all(
                          color: active
                              ? KioskColors.ring
                              : KioskColors.glass(.14),
                          width: active ? 5 : 2,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: KioskColors.ring.withValues(
                                    alpha: .55,
                                  ),
                                  blurRadius: 56,
                                ),
                                BoxShadow(
                                  color: KioskColors.ring.withValues(
                                    alpha: .16,
                                  ),
                                  spreadRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: imageUrl != null
                          // §11: the category node reads as FOOD — a clipped
                          // cover photo of a real product from THIS category,
                          // with a mild dark veil for label/ring contrast. A
                          // failed load falls back to the icon path below.
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image(
                                  // PERF-110: a 78–210px disc must never decode
                                  // the full product photo.
                                  image: kioskNetworkImageProvider(
                                    context,
                                    imageUrl!,
                                    designWidth: disc,
                                  ),
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, _, _) =>
                                      _iconFallback(disc),
                                ),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0x24000000),
                                  ),
                                ),
                              ],
                            )
                          : category.thumbAsset != null
                          ? KioskFixtureImage(
                              asset: category.thumbAsset,
                              fallback: ColoredBox(
                                color: KioskColors.imageWell,
                              ),
                            )
                          : _iconFallback(disc),
                    ),
                  ),
                  const SizedBox(height: 9),
                  // The label takes whatever the fixed row box leaves under
                  // the centered disc (Flexible, never an overflow error);
                  // long names ellipsize inside that window.
                  Flexible(
                    child: AnimatedOpacity(
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
                  ),
                ],
              ),
            ),
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
            Icon(
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
            Icon(
              Icons.keyboard_arrow_down,
              size: 26,
              color: KioskColors.accentTop,
            ),
        ],
      ),
    ),
  );
}

/// 115A — the guide's STATIC layer: the faint full-height spine, fixed in
/// rail-local space. `flip` is its ONLY input, so a category swipe can
/// never translate it (the v11 "whole line drags along" defect). Repaints
/// only on a direction flip.
class _WheelRailPainter extends CustomPainter {
  const _WheelRailPainter({required this.flip});
  final bool flip;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height.isFinite ? size.height : 1200.0;
    if (flip) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          KioskColors.ring.withValues(alpha: 0),
          KioskColors.ring.withValues(alpha: .5),
          KioskColors.ring.withValues(alpha: 0),
        ],
        stops: const [0, .5, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, h));
    final path = Path()
      ..moveTo(KioskWheel.railSpineInnerX, 0)
      ..cubicTo(
        KioskWheel.railSpineControlX,
        h * .32,
        KioskWheel.railSpineControlX,
        h * .68,
        KioskWheel.railSpineInnerX,
        h,
      );
    // (the artifact's container opacity .9 is folded into the gradient stops)
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WheelRailPainter oldDelegate) => oldDelegate.flip != flip;
}

/// 115A — the guide's MOVING layer, the ONLY apex-driven paint: a bright
/// local segment of the shared spine hugging the active point, the marker
/// ring + dot sitting exactly ON the spine, and fading connector dots
/// one/two rows out. Simple strokes and circles, no filters; repaints only
/// while the apex changes (drag/snap frames — zero at rest).
class _WheelMarkerPainter extends CustomPainter {
  const _WheelMarkerPainter({required this.flip, required this.apexY});
  final bool flip;
  final double apexY;

  /// Half-height of the bright spine segment around the marker.
  static const double _segment = 90;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height.isFinite ? size.height : 1200.0;
    if (flip) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    // Bright segment of the SAME spine around the marker (sampled polyline
    // on KioskWheel.railSpineX, so it hugs the static rail exactly).
    final top = (apexY - _segment).clamp(0.0, h);
    final bottom = (apexY + _segment).clamp(0.0, h);
    if (bottom > top) {
      final seg = Path();
      const steps = 12;
      for (var i = 0; i <= steps; i++) {
        final y = top + (bottom - top) * i / steps;
        final x = KioskWheel.railSpineX(y, h);
        if (i == 0) {
          seg.moveTo(x, y);
        } else {
          seg.lineTo(x, y);
        }
      }
      canvas.drawPath(
        seg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              KioskColors.ring.withValues(alpha: 0),
              KioskColors.ring,
              KioskColors.ring.withValues(alpha: 0),
            ],
            stops: const [0, .5, 1],
          ).createShader(Rect.fromLTRB(0, top, size.width, bottom)),
      );
    }

    // Marker ring + filled dot ON the spine.
    final markerY = apexY.clamp(0.0, h);
    final apex = Offset(KioskWheel.railSpineX(markerY, h), markerY);
    canvas.drawCircle(
      apex,
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = KioskColors.ring.withValues(alpha: .9),
    );
    canvas.drawCircle(apex, 7, Paint()..color = KioskColors.ring);

    // Connector dots ON the spine at ±1/±2 rows (skipped outside the rail).
    for (final (dy, r, a) in [
      (-KioskWheel.rowExtent, 5.0, .5),
      (KioskWheel.rowExtent, 5.0, .5),
      (-2 * KioskWheel.rowExtent, 3.5, .3),
      (2 * KioskWheel.rowExtent, 3.5, .3),
    ]) {
      final y = apexY + dy;
      if (y < 0 || y > h) continue;
      canvas.drawCircle(
        Offset(KioskWheel.railSpineX(y, h), y),
        r,
        Paint()..color = KioskColors.ring.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(_WheelMarkerPainter oldDelegate) =>
      oldDelegate.flip != flip || oldDelegate.apexY != apexY;
}
