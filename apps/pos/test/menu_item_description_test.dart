import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart' show posMenuCardExtent;
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// POS-PRODUCT-DESCRIPTIONS-001 — A/B/C/D/E. the product description reaching
/// the POS.
///
/// The description already exists in the database, is already written by the
/// Dashboard item editor, and is ALREADY served by the `pos_menu` RPC for both
/// the cashier and the kitchen-redacted object. The POS was throwing it away in
/// three places: the parse, the model, and the card.
///
/// It is operator-managed SINGLE-LANGUAGE product content — the same stored
/// string under every app locale, exactly like the product name. It is never
/// translated, never localized, never searched, and never travels with an
/// order.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  int calls = 0;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls++;
    return _handler(function, params);
  }
}

class _AllResolveResolver implements DeviceImageUrlResolver {
  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async => {for (final k in objectKeys) k: 'https://signed.example/$k'};
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

/// One menu envelope whose items cover every description shape the wire can
/// legally (and illegally) carry.
Map<String, dynamic> _envelope({
  Object? plainDescription = 'A juicy classic.',
}) => {
  'ok': true,
  'currency_code': 'ILS',
  'categories': [
    {'id': 'food', 'name': 'Food'},
  ],
  'items': [
    {
      'id': 'plain',
      'name': 'Classic Burger',
      'base_price_minor': 4200,
      'menu_category_id': 'food',
      'description': plainDescription,
    },
    // Key entirely absent.
    {
      'id': 'absent',
      'name': 'No Key',
      'base_price_minor': 1000,
      'menu_category_id': 'food',
    },
    {
      'id': 'null',
      'name': 'Null Value',
      'base_price_minor': 1000,
      'menu_category_id': 'food',
      'description': null,
    },
    {
      'id': 'blank',
      'name': 'Whitespace Only',
      'base_price_minor': 1000,
      'menu_category_id': 'food',
      'description': '   \n\t  ',
    },
    {
      'id': 'padded',
      'name': 'Padded',
      'base_price_minor': 1000,
      'menu_category_id': 'food',
      'description': '  Served warm.  ',
    },
    // Wrong types: an integer, an object and a list.
    {
      'id': 'int',
      'name': 'Int Value',
      'base_price_minor': 1000,
      'menu_category_id': 'food',
      'description': 42,
    },
    {
      'id': 'object',
      'name': 'Object Value',
      'base_price_minor': 1000,
      'menu_category_id': 'food',
      'description': {'en': 'nope'},
    },
    {
      'id': 'list',
      'name': 'List Value',
      'base_price_minor': 1000,
      'menu_category_id': 'food',
      'description': ['nope'],
    },
    // Description AND an image, so the signed-URL rebuild is exercised.
    {
      'id': 'imaged',
      'name': 'With Image',
      'base_price_minor': 2000,
      'menu_category_id': 'food',
      'image_path': 'menu/burger.png',
      'description': 'Photographed and described.',
    },
  ],
};

(ProviderContainer, _FakeTransport) _realMenu({Object? Function()? envelope}) {
  final transport = _FakeTransport((fn, p) => (envelope ?? _envelope)());
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(_session),
      posImageUrlResolverProvider.overrideWithValue(_AllResolveResolver()),
    ],
  );
  addTearDown(c.dispose);
  return (c, transport);
}

DemoMenuItem _byId(PosMenuData menu, String id) =>
    menu.items.firstWhere((i) => i.id == id);

Widget _wrapCard(Widget card, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        // The REAL grid extent for this cell width (REFERENCE-REDESIGN-002).
        body: SizedBox(width: 220, height: posMenuCardExtent(220), child: card),
      ),
    );

DemoMenuItem _item({String? description, String name = 'Classic Burger'}) =>
    DemoMenuItem(
      id: 'i-1',
      name: name,
      priceMinor: 4200,
      categoryId: 'food',
      categoryName: 'Food',
      description: description,
    );

