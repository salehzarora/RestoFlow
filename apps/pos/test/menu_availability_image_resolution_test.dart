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

/// PILOT-OPERATIONS-CORRECTIONS-001 — A1 regression.
///
/// The signed-image rebuild in [posMenuProvider] used to reconstruct a partial
/// [DemoMenuItem] that dropped `availability`/`availabilityReason`, so a
/// server-authoritative Sold-out / Paused item became a normally-sellable tile
/// the moment its image URL resolved. These tests exercise the REAL-mode menu
/// parse + image-resolution path and assert the unavailable state survives.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async =>
      _handler(function, params);
}

/// Resolves EVERY requested object key to a signed URL (the success path that
/// triggered the regression). Never throws — mirrors the real fail-soft seam.
class _AllResolveResolver implements DeviceImageUrlResolver {
  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async => {for (final k in objectKeys) k: 'https://signed.example/$k'};
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

Map<String, dynamic> _menuEnvelope() => {
  'ok': true,
  'currency_code': 'ILS',
  'categories': [
    {'id': 'sides', 'name': 'Sides'},
    {'id': 'drinks', 'name': 'Drinks'},
  ],
  'items': [
    // Sold out WITH an image path (the regression case).
    {
      'id': 'sold-img',
      'name': 'Onion Rings',
      'base_price_minor': 1900,
      'menu_category_id': 'sides',
      'image_path': 'menu/onion.png',
      'availability': 'unavailable',
      'availability_reason': 'sold_out',
    },
    // Paused WITH an image path.
    {
      'id': 'paused-img',
      'name': 'Fresh Lemonade',
      'base_price_minor': 1400,
      'menu_category_id': 'drinks',
      'image_path': 'menu/lemonade.png',
      'availability': 'unavailable',
      'availability_reason': 'paused',
    },
    // Sold out with NO image path.
    {
      'id': 'sold-noimg',
      'name': 'French Fries',
      'base_price_minor': 1600,
      'menu_category_id': 'sides',
      'availability': 'unavailable',
      'availability_reason': 'sold_out',
    },
    // Available WITH an image path — the normal sellable case.
    {
      'id': 'avail-img',
      'name': 'Cola',
      'base_price_minor': 900,
      'menu_category_id': 'drinks',
      'image_path': 'menu/cola.png',
      'availability': 'available',
    },
  ],
};

ProviderContainer _realMenuContainer() {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(
        _FakeTransport((fn, p) => _menuEnvelope()),
      ),
      posSyncSessionProvider.overrideWithValue(_session),
      posImageUrlResolverProvider.overrideWithValue(_AllResolveResolver()),
    ],
  );
  return c;
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  group('A1: availability survives signed-image resolution', () {
    test('1. sold-out WITHOUT an image stays unavailable', () async {
      final c = _realMenuContainer();
      addTearDown(c.dispose);
      final menu = await c.read(posMenuProvider.future);
      final item = menu.items.firstWhere((i) => i.id == 'sold-noimg');
      expect(item.isUnavailable, isTrue);
      expect(item.imageUrl, isNull);
    });

    test('2. sold-out WHOSE image resolves stays unavailable', () async {
      final c = _realMenuContainer();
      addTearDown(c.dispose);
      final menu = await c.read(posMenuProvider.future);
      final item = menu.items.firstWhere((i) => i.id == 'sold-img');
      // The image resolved...
      expect(item.imageUrl, isNotNull);
      // ...but the item is STILL not sellable.
      expect(item.isUnavailable, isTrue);
      expect(item.availability, 'unavailable');
    });

    test('3. paused WHOSE image resolves stays unavailable', () async {
      final c = _realMenuContainer();
      addTearDown(c.dispose);
      final menu = await c.read(posMenuProvider.future);
      final item = menu.items.firstWhere((i) => i.id == 'paused-img');
      expect(item.imageUrl, isNotNull);
      expect(item.isUnavailable, isTrue);
    });

    test('4. the reason survives image resolution', () async {
      final c = _realMenuContainer();
      addTearDown(c.dispose);
      final menu = await c.read(posMenuProvider.future);
      expect(
        menu.items.firstWhere((i) => i.id == 'sold-img').availabilityReason,
        'sold_out',
      );
      expect(
        menu.items.firstWhere((i) => i.id == 'paused-img').availabilityReason,
        'paused',
      );
    });

    test('8. an available item with a resolved image stays sellable', () async {
      final c = _realMenuContainer();
      addTearDown(c.dispose);
      final menu = await c.read(posMenuProvider.future);
      final item = menu.items.firstWhere((i) => i.id == 'avail-img');
      expect(item.imageUrl, isNotNull);
      expect(item.isUnavailable, isFalse);
    });
  });

  group('DemoMenuItem.copyWith preserves fields', () {
    test('attaching an image URL keeps availability + reason', () {
      const item = DemoMenuItem(
        id: 'x',
        name: 'X',
        priceMinor: 100,
        categoryId: 'c',
        categoryName: 'C',
        imagePath: 'k',
        availability: 'unavailable',
        availabilityReason: 'sold_out',
      );
      final copy = item.copyWith(imageUrl: 'https://u');
      expect(copy.imageUrl, 'https://u');
      expect(copy.availability, 'unavailable');
      expect(copy.availabilityReason, 'sold_out');
      expect(copy.imagePath, 'k');
    });

    test(
      'withAvailability can clear the reason when returning to available',
      () {
        const item = DemoMenuItem(
          id: 'x',
          name: 'X',
          priceMinor: 100,
          categoryId: 'c',
          categoryName: 'C',
          availability: 'unavailable',
          availabilityReason: 'sold_out',
        );
        final back = item.withAvailability('available', null);
        expect(back.isUnavailable, isFalse);
        expect(back.availabilityReason, isNull);
      },
    );
  });

  group('A1: the card gate holds regardless of image', () {
    // A tile that is unavailable AND has a resolved image + option groups: the
    // add/modifier entry (onAdd) must NOT fire (5/6/7), the management gesture
    // (onManageAvailability) still must (independent of the disabled add).
    testWidgets(
      'unavailable tile with image: no add/modifier, still manageable',
      (tester) async {
        await _en();
        var added = 0;
        var managed = 0;
        const item = DemoMenuItem(
          id: 'sold-img',
          name: 'Onion Rings',
          priceMinor: 1900,
          categoryId: 'sides',
          categoryName: 'Sides',
          imagePath: 'menu/onion.png',
          imageUrl: 'https://signed.example/menu/onion.png',
          availability: 'unavailable',
          availabilityReason: 'sold_out',
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 240,
                height: 320,
                child: MenuItemCard(
                  item: item,
                  // Non-zero option groups: proves the variant/modifier entry is
                  // reached only through onAdd, which is gated off here.
                  optionGroupCount: 3,
                  onAdd: () => added++,
                  onManageAvailability: () => managed++,
                ),
              ),
            ),
          ),
        );
        // No add button rendered for an unavailable tile.
        expect(find.byIcon(Icons.add_shopping_cart), findsNothing);
        // A normal tap does not enter the add/modifier flow.
        await tester.tap(find.byKey(const Key('menu-item-sold-img')));
        await tester.pump();
        expect(added, 0);
        // The deliberate management gesture is independent and still fires.
        await tester.longPress(find.byKey(const Key('menu-item-sold-img')));
        await tester.pump();
        expect(managed, 1);
      },
    );
  });
}
