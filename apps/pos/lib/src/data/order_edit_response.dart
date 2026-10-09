/// ORDER-EDIT-001E — what a `sync_push` response PROVES about one `order.edit`
/// operation (API_CONTRACT §4.45.5 / §4.45.6), classified the way the Add-items
/// classifier is (`AdditionController.classifyAdditionResponse`).
///
/// PURE: no widgets, no providers, no I/O.
///
/// Only three things are definitive:
///
///  * a COMPLETE applied envelope for THIS operation — the edit exists, the
///    identity is spent, and the operation must never be dispatched again;
///  * an ALLOWLISTED typed refusal ([kOrderEditRefusalCodes]) — `app.edit_order`
///    decides every refusal before its first write, so nothing was written and
///    the identity may be released;
///  * a RAISE that `sync_push` ledgered as `rejected` with its sqlstate — the
///    operation was rolled back whole and the ledger row is terminal, so a
///    replay of the same identity returns the same verdict forever.
///
/// A `conflict` (the identity was used on another order, or under another
/// payload) is a verdict too, but not a resolvable one: it needs a person.
/// EVERYTHING ELSE is outcome-unknown — a `dead` row, a code this build has
/// never seen, a malformed or truncated answer, our operation missing from the
/// results — and an operation whose outcome is unknown keeps its identity and
/// its frozen payload, because the server may already own the edit.
///
/// There is no replay flag: `sync_push` overwrites `idempotency_replay` on the
/// first application, and a replay is handled exactly like a first answer.
library;

import 'order_edit_read_model.dart' show PosKitchenChannel;

/// The wire operation type. A result row under any other type is not this
/// operation's verdict.
const String kOrderEditOperationType = 'order.edit';

/// The typed refusals `app.edit_order` RETURNs (§4.45.6, confirmed against
/// `20261008170100_order_edit_001a_edit_order.sql`), plus `sync_push`'s own
/// identity-hardening `invalid_payload`. Each is decided before the first
/// write, so the operation provably changed nothing.
///
/// `const`, so nothing can widen the set that decides which answers free an
/// idempotency identity — an unknown code is never evidence that nothing
/// happened.
const Set<String> kOrderEditRefusalCodes = <String>{
  // Step 1–2: device, role and payload shape.
  'invalid_device_type',
  'permission_denied',
  'invalid_payload',
  'no_changes',
  'too_many_changes',
  'duplicate_line_reference',
  'expected_totals_required',
  // Step 5: order gates.
  'feature_disabled',
  'order_not_editable',
  'order_already_settled',
  'kitchen_mode_changed',
  // Step 6 / 6a: line checks, authority and reason.
  'line_changed',
  'line_has_discount',
  'legacy_line_not_editable',
  'reason_required',
  // Step 8: new-line validation.
  'item_unavailable',
  'modifier_option_not_in_scope',
  'modifier_prep_snapshot_stale',
  'invalid_item_payload',
  // Steps 10–11: never empty, and the money plan.
  'edit_would_empty_order',
  'invalid_discount',
  'tax_mode_unsupported',
  'totals_mismatch',
};

/// What a response proves about one edit operation.
enum OrderEditOutcomeKind {
  /// A complete authoritative applied envelope.
  applied,

  /// An allowlisted typed refusal; nothing was written.
  refused,

  /// A RAISE ledgered terminally as `rejected`; nothing was written.
  rejected,

  /// The identity exists server-side under another order or payload.
  conflict,

  /// Proves nothing — the server may or may not own the edit.
  unknown,
}

/// The class of a RAISE that `sync_push` ledgered as `rejected` (§4.45.6).
enum OrderEditRejection {
  /// 42501 from `app.edit_order`: a nonexistent or foreign order (the
  /// anti-oracle) — on this POS, an order whose submit the server never took.
  orderNotFound,

  /// The membership or the device was revoked (`revoked_employee` /
  /// `revoked_device`).
  notAllowed,

  /// 23514: the paper change slip exceeds the dispatch ledger's cap.
  slipTooLarge,

  /// Any other raised failure.
  invalid,
}

/// The paper-channel `order_edit` dispatch, born claimed by this POS
/// (§4.45.9). Carried for ORDER-EDIT-001F; nothing in 001E acts on it.
class OrderEditKitchenDispatch {
  const OrderEditKitchenDispatch({required this.id, this.claimExpiresAt});

  final String id;
  final DateTime? claimExpiresAt;
}

/// The applied envelope's facts this POS relies on.
class OrderEditApplied {
  const OrderEditApplied({
    required this.orderEditId,
    required this.editNumber,
    required this.revision,
    required this.kitchenChannel,
    required this.kitchenAckRequired,
    this.newRoundId,
    this.newRoundNumber,
    this.remakeChangeCount = 0,
    this.kitchenDispatch,
    this.orderStatus,
    this.autoCompleted = false,
  });

  final String orderEditId;

  /// "Change N".
  final int editNumber;

  /// The order's revision after the edit.
  final int revision;
  final PosKitchenChannel kitchenChannel;
  final bool kitchenAckRequired;
  final String? newRoundId;
  final int? newRoundNumber;

