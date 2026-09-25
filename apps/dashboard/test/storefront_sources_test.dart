import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_sources.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

/// STOREFRONT-PUBLISH-001 — the editor's read-only lookups: the restaurant's
/// branches from `list_org_structure` (ONLY this restaurant's), and the
/// candidate originals (the current receipt logo; menu items' image keys),
/// each fail-soft and never inventing an option.
const _org = '11111111-1111-4111-8111-111111111111';
const _rest = '22222222-2222-4222-8222-222222222222';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.reply);

  final Object? reply;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    final r = reply;
    if (r is SyncTransportException) throw r;
    return r;
  }
}

class _FakeLogoRepo implements RestaurantLogoRepository {
  _FakeLogoRepo(this.settings, {this.throws = false});

  final RestaurantLogoSettings? settings;
  final bool throws;

  @override
  Future<RestaurantLogoSettings?> read() async {
    if (throws) throw StateError('boom');
    return settings;
  }

  @override
  Future<RestaurantLogoWriteResult> save({
    required String? path,
    required bool enabled,
    required int expectedVersion,
  }) => throw StateError('never written here');
}

class _FakeMenu implements MenuReadSource {
  _FakeMenu(this.items, {this.throws = false});

  final List<MenuItem> items;
  final bool throws;
  final List<MenuScope> scopes = [];

  @override
  Future<MenuSnapshot> load(MenuScope scope) async {
    scopes.add(scope);
    if (throws) throw const MenuReadException('rejected');
    return MenuSnapshot(items: items);
  }
}

MenuItem _item(String id, String name, String? image, {DateTime? deleted}) =>
    MenuItem(
      id: id,
      organizationId: _org,
      restaurantId: _rest,
      branchId: null,
      menuCategoryId: 'cat',
      name: name,
      description: null,
      basePriceMinor: 1000,
      currencyCode: 'ILS',
      defaultStationId: null,
      displayOrder: 0,
      isActive: true,
      imagePath: image,
      deletedAt: deleted,
    );

const _scope = MenuScope(
  organizationId: _org,
  restaurantId: _rest,
  currencyCode: 'ILS',
);

