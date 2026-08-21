import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/data/kiosk_menu_data.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_kiosk/src/widgets/kiosk_chrome.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-001-PREREQ-083 — live product photos through the SHARED resolver
/// seam, strictly fail-soft: one batch per successful menu read, unique keys
/// only, per-key misses and total signing failure both degrade to the
/// approved V2 no-photo fallback while the menu stays fully usable. Nothing
/// here talks to a network — the resolver is the package's own fake.
const _pathA = 'org-1/rest-1/global/menu_item/i1/a.png';
const _pathB = 'org-1/rest-1/branch-1/menu_item/i2/b.png';
const _urlA = 'https://signed.invalid/a.png';

Map<String, dynamic> _envelope({int colaPriceMinor = 1000}) => {
  'ok': true,
  'currency_code': 'ILS',
  'categories': [
    {'id': 'c1', 'name': 'Burgers', 'display_order': 0, 'icon_key': 'burger'},
  ],
  'items': [
    {
      'id': 'i1',
      'menu_category_id': 'c1',
      'name': 'Classic Burger',
      'base_price_minor': 4000,
      'image_path': _pathA,
      'availability': 'available',
    },
    {
      'id': 'i2',
      'menu_category_id': 'c1',
      'name': 'Special Burger',
      'base_price_minor': 5200,
      'image_path': _pathB,
      'availability': 'available',
    },
    // A duplicate key (must not be requested twice) and a photo-less item.
    {
      'id': 'i3',
      'menu_category_id': 'c1',
      'name': 'Twin Burger',
      'base_price_minor': 4100,
      'image_path': _pathA,
    },
    {
      'id': 'i4',
      'menu_category_id': 'c1',
      'name': 'Cola',
      'base_price_minor': colaPriceMinor,
      'image_path': '',
    },
  ],
  'modifiers': <Map<String, Object?>>[],
};

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.handler);
  final Future<Object?> Function(String fn, Map<String, dynamic> params)
  handler;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) =>
      handler(function, params);
}

