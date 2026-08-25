import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_kiosk/src/data/kiosk_appearance.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_menu_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_order_submit.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/screens/printer_settings.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_kiosk/src/state/kiosk_receipt_branding.dart';
import 'package:restoflow_kiosk/src/state/kiosk_staff_access.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-001-103 — widget surfaces: the §16 confirmation-slip branding chain
/// (Dashboard logo -> real name -> appearance name; EMBER only in demo), the
/// §10 accepted-only hook wiring, and the §8 printer settings section.

// ---- compact real-submit harness (kiosk_order_submit_test pattern) --------

Map<String, dynamic> _menuEnvelope() => {
  'ok': true,
  'currency_code': 'ILS',
  'categories': [
    {'id': 'c1', 'name': 'Burgers', 'display_order': 0},
  ],
  'items': [
    {
      'id': 'i1',
      'menu_category_id': 'c1',
      'name': 'Classic Burger',
      'base_price_minor': 4000,
      'availability': 'available',
    },
  ],
  'modifiers': const [],
  'modifier_options': const [],
};

Map<String, dynamic> _taxEnvelope() => {
  'ok': true,
  'tax_enabled': false,
  'tax_rate_bp': 0,
  'tax_mode': 'exclusive',
};

const _acceptedEnvelope = {
  'ok': true,
  'order_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeffff',
  'revision': 1,
  'idempotency_replay': false,
  'auto_completed': false,
  'order_status': 'submitted',
};

class _Rpc {
  _Rpc(this.handlers);
  final Map<String, Object? Function(Map<String, dynamic> params)> handlers;
  final calls = <(String, Map<String, dynamic>)>[];
}

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.rpc);
  final _Rpc rpc;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    rpc.calls.add((function, Map<String, dynamic>.from(params)));
    final h = rpc.handlers[function];
    if (h == null) throw StateError('unexpected RPC $function');
    var out = h(params);
    if (out is Future) out = await out;
    if (out is Exception) throw out;
    return out;
  }
}

InMemoryDeviceSessionSecretStore _credStore() =>
    InMemoryDeviceSessionSecretStore()
      ..write(DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 't-1'));

({ProviderContainer container, _Rpc rpc}) _harness({
  List<Override> extraOverrides = const [],
  Map<String, Object? Function(Map<String, dynamic>)>? overrides,
}) {
  final rpc = _Rpc({
    'kiosk_menu': (_) => _menuEnvelope(),
    'kiosk_tables': (_) => {'ok': true, 'sections': [], 'tables': []},
    'get_device_branch_tax': (_) => _taxEnvelope(),
    'kiosk_submit_order': (p) => {
      ..._acceptedEnvelope,
      'order_id': p['p_order_id'],
    },
    ...?overrides,
  });
  final transport = _FakeTransport(rpc);
  final store = _credStore();
  final container = ProviderContainer(
    overrides: [
      kioskLiveReadsProvider.overrideWithValue(
        KioskLiveReads(transport: transport, secretStore: store),
      ),
      kioskOrderSubmitterProvider.overrideWithValue(
        KioskOrderSubmitter(transport: transport, secretStore: store),
      ),
      kioskBranchTaxReaderProvider.overrideWithValue(
        KioskBranchTaxReader(transport: transport, secretStore: store),
      ),
      kioskMenuDataProvider.overrideWith((ref) {
        final live = ref.watch(kioskLiveProvider.select((s) => s.menu));
        return live ?? const KioskMenuData.empty();
      }),
      ...extraOverrides,
    ],
  );
  final flow = container.read(kioskFlowProvider.notifier);
  flow.updateSettings(
    container
        .read(kioskFlowProvider)
        .settings
        .copyWith(tablePickerEnabled: false),
  );
  return (container: container, rpc: rpc);
}

Future<void> _fillCartAndOpen(ProviderContainer c) async {
  await c.read(kioskLiveProvider.notifier).loadMenu();
  final flow = c.read(kioskFlowProvider.notifier);
  flow.startFromAttract();
  flow.pickService(KioskServiceType.takeaway);
  flow.openItem('i1');
  expect(flow.submitDraft(), isTrue);
  flow.openCart();
  for (var i = 0; i < 30; i++) {
    await null;
  }
}

/// A tiny valid 1×1 transparent PNG (kTransparentImage).
final Uint8List _kPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Future<void> _pumpShell(WidgetTester tester, ProviderContainer container) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
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
}

