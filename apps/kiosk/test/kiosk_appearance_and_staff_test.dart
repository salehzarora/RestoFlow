import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_kiosk/src/data/kiosk_appearance.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_logo_picker.dart';
import 'package:restoflow_kiosk/src/data/kiosk_menu_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_order_submit.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_staff_access.dart';
import 'package:restoflow_kiosk/src/widgets/kiosk_chrome.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-001-102 — device-local appearance settings, the REAL staff PIN gate,
/// the attract/menu branding surfaces, and the category-wheel photo strategy.
Map<String, dynamic> _menuEnvelope() => {
  'ok': true,
  'currency_code': 'ILS',
  'categories': [
    {'id': 'c1', 'name': 'Burgers', 'display_order': 0},
    {'id': 'c2', 'name': 'Drinks', 'display_order': 1},
    {'id': 'c3', 'name': 'Sides', 'display_order': 2},
  ],
  'items': [
    {
      'id': 'i1',
      'menu_category_id': 'c1',
      'name': 'Burger A',
      'base_price_minor': 4000,
      'availability': 'available',
      'image_path': 'org/a.png',
    },
    {
      'id': 'i2',
      'menu_category_id': 'c1',
      'name': 'Burger B',
      'base_price_minor': 4200,
      'availability': 'available',
      'image_path': 'org/b.png',
    },
    {
      'id': 'i3',
      'menu_category_id': 'c2',
      'name': 'Cola',
      'base_price_minor': 1000,
      'availability': 'available',
      'image_path': 'org/c.png',
    },
    {
      'id': 'i4',
      'menu_category_id': 'c2',
      'name': 'Sold Out Juice',
      'base_price_minor': 1200,
      'availability': 'unavailable',
      'availability_reason': 'sold_out',
      'image_path': 'org/d.png',
    },
    {
      'id': 'i5',
      'menu_category_id': 'c3',
      'name': 'Fries (no photo)',
      'base_price_minor': 900,
      'availability': 'available',
    },
  ],
  'modifiers': const [],
  'modifier_options': const [],
};

