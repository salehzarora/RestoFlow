import 'package:drift/drift.dart';

import 'sync_operation_state.dart';

/// Drift [TypeConverter] persisting [SyncOperationState] as its snake_case
/// [SyncOperationState.wireName] text (e.g. `in_flight`). Keeping the enum pure
/// Dart and the storage mapping here means the DB column stores the canonical
/// wire value shared with the server vocabulary (OFFLINE_SYNC_SPEC section 4).
class SyncOperationStateConverter
    extends TypeConverter<SyncOperationState, String> {
  const SyncOperationStateConverter();

  @override
  String toSql(SyncOperationState value) => value.wireName;

  @override
  SyncOperationState fromSql(String fromDb) =>
      SyncOperationState.fromWire(fromDb);
}
