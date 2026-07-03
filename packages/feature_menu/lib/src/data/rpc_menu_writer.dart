import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import '../models/menu_entity_type.dart';
import '../models/menu_scope.dart';
import '../models/menu_write_failure.dart';
import '../models/menu_write_result.dart';
import 'menu_writer.dart';

/// The RF-109 public menu RPC names. They are passed WITHOUT the `public.`
/// prefix: [SyncRpcTransport] (the Supabase impl) calls
/// `client.schema('public').rpc(<name>)` (RF-064), so `menu_upsert_item`
/// resolves to `public.menu_upsert_item`. The `app.*` schema stays unexposed.
class MenuRpcNames {
  static const upsertCategory = 'menu_upsert_category';
  static const upsertItem = 'menu_upsert_item';
  static const upsertSize = 'menu_upsert_size';
  static const upsertVariant = 'menu_upsert_variant';
  static const upsertModifier = 'menu_upsert_modifier';
  static const upsertModifierOption = 'menu_upsert_modifier_option';
  static const softDelete = 'menu_soft_delete';
}

/// Calls the RF-109 `public.menu_*` RPCs over the neutral [SyncRpcTransport].
///
/// Error mapping is the load-bearing part. RF-109 has TWO failure surfaces:
///  * role-denied -> RETURNED `{ok:false, error:'permission_denied'}` envelope;
///  * everything else (validation / scope / cross-org / immutable / not-found /
///    no-membership) -> RAISED SQLSTATE `42501` with a descriptive message.
/// The shared `classifyPostgrestCode` collapses ALL `42501` to "auth", which
/// would wrongly present validation errors as "access denied", so this writer
/// inspects the raised `42501` directly and surfaces its message as a
/// [MenuValidationRejected] (NOT a generic auth failure).
class RpcMenuWriter implements MenuWriter {
  const RpcMenuWriter(this._transport);

  final SyncRpcTransport _transport;

  Future<MenuWriteOutcome> _invoke(
    String function,
    Map<String, dynamic> params,
    MenuEntityType entity,
  ) async {
    try {
      final raw = await _transport.invoke(function, params);
      if (raw is! Map) return const Failure(MenuInvalidResponseFailure());
      final body = Map<String, dynamic>.from(raw);
      if (body['ok'] == true) {
        try {
          return Success(MenuWriteResult.fromOkEnvelope(body));
        } on FormatException {
          return const Failure(MenuInvalidResponseFailure());
        }
      }
      if (body['error'] == 'permission_denied') {
        return Failure(MenuPermissionDenied(entity));
      }
      return const Failure(MenuInvalidResponseFailure());
    } on SyncTransportException catch (e) {
      if (e.code == '42501') {
        // RF-109 raises validation/scope/not-found with a descriptive message.
        return Failure(MenuValidationRejected(e.message ?? ''));
      }
      if (e.kind == SyncTransportErrorKind.transient) {
        return Failure(MenuTransientFailure(e.message));
      }
      return Failure(MenuServerFailure(e.message));
    }
  }

