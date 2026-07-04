import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/state/pos_shift_close_policy.dart';
import 'package:restoflow_pos/src/widgets/device_settings_menu.dart';

/// RF-113: the ⋮ "Close shift" entry is gated by the branch's owner-controlled
/// `pos_shift_close_enabled` policy. Default-true (demo / unread / glitch keep
/// it visible); only a confirmed `false` from the token-proven device read
/// hides it. Payments/orders are unaffected — this is visibility only.
class _FakePolicy implements DeviceShiftClosePolicyReader {
  _FakePolicy(this.value);
  final bool? value;
  @override
  Future<bool?> load() async => value;
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  DeviceShiftClosePolicyReader? reader,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (reader != null)
          posShiftClosePolicyReaderProvider.overrideWithValue(reader),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          appBar: null,
          body: Align(
            alignment: Alignment.topRight,
            child: DeviceSettingsMenu(),
          ),
        ),
      ),
    ),
  );
  // Let the policy FutureProvider resolve before the menu is opened.
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('device-settings-menu')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default (no reader wired): the Close-shift entry is visible', (
    tester,
  ) async {
    await _pumpMenu(tester);
    expect(find.byKey(const Key('device-settings-item')), findsOneWidget);
    expect(find.byKey(const Key('shift-close-item')), findsOneWidget);
  });

  testWidgets('policy enabled: the Close-shift entry is visible', (
    tester,
  ) async {
    await _pumpMenu(tester, reader: _FakePolicy(true));
    expect(find.byKey(const Key('shift-close-item')), findsOneWidget);
  });

  testWidgets(
    'policy DISABLED: the Close-shift entry is hidden (settings stays)',
    (tester) async {
      await _pumpMenu(tester, reader: _FakePolicy(false));
      // The device settings entry is unaffected; only shift-close is hidden.
      expect(find.byKey(const Key('device-settings-item')), findsOneWidget);
      expect(find.byKey(const Key('shift-close-item')), findsNothing);
    },
  );

  testWidgets(
    'read glitch (null): the entry stays visible (fail-open default)',
    (tester) async {
      await _pumpMenu(tester, reader: _FakePolicy(null));
      expect(find.byKey(const Key('shift-close-item')), findsOneWidget);
    },
  );
}
