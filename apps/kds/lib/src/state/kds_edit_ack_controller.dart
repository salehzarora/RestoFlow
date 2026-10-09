import 'dart:math';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncSession;
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

/// ORDER-EDIT-001D — a change chit OWED by a "Got it" whose outcome is
/// UNKNOWN (a transport throw, or no matching result): the server may have
/// applied the tap and lost only the reply. Once an authoritative pull shows
/// the edits it would have stamped as confirmed there is nothing left to
/// re-tap, so [KdsEditAckController.replayOwedChits] replays the SAME
/// `local_operation_id` (D-022: the server returns the stored result,
/// `acknowledged_count` included) and the chit prints once from [board].
@immutable
class KdsOwedChit {
  const KdsOwedChit({
    required this.orderId,
    required this.upToEditNumber,
    required this.localOperationId,
    required this.session,
    required this.board,
    this.unknownReplays = 0,
  });

  final String orderId;

  /// The `up_to_edit_number` the tap sent: it stamps every pending edit of
  /// [orderId] up to this number.
  final int upToEditNumber;

  /// The operation id the replay reuses.
  final String localOperationId;

  /// The PIN/device session that tapped. A replay runs only under it, so a
  /// confirmation is never attributed to the next person signed in (D-004).
  final SyncSession session;

  /// The board the cook confirmed, copied before the tap.
  final List<KdsTicketView> board;

  /// Replays already answered with an unknown outcome again.
  final int unknownReplays;
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
  KdsEditAckState build() {
    _owed.clear();
    return const KdsEditAckState();
  }

  /// How many times an owed chit is replayed while the answer stays UNKNOWN
  /// (one replay per fresh pull), so a server that never answers is not
  /// re-sent forever.
  static const int _maxUnknownReplays = 3;

  /// ORDER-EDIT-001D: chits owed by unknown-outcome taps, by operation id.
  /// In memory only, like the print watermarks.
  final Map<String, KdsOwedChit> _owed = {};

  /// Operation ids whose push is in flight (a tap or a replay), so a replay
  /// never races the same operation.
  final Set<String> _inFlight = {};

  /// The chits currently owed (diagnostics / tests).
  List<KdsOwedChit> get owedChits => List.unmodifiable(_owed.values);

  /// Sends `order.edit_ack {order_id, up_to_edit_number}` for [ticket]'s
  /// newest pending edit. Duplicate taps while covered are no-ops. On
  /// [KdsEditAckOutcome.applied] and [KdsEditAckOutcome.superseded] the key
  /// STAYS pending and the canonical immediate pull runs (best-effort).
  ///
  /// [confirmedBoard] is the board the cook confirmed: on an UNKNOWN outcome
  /// the tap owes its change chit, recorded with that board for
  /// [replayOwedChits]. Any definitive answer for the operation settles it.
  Future<KdsEditAckResult> acknowledge(
    KdsTicketView ticket, {
    List<KdsTicketView>? confirmedBoard,
  }) async {
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

    void owe() {
      if (confirmedBoard == null) return;
      _owed[localOperationId] = KdsOwedChit(
        orderId: orderId,
        upToEditNumber: upTo,
        localOperationId: localOperationId,
        session: session,
        board: List.unmodifiable(confirmedBoard),
      );
    }

    final Object? raw;
    _inFlight.add(localOperationId);
    try {
      raw = await _push(transport, session, orderId, upTo, localOperationId);
    } catch (_) {
      _markFailed(key, reuseOperationId: localOperationId);
      owe();
      return const KdsEditAckResult(KdsEditAckOutcome.failed);
    } finally {
      _inFlight.remove(localOperationId);
    }

    final op = _matchingOp(raw, localOperationId);
    if (op == null) {
      // A malformed body or no matching op: the outcome is UNKNOWN, so the
      // retry replays the same id.
      _markFailed(key, reuseOperationId: localOperationId);
      owe();
      return const KdsEditAckResult(KdsEditAckOutcome.failed);
    }
    // A definitive answer: any chit this operation owed is settled here (an
    // applied re-tap prints through its own caller).
    _owed.remove(localOperationId);
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

  /// ORDER-EDIT-001D: replays every owed chit whose edits the AUTHORITATIVE
  /// [board] shows confirmed — no card of the order still has a pending edit
  /// numbered at or below the tap's (confirmed by the lost tap itself, or
  /// elsewhere): no card is left to re-tap. The SAME `local_operation_id` is
  /// sent (D-022), so a tap the server applied returns its stored result;
  /// one that never arrived now stamps nothing. A replay therefore never
  /// confirms a change still pending on the board. Returns the chits to
  /// print — those applied with `acknowledged_count > 0` — each once.
  ///
  /// A definitive answer drops the record (count 0 means another display
  /// confirmed first and printed its own; a refusal prints nothing). A
  /// still-unknown answer keeps it for the next fresh pull, at most
  /// [_maxUnknownReplays] times. A record from another PIN session is
  /// dropped unsent. The caller invokes this ONLY on a fresh
  /// `KdsSyncStatus.data` state, with the COMPLETE board.
  Future<List<KdsOwedChit>> replayOwedChits(List<KdsTicketView> board) async {
    if (_owed.isEmpty) return const <KdsOwedChit>[];
    final transport = ref.read(kdsAuthTransportProvider);
    final session = ref.read(kdsSyncSessionProvider);
    if (transport == null || session == null) return const <KdsOwedChit>[];
    bool stillPending(KdsOwedChit owed) {
      for (final t in board) {
        final change = t.change;
        if (t.orderId != owed.orderId || change == null) continue;
        for (final n in change.orderPendingEditNumbers) {
          if (n <= owed.upToEditNumber) return true;
        }
        for (final e in change.pendingEdits) {
          if (e.editNumber <= owed.upToEditNumber) return true;
        }
      }
      return false;
    }

    final due = <KdsOwedChit>[];
    for (final owed in List.of(_owed.values)) {
      if (owed.session != session) {
        _owed.remove(owed.localOperationId);
      } else if (!stillPending(owed) &&
          !_inFlight.contains(owed.localOperationId)) {
        due.add(owed);
      }
    }
    final toPrint = <KdsOwedChit>[];
    for (final owed in due) {
      final id = owed.localOperationId;
      Map<dynamic, dynamic>? op;
      _inFlight.add(id);
      try {
        op = _matchingOp(
          await _push(
            transport,
            session,
            owed.orderId,
            owed.upToEditNumber,
            id,
          ),
          id,
        );
      } catch (_) {
        op = null;
      } finally {
        _inFlight.remove(id);
      }
      // A re-tap settled (or re-recorded) this operation meanwhile.
      if (!identical(_owed[id], owed)) continue;
      if (op == null) {
        final replays = owed.unknownReplays + 1;
        if (replays >= _maxUnknownReplays) {
          _owed.remove(id);
        } else {
          _owed[id] = KdsOwedChit(
            orderId: owed.orderId,
            upToEditNumber: owed.upToEditNumber,
            localOperationId: id,
            session: owed.session,
            board: owed.board,
            unknownReplays: replays,
          );
        }
        continue;
      }
      _owed.remove(id);
      final count = op['acknowledged_count'];
      if (op['status'] == 'applied' &&
          op['ok'] == true &&
          count is int &&
          count > 0) {
        toPrint.add(owed);
      }
    }
    return toPrint;
  }

  /// The canonical single-op `order.edit_ack` push (API_CONTRACT §4.46).
  static Future<Object?> _push(
    SyncRpcTransport transport,
    SyncSession session,
    String orderId,
    int upTo,
    String localOperationId,
  ) => transport.invoke('sync_push', <String, dynamic>{
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
