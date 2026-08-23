import 'package:flutter/material.dart';

import '../design/kiosk_theme.dart';

/// Web: no durable device-local media — the neutral canvas renders instead
/// (the editor already explains that custom media is installed-device only).
class KioskCustomImageBackground extends StatelessWidget {
  const KioskCustomImageBackground({super.key, required this.mediaRef});
  final String? mediaRef;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: KioskColors.canvasBottom);
}

class KioskCustomVideoBackground extends StatelessWidget {
  const KioskCustomVideoBackground({super.key, required this.mediaRef});
  final String? mediaRef;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: KioskColors.canvasBottom);
}
