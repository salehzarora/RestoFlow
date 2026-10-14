import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/media/online_order_alert_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('restoflow.pos/online_order_alert');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('one play and stop use only the bounded audio transport', () async {
    final audio = MethodChannelOnlineOrderAlertAudio(enabled: true);
    await audio.play();
    await audio.stop();
    expect(calls, ['play', 'stop']);
  });

  test('concurrent play calls do not overlap a pending native call', () async {
    final completion = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'play') await completion.future;
      return null;
    });
    final audio = MethodChannelOnlineOrderAlertAudio(enabled: true);
    final playing = audio.play();
    await audio.play();
    expect(calls, ['play']);
    completion.complete();
    await playing;
    await audio.play();
    expect(calls, ['play', 'play']);
  });

  test('stop is immediate while play acknowledgement is pending', () async {
    final completion = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'play') await completion.future;
      return null;
    });
    final audio = MethodChannelOnlineOrderAlertAudio(enabled: true);
    final playing = audio.play();
    await audio.stop();
    expect(calls, ['play', 'stop']);
    completion.complete();
    await playing;
    expect(calls, ['play', 'stop']);
  });

  test('dispose is idempotent and late completion cannot restart', () async {
    final completion = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'play') await completion.future;
      return null;
    });
    final audio = MethodChannelOnlineOrderAlertAudio(enabled: true);
    final playing = audio.play();
    await audio.dispose();
    await audio.dispose();
    await audio.stop();
    await audio.play();
    expect(calls, ['play', 'dispose']);
    completion.complete();
    await playing;
    await audio.play();
    expect(calls, ['play', 'dispose']);
  });

  test(
    'unavailable native plugin is silent for every lifecycle method',
    () async {
      messenger.setMockMethodCallHandler(channel, null);
      final audio = MethodChannelOnlineOrderAlertAudio(enabled: true);
      await audio.play();
      await audio.stop();
      await audio.dispose();
    },
  );

  test(
    'native audio errors are contained and a later play can retry',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        throw PlatformException(code: 'audio_unavailable');
      });
      final audio = MethodChannelOnlineOrderAlertAudio(enabled: true);
      await audio.play();
      await audio.play();
      await audio.stop();
      await audio.dispose();
      expect(calls, ['play', 'play', 'stop', 'dispose']);
    },
  );

  test('unavailable platforms do not invoke native audio', () async {
    final audio = MethodChannelOnlineOrderAlertAudio(enabled: false);
    await audio.play();
    await audio.stop();
    await audio.dispose();
    expect(calls, isEmpty);
  });

  test('production factory is silent on a non-Android target', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final audio = MethodChannelOnlineOrderAlertAudio();
    await audio.play();
    await audio.stop();
    await audio.dispose();
    expect(calls, isEmpty);
  });

  test('provider releases transport when its container is disposed', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final container = ProviderContainer();
    await container.read(onlineOrderAlertAudioProvider).play();
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(calls, kIsWeb ? isEmpty : ['play', 'dispose']);
  });

  test('browser stays silent even with an Android target override', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final audio = MethodChannelOnlineOrderAlertAudio();
    await audio.play();
    await audio.stop();
    await audio.dispose();
    expect(calls, isEmpty);
  }, skip: !kIsWeb);
}
