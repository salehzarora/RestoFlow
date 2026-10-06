import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';

class _Manager implements DeviceSessionHeartbeatManager {
  @override
  DeviceContext? get activeDevice => const DeviceContext(
    organizationId: 'o',
    restaurantId: 'r',
    branchId: 'b',
    deviceId: 'd',
    deviceSessionId: 's',
    deviceType: 'pos',
  );
  @override
  Stream<DeviceSessionChange> get sessionChanges => const Stream.empty();
  @override
  Future<DeviceHeartbeatResult> heartbeat() async =>
      DeviceHeartbeatResult.unavailable;
}

void main() {
  for (final portrait in [true, false]) {
    testWidgets(
      'G2 POS ${portrait ? "phone portrait cart bar" : "landscape cart bottom action"} remains hit-testable under unknown notice',
      (tester) async {
        tester.view.physicalSize = portrait
            ? const Size(390, 844)
            : const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = ProviderContainer(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: true),
            ),
          ],
        );
        addTearDown(c.dispose);
        c
            .read(cartControllerProvider.notifier)
            .addItem(
              const DemoMenuItem(
                id: 'p1',
                name: 'Meal',
                priceMinor: 1200,
                categoryId: 'mains',
                categoryName: 'Mains',
              ),
            );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: DeviceSessionAppHost(
              manager: _Manager(),
              onInvalidSession: () {},
              onRestored: (_) {},
              buildApp: (key, builder) => MaterialApp(
                navigatorKey: key,
                builder: builder,
                locale: const Locale('en'),
                localizationsDelegates: restoflowLocalizationsDelegates,
                supportedLocales: kSupportedLocales,
                home: const PosMenuScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final target = find.byKey(
          Key(portrait ? 'pos-bottom-cart-bar' : 'park-cart-button'),
        );
        if (!portrait) {
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
        }
        expect(target.hitTestable(), findsOneWidget);
        await tester.tap(target);
        await tester.pumpAndSettle();
        if (portrait) {
          expect(find.byKey(const Key('cart-sheet-close')), findsOneWidget);
        } else {
          expect(c.read(cartControllerProvider).lines, isEmpty);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
