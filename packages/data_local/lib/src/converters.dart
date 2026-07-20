import 'package:drift/drift.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

import 'kitchen_spool/kitchen_spool_status.dart';
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

/// Drift [TypeConverter] persisting the RF-071 [PrintJobState] as its wire text
/// (e.g. `possibly_printed`). The state machine lives in `packages/printing`;
/// `data_local` only stores the wire value.
class PrintJobStateConverter extends TypeConverter<PrintJobState, String> {
  const PrintJobStateConverter();

  @override
  String toSql(PrintJobState value) => value.wireName;

  @override
  PrintJobState fromSql(String fromDb) => PrintJobState.fromWire(fromDb);
}

/// Drift [TypeConverter] persisting the RF-071 [PrintJobType] as its wire text
/// (`receipt` / `kitchen_ticket` / `drawer_kick`). Wire-driven via
/// `wireName`/`fromWire`, so new job types persist with no converter change.
class PrintJobTypeConverter extends TypeConverter<PrintJobType, String> {
  const PrintJobTypeConverter();

  @override
  String toSql(PrintJobType value) => value.wireName;

  @override
  PrintJobType fromSql(String fromDb) => PrintJobType.fromWire(fromDb);
}

/// Drift [TypeConverter] persisting the KITCHEN-MODE-001C2A
/// [KitchenSpoolJobStatus] as its closed wire text (e.g. `possibly_printed`).
/// Unknown stored values throw (closed vocabulary — never pass through).
class KitchenSpoolJobStatusConverter
    extends TypeConverter<KitchenSpoolJobStatus, String> {
  const KitchenSpoolJobStatusConverter();

  @override
  String toSql(KitchenSpoolJobStatus value) => value.wireName;

  @override
  KitchenSpoolJobStatus fromSql(String fromDb) =>
      KitchenSpoolJobStatus.fromWire(fromDb);
}

/// Drift [TypeConverter] persisting [KitchenSpoolDispatchType] as the server
/// ledger's wire text (`initial_order` / `service_round` / `void`).
class KitchenSpoolDispatchTypeConverter
    extends TypeConverter<KitchenSpoolDispatchType, String> {
  const KitchenSpoolDispatchTypeConverter();

  @override
  String toSql(KitchenSpoolDispatchType value) => value.wireName;

  @override
  KitchenSpoolDispatchType fromSql(String fromDb) =>
      KitchenSpoolDispatchType.fromWire(fromDb);
}

/// Drift [TypeConverter] persisting the pending server acknowledgement status
/// ([KitchenServerAckStatus]) as its closed wire text.
class KitchenServerAckStatusConverter
    extends TypeConverter<KitchenServerAckStatus, String> {
  const KitchenServerAckStatusConverter();

  @override
  String toSql(KitchenServerAckStatus value) => value.wireName;

  @override
  KitchenServerAckStatus fromSql(String fromDb) =>
      KitchenServerAckStatus.fromWire(fromDb);
}
