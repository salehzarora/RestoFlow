import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_menu_data.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_activation.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-001 Phase 3 — widget coverage for the real-mode surfaces:
/// activation (+ every typed error), the pairing gate's three routes, the
/// live-menu presentation states, the live table picker, the stale-cart
/// banner and the Phase-3 ordering gate.
class _FakePairing
    implements DevicePairingRepository, DeviceSessionOutcomeManager {
  _FakePairing({this.pairResult, this.restoreResult});

  Result<DeviceContext, PairingFailure>? pairResult;
  DeviceRestoreOutcome? restoreResult;
  final pairCalls = <(String, String)>[];
  int restoreCalls = 0;

  static DeviceContext context() => const DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-1',
    deviceId: 'dev-1',
    deviceType: 'kiosk',
    deviceSessionId: 'sess-1',
  );

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async {
    pairCalls.add((code, deviceType));
    return pairResult ?? Success(context());
  }

  @override
  Future<DeviceContext?> restore({String? expectedDeviceType}) async =>
      switch (await restoreOutcome(expectedDeviceType: expectedDeviceType)) {
        DeviceSessionRestored(:final context) => context,
        _ => null,
      };

  @override
  Future<DeviceRestoreOutcome> restoreOutcome({
    String? expectedDeviceType,
  }) async {
    restoreCalls++;
    return restoreResult ?? const DeviceSessionRestoreRejected();
  }

  @override
  Future<void> unpair() async {}
}

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: home,
      ),
    );

/// The canonical kiosk viewport for gate/activation pumps (the staff surfaces
/// scroll at any size, but the tests pin the real frame like every Phase-1
/// suite does).
void _useKioskViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

