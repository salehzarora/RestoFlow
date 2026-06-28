import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/kitchen_order.dart';
import '../data/kitchen_orders_repository.dart';

/// Placeholder recall context (RF-117). Not user-facing chrome, not persisted,
/// not a real audit row — the real audited recall is server-side (RF-053).
const String _recallReason = 'recalled from KDS';
const String _recallActor = 'kds-device';

/// Drives the KDS kitchen board (RF-117): loads the demo kitchen feed and
/// applies status actions through the frozen [KitchenTicketStateMachine]
/// (DECISION D-018). In-memory demo only — no backend, no realtime; each action
/// would map to the `bump_kitchen_item` RPC (API_CONTRACT §4.4).
class KitchenOrdersController extends AsyncNotifier<List<KitchenOrderTicket>> {
  @override
  Future<List<KitchenOrderTicket>> build() =>
      ref.watch(kitchenOrdersRepositoryProvider).loadOrders();

  KitchenOrderTicket? _byId(String ticketId) {
    for (final t in state.value ?? const <KitchenOrderTicket>[]) {
      if (t.ticketId == ticketId) return t;
    }
    return null;
  }

  void _setStatus(String ticketId, KitchenTicketStatus status) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([
      for (final t in list)
        if (t.ticketId == ticketId) t.copyWith(status: status) else t,
    ]);
  }

  /// Start preparing: `new`/`acknowledged → in_preparation` (each edge is
  /// validated by the state machine).
  void start(String ticketId) {
    final ticket = _byId(ticketId);
    if (ticket == null) return;
    var status = ticket.status;
    if (status == KitchenTicketStatus.newTicket) {
      status = KitchenTicketStateMachine.transition(
        status,
        KitchenTicketStatus.acknowledged,
      );
    }
    if (status == KitchenTicketStatus.acknowledged) {
      status = KitchenTicketStateMachine.transition(
        status,
        KitchenTicketStatus.inPreparation,
      );
    }
    _setStatus(ticketId, status);
  }

  /// `in_preparation → ready`.
  void markReady(String ticketId) =>
      _advance(ticketId, KitchenTicketStatus.ready);

  /// `ready → bumped` (Complete / cleared off the active board).
  void complete(String ticketId) =>
      _advance(ticketId, KitchenTicketStatus.bumped);

  /// Recall a bumped ticket back to `in_preparation` (audited; demo placeholder).
  void recall(String ticketId) {
    final ticket = _byId(ticketId);
    if (ticket == null || ticket.status != KitchenTicketStatus.bumped) return;
    final event = KitchenTicketStateMachine.recall(
      kitchenTicketId: ticket.ticketId,
      from: ticket.status,
      reason: _recallReason,
      actorId: _recallActor,
    );
    _setStatus(ticketId, event.toStatus);
  }

  void _advance(String ticketId, KitchenTicketStatus to) {
    final ticket = _byId(ticketId);
    if (ticket == null) return;
    _setStatus(
      ticketId,
      KitchenTicketStateMachine.transition(ticket.status, to),
    );
  }
}

/// The kitchen-orders repository seam (RF-117). In demo mode - the DEFAULT
/// (`RESTOFLOW_DEMO_MODE` defaults to true) - this is the in-memory
/// [DemoKitchenOrdersStore]. In real mode the live kitchen feed runs through the
/// injected `KdsSyncSource` (`sync_pull`, RF-063) on the `KdsSyncedHome` path,
/// NOT this seam; so real mode resolves to a fail-closed
/// [RealKitchenOrdersRepository] skeleton that throws rather than serve demo
/// tickets under a real-mode label. Tests can still override this provider.
final kitchenOrdersRepositoryProvider = Provider<KitchenOrdersRepository>((
  ref,
) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return DemoKitchenOrdersStore();
  return const RealKitchenOrdersRepository();
});

/// The KDS kitchen-orders controller (the demo board's state + actions).
final kitchenOrdersControllerProvider =
    AsyncNotifierProvider<KitchenOrdersController, List<KitchenOrderTicket>>(
      KitchenOrdersController.new,
    );
