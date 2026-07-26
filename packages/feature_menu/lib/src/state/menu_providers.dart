import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart' show immutable;
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

/// MENU-ORDER-001 (Codex): identifies the EXACT sibling list a reorder targets —
/// the org/restaurant/branch scope + entity kind + the sibling-set PARENT id
/// (the restaurant for categories, the category for items, the item for modifier
/// groups, the modifier for options). Two drags of the SAME list share this key;
/// unrelated lists (a different category's items, a different modifier's options)
/// get distinct keys and never block one another.
@immutable
class MenuReorderScope {
  const MenuReorderScope({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.entity,
    required this.parentId,
  });

  final String organizationId;
  final String restaurantId;
  final String? branchId;
  final MenuEntityType entity;

  /// The sibling-set owner id: restaurantId (categories), the category id
  /// (items), the item id (modifier groups), the modifier id (options).
  final String parentId;

  @override
  bool operator ==(Object other) =>
      other is MenuReorderScope &&
      other.organizationId == organizationId &&
      other.restaurantId == restaurantId &&
      other.branchId == branchId &&
      other.entity == entity &&
      other.parentId == parentId;

  @override
  int get hashCode =>
      Object.hash(organizationId, restaurantId, branchId, entity, parentId);
}

/// MENU-ORDER-001 (Codex correction): a PER-SIBLING-SCOPE reorder in-flight latch.
/// While a drag reorder of one sibling list is persisting, a second drag on that
/// SAME list is ignored AND its controls are disabled — so two overlapping
/// reorders can never race two writes off a stale base order. Keyed by the exact
/// [MenuReorderScope] (not the entity kind), so reordering one category's items
/// never blocks another category's items. Non-autoDispose (must not reset
/// mid-await) and defaults false.
final menuReorderInFlightProvider =
    StateProvider.family<bool, MenuReorderScope>((ref, scope) => false);

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

  /// MENU-ORDER-001 (Codex, same-scope write guard): true when a user mutation of
  /// the sibling list named by [scope] is allowed — i.e. that EXACT list is not
  /// mid drag-reorder. Read at the controller boundary so the answer is authored
  /// once and cannot be bypassed by a widget that forgot to disable a control.
  /// A disposed container (the whole surface is gone) reads as writable: nothing
  /// is reordering and the write path below can't run anyway.
  bool canWriteMenuScope(MenuReorderScope scope) {
    try {
      return !_ref.read(menuReorderInFlightProvider(scope));
    } catch (_) {
      return true;
    }
  }

  /// MENU-ORDER-001 (Codex, same-scope write guard): the SINGLE chokepoint every
  /// user mutation funnels through. If [guardScope]'s sibling list is mid-reorder
  /// the write is REFUSED right here — BEFORE any repository/RPC call, so there is
  /// no optimistic change, no stale DTO on the wire, and no audit/server write —
  /// and returns a [MenuReorderInProgress] failure the caller may surface once.
  /// Otherwise it runs through [_run] (reload-on-success) like any other write.
  ///
  /// reorder()/reorderScoped() deliberately DO NOT route through here: they ARE
  /// the reorder and own the latch, so guarding them would self-block. This
  /// replaces scattered widget-only IgnorePointer/onPressed:null defences with one
  /// controller-level gate that a stale dialog callback, a keyboard action, a
  /// queued closure, or a direct/test call cannot get around.
  Future<MenuWriteOutcome> _guarded(
    MenuReorderScope guardScope,
    Future<MenuWriteOutcome> Function() operation,
  ) {
    if (!canWriteMenuScope(guardScope)) {
      return Future<MenuWriteOutcome>.value(
        const Failure(MenuReorderInProgress()),
      );
    }
    return _run(operation);
  }

  /// The exact sibling-list scope a write belongs to: the active org/restaurant/
  /// branch + the entity kind + the sibling-set owner id (the restaurant for
  /// categories, the category for items, the item for modifier groups, the
  /// modifier for options). Two writes on the same list share this key, so the
  /// guard matches exactly the list a drag reorder is rewriting.
  MenuReorderScope _siblingScope(MenuEntityType entity, String parentId) =>
      MenuReorderScope(
        organizationId: _scope.organizationId,
        restaurantId: _scope.restaurantId,
        branchId: _scope.branchId,
        entity: entity,
        parentId: parentId,
      );

  Future<MenuWriteOutcome> upsertCategory({
    String? id,
    required String name,
    int? displayOrder,
    bool isActive = true,
  }) => _guarded(
    // Categories' sibling owner is the restaurant.
    _siblingScope(MenuEntityType.category, _scope.restaurantId),
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
    int? displayOrder,
    bool isActive = true,
    String? imagePath,
    String? itemType,
    List<String> tags = const [],
    int? prepMinutes,
    String? sku,
    String? kitchenNote,
    Map<String, dynamic> attributes = const {},
  }) => _guarded(
    // Items' sibling owner is their category — reached the same way whether the
    // write is an add/edit, an active flip, or an image save/remove.
    _siblingScope(MenuEntityType.item, menuCategoryId),
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
    int? displayOrder,
    bool isActive = true,
  }) => _guarded(
    // Sizes' sibling owner is their item. (Sizes are not drag-reordered on this
    // surface, so the latch is never set — the guard is a harmless no-op today,
    // kept for uniformity + safety if a size reorder is ever added.)
    _siblingScope(MenuEntityType.size, menuItemId),
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
    int? displayOrder,
    bool isActive = true,
  }) => _guarded(
    // Variants' sibling owner is their item (not drag-reordered here — no-op
    // guard today, kept for uniformity).
    _siblingScope(MenuEntityType.variant, menuItemId),
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
    int? displayOrder,
    bool isActive = true,
    bool allowQuantity = false,
    int? maxQuantity,
  }) => _guarded(
    // Modifier groups' sibling owner is their item.
    _siblingScope(MenuEntityType.modifier, menuItemId),
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
    int? displayOrder,
    bool isActive = true,
    Map<String, dynamic>? kitchenMeat,
  }) => _guarded(
    // Options' sibling owner is their modifier group.
    _siblingScope(MenuEntityType.modifierOption, modifierId),
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

  /// Soft-deletes [id]. [parentId] is the sibling-set owner (the restaurant for a
  /// category, the category for an item, the item for a modifier group, the
  /// modifier for an option) — required so the same-scope guard can refuse the
  /// delete while that exact list is mid-reorder (a delete removes a member of
  /// the very set the reorder is rewriting to 1..N).
  Future<MenuWriteOutcome> softDelete({
    required MenuEntityType entity,
    required String id,
    required String parentId,
  }) => _guarded(
    _siblingScope(entity, parentId),
    () => _repository.softDelete(
      organizationId: _scope.organizationId,
      entity: entity,
      id: id,
    ),
  );

  /// MENU-ORDER-001 (Codex #4): the FULL reorder lifecycle owned by the
  /// controller, not a disposable widget callback — latch acquire, the RPC, the
  /// authoritative reconcile (#7), rollback, and the latch RELEASE all run on the
  /// provider [Ref], which outlives the menu widgets. So a widget disposed
  /// mid-flight (navigation) can neither throw a WidgetRef-after-await error nor
  /// leave the non-autoDispose per-scope latch stuck: the finally always runs on
  /// the surviving Ref, and if the whole surface scope is torn down the latch is
  /// disposed with it (and recreated false on return). Returns null when a
  /// reorder for [scope] is ALREADY in flight (the second drag is ignored);
  /// otherwise the outcome, which the caller may surface IF it is still mounted.
  Future<MenuWriteOutcome?> reorderScoped({
    required MenuReorderScope scope,
    required List<String> orderedIds,
  }) async {
    final latch = menuReorderInFlightProvider(scope);
    try {
      if (_ref.read(latch))
        return null; // already in flight for this exact scope
    } catch (_) {
      return null; // container already gone — nothing to do
    }
    _ref.read(latch.notifier).state = true;
    try {
      final MenuWriteOutcome outcome;
      try {
        outcome = await _repository.reorder(
          organizationId: scope.organizationId,
          restaurantId: scope.restaurantId,
          branchId: scope.branchId,
          entity: scope.entity,
          orderedIds: orderedIds,
        );
      } catch (_) {
        // A writer/wiring error that THROWS -> exact rollback + generic failure.
        try {
          _ref.invalidate(menuSnapshotProvider);
        } catch (_) {}
        return const Failure(MenuServerFailure());
      }
      if (outcome.isSuccess) {
        // #7: reconcile the COMMITTED order before releasing the latch (and
        // re-enabling controls), so no edit can capture a stale order in the gap.
        try {
          _ref.invalidate(menuSnapshotProvider);
          await _ref.read(menuSnapshotProvider.future);
        } catch (_) {}
      } else {
        // Exact rollback: re-assert the authoritative (unchanged) order.
        try {
          _ref.invalidate(menuSnapshotProvider);
        } catch (_) {}
      }
      return outcome;
    } finally {
      // ALWAYS release — even when the surface was disposed mid-flight (the read
      // then throws harmlessly; the latch went with the disposed container).
      try {
        _ref.read(latch.notifier).state = false;
      } catch (_) {}
    }
  }

  /// RESTAURANT-OPERATIONS-V1-001: flips the item's PER-BRANCH availability.
  /// Only callable when the active scope names a branch (availability is
  /// per-branch by definition — the UI hides the control otherwise).
  /// [menuCategoryId] is the item's category (its sibling-set owner) so the
  /// same-scope guard can refuse the flip while that category's items are
  /// mid-reorder.
  Future<MenuWriteOutcome> setItemAvailability({
    required String menuItemId,
    required String menuCategoryId,
    required String availability,
    String? reason,
  }) => _guarded(
    _siblingScope(MenuEntityType.item, menuCategoryId),
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
