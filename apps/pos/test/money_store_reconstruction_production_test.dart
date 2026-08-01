import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show KitchenMeat;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart' show DemoTable;
import 'package:restoflow_pos/src/data/parked_carts_store.dart';
import 'package:restoflow_pos/src/data/payment.dart'
    show PaymentMethod, PaymentStatus;
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart'
    show tablesProvider;
import 'package:restoflow_pos/src/state/parked_carts_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MONEY-PRODUCTION-PATH-TESTS-002D [B + G] — Codex Blocker 7, the durable
/// local stores across a PROCESS RECREATION.
///
/// `parked_carts_restore_test.dart` already ships a park -> dispose -> rebuild
/// harness, so this suite covers what that one cannot: the 002C stable
/// `modifierGroupId` surviving a real restart, an UNREADABLE sibling record
/// coexisting with a healthy one, and the recent-order store's round-trip and
/// quarantine.
///
/// Everything goes through the REAL `SharedPrefsParkedCartsStore` /
/// `SharedPrefsRecentOrdersStore` and the REAL controllers, over ONE
/// `SharedPreferences` instance that outlives the disposed container.
///
/// Every expected amount is an INDEPENDENT LITERAL.
///
/// Classification: CODEX COVERAGE GAP.

const kBase = 4500;
const k240 = 1500;
const kCola = 1000;
const kIce = 300;
// 2 x (4500 + 1500) = 12000; 1 x (1000 + 300) = 1300; cart = 13300.
const kBurgerLine = 12000;
const kColaLine = 1300;
const kCartSubtotal = 13300;

const _scope = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchA',
  deviceId: 'dev1',
);

const _burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'food',
  categoryName: 'Food',
);
const _cola = DemoMenuItem(
  id: 'cola',
  name: 'Cola',
  priceMinor: kCola,
  categoryId: 'drinks',
  categoryName: 'Drinks',
);

const _meat240 = SelectedModifier(
  optionId: 'opt-240',
  modifierGroupId: 'grp-meat',
  groupName: 'Meat',
  optionName: '240g',
  priceDeltaMinor: k240,
  kitchenMeat: KitchenMeat(quantity: 1, unit: 'patty'),
);
const _extraIce = SelectedModifier(
  optionId: 'opt-ice',
  modifierGroupId: 'grp-ice',
  groupName: 'Ice',
  optionName: 'Extra ice',
  priceDeltaMinor: kIce,
);

PosMenuData _menu() => const PosMenuData(
  categories: [
    DemoCategory(
      id: 'food',
      name: 'Food',
      icon: Icons.lunch_dining,
      color: Colors.orange,
    ),
  ],
  items: [_burger, _cola],
  currencyCode: 'ILS',
  modifierGroups: [],
);

/// ONE process: the REAL store over the given prefs, disposed with the test.
ProviderContainer process(SharedPreferences prefs) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      posSyncScopeProvider.overrideWithValue(_scope),
      parkedCartsStoreProvider.overrideWithValue(
        SharedPrefsParkedCartsStore(prefs),
      ),
      tablesProvider.overrideWith((ref) async => const <DemoTable>[]),
      posMenuProvider.overrideWith((ref) async => _menu()),
    ],
  );
  return c;
}

Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
}

