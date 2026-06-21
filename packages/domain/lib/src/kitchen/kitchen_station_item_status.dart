/// The PROPOSED kitchen-station-item status enumeration (RF-034, DECISION D-018;
/// transitions owned by docs/STATE_MACHINES.md §4). Pure Dart.
///
/// Terminal states are `bumped` and `voided`. Station items have NO recall in
/// RF-034 (recall is driven at the kitchen-ticket level).
library;

enum KitchenStationItemStatus { queued, inPreparation, ready, bumped, voided }

extension KitchenStationItemStatusX on KitchenStationItemStatus {
  /// The canonical D-018 / D-017 snake_case state name.
  String get canonicalName => switch (this) {
    KitchenStationItemStatus.queued => 'queued',
    KitchenStationItemStatus.inPreparation => 'in_preparation',
    KitchenStationItemStatus.ready => 'ready',
    KitchenStationItemStatus.bumped => 'bumped',
    KitchenStationItemStatus.voided => 'voided',
  };

  /// Terminal station-item states accept no further transition (STATE_MACHINES §4).
  bool get isTerminal =>
      this == KitchenStationItemStatus.bumped ||
      this == KitchenStationItemStatus.voided;
}
