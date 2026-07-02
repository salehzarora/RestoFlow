import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import '../models/item_size.dart';
import '../models/item_variant.dart';
import '../models/menu_category.dart';
import '../models/menu_item.dart';
import '../models/menu_snapshot.dart';
import '../models/menu_scope.dart';
import '../models/modifier.dart';
import '../models/modifier_option.dart';
import 'menu_read_source.dart';

/// A failed real menu read. [menuSnapshotProvider] surfaces it as the screen's
/// honest load-error state (retry re-invokes the RPC) — never demo data.
class MenuReadException implements Exception {
  const MenuReadException(this.message);
  final String message;

  @override
  String toString() => 'MenuReadException: $message';
}

/// The REAL menu read (sprint): `public.list_menu` over the authenticated
/// dashboard transport.
///
/// `list_menu` is the manager+ management read added alongside the GUC-free
/// `app.menu_guard` fix: it returns the full non-deleted menu tree for the
/// scope INCLUDING `is_active = false` rows (the management view must show
/// disabled entries), with the scope's effective `currency_code`. Tombstones
/// never leave the server. Any failure — permission_denied envelope, raised
/// 42501, transport error, malformed body — throws [MenuReadException]
/// (fail-closed: the surface shows its load-error state, never a fake menu).
class RpcMenuReadSource implements MenuReadSource {
  const RpcMenuReadSource(this._transport);

  final SyncRpcTransport _transport;

  /// The public wrapper name (resolves to `public.list_menu`, RF-064 style).
  static const String rpcName = 'list_menu';

  @override
  Future<MenuSnapshot> load(MenuScope scope) async {
    final Object? raw;
    try {
      raw = await _transport.invoke(rpcName, <String, dynamic>{
        'p_organization_id': scope.organizationId,
        'p_restaurant_id': scope.restaurantId,
        'p_branch_id': scope.branchId,
      });
    } on SyncTransportException catch (e) {
      throw MenuReadException('list_menu transport failure (${e.kind.name})');
    }
    if (raw is! Map || raw['ok'] != true) {
      throw const MenuReadException('list_menu rejected');
    }
    final body = Map<String, dynamic>.from(raw);
    try {
      return MenuSnapshot(
        categories: _rows(body, 'categories', MenuCategory.fromJson),
        items: _rows(body, 'items', MenuItem.fromJson),
        sizes: _rows(body, 'sizes', ItemSize.fromJson),
        variants: _rows(body, 'variants', ItemVariant.fromJson),
        modifiers: _rows(body, 'modifiers', Modifier.fromJson),
        modifierOptions: _rows(
          body,
          'modifier_options',
          ModifierOption.fromJson,
        ),
      );
    } on FormatException catch (e) {
      throw MenuReadException('list_menu malformed row: ${e.message}');
    }
  }

  static List<T> _rows<T>(
    Map<String, dynamic> body,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final rows = body[key];
    if (rows is! List) return <T>[];
    return rows
        .whereType<Map>()
        .map((row) => fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }
}
