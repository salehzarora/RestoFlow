import 'package:drift/drift.dart' show TableInfo, Value, Variable;
import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 1, 1, 12);
const _org = 'org-1';
const _rest = 'rest-1';
const _dev = 'dev-1';

MenuCategoriesCompanion _category(String id, {String name = 'Drinks'}) =>
    MenuCategoriesCompanion.insert(
      id: id,
      organizationId: _org,
      deviceId: _dev,
      localOperationId: 'op-$id',
      restaurantId: _rest,
      name: name,
      clientUpdatedAt: _now,
      createdAt: _now,
      updatedAt: _now,
    );

MenuItemsCompanion _item(
  String id,
  String categoryId, {
  String name = 'Cola',
  int price = 1200,
  String currency = 'ILS',
}) => MenuItemsCompanion.insert(
  id: id,
  organizationId: _org,
  deviceId: _dev,
  localOperationId: 'op-$id',
  restaurantId: _rest,
  menuCategoryId: categoryId,
  name: name,
  basePriceMinor: price,
  currencyCode: currency,
  clientUpdatedAt: _now,
  createdAt: _now,
  updatedAt: _now,
);

ItemSizesCompanion _size(String id, String itemId, {int delta = 300}) =>
    ItemSizesCompanion.insert(
      id: id,
      organizationId: _org,
      deviceId: _dev,
      localOperationId: 'op-$id',
      restaurantId: _rest,
      menuItemId: itemId,
      name: 'Large',
      priceDeltaMinor: Value(delta),
      clientUpdatedAt: _now,
      createdAt: _now,
      updatedAt: _now,
    );

ItemVariantsCompanion _variant(String id, String itemId, {int delta = 0}) =>
    ItemVariantsCompanion.insert(
      id: id,
      organizationId: _org,
      deviceId: _dev,
      localOperationId: 'op-$id',
      restaurantId: _rest,
      menuItemId: itemId,
      name: 'Zero sugar',
      priceDeltaMinor: Value(delta),
      clientUpdatedAt: _now,
      createdAt: _now,
      updatedAt: _now,
    );

ModifiersCompanion _modifier(String id, String itemId) =>
    ModifiersCompanion.insert(
      id: id,
      organizationId: _org,
      deviceId: _dev,
      localOperationId: 'op-$id',
      restaurantId: _rest,
      menuItemId: itemId,
      name: 'Toppings',
      selectionType: 'multiple',
      clientUpdatedAt: _now,
      createdAt: _now,
      updatedAt: _now,
    );