void main() {
  group('SupabaseStorefrontBranchSource', () {
    SupabaseStorefrontBranchSource source(_FakeTransport t) =>
        SupabaseStorefrontBranchSource(
          transport: t,
          organizationId: _org,
          restaurantId: _rest,
        );

    test('returns ONLY this restaurant\'s branches (with timezones)', () async {
      final t = _FakeTransport({
        'ok': true,
        'restaurants': [
          {
            'id': 'other',
            'branches': [
              {'id': 'x1', 'name': 'Elsewhere'},
            ],
          },
          {
            'id': _rest.toUpperCase(),
            'branches': [
              {'id': 'b1', 'name': 'Downtown', 'timezone': 'Asia/Jerusalem'},
              {'id': 'b2', 'name': '', 'timezone': ''},
              {'name': 'no id'},
            ],
          },
        ],
      });
      final branches = await source(t).list();
      expect(t.calls.single.$1, 'list_org_structure');
      expect(t.calls.single.$2, {'p_organization_id': _org});
      expect([for (final b in branches!) b.id], ['b1', 'b2']);
      expect(branches[0].timezone, 'Asia/Jerusalem');
      expect(branches[1].name, 'b2', reason: 'blank name falls back to id');
      expect(branches[1].timezone, isNull);
      // No restaurant zone in this payload: nothing is invented.
      expect(branches[1].effectiveTimezone, isNull);
    });

    test('C11 / DASH-3: carries each branch\'s status from the SAME read '
        '(no new data path); a non-active branch is suspended', () async {
      final t = _FakeTransport({
        'ok': true,
        'restaurants': [
          {
            'id': _rest,
            'status': 'active',
            'branches': [
              {'id': 'b1', 'name': 'Downtown', 'status': 'active'},
              {'id': 'b2', 'name': 'Harbor', 'status': 'suspended'},
              {'id': 'b3', 'name': 'Old read'},
            ],
          },
        ],
      });
      final branches = (await source(t).list())!;
      expect(t.calls.single.$1, 'list_org_structure');
      expect(
        [for (final b in branches) b.status],
        ['active', 'suspended', null],
      );
      expect([for (final b in branches) b.isSuspended], [false, true, false]);
    });

    test('the effective zone follows the server rule: the branch\'s own, '
        'else the restaurant\'s (same payload)', () async {
      final t = _FakeTransport({
        'ok': true,
        'restaurants': [
          {
            'id': _rest,
            'timezone': 'Asia/Jerusalem',
            'branches': [
              {'id': 'b1', 'name': 'London', 'timezone': 'Europe/London'},
              {'id': 'b2', 'name': 'Harbor', 'timezone': null},
            ],
          },
        ],
      });
      final branches = (await source(t).list())!;
      expect(branches[0].timezone, 'Europe/London');
      expect(branches[0].effectiveTimezone, 'Europe/London');
      expect(branches[1].timezone, isNull);
      expect(branches[1].restaurantTimezone, 'Asia/Jerusalem');
      expect(branches[1].effectiveTimezone, 'Asia/Jerusalem');
    });

    test('fail-soft: transport error / refusal / unknown restaurant', () async {
      for (final reply in <Object?>[
        const SyncTransportException(SyncTransportErrorKind.transient),
        {'ok': false, 'error': 'permission_denied'},
        {'ok': true, 'restaurants': <Object?>[]},
        'not a map',
      ]) {
        expect(await source(_FakeTransport(reply)).list(), isNull);
      }
    });
  });

  group('DashboardStorefrontSourceCatalog', () {
    test('the receipt logo key + menu originals (deduped, by name)', () async {
      final menu = _FakeMenu([
        _item('i2', 'Pizza', 'k/pizza.jpg'),
        _item('i1', 'Bagel', 'k/bagel.jpg'),
        _item('i3', 'Soup', null),
        _item('i4', 'Old', 'k/old.jpg', deleted: DateTime.utc(2026)),
        _item('i5', 'Pizza copy', 'k/pizza.jpg'),
      ]);
      final options = await DashboardStorefrontSourceCatalog(
        logoRepository: _FakeLogoRepo(
          const RestaurantLogoSettings(
            path: 'org/rest/logo/a.png',
            enabled: false,
            version: 2,
          ),
        ),
        menuReadSource: menu,
        menuScope: _scope,
      ).load();
      // A disabled receipt logo is still the CURRENT logo (a valid source).
      expect(options.receiptLogoKey, 'org/rest/logo/a.png');
      expect(options.receiptLogoUnavailable, isFalse);
      expect(
        [for (final m in options.menuImages) m.imageKey],
        ['k/bagel.jpg', 'k/pizza.jpg'],
      );
      expect(options.menuImagesUnavailable, isFalse);
      expect(menu.scopes.single, _scope);
    });

    test('no logo is not the same as an unreadable logo', () async {
      final none = await DashboardStorefrontSourceCatalog(
        logoRepository: _FakeLogoRepo(
          const RestaurantLogoSettings(path: null, enabled: false, version: 0),
        ),
      ).load();
      expect(none.receiptLogoKey, isNull);
      expect(none.receiptLogoUnavailable, isFalse);

      for (final repo in [
        _FakeLogoRepo(null),
        _FakeLogoRepo(null, throws: true),
        null,
      ]) {
        final r = await DashboardStorefrontSourceCatalog(
          logoRepository: repo,
        ).load();
        expect(r.receiptLogoKey, isNull);
        expect(r.receiptLogoUnavailable, isTrue);
      }
    });

    test('a failed / unwired menu read is flagged, never faked', () async {
      final failed = await DashboardStorefrontSourceCatalog(
        menuReadSource: _FakeMenu(const [], throws: true),
        menuScope: _scope,
      ).load();
      expect(failed.menuImages, isEmpty);
      expect(failed.menuImagesUnavailable, isTrue);
      final unwired = await const DashboardStorefrontSourceCatalog().load();
      expect(unwired.menuImagesUnavailable, isTrue);
    });
  });
}