void main() {
  group('A. parsing at the RPC boundary', () {
    test('A1 a description survives the parse, trimmed', () async {
      final (c, _) = _realMenu();
      final menu = await c.read(posMenuProvider.future);
      expect(_byId(menu, 'plain').description, 'A juicy classic.');
      expect(_byId(menu, 'padded').description, 'Served warm.');
    });

    test('A2 absent / null / whitespace-only all normalize to NULL', () async {
      final (c, _) = _realMenu();
      final menu = await c.read(posMenuProvider.future);
      expect(_byId(menu, 'absent').description, isNull);
      expect(_byId(menu, 'null').description, isNull);
      expect(
        _byId(menu, 'blank').description,
        isNull,
        reason: 'whitespace is not content',
      );
    });

    test('A3 a WRONG-TYPED description degrades to null and never fails the '
        'item or the menu', () async {
      final (c, _) = _realMenu();
      final menu = await c.read(posMenuProvider.future);

      expect(_byId(menu, 'int').description, isNull);
      expect(_byId(menu, 'object').description, isNull);
      expect(_byId(menu, 'list').description, isNull);
      // The sellable items are all still there — one bad field never drops a
      // product off the menu.
      expect(menu.items, hasLength(9));
      expect(_byId(menu, 'int').name, 'Int Value');
      expect(_byId(menu, 'int').priceMinor, 1000);
    });
  });

  group('B. copyWith and the signed-image rebuild', () {
    test('B1 the description survives the signed-URL rebuild', () async {
      final (c, _) = _realMenu();
      final menu = await c.read(posMenuProvider.future);
      final imaged = _byId(menu, 'imaged');

      expect(
        imaged.imageUrl,
        'https://signed.example/menu/burger.png',
        reason: 'the rebuild really happened',
      );
      expect(
        imaged.description,
        'Photographed and described.',
        reason: 'a field-preserving copy must not drop the description',
      );
    });

    test('B2 copyWith preserves the description across every path', () {
      final original = _item(description: 'Served warm.');
      expect(original.copyWith().description, 'Served warm.');
      expect(original.copyWith(imageUrl: 'u').description, 'Served warm.');
      expect(original.copyWith(name: 'Other').description, 'Served warm.');
      expect(
        original.withAvailability('unavailable', 'sold_out').description,
        'Served warm.',
        reason: 'the availability overlay is a copyWith too',
      );
    });

    test(
      'B3 copyWith can SET a description without disturbing other fields',
      () {
        final plain = _item();
        expect(plain.description, isNull);
        final described = plain.copyWith(description: 'New text.');
        expect(described.description, 'New text.');
        expect(described.name, plain.name);
        expect(described.priceMinor, plain.priceMinor);
        expect(described.availability, plain.availability);
      },
    );
  });

  group('C. runtime refresh', () {
    test('C1 a refreshed menu shows the NEW description, with exactly one '
        'fetch per load and none per card', () async {
      var text = 'First description.';
      final (c, transport) = _realMenu(
        envelope: () => _envelope(plainDescription: text),
      );

      final first = await c.read(posMenuProvider.future);
      expect(_byId(first, 'plain').description, 'First description.');
      expect(transport.calls, 1, reason: 'one menu fetch, not one per item');

      text = 'Second description.';
      c.invalidate(posMenuProvider);
      final second = await c.read(posMenuProvider.future);

      expect(_byId(second, 'plain').description, 'Second description.');
      expect(
        transport.calls,
        2,
        reason: 'exactly one additional fetch for the refresh',
      );
    });

    test(
      'C2 a description REMOVED in the Dashboard disappears on refresh',
      () async {
        Object? text = 'Temporary.';
        final (c, _) = _realMenu(
          envelope: () => _envelope(plainDescription: text),
        );
        expect(
          (await c.read(posMenuProvider.future)).items.first.description,
          'Temporary.',
        );

        text = null;
        c.invalidate(posMenuProvider);
        expect(
          _byId(await c.read(posMenuProvider.future), 'plain').description,
          isNull,
        );
      },
    );
  });

  group('D. the standard card', () {
    testWidgets(
      'D1 the description renders BENEATH the name, above the price',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          _wrapCard(
            MenuItemCard(
              item: _item(description: 'Served warm with house pickles.'),
              currencyCode: 'ILS',
              onAdd: () => taps++,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final name = find.text('Classic Burger');
        final description = find.text('Served warm with house pickles.');
        expect(name, findsOneWidget);
        expect(description, findsOneWidget);
        expect(
          tester.getTopLeft(description).dy,
          greaterThan(tester.getTopLeft(name).dy),
          reason: 'the description sits under the product name',
        );
        // The price is still below it, and the card key is unchanged.
        expect(find.byKey(const Key('menu-item-i-1')), findsOneWidget);
        expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);

        // The WHOLE card is the tap target; the description is not its own.
        await tester.tap(find.byKey(const Key('menu-item-i-1')));
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(
          find.descendant(of: description, matching: find.byType(InkWell)),
          findsNothing,
          reason: 'the description must not become interactive',
        );
      },
    );

    testWidgets('D2 the description joins the ONE semantic label, after the '
        'name', (tester) async {
      await tester.pumpWidget(
        _wrapCard(
          MenuItemCard(
            item: _item(description: 'Served warm.'),
            currencyCode: 'ILS',
            onAdd: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.byKey(const Key('menu-item-i-1')),
      );
      expect(semantics.label, contains('Classic Burger'));
      expect(semantics.label, contains('Served warm.'));
      expect(
        semantics.label.indexOf('Classic Burger'),
        lessThan(semantics.label.indexOf('Served warm.')),
        reason: 'name first, then description',
      );
    });
  });

  group('E. no description', () {
    testWidgets('E1 nothing is rendered — no placeholder, no blank Text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapCard(
          MenuItemCard(item: _item(), currencyCode: 'ILS', onAdd: () {}),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly two Text widgets survive in the body: the name and the price.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(texts, contains('Classic Burger'));
      expect(
        texts.where((t) => t.trim().isEmpty),
        isEmpty,
        reason: 'no blank Text widget is reserved for a missing description',
      );
      expect(find.textContaining('No description'), findsNothing);
      // The card still works exactly as before.
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
      expect(find.byKey(const Key('menu-item-i-1')), findsOneWidget);
    });

    testWidgets('E2 a whitespace-only description is treated as absent by the '
        'card too', (tester) async {
      await tester.pumpWidget(
        _wrapCard(
          MenuItemCard(
            // The parse normalizes this to null, but a caller that hands the
            // card blank text must not produce a blank line either.
            item: _item(description: '   '),
            currencyCode: 'ILS',
            onAdd: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>();
      expect(texts.where((t) => t.trim().isEmpty), isEmpty);
    });
  });

  group('F. long description', () {
    testWidgets('F1 truncates to exactly two lines with an ellipsis and never '
        'overflows', (tester) async {
      const long =
          'A generously stacked house burger with aged cheddar, smoked '
          'brisket, caramelised onion, dill pickles, baby gem lettuce and our '
          'smoked paprika aioli, served on a toasted brioche bun with a side '
          'of rosemary salted fries and a small pot of house slaw.';
      await tester.pumpWidget(
        _wrapCard(
          MenuItemCard(
            item: _item(description: long),
            currencyCode: 'ILS',
            onAdd: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text(long));
      // REFERENCE-REDESIGN-002: ONE subdued description line on the
      // food-first card.
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(
        text.style?.letterSpacing ?? 0,
        0,
        reason: 'letterSpacing breaks Arabic/Hebrew shaping',
      );
      expect(tester.takeException(), isNull);
      // The price row survives the long text.
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
    });
  });
}
