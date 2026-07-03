import 'package:restoflow_core/restoflow_core.dart';

import '../models/menu_entity_type.dart';
import '../models/menu_scope.dart';
import '../models/menu_write_failure.dart';
import '../models/menu_write_result.dart';

/// A single menu write outcome.
typedef MenuWriteOutcome = Result<MenuWriteResult, MenuWriteFailure>;

/// The menu write seam (RF-111): the seven RF-109 management operations.
///
/// Writes are UPSERT-BY-ID (pass `id == null` to create, an existing id to
/// update) and ONLINE-DIRECT (no outbox / idempotency key). Org/restaurant/branch
/// are immutable on update (they come from [scope]). Implementations:
///  * [RpcMenuWriter] — calls the `public.menu_*` RPCs over the transport seam;
///  * the in-memory store — a local demo/test double.
abstract class MenuWriter {
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int displayOrder = 0,
    bool isActive = true,
  });

  /// [imagePath] is the RF-110 object key of the item's current image; null
  /// CLEARS it (the editor always sends the item's full state — the server
  /// treats a missing/blank `p_image_path` as unset).
  ///
  /// The rich attributes (menu/media sprint) follow the same full-state rule:
  /// null/empty = clear. [itemType] is one of [kMenuItemTypes]; [tags] holds
  /// [kMenuItemTags] wire strings; [attributes] is the generic NON-MONEY bag
  /// (snake_case keys — see [MenuItem.buildAttributes]; money NEVER rides it,
  /// D-007); [sku] never reaches devices (server-side).
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
  });

  Future<MenuWriteOutcome> upsertSize({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  });

  Future<MenuWriteOutcome> upsertVariant({
    required MenuScope scope,
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  });

  /// [allowQuantity] lets the POS add the SAME option more than once (a
  /// quantity stepper). Only meaningful for `multiple` selection — the server
  /// rejects `single` + allow_quantity. [maxQuantity] caps the units of a
  /// single option while quantity is allowed (null = no cap).
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
    bool allowQuantity = false,
    int? maxQuantity,
  });

  Future<MenuWriteOutcome> upsertModifierOption({
    required MenuScope scope,
    String? id,
    required String modifierId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  });

  Future<MenuWriteOutcome> softDelete({
    required String organizationId,
    required MenuEntityType entity,
    required String id,
  });
}
