import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _Manager implements DeviceSessionHeartbeatManager {
  @override
  DeviceContext? get activeDevice => const DeviceContext(
    organizationId: 'o',
    restaurantId: 'r',
    branchId: 'b',
    deviceId: 'd',
    deviceSessionId: 's',
    deviceType: 'kds',
  );
  @override
  Stream<DeviceSessionChange> get sessionChanges => const Stream.empty();
  @override
  Future<DeviceHeartbeatResult> heartbeat() async =>
      DeviceHeartbeatResult.unavailable;
}

void main() {
  testWidgets(
    'G2 real KDS bottom ticket action remains hit-testable under notice',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ticket = KdsTicketView(
        kitchenTicketId: 'o:grill',
        stationId: 'grill',
        items: List.generate(
          15,
          (i) => KdsItemView(name: 'Plate $i', quantity: 1),
        ),
      );
      var advanced = 0;
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        DeviceSessionAppHost(
          manager: _Manager(),
          onInvalidSession: () {},
          onRestored: (_) {},
          buildApp: (key, builder) => MaterialApp(
            navigatorKey: key,
            builder: builder,
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: KdsScreen(
              tickets: [ticket],
              onAdvanced: (_, _) => advanced++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.widgetWithText(FilledButton, l10n.kdsServedAction);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(tester.getCenter(action).dy, greaterThan(600));
      expect(action.hitTestable(), findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(advanced, 1);
      expect(ticket.status, KitchenTicketStatus.bumped);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
