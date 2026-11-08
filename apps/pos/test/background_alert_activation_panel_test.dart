import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/media/background_order_alert_bridge.dart';
import 'package:restoflow_pos/src/state/background_alert_attempt_report.dart';
import 'package:restoflow_pos/src/state/background_order_alerts.dart';
import 'package:restoflow_pos/src/widgets/background_alert_activation_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Bridge extends BackgroundOrderAlertBridge
    implements BackgroundOrderAlertActivationSupport {
  int reads = 0, prepares = 0, binds = 0;
  bool settingsResult = true;
  final settings = <bool>[];
  Map<String, dynamic> snapshot = {
    'app_version': '0.0.76-qa.1',
    'android_sdk': 35,
    'model': 'Synthetic Model',
    'permission_allowed': false,
    'notifications_enabled': false,
    'channel_present': true,
    'channel_importance_allowed': true,
    'channel_sound_present': true,
    'google_play_services': 'available',
    'firebase_initialized': true,
    'fcm_token': 'MUST_NOT_LEAK',
    'status_secret': 'MUST_NOT_LEAK',
  };
  @override
  Future<Map<String, dynamic>> activationStatus() async {
    reads++;
    return snapshot;
  }

  @override
  Future<bool> openNotificationSettings({required bool channel}) async {
    settings.add(channel);
    return settingsResult;
  }

  @override
  Future<Map<String, dynamic>> prepare({bool requestPermission = false}) async {
    prepares++;
    return {};
  }

  @override
  Future<bool> bind(Map<String, dynamic> binding) async {
    binds++;
    return false;
  }

  @override
  Future<bool> consumeInboxTap() async => false;
  @override
  Future<void> pending(Map<String, dynamic> snapshot) async {}
  @override
  Future<void> suspend({bool retainOptIn = false}) async {}
  @override
  Future<void> disable() async {}
  @override
  Future<void> dispose() async {}
  @override
  void setHints({
    required VoidCallback tokenChanged,
    required VoidCallback pendingHint,
  }) {}
}

