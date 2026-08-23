import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — the kiosk's image DECODE budget.
///
/// The kiosk is authored in a fixed 1080×1920 design space and letterboxed
/// through `KioskStage` (FittedBox.contain), so a widget that is 343 design
/// px wide is really `343 × stageScale × devicePixelRatio` device pixels.
/// Decoding a 2400-px camera photo into that well wastes memory bandwidth and
/// GPU upload on exactly the weak tablets this ticket targets. These helpers
/// mirror the POS approach (`ResizeImage.resizeIfNeeded`, width-only, never
/// upscaling) with the one extra term the kiosk needs: the stage scale.
///
/// Quality is preserved: the decode target is the PHYSICAL pixel need of the
/// destination, never below it; `ResizeImage` never inflates a smaller
/// source (`allowUpscaling` stays false).
class KioskStageScale extends InheritedWidget {
  const KioskStageScale({super.key, required this.scale, required super.child});

  /// Design-px → logical-px factor of the enclosing stage (1.0 = the stage
  /// renders at its native 1080×1920 logical size).
  final double scale;

  /// 1.0 outside any stage (root-navigator dialogs, bare widget tests) — the
  /// honest no-letterbox assumption.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KioskStageScale>()?.scale ??
      1.0;

  /// The stage scale that `FittedBox.contain` will resolve for the given
  /// box — identical arithmetic to `applyBoxFit(BoxFit.contain, ...)`.
  static double forBox(Size box, Size design) {
    if (!box.width.isFinite || !box.height.isFinite) return 1.0;
    if (box.width <= 0 || box.height <= 0) return 1.0;
    final s = math.min(box.width / design.width, box.height / design.height);
    return (s.isFinite && s > 0) ? s : 1.0;
  }

  @override
  bool updateShouldNotify(KioskStageScale oldWidget) =>
      oldWidget.scale != scale;
}

/// Pure decode-width math (unit-testable): the device pixels needed to
/// render [designWidth] stage units crisply. Null = "no cap" (unknown /
/// unbounded width), which makes `ResizeImage.resizeIfNeeded` a no-op.
int? kioskDecodeWidthFor({
  required double designWidth,
  required double stageScale,
  required double devicePixelRatio,
}) {
  if (!designWidth.isFinite || designWidth <= 0) return null;
  if (!stageScale.isFinite || stageScale <= 0) return null;
  if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) return null;
  final px = designWidth * stageScale * devicePixelRatio;
  return px >= 1 ? px.ceil() : null;
}

/// [kioskDecodeWidthFor] resolved from the widget tree (stage scale +
/// MediaQuery device pixel ratio).
int? kioskDecodeWidth(BuildContext context, double designWidth) =>
    kioskDecodeWidthFor(
      designWidth: designWidth,
      stageScale: KioskStageScale.of(context),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );

/// Wraps [base] so it decodes at (most) the physical width the destination
/// needs. Width-only, like POS; safe with `BoxFit.cover`.
ImageProvider kioskCappedImageProvider(
  BuildContext context,
  ImageProvider base, {
  required double designWidth,
}) => ResizeImage.resizeIfNeeded(
  kioskDecodeWidth(context, designWidth),
  null,
  base,
);

/// A LIVE menu/attract photo provider capped to [designWidth] stage units.
ImageProvider kioskNetworkImageProvider(
  BuildContext context,
  String url, {
  required double designWidth,
}) => kioskCappedImageProvider(
  context,
  NetworkImage(url),
  designWidth: designWidth,
);

/// Unwraps a (possibly capped) provider back to its source — for tests and
/// diagnostics that need the original URL/file identity.
ImageProvider kioskUnwrapImageProvider(ImageProvider provider) =>
    provider is ResizeImage ? provider.imageProvider : provider;
