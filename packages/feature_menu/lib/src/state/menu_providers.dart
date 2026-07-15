import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_core/restoflow_core.dart' show Failure;

import '../data/image_file_picker.dart' as picker;
import '../data/menu_image_storage.dart';
import '../data/menu_management_repository.dart';
import '../data/menu_read_source.dart';
import '../data/menu_writer.dart';
import '../data/picked_menu_image.dart';
import '../models/menu_entity_type.dart';
import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';
import '../models/menu_write_failure.dart';

/// The active menu scope (RF-108 membership). MUST be overridden at the surface
/// root — unoverridden it throws (deny-by-default; never a guessed scope).
final menuScopeProvider = Provider<MenuScope>((ref) {
  throw UnimplementedError(
    'menuScopeProvider must be overridden with the active MenuScope (RF-108).',
  );
});

/// The menu read source. MUST be overridden (fake/demo today; a real online
/// source is deferred to the auth/org-context bridge, D1/D3).
final menuReadSourceProvider = Provider<MenuReadSource>((ref) {
  throw UnimplementedError('menuReadSourceProvider must be overridden.');
});

/// The menu writer. MUST be overridden with the in-memory store (demo) or an
/// [RpcMenuWriter] over an authenticated transport (deferred).
final menuWriterProvider = Provider<MenuWriter>((ref) {
  throw UnimplementedError('menuWriterProvider must be overridden.');
});

/// The image storage wiring for the item editor's image panel (menu/media
/// sprint). Defaults to `null` (no storage on this surface) — the panel shows
/// its honest "upload not available" state instead of a fake uploader. The
/// dashboard overrides it: real mode with a Supabase-backed [MenuImageStorage],
/// demo mode with a [FakeMenuImageStorage] + `isDemo: true` label.
final menuImageStorageProvider = Provider<MenuImageStorageConfig?>(
  (ref) => null,
);

/// Whether THIS build target can pick an image file at all (web: yes; other
/// targets: no — the panel shows an honest note). Provider-wrapped so widget
/// tests (which run on the VM) can exercise the picking flow.
final menuImagePickerSupportedProvider = Provider<bool>(
  (ref) => picker.menuImagePickerSupported,
);

/// Opens the platform image picker. Provider-wrapped so tests can inject a
/// canned [PickedMenuImage] without a browser.
final menuImageFilePickerProvider =
    Provider<Future<PickedMenuImage?> Function()>(
      (ref) => picker.pickMenuImageFile,
    );

/// The repository, composed from the injected read source + writer.
final menuRepositoryProvider = Provider<MenuManagementRepository>((ref) {
  return MenuManagementRepository(
    readSource: ref.watch(menuReadSourceProvider),
    writer: ref.watch(menuWriterProvider),
  );
}, dependencies: [menuReadSourceProvider, menuWriterProvider]);

/// The loaded menu tree for the active scope. Reloads when invalidated after a
/// successful write (non-optimistic).
final menuSnapshotProvider = FutureProvider.autoDispose<MenuSnapshot>((
  ref,
) async {
  final repository = ref.watch(menuRepositoryProvider);
  final scope = ref.watch(menuScopeProvider);
  return repository.load(scope);
}, dependencies: [menuScopeProvider, menuRepositoryProvider]);

/// The currently focused category in the master/detail layout.
final selectedCategoryIdProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

/// The currently focused item in the master/detail layout.
final selectedItemIdProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

/// Performs menu writes against the active scope, then reloads the snapshot on
/// success (the UI shows the [MenuWriteFailure] on failure). Writes are
/// non-optimistic: nothing changes locally until the reload reflects the server.
class MenuWriteController {
  MenuWriteController(this._ref);

  final Ref _ref;

  MenuManagementRepository get _repository => _ref.read(menuRepositoryProvider);
  MenuScope get _scope => _ref.read(menuScopeProvider);

  Future<MenuWriteOutcome> _run(
    Future<MenuWriteOutcome> Function() operation,
  ) async {
    final MenuWriteOutcome outcome;
    try {
      outcome = await operation();
    } catch (_) {
      // Defensive: a writer/wiring error that THROWS (instead of returning a
      // Failure) must still surface as a visible, safe dialog error — never
      // strand a submitting state, never leak a raw error/SQL string (the UI
      // renders MenuServerFailure as the generic write-problem message).
      return const Failure(MenuServerFailure());
    }
    if (outcome.isSuccess) {
      // Deferred: the save dialog pops in the SAME tick this future completes,
      // and a synchronous invalidate then delivers a cross-subtree
      // markNeedsBuild while the overlay is mid-build ("setState() called
      // during build" — crashes debug web). A zero-delay timer refreshes the
      // surface right after the frame instead. Swallow only the
      // disposed-container race (surface already gone -> nothing to refresh).
      Future<void>.delayed(Duration.zero, () {
        try {
          _ref.invalidate(menuSnapshotProvider);
        } catch (_) {}
      });
    }
    return outcome;
  }

