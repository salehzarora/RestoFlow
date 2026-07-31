import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// MONEY-LOCAL-ATOMICITY-003A [E] — the POS MENU SOURCE BOUNDARY fails closed.
///
/// Every identifier on this boundary used to be coerced with
/// `(row['x'] ?? '').toString()`, and the consequence was not a loud failure —
/// it was that the PRODUCT SILENTLY BECAME PLAIN-ADDABLE. A group row with a
/// blank id was still constructed (`id: ''`), its options orphaned under their
/// real `modifier_id`, `groupsForItem` dropped it for having no options, and the
/// add handler took the `groups.isEmpty -> addItem` branch. A required PAID
/// group vanished and the item sold at base price with no indicator.
///
/// THE CHOSEN RULE, stated: a product is UNAVAILABLE when any group associated
/// with it cannot be interpreted safely — not merely the broken group dropped.
/// Dropping only the bad group still sells the item, just without a choice the
/// operator configured and possibly charged for. An unsellable product is a
/// better outcome than an undercharged sale.
///
/// This is the first suite in the repository to feed a `pos_menu` envelope
/// containing `modifiers` / `modifier_options` rows.

const kBase = 4500;
const kBurgerId = 'burger-meat';
const kColaId = 'cola';

class _Transport implements SyncRpcTransport {
  _Transport(this._menu);
  final Map<String, Object?> _menu;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'pos_menu') return _menu;
    return null;
  }
}

Map<String, Object?> envelope({
  List<Object?> modifiers = const [],
  List<Object?> options = const [],
}) => <String, Object?>{
  'ok': true,
  'currency_code': 'ILS',
  'categories': <Object?>[
    <String, Object?>{'id': 'food', 'name': 'Food', 'display_order': 1},
  ],
  'items': <Object?>[
    <String, Object?>{
      'id': kBurgerId,
      'name': 'Burger',
      'base_price_minor': kBase,
      'menu_category_id': 'food',
    },
    <String, Object?>{
      'id': kColaId,
      'name': 'Cola',
      'base_price_minor': 1000,
      'menu_category_id': 'food',
    },
  ],
  'modifiers': modifiers,
  'modifier_options': options,
};

Map<String, Object?> groupRow([Map<String, Object?> o = const {}]) =>
    <String, Object?>{
      'id': 'grp-meat',
      'menu_item_id': kBurgerId,
      'name': 'Meat',
      'selection_type': 'single',
      'is_required': true,
      ...o,
    };

Map<String, Object?> optionRow([Map<String, Object?> o = const {}]) =>
    <String, Object?>{
      'id': 'opt-240',
      'modifier_id': 'grp-meat',
      'name': '240g',
      'price_delta_minor': 1500,
      ...o,
    };