  /// How many changes the server marked `remake` (a count of changes, not of
  /// dishes — the envelope has no dish count; the toast uses the plan's).
  final int remakeChangeCount;
  final OrderEditKitchenDispatch? kitchenDispatch;
  final String? orderStatus;
  final bool autoCompleted;
}

/// The server's own figures, returned with `totals_mismatch`.
class OrderEditServerTotals {
  const OrderEditServerTotals({
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.grandMinor,
  });

  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int grandMinor;
}

/// One item `item_unavailable` names.
class OrderEditRefusedItem {
  const OrderEditRefusedItem({this.menuItemId, this.name, this.reason});

  final String? menuItemId;
  final String? name;
  final String? reason;
}

/// A typed refusal with the extras the POS acts on.
class OrderEditRefusal {
  const OrderEditRefusal({
    required this.code,
    this.detail,
    this.staleIds = const <String>[],
    this.totals,
    this.items = const <OrderEditRefusedItem>[],
    this.orderStatus,
  });

  final String code;

  /// The detail token of an error / detail pair (`removal_not_permitted`,
  /// `finished_food_needs_manager`, `full_comp_permission_required`,
  /// `discount_exceeds_order_total`, an `invalid_item_payload` reason).
  final String? detail;

  /// `line_changed`: the referenced lines that are no longer live.
  final List<String> staleIds;

  /// `totals_mismatch`: the server's figures.
  final OrderEditServerTotals? totals;

  /// `item_unavailable`: the items that cannot be sold now.
  final List<OrderEditRefusedItem> items;

  /// `order_not_editable`: the order's current status.
  final String? orderStatus;
}

/// The classified outcome. [reason] is a SAFE classification code — never raw
/// backend text — fit for the journal and for choosing a message.
class OrderEditOutcome {
  const OrderEditOutcome.applied(OrderEditApplied this.applied)
    : kind = OrderEditOutcomeKind.applied,
      reason = null,
      refusal = null,
      rejection = null;

  OrderEditOutcome.refused(OrderEditRefusal this.refusal)
    : kind = OrderEditOutcomeKind.refused,
      reason = refusal.code,
      applied = null,
      rejection = null;

  const OrderEditOutcome.rejected(OrderEditRejection this.rejection)
    : kind = OrderEditOutcomeKind.rejected,
      reason = 'rejected',
      applied = null,
      refusal = null;

  const OrderEditOutcome.conflict()
    : kind = OrderEditOutcomeKind.conflict,
      reason = 'conflict',
      applied = null,
      refusal = null,
      rejection = null;

  const OrderEditOutcome.unknown(String this.reason)
    : kind = OrderEditOutcomeKind.unknown,
      applied = null,
      refusal = null,
      rejection = null;

  final OrderEditOutcomeKind kind;
  final String? reason;
  final OrderEditApplied? applied;
  final OrderEditRefusal? refusal;
  final OrderEditRejection? rejection;

  /// The operation provably changed nothing and its identity is spent — the
  /// journal record may be closed and a NEW attempt minted.
  bool get isDefinitiveNo =>
      kind == OrderEditOutcomeKind.refused ||
      kind == OrderEditOutcomeKind.rejected;
}

/// THE ONE classification of a `sync_push` response for the edit operation
/// [localOperationId] on [orderId].
///
/// APPLIED requires all of: the matching operation id and type, status
/// `applied`, `ok` exactly true, the same `order_id`, a non-blank
/// `order_edit_id`, an integer `edit_number` ≥ 1, an integer `revision`, a
/// `kitchen_channel` of `kds` / `paper` and a boolean `kitchen_ack_required`.
/// Anything less is unknown: an applied answer that cannot be verified must
/// neither be re-sent nor be cleaned up.
OrderEditOutcome classifyOrderEditResponse(
  Object? raw, {
  required String localOperationId,
  required String orderId,
}) {
  // ONE try/catch around the whole boundary: the rows come from a network
  // decode, and a hostile shape can raise more than FormatException.
  try {
    if (raw is! Map)
      return const OrderEditOutcome.unknown('malformed_envelope');
    final results = raw['results'];
    if (results is! List) {
      return const OrderEditOutcome.unknown('missing_results');
    }
    for (final r in results) {
      if (r is! Map) continue;
      if (r['local_operation_id'] != localOperationId) continue;
      if (r['operation_type'] != kOrderEditOperationType) {
        return const OrderEditOutcome.unknown('operation_type_mismatch');
      }
      final status = r['status'];
      if (status == 'applied') return _applied(r, orderId);
      if (status == 'rejected' || status == 'conflict') {
        final error = r['error'];
        final code = error is String ? error.trim() : '';
        if (code.isEmpty) {
          return const OrderEditOutcome.unknown('refusal_without_code');
        }
        if (status == 'conflict' || code == 'conflict') {
          // 40001 (the identity was used on another order) or a fingerprint
          // mismatch: never a second edit, never resolvable by retrying.
          return const OrderEditOutcome.conflict();
        }
        if (code == 'rejected') return _rejected(r);
        if (!kOrderEditRefusalCodes.contains(code)) {
          return const OrderEditOutcome.unknown('unknown_refusal_code');
        }
        return OrderEditOutcome.refused(_refusal(code, r));
      }
      if (status == 'dead') {
        // Retry exhaustion with no recorded server verdict.
        return const OrderEditOutcome.unknown('dead_no_server_verdict');
      }
      return const OrderEditOutcome.unknown('unknown_status');
    }
    return const OrderEditOutcome.unknown('operation_absent');
  } catch (_) {
    return const OrderEditOutcome.unknown('unreadable_response');
  }
}

