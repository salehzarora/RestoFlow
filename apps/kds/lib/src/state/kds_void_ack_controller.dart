import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show kdsRepositoryProvider;

import 'kds_session.dart';

/// PSC-001D — the honest per-order acknowledgement state for the red
/// cancellation cards.
///
/// [pending] holds order ids whose `order.void_ack` is in flight OR already
/// applied and awaiting the authoritative pull (the card is NEVER hidden
/// locally — the mapper removes it only once the pulled row carries
/// `kitchen_ack_at`, so two devices and a restarted app converge on the same
/// server truth). [failed] holds order ids whose last attempt failed — the
/// card stays visible with a localized failure line and remains retryable.
class KdsVoidAckState {
  const KdsVoidAckState({
    this.pending = const <String>{},
    this.failed = const <String>{},
  });

  final Set<String> pending;
  final Set<String> failed;
}

/// PSC-001D — a NARROW acknowledgement sender over the EXISTING KDS transport
/// + PIN/device session (the same seam `KdsStatusPusher` uses; no second sync
/// engine, no outbox). Unlike the fire-and-forget status pusher, this parses
/// the per-op result HONESTLY: a typed rejection or a transport failure marks
/// the order failed (card stays, retry offered) and never fakes success.
class KdsVoidAckController extends Notifier<KdsVoidAckState> {
  @override
  KdsVoidAckState build() => const KdsVoidAckState();

  /// Sends `order.void_ack` for [orderId]. Duplicate taps while in flight are
  /// no-ops. On success (including the server's idempotent
  /// `already_acknowledged` replay) the id STAYS pending and the canonical
  /// immediate pull is triggered — the mapper clears the card when the
  /// authoritative row returns acknowledged.
  Future<void> acknowledge(String orderId) async {
    final transport = ref.read(kdsAuthTransportProvider);
    final session = ref.read(kdsSyncSessionProvider);
    // No live transport/session (demo / signed out): nothing to send and
    // nothing to fake — the button is not rendered in that mode anyway.
    if (transport == null || session == null) return;
    if (state.pending.contains(orderId)) return;
    state = KdsVoidAckState(
      pending: {...state.pending, orderId},
      failed: {...state.failed}..remove(orderId),
    );

    final localOperationId = _uuidV4();
    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[
          <String, dynamic>{
            'local_operation_id': localOperationId,
            'operation_type': 'order.void_ack',
            'target_entity': 'order',
            'target_id': orderId,
            'client_created_at': DateTime.now().toIso8601String(),
            'payload': <String, dynamic>{'order_id': orderId},
          },
        ],
      });
    } catch (_) {
      _markFailed(orderId);
      return;
    }

    if (!_appliedOk(raw, localOperationId)) {
      _markFailed(orderId);
      return;
    }
    // Applied (first ack or the idempotent already-acknowledged replay): keep
    // the id pending and pull NOW so the red card clears from the
    // AUTHORITATIVE row rather than a local guess. Best-effort — a refresh
    // failure just leaves the regular 5s poll to converge.
    try {
      await ref.read(kdsRepositoryProvider).refresh();
    } catch (_) {}
  }

  void _markFailed(String orderId) {
    state = KdsVoidAckState(
      pending: {...state.pending}..remove(orderId),
      failed: {...state.failed, orderId},
    );
  }

  /// Fail-closed per-op result parse (the POS table-operations convention):
  /// only an explicit `status == 'applied'` with `ok != false` counts.
  static bool _appliedOk(Object? raw, String localOperationId) {
    if (raw is! Map) return false;
    final results = raw['results'];
    if (results is! List) return false;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOperationId) {
        return r['status'] == 'applied' && r['ok'] != false;
      }
    }
    return false;
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

final kdsVoidAckControllerProvider =
    NotifierProvider<KdsVoidAckController, KdsVoidAckState>(
      KdsVoidAckController.new,
    );