Future<PosMenuData> loadMenu(Map<String, Object?> menu) async {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(_Transport(menu)),
      posSyncSessionProvider.overrideWithValue(
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c.read(posMenuProvider.future);
}

DemoMenuItem itemOf(PosMenuData menu, String id) =>
    menu.items.firstWhere((i) => i.id == id);

void main() {
  test('E0 a HEALTHY configuration is unchanged: the group resolves, the item '
      'stays sellable, and the sheet has its paid option', () async {
    final menu = await loadMenu(
      envelope(modifiers: [groupRow()], options: [optionRow()]),
    );
    final burger = itemOf(menu, kBurgerId);
    expect(burger.isUnavailable, isFalse);
    final groups = menu.groupsForItem(kBurgerId);
    expect(groups, hasLength(1));
    expect(groups.single.id, 'grp-meat');
    expect(groups.single.options.single.priceDeltaMinor, 1500);
  });

  group('[E] a broken GROUP row makes its product unavailable', () {
    for (final entry in <String, Object?>{
      'missing id': null,
      'blank id': '',
      'whitespace id': '   ',
      'non-string id': 7,
      'list id': <Object?>[],
    }.entries) {
      test(
        'E1 group ${entry.key} — the product must NOT become plain-addable',
        () async {
          final g = groupRow();
          if (entry.key == 'missing id') {
            g.remove('id');
          } else {
            g['id'] = entry.value;
          }
          final menu = await loadMenu(
            envelope(modifiers: [g], options: [optionRow()]),
          );

          final burger = itemOf(menu, kBurgerId);
          expect(
            burger.isUnavailable,
            isTrue,
            reason:
                'a required PAID group vanished; selling at base price '
                'would be an under-charge with no indicator',
          );
          expect(
            burger.availabilityReason,
            DemoMenuItem.configurationUnavailableReason,
            reason: 'and the reason is CONFIGURATION, not sold-out',
          );
          expect(
            menu.groupsForItem(kBurgerId),
            isEmpty,
            reason: 'no half-group is offered either',
          );
          // The healthy sibling is untouched.
          expect(itemOf(menu, kColaId).isUnavailable, isFalse);
        },
      );
    }

    test('E2 a group with a missing/blank NAME is broken too', () async {
      for (final bad in <Object?>[null, '', '   ', 7]) {
        final g = groupRow();
        if (bad == null) {
          g.remove('name');
        } else {
          g['name'] = bad;
        }
        final menu = await loadMenu(
          envelope(modifiers: [g], options: [optionRow()]),
        );
        expect(itemOf(menu, kBurgerId).isUnavailable, isTrue);
      }
    });

    test('E3 a group with an unreadable menu_item_id is DROPPED, and cannot '
        'make any one product unsafe because it never named one', () async {
      final menu = await loadMenu(
        envelope(
          modifiers: [
            groupRow({'menu_item_id': 7}),
          ],
          options: [optionRow()],
        ),
      );
      // Nothing claims it, so no product is blamed — and no product gained a
      // phantom group either.
      expect(menu.groupsForItem(kBurgerId), isEmpty);
      expect(itemOf(menu, kBurgerId).isUnavailable, isFalse);
    });
  });

  group('[E] a broken OPTION row makes its product unavailable', () {
    for (final entry in <String, Object?>{
      'missing id': null,
      'blank id': '',
      'non-string id': 7,
    }.entries) {
      test('E4 option ${entry.key} — the group is untrustworthy', () async {
        final o = optionRow();
        if (entry.key == 'missing id') {
          o.remove('id');
        } else {
          o['id'] = entry.value;
        }
        final menu = await loadMenu(
          envelope(modifiers: [groupRow()], options: [o]),
        );
        expect(
          itemOf(menu, kBurgerId).isUnavailable,
          isTrue,
          reason:
              'the cashier would be offered a SUBSET of the real choices, '
              'at the real prices, with no sign one is missing',
        );
      });
    }

    test('E5 a malformed PAID price is the sharpest case', () async {
      for (final bad in <Object?>['1500', 15.0, null, true]) {
        final o = optionRow();
        if (bad == null) {
          o.remove('price_delta_minor');
        } else {
          o['price_delta_minor'] = bad;
        }
        final menu = await loadMenu(
          envelope(modifiers: [groupRow()], options: [o]),
        );
        expect(
          itemOf(menu, kBurgerId).isUnavailable,
          isTrue,
          reason: 'a skipped paid option is a silent under-charge',
        );
      }
    });

    test('E6 an option with an unreadable modifier_id cannot orphan onto a '
        'blank group', () async {
      final menu = await loadMenu(
        envelope(
          modifiers: [groupRow()],
          options: [
            optionRow(),
            optionRow({'id': 'opt-360', 'modifier_id': ''}),
          ],
        ),
      );
      // The orphan is not attached anywhere...
      final groups = menu.groupsForItem(kBurgerId);
      if (groups.isNotEmpty) {
        expect(
          groups.single.options.map((o) => o.id),
          isNot(contains('opt-360')),
        );
      }
    });
  });

  test('E7 a BROKEN group alongside a HEALTHY one still makes the product '
      'unavailable — the safe default for money', () async {
    final menu = await loadMenu(
      envelope(
        modifiers: [
          groupRow(),
          groupRow({'id': '', 'name': 'Extras'}),
        ],
        options: [optionRow()],
      ),
    );
    expect(
      itemOf(menu, kBurgerId).isUnavailable,
      isTrue,
      reason:
          'selling with only the readable half would omit a configured '
          'choice the operator may charge for',
    );
    expect(itemOf(menu, kColaId).isUnavailable, isFalse);
  });

  test('E8 an item with genuinely NO groups stays plainly sellable — the '
      'guard must distinguish "none" from "unreadable"', () async {
    final menu = await loadMenu(envelope());
    expect(itemOf(menu, kBurgerId).isUnavailable, isFalse);
    expect(menu.groupsForItem(kBurgerId), isEmpty);
  });
}
