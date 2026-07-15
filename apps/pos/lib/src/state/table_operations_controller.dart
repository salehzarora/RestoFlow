import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/ids.dart';
import '../data/table_operations_repository.dart';
import 'pos_session.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — the DEMO table-operations overlay.
///
/// The demo tables are seeded, so a demo manual-status change or link/unlink is
/// represented as an in-memory overlay of `tableId -> manual status` +
/// `tableId -> groupId`. [DemoTablesStore] applies it (via the repository seam),
/// so a demo cashier's floor control is HONESTLY reflected (no fake success). Real
/// mode never uses this — it re-reads `pos_tables`.
class DemoTableOps {
  const DemoTableOps({this.manualStatus = const {}, this.groupOf = const {}});

  /// tableId -> manual status ('available'|'reserved'|'occupied'|'out_of_service').
  final Map<String, String> manualStatus;

  /// tableId -> active group id.
  final Map<String, String> groupOf;
}

class DemoTableOpsController extends Notifier<DemoTableOps> {
  int _groupSeq = 0;

  @override
  DemoTableOps build() => const DemoTableOps();

  void setStatus(String tableId, String status) {
    state = DemoTableOps(
      manualStatus: <String, String>{...state.manualStatus, tableId: status},
      groupOf: state.groupOf,
    );
  }

  void link(String a, String b) {
    if (a == b) return;
    final ga = state.groupOf[a];
    final gb = state.groupOf[b];
    if (ga != null && gb != null && ga != gb)
      return; // different groups: no merge
    final go = <String, String>{...state.groupOf};
    if (ga != null && gb != null) {
      // already same group -> no-op
    } else if (ga != null) {
      go[b] = ga;
    } else if (gb != null) {
      go[a] = gb;
    } else {
      final g = 'demo-group-${_groupSeq++}';
      go[a] = g;
      go[b] = g;
    }
    state = DemoTableOps(manualStatus: state.manualStatus, groupOf: go);
  }

  void unlink(String tableId) {
    final g = state.groupOf[tableId];
    if (g == null) return;
    final go = <String, String>{...state.groupOf}
      ..removeWhere((_, v) => v == g);
    state = DemoTableOps(manualStatus: state.manualStatus, groupOf: go);
  }
}

final demoTableOpsProvider =
    NotifierProvider<DemoTableOpsController, DemoTableOps>(
      DemoTableOpsController.new,
    );

/// DEMO table operations: write to the in-memory overlay (honest demo success).
class DemoTableOperationsRepository implements TableOperationsRepository {
  DemoTableOperationsRepository(this._ref);
  final Ref _ref;

  @override
  Future<void> setStatus({
    required String tableId,
    required String status,
  }) async =>
      _ref.read(demoTableOpsProvider.notifier).setStatus(tableId, status);

  @override
  Future<void> link({
    required String tableIdA,
    required String tableIdB,
  }) async => _ref.read(demoTableOpsProvider.notifier).link(tableIdA, tableIdB);

  @override
  Future<void> unlink({required String tableId}) async =>
      _ref.read(demoTableOpsProvider.notifier).unlink(tableId);
}

/// The table-operations write seam: demo overlay vs the real sync_push path.
final tableOperationsRepositoryProvider = Provider<TableOperationsRepository>((
  ref,
) {
  if (ref.watch(runtimeConfigProvider).isDemoMode) {
    return DemoTableOperationsRepository(ref);
  }
  return RealTableOperationsRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
    ref.watch(clientIdGeneratorProvider),
  );
});
