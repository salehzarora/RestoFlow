/// GLOBAL-BRAND-DASHBOARD-V2-1 — the Overview setup surfaces' data layer.
///
/// THE DEFECT THIS REPLACES. `DashboardSetupCenter` loaded from a State field
/// initializer (`late Future _counts = _load()`) and `DashboardDeviceSummaryCard`
/// loaded in `initState`, so every mount of the Overview re-ran all of it — and
/// because the shell hands BOTH widgets the same `AdminRepository`, the device
/// list was fetched TWICE even on the very first mount. The shell destroys the
/// destination subtree on every tab switch, so the whole set repeated on every
/// return.
///
/// The Overview's analytics never had this problem: their four families are
/// non-autoDispose and live in the ProviderScope the shell hoists ABOVE the
/// KeyedSubtree, so they survive the teardown. These providers simply join them
/// there — the fix is to move the load off the widget lifecycle, not to retain
/// the widgets.
///
/// FOUR SOURCES, NOT ONE CACHE. Devices, printers, staff and the menu are
/// distinct domains that fail independently, and the Setup Center already
/// renders each one's failure as its own "unavailable" rather than failing the
/// panel. They stay four entries; only the DEVICE list is shared, because two
/// widgets genuinely ask the same question of the same repository.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminDevice, AdminRepository;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show MenuReadSource, MenuScope, MenuSnapshot;

import '../printers/printer_models.dart';
import '../printers/printers_repository.dart';
import '../staff/staff_models.dart';
import '../staff/staff_repository.dart';
import 'dashboard_providers.dart';

/// The identity of one setup/device request.
///
/// VALUE-BASED, never the repository instance. The shell keeps its scope and
/// its repositories in `late final` fields, so the repository object is the
/// SAME object across a membership change — keying on it would have quietly
/// served the previous tenant's devices under the new tenant's scope. These
/// four values are what actually decide the answer.
///
/// The membership scope, not the analytics branch selector: the Setup Center
/// asks "is THIS branch ready for service", and the repositories behind it are
/// built from the membership. Keying on the analytics selection would make the
/// checklist follow a reporting filter it has nothing to do with.
class SetupScopeKey {
  const SetupScopeKey({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.isDemoMode,
  });

  /// Null before a membership resolves — a valid, distinct identity whose
  /// answer is an honest "unavailable", never a silent empty list.
  final String? organizationId;
  final String? restaurantId;
  final String? branchId;

  /// Demo and real are different data sources on one provider path.
  final bool isDemoMode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetupScopeKey &&
          other.organizationId == organizationId &&
          other.restaurantId == restaurantId &&
          other.branchId == branchId &&
          other.isDemoMode == isDemoMode;

  @override
  int get hashCode =>
      Object.hash(organizationId, restaurantId, branchId, isDemoMode);

  @override
  String toString() =>
      'SetupScopeKey(org: $organizationId, restaurant: $restaurantId, '
      'branch: $branchId, demo: $isDemoMode)';
}

// ---------------------------------------------------------------------------
// Repository seams — overridden by the shell with the instances it ALREADY owns
// ---------------------------------------------------------------------------

/// The real device repository, or null when it is not wired (demo/tests).
///
/// A seam rather than a constructor argument so the load can live in a provider
/// that outlives the widget. The shell overrides it with the same instance the
/// Devices tab uses; nothing here ever constructs a repository, because a second
/// instance would mean a second cache and a second set of credentials.
final setupDevicesRepositoryProvider = Provider<AdminRepository?>(
  (ref) => null,
);

final setupPrintersRepositoryProvider = Provider<PrintersRepository?>(
  (ref) => null,
);

final setupStaffRepositoryProvider = Provider<StaffRepository?>((ref) => null);

/// The real menu read seam and the scope to read it at. Both null => the menu
/// card is omitted rather than shown with invented counts.
final setupMenuSourceProvider = Provider<MenuReadSource?>((ref) => null);
final setupMenuScopeProvider = Provider<MenuScope?>((ref) => null);