const rejected = BackgroundOrderAlertState(
  available: true,
  failed: true,
  failureReason: BackgroundOrderAlertFailure.registrationRejected,
  diagnostics: BackgroundOrderAlertDiagnostics(
    permissionAllowed: true,
    notificationsEnabled: true,
    channelPresent: true,
    channelImportanceAllowed: true,
    channelSoundPresent: true,
    firebaseInitialized: true,
    tokenAcquired: true,
    registration: BackgroundOrderAlertRegistrationResult.rejected,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    latestBackgroundAlertAttempt.value = null;
  });

  test(
    'exact typed stages persist; rejected never infers an ownership branch',
    () async {
      await saveBackgroundAlertAttempt(rejected);
      final report = (await BackgroundAlertAttemptReport.load())!;
      expect(report.values['result'], 'registrationRejected');
      expect(report.values['token_acquired'], true);
      expect(report.values['bound'], null);
      expect(report.encode(), isNot(contains('INSTALLATION_CONFLICT')));
      expect(report.encode(), isNot(contains('TOKEN_CONFLICT')));
      expect(utf8.encode(report.encode()).length, lessThan(2048));
      latestBackgroundAlertAttempt.value = null; // process-local state lost
      expect(
        (await BackgroundAlertAttemptReport.load())!.encode(),
        report.encode(),
      );
    },
  );

  test('corrupt, unknown, oversized persisted summaries fail closed', () {
    final report = BackgroundAlertAttemptReport.fromState(
      rejected,
      DateTime.utc(2026),
    ).values;
    expect(
      BackgroundAlertAttemptReport.decode(
        jsonEncode({...report, 'token': 'secret'}),
      ),
      null,
    );
    expect(
      BackgroundAlertAttemptReport.decode(
        jsonEncode({...report, 'result': 'raw error secret'}),
      ),
      null,
    );
    expect(
      BackgroundAlertAttemptReport.decode(
        jsonEncode({...report, 'bound': 'true'}),
      ),
      null,
    );
    expect(
      BackgroundAlertAttemptReport.decode(
        jsonEncode({...report, 'at': 'secret'}),
      ),
      null,
    );
    expect(BackgroundAlertAttemptReport.decode('x' * 2049), null);
    expect(BackgroundAlertAttemptReport.decode('{broken'), null);
  });

  test('readiness accepts only fixed keys and bounded metadata', () {
    final safe = BackgroundAlertReadiness.fromNative({
      'app_version': '0.0.76\nAuthorization: secret',
      'model': 'private@example.test',
      'android_sdk': '35',
      'permission_allowed': 'true',
      'google_play_services': 'raw exception secret',
      'firebase_initialized': false,
      'token': 'MUST_NOT_LEAK',
    }).values;
    expect(safe['app_version'], null);
    expect(safe['model'], null);
    expect(safe['android_sdk'], null);
    expect(safe['permission_allowed'], null);
    expect(safe['google_play_services'], 'unknown');
    expect(safe['firebase_initialized'], false);
    expect(jsonEncode(safe), isNot(contains('MUST_NOT_LEAK')));
    expect(
      BackgroundAlertReadiness.fromNative({'model': 'x' * 41}).values['model'],
      null,
    );
  });

  test(
    'latest completed result replaces earlier one without an attempt history',
    () async {
      await saveBackgroundAlertAttempt(rejected);
      await saveBackgroundAlertAttempt(
        const BackgroundOrderAlertState(
          available: true,
          enabled: true,
          diagnostics: BackgroundOrderAlertDiagnostics(
            registration: BackgroundOrderAlertRegistrationResult.confirmed,
            bound: true,
          ),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {BackgroundAlertAttemptReport.storageKey});
      expect(
        (await BackgroundAlertAttemptReport.load())!.values['result'],
        'confirmed',
      );
    },
  );

  for (final locale in ['ar', 'he', 'en']) {
    testWidgets(
      'bounded diagnostic panel, settings and copy $locale at mobile width',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          BackgroundAlertAttemptReport.storageKey:
              BackgroundAlertAttemptReport.fromState(
                rejected,
                DateTime.utc(2026),
              ).encode(),
        });
        final bridge = _Bridge();
        String? clipboard;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData')
                clipboard = (call.arguments as Map)['text'] as String;
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backgroundOrderAlertBridgeProvider.overrideWithValue(bridge),
            ],
            child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: kSupportedLocales,
              localizationsDelegates: restoflowLocalizationsDelegates,
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: BackgroundAlertActivationPanel(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          Directionality.of(tester.element(find.byType(ExpansionTile))),
          locale == 'en' ? TextDirection.ltr : TextDirection.rtl,
        );
        await tester.tap(find.byKey(const Key('background-alert-diagnostics')));
        await tester.pumpAndSettle();
        expect(find.textContaining('registrationRejected'), findsWidgets);
        final settings = find.byKey(const Key('background-alert-settings'));
        await tester.ensureVisible(settings);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(bridge.settings, [false]); // permission => app settings
        final reads = bridge.reads;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(bridge.reads, greaterThan(reads));
        expect(bridge.prepares, 0);
        expect(bridge.binds, 0);
        final copy = find.byKey(const Key('background-alert-copy'));
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(clipboard, isNotNull);
        expect(clipboard, isNot(contains('MUST_NOT_LEAK')));
        final summary = jsonDecode(clipboard!) as Map;
        expect(summary['attempt_kind'], 'previous');
        expect(summary['attempt']['permission_allowed'], true);
        expect(summary['current_readiness']['permission_allowed'], false);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('channel failure opens channel settings without activation', (
    tester,
  ) async {
    final bridge = _Bridge()
      ..snapshot = {
        'permission_allowed': true,
        'notifications_enabled': true,
        'channel_present': true,
        'channel_sound_present': false,
      };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backgroundOrderAlertBridgeProvider.overrideWithValue(bridge),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BackgroundAlertActivationPanel(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('background-alert-diagnostics')));
    await tester.pumpAndSettle();
    final settings = find.byKey(const Key('background-alert-settings'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(bridge.settings, [true]);
    expect(bridge.prepares, 0);
    expect(bridge.binds, 0);
  });

  testWidgets('settings failure provides safe manual action without activation', (
    tester,
  ) async {
    final bridge = _Bridge()..settingsResult = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backgroundOrderAlertBridgeProvider.overrideWithValue(bridge),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BackgroundAlertActivationPanel(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('background-alert-diagnostics')));
    await tester.pumpAndSettle();
    final settings = find.byKey(const Key('background-alert-settings'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not open Settings. Open Android Settings, then Apps, POS, and Notifications.',
      ),
      findsOneWidget,
    );
    expect(bridge.prepares, 0);
    expect(bridge.binds, 0);
  });
}
