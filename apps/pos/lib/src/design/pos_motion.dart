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
