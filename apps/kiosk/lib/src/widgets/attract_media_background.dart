/// KIOSK-001-103 §5/§6 — the custom attract backgrounds (one static external
/// image / one looping muted external video), platform-split so `dart:io` +
/// `video_player`'s file path never enter the web build. Web renders the
/// neutral canvas fallback (custom media is installed-device only).
library;

export 'attract_media_background_io.dart'
    if (dart.library.js_interop) 'attract_media_background_web.dart';
