import 'kds_ticket_view.dart';

/// ORDER-EDIT-001C: the kitchen channel an applied sent-order edit was told on
/// (`order_edits.kitchen_channel`). Only `kds` edits ever reach a KDS card;
/// `paper` edits print a change slip on the POS instead (D-044).
enum KdsEditChannel { kds, paper }

/// ORDER-EDIT-001C (D-043 / D-044): one applied sent-order edit as the KDS
/// sees it — an EXPLICIT, money-free pluck of a pulled `order_edits` row.
///
/// The wire row also carries the acting staff, PIN session, POS and
/// replay-key columns (the kitchen redaction strips money only), so this model
/// is built field by field and never keeps the raw row (SECURITY T-003).
final class KdsOrderEdit {
  const KdsOrderEdit({
    required this.id,
    required this.orderId,
    required this.editNumber,
    required this.channel,
    required this.ackRequired,
    this.ackAt,
    this.createdAt,
    this.reasonCode,
    this.reasonText,
  });

  /// `order_edits.id` — the id order items and rounds reference.
  final String id;

  /// The edited order.
  final String orderId;

  /// 1, 2, 3 … per order ("Change N"); the `order.edit_ack` target number.
  final int editNumber;

  /// Where the kitchen was told about the edit.
  final KdsEditChannel channel;

  /// The server's verdict at commit: the edit wrote to or retired from a work
  /// unit in `submitted..ready`, so the kitchen must confirm it (§4.45.4).
  final bool ackRequired;

  /// When the kitchen confirmed it ("Got it"); null while unconfirmed.
  final DateTime? ackAt;

  /// When the edit was applied (`created_at`, falling back to
  /// `client_created_at`) — the change header's time. Null when neither parses.
  final DateTime? createdAt;

  /// The closed reason code (`customer_changed_mind`, `entry_mistake`,
  /// `item_unavailable`, `kitchen_issue`, `other`), or null for a pure
  /// addition. Rendered through a localized label, never as raw text.
  final String? reasonCode;

  /// The optional free-text reason (always present for `other`).
  final String? reasonText;

  /// Whether this edit still waits for the kitchen's "Got it": a KDS-channel
  /// edit that required a confirmation not yet given. The caller decides the
  /// voided-order rule (a void supersedes every pending edit, §4.46).
  bool get awaitsKitchenAck =>
      channel == KdsEditChannel.kds && ackRequired && ackAt == null;

  /// Parses one pulled `order_edits` row, or returns null for a row the KDS
  /// must ignore: a tombstone, a non-string `id` / `order_id`, an
  /// `edit_number` that is not an integer ≥ 1, an unknown channel, or a set
  /// but unreadable acknowledgement time (an acknowledged edit is never
  /// resurrected as pending).
  static KdsOrderEdit? tryParse(Map<String, dynamic> row) {
    if (row['deleted_at'] != null) return null;
    final id = row['id'];
    final orderId = row['order_id'];
    final number = row['edit_number'];
    if (id is! String || id.isEmpty) return null;
    if (orderId is! String || orderId.isEmpty) return null;
    if (number is! int || number < 1) return null;
    final channel = switch (row['kitchen_channel']) {
      'kds' => KdsEditChannel.kds,
      'paper' => KdsEditChannel.paper,
      _ => null,
    };
    if (channel == null) return null;
    final ackRaw = row['kitchen_ack_at'];
    DateTime? ackAt;
    if (ackRaw != null) {
      ackAt = ackRaw is String ? DateTime.tryParse(ackRaw) : null;
      if (ackAt == null) return null;
    }
    final reasonCode = row['reason_code'];
    final reasonText = row['reason_text'];
    return KdsOrderEdit(
      id: id,
      orderId: orderId,
      editNumber: number,
      channel: channel,
      ackRequired: row['kitchen_ack_required'] == true,
      ackAt: ackAt,
      createdAt:
          _timestamp(row['created_at']) ?? _timestamp(row['client_created_at']),
      reasonCode: reasonCode is String && reasonCode.isNotEmpty
          ? reasonCode
          : null,
      reasonText: reasonText is String && reasonText.trim().isNotEmpty
          ? reasonText.trim()
          : null,
    );
  }

  static DateTime? _timestamp(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}

/// ORDER-EDIT-001C: how an edit touched a LIVE line on a KDS card.
enum KdsEditLineMark {
  /// A new dish (an `add`, a modify's extra dishes with no old line to
  /// compare, or anything the overlay cannot pair with an old line).
  added,

  /// A "+N" quantity increase written next to the kept line it extends.
  increased,

  /// A reduced or modified line; [KdsItemView.editWas] holds the old line.
  changed,

  /// A dish re-made in the edit's round instead of finished food;
  /// [KdsItemView.editWas] holds the line it replaces ("instead of").
  remake,
}

/// ORDER-EDIT-001C: a line a pending edit took off this card ("REMOVED",
/// struck through on screen).
final class KdsRemovedLine {
  const KdsRemovedLine({
    required this.line,
    required this.editNumber,
    this.removedKitchenStage,
    this.remadeInRoundNumber,
  });

  /// The retired line, rendered exactly like a live line.
  final KdsItemView line;

  /// The number of the edit that removed it.
  final int editNumber;

  /// `order_items.removed_kitchen_stage` — the unit's stage at commit
  /// (provenance, not a state).
  final String? removedKitchenStage;

  /// When the line was replaced by a REMAKE in another round, that round's
  /// number ("Remade in Round N"); null otherwise.
  final int? remadeInRoundNumber;
}

/// ORDER-EDIT-001C: the unconfirmed change(s) on ONE KDS card.
final class KdsTicketChange {
  const KdsTicketChange({
    required this.pendingEdits,
    this.removed = const <KdsRemovedLine>[],
    this.standalone = false,
    this.emptied = false,
    this.formerStage,
    this.orderPendingEditNumbers = const <int>[],
  });

  /// The pending edits that touched THIS card (wrote, retired, opened or
  /// emptied it), oldest first. Never empty.
  final List<KdsOrderEdit> pendingEdits;

  /// The lines pending edits removed from this card, in menu print order.
  final List<KdsRemovedLine> removed;

  /// True when the card exists only because of the change: its work unit has
  /// no live base ticket any more (an emptied unit, or an order that left the
  /// board while the change was unconfirmed).
  final bool standalone;

  /// True when no live line is left in the work unit ("All items of this
  /// ticket removed").
  final bool emptied;

  /// For a standalone card: the unit's stage when the newest pending edit
  /// removed from it (`submitted` / `accepted` / `preparing` / `ready`), which
  /// drives the column; null when unknown (the card then sits in New).
  final String? formerStage;

  /// EVERY pending edit number of the order, ascending — the server stamps
  /// every pending edit up to N on one "Got it" (§4.46).
  final List<int> orderPendingEditNumbers;

  /// The newest pending edit on this card.
  KdsOrderEdit get latest => pendingEdits.last;

  /// The `up_to_edit_number` "Got it" sends for this card.
  int get upToEditNumber => latest.editNumber;

  /// Lower pending edit numbers of the order that are NOT on this card but
  /// that this card's "Got it" also confirms (the stamp is per order).
  List<int> get alsoAcknowledges {
    final upTo = upToEditNumber;
    final onCard = {for (final e in pendingEdits) e.editNumber};
    return [
      for (final n in orderPendingEditNumbers)
        if (n < upTo && !onCard.contains(n)) n,
    ];
  }
}
