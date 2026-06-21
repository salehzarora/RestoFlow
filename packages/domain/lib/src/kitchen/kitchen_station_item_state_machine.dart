/// Table-driven kitchen-station-item transition validator (RF-034,
/// STATE_MACHINES §4). The allowed-edge table is the single source of legality;
/// any transition not listed is rejected. No recall at the station-item level
/// (RF-034). Pure Dart.
library;

import 'kitchen_state_exceptions.dart';
import 'kitchen_station_item_status.dart';

abstract final class KitchenStationItemStateMachine {
  static const Set<(KitchenStationItemStatus, KitchenStationItemStatus)>
  _edges = {
    (KitchenStationItemStatus.queued, KitchenStationItemStatus.inPreparation),
    (KitchenStationItemStatus.inPreparation, KitchenStationItemStatus.ready),
    (KitchenStationItemStatus.ready, KitchenStationItemStatus.bumped),
    (KitchenStationItemStatus.queued, KitchenStationItemStatus.voided),
    (KitchenStationItemStatus.inPreparation, KitchenStationItemStatus.voided),
    (KitchenStationItemStatus.ready, KitchenStationItemStatus.voided),
  };

  /// Whether `from -> to` is a legal kitchen-station-item transition.
  static bool isLegal(
    KitchenStationItemStatus from,
    KitchenStationItemStatus to,
  ) => _edges.contains((from, to));

  /// Returns [to] if legal, else throws
  /// [IllegalKitchenStationItemTransitionException].
  static KitchenStationItemStatus transition(
    KitchenStationItemStatus from,
    KitchenStationItemStatus to,
  ) {
    if (!isLegal(from, to)) {
      throw IllegalKitchenStationItemTransitionException(from, to);
    }
    return to;
  }
}
