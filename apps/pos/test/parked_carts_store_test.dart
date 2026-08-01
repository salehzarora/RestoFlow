import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenMeat, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/parked_carts_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException, PosSyncScope;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/parked_carts_controller.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PARKED-CARTS-001 — A. the parked-cart STORE, scope isolation, and the ATOMIC
/// park contract.
///
/// A parked cart is a purely LOCAL draft. Parking must never touch the server,
/// the outbox, the kitchen, a printer, a payment, or table state — and it must
/// never clear the cashier's cart until the draft is provably on disk.
///
/// This suite drives the REAL store, the REAL controller, and the REAL
/// CartController/OrderSetupController, so it pins behaviour rather than
/// serialization helpers.

const _scopeA = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchA',
  deviceId: 'dev1',
);
const _scopeOtherBranch = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchB',
  deviceId: 'dev1',
);
const _scopeOtherDevice = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchA',
  deviceId: 'dev2',
);

final _t0 = DateTime.utc(2026, 8, 5, 9);

/// A menu item carrying BOTH kitchen prep components and a meat-bearing
/// modifier, so a parked cart exercises every snapshot the kitchen needs.
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

ParkedCart _cart({
  String id = 'park-1',
  DateTime? createdAt,
  DateTime? updatedAt,
  String? label,
  OrderType orderType = OrderType.takeaway,
}) => ParkedCart(
  id: id,
  createdAt: createdAt ?? _t0,
  updatedAt: updatedAt ?? _t0,
  orderType: orderType,
  label: label,
  draft: const CartDraftSnapshot(
    currencyCode: 'ILS',
    lines: [
      CartDraftLine(
        lineId: 'line-0',
        menuItemId: 'burger-9',
        name: 'Double Burger',
        basePriceMinor: 4200,
        quantity: 2,
        modifiers: [_cheese],
        note: 'no onion',
        categoryDisplayOrder: 1,
        itemDisplayOrder: 2,
      ),
    ],
  ),
  scopeKey: _scopeA.key,
  employeeProfileId: 'emp-A',
);

Future<void> _tick() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// A SharedPreferences double whose `setString` can be made to fail the way the
/// real one does on a full disk or a browser refusing localStorage: it returns
/// FALSE without throwing.
class _FailingPrefs implements SharedPreferences {
  _FailingPrefs(this._inner);
  final SharedPreferences _inner;
  bool failWrites = false;
  int writeAttempts = 0;

  @override
  Future<bool> setString(String key, String value) async {
    writeAttempts++;
    if (failWrites) return false;
    return _inner.setString(key, value);
  }

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  Future<bool> remove(String key) => _inner.remove(key);

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by the parked-cart store');
}