OrderEditOutcome _applied(Map<dynamic, dynamic> r, String orderId) {
  if (r['ok'] != true) return const OrderEditOutcome.unknown('applied_not_ok');
  final resultOrderId = r['order_id'];
  if (resultOrderId is! String || resultOrderId != orderId) {
    return const OrderEditOutcome.unknown('target_order_mismatch');
  }
  final editIdRaw = r['order_edit_id'];
  final editId = editIdRaw is String ? editIdRaw.trim() : '';
  if (editId.isEmpty) {
    return const OrderEditOutcome.unknown('applied_without_edit_id');
  }
  final editNumber = r['edit_number'];
  if (editNumber is! int || editNumber < 1) {
    return const OrderEditOutcome.unknown('applied_without_edit_number');
  }
  final revision = r['revision'];
  if (revision is! int) {
    return const OrderEditOutcome.unknown('applied_without_revision');
  }
  final channel = PosKitchenChannel.fromWire(r['kitchen_channel']);
  if (channel == null) {
    return const OrderEditOutcome.unknown('applied_without_kitchen_channel');
  }
  final ackRequired = r['kitchen_ack_required'];
  if (ackRequired is! bool) {
    return const OrderEditOutcome.unknown('applied_without_ack_flag');
  }
  // Optional facts: tolerant, because demanding a field 001E does not act on
  // would turn harmless shape drift into a permanently stuck edit.
  final changes = r['changes'];
  var remakes = 0;
  if (changes is List) {
    for (final c in changes) {
      if (c is Map && c['remake'] == true) remakes++;
    }
  }
  final dispatchRaw = r['kitchen_dispatch'];
  OrderEditKitchenDispatch? dispatch;
  if (dispatchRaw is Map) {
    final id = _nonBlank(dispatchRaw['id']);
    if (id != null) {
      final expires = dispatchRaw['claim_expires_at'];
      dispatch = OrderEditKitchenDispatch(
        id: id,
        claimExpiresAt: expires is String ? DateTime.tryParse(expires) : null,
      );
    }
  }
  final roundNumber = r['new_round_number'];
  return OrderEditOutcome.applied(
    OrderEditApplied(
      orderEditId: editId,
      editNumber: editNumber,
      revision: revision,
      kitchenChannel: channel,
      kitchenAckRequired: ackRequired,
      newRoundId: _nonBlank(r['new_round_id']),
      newRoundNumber: roundNumber is int ? roundNumber : null,
      remakeChangeCount: remakes,
      kitchenDispatch: dispatch,
      orderStatus: _nonBlank(r['order_status']),
      autoCompleted: r['auto_completed'] == true,
    ),
  );
}

OrderEditOutcome _rejected(Map<dynamic, dynamic> r) {
  final detail = r['detail'];
  if (detail == 'revoked_employee' || detail == 'revoked_device') {
    return const OrderEditOutcome.rejected(OrderEditRejection.notAllowed);
  }
  return OrderEditOutcome.rejected(switch (r['sqlstate']) {
    '42501' => OrderEditRejection.orderNotFound,
    '23514' => OrderEditRejection.slipTooLarge,
    _ => OrderEditRejection.invalid,
  });
}

OrderEditRefusal _refusal(String code, Map<dynamic, dynamic> r) {
  final staleRaw = r['stale_ids'];
  final itemsRaw = r['items'];
  final totalsRaw = r['totals'];
  OrderEditServerTotals? totals;
  if (totalsRaw is Map) {
    final sub = totalsRaw['subtotal_minor'];
    final disc = totalsRaw['discount_total_minor'];
    final tax = totalsRaw['tax_total_minor'];
    final grand = totalsRaw['grand_total_minor'];
    if (sub is int && disc is int && tax is int && grand is int) {
      totals = OrderEditServerTotals(
        subtotalMinor: sub,
        discountMinor: disc,
        taxMinor: tax,
        grandMinor: grand,
      );
    }
  }
  return OrderEditRefusal(
    code: code,
    detail: _nonBlank(r['detail']),
    staleIds: [
      if (staleRaw is List)
        for (final id in staleRaw)
          if (_nonBlank(id) case final s?) s,
    ],
    totals: totals,
    items: [
      if (itemsRaw is List)
        for (final i in itemsRaw)
          if (i is Map)
            OrderEditRefusedItem(
              menuItemId: _nonBlank(i['menu_item_id']),
              name: _nonBlank(i['name']),
              reason: _nonBlank(i['reason']),
            ),
    ],
    orderStatus: _nonBlank(r['order_status']),
  );
}

String? _nonBlank(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;
