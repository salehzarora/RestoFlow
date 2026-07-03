import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// Menu/media sprint: the REAL pos_menu parse consumes items[].image_path and
/// batch-resolves signed URLs ONCE per load through the device resolver —
/// FAIL-SOFT at every step (no resolver / resolver error / per-key denial =>
/// imageless items, never an error). The card renders an image band when a URL
/// resolved and falls back to the tinted category-icon band otherwise.

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

const String _imagedPath = 'org-1/rest-1/branch-1/menu_item/item-1/img-1.png';

class _MenuTransport implements SyncRpcTransport {
  int calls = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls++;
    return <String, dynamic>{
      'ok': true,
      'entity': 'menu',
      'currency_code': 'ILS',
      'categories': [
        {'id': 'cat-1', 'name': 'Food', 'display_order': 1},
      ],
      'items': [
        {
          'id': 'item-1',
          'menu_category_id': 'cat-1',
          'name': 'Burger',
          'base_price_minor': 5000,
          'image_path': _imagedPath,
        },
        {
          'id': 'item-2',
          'menu_category_id': 'cat-1',
          'name': 'Cola',
          'base_price_minor': 900,
          'image_path': null,
        },
      ],
      'sizes': const [],
      'variants': const [],
      'modifiers': const [],
      'modifier_options': const [],
      'server_ts': '2026-07-03T09:00:00Z',
    };
  }
}

ProviderContainer _container({DeviceImageUrlResolver? resolver}) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(_MenuTransport()),
      posSyncSessionProvider.overrideWithValue(_session),
      if (resolver != null)
        posImageUrlResolverProvider.overrideWithValue(resolver),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'real menu load resolves signed URLs once, only for imaged items',
    () async {
      final resolver = FakeDeviceImageUrlResolver(
        urls: const {_imagedPath: 'https://storage.example/signed/img-1.png'},
      );
      final container = _container(resolver: resolver);

      final menu = await container.read(posMenuProvider.future);

      // ONE batch request carrying exactly the imaged item's key.
      expect(resolver.requests, [
        [_imagedPath],
      ]);
      final burger = menu.items.singleWhere((i) => i.name == 'Burger');
      final cola = menu.items.singleWhere((i) => i.name == 'Cola');
      expect(burger.imagePath, _imagedPath);
      expect(burger.imageUrl, 'https://storage.example/signed/img-1.png');
      expect(cola.imagePath, isNull);
      expect(cola.imageUrl, isNull);
    },
  );

  test(
    'a resolver failure is fail-soft: menu loads imageless, no throw',
    () async {
      final container = _container(
        resolver: FakeDeviceImageUrlResolver(error: 'storage down'),
      );

      final menu = await container.read(posMenuProvider.future);

      final burger = menu.items.singleWhere((i) => i.name == 'Burger');
      expect(burger.imagePath, _imagedPath); // parsed
      expect(burger.imageUrl, isNull); // unresolved -> icon-band fallback
      expect(menu.items, hasLength(2));
    },
  );

  test('no resolver wired (dormant real mode): menu loads imageless', () async {
    final container = _container();

    final menu = await container.read(posMenuProvider.future);

    expect(menu.items.map((i) => i.imageUrl), everyElement(isNull));
  });

  testWidgets('the card keeps its contracts and falls back to the icon band '
      'when the image cannot load', (tester) async {
    const item = DemoMenuItem(
      id: 'item-1',
      name: 'Burger',
      priceMinor: 5000,
      categoryId: 'burgers',
      categoryName: 'Burgers',
      imagePath: _imagedPath,
      // The test HTTP client rejects every request, so this exercises the
      // errorBuilder fallback path.
      imageUrl: 'https://storage.example/signed/img-1.png',
    );
    var added = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 188,
            child: MenuItemCard(item: item, onAdd: () => added++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Contracts: Card tile, name + integer-minor price, the canonical add icon.
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('Burger'), findsOneWidget);
    expect(find.text('₪50.00'), findsOneWidget);
    expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
    // Failed image load -> the tinted category-icon band (fallback, no error).
    expect(find.byIcon(Icons.lunch_dining), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_shopping_cart));
    expect(added, 1);
  });

  testWidgets(
    'an imageless item renders the tinted icon band (demo unchanged)',
    (tester) async {
      const item = DemoMenuItem(
        id: 'cola',
        name: 'Cola',
        priceMinor: 900,
        categoryId: 'drinks',
        categoryName: 'Drinks',
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 220,
              height: 188,
              child: MenuItemCard(item: item, onAdd: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.local_bar), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );
}