// ---------------------------------------------------------------------------
// The current key
// ---------------------------------------------------------------------------

/// The setup scope the Overview is currently showing.
final currentSetupScopeKeyProvider = Provider<SetupScopeKey>((ref) {
  final membership = ref.watch(dashboardMembershipIdentityProvider)?.membership;
  return SetupScopeKey(
    organizationId: membership?.organizationId,
    restaurantId: membership?.restaurantId,
    branchId: membership?.branchId,
    isDemoMode: ref.watch(runtimeConfigProvider).isDemoMode,
  );
}, dependencies: [dashboardMembershipIdentityProvider]);

// ---------------------------------------------------------------------------
// The four sources
// ---------------------------------------------------------------------------

/// THE canonical device list. Both the Setup Center and the device summary card
/// watch this ONE entry, so the pair costs a single `loadDevices()` instead of
/// two — on the first mount as much as on every later one.
///
/// Not `autoDispose`: the whole point is that it survives the shell tearing the
/// Overview subtree down. Null means the load failed or no repository is wired,
/// which both surfaces already render as an honest "unavailable" rather than a
/// fake zero.
final setupDevicesProvider =
    FutureProvider.family<List<AdminDevice>?, SetupScopeKey>((ref, key) async {
      final repository = ref.watch(setupDevicesRepositoryProvider);
      if (repository == null) return null;
      List<AdminDevice>? devices;
      (await repository.loadDevices()).fold((value) => devices = value, (_) {});
      return devices;
    }, dependencies: [setupDevicesRepositoryProvider]);

final setupPrintersProvider =
    FutureProvider.family<PrintersSnapshot?, SetupScopeKey>((ref, key) async {
      final repository = ref.watch(setupPrintersRepositoryProvider);
      if (repository == null) return null;
      PrintersSnapshot? snapshot;
      (await repository.load()).fold((value) => snapshot = value, (_) {});
      return snapshot;
    }, dependencies: [setupPrintersRepositoryProvider]);

final setupStaffProvider =
    FutureProvider.family<List<StaffMember>?, SetupScopeKey>((ref, key) async {
      final repository = ref.watch(setupStaffRepositoryProvider);
      if (repository == null) return null;
      List<StaffMember>? staff;
      (await repository.load()).fold((value) => staff = value, (_) {});
      return staff;
    }, dependencies: [setupStaffRepositoryProvider]);

/// The live menu, when both menu seams are wired. A throw degrades to null for
/// the same reason the others do: an unavailable count is honest, a zero is not.
final setupMenuProvider = FutureProvider.family<MenuSnapshot?, SetupScopeKey>((
  ref,
  key,
) async {
  final source = ref.watch(setupMenuSourceProvider);
  final scope = ref.watch(setupMenuScopeProvider);
  if (source == null || scope == null) return null;
  try {
    return await source.load(scope);
  } catch (_) {
    return null;
  }
}, dependencies: [setupMenuSourceProvider, setupMenuScopeProvider]);

/// Invalidates every setup source for ONE key.
///
/// Used by the Overview refresh action and by setup mutations. Scoped to the
/// key on purpose: refreshing the branch you are looking at must not throw away
/// another branch's cached answers.
void invalidateSetupSources(WidgetRef ref, SetupScopeKey key) =>
    _invalidateSetupSources(ref.invalidate, key);

/// The same, from a provider [Ref] (the refresh controller's side).
void invalidateSetupSourcesFromRef(Ref ref, SetupScopeKey key) =>
    _invalidateSetupSources(ref.invalidate, key);

void _invalidateSetupSources(
  void Function(ProviderOrFamily) invalidate,
  SetupScopeKey key,
) {
  invalidate(setupDevicesProvider(key));
  invalidate(setupPrintersProvider(key));
  invalidate(setupStaffProvider(key));
  invalidate(setupMenuProvider(key));
}
