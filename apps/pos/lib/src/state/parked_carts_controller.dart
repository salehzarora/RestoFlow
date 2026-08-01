/// PARKED-CARTS-001 — parking and restoring ordinary UNSENT POS carts.
///
/// SAFETY CONTRACT (the whole point of this file): parking and restoring are
/// LOCAL DRAFT MANAGEMENT ONLY. Nothing here calls `order.submit` or
/// `order.items_add`, allocates a server order, enqueues a sync/outbox
/// operation, reserves inventory, creates kitchen work, prints anything, touches
/// a payment, or claims a table on the server. A parked cart becomes a real
/// order only after it is restored and the cashier uses the ordinary Submit
/// flow.
///
/// AMENDMENT CARTS ARE EXCLUDED. A cart that is adding items to an EXISTING
/// order is not a free draft: its payload is frozen and owned by the server-side
/// attempt, so parking it would either strand the amendment or let the same
/// lines be sent twice. Park refuses while addition mode is active, while the
/// cart is locked by an addition, and while any amendment attempt is open.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_tables.dart' show DemoTable;
import '../data/parked_carts_store.dart';
import 'addition_controller.dart' show additionControllerProvider;
import 'cart_controller.dart';
import 'order_setup_controller.dart';
import 'order_sync_controller.dart' show posSyncClockProvider;
import 'pos_menu_provider.dart' show posMenuProvider;
import 'pos_session.dart' show posSignedInEmployeeProfileIdProvider;
import 'pos_sync_scope_provider.dart';

/// Why a Park attempt ended the way it did. Every refusal is REPORTED so the UI
/// can say something true, never silently swallowed.
enum ParkResult {
  parked,

  /// There is nothing to park.
  cartEmpty,

  /// An amendment (add-items) cart, or a cart frozen by one, is not parkable.
  blockedByAddition,

  /// A submitted-order confirmation is still showing, or another park/restore is
  /// already running.
  busy,

  /// No active POS scope (unpaired / signed out) — a draft with no scope has
  /// nowhere safe to live.
  noScope,

  /// The durable write did not stick. The cart and the setup are untouched.
  persistFailed,
}

/// Why a Restore attempt ended the way it did.
enum RestoreStatus {
  restored,

  /// The active cart has lines. The caller must offer "Park current cart and
  /// restore" or Cancel — never a silent overwrite, merge, clear or discard.
  activeCartNotEmpty,

  blockedByAddition,
  notFound,
  busy,
  noScope,

  /// Restoration failed BEFORE any active state was applied: the parked record
  /// is still on disk and the active cart is unchanged.
  failed,
}

/// The full outcome of a restore, including the non-blocking reviews the cashier
/// must see.
class RestoreOutcome {
  const RestoreOutcome(
    this.status, {
    this.tableUnavailable = false,
    this.unavailableItems = const <String>[],
    this.entryRetained = false,
  });

  final RestoreStatus status;

  /// The parked dine-in table is no longer assignable, so the cart was restored
  /// WITHOUT a table. No other table is ever chosen automatically.
  final bool tableUnavailable;

  /// Names of restored lines whose menu item is now missing or unavailable. The
  /// PARKED snapshots are kept as-is (never substituted with current catalog
  /// values); this is a non-blocking review, and the authoritative submit-time
  /// rejection remains the real enforcement boundary.
  final List<String> unavailableItems;

  /// The cart was restored but the parked record could NOT be deleted. It stays
  /// on disk on purpose — losing the cashier's restored work would be worse.
  final bool entryRetained;

  bool get ok => status == RestoreStatus.restored;
  bool get needsReview => tableUnavailable || unavailableItems.isNotEmpty;
}

/// Why a Delete attempt ended the way it did.
enum DeleteResult { deleted, notFound, busy, noScope, persistFailed }

/// The parked-carts list state.
class ParkedCartsState {
  const ParkedCartsState({
    this.carts = const <ParkedCart>[],
    this.loading = true,
    this.loadFailed = false,
    this.unreadableCount = 0,
    this.busy = false,
  });

  final List<ParkedCart> carts;
  final bool loading;

  /// The stored envelope could not be trusted. The list is shown as FAILED with
  /// a retry — never as "no parked orders", which would invite the cashier to
  /// re-key an order that is still on disk.
  final bool loadFailed;