  @override
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int displayOrder = 0,
    bool isActive = true,
  }) {
    return _invoke(MenuRpcNames.upsertCategory, {
      'p_organization_id': scope.organizationId,
      'p_restaurant_id': scope.restaurantId,
      'p_branch_id': scope.branchId,
      'p_id': id,
      'p_name': name,
      'p_display_order': displayOrder,
      'p_is_active': isActive,
    }, MenuEntityType.category);
  }

  @override
  Future<MenuWriteOutcome> upsertItem({
    required MenuScope scope,
    String? id,
    required String menuCategoryId,
    required String name,
    String? description,
    required int basePriceMinor,
    required String currencyCode,
    String? defaultStationId,
    int displayOrder = 0,
    bool isActive = true,
    String? imagePath,
    String? itemType,
    List<String> tags = const [],
    int? prepMinutes,
    String? sku,
    String? kitchenNote,
    Map<String, dynamic> attributes = const {},
  }) {
    return _invoke(MenuRpcNames.upsertItem, {
      'p_organization_id': scope.organizationId,
      'p_restaurant_id': scope.restaurantId,
      'p_branch_id': scope.branchId,
      'p_id': id,
      'p_menu_category_id': menuCategoryId,
      'p_name': name,
      'p_description': description,
      'p_base_price_minor': basePriceMinor,
      'p_currency_code': currencyCode,
      'p_default_station_id': defaultStationId,
      'p_display_order': displayOrder,
      'p_is_active': isActive,
      // null = clear/unset (the editor sends the item's full state). Empty
      // tags/attributes travel as null — one canonical "unset" wire shape
      // (matching the server-side normalization).
      'p_image_path': imagePath,
      'p_item_type': itemType,
      'p_tags': tags.isEmpty ? null : tags,
      'p_prep_minutes': prepMinutes,
      'p_sku': sku,
      'p_kitchen_note': kitchenNote,
      'p_attributes': attributes.isEmpty ? null : attributes,
    }, MenuEntityType.item);
  }

  @override
  Future<MenuWriteOutcome> upsertSize({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) {
    return _invoke(MenuRpcNames.upsertSize, {
      'p_organization_id': scope.organizationId,
      'p_restaurant_id': scope.restaurantId,
      'p_branch_id': scope.branchId,
      'p_id': id,
      'p_menu_item_id': menuItemId,
      'p_name': name,
      'p_price_delta_minor': priceDeltaMinor,
      'p_display_order': displayOrder,
      'p_is_active': isActive,
    }, MenuEntityType.size);
  }

  @override
  Future<MenuWriteOutcome> upsertVariant({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) {
    return _invoke(MenuRpcNames.upsertVariant, {
      'p_organization_id': scope.organizationId,
      'p_restaurant_id': scope.restaurantId,
      'p_branch_id': scope.branchId,
      'p_id': id,
      'p_menu_item_id': menuItemId,
      'p_name': name,
      'p_price_delta_minor': priceDeltaMinor,
      'p_display_order': displayOrder,
      'p_is_active': isActive,
    }, MenuEntityType.variant);
  }

  @override
  Future<MenuWriteOutcome> upsertModifier({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    String selectionType = 'single',
    int minSelect = 0,
    int? maxSelect,
    bool isRequired = false,
    int displayOrder = 0,
    bool isActive = true,
  }) {
    return _invoke(MenuRpcNames.upsertModifier, {
      'p_organization_id': scope.organizationId,
      'p_restaurant_id': scope.restaurantId,
      'p_branch_id': scope.branchId,
      'p_id': id,
      'p_menu_item_id': menuItemId,
      'p_name': name,
      'p_selection_type': selectionType,
      'p_min_select': minSelect,
      'p_max_select': maxSelect,
      'p_is_required': isRequired,
      'p_display_order': displayOrder,
      'p_is_active': isActive,
    }, MenuEntityType.modifier);
  }

  @override
  Future<MenuWriteOutcome> upsertModifierOption({
    required MenuScope scope,
    String? id,
    required String modifierId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) {
    return _invoke(MenuRpcNames.upsertModifierOption, {
      'p_organization_id': scope.organizationId,
      'p_restaurant_id': scope.restaurantId,
      'p_branch_id': scope.branchId,
      'p_id': id,
      'p_modifier_id': modifierId,
      'p_name': name,
      'p_price_delta_minor': priceDeltaMinor,
      'p_display_order': displayOrder,
      'p_is_active': isActive,
    }, MenuEntityType.modifierOption);
  }

  @override
  Future<MenuWriteOutcome> softDelete({
    required String organizationId,
    required MenuEntityType entity,
    required String id,
  }) {
    return _invoke(MenuRpcNames.softDelete, {
      'p_organization_id': organizationId,
      'p_entity': entity.wire,
      'p_id': id,
    }, entity);
  }
}
