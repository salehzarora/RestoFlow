import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notification-only delegation. Never contains a POS pairing/PIN credential,
/// customer data, a customer status capability or a printing operation.
abstract class BackgroundOrderAlertBridge {
  Future<Map<String, dynamic>> prepare({bool requestPermission = false});
  Future<bool> bind(Map<String, dynamic> binding);
  Future<void> pending(Map<String, dynamic> snapshot);
  Future<void> suspend({bool retainOptIn = false});
  Future<void> disable();
  Future<bool> consumeInboxTap();
  void setHints({
    required VoidCallback tokenChanged,
    required VoidCallback pendingHint,
  });
  Future<void> dispose();
}

/// Optional observable cleanup for the controller. Legacy logout/unpair callers
/// retain their nonthrowing void methods; no native method or payload changes.
abstract interface class BackgroundOrderAlertRevocation {
  Future<bool> revoke({bool suspend = false, bool retainOptIn = false});
}

final backgroundOrderAlertsBuildEnabledProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      const bool.fromEnvironment('BIZBOT_BACKGROUND_ORDER_ALERTS'),
);

final backgroundOrderAlertBridgeProvider = Provider<BackgroundOrderAlertBridge>(
  (ref) {
    final bridge = MethodChannelBackgroundOrderAlertBridge();
    ref.onDispose(() => unawaited(bridge.dispose()));
    return bridge;
  },
);

class MethodChannelBackgroundOrderAlertBridge
    implements BackgroundOrderAlertBridge, BackgroundOrderAlertRevocation {
  MethodChannelBackgroundOrderAlertBridge({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('restoflow.pos/background_order_alert');
  final MethodChannel _channel;
  bool _disposed = false;

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    if (_disposed || kIsWeb || defaultTargetPlatform != TargetPlatform.android)
      return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      // Notification failure cannot interrupt existing Inbox discovery/orders.
      // Never log native diagnostics or registration secrets.
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> prepare({bool requestPermission = false}) async {
    final value = await _call<Map>('prepare', {
      'request_permission': requestPermission,
    });
    return value == null
        ? const {'available': false, 'enabled': false}
        : Map<String, dynamic>.from(value);
  }

  @override
  Future<bool> bind(Map<String, dynamic> binding) async =>
      await _call<bool>('bind', binding) ?? false;
  @override
  Future<void> pending(Map<String, dynamic> snapshot) async =>
      _call<void>('pending', snapshot);
  @override
  Future<void> suspend({bool retainOptIn = false}) async =>
      revoke(suspend: true, retainOptIn: retainOptIn);
  @override
  Future<void> disable() async => revoke();
  @override
  Future<bool> revoke({bool suspend = false, bool retainOptIn = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      // Revocation remains possible after disposal, under controller ownership.
      await _channel.invokeMethod<void>(
        suspend ? 'suspend' : 'disable',
        suspend ? {'retain_opt_in': retainOptIn} : null,
      );
      return true; // native void success returns null, not a boolean
    } catch (_) {
      return false; // no raw platform diagnostics or credentials escape
    }
  }

  @override
  Future<bool> consumeInboxTap() async =>
      await _call<bool>('consumeInboxTap') ?? false;
  @override
  void setHints({
    required VoidCallback tokenChanged,
    required VoidCallback pendingHint,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (_disposed) return;
      if (call.method == 'tokenChanged') tokenChanged();
      if (call.method == 'pendingHint') pendingHint();
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    // Flutter engine teardown after normal Activity closure is not logout.
    // Its native delegation remains bounded and independently re-verified;
    // explicit security/session writers revoke before teardown.
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}
