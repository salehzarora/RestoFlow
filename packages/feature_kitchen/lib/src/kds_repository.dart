import 'dart:async';

import 'package:restoflow_sync/restoflow_sync.dart';

import 'kds_ticket_mapper.dart';
import 'kds_view_state.dart';

/// Bridges the pull-only sync coordinator to the KDS UI (RF-063).
///
/// It owns no networking and no business state of its own: it observes a
/// [KdsSyncSource] and projects each [KdsSyncState] into a [KdsViewState] by
/// running the (money-free) [KdsTicketMapper]. Start/refresh/dispose delegate to
/// the source.
class KdsRepository {
  KdsRepository(this._source);

  final KdsSyncSource _source;

  /// The current projected view state.
  KdsViewState get viewState => _toViewState(_source.state);

  /// A stream of view states that first replays the current state, then
  /// forwards each subsequent sync state (seeded inside `onListen` so the
  /// initial value is never missed on a broadcast source).
  Stream<KdsViewState> get viewStates {
    late StreamController<KdsViewState> controller;
    StreamSubscription<KdsSyncState>? sub;
    controller = StreamController<KdsViewState>(
      onListen: () {
        controller.add(_toViewState(_source.state));
        sub = _source.states.listen(
          (s) => controller.add(_toViewState(s)),
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );
    return controller.stream;
  }

  /// Begin syncing (idempotent — the coordinator guards re-entry).
  Future<void> start() => _source.start();

  /// Trigger an immediate pull.
  Future<void> refresh() => _source.refresh();

  /// PILOT-OPERATIONS-CORRECTIONS-001: recover after an app foreground/resume
  /// (re-evaluate reachability, un-latch a transient terminal stop, pull fresh).
  Future<void> resume() => _source.resume();

  /// Release the underlying source.
  Future<void> dispose() => _source.dispose();

  KdsViewState _toViewState(KdsSyncState s) {
    return KdsViewState(
      status: s.status,
      tickets: KdsTicketMapper.map(
        orders: s.rowsFor('orders'),
        orderItems: s.rowsFor('order_items'),
        modifiers: s.rowsFor('order_item_modifiers'),
        tables: s.rowsFor('tables'),
      ),
    );
  }
}
