import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_featured_items.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

const org = '10000000-0000-0000-0000-000000000001';
const restaurant = '20000000-0000-0000-0000-000000000001';
const branch = '30000000-0000-0000-0000-000000000001';
const otherBranch = '30000000-0000-0000-0000-000000000002';
const categoryId = '40000000-0000-0000-0000-000000000001';
String itemId(int n) =>
    '50000000-0000-0000-0000-${n.toRadixString(16).padLeft(12, '0')}';

MenuCategory category({
  String id = categoryId,
  String? branchId,
  bool active = true,
  String organization = org,
}) => MenuCategory(
  id: id,
  organizationId: organization,
  restaurantId: restaurant,
  branchId: branchId,
  name: 'Stored category',
  displayOrder: 0,
  isActive: active,
);
MenuItem item(
  int n, {
  String? branchId,
  String category = categoryId,
  bool active = true,
  String organization = org,
  DateTime? deleted,
  String? image,
  String? availability,
}) => MenuItem(
  id: itemId(n),
  organizationId: organization,
  restaurantId: restaurant,
  branchId: branchId,
  menuCategoryId: category,
  name: 'Stored product $n',
  description: null,
  basePriceMinor: 1234,
  currencyCode: 'ILS',
  defaultStationId: null,
  displayOrder: n,
  isActive: active,
  deletedAt: deleted,
  imagePath: image,
  availability: availability,
);

class CatalogRead implements MenuReadSource {
  CatalogRead(this.snapshot);
  final MenuSnapshot snapshot;
  final List<MenuScope> calls = [];
  bool fail = false;
  @override
  Future<MenuSnapshot> load(MenuScope scope) async {
    calls.add(scope);
    if (fail) throw StateError('synthetic offline');
    return snapshot;
  }
}

class FeaturedTransport implements SyncRpcTransport {
  FeaturedTransport(this.responses, {this.readResponse});
  final List<Object?> responses;
  final Object? readResponse;
  final List<Map<String, dynamic>> calls = [];
  int reads = 0;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'get_restaurant_storefront_profile') {
      reads++;
      return readResponse;
    }
    expect(function, 'set_restaurant_storefront_featured_items');
    calls.add(params);
    final response = responses[calls.length - 1];
    if (response is SyncTransportException) throw response;
    return response;
  }
}

Map<String, Object?> success({bool replay = false}) => {
  'ok': true,
  'entity': 'restaurant_storefront_profile',
  'restaurant_id': restaurant,
  'version': 4,
  'slug': 'synthetic-featured',
  'is_published': false,
  'idempotent_replay': replay,
};
SupabaseStorefrontProfileRepository repository(FeaturedTransport transport) =>
    SupabaseStorefrontProfileRepository(
      transport: transport,
      organizationId: org,
      restaurantId: restaurant,
      nonce: () => 7,
    );

