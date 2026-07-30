import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenMeat, KitchenPrepComponent;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/state/cart_controller.dart';

/// PARKED-CARTS-001 (adjacent approved fix) — the CART DRAFT must carry the
/// per-line KITCHEN PREP snapshot.
///
/// `CartController` captures each line's PER-UNIT prep components at ADD time
/// (the order-time D-008 snapshot the outbox payload and the kitchen ticket
/// both use). `captureDraft()` did not copy that map onto the draft and
/// `restoreDraft()` cleared it without repopulating it — so any draft
/// round-trip silently lost the prep data, and a cart restored from one would
/// print a kitchen ticket with NO prep summary for the chef.
///
/// Exact restoration of a parked cart requires this, so it is fixed additively:
/// a new OPTIONAL field on CartDraftLine, absent in older serialized records
/// (which decode as empty), with every existing draft-recovery contract intact.

const _burger = DemoMenuItem(
  id: 'burger-9',
  name: 'Double Burger',
  priceMinor: 4200,
  categoryId: 'food',
  categoryName: 'Food',
  categoryDisplayOrder: 1,
  itemDisplayOrder: 2,
  attributes: <String, dynamic>{
    'prep_components': [
      {'name': 'Patty', 'quantity': 2, 'unit': 'pcs'},
      {'name': 'Bun', 'quantity': 1, 'unit': ''},
    ],
  },
);

const _cola = DemoMenuItem(
  id: 'cola-1',
  name: 'Cola',
  priceMinor: 1000,
  categoryId: 'drinks',
  categoryName: 'Drinks',
);

