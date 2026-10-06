import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _Manager
    implements
        DeviceSessionHeartbeatManager,
        DeviceSessionRecoveryManager,
        DeviceSessionLocalRepairManager {
  final changes = StreamController<DeviceSessionChange>.broadcast();
  final blocks = StreamController<bool>.broadcast();
  @override
  final activeDevice = const DeviceContext(
    organizationId: 'org',
    restaurantId: 'restaurant',
    branchId: 'branch',
    deviceId: 'device',
    deviceSessionId: 'session',
    deviceType: 'pos',
  );
  @override
  bool protectedCallsBlocked = false;
  @override
  int get consecutiveUnavailable => 3;
  @override
  Stream<bool> get protectedCallBlockChanges => blocks.stream;
  @override
  Stream<DeviceSessionChange> get sessionChanges => changes.stream;
  @override
  Future<DeviceHeartbeatResult> heartbeat() async => protectedCallsBlocked
      ? DeviceHeartbeatResult.unavailable
      : DeviceHeartbeatResult.active;
  @override
  Future<void> clearLocalPairing() async {}

  void block(bool value) {
    protectedCallsBlocked = value;
    blocks.add(value);
  }

  Future<void> dispose() async {
    await changes.close();
    await blocks.close();
  }
}

Future<void> _reveal(WidgetTester tester) async {
  final hold = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('device-session-unavailable-title'))),
  );
  await tester.pump(const Duration(seconds: 5));
  await hold.up();
  await tester.pump();
  expect(find.byKey(const Key('device-session-repair')), findsOneWidget);
}

Widget _unavailable(
  _Manager manager, {
  required bool compact,
  VoidCallback? onRetry,
}) => MaterialApp(
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  home: Scaffold(
    body: DeviceSessionUnavailableView(
      compact: compact,
      staffOnlyRepair: true,
      repairManager: manager,
      onRetry: onRetry ?? () {},
    ),
  ),
);

void main() {
  testWidgets('K3 disposing a revealed kiosk cancels the conceal timer', (
    tester,
  ) async {
    final manager = _Manager();
    await tester.pumpWidget(_unavailable(manager, compact: true));
    await tester.pumpAndSettle();
    await _reveal(tester);
    await tester.pumpWidget(const SizedBox());
    await manager.dispose();
    // The widget-test timer invariant must pass without advancing the clock
    // to consume an orphaned 30-second timer after disposal.
  });

  testWidgets(
    'K2 visible notice consumes top inset once without enlarging app toolbar',
    (tester) async {
      final manager = _Manager();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.padding = const FakeViewPadding(top: 40);
      tester.view.viewPadding = const FakeViewPadding(top: 40);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        DeviceSessionAppHost(
          manager: manager,
          onInvalidSession: () {},
          onRestored: (_) {},
          buildApp: (key, builder) => MaterialApp(
            navigatorKey: key,
            builder: builder,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              appBar: AppBar(title: const Text('Application')),
              body: const Text('Body'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 40);
      expect(
        tester.getSize(find.byType(NavigationToolbar)).height,
        kToolbarHeight,
      );
      manager.block(true);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(NavigationToolbar)).height,
        kToolbarHeight,
      );
      expect(
        tester.getSize(find.byType(AppBar)).height,
        kToolbarHeight,
        reason: 'the notice already owns the 40px system inset',
      );
      expect(
        tester.getTopLeft(find.byType(DeviceSessionUnavailableView)).dy,
        40,
      );
      expect(
        tester.getTopLeft(find.byType(AppBar)).dy,
        tester.getBottomLeft(find.byType(DeviceSessionUnavailableView)).dy,
      );
      expect(
        MediaQuery.sizeOf(tester.element(find.text('Body'))),
        tester.getSize(find.byType(Navigator)),
        reason: 'the navigator keeps the actual remaining viewport size',
      );
      final insetToolbarHeight = tester.getSize(find.byType(AppBar)).height;
      tester.view.padding = const FakeViewPadding();
      tester.view.viewPadding = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(AppBar)).height,
        insetToolbarHeight,
        reason: 'the app bar is the same height for 0px and 40px insets',
      );
      tester.view.padding = const FakeViewPadding(top: 40);
      tester.view.viewPadding = const FakeViewPadding(top: 40);
      manager.block(false);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 40);
      expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);
      await tester.pumpWidget(const SizedBox());
      await manager.dispose();
    },
  );

  for (final compact in [false, true]) {
    testWidgets(
      'K3 kiosk repair reveal expires after thirty seconds compact=$compact',
      (tester) async {
        final manager = _Manager();
        await tester.pumpWidget(_unavailable(manager, compact: compact));
        await tester.pumpAndSettle();
        await _reveal(tester);
        await tester.pump(const Duration(milliseconds: 29999));
        expect(find.byKey(const Key('device-session-repair')), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.byKey(const Key('device-session-repair')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await manager.dispose();
      },
    );

    testWidgets(
      'K3 retry hides kiosk repair and a new hold gets a fresh window compact=$compact',
      (tester) async {
        final manager = _Manager();
        var retries = 0;
        await tester.pumpWidget(
          _unavailable(manager, compact: compact, onRetry: () => retries++),
        );
        await tester.pumpAndSettle();
        await _reveal(tester);
        await tester.pump(const Duration(seconds: 10));
        await tester.tap(find.byKey(const Key('device-session-retry')));
        await tester.pump();
        expect(retries, 1);
        expect(find.byKey(const Key('device-session-repair')), findsNothing);
        await _reveal(tester);
        // The first reveal's old timeout would expire after 15 more seconds.
        await tester.pump(const Duration(seconds: 16));
        expect(find.byKey(const Key('device-session-repair')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 30));
        expect(tester.takeException(), isNull);
        await manager.dispose();
      },
    );
  }
}