ModifierOptionsCompanion _option(
  String id,
  String modifierId, {
  int delta = 250,
}) => ModifierOptionsCompanion.insert(
  id: id,
  organizationId: _org,
  deviceId: _dev,
  localOperationId: 'op-$id',
  restaurantId: _rest,
  modifierId: modifierId,
  name: 'Extra cheese',
  priceDeltaMinor: Value(delta),
  clientUpdatedAt: _now,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  late LocalDatabase db;
  late MenuRepository repo;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repo = MenuRepository(db);
  });
  tearDown(() => db.close());

  /// Seeds a full FK chain c1 -> i1 -> (s1, v1, m1 -> o1).
  Future<void> seedChain() async {
    await repo.createCategory(_category('c1'));
    await repo.createItem(_item('i1', 'c1'));
    await repo.createSize(_size('s1', 'i1'));
    await repo.createVariant(_variant('v1', 'i1'));
    await repo.createModifier(_modifier('m1', 'i1'));
    await repo.createOption(_option('o1', 'm1'));
  }

  Future<bool> _rowPresent(String table, String id) async {
    final rows = await db
        .customSelect(
          'SELECT deleted_at FROM $table WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.length == 1 && rows.single.data['deleted_at'] != null;
  }

  group('CRUD round-trip — all six tables (RF-030)', () {
    test('menu_categories create/get/list/update/tombstone', () async {
      await repo.createCategory(_category('c1', name: 'Drinks'));

      final got = await repo.getCategory('c1');
      expect(got, isNotNull);
      expect(got!.name, 'Drinks');
      expect(got.organizationId, _org);
      expect(got.restaurantId, _rest);
      expect(got.branchId, isNull);

      expect(
        (await repo.listCategories(
          organizationId: _org,
          restaurantId: _rest,
        )).map((c) => c.id),
        contains('c1'),
      );

      expect(
        await repo.updateCategory(
          MenuCategoriesCompanion(
            id: const Value('c1'),
            name: const Value('Beverages'),
            updatedAt: Value(_now),
          ),
        ),
        1,
      );
      expect((await repo.getCategory('c1'))!.name, 'Beverages');

      expect(await repo.tombstoneCategory('c1', _now), 1);
      expect(await repo.getCategory('c1'), isNull); // excluded from get
      expect(
        await repo.listCategories(organizationId: _org, restaurantId: _rest),
        isEmpty,
      ); // excluded from list
      expect(await repo.tombstoneCategory('c1', _now), 0); // idempotent
      expect(await _rowPresent('menu_categories', 'c1'), isTrue); // not removed
    });

    test('menu_items create/get/list/update/tombstone', () async {
      await repo.createCategory(_category('c1'));
      await repo.createItem(_item('i1', 'c1', price: 1200, currency: 'ILS'));

      final got = await repo.getItem('i1');
      expect(got, isNotNull);
      expect(got!.basePriceMinor, 1200);
      expect(got.currencyCode, 'ILS');
      expect(got.menuCategoryId, 'c1');

      expect((await repo.listItemsByCategory('c1')).map((i) => i.id), ['i1']);

      expect(
        await repo.updateItem(
          MenuItemsCompanion(
            id: const Value('i1'),
            basePriceMinor: const Value(1500),
            updatedAt: Value(_now),
          ),
        ),
        1,
      );
      expect((await repo.getItem('i1'))!.basePriceMinor, 1500);

      expect(await repo.tombstoneItem('i1', _now), 1);
      expect(await repo.getItem('i1'), isNull);
      expect(await repo.listItemsByCategory('c1'), isEmpty);
      expect(await repo.tombstoneItem('i1', _now), 0);
      expect(await _rowPresent('menu_items', 'i1'), isTrue);
    });

    test('item_sizes create/get/list/update/tombstone', () async {
      await repo.createCategory(_category('c1'));
      await repo.createItem(_item('i1', 'c1'));
      await repo.createSize(_size('s1', 'i1', delta: 300));

      final got = await repo.getSize('s1');
      expect(got!.priceDeltaMinor, 300);
      expect(got.menuItemId, 'i1');
      expect((await repo.listSizesByItem('i1')).map((s) => s.id), ['s1']);

      expect(
        await repo.updateSize(
          ItemSizesCompanion(
            id: const Value('s1'),
            priceDeltaMinor: const Value(400),
            updatedAt: Value(_now),
          ),
        ),
        1,
      );
      expect((await repo.getSize('s1'))!.priceDeltaMinor, 400);

      expect(await repo.tombstoneSize('s1', _now), 1);
      expect(await repo.getSize('s1'), isNull);
      expect(await repo.tombstoneSize('s1', _now), 0);
      expect(await _rowPresent('item_sizes', 's1'), isTrue);
    });

    test('item_variants create/get/list/update/tombstone', () async {
      await repo.createCategory(_category('c1'));
      await repo.createItem(_item('i1', 'c1'));
      await repo.createVariant(_variant('v1', 'i1'));

      expect((await repo.getVariant('v1'))!.menuItemId, 'i1');
      expect((await repo.listVariantsByItem('i1')).map((v) => v.id), ['v1']);

      expect(
        await repo.updateVariant(
          ItemVariantsCompanion(
            id: const Value('v1'),
            priceDeltaMinor: const Value(100),
            updatedAt: Value(_now),
          ),
        ),
        1,
      );
      expect((await repo.getVariant('v1'))!.priceDeltaMinor, 100);

      expect(await repo.tombstoneVariant('v1', _now), 1);
      expect(await repo.getVariant('v1'), isNull);
      expect(await repo.tombstoneVariant('v1', _now), 0);
      expect(await _rowPresent('item_variants', 'v1'), isTrue);
    });

    test('modifiers create/get/list/update/tombstone', () async {
      await repo.createCategory(_category('c1'));
      await repo.createItem(_item('i1', 'c1'));
      await repo.createModifier(_modifier('m1', 'i1'));

      final got = await repo.getModifier('m1');
      expect(got!.menuItemId, 'i1');
      expect(got.selectionType, 'multiple');
      expect((await repo.listModifiersByItem('i1')).map((m) => m.id), ['m1']);

      expect(
        await repo.updateModifier(
          ModifiersCompanion(
            id: const Value('m1'),
            isRequired: const Value(true),
            updatedAt: Value(_now),
          ),
        ),
        1,
      );
      expect((await repo.getModifier('m1'))!.isRequired, isTrue);

      expect(await repo.tombstoneModifier('m1', _now), 1);
      expect(await repo.getModifier('m1'), isNull);
      expect(await repo.tombstoneModifier('m1', _now), 0);
      expect(await _rowPresent('modifiers', 'm1'), isTrue);
    });

    test('modifier_options create/get/list/update/tombstone', () async {
      await repo.createCategory(_category('c1'));
      await repo.createItem(_item('i1', 'c1'));
      await repo.createModifier(_modifier('m1', 'i1'));
      await repo.createOption(_option('o1', 'm1', delta: 250));

      final got = await repo.getOption('o1');
      expect(got!.priceDeltaMinor, 250);
      expect(got.modifierId, 'm1');
      expect((await repo.listOptionsByModifier('m1')).map((o) => o.id), ['o1']);

      expect(
        await repo.updateOption(
          ModifierOptionsCompanion(
            id: const Value('o1'),
            priceDeltaMinor: const Value(300),
            updatedAt: Value(_now),
          ),
        ),
        1,
      );
      expect((await repo.getOption('o1'))!.priceDeltaMinor, 300);

      expect(await repo.tombstoneOption('o1', _now), 1);
      expect(await repo.getOption('o1'), isNull);
      expect(await repo.tombstoneOption('o1', _now), 0);
      expect(await _rowPresent('modifier_options', 'o1'), isTrue);
    });
  });

  group('Relationship constraints — FKs enforced (RF-030)', () {
    test('full chain round-trips and each FK resolves', () async {
      await seedChain();
      expect((await repo.getItem('i1'))!.menuCategoryId, 'c1');
      expect((await repo.getSize('s1'))!.menuItemId, 'i1');
      expect((await repo.getVariant('v1'))!.menuItemId, 'i1');
      expect((await repo.getModifier('m1'))!.menuItemId, 'i1');
      expect((await repo.getOption('o1'))!.modifierId, 'm1');
    });

    test('orphan rows are rejected by foreign keys', () async {
      await seedChain();
      // item -> missing category
      await expectLater(
        repo.createItem(_item('i9', 'no-cat')),
        throwsA(isA<SqliteException>()),
      );
      // size -> missing item
      await expectLater(
        repo.createSize(_size('s9', 'no-item')),
        throwsA(isA<SqliteException>()),
      );
      // variant -> missing item
      await expectLater(
        repo.createVariant(_variant('v9', 'no-item')),
        throwsA(isA<SqliteException>()),
      );
      // modifier -> missing item
      await expectLater(
        repo.createModifier(_modifier('m9', 'no-item')),
        throwsA(isA<SqliteException>()),
      );
      // option -> missing modifier
      await expectLater(
        repo.createOption(_option('o9', 'no-mod')),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group(
    'Tombstoned rows are live-only-excluded from update (RF-030, D-020)',
    () {
      test('update of a tombstoned row is a no-op (no resurrection)', () async {
        await repo.createCategory(_category('c1'));
        expect(await repo.tombstoneCategory('c1', _now), 1);

        // Updating a tombstoned row affects zero rows and never un-deletes it.
        final changed = await repo.updateCategory(
          MenuCategoriesCompanion(
            id: const Value('c1'),
            name: const Value('Resurrected?'),
            updatedAt: Value(_now),
          ),
        );
        expect(changed, 0);
        expect(await repo.getCategory('c1'), isNull); // still tombstoned
      });
    },
  );

  group('Tenant fields present on all six menu tables (RF-030, D-001)', () {
    test('non-null organization_id + restaurant_id, nullable branch_id', () {
      final tables = <TableInfo>[
        db.menuCategories,
        db.menuItems,
        db.itemSizes,
        db.itemVariants,
        db.modifiers,
        db.modifierOptions,
      ];
      for (final table in tables) {
        final byName = {for (final c in table.$columns) c.name: c};
        final where = table.actualTableName;
        expect(byName['organization_id']?.$nullable, isFalse, reason: where);
        expect(byName['restaurant_id']?.$nullable, isFalse, reason: where);
        expect(byName.containsKey('branch_id'), isTrue, reason: where);
        expect(byName['branch_id']?.$nullable, isTrue, reason: where);
      }
    });
  });
}
