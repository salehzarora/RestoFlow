import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

import 'kds_repository.dart';
import 'kds_view_state.dart';

/// The injected sync source (RF-063). MUST be overridden at the app root with a
/// concrete [KdsSyncSource] (e.g. a `KdsSyncCoordinator` built from an
/// authenticated client + session). Left unoverridden it throws — the app shell
/// falls back to the local fixture instead of constructing one (approved
/// decision A1: no login/pairing/PIN bootstrap is built here).
final kdsSyncSourceProvider = Provider<KdsSyncSource>((ref) {
  throw UnimplementedError(
    'kdsSyncSourceProvider must be overridden with a KdsSyncSource (RF-063).',
  );
});

/// The KDS repository, built from the injected source. Disposed with the scope.
final kdsRepositoryProvider = Provider<KdsRepository>((ref) {
  final source = ref.watch(kdsSyncSourceProvider);
  final repo = KdsRepository(source);
  ref.onDispose(repo.dispose);
  return repo;
});

/// The OPTIONAL realtime invalidation source (RF-058). Defaults to null —
/// override at the app root with a `RealtimeInvalidationSource` when a realtime
/// scope (org/branch) is available. When null, the KDS is polling-only.
final kdsInvalidationSourceProvider = Provider<InvalidationSource?>(
  (ref) => null,
);

/// The KDS view-state stream the screen watches. Starting is idempotent.
final kdsViewStateProvider = StreamProvider.autoDispose<KdsViewState>((ref) {
  final repo = ref.watch(kdsRepositoryProvider);
  // Fire-and-forget: begin the initial pull + polling. The coordinator guards
  // against double-start, so a provider rebuild is safe.
  repo.start();

  // RF-058: if a realtime source is injected, bridge its hints to refresh() on
  // top of polling. Realtime is purely additive — polling remains the source of
  // truth, so a null source (or a realtime drop) just means polling-only.
  final invalidationSource = ref.watch(kdsInvalidationSourceProvider);
  if (invalidationSource != null) {
    final bridge = KdsRealtimeBridge(
      source: invalidationSource,
      coordinator: ref.watch(kdsSyncSourceProvider),
    );
    bridge.start();
    ref.onDispose(bridge.dispose);
  }

  return repo.viewStates;
});