  /// How many stored records this build could not decode. They are preserved on
  /// disk, not deleted.
  final int unreadableCount;

  /// A park/restore/delete is in flight.
  final bool busy;

  int get count => carts.length;
  bool get isEmpty => carts.isEmpty;

  ParkedCartsState copyWith({
    List<ParkedCart>? carts,
    bool? loading,
    bool? loadFailed,
    int? unreadableCount,
    bool? busy,
  }) => ParkedCartsState(
    carts: carts ?? this.carts,
    loading: loading ?? this.loading,
    loadFailed: loadFailed ?? this.loadFailed,
    unreadableCount: unreadableCount ?? this.unreadableCount,
    busy: busy ?? this.busy,
  );
}

class ParkedCartsController extends Notifier<ParkedCartsState> {
  bool _disposed = false;

  /// ONE in-flight guard for every mutating operation. A rapid double press —
  /// on Park, on Restore, on Delete — must produce exactly one effect, and two
  /// different operations must never interleave over the same envelope.
  bool _busy = false;

  @override
  ParkedCartsState build() {
    // WATCHING the scope is what makes parked carts scope-gated: a re-pair, a
    // branch move or a sign-out rebuilds this controller, so another scope's
    // drafts are neither shown nor adopted.
    ref.watch(posSyncScopeProvider);
    ref.onDispose(() => _disposed = true);
    Future<void>.microtask(load);
    return const ParkedCartsState();
  }

  ParkedCartsStore get _store => ref.read(parkedCartsStoreProvider);
  DateTime _now() => ref.read(posSyncClockProvider)();

  /// (Re)loads this scope's parked carts. Safe to call from a Retry action.
  Future<void> load() async {
    final scope = ref.read(posSyncScopeProvider);
    if (scope == null) {
      if (!_disposed) {
        state = const ParkedCartsState(loading: false);
      }
      return;
    }
    try {
      final snapshot = await _store.load(scope);
      if (_disposed) return;
      state = state.copyWith(
        carts: snapshot.carts,
        loading: false,
        loadFailed: false,
        unreadableCount: snapshot.unreadable.length,
      );
    } catch (_) {
      if (_disposed) return;
      // Fail CLOSED and VISIBLY: an unreadable envelope is not an empty one.
      state = state.copyWith(
        carts: const <ParkedCart>[],
        loading: false,
        loadFailed: true,
      );
    }
  }

  /// Whether the CURRENT cart may be parked. Pure read — the UI uses it to
  /// enable/disable the action, and [park] re-checks it regardless.
  bool get canPark => _parkRefusal() == null;

  /// The reason Park is refused, or null when it is allowed.
  ParkResult? _parkRefusal() {
    if (_busy) return ParkResult.busy;
    final cart = ref.read(cartControllerProvider);
    // A frozen amendment owns this cart; its payload must stay exactly what was
    // frozen. Checked BEFORE emptiness so the refusal reason is the honest one.
    if (cart.lockedByAddition) return ParkResult.blockedByAddition;
    final addition = ref.read(additionControllerProvider);
    if (addition.active || addition.hasOpenAttempt) {
      return ParkResult.blockedByAddition;
    }
    // A confirmation is still on screen: that order is already submitted, and
    // the cart behind it is not a free draft to set aside.
    if (cart.hasSubmittedOrder) return ParkResult.busy;
    if (cart.isEmpty) return ParkResult.cartEmpty;
    if (ref.read(posSyncScopeProvider) == null) return ParkResult.noScope;
    return null;
  }

