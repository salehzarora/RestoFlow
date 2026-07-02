import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

/// A hand-written fake transport (the repo convention: fake the SyncRpcTransport
/// seam, never the Supabase SDK). Records the last call and returns/throws a
/// canned value.
class _FakeTransport implements SyncRpcTransport {
  Object? returnValue;
  SyncTransportException? throwValue;
  String? lastFunction;
  Map<String, dynamic>? lastParams;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    lastFunction = function;
    lastParams = params;
    if (throwValue != null) throw throwValue!;
    return returnValue;
  }
}

const _scope = MenuScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  currencyCode: 'ILS',
);

/// The verbatim `public.list_menu` ok-envelope shape (mvp_menu_real_access):
/// every row carries the tenant keys; inactive rows are INCLUDED (management
/// view); tombstones never leave the server.
Map<String, Object?> _okEnvelope() => {
  'ok': true,
  'entity': 'menu',
  'currency_code': 'ILS',
  'categories': [
    {
      'id': 'cat-1',
      'organization_id': 'org-1',
      'restaurant_id': 'rest-1',
      'branch_id': null,
      'name': 'Mains',
      'display_order': 0,
      'is_active': true,
    },
  ],
  'items': [
    {
      'id': 'item-1',
      'organization_id': 'org-1',
      'restaurant_id': 'rest-1',
      'branch_id': 'branch-1',
      'menu_category_id': 'cat-1',
      'name': 'Shakshuka',
      'description': null,
      'base_price_minor': 4200,
      'currency_code': 'ILS',
      'default_station_id': null,
      'display_order': 0,
      'is_active': true,
    },
    {
      'id': 'item-2',
      'organization_id': 'org-1',
      'restaurant_id': 'rest-1',
      'branch_id': null,
      'menu_category_id': 'cat-1',
      'name': 'Retired special',
      'description': 'disabled, still managed',
      'base_price_minor': 990,
      'currency_code': 'ILS',
      'default_station_id': null,
      'display_order': 1,
      'is_active': false,
    },
  ],
  'sizes': [
    {
      'id': 'size-1',
      'organization_id': 'org-1',
      'restaurant_id': 'rest-1',
      'branch_id': null,
      'menu_item_id': 'item-1',
      'name': 'Large',
      'price_delta_minor': 600,
      'display_order': 0,
      'is_active': true,
    },
  ],
  'variants': <Object?>[],
  'modifiers': [
    {
      'id': 'mod-1',
      'organization_id': 'org-1',
      'restaurant_id': 'rest-1',
      'branch_id': null,
      'menu_item_id': 'item-1',
      'name': 'Extras',
      'selection_type': 'multiple',
      'min_select': 0,
      'max_select': 3,
      'is_required': false,
      'display_order': 0,
      'is_active': true,
    },
  ],
  'modifier_options': [
    {
      'id': 'opt-1',
      'organization_id': 'org-1',
      'restaurant_id': 'rest-1',
      'branch_id': null,
      'modifier_id': 'mod-1',
      'name': 'Feta',
      'price_delta_minor': 300,
      'display_order': 0,
      'is_active': true,
    },
  ],
  'server_ts': '2026-07-03T10:00:00Z',
};

void main() {
  test('calls public.list_menu with the exact scope params', () async {
    final transport = _FakeTransport()..returnValue = _okEnvelope();
    final source = RpcMenuReadSource(transport);

    await source.load(_scope);

    expect(transport.lastFunction, 'list_menu');
    expect(transport.lastParams, {
      'p_organization_id': 'org-1',
      'p_restaurant_id': 'rest-1',
      'p_branch_id': 'branch-1',
    });
  });

  test(
    'parses the full tree — inactive rows INCLUDED, minor-unit money',
    () async {
      final transport = _FakeTransport()..returnValue = _okEnvelope();
      final snapshot = await RpcMenuReadSource(transport).load(_scope);

      expect(snapshot.categories.single.name, 'Mains');
      expect(snapshot.items, hasLength(2));
      final disabled = snapshot.items.singleWhere((i) => i.id == 'item-2');
      expect(disabled.isActive, isFalse);
      expect(disabled.basePriceMinor, 990);
      expect(snapshot.sizesForItem('item-1').single.priceDeltaMinor, 600);
      expect(snapshot.modifiersForItem('item-1').single.maxSelect, 3);
      expect(snapshot.optionsForModifier('mod-1').single.name, 'Feta');
      expect(snapshot.variants, isEmpty);
    },
  );

  test('a permission_denied envelope throws (never demo data)', () async {
    final transport = _FakeTransport()
      ..returnValue = const {
        'ok': false,
        'error': 'permission_denied',
        'entity': 'menu',
      };
    expect(
      () => RpcMenuReadSource(transport).load(_scope),
      throwsA(isA<MenuReadException>()),
    );
  });

  test('a raised 42501 (structural denial) throws', () async {
    final transport = _FakeTransport()
      ..throwValue = const SyncTransportException(
        SyncTransportErrorKind.auth,
        code: '42501',
        message: 'menu: no covering membership',
      );
    expect(
      () => RpcMenuReadSource(transport).load(_scope),
      throwsA(isA<MenuReadException>()),
    );
  });

  test(
    'a transient transport error throws (retryable load-error state)',
    () async {
      final transport = _FakeTransport()
        ..throwValue = const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: '503',
          message: 'unavailable',
        );
      expect(
        () => RpcMenuReadSource(transport).load(_scope),
        throwsA(isA<MenuReadException>()),
      );
    },
  );

  test('a malformed row throws instead of a partial menu', () async {
    final envelope = _okEnvelope();
    envelope['items'] = [
      {'id': 'item-x'}, // missing every required field
    ];
    final transport = _FakeTransport()..returnValue = envelope;
    expect(
      () => RpcMenuReadSource(transport).load(_scope),
      throwsA(isA<MenuReadException>()),
    );
  });
}
