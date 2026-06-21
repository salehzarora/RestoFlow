/// Local table-management config (RF-035). Conceptually a branch-level setting;
/// modeled minimally as an immutable value object. Pure Dart.
library;

class TablePolicy {
  const TablePolicy({this.allowMultipleOpenDineInPerTable = false});

  /// When false (default), a table may host at most one OPEN (non-terminal)
  /// dine-in order at a time. When true, multiple open dine-in orders may share
  /// a table (RF-035 AC#3 "unless explicitly allowed by config").
  final bool allowMultipleOpenDineInPerTable;

  @override
  bool operator ==(Object other) =>
      other is TablePolicy &&
      other.allowMultipleOpenDineInPerTable == allowMultipleOpenDineInPerTable;

  @override
  int get hashCode => allowMultipleOpenDineInPerTable.hashCode;
}
