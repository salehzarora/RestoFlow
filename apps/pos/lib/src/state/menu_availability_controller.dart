import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/ids.dart';
import '../data/menu_availability_repository.dart';
import 'pos_session.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — the demo availability overlay.
///
/// The demo menu is a const dataset, so a demo availability change is represented
/// as an in-memory overlay of `menu_item_id -> (availability, reason)`. `posMenuProvider`
/// applies it in demo mode, so a demo Sold-out/Paused is HONESTLY reflected on the
/// tile (no fake success). Real mode never uses this — it re-fetches the menu.
typedef DemoAvailabilityOverride = ({String availability, String? reason});

class DemoAvailabilityOverrides
    extends Notifier<Map<String, DemoAvailabilityOverride>> {
  @override
  Map<String, DemoAvailabilityOverride> build() =>
      const <String, DemoAvailabilityOverride>{};

  void set(String menuItemId, String availability, String? reason) {
    state = <String, DemoAvailabilityOverride>{
      ...state,
      menuItemId: (
        availability: availability,
        reason: availability == 'unavailable' ? reason : null,
      ),
    };
  }
}

final demoAvailabilityOverridesProvider =
    NotifierProvider<
      DemoAvailabilityOverrides,
      Map<String, DemoAvailabilityOverride>
    >(DemoAvailabilityOverrides.new);

/// DEMO availability repository: writes to the in-memory overlay (honest demo
/// success — the demo store CAN represent it).
class DemoMenuAvailabilityRepository implements MenuAvailabilityRepository {
  DemoMenuAvailabilityRepository(this._ref);

  final Ref _ref;

  @override
  Future<MenuAvailabilityState> setAvailability({
    required String menuItemId,
    required String availability,
    String? reason,
  }) async {
    _ref
        .read(demoAvailabilityOverridesProvider.notifier)
        .set(menuItemId, availability, reason);
    return MenuAvailabilityState(
      menuItemId: menuItemId,
      availability: availability,
      reason: availability == 'unavailable' ? reason : null,
    );
  }
}

/// The availability write seam: demo overlay vs the real sync_push path.
final menuAvailabilityRepositoryProvider = Provider<MenuAvailabilityRepository>(
  (ref) {
    if (ref.watch(runtimeConfigProvider).isDemoMode) {
      return DemoMenuAvailabilityRepository(ref);
    }
    return RealMenuAvailabilityRepository(
      ref.watch(posAuthTransportProvider),
      ref.watch(posSyncSessionProvider),
      ref.watch(clientIdGeneratorProvider),
    );
  },
);