void main() {
  test('selection validates bound/types and semantic UUID aliases', () {
    expect(StorefrontProfile.isValidFeaturedItemIds([]), isTrue);
    expect(
      StorefrontProfile.isValidFeaturedItemIds(List.generate(12, itemId)),
      isTrue,
    );
    for (final invalid in [
      null,
      {},
      [null],
      [[]],
      [1],
      [itemId(10), itemId(10).toUpperCase()],
      [itemId(1) + '\n'],
      List.generate(13, itemId),
    ]) {
      expect(
        StorefrontProfile.isValidFeaturedItemIds(invalid),
        isFalse,
        reason: '$invalid',
      );
    }
  });

  test(
    'complete saved-branch catalog includes no-photo/shared-photo/sold-out products',
    () async {
      final source = CatalogRead(
        MenuSnapshot(
          categories: [category()],
          items: [
            item(2, image: 'shared'),
            item(1),
            item(3, image: 'shared', availability: 'unavailable'),
          ],
        ),
      );
      final catalog = DashboardStorefrontFeaturedCatalog(
        menuReadSource: source,
        organizationId: org,
        restaurantId: restaurant,
        currencyCode: 'ILS',
      );
      final options = await catalog.load(branch);
      expect(source.calls.single.branchId, branch);
      expect(source.calls.single.organizationId, org);
      expect(source.calls.single.restaurantId, restaurant);
      expect(options!.map((option) => option.id), [
        itemId(1),
        itemId(2),
        itemId(3),
      ]);
    },
  );

  test(
    'private management rows require active same-scope parent AND item',
    () async {
      final source = CatalogRead(
        MenuSnapshot(
          categories: [
            category(),
            category(id: itemId(80), active: false),
            category(id: itemId(81), branchId: otherBranch),
          ],
          items: [
            item(1),
            item(2, branchId: branch),
            item(3, branchId: otherBranch),
            item(4, active: false),
            item(5, deleted: DateTime.utc(2026)),
            item(6, organization: itemId(90)),
            item(7, category: itemId(80)),
            item(8, category: itemId(81)),
            item(9, category: itemId(82)),
          ],
        ),
      );
      final catalog = DashboardStorefrontFeaturedCatalog(
        menuReadSource: source,
        organizationId: org,
        restaurantId: restaurant,
        currencyCode: 'ILS',
      );
      expect((await catalog.load(branch))!.map((option) => option.id), [
        itemId(1),
        itemId(2),
      ]);
      expect(await catalog.load(''), isNull);
      expect(source.calls, hasLength(1), reason: 'no null/global branch read');
    },
  );

  test(
    'malformed duplicate categories/items and failed reads are unavailable, not guessed',
    () async {
      for (final snapshot in [
        MenuSnapshot(categories: [category(), category()], items: [item(1)]),
        MenuSnapshot(
          categories: [category(id: 'bad')],
          items: [item(1, category: 'bad')],
        ),
        MenuSnapshot(categories: [category()], items: [item(1), item(1)]),
        MenuSnapshot(
          categories: [category(id: '$categoryId\n')],
          items: [item(1, category: '$categoryId\n')],
        ),
      ]) {
        final source = CatalogRead(snapshot);
        expect(
          await DashboardStorefrontFeaturedCatalog(
            menuReadSource: source,
            organizationId: org,
            restaurantId: restaurant,
            currencyCode: 'ILS',
          ).load(branch),
          isNull,
        );
      }
      final source = CatalogRead(const MenuSnapshot())..fail = true;
      expect(
        await DashboardStorefrontFeaturedCatalog(
          menuReadSource: source,
          organizationId: org,
          restaurantId: restaurant,
          currencyCode: 'ILS',
        ).load(branch),
        isNull,
      );
    },
  );

  test(
    'one narrow request freezes raw list and does not route generic/Home writers',
    () async {
      final transport = FeaturedTransport([success()]);
      final raw = [itemId(10).toUpperCase(), itemId(1)];
      final future = repository(
        transport,
      ).saveFeaturedItems(expectedVersion: 3, itemIds: raw);
      raw.clear();
      final result = await future;
      expect(result.status, StorefrontWriteStatus.ok);
      expect(transport.calls, hasLength(1));
      final call = transport.calls.single;
      expect(call['p_organization_id'], org);
      expect(call['p_restaurant_id'], restaurant);
      expect(call['p_expected_version'], 3);
      expect(call['p_patch'], {
        'featured_item_ids': [itemId(10).toUpperCase(), itemId(1)],
      });
      expect(
        () => ((call['p_patch'] as Map)['featured_item_ids'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('explicit retry preserves exact raw body/version/identity', () async {
    final transport = FeaturedTransport([success(), success(replay: true)]);
    final repo = repository(transport);
    final first = await repo.saveFeaturedItems(
      expectedVersion: 3,
      itemIds: [itemId(1)],
    );
    final second = await repo.saveFeaturedItems(
      expectedVersion: 3,
      itemIds: [itemId(1)],
      requestId: first.requestId,
    );
    expect(second.idempotentReplay, isTrue);
    expect(transport.calls[1], transport.calls[0]);
  });

  test(
    'unknown or malformed result causes one readback and NO POST retry or inferred commit',
    () async {
      for (final response in [
        const SyncTransportException(SyncTransportErrorKind.transient),
        {'ok': true},
        {...success(), 'restaurant_id': org},
        {...success(), 'version': 99},
        {...success(), 'version': 4.0},
        {...success(), 'is_published': 'false'},
        {...success(), 'idempotent_replay': 1},
        {...success(), 'slug': ''},
      ]) {
        final transport = FeaturedTransport(
          [response],
          readResponse: {'ok': false, 'error': 'not_found'},
        );
        final result = await repository(
          transport,
        ).saveFeaturedItems(expectedVersion: 3, itemIds: [itemId(1)]);
        expect(result.status, StorefrontWriteStatus.uncertain);
        expect(result.requestId, isNotNull);
        expect(transport.calls, hasLength(1));
        expect(transport.reads, 1);
      }
    },
  );

  test(
    'invalid selection/missing profile refuses locally without a wire request',
    () async {
      final transport = FeaturedTransport([]);
      for (final invalid in [
        [itemId(1), itemId(1)],
        ['bad'],
        List.generate(13, itemId),
      ]) {
        final result = await repository(
          transport,
        ).saveFeaturedItems(expectedVersion: 3, itemIds: invalid);
        expect(result.refusedLocally, isTrue);
      }
      expect(
        (await repository(
          transport,
        ).saveFeaturedItems(expectedVersion: 0, itemIds: [])).refusedLocally,
        isTrue,
      );
      expect(transport.calls, isEmpty);
    },
  );
}
