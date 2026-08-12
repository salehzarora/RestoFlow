/// POS-PREMIUM-VISUAL-POLISH-001 — the POS motion system.
///
/// One curve, five durations, and a small set of composable widgets. Every
/// animation here is FINITE (one-shot, no repeating tickers, no raw timers),
/// so every existing `pumpAndSettle` in the ~90 POS test files still settles
/// and no "pending timer" guard ever fires.
///
/// REDUCED MOTION IS A CONTRACT: every widget in this file checks
/// [posMotionEnabled] and renders its FINAL state immediately when the
/// platform asks for reduced motion. Layout is never animated — only opacity
/// and paint-level transforms — so test geometry (getRect/getSize) is stable
/// mid-flight.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import 'pos_visual_tokens.dart';

/// The one easing: an overshooting spring (cubic-bezier(.34,1.56,.64,1)).
const Curve kPosSpring = Cubic(0.34, 1.56, 0.64, 1);

/// Motion durations (owner brief: 150–400ms).
abstract final class PosMotionDurations {
  /// Tap bump / pressed feedback.
  static const Duration tap = Duration(milliseconds: 150);

  /// Value changes (count-up, small state swaps).
  static const Duration base = Duration(milliseconds: 220);

  /// Entrance of a card / chip / summary row.
  static const Duration entrance = Duration(milliseconds: 320);

  /// The fly-to-cart flight and the toast slide.
  static const Duration flight = Duration(milliseconds: 400);

  /// Stagger step between entrance siblings (brief: 30–50ms).
  static const Duration stagger = Duration(milliseconds: 40);
}

/// Whether motion is allowed here. False when the platform requests reduced
/// motion — every widget below then renders its final state with no tween.
bool posMotionEnabled(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context);

/// One-shot staggered entrance: fade + a 0.97→1 paint-level scale, delayed by
/// `index × stagger`. Purely decorative — the child is laid out at full size
/// from the first frame, so finders and geometry assertions are unaffected.
class PosEntrance extends StatelessWidget {
  const PosEntrance({super.key, required this.index, required this.child});

  /// Position in the entrance sequence (grid order, chip order, row order).
  final int index;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!posMotionEnabled(context)) return child;
    // Cap the delay so a long grid does not make its tail feel broken: after
    // ~10 steps everything remaining enters together.
    final steps = index.clamp(0, 10);
    final delay = PosMotionDurations.stagger * steps;
    final total = PosMotionDurations.entrance + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: kPosSpring),
      child: child,
      builder: (context, t, child) {
        final v = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
        );
      },
    );
  }
}

/// Bump/pop feedback: scales down to 0.97 while the pointer is down and
/// springs back on release. Wraps WITHOUT consuming the tap — it listens on a
/// translucent [Listener], so the child's own InkWell/button keeps its
/// behaviour, semantics and hit target.
class PosTapBump extends StatefulWidget {
  const PosTapBump({super.key, this.enabled = true, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<PosTapBump> createState() => _PosTapBumpState();
}

class _PosTapBumpState extends State<PosTapBump> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !posMotionEnabled(context)) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: PosMotionDurations.tap,
        curve: _down ? Curves.easeOut : kPosSpring,
        child: widget.child,
      ),
    );
  }
}

/// Count-up tween for an integer that changes (cart badge, item counts).
/// Renders through [builder] so the caller owns the text style; settles on
/// EXACTLY [value], so tests that assert the final text are unaffected.
class PosAnimatedCount extends StatelessWidget {
  const PosAnimatedCount({
    super.key,
    required this.value,
    required this.builder,
  });

  final int value;
  final Widget Function(BuildContext context, int value) builder;

  @override
  Widget build(BuildContext context) {
    if (!posMotionEnabled(context)) return builder(context, value);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: value.toDouble(), end: value.toDouble()),
      duration: PosMotionDurations.base,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => builder(context, v.round()),
    );
  }
}

/// Count-up tween for a money amount in integer minor units (D-007: the
/// tweened value is rounded back to an int before formatting — no float money
/// ever reaches a formatter). Settles on exactly [minor].
class PosAnimatedAmount extends StatelessWidget {
  const PosAnimatedAmount({
    super.key,
    required this.minor,
    required this.builder,
  });

  final int minor;
  final Widget Function(BuildContext context, int minor) builder;

  @override
  Widget build(BuildContext context) {
    if (!posMotionEnabled(context)) return builder(context, minor);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: minor.toDouble(), end: minor.toDouble()),
      duration: PosMotionDurations.base,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => builder(context, v.round()),
    );
  }
}

/// A one-shot shimmer sweep across [child], re-armed by bumping [trigger].
/// Used ONLY on the primary CTA (owner brief). No repeat: the sweep runs once
/// per trigger change (e.g. Send becoming enabled), so `pumpAndSettle`
/// settles and reduced-motion renders the plain child.
///
/// Implemented as a clipped translucent gradient band gliding over the child
/// (no ShaderMask: shader compositing is heavier and asserts in some test
/// bindings; a band over a filled button reads identically).
class PosShimmerSweep extends StatefulWidget {
  const PosShimmerSweep({
    super.key,
    required this.trigger,
    this.tint = kPosEmberOrange,
    this.borderRadius,
    required this.child,
  });

  /// Any change re-runs the sweep once. Pass a stable value to keep it idle.
  final Object trigger;

  /// Warm highlight tint blended into the sweep (decorative ember note).
  final Color tint;

  /// Clip radius for the band — pass the child's own radius so the sweep
  /// never paints outside the control.
  final BorderRadius? borderRadius;

  final Widget child;

