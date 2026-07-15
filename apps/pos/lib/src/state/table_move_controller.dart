import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/demo_order_snapshots.dart';
import '../data/ids.dart';
import '../data/table_move_repository.dart';
import 'order_sync_controller.dart' show orderSnapshotRepositoryProvider;
import 'pos_session.dart';

/// RESTAURANT-OPERATIONS-V1-001: the table-move repository seam. Selects by
/// client runtime mode (M7): the demo store (which records the move on the
/// demo snapshot repository so the Orders Centre reflects it through the SAME
/// targeted-refresh path the real app uses), or the real repository posting an
/// `order.table_move` op to `public.sync_push` over the shared transport +
/// PIN/device session — fail-closed without either. Tests can override this
/// provider, [runtimeConfigProvider], [posAuthTransportProvider], or
/// [posSyncSessionProvider] to force a mode.
final posMoveTableRepositoryProvider = Provider<MoveTableRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) {
    final snapshots = ref.watch(orderSnapshotRepositoryProvider);
    return DemoMoveTableStore(
      snapshots is DemoOrderSnapshotRepository ? snapshots : null,
    );
  }
  return RealMoveTableRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
    ref.watch(clientIdGeneratorProvider),
  );
});
