import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show KitchenMeat;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/parked_carts_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/parked_carts_controller.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MONEY-MODIFIER-PRICING-INTEGRITY-001 — the cart must never under-charge.
///
/// USER-REPORTED PHYSICAL FAIL: on the combined-v2 POS APK an upgraded burger
/// kept its meat selection on screen but was priced at the plain base price, so
/// the order would have been under-charged.
///
/// THE MONEY INVARIANT pinned here, in integer minor units only (D-007):
///
///   line modifier subtotal = Σ(priceDeltaMinor × modifierQuantity)
///   configured line total   = quantity × unitPrice + line modifier subtotal
///   cart subtotal           = Σ line totals
///
/// Groups are labelled by whether they hold on the BASELINE:
///   [PERMANENT]  already true before this phase — regression guards.
///   [D1]/[D2]    reproduce an approved defect and FAIL before the fix.

// ---------------------------------------------------------------------------
// The representative REAL pricing shape (F3): a required, single-select, PAID
// meat group — 120g free, 240g +15.00, 360g +25.00, 480g +35.00 — modelled on
// the product that actually failed. Held test-local so no shared demo total
// moves.
// ---------------------------------------------------------------------------
const kBurgerBaseMinor = 4500; // 45 ILS
const k120gMinor = 0;
const k240gMinor = 1500;
const k360gMinor = 2500;
const k480gMinor = 3500;

const burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBurgerBaseMinor,
  categoryId: 'food',
  categoryName: 'Food',
);

const otherProduct = DemoMenuItem(
  id: 'wrap-meat',
  name: 'Wrap',
  priceMinor: 3800,
  categoryId: 'food',
  categoryName: 'Food',
);

SelectedModifier meat(int deltaMinor, {int quantity = 1}) => SelectedModifier(
  optionId: 'opt-meat-$deltaMinor',
  groupName: 'Meat',
  optionName: '${deltaMinor}g',
  priceDeltaMinor: deltaMinor,
  quantity: quantity,
  kitchenMeat: const KitchenMeat(quantity: 1, unit: 'patty'),
);

