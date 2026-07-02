import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

import 'kds_session.dart';

/// Persists a LIVE-board kitchen advance as an `order.status` operation through
/// `public.sync_push` (sprint; DECISION D-010/D-022 — the same offline sync
/// pipeline the POS uses, with a client-generated `local_operation_id`).
///
/// Fire-and-forget by design: the local board already advanced for instant
/// feedback, and the next `sync_pull` re-syncs it to the SERVER's state — so a
/// rejected/failed push self-corrects visually within one poll (the server
/// always wins; nothing is ever faked). Kitchen pushes carry NO money (T-003).
class KdsStatusPusher {
  KdsStatusPusher({
    required SyncRpcTransport transport,
    required SyncSession session,
    String Function()? generateOperationId,
  }) : _transport = transport,
       _session = session,
       _newOperationId = generateOperationId ?? _uuidV4;

  final SyncRpcTransport _transport;
  final SyncSession _session;
  final String Function() _newOperationId;

  /// Board ticket status -> the frozen order status wire value (D-018 §1.1).
  /// `bumped` = the kitchen is done with the order (`served`).
  static String? orderStatusFor(KitchenTicketStatus to) => switch (to) {
    KitchenTicketStatus.acknowledged => 'accepted',
    KitchenTicketStatus.inPreparation => 'preparing',
    KitchenTicketStatus.ready => 'ready',
    KitchenTicketStatus.bumped => 'served',
    // Never pushed from the board (cancellation is not a kitchen action).
    KitchenTicketStatus.newTicket || KitchenTicketStatus.cancelled => null,
  };

  /// Pushes the advance for [ticket] (no-op for demo tickets without an
  /// [KdsTicketView.orderId] or unmapped statuses). Errors are swallowed —
  /// the next poll re-syncs the board to the authoritative server state.
  Future<void> push(KdsTicketView ticket, KitchenTicketStatus to) async {
    final orderId = ticket.orderId;
    final newStatus = orderStatusFor(to);
    if (orderId == null || newStatus == null) return;
    try {
      await _transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': _session.pinSessionId,
        'p_device_id': _session.deviceId,
        'p_operations': <dynamic>[
          <String, dynamic>{
            'local_operation_id': _newOperationId(),
            'operation_type': 'order.status',
            'target_entity': 'order',
            'target_id': orderId,
            'client_created_at': DateTime.now().toIso8601String(),
            'payload': <String, dynamic>{
              'order_id': orderId,
              'new_status': newStatus,
            },
          },
        ],
      });
    } catch (_) {
      // Swallowed on purpose (see class doc): the poll self-corrects the board.
    }
  }

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int index) => bytes[index].toRadixString(16).padLeft(2, '0');
    return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
        '${hex(4)}${hex(5)}-'
        '${hex(6)}${hex(7)}-'
        '${hex(8)}${hex(9)}-'
        '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
  }
}

/// The live-board status pusher, or null when there is no real transport +
/// session (demo mode / not signed in) — the board is then local-only.
final kdsStatusPusherProvider = Provider<KdsStatusPusher?>((ref) {
  final transport = ref.watch(kdsAuthTransportProvider);
  final session = ref.watch(kdsSyncSessionProvider);
  if (transport == null || session == null) return null;
  return KdsStatusPusher(transport: transport, session: session);
});
