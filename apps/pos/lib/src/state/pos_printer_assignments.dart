import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';

/// The token-proven printer-assignments reader for THIS paired POS station
/// (device settings sprint). Null by default (demo mode / unconfigured real
/// mode — the settings sheet then shows no printer data instead of faking
/// any). Overridden in `main.dart` with the real repository riding the same
/// anonymous device transport.
final posPrinterAssignmentsReaderProvider =
    Provider<DevicePrinterAssignmentsReader?>((ref) => null);

/// The current printer-assignment snapshot for this station, or null when no
/// reader is wired. Refresh = `ref.invalidate(posPrinterAssignmentsProvider)`
/// (the ⋮ menu's "Refresh connection"). Failures surface as typed values —
/// the sheet renders a safe error, never a fake "Ready".
final posPrinterAssignmentsProvider =
    FutureProvider<
      Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>?
    >((ref) async {
      final reader = ref.watch(posPrinterAssignmentsReaderProvider);
      if (reader == null) return null;
      return reader.load();
    });

/// PRINT-LAYOUT-001B: the paired station's own RESTAURANT NAME for printed
/// headers, or null when unknown (demo / unconfigured / still loading / load
/// failed) — the print builders then use a localized fallback, never a
/// hardcoded placeholder. Offline-safe: reads the already-loaded assignments
/// snapshot (the same one the settings sheet shows); it never triggers a fetch.
final posRestaurantNameProvider = Provider<String?>((ref) {
  final snapshot = switch (ref
      .watch(posPrinterAssignmentsProvider)
      .valueOrNull) {
    Success(:final value) => value,
    _ => null,
  };
  final name = snapshot?.restaurantName?.trim();
  return (name == null || name.isEmpty) ? null : name;
});

/// POS-TOPBAR-RESTAURANT-IDENTITY-009: the label that names the connected
/// station in the UI — the RESTAURANT name, falling back to the BRANCH name
/// when the server did not send a restaurant name.
///
/// Null when neither is known (demo / unconfigured / still loading / load
/// failed). Callers must render nothing rather than invent placeholder copy:
/// a wrong restaurant name on a cashier's screen is worse than no name.
/// Offline-safe for the same reason as [posRestaurantNameProvider] — it reads
/// the already-loaded snapshot and never triggers a fetch.
final posStationIdentityLabelProvider = Provider<String?>((ref) {
  final restaurant = ref.watch(posRestaurantNameProvider);
  if (restaurant != null) return restaurant;
  final snapshot = switch (ref
      .watch(posPrinterAssignmentsProvider)
      .valueOrNull) {
    Success(:final value) => value,
    _ => null,
  };
  final branch = snapshot?.branchName?.trim();
  return (branch == null || branch.isEmpty) ? null : branch;
});
