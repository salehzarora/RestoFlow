/// Domain exceptions for local table management (RF-035).
///
/// Messages carry only domain values (short fixed text) — never secrets. Pure
/// Dart.
library;

/// Base type for all table-management failures.
abstract class TableException implements Exception {
  const TableException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Invalid [DiningTable] construction data (e.g. an empty required field).
class InvalidDiningTableException extends TableException {
  const InvalidDiningTableException(super.message);
}

/// Invalid [OrderPlacement] construction data.
class InvalidOrderPlacementException extends TableException {
  const InvalidOrderPlacementException(super.message);
}

/// A dine-in placement/assignment was attempted without a (required) tableId.
class MissingTableForDineInException extends TableException {
  const MissingTableForDineInException([
    super.message = 'a dine-in order requires a non-empty tableId',
  ]);
}

/// A table already hosts another open (non-terminal) dine-in order and the
/// policy does not allow multiple open dine-in orders per table.
class TableOccupiedException extends TableException {
  const TableOccupiedException([
    super.message =
        'table already hosts an open dine-in order (policy disallows sharing)',
  ]);
}

/// The order's tenant scope (org/restaurant/branch) does not match the table's.
class TableTenantMismatchException extends TableException {
  const TableTenantMismatchException([
    super.message = 'order and table tenant scope do not match',
  ]);
}

/// An assignment was attempted to an inactive table.
class InactiveTableException extends TableException {
  const InactiveTableException([super.message = 'table is not active']);
}

/// The order's [OrderType] does not match the requested assignment kind.
class OrderTypeMismatchException extends TableException {
  const OrderTypeMismatchException(super.message);
}
