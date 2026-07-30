import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, KitchenMeat, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart'
    show DemoCategory, DemoMenuItem;
import 'package:restoflow_pos/src/data/demo_tables.dart'
    show DemoTable, TableStatusKind;
import 'package:restoflow_pos/src/data/parked_carts_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/parked_carts_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PARKED-CARTS-001 — B. EXACT restore, process recreation, multiple carts,
/// table revalidation, catalog change, delete and the amendment interlock.
///
/// Everything here drives the REAL controller over the REAL SharedPreferences
/// store, with the REAL CartController / OrderSetupController.

const _scopeA = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchA',
  deviceId: 'dev1',
);

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
  categoryDisplayOrder: 3,
  itemDisplayOrder: 1,
);

const _cheese = SelectedModifier(
  optionId: 'opt-cheese',
  groupName: 'Extras',
  optionName: 'Cheese',
  priceDeltaMinor: 300,
  quantity: 2,
  kitchenMeat: KitchenMeat(quantity: 1, unit: 'patty'),
);

DemoTable _table({
  String id = 't-1',
  String label = 'T1',
  TableStatusKind status = TableStatusKind.available,
}) => DemoTable(
  table: DiningTable(
    tableId: id,
    label: label,
    organizationId: 'orgA',
    restaurantId: 'restA',
    branchId: 'branchA',
    seats: 4,
    area: 'Terrace',
  ),
  status: status,
);

/// Only `items` matters here — the catalog-review check reads the item list, and
/// the cart never consults categories.
PosMenuData _menu(List<DemoMenuItem> items) => PosMenuData(
  categories: const <DemoCategory>[],
  items: items,
  currencyCode: 'ILS',
);

