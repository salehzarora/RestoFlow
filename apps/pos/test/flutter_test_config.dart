import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:restoflow_pos/src/media/pos_media_image.dart';

/// EGRESS-REMEDIATION-001 — POS widget-test harness configuration.
///
/// Production menu images resolve through [posMediaImageProvider]
/// (CachedNetworkImageProvider + a persistent cache manager keyed by the
/// stable object path). The cache manager needs real platform channels
/// (path_provider/sqflite) that widget tests do not have, and the pre-change
/// test corpus was written against plain [NetworkImage] semantics (including
/// the [debugNetworkImageHttpClientProvider] hook that
/// pos_menu_images_test.dart uses to serve tiny PNG bytes).
///
/// So every POS test runs with the provider factory pinned back to
/// [NetworkImage] — EXACTLY the pre-change rendering pipeline. Tests that
/// exercise the real cached provider (pos_media_image_test.dart) construct it
/// directly instead of going through the factory.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugPosMediaImageProviderOverride = NetworkImage.new;
  await testMain();
}
