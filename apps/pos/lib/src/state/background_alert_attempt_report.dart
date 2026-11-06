import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_order_alerts.dart';

/// One bounded support summary, never notification authority. No scope, IDs,
/// credential fields, payloads or exception strings enter this projection.
class BackgroundAlertAttemptReport {
  BackgroundAlertAttemptReport._(this.values);
  final Map<String, Object?> values;
  static const storageKey = 'pos.background_alert.last_attempt.v1';
  static const maxBytes = 2048;
  static const flags = [
    'permission_allowed',
    'notifications_enabled',
    'channel_present',
    'channel_importance_allowed',
    'channel_sound_present',
    'firebase_initialized',
    'token_acquired',
    'bound',
    'registration_quarantined',
    'cleanup_quarantined',
  ];

  factory BackgroundAlertAttemptReport.fromState(
    BackgroundOrderAlertState state,
    DateTime at,
  ) {
    final d = state.diagnostics;
    return BackgroundAlertAttemptReport._(
      Map.unmodifiable({
        'schema': 1,
        'at': at.toUtc().toIso8601String(),
        'result':
            state.failureReason?.name ??
            (state.enabled ? 'confirmed' : 'unknown'),
        'registration': d.registration.name,
        'permission_allowed': d.permissionAllowed,
        'notifications_enabled': d.notificationsEnabled,
        'channel_present': d.channelPresent,
        'channel_importance_allowed': d.channelImportanceAllowed,
        'channel_sound_present': d.channelSoundPresent,
        'firebase_initialized': d.firebaseInitialized,
        'token_acquired': d.tokenAcquired,
        'bound': d.bound,
        'registration_quarantined': d.registrationQuarantined,
        'cleanup_quarantined': d.cleanupQuarantined,
      }),
    );
  }

  String encode() => jsonEncode(values);

  static BackgroundAlertAttemptReport? decode(String? input) {
    if (input == null ||
        input.length > maxBytes ||
        utf8.encode(input).length > maxBytes)
      return null;
    try {
      final map = jsonDecode(input);
      final keys = {'schema', 'at', 'result', 'registration', ...flags};
      if (map is! Map ||
          map.length != keys.length ||
          map.keys.any((k) => !keys.contains(k)) ||
          map['schema'] != 1)
        return null;
      final at = map['at'];
      if (at is! String ||
          at.length > 32 ||
          !at.endsWith('Z') ||
          DateTime.tryParse(at) == null)
        return null;
      if (!{
        'unknown',
        'confirmed',
        ...BackgroundOrderAlertFailure.values.map((v) => v.name),
      }.contains(map['result']))
        return null;
      if (!BackgroundOrderAlertRegistrationResult.values.any(
        (v) => v.name == map['registration'],
      ))
        return null;
      if (flags.any((k) => map[k] != null && map[k] is! bool)) return null;
      return BackgroundAlertAttemptReport._(
        Map.unmodifiable(Map<String, Object?>.from(map)),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<BackgroundAlertAttemptReport?> load() async {
    try {
      return decode(
        (await SharedPreferences.getInstance()).getString(storageKey),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Presentation-only publication. The registration controller never reads it.
final latestBackgroundAlertAttempt =
    ValueNotifier<BackgroundAlertAttemptReport?>(null);
Future<void> _writeTail = Future<void>.value();

Future<void> saveBackgroundAlertAttempt(BackgroundOrderAlertState state) {
  final report = BackgroundAlertAttemptReport.fromState(
    state,
    DateTime.now().toUtc(),
  );
  latestBackgroundAlertAttempt.value = report;
  // Keep completion order when the platform storage callback is delayed.
  _writeTail = _writeTail.then((_) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        BackgroundAlertAttemptReport.storageKey,
        report.encode(),
      );
    } catch (_) {
      // Diagnostic persistence must never change registration or its result.
    }
  });
  return _writeTail;
}

/// Snapshot of current Android settings; it is NOT evidence of an old attempt.
class BackgroundAlertReadiness {
  BackgroundAlertReadiness._(this.values);
  final Map<String, Object?> values;

  factory BackgroundAlertReadiness.fromNative(Map raw) {
    bool? flag(String key) => raw[key] is bool ? raw[key] as bool : null;
    final version = raw['app_version'];
    final model = raw['model'];
    final sdk = raw['android_sdk'];
    final services = raw['google_play_services'];
    return BackgroundAlertReadiness._(
      Map.unmodifiable({
        'app_version':
            version is String &&
                version.length <= 32 &&
                RegExp(
                  r'^\d{1,4}\.\d{1,4}\.\d{1,5}(?:-qa\.\d{1,3})?$',
                ).hasMatch(version)
            ? version
            : null,
        'android_sdk': sdk is int && sdk >= 21 && sdk <= 100 ? sdk : null,
        'model':
            model is String &&
                model.length <= 40 &&
                RegExp(
                  r'^[A-Za-z0-9][A-Za-z0-9 ._()+/-]{0,39}$',
                ).hasMatch(model)
            ? model
            : null,
        'google_play_services':
            const {
              'available',
              'missing',
              'disabled',
              'update_required',
              'unsupported',
              'unknown',
            }.contains(services)
            ? services
            : 'unknown',
        for (final key in BackgroundAlertAttemptReport.flags.take(6))
          key: flag(key),
      }),
    );
  }
}
