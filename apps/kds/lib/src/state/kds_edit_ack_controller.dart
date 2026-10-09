import 'dart:math';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketView, kdsRepositoryProvider;

import 'kds_session.dart';

/// ORDER-EDIT-001D — what one "Got it" tap confirmed: the order and the
/// `up_to_edit_number` it sent. The server stamps EVERY pending edit of the
/// order up to that number (API_CONTRACT §4.46), so a sibling card whose own
/// newest edit is at or below it is covered by the same tap.
@immutable
class KdsEditAckTarget {
  const KdsEditAckTarget(this.orderId, this.upToEditNumber);

  final String orderId;
  final int upToEditNumber;

  @override
  bool operator ==(Object other) =>
      other is KdsEditAckTarget &&
      other.orderId == orderId &&
      other.upToEditNumber == upToEditNumber;

  @override
  int get hashCode => Object.hash(orderId, upToEditNumber);
}

/// ORDER-EDIT-001D — the honest per-card "Got it" state for sent-order edit
/// changes (design §7.2, D-044).
///
/// Keyed by [KdsTicketView.changeAlertKey] (`<ticketId>|e<N>`), never by order
/// id: a per-order key would block card B (edit 2) once card A (edit 1) was
/// tapped. [pending] holds taps in flight OR applied and awaiting the
/// authoritative pull — the card is NEVER hidden locally; the mapper drops the
/// change once the pulled `order_edits` rows carry `kitchen_ack_at`. [failed]
/// holds taps whose last attempt failed; its value is the
/// `local_operation_id` to REUSE on retry, non-null only after an UNKNOWN
/// outcome (D-022: a replay of the same id returns the stored result, so a
/// timed-out-but-applied tap is never counted twice).
class KdsEditAckState {
  const KdsEditAckState({
    this.pending = const <String, KdsEditAckTarget>{},
    this.failed = const <String, String?>{},
  });

  final Map<String, KdsEditAckTarget> pending;
  final Map<String, String?> failed;

  /// Whether a "Got it" in flight (or applied, awaiting the pull) already
  /// covers [ticket]'s change: any pending tap on the SAME order whose number
  /// reaches this card's newest pending edit. A newer edit (a higher number)
  /// is never hidden by an older tap.
  bool isPending(KdsTicketView ticket) {
    final change = ticket.change;
    final orderId = ticket.orderId;
    if (change == null || orderId == null || ticket.requiresAck) return false;
    final upTo = change.upToEditNumber;
    for (final target in pending.values) {
      if (target.orderId == orderId && target.upToEditNumber >= upTo) {
        return true;
      }
    }
    return false;
  }

  /// Whether [ticket]'s last "Got it" failed and nothing newer covers it.
  bool isFailed(KdsTicketView ticket) {
    final key = ticket.changeAlertKey;
    return key != null && failed.containsKey(key) && !isPending(ticket);
  }
}

/// ORDER-EDIT-001D — how one "Got it" ended.
enum KdsEditAckOutcome {
  /// The server stamped the acknowledgement (`acknowledged_count` may be 0
  /// when another KDS confirmed first). The card stays pending until the pull.
  applied,

  /// The order was voided meanwhile (`order_voided`): the void supersedes the
  /// edit and the red card replaces this one on the next pull. Never shown as
  /// a connection failure.
  superseded,

  /// A terminal refusal or an unknown outcome: the card stays, retryable.
  failed,

  /// Nothing was sent (no live session, no change, a red card, or a duplicate
  /// tap while the change is already covered).
  skipped,
}

/// ORDER-EDIT-001D — the result of [KdsEditAckController.acknowledge].
final class KdsEditAckResult {
  const KdsEditAckResult(this.outcome, {this.acknowledgedCount = 0});

  final KdsEditAckOutcome outcome;

  /// The server's `acknowledged_count` on [KdsEditAckOutcome.applied]: how
  /// many pending edits THIS tap stamped. 0 otherwise.
  final int acknowledgedCount;
}

/// ORDER-EDIT-001D — the NARROW `order.edit_ack` sender over the EXISTING KDS
/// transport + PIN/device session (the seam `KdsVoidAckController` uses; no
/// second sync engine, no outbox: "Got it" is online-only, RISK R-007). It
/// parses the per-op result STRICTLY and never mutates the ticket's status or
/// hides the card — the authoritative pull decides (§4.46).
class KdsEditAckController extends Notifier<KdsEditAckState> {
  @override
  KdsEditAckState build() => const KdsEditAckState();