  @override
  State<PosShimmerSweep> createState() => _PosShimmerSweepState();
}

class _PosShimmerSweepState extends State<PosShimmerSweep> {
  int _run = 0;

  @override
  void didUpdateWidget(PosShimmerSweep old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _run++;
  }

  @override
  Widget build(BuildContext context) {
    if (!posMotionEnabled(context)) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: widget.borderRadius ?? BorderRadius.zero,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_run),
                tween: Tween(begin: -0.6, end: 1.6),
                duration: PosMotionDurations.flight,
                curve: Curves.easeInOut,
                builder: (context, x, _) {
                  if (x >= 1.6) return const SizedBox.shrink();
                  return FractionalTranslation(
                    translation: Offset(x, 0),
                    child: FractionallySizedBox(
                      widthFactor: 0.45,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: 0.22),
                              widget.tint.withValues(alpha: 0.12),
                              Colors.white.withValues(alpha: 0),
                            ],
                            stops: const [0, 0.45, 0.6, 1],
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The cart glyph the fly-to-cart ghost lands on. Attached to EXACTLY ONE
/// mounted widget at a time: the side-cart header icon on two-pane layouts,
/// the bottom-bar icon on phones (the sheet header never carries it).
final GlobalKey posCartFlyTargetKey = GlobalKey(
  debugLabel: 'pos-cart-fly-target',
);

/// FLIP fly-to-cart: measure the tapped card (First), the cart glyph (Last),
/// and play a small ghost along an arced path between them (Invert/Play).
/// Fire-and-forget and safe by construction: any missing/detached geometry,
/// missing overlay, or reduced-motion setting simply skips the flight — the
/// add itself already happened through the ordinary controller path.
void posFlyToCart(BuildContext fromContext, {Color? color}) {
  if (!posMotionEnabled(fromContext)) return;
  final overlay = Overlay.maybeOf(fromContext);
  final fromBox = fromContext.findRenderObject();
  final targetContext = posCartFlyTargetKey.currentContext;
  final toBox = targetContext?.findRenderObject();
  if (overlay == null ||
      fromBox is! RenderBox ||
      !fromBox.attached ||
      toBox is! RenderBox ||
      !toBox.attached) {
    return;
  }
  final from = fromBox.localToGlobal(fromBox.size.center(Offset.zero));
  final to = toBox.localToGlobal(toBox.size.center(Offset.zero));
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _FlyGhost(
      from: from,
      to: to,
      color: color ?? kPosDefaultSecondaryAccent,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _FlyGhost extends StatelessWidget {
  const _FlyGhost({
    required this.from,
    required this.to,
    required this.color,
    required this.onDone,
  });

  final Offset from;
  final Offset to;
  final Color color;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    const size = 28.0;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: PosMotionDurations.flight,
        curve: Curves.easeInOutCubic,
        onEnd: onDone,
        builder: (context, t, _) {
          // A gentle arc: linear interpolation lifted by a parabolic bump.
          final lift = 36 * (1 - (2 * t - 1) * (2 * t - 1));
          final pos = Offset.lerp(from, to, t)! - Offset(0, lift);
          final scale = 1 - 0.45 * t;
          final opacity = t < 0.85 ? 1.0 : (1 - (t - 0.85) / 0.15);
          return Stack(
            children: [
              Positioned(
                left: pos.dx - size / 2,
                top: pos.dy - size / 2,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: kPosToastShadow,
                      ),
                      child: const Icon(
                        Icons.shopping_cart,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
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

OverlayEntry? _activeToast;

/// A bottom spring toast for lightweight confirmations. One at a time; a new
/// toast replaces the current one. Driven by a SINGLE finite tween (enter ->
/// hold -> exit phases of one 2s timeline) — no Timer, so tests never trip
/// the pending-timer guard and `pumpAndSettle` always settles. Reduced motion
/// keeps the toast (it is information) but drops the slide.
void showPosSpringToast(
  BuildContext context, {
  required String message,
  IconData icon = Icons.check_circle_outline,
  Color? accent,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  final reduced = !posMotionEnabled(context);
  _activeToast?.remove();
  _activeToast = null;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _SpringToast(
      message: message,
      icon: icon,
      accent: accent ?? kPosDefaultSecondaryAccent,
      reduced: reduced,
      onDone: () {
        if (identical(_activeToast, entry)) _activeToast = null;
        entry.remove();
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

class _SpringToast extends StatelessWidget {
  const _SpringToast({
    required this.message,
    required this.icon,
    required this.accent,
    required this.reduced,
    required this.onDone,
  });

  final String message;
  final IconData icon;
  final Color accent;
  final bool reduced;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2000),
      onEnd: onDone,
      builder: (context, t, child) {
        final enter = reduced
            ? 1.0
            : kPosSpring.transform((t / 0.16).clamp(0.0, 1.0));
        final exit = t < 0.86 ? 1.0 : 1 - ((t - 0.86) / 0.14);
        return PositionedDirectional(
          start: RestoflowSpacing.xl,
          end: RestoflowSpacing.xl,
          bottom: bottomInset + 24 + (reduced ? 0 : 16 * (1 - enter)),
          child: Opacity(
            opacity: (enter * exit).clamp(0.0, 1.0),
            child: child!,
          ),
        );
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: kPosSlateInk,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(
                RestoflowSpacing.md,
                RestoflowSpacing.sm,
                RestoflowSpacing.lg,
                RestoflowSpacing.sm,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(RestoflowRadii.md),
                boxShadow: kPosToastShadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: RestoflowIconSizes.md, color: accent),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Flexible(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
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