ProviderContainer container() {
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

CartController cartOf(ProviderContainer c) =>
    c.read(cartControllerProvider.notifier);
CartViewState viewOf(ProviderContainer c) => c.read(cartControllerProvider);

/// Adds [item] with [mods] and returns the new line's id.
String addConfigured(
  ProviderContainer c,
  DemoMenuItem item,
  List<SelectedModifier> mods,
) {
  cartOf(c).addItemWithModifiers(item, mods);
  return viewOf(c).lines.last.lineId;
}

void main() {
  // =========================================================================
  group(
    '[PERMANENT] A. fresh sequential adds price every line independently',
    () {
      test('A1 a plain 120g burger is the bare base price', () {
        final c = container();
        addConfigured(c, burger, [meat(k120gMinor)]);
        final v = viewOf(c);
        expect(v.lines.single.lineTotalMinor, kBurgerBaseMinor);
        expect(v.subtotalMinor, kBurgerBaseMinor);
      });

      test('A2 a 240g burger carries the surcharge exactly once', () {
        final c = container();
        addConfigured(c, burger, [meat(k240gMinor)]);
        final v = viewOf(c);
        expect(v.lines.single.modifiers.single.totalDeltaMinor, k240gMinor);
        expect(v.lines.single.lineTotalMinor, kBurgerBaseMinor + k240gMinor);
        expect(v.subtotalMinor, kBurgerBaseMinor + k240gMinor);
      });

      test('A3 TWO separate 240g burgers count the surcharge TWICE — the exact '
          'physical symptom', () {
        final c = container();
        addConfigured(c, burger, [meat(k240gMinor)]);
        addConfigured(c, burger, [meat(k240gMinor)]);
        final v = viewOf(c);
        expect(v.lines, hasLength(2));
        expect(v.lines[0].lineId, isNot(v.lines[1].lineId));
        for (final line in v.lines) {
          expect(line.lineTotalMinor, kBurgerBaseMinor + k240gMinor);
        }
        expect(v.subtotalMinor, 2 * (kBurgerBaseMinor + k240gMinor));
      });

      test(
        'A4 the SAME product at 120g then 240g stays two independent lines',
        () {
          final c = container();
          addConfigured(c, burger, [meat(k120gMinor)]);
          addConfigured(c, burger, [meat(k240gMinor)]);
          final v = viewOf(c);
          expect(v.lines[0].lineTotalMinor, kBurgerBaseMinor);
          expect(v.lines[1].lineTotalMinor, kBurgerBaseMinor + k240gMinor);
          expect(v.subtotalMinor, 2 * kBurgerBaseMinor + k240gMinor);
        },
      );

      test('A5 480g first then 120g — no leakage in reverse order', () {
        final c = container();
        addConfigured(c, burger, [meat(k480gMinor)]);
        addConfigured(c, burger, [meat(k120gMinor)]);
        final v = viewOf(c);
        expect(v.lines[0].lineTotalMinor, kBurgerBaseMinor + k480gMinor);
        expect(v.lines[1].lineTotalMinor, kBurgerBaseMinor);
        expect(v.subtotalMinor, 2 * kBurgerBaseMinor + k480gMinor);
      });

      test('A6 all four sizes together — every line pinned exactly', () {
        final c = container();
        for (final d in [k120gMinor, k240gMinor, k360gMinor, k480gMinor]) {
          addConfigured(c, burger, [meat(d)]);
        }
        final v = viewOf(c);
        expect(v.lines.map((l) => l.lineTotalMinor).toList(), [
          kBurgerBaseMinor,
          kBurgerBaseMinor + k240gMinor,
          kBurgerBaseMinor + k360gMinor,
          kBurgerBaseMinor + k480gMinor,
        ]);
        expect(
          v.subtotalMinor,
          4 * kBurgerBaseMinor + k240gMinor + k360gMinor + k480gMinor,
        );
      });

      test('A7 different products keep independent modifier money', () {
        final c = container();
        addConfigured(c, burger, [meat(k240gMinor)]);
        addConfigured(c, otherProduct, [meat(k360gMinor)]);
        final v = viewOf(c);
        expect(v.lines[0].lineTotalMinor, kBurgerBaseMinor + k240gMinor);
        expect(v.lines[1].lineTotalMinor, otherProduct.priceMinor + k360gMinor);
        expect(
          v.subtotalMinor,
          kBurgerBaseMinor + k240gMinor + otherProduct.priceMinor + k360gMinor,
        );
      });

      test('A8 item quantity 2 charges TWO fully configured units — the '
          'authoritative MONEY_AND_TAX_SPEC §9.1 formula', () {
        // CORRECTED by MONEY-PRICING-FORMULA-002A. This previously pinned
        // `2 × base + delta ONCE`, under-charging one surcharge per extra unit
        // while the kitchen still cooked two upgraded meals.
        final c = container();
        final id = addConfigured(c, burger, [meat(k240gMinor)]);
        cartOf(c).increaseQuantity(id);
        final v = viewOf(c);
        expect(v.lines.single.quantity, 2);
        expect(
          v.lines.single.lineTotalMinor,
          2 * (kBurgerBaseMinor + k240gMinor),
        );
        expect(v.subtotalMinor, 2 * (kBurgerBaseMinor + k240gMinor));
      });

      test('A9 modifier quantity multiplies the delta exactly once', () {
        final c = container();
        addConfigured(c, burger, [meat(k240gMinor, quantity: 3)]);
        final v = viewOf(c);
        expect(v.lines.single.modifiers.single.totalDeltaMinor, 3 * k240gMinor);
        expect(
          v.lines.single.lineTotalMinor,
          kBurgerBaseMinor + 3 * k240gMinor,
        );
      });

      test(
        'A10 removing one line never changes another line\'s modifier money',
        () {
          final c = container();
          final a = addConfigured(c, burger, [meat(k240gMinor)]);
          addConfigured(c, burger, [meat(k480gMinor)]);
          cartOf(c).removeLine(a);
          final v = viewOf(c);
          expect(v.lines.single.lineTotalMinor, kBurgerBaseMinor + k480gMinor);
          expect(v.subtotalMinor, kBurgerBaseMinor + k480gMinor);
        },
      );

      test('A11 clear then re-add reprices from scratch with no residue', () {
        final c = container();
        addConfigured(c, burger, [meat(k480gMinor)]);
        cartOf(c).clear();
        expect(viewOf(c).subtotalMinor, 0);
        addConfigured(c, burger, [meat(k120gMinor)]);
        expect(viewOf(c).subtotalMinor, kBurgerBaseMinor);
      });

      test('A12 cart subtotal always equals the sum of line totals', () {
        final c = container();
        for (final d in [k240gMinor, k120gMinor, k360gMinor, k480gMinor]) {
          addConfigured(c, burger, [meat(d)]);
        }
        final v = viewOf(c);
        expect(
          v.subtotalMinor,
          v.lines.fold<int>(0, (s, l) => s + l.lineTotalMinor),
        );
      });
    },
  );

  // =========================================================================
  group('[PERMANENT] B. the decode keeps a WELL-FORMED record exact', () {
    test(
      'B1 a full round-trip preserves every modifier field and the money',
      () {
        final c = container();
        addConfigured(c, burger, [meat(k240gMinor, quantity: 2)]);
        final draft = cartOf(c).captureDraft();
        final revived = CartDraftSnapshot.fromJson(
          jsonDecode(jsonEncode(draft.toJson())) as Map<String, Object?>,
        );
        final m = revived.lines.single.modifiers.single;
        expect(m.optionId, 'opt-meat-$k240gMinor');
        expect(m.priceDeltaMinor, k240gMinor);
        expect(m.quantity, 2);
        expect(m.totalDeltaMinor, 2 * k240gMinor);
        expect(m.kitchenMeat?.quantity, 1);
      },
    );

    test('B2 a LEGACY record with no quantity key decodes as quantity 1 and '
        'keeps its surcharge', () {
      final m = SelectedModifier.fromJson(const <String, Object?>{
        'option_id': 'opt-240',
        'group_name': 'Meat',
        'option_name': '240g',
        'price_delta_minor': k240gMinor,
        // no 'quantity' key at all
      });
      expect(m.quantity, 1);
      expect(m.priceDeltaMinor, k240gMinor);
      expect(m.totalDeltaMinor, k240gMinor);
    });
  });

  // =========================================================================
  group(
    '[D2] C. corrupt modifier money must FAIL CLOSED, never become zero',
    () {
      Map<String, Object?> base() => <String, Object?>{
        'option_id': 'opt-240',
        'group_name': 'Meat',
        'option_name': '240g',
        'price_delta_minor': k240gMinor,
        'quantity': 1,
      };

      test(
        'C1 a MISSING price_delta_minor is corruption, not a free option',
        () {
          final json = base()..remove('price_delta_minor');
          expect(
            () => SelectedModifier.fromJson(json),
            throwsA(isA<FormatException>()),
            reason: 'silently decoding 0 under-charges the order',
          );
        },
      );

      for (final bad in <Object?>[
        '1500',
        15.0,
        <String, Object?>{},
        <Object?>[],
        true,
      ]) {
        test(
          'C2 a malformed price_delta_minor (${bad.runtimeType}) fails closed',
          () {
            final json = base()..['price_delta_minor'] = bad;
            expect(
              () => SelectedModifier.fromJson(json),
              throwsA(isA<FormatException>()),
            );
          },
        );
      }

      test('C3 an EXPLICIT null price_delta_minor fails closed', () {
        final json = base()..['price_delta_minor'] = null;
        expect(
          () => SelectedModifier.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      for (final bad in <Object?>[
        null,
        '2',
        2.0,
        <String, Object?>{},
        <Object?>[],
      ]) {
        test(
          'C4 a PRESENT malformed quantity (${bad.runtimeType}) fails closed — '
          'never 0, never a silent 1',
          () {
            final json = base()..['quantity'] = bad;
            expect(
              () => SelectedModifier.fromJson(json),
              throwsA(isA<FormatException>()),
            );
          },
        );
      }

      test(
        'C5 a non-positive quantity fails closed (it would zero the delta)',
        () {
          expect(
            () => SelectedModifier.fromJson(base()..['quantity'] = 0),
            throwsA(isA<FormatException>()),
          );
          expect(
            () => SelectedModifier.fromJson(base()..['quantity'] = -1),
            throwsA(isA<FormatException>()),
          );
        },
      );

      test('C6 a corrupt modifier fails the WHOLE draft — no partially decoded '
          'cart, no silently dropped modifier', () {
        final json = <String, Object?>{
          'currency_code': 'ILS',
          'lines': [
            {
              'menu_item_id': burger.id,
              'name': burger.name,
              'base_price_minor': kBurgerBaseMinor,
              'quantity': 1,
              'modifiers': [base()..['price_delta_minor'] = 'oops'],
            },
          ],
        };
        expect(
          () => CartDraftSnapshot.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });
    },
  );

  // =========================================================================
  group(
    '[D2] D. a corrupt PARKED record must not restore an under-charged cart',
    () {
      const scope = PosSyncScope(
        organizationId: 'org',
        restaurantId: 'rest',
        branchId: 'branch',
        deviceId: 'dev',
      );

      setUp(() => SharedPreferences.setMockInitialValues({}));

      /// Writes a parked envelope by hand with a corrupt modifier price.
      Future<void> seedCorrupt(SharedPreferences prefs) async {
        final payload = jsonEncode(<String, Object?>{
          'version': 1,
          'seq': 1,
          'carts': [
            {
              'id': 'park-1',
              'created_at': '2026-08-05T09:00:00.000Z',
              'updated_at': '2026-08-05T09:00:00.000Z',
              'order_type': 'takeaway',
              'draft': {
                'currency_code': 'ILS',
                'lines': [
                  {
                    'line_id': 'line-1',
                    'menu_item_id': burger.id,
                    'name': burger.name,
                    'base_price_minor': kBurgerBaseMinor,
                    'quantity': 1,
                    'modifiers': [
                      {
                        'option_id': 'opt-240',
                        'group_name': 'Meat',
                        'option_name': '240g',
                        // corrupt: the surcharge is unreadable
                        'price_delta_minor': 'fifteen',
                        'quantity': 1,
                      },
                    ],
                  },
                ],
              },
            },
          ],
        });
        await prefs.setString(parkedCartsStorageKey(scope), payload);
      }

      test('D1 the corrupt record is NOT offered as a restorable cart, and is '
          'kept verbatim on disk', () async {
        final prefs = await SharedPreferences.getInstance();
        await seedCorrupt(prefs);
        final store = SharedPrefsParkedCartsStore(prefs);

        final snapshot = await store.load(scope);
        expect(
          snapshot.carts,
          isEmpty,
          reason: 'a cart whose money cannot be read must never be restorable',
        );
        expect(
          snapshot.unreadable,
          hasLength(1),
          reason: 'and it must be preserved, not destroyed',
        );

        // The raw record is still on disk, byte-for-byte.
        final raw = prefs.getString(parkedCartsStorageKey(scope))!;
        expect(raw, contains('fifteen'));
      });

      test('D2 restoring it leaves the ACTIVE cart untouched', () async {
        final prefs = await SharedPreferences.getInstance();
        await seedCorrupt(prefs);
        final c = ProviderContainer(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: true),
            ),
            posSyncScopeProvider.overrideWithValue(scope),
            parkedCartsStoreProvider.overrideWithValue(
              SharedPrefsParkedCartsStore(prefs),
            ),
          ],
        );
        addTearDown(c.dispose);
        c.read(orderSetupControllerProvider.notifier);
        final before = viewOf(c).subtotalMinor;

        final controller = c.read(parkedCartsControllerProvider.notifier);
        await controller.load();
        final outcome = await controller.restore('park-1');

        expect(outcome.status, isNot(RestoreStatus.restored));
        expect(
          viewOf(c).subtotalMinor,
          before,
          reason: 'no under-charged line may be installed',
        );
        expect(viewOf(c).lines, isEmpty);
      });

      test('D3 a WELL-FORMED park survives a full restart round-trip with its '
          'money, ids, quantities and meat intact', () async {
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsParkedCartsStore(prefs);
        final c = ProviderContainer(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: true),
            ),
            posSyncScopeProvider.overrideWithValue(scope),
            parkedCartsStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(c.dispose);
        addConfigured(c, burger, [meat(k240gMinor, quantity: 2)]);
        addConfigured(c, burger, [meat(k480gMinor)]);
        final expected = viewOf(c).subtotalMinor;
        expect(expected, 2 * kBurgerBaseMinor + 2 * k240gMinor + k480gMinor);

        final parked = await c
            .read(parkedCartsControllerProvider.notifier)
            .park();
        expect(parked, ParkResult.parked);

        // A FRESH process reading the same disk.
        final c2 = ProviderContainer(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: true),
            ),
            posSyncScopeProvider.overrideWithValue(scope),
            parkedCartsStoreProvider.overrideWithValue(
              SharedPrefsParkedCartsStore(prefs),
            ),
          ],
        );
        addTearDown(c2.dispose);
        final ctl2 = c2.read(parkedCartsControllerProvider.notifier);
        await ctl2.load();
        final id = c2.read(parkedCartsControllerProvider).carts.single.id;
        final outcome = await ctl2.restore(id);
        expect(outcome.status, RestoreStatus.restored);

        final v = viewOf(c2);
        expect(v.subtotalMinor, expected);
        expect(v.lines[0].modifiers.single.priceDeltaMinor, k240gMinor);
        expect(v.lines[0].modifiers.single.quantity, 2);
        expect(v.lines[0].modifiers.single.kitchenMeat?.quantity, 1);
        expect(v.lines[0].lineTotalMinor, kBurgerBaseMinor + 2 * k240gMinor);
        expect(v.lines[1].lineTotalMinor, kBurgerBaseMinor + k480gMinor);
      });
    },
  );
}
