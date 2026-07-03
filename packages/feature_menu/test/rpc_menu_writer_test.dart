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
  currencyCode: 'USD',
);

MenuWriteResult? _success(MenuWriteOutcome o) =>
    o.fold((value) => value, (_) => null);
MenuWriteFailure? _failure(MenuWriteOutcome o) =>
    o.fold((_) => null, (failure) => failure);

void main() {
  group('RpcMenuWriter — RPC names + params', () {
    test(
      'upsertItem (create) calls menu_upsert_item with p_id null + minor money',
      () async {
        final transport = _FakeTransport()
          ..returnValue = const {
            'ok': true,
            'entity': 'menu_item',
            'id': 'item-9',
            'action': 'created',
          };
        final writer = RpcMenuWriter(transport);

        final outcome = await writer.upsertItem(
          scope: _scope,
          id: null,
          menuCategoryId: 'cat-1',
          name: 'Espresso',
          basePriceMinor: 350,
          currencyCode: 'USD',
        );

        expect(transport.lastFunction, 'menu_upsert_item');
        expect(transport.lastParams!['p_id'], isNull);
        expect(transport.lastParams!['p_organization_id'], 'org-1');
        expect(transport.lastParams!['p_restaurant_id'], 'rest-1');
        expect(transport.lastParams!['p_branch_id'], 'branch-1');
        expect(transport.lastParams!['p_base_price_minor'], 350);
        expect(transport.lastParams!['p_currency_code'], 'USD');
        // Full-state contract: an omitted image sends p_image_path null
        // (the server treats null as clear/unset).
        expect(transport.lastParams!.containsKey('p_image_path'), isTrue);
        expect(transport.lastParams!['p_image_path'], isNull);
        // Rich attributes (menu/media sprint): unset fields travel as null —
        // one canonical "unset" wire shape (empty tags/attributes => null).
        for (final key in [
          'p_item_type',
          'p_tags',
          'p_prep_minutes',
          'p_sku',
          'p_kitchen_note',
          'p_attributes',
        ]) {
          expect(transport.lastParams!.containsKey(key), isTrue);
          expect(transport.lastParams![key], isNull);
        }

        final result = _success(outcome);
        expect(result, isNotNull);
        expect(result!.entity, MenuEntityType.item);
        expect(result.id, 'item-9');
        expect(result.action, MenuWriteAction.created);
      },
    );

    test('upsertItem passes p_image_path when an image is set', () async {
      final transport = _FakeTransport()
        ..returnValue = const {
          'ok': true,
          'entity': 'menu_item',
          'id': 'item-9',
          'action': 'updated',
        };
      final writer = RpcMenuWriter(transport);

      await writer.upsertItem(
        scope: _scope,
        id: 'item-9',
        menuCategoryId: 'cat-1',
        name: 'Espresso',
        basePriceMinor: 350,
        currencyCode: 'USD',
        imagePath: 'org-1/rest-1/branch-1/menu_item/item-9/img-1.png',
      );

      expect(
        transport.lastParams!['p_image_path'],
        'org-1/rest-1/branch-1/menu_item/item-9/img-1.png',
      );
    });

    test('upsertItem passes the rich attribute p_* params when set', () async {
      final transport = _FakeTransport()
        ..returnValue = const {
          'ok': true,
          'entity': 'menu_item',
          'id': 'item-9',
          'action': 'updated',
        };
      final writer = RpcMenuWriter(transport);

      await writer.upsertItem(
        scope: _scope,
        id: 'item-9',
        menuCategoryId: 'cat-1',
        name: 'Burger',
        basePriceMinor: 4200,
        currencyCode: 'ILS',
        itemType: 'food',
        tags: const ['spicy', 'popular'],
        prepMinutes: 12,
        sku: 'BRG-01',
        kitchenNote: 'No onions.',
        attributes: const {
          'portion_label': 'Single',
          'patty_count': 1,
          'patty_weight_grams': 160,
        },
      );

      expect(transport.lastParams!['p_item_type'], 'food');
      expect(transport.lastParams!['p_tags'], ['spicy', 'popular']);
      expect(transport.lastParams!['p_prep_minutes'], 12);
      expect(transport.lastParams!['p_sku'], 'BRG-01');
      expect(transport.lastParams!['p_kitchen_note'], 'No onions.');
      expect(transport.lastParams!['p_attributes'], {
        'portion_label': 'Single',
        'patty_count': 1,
        'patty_weight_grams': 160,
      });
    });

    test('upsertCategory (update) passes the existing id', () async {
      final transport = _FakeTransport()
        ..returnValue = const {
          'ok': true,
          'entity': 'menu_category',
          'id': 'cat-1',
          'action': 'updated',
        };
      final writer = RpcMenuWriter(transport);

      final outcome = await writer.upsertCategory(
        scope: _scope,
        id: 'cat-1',
        name: 'Hot Drinks',
      );

      expect(transport.lastFunction, 'menu_upsert_category');
      expect(transport.lastParams!['p_id'], 'cat-1');
      expect(_success(outcome)!.action, MenuWriteAction.updated);
    });

    test(
      'softDelete calls menu_soft_delete with the entity wire key',
      () async {
        final transport = _FakeTransport()
          ..returnValue = const {
            'ok': true,
            'entity': 'menu_item',
            'id': 'item-1',
            'action': 'soft_deleted',
          };
        final writer = RpcMenuWriter(transport);

        final outcome = await writer.softDelete(
          organizationId: 'org-1',
          entity: MenuEntityType.item,
          id: 'item-1',
        );

        expect(transport.lastFunction, 'menu_soft_delete');
        expect(transport.lastParams!['p_entity'], 'menu_item');
        expect(transport.lastParams!['p_id'], 'item-1');
        expect(_success(outcome)!.action, MenuWriteAction.softDeleted);
      },
    );

    test('child upserts pass the correct parent + signed delta', () async {
      final transport = _FakeTransport()
        ..returnValue = const {
          'ok': true,
          'entity': 'item_size',
          'id': 's',
          'action': 'created',
        };
      final writer = RpcMenuWriter(transport);

      await writer.upsertSize(
        scope: _scope,
        menuItemId: 'item-1',
        name: 'Large',
        priceDeltaMinor: -50,
      );
      expect(transport.lastFunction, 'menu_upsert_size');
      expect(transport.lastParams!['p_menu_item_id'], 'item-1');
      expect(transport.lastParams!['p_price_delta_minor'], -50);

      transport.returnValue = const {
        'ok': true,
        'entity': 'modifier_option',
        'id': 'o',
        'action': 'created',
      };
      await writer.upsertModifierOption(
        scope: _scope,
        modifierId: 'mod-1',
        name: 'Caramel',
        priceDeltaMinor: 90,
      );
      expect(transport.lastFunction, 'menu_upsert_modifier_option');
      expect(transport.lastParams!['p_modifier_id'], 'mod-1');
    });
  });

  group('RpcMenuWriter — error mapping (the load-bearing part)', () {
    test(
      'returned {ok:false, permission_denied} -> MenuPermissionDenied',
      () async {
        final transport = _FakeTransport()
          ..returnValue = const {
            'ok': false,
            'error': 'permission_denied',
            'entity': 'menu_item',
          };
        final writer = RpcMenuWriter(transport);

        final failure = _failure(
          await writer.upsertItem(
            scope: _scope,
            menuCategoryId: 'cat-1',
            name: 'X',
            basePriceMinor: 100,
            currencyCode: 'USD',
          ),
        );
        expect(failure, isA<MenuPermissionDenied>());
        expect((failure! as MenuPermissionDenied).entity, MenuEntityType.item);
      },
    );

    test(
      'RAISED 42501 -> MenuValidationRejected with the message (NOT a generic auth denial)',
      () async {
        final transport = _FakeTransport()
          ..throwValue = const SyncTransportException(
            SyncTransportErrorKind
                .auth, // classifyPostgrestCode collapses 42501 -> auth
            code: '42501',
            message: 'name is required',
          );
        final writer = RpcMenuWriter(transport);

        final failure = _failure(
          await writer.upsertCategory(scope: _scope, name: ''),
        );
        expect(failure, isA<MenuValidationRejected>());
        expect(
          (failure! as MenuValidationRejected).message,
          'name is required',
        );
      },
    );

    test('transient transport error -> MenuTransientFailure', () async {
      final transport = _FakeTransport()
        ..throwValue = const SyncTransportException(
          SyncTransportErrorKind.transient,
          message: 'timeout',
        );
      final writer = RpcMenuWriter(transport);

      final failure = _failure(
        await writer.upsertCategory(scope: _scope, name: 'X'),
      );
      expect(failure, isA<MenuTransientFailure>());
    });

    test(
      'non-transient server error (other code) -> MenuServerFailure',
      () async {
        final transport = _FakeTransport()
          ..throwValue = const SyncTransportException(
            SyncTransportErrorKind.server,
            code: 'PGRST000',
            message: 'boom',
          );
        final writer = RpcMenuWriter(transport);

        final failure = _failure(
          await writer.upsertCategory(scope: _scope, name: 'X'),
        );
        expect(failure, isA<MenuServerFailure>());
      },
    );

    test('malformed body (not a Map) -> MenuInvalidResponseFailure', () async {
      final transport = _FakeTransport()..returnValue = 'oops';
      final writer = RpcMenuWriter(transport);

      final failure = _failure(
        await writer.upsertCategory(scope: _scope, name: 'X'),
      );
      expect(failure, isA<MenuInvalidResponseFailure>());
    });
  });
}