  /// Sends `order.edit_ack {order_id, up_to_edit_number}` for [ticket]'s
  /// newest pending edit. Duplicate taps while covered are no-ops. On
  /// [KdsEditAckOutcome.applied] and [KdsEditAckOutcome.superseded] the key
  /// STAYS pending and the canonical immediate pull runs (best-effort).
  Future<KdsEditAckResult> acknowledge(KdsTicketView ticket) async {
    final transport = ref.read(kdsAuthTransportProvider);
    final session = ref.read(kdsSyncSessionProvider);
    final orderId = ticket.orderId;
    final change = ticket.change;
    final key = ticket.changeAlertKey;
    // No live transport/session (demo / signed out), nothing to confirm, or a
    // red cancellation card (a void supersedes every pending edit): nothing to
    // send and nothing to fake.
    if (transport == null ||
        session == null ||
        orderId == null ||
        change == null ||
        key == null ||
        ticket.requiresAck ||
        state.isPending(ticket)) {
      return const KdsEditAckResult(KdsEditAckOutcome.skipped);
    }
    final upTo = change.upToEditNumber;
    // Reuse the id ONLY after an unknown outcome (D-022 replay); a terminal
    // answer stored null, so a retry after it is a NEW operation.
    final localOperationId = state.failed[key] ?? _uuidV4();
    state = KdsEditAckState(
      pending: {...state.pending, key: KdsEditAckTarget(orderId, upTo)},
      failed: {...state.failed}..remove(key),
    );

    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[
          <String, dynamic>{
            'local_operation_id': localOperationId,
            'operation_type': 'order.edit_ack',
            'target_entity': 'order',
            // MUST equal payload.order_id, or the server rejects the envelope
            // `invalid_payload` before the ledger (API_CONTRACT §4.46).
            'target_id': orderId,
            'client_created_at': DateTime.now().toIso8601String(),
            'payload': <String, dynamic>{
              'order_id': orderId,
              // A JSON integer (the server accepts 1..9 digits only).
              'up_to_edit_number': upTo,
            },
          },
        ],
      });
    } catch (_) {
      _markFailed(key, reuseOperationId: localOperationId);
      return const KdsEditAckResult(KdsEditAckOutcome.failed);
    }

    final op = _matchingOp(raw, localOperationId);
    if (op == null) {
      // A malformed body or no matching op: the outcome is UNKNOWN, so the
      // retry replays the same id.
      _markFailed(key, reuseOperationId: localOperationId);
      return const KdsEditAckResult(KdsEditAckOutcome.failed);
    }
    if (op['status'] == 'applied' && op['ok'] == true) {
      final count = op['acknowledged_count'];
      await _refresh();
      return KdsEditAckResult(
        KdsEditAckOutcome.applied,
        acknowledgedCount: count is int ? count : 0,
      );
    }
    if (op['status'] == 'rejected' && op['error'] == 'order_voided') {
      // The void supersedes the edit: keep the key pending (no failure line —
      // nothing is wrong with the connection) and pull so the red card lands.
      await _refresh();
      return const KdsEditAckResult(KdsEditAckOutcome.superseded);
    }
    // Any other matching op (rejected / conflict / dead / ok false) is a
    // TERMINAL server answer: the retry must be a new operation.
    _markFailed(key, reuseOperationId: null);
    return const KdsEditAckResult(KdsEditAckOutcome.failed);
  }

  /// Best-effort canonical pull — a refresh failure just leaves the regular
  /// poll to converge.
  Future<void> _refresh() async {
    try {
      await ref.read(kdsRepositoryProvider).refresh();
    } catch (_) {}
  }

  void _markFailed(String key, {required String? reuseOperationId}) {
    state = KdsEditAckState(
      pending: {...state.pending}..remove(key),
      failed: {...state.failed, key: reuseOperationId},
    );
  }

  /// Reconciles against the AUTHORITATIVE change keys of a fresh pull: an
  /// entry whose card no longer shows that change (acknowledged here or on
  /// another KDS, or superseded) is dropped, so a long session never
  /// accumulates stale keys. The caller invokes this ONLY on a fresh
  /// `KdsSyncStatus.data` state, with the COMPLETE board's keys.
  void reconcile(Iterable<String> authoritativeChangeAlertKeys) {
    final live = authoritativeChangeAlertKeys.toSet();
    final pending = {
      for (final e in state.pending.entries)
        if (live.contains(e.key)) e.key: e.value,
    };
    final failed = {
      for (final e in state.failed.entries)
        if (live.contains(e.key)) e.key: e.value,
    };
    if (pending.length == state.pending.length &&
        failed.length == state.failed.length) {
      return; // nothing stale — no state churn
    }
    state = KdsEditAckState(pending: pending, failed: failed);
  }

  /// The per-op result echoing [localOperationId], or null for a non-Map
  /// body, a missing/malformed `results` list, or no matching op.
  static Map<dynamic, dynamic>? _matchingOp(
    Object? raw,
    String localOperationId,
  ) {
    if (raw is! Map) return null;
    final results = raw['results'];
    if (results is! List) return null;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOperationId) return r;
    }
    return null;
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

final kdsEditAckControllerProvider =
    NotifierProvider<KdsEditAckController, KdsEditAckState>(
      KdsEditAckController.new,
    );