Future<void> _tick() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// One app process: its own container over a SHARED SharedPreferences backing.
ProviderContainer _process({
  required SharedPreferences prefs,
  List<DemoTable> tables = const <DemoTable>[],
  List<DemoMenuItem> menu = const [_burger, _cola],
  PosSyncScope scope = _scopeA,
}) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      posSyncScopeProvider.overrideWithValue(scope),
      parkedCartsStoreProvider.overrideWithValue(
        SharedPrefsParkedCartsStore(prefs),
      ),
      tablesProvider.overrideWith((ref) async => tables),
      posMenuProvider.overrideWith((ref) async => _menu(menu)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Builds the representative cart: a configured burger (modifier ×2 carrying
/// kitchen meat, an item note, prep components) plus a plain cola.
void _buildCart(ProviderContainer c, {String? customer, DemoTable? table}) {
  final cart = c.read(cartControllerProvider.notifier);
  cart.addItemWithModifiers(_burger, const [_cheese], note: 'no onion');
  cart.addItem(_cola);
  final setup = c.read(orderSetupControllerProvider.notifier);
  if (table != null) {
    setup.setOrderType(OrderType.dineIn);
    setup.assignTable(table);
  }
  if (customer != null) {
    setup.setCustomerName(customer);
    setup.setCustomerPhone('0591234567');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('B1. EXACT restore', () {
    test('a takeaway cart restores with every snapshot intact', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      c.read(parkedCartsControllerProvider);
      await _tick();

      _buildCart(c, customer: 'Dana');
      final before = c.read(cartControllerProvider).lines;
      final beforeDraft = c
          .read(cartControllerProvider.notifier)
          .captureDraft();

      expect(
        await c.read(parkedCartsControllerProvider.notifier).park(),
        ParkResult.parked,
      );
      await _tick();
      expect(c.read(cartControllerProvider).lines, isEmpty);

      final id = c.read(parkedCartsControllerProvider).carts.single.id;
      final outcome = await c
          .read(parkedCartsControllerProvider.notifier)
          .restore(id);
      await _tick();

      expect(outcome.status, RestoreStatus.restored);
      expect(outcome.needsReview, isFalse);
      expect(outcome.entryRetained, isFalse);

      final after = c.read(cartControllerProvider).lines;
      expect(after, hasLength(before.length));
      for (var i = 0; i < before.length; i++) {
        expect(after[i].lineId, before[i].lineId);
        expect(after[i].menuItemId, before[i].menuItemId);
        expect(after[i].name, before[i].name);
        expect(after[i].quantity, before[i].quantity);
        expect(after[i].unitPriceMinor, before[i].unitPriceMinor);
        expect(after[i].lineTotalMinor, before[i].lineTotalMinor);
        expect(after[i].currencyCode, before[i].currencyCode);
        expect(after[i].note, before[i].note);
        expect(after[i].categoryDisplayOrder, before[i].categoryDisplayOrder);
        expect(after[i].itemDisplayOrder, before[i].itemDisplayOrder);
        expect(after[i].modifiers.length, before[i].modifiers.length);
        for (var m = 0; m < before[i].modifiers.length; m++) {
          final b = before[i].modifiers[m];
          final a = after[i].modifiers[m];
          expect(a.optionId, b.optionId);
          expect(a.optionName, b.optionName);
          expect(a.groupName, b.groupName);
          expect(a.priceDeltaMinor, b.priceDeltaMinor);
          expect(a.quantity, b.quantity);
          expect(a.kitchenMeat?.quantity, b.kitchenMeat?.quantity);
          expect(a.kitchenMeat?.unit, b.kitchenMeat?.unit);
        }
      }
      // Derived totals agree.
      expect(
        c.read(cartControllerProvider).subtotalMinor,
        beforeDraft.lines.fold<int>(
          0,
          (s, l) =>
              s +
              l.basePriceMinor * l.quantity +
              l.modifiers.fold<int>(0, (m, x) => m + x.totalDeltaMinor),
        ),
      );
      // The per-line PREP snapshot survived the whole round trip.
      final restoredDraft = c
          .read(cartControllerProvider.notifier)
          .captureDraft();
      final burgerLine = restoredDraft.lines.firstWhere(
        (l) => l.menuItemId == 'burger-9',
      );
      expect(burgerLine.prepComponents, hasLength(2));
      expect(burgerLine.prepComponents.first.name, 'Patty');

      // Customer data and order type came back.
      final setup = c.read(orderSetupControllerProvider);
      expect(setup.customerName, 'Dana');
      expect(setup.customerPhone, isNotNull);
      expect(setup.orderType, OrderType.takeaway);

      // The parked entry is gone (it became the active cart).
      expect(c.read(parkedCartsControllerProvider).carts, isEmpty);
    });

    test('a dine-in cart restores its VALID table', () async {
      final prefs = await SharedPreferences.getInstance();
      final table = _table();
      final c = _process(prefs: prefs, tables: [table]);
      c.read(parkedCartsControllerProvider);
      await _tick();

      _buildCart(c, table: table);
      await c.read(parkedCartsControllerProvider.notifier).park();
      await _tick();

      final id = c.read(parkedCartsControllerProvider).carts.single.id;
      final outcome = await c
          .read(parkedCartsControllerProvider.notifier)
          .restore(id);
      await _tick();

      expect(outcome.status, RestoreStatus.restored);
      expect(outcome.tableUnavailable, isFalse);
      final setup = c.read(orderSetupControllerProvider);
      expect(setup.orderType, OrderType.dineIn);
      expect(setup.assignedTable?.tableId, 't-1');
      expect(setup.assignedTable?.label, 'T1');
    });

    test(
      'restoring creates NO outbox/sync operation and no submitted order',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final c = _process(prefs: prefs);
        c.read(parkedCartsControllerProvider);
        await _tick();
        _buildCart(c);
        await c.read(parkedCartsControllerProvider.notifier).park();
        await _tick();
        final id = c.read(parkedCartsControllerProvider).carts.single.id;
        await c.read(parkedCartsControllerProvider.notifier).restore(id);
        await _tick();

        expect(c.read(outboxControllerProvider), isEmpty);
        expect(c.read(cartControllerProvider).submittedOrder, isNull);
      },
    );
  });

  group('B2. multiple carts', () {
    test('two parked carts coexist, keep distinct ids, and restoring one '
        'leaves the other untouched', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      final parked = c.read(parkedCartsControllerProvider.notifier);
      await _tick();

      _buildCart(c, customer: 'Alice');
      expect(await parked.park(), ParkResult.parked);
      c.read(cartControllerProvider.notifier).addItem(_cola);
      c.read(orderSetupControllerProvider.notifier).setCustomerName('Bob');
      expect(await parked.park(), ParkResult.parked);
      await _tick();

      final carts = c.read(parkedCartsControllerProvider).carts;
      expect(carts, hasLength(2));
      expect(carts.map((p) => p.id).toSet(), hasLength(2));

      final alice = carts.firstWhere((p) => p.customerName == 'Alice');
      final bob = carts.firstWhere((p) => p.customerName == 'Bob');
      expect(bob.itemCount, 1);
      // One burger (its ×2 is the MODIFIER quantity, not the item quantity)
      // plus one cola.
      expect(alice.itemCount, 2);

      await parked.restore(bob.id);
      await _tick();

      final remaining = c.read(parkedCartsControllerProvider).carts;
      expect(remaining, hasLength(1));
      expect(remaining.single.id, alice.id);
      expect(remaining.single.customerName, 'Alice');
      expect(remaining.single.itemCount, 2);
      expect(c.read(cartControllerProvider).lines, hasLength(1));
    });
  });

  group('B3. process recreation', () {
    test('parked carts survive a process restart, and nothing auto-submits, '
        'auto-prints or re-enqueues', () async {
      final prefs = await SharedPreferences.getInstance();

      final first = _process(prefs: prefs);
      first.read(parkedCartsControllerProvider);
      await _tick();
      _buildCart(first, customer: 'Dana');
      await first.read(parkedCartsControllerProvider.notifier).park();
      first.read(cartControllerProvider.notifier).addItem(_cola);
      await first.read(parkedCartsControllerProvider.notifier).park();
      await _tick();
      expect(first.read(parkedCartsControllerProvider).count, 2);
      first.dispose(); // the process dies

      // A brand-new container over the SAME durable backing.
      final second = _process(prefs: prefs);
      second.read(parkedCartsControllerProvider);
      await _tick();

      final state = second.read(parkedCartsControllerProvider);
      expect(state.loading, isFalse);
      expect(state.loadFailed, isFalse);
      expect(state.count, 2);
      // The till starts on a CLEAN cart — a parked draft is never auto-restored
      // and certainly never auto-sent.
      expect(second.read(cartControllerProvider).lines, isEmpty);
      expect(second.read(cartControllerProvider).submittedOrder, isNull);
      expect(second.read(outboxControllerProvider), isEmpty);
    });

    test('a restart in ANOTHER scope neither shows nor adopts them', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = _process(prefs: prefs);
      first.read(parkedCartsControllerProvider);
      await _tick();
      _buildCart(first);
      await first.read(parkedCartsControllerProvider.notifier).park();
      await _tick();
      first.dispose();

      final other = _process(
        prefs: prefs,
        scope: const PosSyncScope(
          organizationId: 'orgA',
          restaurantId: 'restA',
          branchId: 'branchB',
          deviceId: 'dev1',
        ),
      );
      other.read(parkedCartsControllerProvider);
      await _tick();
      expect(other.read(parkedCartsControllerProvider).count, 0);
      expect(other.read(parkedCartsControllerProvider).loadFailed, isFalse);
    });
  });

  group('B4. non-empty active cart', () {
    test(
      'restore REFUSES rather than overwriting, merging or discarding',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final c = _process(prefs: prefs);
        final parked = c.read(parkedCartsControllerProvider.notifier);
        await _tick();

        _buildCart(c, customer: 'Alice');
        await parked.park();
        await _tick();
        final aliceId = c.read(parkedCartsControllerProvider).carts.single.id;

        // A different customer is now at the till.
        c.read(cartControllerProvider.notifier).addItem(_cola);
        c.read(orderSetupControllerProvider.notifier).setCustomerName('Bob');

        final outcome = await parked.restore(aliceId);
        expect(outcome.status, RestoreStatus.activeCartNotEmpty);
        // NOTHING changed: Bob's cart intact, Alice still parked.
        expect(c.read(cartControllerProvider).lines, hasLength(1));
        expect(c.read(orderSetupControllerProvider).customerName, 'Bob');
        expect(c.read(parkedCartsControllerProvider).carts.single.id, aliceId);
      },
    );

    test('"park current and restore" parks the active cart FIRST, then '
        'restores — neither cart is lost and nothing merges', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      final parked = c.read(parkedCartsControllerProvider.notifier);
      await _tick();

      _buildCart(c, customer: 'Alice');
      await parked.park();
      await _tick();
      final aliceId = c.read(parkedCartsControllerProvider).carts.single.id;

      c.read(cartControllerProvider.notifier).addItem(_cola);
      c.read(orderSetupControllerProvider.notifier).setCustomerName('Bob');

      final outcome = await parked.restore(aliceId, parkCurrentFirst: true);
      await _tick();

      expect(outcome.status, RestoreStatus.restored);
      // Alice is now the ACTIVE cart, with her own lines only (no merge).
      expect(c.read(cartControllerProvider).lines, hasLength(2));
      expect(c.read(orderSetupControllerProvider).customerName, 'Alice');
      // Bob is now the parked one — nothing was lost.
      final remaining = c.read(parkedCartsControllerProvider).carts;
      expect(remaining, hasLength(1));
      expect(remaining.single.customerName, 'Bob');
      expect(remaining.single.itemCount, 1);
    });
  });

  group('B5. table revalidation', () {
    test('an OCCUPIED table is not claimed: items and customer restore, the '
        'table stays unassigned, and no other table is chosen', () async {
      final prefs = await SharedPreferences.getInstance();
      final table = _table();
      final c = _process(
        prefs: prefs,
        tables: [
          table,
          _table(id: 't-2', label: 'T2'),
        ],
      );
      c.read(parkedCartsControllerProvider);
      await _tick();
      _buildCart(c, customer: 'Dana', table: table);
      await c.read(parkedCartsControllerProvider.notifier).park();
      await _tick();
      final id = c.read(parkedCartsControllerProvider).carts.single.id;
      c.dispose();

      // The floor moved on: T1 is now occupied.
      final later = _process(
        prefs: prefs,
        tables: [
          _table(status: TableStatusKind.occupied),
          _table(id: 't-2', label: 'T2'),
        ],
      );
      later.read(parkedCartsControllerProvider);
      await _tick();

      final outcome = await later
          .read(parkedCartsControllerProvider.notifier)
          .restore(id);
      await _tick();

      expect(outcome.status, RestoreStatus.restored);
      expect(outcome.tableUnavailable, isTrue);
      expect(outcome.needsReview, isTrue);
      expect(later.read(cartControllerProvider).lines, hasLength(2));
      expect(later.read(orderSetupControllerProvider).customerName, 'Dana');
      expect(
        later.read(orderSetupControllerProvider).orderType,
        OrderType.dineIn,
      );
      expect(
        later.read(orderSetupControllerProvider).assignedTable,
        isNull,
        reason: 'no table is ever chosen automatically',
      );
      expect(
        later.read(orderSetupControllerProvider).needsTableWarning,
        isTrue,
      );
    });

    test('an OUT-OF-SERVICE (blocked) table is not claimed either', () async {
      final prefs = await SharedPreferences.getInstance();
      final table = _table();
      final c = _process(prefs: prefs, tables: [table]);
      c.read(parkedCartsControllerProvider);
      await _tick();
      _buildCart(c, table: table);
      await c.read(parkedCartsControllerProvider.notifier).park();
      await _tick();
      final id = c.read(parkedCartsControllerProvider).carts.single.id;
      c.dispose();

      final later = _process(
        prefs: prefs,
        tables: [_table(status: TableStatusKind.blocked)],
      );
      later.read(parkedCartsControllerProvider);
      await _tick();
      final outcome = await later
          .read(parkedCartsControllerProvider.notifier)
          .restore(id);
      expect(outcome.tableUnavailable, isTrue);
      expect(later.read(orderSetupControllerProvider).assignedTable, isNull);
    });

    test('a table that VANISHED from the floor is not claimed', () async {
      final prefs = await SharedPreferences.getInstance();
      final table = _table();
      final c = _process(prefs: prefs, tables: [table]);
      c.read(parkedCartsControllerProvider);
      await _tick();
      _buildCart(c, table: table);
      await c.read(parkedCartsControllerProvider.notifier).park();
      await _tick();
      final id = c.read(parkedCartsControllerProvider).carts.single.id;
      c.dispose();

      final later = _process(prefs: prefs, tables: const <DemoTable>[]);
      later.read(parkedCartsControllerProvider);
      await _tick();
      final outcome = await later
          .read(parkedCartsControllerProvider.notifier)
          .restore(id);
      expect(outcome.tableUnavailable, isTrue);
      expect(later.read(orderSetupControllerProvider).assignedTable, isNull);
    });
  });

  group('B6. catalog change', () {
    test('a renamed/repriced item restores from the PARKED snapshot, never '
        'from the current catalog', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      c.read(parkedCartsControllerProvider);
      await _tick();
      _buildCart(c);
      await c.read(parkedCartsControllerProvider.notifier).park();
      await _tick();
      final id = c.read(parkedCartsControllerProvider).carts.single.id;
      c.dispose();

      // The menu changed underneath: new name, new price.
      final later = _process(
        prefs: prefs,
        menu: const [
          DemoMenuItem(
            id: 'burger-9',
            name: 'RENAMED Burger',
            priceMinor: 9999,
            categoryId: 'food',
            categoryName: 'Food',
          ),
          _cola,
        ],
      );
      later.read(parkedCartsControllerProvider);
      await _tick();
      final outcome = await later
          .read(parkedCartsControllerProvider.notifier)
          .restore(id);
      await _tick();

      expect(outcome.status, RestoreStatus.restored);
      final line = later
          .read(cartControllerProvider)
          .lines
          .firstWhere((l) => l.menuItemId == 'burger-9');
      expect(line.name, 'Double Burger', reason: 'the parked snapshot wins');
      expect(line.unitPriceMinor, 4200, reason: 'no silent repricing');
      expect(outcome.unavailableItems, isEmpty);
    });

    test('an item that became UNAVAILABLE raises a non-blocking review and '
        'still restores its snapshot', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      c.read(parkedCartsControllerProvider);
      await _tick();
      _buildCart(c);
      await c.read(parkedCartsControllerProvider.notifier).park();
      await _tick();
      final id = c.read(parkedCartsControllerProvider).carts.single.id;
      c.dispose();

      final later = _process(
        prefs: prefs,
        menu: [_burger.withAvailability('unavailable', 'sold_out'), _cola],
      );
      later.read(parkedCartsControllerProvider);
      await _tick();
      final outcome = await later
          .read(parkedCartsControllerProvider.notifier)
          .restore(id);
      await _tick();

      expect(outcome.status, RestoreStatus.restored);
      expect(outcome.unavailableItems, ['Double Burger']);
      expect(outcome.needsReview, isTrue);
      expect(later.read(cartControllerProvider).lines, hasLength(2));
    });

    test('an item DELETED from the menu also raises the review', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      c.read(parkedCartsControllerProvider);
      await _tick();
      _buildCart(c);
      await c.read(parkedCartsControllerProvider.notifier).park();
      await _tick();
      final id = c.read(parkedCartsControllerProvider).carts.single.id;
      c.dispose();

      final later = _process(prefs: prefs, menu: const [_cola]);
      later.read(parkedCartsControllerProvider);
      await _tick();
      final outcome = await later
          .read(parkedCartsControllerProvider.notifier)
          .restore(id);
      expect(outcome.unavailableItems, ['Double Burger']);
    });
  });

  group('B7. delete', () {
    test(
      'delete removes ONLY the selected stable id and touches no server',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final c = _process(prefs: prefs);
        final parked = c.read(parkedCartsControllerProvider.notifier);
        await _tick();
        _buildCart(c, customer: 'Alice');
        await parked.park();
        c.read(cartControllerProvider.notifier).addItem(_cola);
        c.read(orderSetupControllerProvider.notifier).setCustomerName('Bob');
        await parked.park();
        await _tick();

        final carts = c.read(parkedCartsControllerProvider).carts;
        final bob = carts.firstWhere((p) => p.customerName == 'Bob');
        final alice = carts.firstWhere((p) => p.customerName == 'Alice');

        expect(await parked.delete(bob.id), DeleteResult.deleted);
        await _tick();

        final remaining = c.read(parkedCartsControllerProvider).carts;
        expect(remaining, hasLength(1));
        expect(remaining.single.id, alice.id);
        expect(c.read(outboxControllerProvider), isEmpty);

        // And it is gone from disk, not just from memory.
        final onDisk = await SharedPrefsParkedCartsStore(prefs).load(_scopeA);
        expect(onDisk.carts.map((p) => p.id), [alice.id]);
      },
    );

    test(
      'deleting an unknown id is reported, not silently swallowed',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final c = _process(prefs: prefs);
        c.read(parkedCartsControllerProvider);
        await _tick();
        expect(
          await c
              .read(parkedCartsControllerProvider.notifier)
              .delete('park-404'),
          DeleteResult.notFound,
        );
      },
    );

    test('rapid repeated delete removes it exactly once', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      final parked = c.read(parkedCartsControllerProvider.notifier);
      await _tick();
      _buildCart(c);
      await parked.park();
      await _tick();
      final id = c.read(parkedCartsControllerProvider).carts.single.id;

      final results = await Future.wait([
        parked.delete(id),
        parked.delete(id),
        parked.delete(id),
      ]);
      expect(results.where((r) => r == DeleteResult.deleted), hasLength(1));
      expect(c.read(parkedCartsControllerProvider).carts, isEmpty);
    });
  });

  group('B8. the AMENDMENT interlock', () {
    test('a cart LOCKED by an addition cannot be parked', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      c.read(parkedCartsControllerProvider);
      await _tick();
      _buildCart(c);

      expect(
        c
            .read(cartControllerProvider.notifier)
            .lockForAddition(
              const CartLockOwner(
                generation: 1,
                orderId: 'o-1',
                localOperationId: 'op-1',
              ),
            ),
        isTrue,
      );
      expect(c.read(cartControllerProvider).lockedByAddition, isTrue);
      expect(c.read(parkedCartsControllerProvider.notifier).canPark, isFalse);
      expect(
        await c.read(parkedCartsControllerProvider.notifier).park(),
        ParkResult.blockedByAddition,
      );
      // The frozen cart is untouched.
      expect(c.read(cartControllerProvider).lines, hasLength(2));
      expect(c.read(parkedCartsControllerProvider).carts, isEmpty);
    });

    test('restore is refused UP FRONT while the cart is locked — before any '
        'non-empty-cart dialog would be offered', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      final parked = c.read(parkedCartsControllerProvider.notifier);
      await _tick();
      _buildCart(c);
      await parked.park();
      await _tick();
      final id = c.read(parkedCartsControllerProvider).carts.single.id;

      // A new cart is being built and then frozen by an amendment.
      c.read(cartControllerProvider.notifier).addItem(_cola);
      c
          .read(cartControllerProvider.notifier)
          .lockForAddition(
            const CartLockOwner(
              generation: 2,
              orderId: 'o-2',
              localOperationId: 'op-2',
            ),
          );

      final outcome = await parked.restore(id);
      expect(
        outcome.status,
        RestoreStatus.blockedByAddition,
        reason: 'the lock refusal must win over activeCartNotEmpty',
      );
      // Nothing moved.
      expect(c.read(parkedCartsControllerProvider).carts.single.id, id);
      expect(c.read(cartControllerProvider).lines, hasLength(1));
    });

    test('the existing cart mutation-refusal contract is unchanged', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      await _tick();
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_cola);
      cart.lockForAddition(
        const CartLockOwner(
          generation: 1,
          orderId: 'o-1',
          localOperationId: 'op-1',
        ),
      );
      expect(cart.addItem(_burger), CartMutationResult.lockedByAddition);
      expect(cart.clear(), CartMutationResult.lockedByAddition);
      expect(cart.startNewOrder(), CartMutationResult.lockedByAddition);
    });
  });

  group('B9. concurrency', () {
    test('rapid repeated restore restores exactly once', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(prefs: prefs);
      final parked = c.read(parkedCartsControllerProvider.notifier);
      await _tick();
      _buildCart(c);
      await parked.park();
      await _tick();
      final id = c.read(parkedCartsControllerProvider).carts.single.id;

      final results = await Future.wait([
        parked.restore(id),
        parked.restore(id),
        parked.restore(id),
      ]);
      await _tick();

      expect(
        results.where((r) => r.status == RestoreStatus.restored),
        hasLength(1),
      );
      expect(c.read(cartControllerProvider).lines, hasLength(2));
      expect(c.read(parkedCartsControllerProvider).carts, isEmpty);
    });
  });
}