const _cheese = SelectedModifier(
  optionId: 'opt-cheese',
  groupName: 'Extras',
  optionName: 'Cheese',
  priceDeltaMinor: 300,
  quantity: 2,
  kitchenMeat: KitchenMeat(quantity: 1, unit: 'patty'),
);

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('A. captureDraft carries the per-line prep snapshot', () {
    test(
      'A1 a captured draft carries each line\'s PER-UNIT prep components',
      () {
        final c = _container();
        final cart = c.read(cartControllerProvider.notifier);
        cart.addItem(_burger);
        cart.addItem(_cola);

        final draft = cart.captureDraft();
        final burgerLine = draft.lines.firstWhere(
          (l) => l.menuItemId == 'burger-9',
        );
        expect(burgerLine.prepComponents, hasLength(2));
        expect(burgerLine.prepComponents.first.name, 'Patty');
        expect(burgerLine.prepComponents.first.quantity, 2);
        expect(burgerLine.prepComponents.first.unit, 'pcs');
        expect(burgerLine.prepComponents[1].name, 'Bun');

        // An item with no configured prep honestly carries none.
        final colaLine = draft.lines.firstWhere(
          (l) => l.menuItemId == 'cola-1',
        );
        expect(colaLine.prepComponents, isEmpty);
      },
    );

    test('A2 a CONFIGURED line (modifiers + note) also carries its prep', () {
      final c = _container();
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(_burger, const [_cheese], note: 'no onion');

      final line = cart.captureDraft().lines.single;
      expect(line.prepComponents, hasLength(2));
      expect(line.note, 'no onion');
      expect(line.modifiers.single.kitchenMeat?.unit, 'patty');
    });
  });

  group('B. restoreDraft repopulates it', () {
    test('B1 a capture -> restore -> capture round trip PRESERVES prep', () {
      final c = _container();
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(_burger, const [_cheese], note: 'no onion');
      cart.addItem(_cola);
      final original = cart.captureDraft();

      expect(cart.restoreDraft(original), CartMutationResult.applied);
      final again = cart.captureDraft();

      expect(again.lines, hasLength(2));
      final burgerLine = again.lines.firstWhere(
        (l) => l.menuItemId == 'burger-9',
      );
      expect(
        burgerLine.prepComponents,
        hasLength(2),
        reason: 'restoreDraft cleared _linePrep without repopulating it',
      );
      expect(burgerLine.prepComponents.first.name, 'Patty');
      expect(burgerLine.prepComponents.first.quantity, 2);
      expect(
        again.lines.firstWhere((l) => l.menuItemId == 'cola-1').prepComponents,
        isEmpty,
      );
    });

    test('B2 the restored cart keeps its stable line ids, quantities, '
        'modifiers and notes (existing contract unchanged)', () {
      final c = _container();
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(_burger, const [_cheese], note: 'no onion');
      cart.increaseQuantity(c.read(cartControllerProvider).lines.single.lineId);
      final original = cart.captureDraft();

      cart.restoreDraft(original);
      final line = c.read(cartControllerProvider).lines.single;
      expect(line.lineId, original.lines.single.lineId);
      expect(line.quantity, 2);
      expect(line.note, 'no onion');
      expect(line.modifiers.single.optionId, 'opt-cheese');
      expect(line.modifiers.single.quantity, 2);
      expect(line.categoryDisplayOrder, 1);
      expect(line.itemDisplayOrder, 2);
    });

    test('B3 restoring keeps the line sequence AHEAD of restored ids, so a '
        'later add cannot collide', () {
      final c = _container();
      final cart = c.read(cartControllerProvider.notifier);
      cart.restoreDraft(
        const CartDraftSnapshot(
          currencyCode: 'ILS',
          lines: [
            CartDraftLine(
              lineId: 'line-7',
              menuItemId: 'burger-9',
              name: 'Double Burger',
              basePriceMinor: 4200,
              quantity: 1,
            ),
          ],
        ),
      );
      cart.addItem(_cola);
      final ids = c.read(cartControllerProvider).lines.map((l) => l.lineId);
      expect(ids.toSet(), hasLength(2));
      expect(ids, contains('line-7'));
    });
  });

  group('C. durable serialization stays backward compatible', () {
    test('C1 prep survives a JSON round trip', () {
      final c = _container();
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_burger);

      final json = jsonDecode(jsonEncode(cart.captureDraft().toJson()));
      final decoded = CartDraftSnapshot.fromJson(
        (json as Map).cast<String, Object?>(),
      );
      expect(decoded.lines.single.prepComponents, hasLength(2));
      expect(decoded.lines.single.prepComponents.first.name, 'Patty');
    });

    test('C2 an OLDER record with no prep field decodes as EMPTY, never an '
        'error and never invented data', () {
      final legacy = <String, Object?>{
        'currency_code': 'ILS',
        'lines': [
          <String, Object?>{
            'line_id': 'line-3',
            'menu_item_id': 'burger-9',
            'name': 'Double Burger',
            'base_price_minor': 4200,
            'quantity': 2,
          },
        ],
      };
      final decoded = CartDraftSnapshot.fromJson(legacy);
      expect(decoded.lines.single.prepComponents, isEmpty);
      expect(decoded.lines.single.lineId, 'line-3');
      expect(decoded.lines.single.quantity, 2);
    });

    test('C3 an EMPTY prep list is omitted from the wire (no bloat, and an '
        'existing record is byte-identical)', () {
      const line = CartDraftLine(
        lineId: 'line-1',
        menuItemId: 'cola-1',
        name: 'Cola',
        basePriceMinor: 1000,
        quantity: 1,
      );
      expect(line.toJson().containsKey('prep_components'), isFalse);
    });

    test(
      'C4 a corrupt prep entry is DROPPED, never shown as a bogus count',
      () {
        final json = <String, Object?>{
          'currency_code': 'ILS',
          'lines': [
            <String, Object?>{
              'menu_item_id': 'burger-9',
              'name': 'Double Burger',
              'base_price_minor': 4200,
              'quantity': 1,
              'prep_components': [
                {'name': 'Patty', 'quantity': 2, 'unit': 'pcs'},
                {'name': '', 'quantity': 5},
                {'name': 'Ghost', 'quantity': 0},
                'not-a-map',
              ],
            },
          ],
        };
        final decoded = CartDraftSnapshot.fromJson(json);
        expect(decoded.lines.single.prepComponents, hasLength(1));
        expect(decoded.lines.single.prepComponents.single.name, 'Patty');
      },
    );
  });

  group('D. the recovered-row view uses the prep the draft now carries', () {
    test('D1 viewFromDraft carries prep onto the submitted line, so a manual '
        'kitchen reprint of a recovered row aggregates real counts', () {
      final c = _container();
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_burger);
      final draft = cart.captureDraft();

      final view = cart.viewFromDraft(draft: draft);
      expect(view.lines.single.prepComponents, hasLength(2));
      expect(view.lines.single.prepComponents.first.name, 'Patty');
    });

    test('D2 a legacy draft with no prep yields an EMPTY prep list rather than '
        'a re-read of today\'s catalog', () {
      final c = _container();
      final cart = c.read(cartControllerProvider.notifier);
      final view = cart.viewFromDraft(
        draft: const CartDraftSnapshot(
          currencyCode: 'ILS',
          lines: [
            CartDraftLine(
              menuItemId: 'burger-9',
              name: 'Double Burger',
              basePriceMinor: 4200,
              quantity: 1,
            ),
          ],
        ),
      );
      expect(view.lines.single.prepComponents, isEmpty);
    });
  });

  group('E. the model itself', () {
    test('E1 CartDraftLine defaults prepComponents to empty', () {
      const line = CartDraftLine(
        menuItemId: 'x',
        name: 'X',
        basePriceMinor: 1,
        quantity: 1,
      );
      expect(line.prepComponents, isEmpty);
    });

    test(
      'E2 prep components are structured values, never rendered strings',
      () {
        const component = KitchenPrepComponent(
          name: 'Patty',
          quantity: 2,
          unit: 'pcs',
        );
        expect(component.name, 'Patty');
        expect(component.quantity, 2);
        expect(component.unit, 'pcs');
      },
    );
  });
}