Future<void> _placeAndSettle(WidgetTester tester, ProviderContainer c) async {
  c.read(kioskFlowProvider.notifier).placeOrder();
  for (var i = 0; i < 40; i++) {
    await tester.pump(Duration.zero);
  }
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('accepted-order hook wiring (§10)', () {
    test(
      'acceptance fires the hook EXACTLY once with the accepted id',
      () async {
        final fired = <(String?, String)>[];
        final h = _harness(
          extraOverrides: [
            kioskAcceptedOrderHookProvider.overrideWith(
              (ref) =>
                  (order, lang, dispatch) => fired.add((order.orderId, lang)),
            ),
          ],
        );
        addTearDown(h.container.dispose);
        await _fillCartAndOpen(h.container);
        h.container.read(kioskFlowProvider.notifier).placeOrder();
        for (var i = 0; i < 40; i++) {
          await null;
        }
        expect(fired.length, 1);
        expect(fired.single.$1, isNotNull);
        expect(
          h.container.read(kioskFlowProvider).lastOrder?.orderId,
          fired.single.$1,
        );
      },
    );

    test('a REJECTED submit never fires the hook', () async {
      final fired = <String?>[];
      final h = _harness(
        overrides: {
          'kiosk_submit_order': (_) => {
            'ok': false,
            'error': 'menu_changed',
            'error_code': 'item_unavailable',
          },
        },
        extraOverrides: [
          kioskAcceptedOrderHookProvider.overrideWith(
            (ref) =>
                (order, lang, dispatch) => fired.add(order.orderId),
          ),
        ],
      );
      addTearDown(h.container.dispose);
      await _fillCartAndOpen(h.container);
      h.container.read(kioskFlowProvider.notifier).placeOrder();
      for (var i = 0; i < 40; i++) {
        await null;
      }
      expect(fired, isEmpty);
      expect(h.container.read(kioskFlowProvider).lastOrder, isNull);
    });
  });

  group('confirmation slip branding (§16)', () {
    testWidgets('REAL + Dashboard logo => logo on the slip, ZERO EMBER', (
      tester,
    ) async {
      final h = _harness(
        extraOverrides: [
          kioskRealModeProvider.overrideWithValue(true),
          kioskReceiptBrandingProvider.overrideWith(
            (ref) async => KioskReceiptBranding(
              restaurantName: 'Maps Burger',
              logoBytes: _kPng,
              logoMime: 'image/png',
            ),
          ),
        ],
      );
      addTearDown(h.container.dispose);
      await _fillCartAndOpen(h.container);
      await _pumpShell(tester, h.container);
      await _placeAndSettle(tester, h.container);
      expect(h.container.read(kioskFlowProvider).screen, KioskScreen.confirm);
      expect(find.byKey(const Key('kiosk-slip-receipt-logo')), findsOneWidget);
      expect(find.textContaining('EMBER'), findsNothing);
      expect(find.textContaining('BURGER HOUSE'), findsNothing);
    });

    testWidgets('REAL + disabled/missing logo => the REAL restaurant name', (
      tester,
    ) async {
      final h = _harness(
        extraOverrides: [
          kioskRealModeProvider.overrideWithValue(true),
          kioskReceiptBrandingProvider.overrideWith(
            (ref) async =>
                const KioskReceiptBranding(restaurantName: 'Maps Burger'),
          ),
        ],
      );
      addTearDown(h.container.dispose);
      await _fillCartAndOpen(h.container);
      await _pumpShell(tester, h.container);
      await _placeAndSettle(tester, h.container);
      final name = tester.widget<Text>(
        find.byKey(const Key('kiosk-slip-restaurant-name')),
      );
      expect(name.data, 'Maps Burger');
      expect(find.textContaining('EMBER'), findsNothing);
    });

    testWidgets('REAL + branding read failure => the appearance display name '
        '(still real), ZERO EMBER', (tester) async {
      final h = _harness(
        extraOverrides: [
          kioskRealModeProvider.overrideWithValue(true),
          kioskReceiptBrandingProvider.overrideWith(
            (ref) async => null, // no session / RPC failure
          ),
        ],
      );
      addTearDown(h.container.dispose);
      h.container.read(kioskAppearanceScopeProvider.notifier).state = (
        deviceId: 'dev-1',
        fallbackName: 'Owner Kiosk',
      );
      await _fillCartAndOpen(h.container);
      await _pumpShell(tester, h.container);
      await _placeAndSettle(tester, h.container);
      final name = tester.widget<Text>(
        find.byKey(const Key('kiosk-slip-restaurant-name')),
      );
      expect(name.data, 'Owner Kiosk');
      expect(find.textContaining('EMBER'), findsNothing);
    });

    testWidgets('DEMO slip keeps the fixture EMBER header unchanged', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpShell(tester, container);
      final flow = container.read(kioskFlowProvider.notifier);
      flow.updateSettings(
        container
            .read(kioskFlowProvider)
            .settings
            .copyWith(tablePickerEnabled: false),
      );
      flow.startFromAttract();
      flow.pickService(KioskServiceType.takeaway);
      flow.openItem(kioskFixtureMenu.first.items.first.id);
      expect(flow.submitDraft(), isTrue);
      flow.openCart();
      await tester.pump(const Duration(milliseconds: 400));
      flow.placeOrder();
      await tester.pump(const Duration(milliseconds: 700));
      expect(container.read(kioskFlowProvider).screen, KioskScreen.confirm);
      expect(find.textContaining('EMBER'), findsWidgets);
    });
  });

  group('attract media modes (§7)', () {
    testWidgets('photo -> image -> video -> photo switching disposes cleanly '
        '(no leaked timers/controllers fail the test harness)', (tester) async {
      final container = ProviderContainer(
        overrides: [kioskRealModeProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      container.read(kioskAppearanceScopeProvider.notifier).state = (
        deviceId: 'dev-1',
        fallbackName: 'R',
      );
      await _pumpShell(tester, container);
      final appearance = container.read(kioskAppearanceProvider.notifier);
      for (final mode in [
        KioskAttractMediaMode.customImage,
        KioskAttractMediaMode.customVideo,
        KioskAttractMediaMode.selectedMenuPhotos,
      ]) {
        await appearance.save(
          container
              .read(kioskAppearanceProvider)
              .copyWith(
                attractMediaMode: mode,
                customImageRef: 'attract_image_1.png',
                customVideoRef: 'attract_video_1.mp4',
              ),
        );
        await tester.pump(const Duration(milliseconds: 400));
      }
      // Unmount everything: a leaked periodic timer or live ticker would
      // fail the test right here.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('printer settings section (§8)', () {
    Future<void> pumpSection(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
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
            home: const Scaffold(
              backgroundColor: Color(0xFF05080F),
              body: SingleChildScrollView(child: KioskPrinterSection()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('web: native printing hidden behind the honest note', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [nativePrintingAvailableProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);
      await pumpSection(tester, container);
      expect(
        find.byKey(const Key('kiosk-printer-web-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('kiosk-printer-autoprint')), findsNothing);
    });

    testWidgets('device: auto-print defaults OFF and persists ON; network save '
        'lands under the KIOSK namespace; test print reports status', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final tested = <NetworkPrinterConfig>[];
      final container = ProviderContainer(
        overrides: [
          nativePrintingAvailableProvider.overrideWithValue(true),
          nativePrinterNamespaceProvider.overrideWithValue('kiosk'),
          nativePrinterDeviceIdProvider.overrideWith(
            (ref) => ref.watch(kioskDeviceContextProvider)?.deviceId,
          ),
          networkPrinterTesterProvider.overrideWithValue(
            _FakeNetworkTester(tested),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(kioskDeviceContextProvider.notifier)
          .state = const DeviceContext(
        organizationId: 'org',
        branchId: 'br',
        deviceId: 'dev-1',
      );
      await pumpSection(tester, container);

      // auto-print: default OFF, tap -> ON persisted under the kiosk key.
      final toggle = find.byKey(const Key('kiosk-printer-autoprint'));
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 300));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('restoflow.autoprint.kiosk.receipt.dev-1'), true);

      // invalid host refused with a visible reason; nothing persisted.
      await tester.enterText(
        find.byKey(const Key('kiosk-printer-host')),
        '   ',
      );
      await tester.tap(find.byKey(const Key('kiosk-printer-save')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('kiosk-printer-status')), findsOneWidget);
      expect(prefs.getString('restoflow.printer.network.kiosk.dev-1'), isNull);

      // valid save persists the config in the KIOSK namespace ONLY.
      await tester.enterText(
        find.byKey(const Key('kiosk-printer-host')),
        '192.168.1.50',
      );
      await tester.enterText(
        find.byKey(const Key('kiosk-printer-port')),
        '9100',
      );
      await tester.tap(find.byKey(const Key('kiosk-printer-save')));
      await tester.pump(const Duration(milliseconds: 300));
      final saved = prefs.getString('restoflow.printer.network.kiosk.dev-1');
      expect(saved, isNotNull);
      expect(saved, contains('192.168.1.50'));
      expect(
        prefs.getKeys().where((k) => k.contains('.pos.')),
        isEmpty,
        reason: 'kiosk settings must never touch a POS key',
      );

      // test print goes through the shared tester seam; no order RPC exists
      // anywhere in this widget.
      await tester.tap(find.byKey(const Key('kiosk-printer-test')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tested, hasLength(1));
      expect(tested.single.host, '192.168.1.50');
    });
  });
}

class _FakeNetworkTester implements NetworkPrinterTester {
  _FakeNetworkTester(this.calls);
  final List<NetworkPrinterConfig> calls;

  @override
  Future<pp.PrintResult> testPrint(
    NetworkPrinterConfig config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  }) async {
    calls.add(config);
    return const pp.PrintResult.success();
  }
}