KioskLiveReads _reads(Map<String, dynamic> envelope) {
  final store = InMemoryDeviceSessionSecretStore()
    ..write(DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok-1'));
  return KioskLiveReads(
    transport: _FakeTransport((fn, p) async => envelope),
    secretStore: store,
  );
}

/// The real-mode menu mirroring from `kioskRealOverrides`, minus the seams
/// that need a pairing repository (not under test here).
List<Override> _liveMenuOverrides(
  KioskLiveReads reads,
  DeviceImageUrlResolver? resolver,
) => [
  kioskLiveReadsProvider.overrideWithValue(reads),
  if (resolver != null) kioskImageResolverProvider.overrideWithValue(resolver),
  kioskMenuDataProvider.overrideWith((ref) {
    final live = ref.watch(kioskLiveProvider.select((s) => s.menu));
    return live ?? const KioskMenuData.empty();
  }),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KioskLiveController image resolution', () {
    test(
      'one batch of UNIQUE non-empty keys per successful menu read',
      () async {
        final resolver = FakeDeviceImageUrlResolver(urls: {_pathA: _urlA});
        final container = ProviderContainer(
          overrides: _liveMenuOverrides(_reads(_envelope()), resolver),
        );
        addTearDown(container.dispose);
        await container.read(kioskLiveProvider.notifier).loadMenu();
        // Exactly one signing request; duplicates collapsed; '' excluded.
        expect(resolver.requests, hasLength(1));
        expect(resolver.requests.single.toSet(), {_pathA, _pathB});
        // Published URLs: the resolved key present, the denied key ABSENT.
        final state = container.read(kioskLiveProvider);
        expect(state.imageUrls, {_pathA: _urlA});
        expect(state.menu, isNotNull);
      },
    );

    test('a signing failure degrades to no photos, menu stays good', () async {
      final resolver = FakeDeviceImageUrlResolver(error: StateError('down'));
      final container = ProviderContainer(
        overrides: _liveMenuOverrides(_reads(_envelope()), resolver),
      );
      addTearDown(container.dispose);
      await container.read(kioskLiveProvider.notifier).loadMenu();
      final state = container.read(kioskLiveProvider);
      expect(state.imageUrls, isEmpty);
      expect(state.menu, isNotNull);
      expect(state.menuError, isNull);
    });

    test(
      'no resolver (demo mode) publishes no URLs and never crashes',
      () async {
        final container = ProviderContainer(
          overrides: _liveMenuOverrides(_reads(_envelope()), null),
        );
        addTearDown(container.dispose);
        await container.read(kioskLiveProvider.notifier).loadMenu();
        expect(container.read(kioskLiveProvider).imageUrls, isEmpty);
        expect(container.read(kioskLiveProvider).menu, isNotNull);
      },
    );

    test(
      'a fresh load REPLACES the URL map (stale keys do not linger)',
      () async {
        final resolver = FakeDeviceImageUrlResolver(urls: {_pathA: _urlA});
        final container = ProviderContainer(
          overrides: _liveMenuOverrides(_reads(_envelope()), resolver),
        );
        addTearDown(container.dispose);
        final controller = container.read(kioskLiveProvider.notifier);
        await controller.loadMenu();
        expect(container.read(kioskLiveProvider).imageUrls, {_pathA: _urlA});
        // The next read resolves nothing (e.g. the photo was removed).
        resolver.urls.clear();
        await controller.loadMenu();
        expect(container.read(kioskLiveProvider).imageUrls, isEmpty);
      },
    );
  });

  group('KioskMenuImage', () {
    Widget host(Widget child) =>
        MaterialApp(home: SizedBox(width: 300, height: 300, child: child));

    testWidgets('a resolved URL renders the network image over the well', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const KioskMenuImage(url: _urlA, fallback: Text('WELL'))),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, _urlA);
      // The approved fallback stays underneath (shows through on failure).
      expect(find.text('WELL'), findsOneWidget);
    });

    testWidgets('no URL + no asset renders ONLY the fallback', (tester) async {
      await tester.pumpWidget(
        host(const KioskMenuImage(fallback: Text('WELL'))),
      );
      expect(find.text('WELL'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('no URL + fixture asset keeps the Phase-1 asset path', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const KioskMenuImage(
            asset: 'assets/images/smash.png',
            fallback: Text('WELL'),
          ),
        ),
      );
      expect(find.byType(KioskFixtureImage), findsOneWidget);
    });
  });

  group('live menu photo wiring end-to-end (fakes only)', () {
    Future<ProviderContainer> pumpLiveShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: _liveMenuOverrides(
          _reads(_envelope()),
          FakeDeviceImageUrlResolver(urls: {_pathA: _urlA}),
        ),
      );
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
      await container.read(kioskLiveProvider.notifier).loadMenu();
      final flow = container.read(kioskFlowProvider.notifier);
      flow.startFromAttract();
      flow.pickService(KioskServiceType.takeaway);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      return container;
    }

    bool isNetworkImageWith(Widget w, String url) =>
        w is Image &&
        w.image is NetworkImage &&
        (w.image as NetworkImage).url == url;

    testWidgets(
      'the card shows the resolved photo; the unresolved card falls back',
      (tester) async {
        await pumpLiveShell(tester);
        // i1 resolved → its card carries the network image.
        expect(
          find.byWidgetPredicate((w) => isNetworkImageWith(w, _urlA)),
          findsWidgets,
        );
        // i2's key was denied → its card renders the approved name well,
        // and no network image for its path exists anywhere.
        expect(find.text('Special Burger'), findsWidgets);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Image &&
                w.image is NetworkImage &&
                (w.image as NetworkImage).url.contains('b.png'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('the item sheet hero reuses the SAME resolved URL', (
      tester,
    ) async {
      final container = await pumpLiveShell(tester);
      container.read(kioskFlowProvider.notifier).openItem('i1');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byWidgetPredicate((w) => isNetworkImageWith(w, _urlA)),
        findsWidgets,
      );
    });
  });
}
