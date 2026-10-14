import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One foreground inbox alert. Cadence and authorization belong to the inbox
/// controller; audio never polls, starts a loop, or changes device settings.
abstract interface class OnlineOrderAlertAudio {
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

final onlineOrderAlertAudioProvider = Provider<OnlineOrderAlertAudio>((ref) {
  final audio = MethodChannelOnlineOrderAlertAudio();
  ref.onDispose(() => unawaited(audio.dispose()));
  return audio;
});

/// Android plays a bounded notification-stream chime. Browser and other
/// platforms are intentionally silent, including a missing native plugin.
class MethodChannelOnlineOrderAlertAudio implements OnlineOrderAlertAudio {
  MethodChannelOnlineOrderAlertAudio({
    MethodChannel channel = const MethodChannel(
      'restoflow.pos/online_order_alert',
    ),
    @visibleForTesting bool? enabled,
  }) : _channel = channel,
       _enabled =
           enabled ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final MethodChannel _channel;
  final bool _enabled;
  bool _disposed = false;
  bool _playInFlight = false;

  @override
  Future<void> play() async {
    if (_disposed || !_enabled || _playInFlight) return;
    _playInFlight = true;
    try {
      await _invoke('play');
    } finally {
      _playInFlight = false;
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed || !_enabled) return;
    await _invoke('stop');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_enabled) await _invoke('dispose');
  }

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // Unavailable audio must never break inbox refresh or decision recovery.
      // In particular, web/missing plugins and native audio-policy failures
      // need no permission prompt, fallback stream, or uncaught future.
    }
  }
}
