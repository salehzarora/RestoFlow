import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../data/kiosk_appearance.dart';
import '../data/kiosk_attract_media.dart';
import '../media/kiosk_media_image.dart';
import '../design/kiosk_theme.dart';

/// Resolves a stored media REF to its absolute device-local path (null =>
/// missing/corrupt/unsupported => the caller's neutral fallback).
Future<String?> _resolve(WidgetRef ref, String? mediaRef) async {
  if (mediaRef == null) return null;
  final store = ref.read(kioskAttractMediaStoreProvider);
  final scope = ref.read(kioskAppearanceScopeProvider);
  if (store == null || scope == null) return null;
  return store.absolutePathOf(deviceId: scope.deviceId, ref: mediaRef);
}

ColoredBox get _fallback => ColoredBox(color: KioskColors.canvasBottom);

/// §5 — ONE static external image, full-bleed cover, no carousel, no timer.
/// Missing/corrupt files degrade to the neutral canvas.
class KioskCustomImageBackground extends ConsumerWidget {
  const KioskCustomImageBackground({super.key, required this.mediaRef});
  final String? mediaRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<String?>(
    future: _resolve(ref, mediaRef),
    builder: (context, snapshot) {
      final path = snapshot.data;
      if (path == null) return _fallback;
      // PERF-110 / KIOSK-UI-113: an operator upload has no size contract —
      // cap the decode at the REAL full-stage physical need (the canvas may
      // widen on 16:10 tablets) instead of the file's native size.
      return LayoutBuilder(
        builder: (context, constraints) => Image(
          image: kioskCappedImageProvider(
            context,
            FileImage(File(path)),
            designWidth: constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : kioskDesignSize.width,
          ),
          key: const Key('kiosk-attract-custom-image'),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback,
        ),
      );
    },
  );
}

/// §6 — ONE looping external video: muted autoplay, no controls, full-bleed
/// cover, lifecycle-safe pause/resume, decode failure => neutral fallback.
/// No raw path is ever logged.
class KioskCustomVideoBackground extends ConsumerStatefulWidget {
  const KioskCustomVideoBackground({super.key, required this.mediaRef});
  final String? mediaRef;

  @override
  ConsumerState<KioskCustomVideoBackground> createState() =>
      _KioskCustomVideoBackgroundState();
}

class _KioskCustomVideoBackgroundState
    extends ConsumerState<KioskCustomVideoBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final path = await _resolve(ref, widget.mediaRef);
    if (!mounted) return;
    if (path == null) {
      setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.file(File(path));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0); // §6: never any audio
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      // Undecodable/broken file: quiet neutral fallback, no path in logs.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    switch (state) {
      case AppLifecycleState.resumed:
        controller.play();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null || !controller.value.isInitialized) {
      return _fallback;
    }
    final size = controller.value.size;
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(
              controller,
              key: const Key('kiosk-attract-custom-video'),
            ),
          ),
        ),
      ),
    );
  }
}