ProviderContainer _process({
  required ParkedCartsStore store,
  PosSyncScope scope = _scopeA,
}) {
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
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('A1. versioned serialization', () {
    test(
      'a parked cart round-trips through JSON with every snapshot intact',
      () {
        final restored = ParkedCart.fromJson(
          jsonDecode(jsonEncode(_cart().toJson())) as Map<String, Object?>,
        );
        expect(restored.id, 'park-1');
        expect(restored.orderType, OrderType.takeaway);
        expect(restored.createdAt, _t0);
        expect(restored.scopeKey, _scopeA.key);
        expect(restored.employeeProfileId, 'emp-A');
        final line = restored.draft.lines.single;
        expect(line.lineId, 'line-0');
        expect(line.menuItemId, 'burger-9');
        expect(line.basePriceMinor, 4200);
        expect(line.quantity, 2);
        expect(line.note, 'no onion');
        expect(line.categoryDisplayOrder, 1);
        expect(line.itemDisplayOrder, 2);
        final mod = line.modifiers.single;
        expect(mod.optionId, 'opt-cheese');
        expect(mod.quantity, 2);
        expect(mod.priceDeltaMinor, 300);
        expect(mod.kitchenMeat?.quantity, 1);
        expect(mod.kitchenMeat?.unit, 'patty');
      },
    );

    test('totals are DERIVED from the snapshot, never stored as authoritative '
        'independent values', () {
      final json = _cart().toJson();
      for (final key in json.keys) {
        expect(
          key,
          isNot(anyOf('subtotal_minor', 'total_minor', 'grand_total_minor')),
          reason: 'a stored total could disagree with its own lines',
        );
      }
      // MONEY-PRICING-FORMULA-002A: 2 x (4200 + 300 x 2) = 9600
      expect(_cart().subtotalMinor, 9600);
      expect(_cart().itemCount, 2);
      expect(_cart().currencyCode, 'ILS');
    });

    test('OPTIONAL fields decode tolerantly — an older/partial record never '
        'crashes the till on start', () {
      final json = _cart().toJson();
      final line = ((json['draft'] as Map)['lines'] as List).single as Map;
      line.remove('modifiers');
      line.remove('note');
      json.remove('label');
      json.remove('table');
      json.remove('customer_name');
      json.remove('customer_phone');

      final restored = ParkedCart.fromJson(json);
      expect(restored.draft.lines.single.menuItemId, 'burger-9');
      expect(restored.draft.lines.single.modifiers, isEmpty);
      expect(restored.draft.lines.single.note, isNull);
      expect(restored.label, isNull);
      expect(restored.table, isNull);
      expect(restored.customerName, isNull);
      expect(restored.customerPhone, isNull);
    });

    test('a record missing its IDENTITY is unusable and REJECTED — never '
        'silently given a fabricated id', () {
      final json = _cart().toJson()..remove('id');
      expect(() => ParkedCart.fromJson(json), throwsA(isA<FormatException>()));
    });
  });

  group('A2. stable identity and ordering', () {
    test(
      'ids come from a PERSISTED monotonic sequence, never a list position',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsParkedCartsStore(prefs);
        final a = await store.add(_scopeA, (id) => _cart(id: id));
        final b = await store.add(_scopeA, (id) => _cart(id: id));
        expect(a.id, 'park-1');
        expect(b.id, 'park-2');

        // A NEW store instance over the same prefs continues the sequence.
        final c = await SharedPrefsParkedCartsStore(
          prefs,
        ).add(_scopeA, (id) => _cart(id: id));
        expect(c.id, 'park-3');
      },
    );

    test('a deleted id is NEVER reused', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsParkedCartsStore(prefs);
      await store.add(_scopeA, (id) => _cart(id: id));
      final b = await store.add(_scopeA, (id) => _cart(id: id));
      await store.remove(_scopeA, b.id);
      final c = await store.add(_scopeA, (id) => _cart(id: id));
      expect(c.id, 'park-3', reason: 'park-2 was deleted and must not return');

      // Both fixtures share _t0, so the documented tie-break (id descending)
      // decides — NOT insertion order.
      final snapshot = await store.load(_scopeA);
      expect(snapshot.carts.map((p) => p.id), ['park-3', 'park-1']);
    });

    test(
      'ordering is updatedAt DESCENDING with a deterministic tie-break',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsParkedCartsStore(prefs);
        await store.add(
          _scopeA,
          (id) => _cart(id: id, updatedAt: _t0.add(const Duration(minutes: 5))),
        );
        await store.add(_scopeA, (id) => _cart(id: id, updatedAt: _t0));
        // Same timestamp as park-1 => the tie-break must be stable, not random.
        await store.add(
          _scopeA,
          (id) => _cart(id: id, updatedAt: _t0.add(const Duration(minutes: 5))),
        );

        final first = (await store.load(
          _scopeA,
        )).carts.map((p) => p.id).toList();
        final second = (await store.load(
          _scopeA,
        )).carts.map((p) => p.id).toList();
        expect(first, second, reason: 'ordering must be deterministic');
        expect(first.first, anyOf('park-1', 'park-3'));
        expect(first.last, 'park-2', reason: 'oldest updatedAt sorts last');
      },
    );
  });

  group('A3. durability and failure honesty', () {
    test(
      'a write that does not stick THROWS PosPersistenceException',
      () async {
        final prefs = _FailingPrefs(await SharedPreferences.getInstance());
        final store = SharedPrefsParkedCartsStore(prefs);
        prefs.failWrites = true;
        await expectLater(
          store.add(_scopeA, (id) => _cart(id: id)),
          throwsA(isA<PosPersistenceException>()),
        );
        // Nothing was published: the envelope is still absent.
        prefs.failWrites = false;
        expect((await store.load(_scopeA)).carts, isEmpty);
      },
    );

    test('remove and update also verify their write', () async {
      final prefs = _FailingPrefs(await SharedPreferences.getInstance());
      final store = SharedPrefsParkedCartsStore(prefs);
      final a = await store.add(_scopeA, (id) => _cart(id: id));
      prefs.failWrites = true;
      await expectLater(
        store.remove(_scopeA, a.id),
        throwsA(isA<PosPersistenceException>()),
      );
      await expectLater(
        store.update(_scopeA, a.copyWith(label: 'x')),
        throwsA(isA<PosPersistenceException>()),
      );
      prefs.failWrites = false;
      expect((await store.load(_scopeA)).carts.single.id, a.id);
    });

    test(
      'an UNKNOWN envelope version fails CLOSED (never mis-parsed)',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          parkedCartsStorageKey(_scopeA),
          jsonEncode(<String, Object?>{'version': 99, 'seq': 4, 'carts': []}),
        );
        await expectLater(
          SharedPrefsParkedCartsStore(prefs).load(_scopeA),
          throwsA(isA<ParkedCartsLoadException>()),
        );
      },
    );

    test('a corrupt INDIVIDUAL record is reported and PRESERVED — the raw '
        'envelope is never silently pruned', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsParkedCartsStore(prefs);
      final good = await store.add(_scopeA, (id) => _cart(id: id));

      // Inject one unreadable record beside the good one.
      final raw =
          jsonDecode(prefs.getString(parkedCartsStorageKey(_scopeA))!)
              as Map<String, Object?>;
      (raw['carts'] as List).add(<String, Object?>{'id': 'park-99'});
      await prefs.setString(parkedCartsStorageKey(_scopeA), jsonEncode(raw));

      final snapshot = await store.load(_scopeA);
      expect(snapshot.carts.map((p) => p.id), [good.id]);
      expect(snapshot.unreadable, hasLength(1));

      // A later legitimate write must NOT delete the record it could not read.
      await store.add(_scopeA, (id) => _cart(id: id));
      final after =
          jsonDecode(prefs.getString(parkedCartsStorageKey(_scopeA))!)
              as Map<String, Object?>;
      expect(
        (after['carts'] as List).where((c) => c is Map && c['id'] == 'park-99'),
        hasLength(1),
        reason: 'an unreadable record survives, it is not data loss',
      );
    });
  });

  group('A4. scope isolation', () {
    test('each scope has its OWN namespace and cannot see another', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsParkedCartsStore(prefs);
      await store.add(_scopeA, (id) => _cart(id: id));
      await store.add(_scopeA, (id) => _cart(id: id));
      await store.add(_scopeOtherBranch, (id) => _cart(id: id));

      expect((await store.load(_scopeA)).carts, hasLength(2));
      expect((await store.load(_scopeOtherBranch)).carts, hasLength(1));
      expect((await store.load(_scopeOtherDevice)).carts, isEmpty);

      // Distinct storage keys — no shared bucket to enumerate.
      expect(
        parkedCartsStorageKey(_scopeA),
        isNot(parkedCartsStorageKey(_scopeOtherBranch)),
      );
      expect(
        parkedCartsStorageKey(_scopeA),
        isNot(parkedCartsStorageKey(_scopeOtherDevice)),
      );
      expect(parkedCartsStorageKey(_scopeA), contains('parked_carts'));
      expect(parkedCartsStorageKey(_scopeA), contains(_scopeA.key));
    });

    test('DEMO and REAL resolve to different namespaces', () {
      expect(
        parkedCartsStorageKey(kDemoSyncScope),
        isNot(parkedCartsStorageKey(_scopeA)),
      );
    });
  });

  group('A5. the ATOMIC park contract (real controllers)', () {
    test('park persists FIRST, then resets the cart and the setup', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(store: SharedPrefsParkedCartsStore(prefs));

      final cart = c.read(cartControllerProvider.notifier);
      final setup = c.read(orderSetupControllerProvider.notifier);
      expect(
        cart.addItemWithModifiers(_burger, const [_cheese], note: 'no onion'),
        CartMutationResult.applied,
      );
      expect(cart.addItem(_cola), CartMutationResult.applied);
      setup.setCustomerName('Dana');
      setup.setCustomerPhone('0591234567');

      final parked = c.read(parkedCartsControllerProvider.notifier);
      await _tick();
      expect(await parked.park(), ParkResult.parked);
      await _tick();

      // Exactly one record, and it carries the whole draft.
      final stored = (await SharedPrefsParkedCartsStore(
        prefs,
      ).load(_scopeA)).carts;
      expect(stored, hasLength(1));
      expect(stored.single.draft.lines, hasLength(2));
      expect(stored.single.customerName, 'Dana');
      expect(stored.single.customerPhone, isNotNull);

      // The cart and the setup were reset ONLY after the write succeeded.
      expect(c.read(cartControllerProvider).lines, isEmpty);
      expect(c.read(orderSetupControllerProvider).customerName, isNull);
      expect(c.read(orderSetupControllerProvider).customerPhoneInput, isEmpty);
    });

    test(
      'park creates NO outbox operation, no order, no payment, no print',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final c = _process(store: SharedPrefsParkedCartsStore(prefs));
        c.read(cartControllerProvider.notifier).addItem(_cola);
        await _tick();
        expect(
          await c.read(parkedCartsControllerProvider.notifier).park(),
          ParkResult.parked,
        );
        await _tick();

        expect(
          c.read(outboxControllerProvider),
          isEmpty,
          reason: 'parking is a local draft operation, never a sync operation',
        );
        expect(c.read(cartControllerProvider).submittedOrder, isNull);
      },
    );

    test('a FAILED persist leaves the cart and the setup byte-for-byte '
        'unchanged and creates no partial row', () async {
      final prefs = _FailingPrefs(await SharedPreferences.getInstance());
      final c = _process(store: SharedPrefsParkedCartsStore(prefs));
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(_burger, const [_cheese], note: 'no onion');
      c.read(orderSetupControllerProvider.notifier).setCustomerName('Dana');
      await _tick();

      final linesBefore = c.read(cartControllerProvider).lines;
      prefs.failWrites = true;
      expect(
        await c.read(parkedCartsControllerProvider.notifier).park(),
        ParkResult.persistFailed,
      );
      await _tick();

      final linesAfter = c.read(cartControllerProvider).lines;
      expect(linesAfter, hasLength(linesBefore.length));
      expect(linesAfter.single.lineId, linesBefore.single.lineId);
      expect(linesAfter.single.quantity, linesBefore.single.quantity);
      expect(linesAfter.single.note, 'no onion');
      expect(c.read(orderSetupControllerProvider).customerName, 'Dana');

      prefs.failWrites = false;
      expect(
        (await SharedPrefsParkedCartsStore(prefs).load(_scopeA)).carts,
        isEmpty,
      );
    });

    test('an EMPTY cart cannot be parked', () async {
      final c = _process(store: InMemoryParkedCartsStore());
      await _tick();
      expect(
        await c.read(parkedCartsControllerProvider.notifier).park(),
        ParkResult.cartEmpty,
      );
    });

    test('rapid double-press parks exactly ONE cart', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(store: SharedPrefsParkedCartsStore(prefs));
      c.read(cartControllerProvider.notifier).addItem(_cola);
      final parked = c.read(parkedCartsControllerProvider.notifier);
      await _tick();

      final results = await Future.wait([
        parked.park(),
        parked.park(),
        parked.park(),
      ]);
      await _tick();

      expect(results.where((r) => r == ParkResult.parked), hasLength(1));
      expect(
        (await SharedPrefsParkedCartsStore(prefs).load(_scopeA)).carts,
        hasLength(1),
      );
    });

    test('parked carts are visible to the controller and counted', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _process(store: SharedPrefsParkedCartsStore(prefs));
      c.read(parkedCartsControllerProvider); // instantiate, then let it load
      await _tick();
      expect(c.read(parkedCartsControllerProvider).loading, isFalse);
      expect(c.read(parkedCartsControllerProvider).count, 0);

      c.read(cartControllerProvider.notifier).addItem(_cola);
      await c.read(parkedCartsControllerProvider.notifier).park();
      await _tick();
      expect(c.read(parkedCartsControllerProvider).count, 1);
      expect(c.read(parkedCartsControllerProvider).carts.single.itemCount, 1);
    });

    test('a load failure is SURFACED, never shown as an empty list', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        parkedCartsStorageKey(_scopeA),
        jsonEncode(<String, Object?>{'version': 99}),
      );
      final c = _process(store: SharedPrefsParkedCartsStore(prefs));
      c.read(parkedCartsControllerProvider); // instantiate, then let it load
      await _tick();
      final state = c.read(parkedCartsControllerProvider);
      expect(state.loading, isFalse);
      expect(state.loadFailed, isTrue);
      expect(state.carts, isEmpty);
    });
  });
}