  Future<MenuWriteOutcome> upsertCategory({
    String? id,
    required String name,
    int displayOrder = 0,
    bool isActive = true,
  }) => _run(
    () => _repository.upsertCategory(
      scope: _scope,
      id: id,
      name: name,
      displayOrder: displayOrder,
      isActive: isActive,
    ),
  );

  Future<MenuWriteOutcome> upsertItem({
    String? id,
    required String menuCategoryId,
    required String name,
    String? description,
    required int basePriceMinor,
    required String currencyCode,
    int displayOrder = 0,
    bool isActive = true,
    String? imagePath,
    String? itemType,
    List<String> tags = const [],
    int? prepMinutes,
    String? sku,
    String? kitchenNote,
    Map<String, dynamic> attributes = const {},
  }) => _run(
    () => _repository.upsertItem(
      scope: _scope,
      id: id,
      menuCategoryId: menuCategoryId,
      name: name,
      description: description,
      basePriceMinor: basePriceMinor,
      currencyCode: currencyCode,
      displayOrder: displayOrder,
      isActive: isActive,
      // null = clear/unset — every caller sends the item's FULL state, so a
      // details-save must pass the item's current imagePath through or it
      // would silently wipe a freshly uploaded image. The rich attributes
      // (itemType/tags/prepMinutes/sku/kitchenNote/attributes) follow the
      // same full-state rule.
      imagePath: imagePath,
      itemType: itemType,
      tags: tags,
      prepMinutes: prepMinutes,
      sku: sku,
      kitchenNote: kitchenNote,
      attributes: attributes,
    ),
  );

  Future<MenuWriteOutcome> upsertSize({
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) => _run(
    () => _repository.upsertSize(
      scope: _scope,
      id: id,
      menuItemId: menuItemId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
    ),
  );

  Future<MenuWriteOutcome> upsertVariant({
    String? id,
    required String menuItemId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
  }) => _run(
    () => _repository.upsertVariant(
      scope: _scope,
      id: id,
      menuItemId: menuItemId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
    ),
  );

  Future<MenuWriteOutcome> upsertModifier({
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
  }) => _run(
    () => _repository.upsertModifier(
      scope: _scope,
      id: id,
      menuItemId: menuItemId,
      name: name,
      selectionType: selectionType,
      minSelect: minSelect,
      maxSelect: maxSelect,
      isRequired: isRequired,
      displayOrder: displayOrder,
      isActive: isActive,
      allowQuantity: allowQuantity,
      maxQuantity: maxQuantity,
    ),
  );

  Future<MenuWriteOutcome> upsertModifierOption({
    String? id,
    required String modifierId,
    required String name,
    int priceDeltaMinor = 0,
    int displayOrder = 0,
    bool isActive = true,
    Map<String, dynamic>? kitchenMeat,
  }) => _run(
    () => _repository.upsertModifierOption(
      scope: _scope,
      id: id,
      modifierId: modifierId,
      name: name,
      priceDeltaMinor: priceDeltaMinor,
      displayOrder: displayOrder,
      isActive: isActive,
      kitchenMeat: kitchenMeat,
    ),
  );

  Future<MenuWriteOutcome> softDelete({
    required MenuEntityType entity,
    required String id,
  }) => _run(
    () => _repository.softDelete(
      organizationId: _scope.organizationId,
      entity: entity,
      id: id,
    ),
  );

  /// RESTAURANT-OPERATIONS-V1-001: flips the item's PER-BRANCH availability.
  /// Only callable when the active scope names a branch (availability is
  /// per-branch by definition — the UI hides the control otherwise).
  Future<MenuWriteOutcome> setItemAvailability({
    required String menuItemId,
    required String availability,
    String? reason,
  }) => _run(
    () => _repository.setItemAvailability(
      scope: _scope,
      menuItemId: menuItemId,
      availability: availability,
      reason: reason,
    ),
  );
}

/// The write controller for the active scope.
final menuWriteControllerProvider = Provider<MenuWriteController>(
  (ref) {
    return MenuWriteController(ref);
  },
  dependencies: [
    menuScopeProvider,
    menuRepositoryProvider,
    menuSnapshotProvider,
  ],
);

/// Builds the [ProviderScope] overrides that wire the menu feature to a concrete
/// scope + read source + writer (+ optionally the image storage for the item
/// editor's image panel — omit it and the panel shows its honest "upload not
/// available" state).
List<Override> menuFeatureOverrides({
  required MenuScope scope,
  required MenuReadSource readSource,
  required MenuWriter writer,
  MenuImageStorageConfig? imageStorage,
}) {
  return [
    menuScopeProvider.overrideWithValue(scope),
    menuReadSourceProvider.overrideWithValue(readSource),
    menuWriterProvider.overrideWithValue(writer),
    if (imageStorage != null)
      menuImageStorageProvider.overrideWithValue(imageStorage),
  ];
}
