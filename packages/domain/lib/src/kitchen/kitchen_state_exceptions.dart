/// Domain exceptions for the local kitchen state machines (RF-034).
///
/// Messages carry only domain values (state names, short fixed text) — never
/// secrets. Pure Dart.
library;

import 'kitchen_station_item_status.dart';
import 'kitchen_ticket_status.dart';

/// Base type for all kitchen state-machine failures.
abstract class KitchenStateException implements Exception {
  const KitchenStateException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A kitchen-ticket transition not present in the allowed table (STATE_MACHINES
/// §3). Note: `bumped -> in_preparation` is the recall ACTION, not a normal
/// transition — use `KitchenTicketStateMachine.recall`.
class IllegalKitchenTicketTransitionException extends KitchenStateException {
  IllegalKitchenTicketTransitionException(this.from, this.to)
    : super(
        'illegal kitchen ticket transition: '
        '${from.canonicalName} -> ${to.canonicalName}',
      );

  final KitchenTicketStatus from;
  final KitchenTicketStatus to;
}

/// A kitchen-station-item transition not present in the allowed table
/// (STATE_MACHINES §4).
class IllegalKitchenStationItemTransitionException
    extends KitchenStateException {
  IllegalKitchenStationItemTransitionException(this.from, this.to)
    : super(
        'illegal kitchen station item transition: '
        '${from.canonicalName} -> ${to.canonicalName}',
      );

  final KitchenStationItemStatus from;
  final KitchenStationItemStatus to;
}

/// A recall was attempted without a (required) non-empty reason.
class MissingRecallReasonException extends KitchenStateException {
  const MissingRecallReasonException([
    super.message = 'recall requires a non-empty reason',
  ]);
}

/// A recall was attempted without a (required) actor id placeholder.
class MissingRecallActorException extends KitchenStateException {
  const MissingRecallActorException([
    super.message = 'recall requires an actor id',
  ]);
}