  /// Parks the active cart.
  ///
  /// ATOMIC BY CONSTRUCTION: the guard is set before any async work; the draft,
  /// the setup and the scope binding are captured SYNCHRONOUSLY; the record is
  /// persisted and VERIFIED; and only then is the cart reset. A failed write
  /// leaves the cashier's cart and setup byte-for-byte unchanged with no partial
  /// row on disk.
  Future<ParkResult> park() async {
    final refusal = _parkRefusal();
    if (refusal != null) return refusal;
    _busy = true;
    if (!_disposed) state = state.copyWith(busy: true);
    try {
      // ---- synchronous capture: no await may separate these reads ----------
      final scope = ref.read(posSyncScopeProvider)!;
      final draft = ref.read(cartControllerProvider.notifier).captureDraft();
      final setup = ref.read(orderSetupControllerProvider);
      final employeeProfileId = ref.read(posSignedInEmployeeProfileIdProvider);
      final now = _now();
      if (draft.isEmpty) return ParkResult.cartEmpty;

      final ParkedCart stored;
      try {
        stored = await _store.add(
          scope,
          (id) => ParkedCart(
            id: id,
            createdAt: now,
            updatedAt: now,
            // v1 has no rename editor: the customer name is the most useful
            // label when there is one, and the UI falls back to the parked time.
            label: setup.customerName,
            orderType: setup.orderType,
            table: setup.assignedTable,
            customerName: setup.customerName,
            customerPhone: setup.customerPhone,
            draft: draft,
            scopeKey: scope.key,
            employeeProfileId: employeeProfileId,
          ),
        );
      } catch (_) {
        // NOTHING has been applied to the active cart yet, and nothing will be.
        return ParkResult.persistFailed;
      }

      // ---- only now is it safe to clear the cashier's screen ---------------
      // startNewOrder (never clear): clear leaves the display-order and prep
      // side maps behind, which would leak the parked cart's kitchen data into
      // the next order.
      ref.read(cartControllerProvider.notifier).startNewOrder();
      ref.read(orderSetupControllerProvider.notifier).reset();

      if (!_disposed) {
        state = state.copyWith(carts: _merge(state.carts, stored));
      }
      return ParkResult.parked;
    } finally {
      _busy = false;
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  /// Restores the parked cart [id] into the active cart.
  ///
  /// When the active cart is NOT empty this refuses with
  /// [RestoreStatus.activeCartNotEmpty] so the caller can offer the only two
  /// honest choices. Passing [parkCurrentFirst] runs the same atomic Park
  /// contract on the current cart first; if that park fails, nothing is
  /// restored and BOTH carts remain intact.
  Future<RestoreOutcome> restore(
    String id, {
    bool parkCurrentFirst = false,
  }) async {
    // The addition interlock is checked UP FRONT, before any restore UI or
    // work — matching how the production recovery path refuses.
    final cart = ref.read(cartControllerProvider);
    final addition = ref.read(additionControllerProvider);
    if (cart.lockedByAddition || addition.active || addition.hasOpenAttempt) {
      return const RestoreOutcome(RestoreStatus.blockedByAddition);
    }
    if (_busy) return const RestoreOutcome(RestoreStatus.busy);
    final scope = ref.read(posSyncScopeProvider);
    if (scope == null) return const RestoreOutcome(RestoreStatus.noScope);

    if (cart.isNotEmpty) {
      if (!parkCurrentFirst) {
        return const RestoreOutcome(RestoreStatus.activeCartNotEmpty);
      }
      final parked = await park();
      if (parked != ParkResult.parked) {
        // Both carts must remain recoverable: the active cart was not cleared
        // (park is atomic), and the selected parked record was never touched.
        return const RestoreOutcome(RestoreStatus.failed);
      }
    }

    _busy = true;
    if (!_disposed) state = state.copyWith(busy: true);
    try {
      final ParkedCartsSnapshot snapshot;
      try {
        snapshot = await _store.load(scope);
      } catch (_) {
        return const RestoreOutcome(RestoreStatus.failed);
      }
      final target = snapshot.carts.where((c) => c.id == id).firstOrNull;
      if (target == null) return const RestoreOutcome(RestoreStatus.notFound);

      // Re-check the interlock after the awaits: an amendment may have started.
      final freshCart = ref.read(cartControllerProvider);
      if (freshCart.lockedByAddition) {
        return const RestoreOutcome(RestoreStatus.blockedByAddition);
      }
      if (freshCart.isNotEmpty) {
        return const RestoreOutcome(RestoreStatus.activeCartNotEmpty);
      }

      // ---- table revalidation, BEFORE touching the cart --------------------
      // The serialized status is a claim about the past. The LIVE table decides.
      final tableOutcome = await _resolveTable(target.table);

      // ---- catalog review: what the parked snapshot names vs today's menu ---
      final unavailable = _unavailableItemNames(target);

      // ---- apply, atomically, only after everything above resolved ---------
      final restored = ref
          .read(cartControllerProvider.notifier)
          .restoreDraft(target.draft);
      if (restored != CartMutationResult.applied) {
        return const RestoreOutcome(RestoreStatus.failed);
      }
      final setupController = ref.read(orderSetupControllerProvider.notifier);
      setupController.reset();
      setupController.setOrderType(target.orderType);
      if (tableOutcome.table != null) {
        setupController.assignTable(tableOutcome.table!);
      }
      setupController.setCustomerName(target.customerName);
      setupController.setCustomerPhone(target.customerPhone ?? '');

      // ---- remove the parked entry LAST, with a verified write -------------
      var entryRetained = false;
      try {
        await _store.remove(scope, id);
      } catch (_) {
        // The restored cart stays. Keeping a duplicate record on disk is
        // recoverable; throwing away the cashier's restored order is not.
        entryRetained = true;
      }
      if (!_disposed) {
        state = state.copyWith(
          carts: entryRetained
              ? state.carts
              : [
                  for (final c in state.carts)
                    if (c.id != id) c,
                ],
        );
      }
      return RestoreOutcome(
        RestoreStatus.restored,
        tableUnavailable: tableOutcome.unavailable,
        unavailableItems: unavailable,
        entryRetained: entryRetained,
      );
    } finally {
      _busy = false;
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  /// Deletes the parked cart [id]. LOCAL ONLY: never `order.cancel`, never
  /// `order.void`, never any server call, print or payment action.
  Future<DeleteResult> delete(String id) async {
    if (_busy) return DeleteResult.busy;
    final scope = ref.read(posSyncScopeProvider);
    if (scope == null) return DeleteResult.noScope;
    if (!state.carts.any((c) => c.id == id)) return DeleteResult.notFound;
    _busy = true;
    if (!_disposed) state = state.copyWith(busy: true);
    try {
      try {
        await _store.remove(scope, id);
      } catch (_) {
        return DeleteResult.persistFailed;
      }
      if (!_disposed) {
        state = state.copyWith(
          carts: [
            for (final c in state.carts)
              if (c.id != id) c,
          ],
        );
      }
      return DeleteResult.deleted;
    } finally {
      _busy = false;
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  /// Re-resolves a parked table against the LIVE tables. Returns the live table
  /// ONLY when it still exists and is currently assignable; otherwise reports it
  /// unavailable so the caller restores everything else and leaves the table
  /// unassigned. Never picks a different table.
  Future<({DemoTable? table, bool unavailable})> _resolveTable(
    DemoTable? parked,
  ) async {
    if (parked == null) return (table: null, unavailable: false);
    try {
      final live = await ref.read(tablesProvider.future);
      final match = live.where((t) => t.tableId == parked.tableId).firstOrNull;
      if (match != null && match.isAssignable) {
        return (table: match, unavailable: false);
      }
      return (table: null, unavailable: true);
    } catch (_) {
      // Fail CLOSED: an unreadable floor is not permission to claim a table.
      return (table: null, unavailable: true);
    }
  }

  /// Names of parked lines whose menu item is now MISSING or UNAVAILABLE.
  ///
  /// The parked name/price/modifier snapshots are preserved either way — a
  /// restored draft must never silently adopt today's catalog values. This is a
  /// non-blocking review; submit-time validation stays the enforcement boundary.
  List<String> _unavailableItemNames(ParkedCart cart) {
    final menu = ref.read(posMenuProvider).valueOrNull;
    if (menu == null) return const <String>[];
    final byId = {for (final item in menu.items) item.id: item};
    final names = <String>[];
    for (final line in cart.draft.lines) {
      final item = byId[line.menuItemId];
      if (item == null || item.isUnavailable) {
        if (!names.contains(line.name)) names.add(line.name);
      }
    }
    return names;
  }

  /// updatedAt DESCENDING with the same deterministic tie-break the store uses,
  /// so the in-memory list and a reloaded one agree.
  static List<ParkedCart> _merge(List<ParkedCart> current, ParkedCart added) {
    final out = [...current, added];
    out.sort((a, b) {
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      if (byTime != 0) return byTime;
      return b.id.compareTo(a.id);
    });
    return out;
  }
}

final parkedCartsControllerProvider =
    NotifierProvider<ParkedCartsController, ParkedCartsState>(
      ParkedCartsController.new,
    );

/// The parked-cart count for the cart-header badge. 0 hides the control.
final parkedCartsCountProvider = Provider<int>(
  (ref) => ref.watch(parkedCartsControllerProvider).count,
);