const _urls = {
  'org/a.png': 'https://signed/a',
  'org/b.png': 'https://signed/b',
  'org/c.png': 'https://signed/c',
  'org/d.png': 'https://signed/d',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KioskAppearanceSettings model', () {
    test('json roundtrip preserves every field', () {
      final settings = KioskAppearanceSettings.defaults(fallbackName: 'first')
          .copyWith(
            restaurantDisplayName: 'برجر الخرائط',
            brandTitlePrimary: 'MAPS',
            brandTitleAccent: '.',
            brandPrimaryColor: const Color(0xFFFFFFFF),
            brandAccentColor: const Color(0xFFF97316),
            tagline: const KioskLocalizedCopy(
              ar: 'طعم',
              he: 'טעם',
              en: 'Taste',
            ),
            menuHeadline: const KioskLocalizedCopy(ar: 'قائمتنا'),
            menuSubtitle: const KioskLocalizedCopy(en: 'Fresh daily'),
            attractIntervalSeconds: 6,
          );
      final restored = KioskAppearanceSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())),
        KioskAppearanceSettings.defaults(fallbackName: 'x'),
      );
      expect(restored.restaurantDisplayName, 'برجر الخرائط');
      expect(restored.brandTitlePrimary, 'MAPS');
      expect(restored.brandTitleAccent, '.');
      expect(restored.brandPrimaryColor.toARGB32(), 0xFFFFFFFF);
      expect(restored.brandAccentColor.toARGB32(), 0xFFF97316);
      expect(restored.tagline.of('he'), 'טעם');
      expect(restored.menuHeadline.of('ar'), 'قائمتنا');
      expect(restored.menuSubtitle.of('en'), 'Fresh daily');
      expect(restored.attractIntervalSeconds, 6);
    });

    test('malformed fields degrade to the fallback, never crash', () {
      final fallback = KioskAppearanceSettings.defaults(fallbackName: 'first');
      final restored = KioskAppearanceSettings.fromJson({
        'restaurant_display_name': 42,
        'brand_primary_color': 'red',
        'tagline': 'not-a-map',
        'attract_interval_seconds': 999, // not a whitelisted choice
        'logo_override_b64': 7,
      }, fallback);
      expect(restored.restaurantDisplayName, fallback.restaurantDisplayName);
      expect(restored.brandPrimaryColor, fallback.brandPrimaryColor);
      expect(restored.tagline.isEmpty, isTrue);
      expect(restored.attractIntervalSeconds, fallback.attractIntervalSeconds);
      expect(restored.logoOverridePngB64, isNull);
    });

    test('stored strings are re-bounded on load (hand-edited store)', () {
      final restored = KioskAppearanceSettings.fromJson({
        'restaurant_display_name': 'x' * 500,
        'brand_title_primary': 'y' * 500,
      }, KioskAppearanceSettings.defaults(fallbackName: 'f'));
      expect(restored.restaurantDisplayName.length, KioskAppearanceLimits.name);
      expect(restored.brandTitlePrimary.length, KioskAppearanceLimits.title);
    });

    test('REAL defaults carry no EMBER fixture identity', () {
      final real = KioskAppearanceSettings.defaults(fallbackName: 'first');
      final blob = jsonEncode(real.toJson());
      expect(blob.contains('EMBER'), isFalse);
      expect(blob.contains('BURGER HOUSE'), isFalse);
      expect(real.brandTitlePrimary, 'first');
    });

    test('demo defaults reproduce the Phase-1 EMBER identity', () {
      final demo = KioskAppearanceSettings.demoDefaults();
      expect(demo.brandTitlePrimary, 'EMBER');
      expect(demo.brandTitleAccent, '.');
      expect(demo.restaurantDisplayName, 'BURGER HOUSE');
    });

    test('hex parsing is strict #RRGGBB', () {
      expect(parseKioskHexColor('#F97316')!.toARGB32(), 0xFFF97316);
      expect(parseKioskHexColor('f97316')!.toARGB32(), 0xFFF97316);
      expect(parseKioskHexColor('#f973'), isNull);
      expect(parseKioskHexColor('# zz7316'), isNull);
      expect(parseKioskHexColor('red'), isNull);
    });

    test('corrupt stored logo reference fails safely to no-override', () {
      final settings = KioskAppearanceSettings.demoDefaults().copyWith(
        logoOverridePngB64: '!!!not-base64!!!',
      );
      expect(settings.logoOverrideBytes, isNull);
    });

    test('appearance storage never carries auth/order material', () {
      final json = KioskAppearanceSettings.defaults(
        fallbackName: 'first',
      ).toJson();
      final keys = json.keys.join(' ');
      for (final forbidden in ['token', 'session', 'order', 'pin', 'price']) {
        expect(keys.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('logo byte validation', () {
    test('rejects non-image magic bytes and oversized files', () async {
      final junk = await validateKioskLogoBytes(
        Uint8List.fromList(List.filled(64, 7)),
      );
      expect(junk.error, KioskLogoPickError.unsupportedType);

      final hugePngHeader = Uint8List(KioskAppearanceLimits.logoBytes + 1);
      hugePngHeader.setRange(0, 4, const [0x89, 0x50, 0x4E, 0x47]);
      final huge = await validateKioskLogoBytes(hugePngHeader);
      expect(huge.error, KioskLogoPickError.tooLarge);

      // Right magic, garbage body: must fail DECODE, not be stored.
      final fakePng = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        ...List.filled(64, 1),
      ]);
      final undecodable = await validateKioskLogoBytes(fakePng);
      expect(undecodable.error, KioskLogoPickError.undecodable);
    });
  });

  group('device-scoped persistence', () {
    test('save/load per device; another device does not inherit; corrupt '
        'JSON and reset fall back to defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = KioskAppearanceStore(prefs);
      final defaults = KioskAppearanceSettings.defaults(fallbackName: 'A');

      final custom = defaults.copyWith(brandTitlePrimary: 'MAPS');
      await store.save('device-A', custom);
      expect(
        store.load('device-A', defaults)!.brandTitlePrimary,
        'MAPS',
        reason: 'restart restores the saved appearance',
      );
      expect(
        store.load('device-B', defaults),
        isNull,
        reason: 'another device id must not inherit device A settings',
      );

      await prefs.setString(
        KioskAppearanceStore.keyFor('device-C'),
        '{not json',
      );
      expect(
        store.load('device-C', defaults),
        isNull,
        reason: 'malformed stored JSON fails safely to defaults',
      );

      await store.clear('device-A');
      expect(store.load('device-A', defaults), isNull);
    });

    test('controller: demo default is EMBER; real scope loads the store and '
        'reset returns to real defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = KioskAppearanceStore(prefs);
      await store.save(
        'dev-1',
        KioskAppearanceSettings.defaults(
          fallbackName: 'first',
        ).copyWith(brandTitlePrimary: 'SAVED'),
      );

      final demo = ProviderContainer();
      addTearDown(demo.dispose);
      expect(
        demo.read(kioskAppearanceProvider).brandTitlePrimary,
        'EMBER',
        reason: 'demo keeps the fixture identity',
      );

      final real = ProviderContainer(
        overrides: [
          kioskRealModeProvider.overrideWithValue(true),
          kioskAppearanceStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(real.dispose);
      real.read(kioskAppearanceScopeProvider.notifier).state = (
        deviceId: 'dev-1',
        fallbackName: 'first',
      );
      expect(real.read(kioskAppearanceProvider).brandTitlePrimary, 'SAVED');

      await real.read(kioskAppearanceProvider.notifier).resetToDefaults();
      expect(real.read(kioskAppearanceProvider).brandTitlePrimary, 'first');
      expect(
        store.load('dev-1', KioskAppearanceSettings.demoDefaults()),
        isNull,
      );
    });
  });

  group('attract carousel + category photo selection', () {
    KioskMenuData menu() => mapKioskMenuEnvelope(_menuEnvelope())!;

    test('one representative per category first, deterministic, capped, '
        'available-with-photo only', () {
      final urls = kioskAttractCarouselUrls(menu(), _urls);
      // Pass 1 diversity: c1 -> a, c2 -> c (i4 sold out never chosen),
      // c3 has no photo; pass 2 fills with b.
      expect(urls, [
        'https://signed/a',
        'https://signed/c',
        'https://signed/b',
      ]);
      expect(kioskAttractCarouselUrls(menu(), _urls, max: 2), [
        'https://signed/a',
        'https://signed/c',
      ]);
      expect(kioskAttractCarouselUrls(menu(), const {}), isEmpty);
    });

    test('category images: A gets an A image, B gets a B image, no photo -> '
        'absent (icon fallback), unresolved URL -> absent', () {
      final byCategory = kioskCategoryImageUrls(menu(), _urls);
      expect(byCategory['c1'], 'https://signed/a');
      expect(byCategory['c2'], 'https://signed/c');
      expect(byCategory.containsKey('c3'), isFalse);

      final partial = kioskCategoryImageUrls(menu(), const {
        'org/c.png': 'https://signed/c',
      });
      expect(partial.containsKey('c1'), isFalse, reason: 'failed signing');
      expect(partial['c2'], 'https://signed/c');
    });
  });

  group('REAL staff gate', () {
    KioskStaffAccess access(
      Map<String, Object? Function(Map<String, dynamic>)> handlers,
    ) {
      final store = InMemoryDeviceSessionSecretStore()
        ..write(
          const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 't'),
        );
      return KioskStaffAccess(
        transport: _FakeTransport(handlers),
        secretStore: store,
      );
    }

    test('lists token-proven staff; PIN outcomes map typed', () async {
      final gate = access({
        'list_device_staff': (_) => {
          'ok': true,
          'staff': [
            {
              'employee_profile_id': 'e-1',
              'display_name': 'Dana',
              'role': 'manager',
            },
          ],
        },
        'start_pin_session': (p) =>
            p['p_pin_verifier'] == '4321' ? 'pin-session-uuid' : null,
      });
      final staff = await gate.listStaff();
      expect(staff.fold((s) => s.single.displayName, (f) => '$f'), 'Dana');

      expect(
        await gate.verifyPin(
          deviceSessionId: 'ds-1',
          employeeProfileId: 'e-1',
          pin: '4321',
        ),
        isNull,
        reason: 'valid staff PIN unlocks',
      );
      expect(
        await gate.verifyPin(
          deviceSessionId: 'ds-1',
          employeeProfileId: 'e-1',
          pin: '2468', // the FIXTURE pin is not a real credential here
        ),
        KioskStaffPinError.wrongPin,
      );
    });

    test(
      'server lockout (42501) and network map to their own errors',
      () async {
        final locked = access({
          'start_pin_session': (_) => const SyncTransportException(
            SyncTransportErrorKind.auth,
            code: '42501',
          ),
        });
        expect(
          await locked.verifyPin(
            deviceSessionId: 'ds',
            employeeProfileId: 'e',
            pin: '1111',
          ),
          KioskStaffPinError.locked,
        );
        final offline = access({
          'start_pin_session': (_) =>
              const SyncTransportException(SyncTransportErrorKind.transient),
        });
        expect(
          await offline.verifyPin(
            deviceSessionId: 'ds',
            employeeProfileId: 'e',
            pin: '1111',
          ),
          KioskStaffPinError.network,
        );
      },
    );
  });

  group('102 widget surfaces', () {
    Future<ProviderContainer> pumpShell(
      WidgetTester tester, {
      List<Override> overrides = const [],
    }) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              locale: Locale(
                ref.watch(kioskFlowProvider.select((s) => s.lang)),
              ),
              debugShowCheckedModeBanner: false,
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: const KioskShell(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      return container;
    }

    testWidgets('demo attract keeps EMBER and has NO "Now preparing" chip', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(find.text('EMBER.'), findsWidgets); // badge + center wordmark
      expect(find.text('BURGER HOUSE'), findsWidgets);
      expect(find.textContaining('#038'), findsNothing);
      expect(find.textContaining('#0'), findsNothing);
    });

    testWidgets('REAL attract renders the editable brand, no EMBER anywhere', (
      tester,
    ) async {
      final container = await pumpShell(
        tester,
        overrides: [kioskRealModeProvider.overrideWithValue(true)],
      );
      container.read(kioskAppearanceScopeProvider.notifier).state = (
        deviceId: 'dev-1',
        fallbackName: 'first',
      );
      await container
          .read(kioskAppearanceProvider.notifier)
          .save(
            KioskAppearanceSettings.defaults(fallbackName: 'first').copyWith(
              restaurantDisplayName: 'برجر الخرائط',
              brandTitlePrimary: 'MAPS',
              brandTitleAccent: '.',
              tagline: const KioskLocalizedCopy(ar: 'طعم يأخذك في مغامرة'),
            ),
          );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('EMBER'), findsNothing);
      expect(find.text('برجر الخرائط'.toUpperCase()), findsWidgets);
      expect(find.textContaining('طعم يأخذك'), findsWidgets);
      expect(find.textContaining('#038'), findsNothing);
    });

    testWidgets('brand badge falls back to the monogram for LONG wordmarks '
        'instead of clipping', (tester) async {
      final container = await pumpShell(
        tester,
        overrides: [kioskRealModeProvider.overrideWithValue(true)],
      );
      container.read(kioskAppearanceScopeProvider.notifier).state = (
        deviceId: 'dev-1',
        fallbackName: 'first',
      );
      await container
          .read(kioskAppearanceProvider.notifier)
          .save(
            KioskAppearanceSettings.defaults(fallbackName: 'first').copyWith(
              restaurantDisplayName: 'Burger House',
              brandTitlePrimary: 'Burger',
              brandTitleAccent: 'House',
            ),
          );
      await tester.pump(const Duration(milliseconds: 200));
      // The centered hero wordmark still renders the full rich text, but the
      // small ring badge shows the monogram, so nothing clips mid-word.
      final badge = find.byType(KioskBrandBadge);
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('BH')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: badge, matching: find.textContaining('Burger')),
        findsNothing,
      );
    });

    testWidgets('REAL menu heading/subtitle come from appearance settings', (
      tester,
    ) async {
      final container = await pumpShell(
        tester,
        overrides: [kioskRealModeProvider.overrideWithValue(true)],
      );
      await container
          .read(kioskAppearanceProvider.notifier)
          .save(
            KioskAppearanceSettings.defaults(fallbackName: 'first').copyWith(
              menuHeadline: const KioskLocalizedCopy(ar: 'شو حابب تطلب؟'),
              menuSubtitle: const KioskLocalizedCopy(ar: 'من مطبخنا مباشرة'),
            ),
          );
      final flow = container.read(kioskFlowProvider.notifier);
      flow.startFromAttract();
      flow.pickService(KioskServiceType.takeaway);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('شو حابب تطلب؟'), findsOneWidget);
      expect(find.text('من مطبخنا مباشرة'), findsOneWidget);
      expect(find.text('ما الذي تشتهيه اليوم؟'), findsNothing);
    });

    testWidgets('REAL triple-tap opens the REAL staff gate; wrong PIN stays '
        'locked; valid staff PIN opens settings with the Appearance editor', (
      tester,
    ) async {
      final store = InMemoryDeviceSessionSecretStore()
        ..write(
          const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 't'),
        );
      final gate = KioskStaffAccess(
        transport: _FakeTransport({
          'list_device_staff': (_) => {
            'ok': true,
            'staff': [
              {
                'employee_profile_id': 'e-1',
                'display_name': 'Dana',
                'role': 'manager',
              },
            ],
          },
          'start_pin_session': (p) =>
              p['p_pin_verifier'] == '4321' ? 'pin-uuid' : null,
        }),
        secretStore: store,
      );
      final container = await pumpShell(
        tester,
        overrides: [
          kioskRealModeProvider.overrideWithValue(true),
          kioskStaffAccessProvider.overrideWithValue(gate),
          kioskStaffSettingsEnabledProvider.overrideWithValue(false),
        ],
      );
      container
          .read(kioskDeviceContextProvider.notifier)
          .state = const DeviceContext(
        organizationId: 'org',
        branchId: 'branch',
        deviceId: 'dev-1',
        deviceSessionId: 'ds-1',
        displayName: 'first',
      );

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('kiosk-staff-dots')));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        container.read(kioskFlowProvider).sheet,
        KioskSheet.staffPin,
        reason: 'real mode opens the REAL gate, not the fixture 2468 sheet',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('kiosk-staff-e-1')));
      await tester.pump(const Duration(milliseconds: 200));

      // Fixture 2468 is NOT a real credential here — locked out politely.
      for (final d in ['2', '4', '6', '8']) {
        await tester.tap(find.text(d).last);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('kiosk-staff-pin-error')), findsOneWidget);
      expect(
        container.read(kioskFlowProvider).screen,
        isNot(KioskScreen.settings),
      );

      // The REAL staff PIN unlocks.
      for (final d in ['4', '3', '2', '1']) {
        await tester.tap(find.text(d).last);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(kioskFlowProvider).screen, KioskScreen.settings);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const Key('kiosk-appearance-save')),
        findsOneWidget,
        reason: 'real settings expose the Appearance editor',
      );
      // Fixture-only controls are NOT presented as real.
      expect(
        find.byKey(const Key('kiosk-settings-tables-toggle')),
        findsNothing,
      );

      // Exit relocks (full reset back to attract).
      await tester.tap(find.byKey(const Key('kiosk-settings-exit')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(kioskFlowProvider).screen, KioskScreen.attract);
    });

    testWidgets('demo triple-tap still opens the FIXTURE pin sheet', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('kiosk-staff-dots')));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(kioskFlowProvider).sheet, KioskSheet.pin);
    });
  });
}

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.handlers);
  final Map<String, Object? Function(Map<String, dynamic>)> handlers;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    final h = handlers[function];
    if (h == null) throw StateError('unexpected RPC $function');
    final out = h(params);
    if (out is Exception) throw out;
    return out;
  }
}