void main() {
  group('[B] park -> process recreation -> restore, through the REAL store', () {
    test('B1 two configured lines survive a full restart with every snapshot '
        'field intact, including the 002C group id', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      // ------------------------------------------------------- process 1
      final c1 = process(prefs);
      final cart1 = c1.read(cartControllerProvider.notifier);
      cart1.addItemWithModifiers(_burger, const [_meat240], note: 'no onion');
      final burgerLine = c1.read(cartControllerProvider).lines.single.lineId;
      cart1.increaseQuantity(burgerLine); // item quantity 2
      cart1.addItemWithModifiers(_cola, const [_extraIce]);

      final before = c1.read(cartControllerProvider);
      expect(before.lines, hasLength(2));
      expect(before.lines[0].lineTotalMinor, kBurgerLine);
      expect(before.lines[1].lineTotalMinor, kColaLine);
      expect(before.subtotalMinor, kCartSubtotal);
      final beforeIds = before.lines.map((l) => l.lineId).toList();

      await c1.read(parkedCartsControllerProvider.notifier).load();
      await settle();
      final parked = await c1
          .read(parkedCartsControllerProvider.notifier)
          .park();
      expect(
        parked,
        ParkResult.parked,
        reason: 'the park must actually persist',
      );
      await settle();
      // The cart is set aside.
      expect(c1.read(cartControllerProvider).lines, isEmpty);

      // ------------------------------------------------- PROCESS RECREATION
      c1.dispose();
      final c2 = process(prefs);
      addTearDown(c2.dispose);

      await c2.read(parkedCartsControllerProvider.notifier).load();
      await settle();
      final list = c2.read(parkedCartsControllerProvider);
      expect(list.carts, hasLength(1), reason: 'the park survived the restart');
      expect(
        list.carts.single.subtotalMinor,
        kCartSubtotal,
        reason: 'the parked-list badge shows the SAME money as the cart did',
      );
      expect(list.unreadableCount, 0);

      // ------------------------------------------------------- restore
      final outcome = await c2
          .read(parkedCartsControllerProvider.notifier)
          .restore(list.carts.single.id);
      expect(outcome.status, RestoreStatus.restored);
      await settle();

      final after = c2.read(cartControllerProvider);
      expect(after.lines, hasLength(2));
      expect(
        after.lines.map((l) => l.lineId).toList(),
        beforeIds,
        reason: 'the STABLE line identity survived the restart',
      );

      final burger = after.lines[0];
      expect(burger.menuItemId, 'burger-meat');
      expect(burger.unitPriceMinor, kBase, reason: 'the FROZEN base price');
      expect(burger.quantity, 2);
      expect(burger.lineTotalMinor, kBurgerLine);
      expect(burger.note, 'no onion');
      final m = burger.modifiers.single;
      expect(m.optionId, 'opt-240');
      expect(
        m.modifierGroupId,
        'grp-meat',
        reason: '002C: the stable group id must ride through persistence',
      );
      expect(m.groupName, 'Meat');
      expect(m.optionName, '240g');
      expect(m.priceDeltaMinor, k240);
      expect(m.quantity, 1);
      expect(m.kitchenMeat?.quantity, 1);
      expect(m.kitchenMeat?.unit, 'patty');

      final cola = after.lines[1];
      expect(cola.lineTotalMinor, kColaLine);
      expect(cola.modifiers.single.modifierGroupId, 'grp-ice');
      expect(cola.modifiers.single.priceDeltaMinor, kIce);

      expect(after.subtotalMinor, kCartSubtotal);
    });

    test(
      'B2 an UNREADABLE sibling record is preserved verbatim while the '
      'healthy cart still restores, and an ordinary park does not delete it',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();

        // Park a healthy cart first, through the real controller.
        final c1 = process(prefs);
        final cart1 = c1.read(cartControllerProvider.notifier);
        cart1.addItemWithModifiers(_burger, const [_meat240]);
        await c1.read(parkedCartsControllerProvider.notifier).load();
        await settle();
        await c1.read(parkedCartsControllerProvider.notifier).park();
        await settle();
        c1.dispose();

        // Inject a sibling record this build cannot decode: its modifier money
        // arrived as a string. It is NOT garbage — it is somebody's parked order.
        final key = parkedCartsStorageKey(_scope);
        final envelope = (jsonDecode(prefs.getString(key)!) as Map)
            .cast<String, Object?>();
        final carts = (envelope['carts']! as List).cast<Object?>();
        final broken =
            jsonDecode(jsonEncode(carts.single)) as Map<String, Object?>;
        broken['id'] = 'park-broken';
        final line =
            (((broken['draft']! as Map)['lines']! as List).first as Map)
                .cast<String, Object?>();
        ((line['modifiers']! as List).first as Map)['price_delta_minor'] =
            '1500';
        final brokenJson = jsonEncode(broken);
        envelope['carts'] = <Object?>[...carts, broken];
        await prefs.setString(key, jsonEncode(envelope));

        // ------------------------------------------------- PROCESS RECREATION
        final c2 = process(prefs);
        addTearDown(c2.dispose);
        await c2.read(parkedCartsControllerProvider.notifier).load();
        await settle();

        final list = c2.read(parkedCartsControllerProvider);
        expect(
          list.carts,
          hasLength(1),
          reason:
              'the healthy cart is still there, and the broken one is not '
              'shown underpriced',
        );
        expect(
          list.unreadableCount,
          1,
          reason: 'the quarantined record is COUNTED, not silently dropped',
        );
        expect(list.carts.single.subtotalMinor, kBase + k240);

        // A later ORDINARY park must not erase the quarantined record.
        final cart2 = c2.read(cartControllerProvider.notifier);
        cart2.addItemWithModifiers(_cola, const [_extraIce]);
        await c2.read(parkedCartsControllerProvider.notifier).park();
        await settle();

        final after = (jsonDecode(prefs.getString(key)!) as Map)
            .cast<String, Object?>();
        final afterCarts = (after['carts']! as List).cast<Object?>();
        expect(
          afterCarts.map((e) => jsonEncode(e)),
          contains(brokenJson),
          reason: 'a record we cannot read is not a record we may destroy',
        );
        expect(afterCarts, hasLength(3), reason: '2 healthy + 1 quarantined');
      },
    );
  });

  // =========================================================================
  group('[G] the REAL recent-orders store across a process recreation', () {
    const ordersKey = 'restoflow.pos.recent_orders.v1.till-1';

    Map<String, Object?> record({
      required String number,
      Map<String, Object?>? payment,
      Object? subtotal = kCartSubtotal,
    }) => <String, Object?>{
      'order': <String, Object?>{
        'order_number': number,
        'currency_code': 'ILS',
        'order_type': 'takeaway',
        'subtotal_minor': subtotal,
        'discount_total_minor': 0,
        'tax_total_minor': 0,
        'tax_rate_bp': 0,
        'lines': <Object?>[
          <String, Object?>{
            'name': 'Burger',
            'quantity': 2,
            'line_total_minor': kBurgerLine,
            'currency_code': 'ILS',
            'modifiers': <Object?>['240g'],
          },
          <String, Object?>{
            'name': 'Cola',
            'quantity': 1,
            'line_total_minor': kColaLine,
            'currency_code': 'ILS',
            'modifiers': <Object?>['Extra ice'],
          },
        ],
      },
      'submitted_at': '2026-08-06T09:00:00.000Z',
      if (payment != null) 'payment': payment,
    };

    Map<String, Object?> paid([Map<String, Object?> o = const {}]) =>
        <String, Object?>{
          'payment_id': 'pay-1',
          'order_number': 'A-2',
          'device_id': 'dev-1',
          'local_operation_id': 'op-1',
          'currency_code': 'ILS',
          'receipt_number': 'R-1',
          'paid_at': '2026-08-06T09:05:00.000Z',
          'amount_minor': kCartSubtotal,
          'tendered_minor': 15000,
          'change_minor': 1700,
          'method': 'cash',
          'status': 'completed',
          ...o,
        };

    Future<SharedPreferences> seed(List<Object?> entries) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ordersKey: jsonEncode(<String, Object?>{
          'version': SharedPrefsRecentOrdersStore.schemaVersion,
          'orders': entries,
        }),
      });
      return SharedPreferences.getInstance();
    }

    test('G1 a valid unpaid and a valid paid record round-trip through two '
        'STORE INSTANCES with every financial field intact', () async {
      final prefs = await seed(<Object?>[
        record(number: 'A-1'),
        record(number: 'A-2', payment: paid()),
      ]);

      // Store instance 1 loads; instance 2 is a fresh object over the same
      // prefs — the production shape of an app restart.
      final loadedA = await SharedPrefsRecentOrdersStore(prefs).load('till-1');
      await SharedPrefsRecentOrdersStore(prefs).persist('till-1', loadedA);
      final loadedB = await SharedPrefsRecentOrdersStore(prefs).load('till-1');

      expect(loadedB, hasLength(2));
      for (final orders in <List<PosRecentOrder>>[loadedA, loadedB]) {
        final unpaid = orders.firstWhere((o) => o.orderNumber == 'A-1');
        final settled = orders.firstWhere((o) => o.orderNumber == 'A-2');

        expect(unpaid.subtotalMinor, kCartSubtotal);
        expect(unpaid.order!.lines[0].lineTotalMinor, kBurgerLine);
        expect(unpaid.order!.lines[1].lineTotalMinor, kColaLine);
        expect(unpaid.payment, isNull);
        expect(unpaid.canReprintReceipt, isFalse);

        expect(settled.subtotalMinor, kCartSubtotal);
        expect(settled.payment!.amountMinor, kCartSubtotal);
        expect(settled.payment!.tenderedMinor, 15000);
        expect(settled.payment!.changeMinor, 1700);
        expect(settled.payment!.method, PaymentMethod.cash);
        expect(settled.payment!.status, PaymentStatus.completed);
        expect(settled.canReprintReceipt, isTrue);
      }
    });

    test('G2 every malformed shape is quarantined, valid siblings survive, and '
        'the raw entry outlives an unrelated write', () async {
      final malformed = <Map<String, Object?>>[
        record(number: 'B-1', subtotal: 'oops'),
        record(number: 'B-2', payment: paid({'method': 'bitcoin'})),
        record(number: 'B-3', payment: paid({'status': 'weird'})),
        record(number: 'B-4', payment: paid({'tendered_minor': '15000'})),
        record(number: 'B-5', payment: paid({'paid_at': 'not-a-date'})),
      ];
      final prefs = await seed(<Object?>[record(number: 'A-1'), ...malformed]);
      final store = SharedPrefsRecentOrdersStore(prefs);

      final loaded = await store.load('till-1');
      expect(
        loaded.map((o) => o.orderNumber),
        <String>['A-1'],
        reason: 'no partial cheaper order, no fake cash, no fake completed',
      );
      expect(loaded.single.subtotalMinor, kCartSubtotal);

      // An ordinary save cycle — the shape that used to erase them.
      await store.persist('till-1', loaded);

      final rawAfter =
          ((jsonDecode(prefs.getString(ordersKey)!) as Map)['orders']! as List)
              .map((e) => jsonEncode(e))
              .toList();
      for (final m in malformed) {
        expect(
          rawAfter,
          contains(jsonEncode(m)),
          reason: 'the unreadable record must survive verbatim',
        );
      }
      expect(rawAfter, hasLength(6), reason: '5 quarantined + 1 rewritten');
    });

    test('G3 a corrupt record grants NO bill, receipt or preview eligibility, '
        'because it never becomes an order at all', () async {
      for (final bad in <Map<String, Object?>>[
        record(number: 'C-1', subtotal: 'oops'),
        record(number: 'C-2', payment: paid({'method': 'bitcoin'})),
        record(number: 'C-3', payment: paid({'status': 'weird'})),
      ]) {
        expect(
          () => PosRecentOrder.fromJson(bad),
          throwsA(isA<FormatException>()),
        );
      }
      // ...while the valid one grants exactly the eligibility it should.
      final ok = PosRecentOrder.fromJson(
        record(number: 'A-2', payment: paid()),
      );
      expect(ok.canReprintReceipt, isTrue);
      expect(ok.subtotalMinor, kCartSubtotal);
    });
  });
}