KioskMenuData _liveMenu({int colaPrice = 1000, bool colaAvailable = true}) =>
    mapKioskMenuEnvelope({
      'ok': true,
      'currency_code': 'ILS',
      'categories': [
        {'id': 'c1', 'name': 'Drinks', 'display_order': 0, 'icon_key': null},
      ],
      'items': [
        {
          'id': 'cola',
          'menu_category_id': 'c1',
          'name': 'Cola',
          'base_price_minor': colaPrice,
          if (!colaAvailable) 'availability': 'unavailable',
          if (!colaAvailable) 'availability_reason': 'sold_out',
        },
      ],
      'modifiers': const [],
      'modifier_options': const [],
    })!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {});

  group('activation screen', () {
    testWidgets('submits the code with device type hardcoded to kiosk', (
      tester,
    ) async {
      _useKioskViewport(tester);
      final pairing = _FakePairing();
      DeviceContext? paired;
      await tester.pumpWidget(
        _app(
          KioskActivationScreen(pairing: pairing, onPaired: (c) => paired = c),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('kiosk-activation-code')),
        'ABC123',
      );
      await tester.tap(find.byKey(const Key('kiosk-activation-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(pairing.pairCalls.single, ('ABC123', 'kiosk'));
      expect(paired?.deviceType, 'kiosk');
    });

    testWidgets('shows the typed error copy per failure kind', (tester) async {
      _useKioskViewport(tester);
      for (final (kind, needle) in [
        (PairingFailureKind.invalidCode, 'not valid'),
        (PairingFailureKind.expired, 'expired'),
        (PairingFailureKind.wrongScope, 'different device type'),
        (PairingFailureKind.lockedOut, 'Too many attempts'),
        (PairingFailureKind.network, 'No connection'),
      ]) {
        final pairing = _FakePairing(pairResult: Failure(PairingFailure(kind)));
        await tester.pumpWidget(
          _app(KioskActivationScreen(pairing: pairing, onPaired: (_) {})),
        );
        await tester.enterText(
          find.byKey(const Key('kiosk-activation-code')),
          'BAD',
        );
        await tester.tap(find.byKey(const Key('kiosk-activation-submit')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('kiosk-activation-error')))
              .data,
          contains(needle),
          reason: '$kind',
        );
      }
    });
  });

  group('pairing gate', () {
    testWidgets('rejected restore lands on activation (never the shell)', (
      tester,
    ) async {
      _useKioskViewport(tester);
      final pairing = _FakePairing(
        restoreResult: const DeviceSessionRestoreRejected(),
      );
      await tester.pumpWidget(
        _app(
          KioskPairingGate(
            outcomes: pairing,
            pairing: pairing,
            shellBuilder: (_) => const Text('CUSTOMER-SHELL'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('kiosk-activation-code')), findsOneWidget);
      expect(find.text('CUSTOMER-SHELL'), findsNothing);
    });

    testWidgets('restored kiosk session enters the shell', (tester) async {
      _useKioskViewport(tester);
      final pairing = _FakePairing(
        restoreResult: DeviceSessionRestored(_FakePairing.context()),
      );
      await tester.pumpWidget(
        _app(
          KioskPairingGate(
            outcomes: pairing,
            pairing: pairing,
            shellBuilder: (_) => const Text('CUSTOMER-SHELL'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('CUSTOMER-SHELL'), findsOneWidget);
    });

    testWidgets('offline restore shows the reconnect state with retry — '
        'never a stale customer flow', (tester) async {
      _useKioskViewport(tester);
      final pairing = _FakePairing(
        restoreResult: const DeviceSessionRestoreOffline(),
      );
      await tester.pumpWidget(
        _app(
          KioskPairingGate(
            outcomes: pairing,
            pairing: pairing,
            shellBuilder: (_) => const Text('CUSTOMER-SHELL'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('kiosk-reconnect-retry')), findsOneWidget);
      expect(find.text('CUSTOMER-SHELL'), findsNothing);
      // Retry re-validates; a now-live session enters the shell.
      pairing.restoreResult = DeviceSessionRestored(_FakePairing.context());
      await tester.tap(find.byKey(const Key('kiosk-reconnect-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('CUSTOMER-SHELL'), findsOneWidget);
      expect(pairing.restoreCalls, 2);
    });
  });

  group('real-mode shell wiring', () {
    Future<ProviderContainer> pumpShell(
      WidgetTester tester, {
      required List<Override> overrides,
      String screen = 'menu',
    }) async {
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      );
      final controller = container.read(kioskFlowProvider.notifier);
      controller.startFromAttract();
      controller.pickService(KioskServiceType.takeaway);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      return container;
    }

    testWidgets(
      'live menu drives the wheel + grid (1 category stays coherent)',
      (tester) async {
        final menu = _liveMenu();
        await pumpShell(
          tester,
          overrides: [
            kioskMenuDataProvider.overrideWithValue(menu),
            kioskMenuStatusProvider.overrideWithValue(KioskMenuStatus.ready),
          ],
        );
        expect(find.text('Cola'), findsWidgets);
        expect(find.text('Drinks'), findsWidgets);
      },
    );

    testWidgets('menu loading + reconnect states render honestly', (
      tester,
    ) async {
      await pumpShell(
        tester,
        overrides: [
          kioskMenuDataProvider.overrideWithValue(const KioskMenuData.empty()),
          kioskMenuStatusProvider.overrideWithValue(KioskMenuStatus.reconnect),
        ],
      );
      expect(find.textContaining('Reconnecting'), findsOneWidget);
    });

    testWidgets(
      'an UNAVAILABLE item is disabled: no sheet opens, badge shows',
      (tester) async {
        final menu = _liveMenu(colaAvailable: false);
        final container = await pumpShell(
          tester,
          overrides: [
            kioskMenuDataProvider.overrideWithValue(menu),
            kioskMenuStatusProvider.overrideWithValue(KioskMenuStatus.ready),
          ],
        );
        expect(
          find.byKey(const Key('kiosk-item-unavailable-cola')),
          findsOneWidget,
        );
        await tester.tap(find.text('Cola').first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(container.read(kioskFlowProvider).sheet, isNull);
      },
    );

    testWidgets('the Phase-3 ordering gate blocks placeOrder with the honest '
        'notice instead of a fake confirmation', (tester) async {
      final container = await pumpShell(
        tester,
        overrides: [
          kioskMenuDataProvider.overrideWithValue(_liveMenu()),
          kioskMenuStatusProvider.overrideWithValue(KioskMenuStatus.ready),
          kioskOrderingEnabledProvider.overrideWithValue(false),
        ],
      );
      final controller = container.read(kioskFlowProvider.notifier);
      controller.openItem('cola');
      controller.submitDraft();
      controller.placeOrder();
      await tester.pump(const Duration(milliseconds: 300));
      final state = container.read(kioskFlowProvider);
      expect(state.screen, isNot(KioskScreen.confirm));
      expect(state.lastOrder, isNull);
      expect(state.toast, 'ordering-unavailable');
      expect(state.cart, isNotEmpty); // nothing was silently discarded
    });

    testWidgets('the stale-cart banner renders and reconfirm clears it', (
      tester,
    ) async {
      final menu = _liveMenu();
      final container = await pumpShell(
        tester,
        overrides: [
          kioskMenuDataProvider.overrideWithValue(menu),
          kioskMenuStatusProvider.overrideWithValue(KioskMenuStatus.ready),
        ],
      );
      final controller = container.read(kioskFlowProvider.notifier);
      controller.openItem('cola');
      controller.submitDraft();
      controller.revalidateCart(_liveMenu(colaPrice: 1100));
      controller.openCart();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('kiosk-cart-stale')), findsOneWidget);
      // NOTE: the banner's refresh re-captures against the CURRENT
      // kioskMenuDataProvider (still the 1000 menu here) and clears the flag.
      await tester.tap(find.byKey(const Key('kiosk-cart-stale-refresh')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(kioskFlowProvider).cartStale, isFalse);
      expect(find.byKey(const Key('kiosk-cart-stale')), findsNothing);
    });

    testWidgets('live tables: four states render, only available selects; '
        'failure shows retry', (tester) async {
      final zones = mapKioskTablesEnvelope({
        'ok': true,
        'tables': [
          {
            'id': 't1',
            'label': 'T1',
            'seats': 4,
            'section_id': 's1',
            'section_name': 'Main Hall',
            'section_display_order': 0,
            'effective_state': 'available',
          },
          {
            'id': 't2',
            'label': 'T2',
            'seats': 2,
            'section_id': 's1',
            'section_name': 'Main Hall',
            'section_display_order': 0,
            'effective_state': 'occupied',
          },
          {
            'id': 't3',
            'label': 'T3',
            'seats': 2,
            'section_id': 's1',
            'section_name': 'Main Hall',
            'section_display_order': 0,
            'effective_state': 'reserved',
          },
          {
            'id': 't4',
            'label': 'T4',
            'seats': 2,
            'section_id': 's1',
            'section_name': 'Main Hall',
            'section_display_order': 0,
            'effective_state': 'out_of_service',
          },
        ],
      })!;
      final container = ProviderContainer(
        overrides: [
          kioskTablesViewProvider.overrideWithValue((
            zones: zones,
            status: KioskTablesStatus.ready,
            live: true,
          )),
        ],
      );
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      );
      final controller = container.read(kioskFlowProvider.notifier);
      controller.startFromAttract();
      controller.pickService(KioskServiceType.dineIn);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Main Hall'), findsOneWidget);
      expect(find.byKey(const Key('kiosk-tables-refresh')), findsOneWidget);
      // Only the available table toggles a selection.
      await tester.tap(find.text('T2'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(kioskFlowProvider).selectedTable, isNull);
      await tester.tap(find.text('T1'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(kioskFlowProvider).selectedTable, 'T1');
    });

    testWidgets('table read failure never lets a stale floor look live', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          kioskTablesViewProvider.overrideWithValue((
            zones: const <KioskFixtureZone>[],
            status: KioskTablesStatus.reconnect,
            live: true,
          )),
        ],
      );
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      );
      final controller = container.read(kioskFlowProvider.notifier);
      controller.startFromAttract();
      controller.pickService(KioskServiceType.dineIn);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('kiosk-tables-retry')), findsOneWidget);
      expect(find.text('T1'), findsNothing);
    });
  });
}
