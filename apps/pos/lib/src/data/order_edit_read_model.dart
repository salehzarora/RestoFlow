/// ORDER-EDIT-001E — the POS's view of the sent-order-edit READ SURFACE that
/// ORDER-EDIT-001B added (API_CONTRACT §4.30b, §4.30c and §4.45.10).
///
/// PURE and MONEY-FREE: no widgets, no providers, no I/O, and no amount of any
/// kind. Nothing here carries a staff, session or device identifier either —
/// the server emits none (`order_edit_id` is order-scoped).
///
/// Every parse is TOLERANT. An absent or malformed value reads as null (or the
/// documented default) and NEVER fails the money-strict container it rides in
/// (the order detail, the order snapshot, the capability probe): an older
/// server that predates these keys must keep working exactly as before.
/// Where a value gates an action, "unknown" is resolved by the CALLER in the
/// direction that rule needs — the rollout switch hides Edit when unknown, a
/// null `legacy` flag counts as legacy — never by inventing a value here.
library;

/// The session branch's two sent-order-edit switches, as the server reports
/// them: the top-level `branch_features` of `pin_session_capabilities`
/// (§4.30b) and of `pos_order_detail` (§4.45.10), the same shape in both.
class PosBranchFeatures {
  const PosBranchFeatures({
    required this.orderEditEnabled,
    required this.finishedFoodManagerOnly,
  });

  /// `order_edit_enabled` — the ROLLOUT gate for the "Edit order" entry.
  final bool orderEditEnabled;

  /// `order_edit_finished_food_manager_only` — on a KDS branch, removing,
  /// reducing or remaking a Ready / Served line needs a manager.
  final bool finishedFoodManagerOnly;

  /// ATOMIC: null unless [raw] is a map whose two switches are BOTH booleans.
  /// A half-readable object is unknown, not half-known, and an unknown
  /// rollout gate hides the entry (API_CONTRACT §4.30b).
  static PosBranchFeatures? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final enabled = raw['order_edit_enabled'];
    final finishedFood = raw['order_edit_finished_food_manager_only'];
    if (enabled is! bool || finishedFood is! bool) return null;
    return PosBranchFeatures(
      orderEditEnabled: enabled,
      finishedFoodManagerOnly: finishedFood,
    );
  }
}

/// How the kitchen of an order hears about an edit: a KDS screen, or paper on
/// a printer-only branch. Mirrors `app.edit_order` step 5.
enum PosKitchenChannel {
  kds,
  paper;

  /// Null for null or any unknown token — the server sends NULL when the
  /// channel is UNRESOLVABLE (a `direct_print` order on a branch now in KDS
  /// mode, or an unreadable branch row), and `edit_order` refuses that order
  /// `kitchen_mode_changed`. Never coerced into one of the two channels.
  static PosKitchenChannel? fromWire(Object? raw) => switch (raw) {
    'kds' => PosKitchenChannel.kds,
    'paper' => PosKitchenChannel.paper,
    _ => null,
  };
}

/// One applied sent-order edit, as `pos_order_detail.edits[]` lists it
/// (oldest first). Money-free and identifier-free beyond the edit's own id.
class PosOrderDetailEdit {
  const PosOrderDetailEdit({
    required this.orderEditId,
    required this.editNumber,
    this.createdAt,
    this.reasonCode,
    this.reasonText,
    this.kitchenChannel,
    this.kitchenAckRequired = false,
    this.kitchenAckAt,
    this.kitchenAckPending = false,
  });

  final String orderEditId;

  /// 1-based, per order — "Change N".
  final int editNumber;
  final DateTime? createdAt;
  final String? reasonCode;
  final String? reasonText;
  final PosKitchenChannel? kitchenChannel;
  final bool kitchenAckRequired;
  final DateTime? kitchenAckAt;

  /// The SERVER's verdict (a required confirmation not yet given; FALSE on a
  /// voided order). Taken verbatim — never re-derived from the two fields
  /// above, because the void rule lives only on the server.
  final bool kitchenAckPending;

  /// Null unless the identity is usable: a non-empty `order_edit_id` and an
  /// integer `edit_number` >= 1. The rest is tolerant.
  static PosOrderDetailEdit? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['order_edit_id'];
    final number = raw['edit_number'];
    if (id is! String || id.isEmpty || number is! int || number < 1) {
      return null;
    }
    return PosOrderDetailEdit(
      orderEditId: id,
      editNumber: number,
      createdAt: _time(raw['created_at']),
      reasonCode: _nonEmpty(raw['reason_code']),
      reasonText: _nonEmpty(raw['reason_text']),
      kitchenChannel: PosKitchenChannel.fromWire(raw['kitchen_channel']),
      kitchenAckRequired: raw['kitchen_ack_required'] == true,
      kitchenAckAt: _time(raw['kitchen_ack_at']),
      kitchenAckPending: raw['kitchen_ack_pending'] == true,
    );
  }

  /// The whole `edits[]` list, or NULL when it is absent, not a list, or ANY
  /// element is unreadable — unknown, never a partial history that would
  /// under-count the order's changes. Sorted by [editNumber] (the server
  /// already sends them oldest first; sorting here keeps the rule local).
  static List<PosOrderDetailEdit>? listFromJson(Object? raw) {
    if (raw is! List) return null;
    final edits = <PosOrderDetailEdit>[];
    for (final e in raw) {
      final edit = tryParse(e);
      if (edit == null) return null;
      edits.add(edit);
    }
    edits.sort((a, b) => a.editNumber.compareTo(b.editNumber));
    return List<PosOrderDetailEdit>.unmodifiable(edits);
  }
}

/// The stage of an order's ACTIVE service rounds, as a status label shows it
/// while a `served` order still has kitchen work live (STATE_MACHINES §1).
enum PosRoundStage { inKitchen, ready }

/// The kitchen stage of ONE sent line, from its work unit (the order for the
/// original ticket, the round for a round line) — the edit-mode stage chip.
enum PosLineStage { waiting, inKitchen, ready, served, printed }

/// Maps a line's raw `unit_status` (D-018 tokens) and its order's kitchen
/// channel to the stage the cashier sees.
///
/// On PAPER every line is "Printed": nothing advances a round on a
/// printer-only branch, so its raw status says nothing about the food, and
/// the server deliberately leaves this mapping to the POS (§4.45.10). An
/// unknown status is null — no stage is shown rather than an invented one.
PosLineStage? posLineStageFor({
  required String? unitStatus,
  required PosKitchenChannel? channel,
}) {
  if (channel == PosKitchenChannel.paper) return PosLineStage.printed;
  return switch (unitStatus) {
    'submitted' => PosLineStage.waiting,
    'accepted' || 'preparing' => PosLineStage.inKitchen,
    'ready' => PosLineStage.ready,
    'served' => PosLineStage.served,
    _ => null,
  };
}

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;
