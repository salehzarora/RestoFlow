/// ORDER-EDIT-001E — THE DIFF ENGINE (design §7.1 point 7): baseline versus
/// edit cart → the `order.edit` change list (API_CONTRACT §4.45.1), the
/// expected totals and everything the footer has to say about them.
///
/// PURE: no widgets, no providers, no I/O, no clock. The same baseline and the
/// same cart always give the same plan and the same payload bytes — which the
/// retry path does not rely on (it re-sends the frozen journal payload
/// verbatim), but which keeps a plan reviewable and testable.
///
/// THE SERVER IS MIRRORED, NOT APPROXIMATED. Every rule below is the rule
/// `app.edit_order` applies (`20261008170100_order_edit_001a_edit_order.sql`):
///
///  * a kept option is matched by its lower-case id and charged its STORED
///    price, whatever the live menu says now (:1296-1305) — only a NEW option
///    carries a client price;
///  * a replacement is a CONTINUATION when its option multiset and its
///    space-trimmed note equal the old line's (:1335-1337);
///  * the old line's dishes go to the continuation first, then to the changed
///    replacements; a changed replacement that takes Ready / Served KDS dishes
///    is a REMAKE (:1369-1436);
///  * the subtotal is RE-ROLLED from the live lines, the absolute order
///    discount is kept and never clamped, tax is recomputed on
///    (subtotal − discount) with the half-away rule of `tax_math.dart` (M5–M8,
///    :1618-1645).
///
/// So the `expected` totals equal the server's figures unless the order (or
/// the branch tax) changed underneath — which is exactly what
/// `totals_mismatch` is for.
///
/// Money is integer minor units only (D-007).
library;

import 'dart:convert' show jsonEncode;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax;
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenPrepComponent;
import 'package:restoflow_l10n/restoflow_l10n.dart' show kOrderEditReasonCodes;

import '../format/tax_math.dart' show taxMinorExclusive;
import '../state/cart_controller.dart'
    show
        CartLineView,
        SelectedModifier,
        classifiedPrepForLine,
        configuredLineTotalMinor,
        resolveOrderTimeMeatSnapshot,
        selectedOptionIdsOf;
import 'order_edit_baseline.dart';
import 'order_submission.dart'
    show OrderSubmissionItem, OrderSubmissionModifier;
import 'staff_capabilities.dart';

/// `app.edit_order` step-2 limits.
const int kOrderEditMaxChanges = 100;
const int kOrderEditMaxReplacements = 20;
const int kOrderEditMaxQuantity = 999;

/// `order_edits.reason_text` is at most 200 characters (`char_length`).
const int kOrderEditReasonTextMaxLength = 200;

/// The reason preselected when every removing change touches a ticket the
/// kitchen has not acknowledged (design §7.1 point 5).
const String kOrderEditPreselectedReason = 'customer_changed_mind';

/// One line of the cart while it is in edit mode — what the planner consumes.
///
/// [sourceOrderItemId] binds the line to the sent line it came from (null for
/// a line the cashier added). A bound line is never re-priced from its own
/// price fields: its base price and its kept options' prices are the source's
/// stored snapshots. [removed] marks a struck-through bound line; a removed
/// line contributes nothing.
class OrderEditCartLine {
  const OrderEditCartLine({
    required this.line,
    this.sourceOrderItemId,
    this.removed = false,
  });

  final CartLineView line;
  final String? sourceOrderItemId;
  final bool removed;
}

/// What one planned change does to one line.
enum OrderEditChangeKind { remove, increase, reduce, modify, add }

/// One planned change, money and stage included — the typed twin of one wire
/// change, for the footer, the finished-food sheet and the journal summary.
class OrderEditPlannedChange {
  const OrderEditPlannedChange({
    required this.kind,
    required this.name,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.totalBeforeMinor,
    required this.totalAfterMinor,
    this.source,
    this.remakeDishes = 0,
  });

  final OrderEditChangeKind kind;

  /// The sent line it changes; null for an added line.
  final OrderEditSourceLine? source;
  final String name;
  final int quantityBefore;
  final int quantityAfter;
  final int totalBeforeMinor;
  final int totalAfterMinor;

  /// Ready / Served KDS dishes a changed replacement takes back and the
  /// kitchen makes again — the server's allotment (`edit_order.sql:1369-1436`),
  /// which is also the count the result toast reports (decision D8).
  final int remakeDishes;

  /// A remove, a modify or a quantity reduction: needs `void_order` and a
  /// reason (`edit_order` step 6a). An add or an increase needs neither.
  bool get isRemoving =>
      kind == OrderEditChangeKind.remove ||
      kind == OrderEditChangeKind.reduce ||
      kind == OrderEditChangeKind.modify;

  /// Takes food the kitchen already finished: a Ready / Served KDS line that
  /// is removed, reduced, or remade (design §7.1 point 6). Never on paper.
  bool get touchesFinishedFood {
    final s = source;
    if (s == null || !s.isFinishedOnKds) return false;
    return kind == OrderEditChangeKind.remove ||
        kind == OrderEditChangeKind.reduce ||
        (kind == OrderEditChangeKind.modify && remakeDishes > 0);
  }
}

/// A money-free summary of one attempt, kept in the durable journal so a
/// restored attempt can still be described (and its remake count reported)
/// without the cart it was planned from.
class OrderEditAttemptSummary {
  const OrderEditAttemptSummary({
    this.removedCount = 0,
    this.quantityChangedCount = 0,
    this.modifiedCount = 0,
    this.addedCount = 0,
    this.remakeDishCount = 0,
  });

  final int removedCount;
  final int quantityChangedCount;
  final int modifiedCount;
  final int addedCount;
  final int remakeDishCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'removed_count': removedCount,
    'quantity_changed_count': quantityChangedCount,
    'modified_count': modifiedCount,
    'added_count': addedCount,
    'remake_dish_count': remakeDishCount,
  };

  /// STRICT: every count must be a non-negative integer, else [FormatException].
  factory OrderEditAttemptSummary.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('order edit summary is not an object');
    }
    int count(String key) {
      final v = raw[key];
      if (v is int && v >= 0) return v;
      throw FormatException('order edit summary: $key is not a count');
    }

    return OrderEditAttemptSummary(
      removedCount: count('removed_count'),
      quantityChangedCount: count('quantity_changed_count'),
      modifiedCount: count('modified_count'),
      addedCount: count('added_count'),
      remakeDishCount: count('remake_dish_count'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OrderEditAttemptSummary &&
      other.removedCount == removedCount &&
      other.quantityChangedCount == quantityChangedCount &&
      other.modifiedCount == modifiedCount &&
      other.addedCount == addedCount &&
      other.remakeDishCount == remakeDishCount;

  @override
  int get hashCode => Object.hash(
    removedCount,
    quantityChangedCount,
    modifiedCount,
    addedCount,
    remakeDishCount,
  );
}

/// The result of [planOrderEdit].
class OrderEditPlan {
  const OrderEditPlan({
    required this.orderId,
    required this.changes,
    required this.plannedChanges,
    required this.beforeGrandMinor,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.grandMinor,
    this.wouldEmpty = false,
    this.discountExceeds = false,
    this.zeroOut = false,
    this.tooMany = false,
    this.invalidLineChange = false,
    this.removalNotPermitted = false,
    this.finishedFoodNeedsManager = false,
  });

  final String orderId;

  /// The wire `changes[]`, canonical: the sent lines' changes in the
  /// baseline's print order, then the added lines in cart order.
  final List<Map<String, Object?>> changes;
  final List<OrderEditPlannedChange> plannedChanges;

  /// The order's stored grand total — the footer's "Was".
  final int beforeGrandMinor;

  /// The planned new figures — the payload's `expected` and the footer's
  /// "Now". [grandMinor] is `subtotal − discount + tax`, unclamped: it is
  /// negative only when [discountExceeds], and such a plan is never sent.
  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int grandMinor;

  /// No live line would remain — a cancellation, not an edit
  /// (`edit_would_empty_order`).
  final bool wouldEmpty;

  /// The kept order discount exceeds the new subtotal (`invalid_discount` /
  /// `discount_exceeds_order_total`).
  final bool discountExceeds;

  /// The total would go from > 0 to 0 and the session is KNOWN not to hold
  /// the full-comp right (`full_comp_permission_required`). Unknown
  /// capabilities never block: the server decides.
  final bool zeroOut;

  /// More than 100 changes, more than 20 replacements on one line, or a sent
  /// line's quantity above 999.
  final bool tooMany;

  /// The cart asks for something no valid edit can express: a quantity or
  /// option change on a remove-only line, or a line bound to a sent line the
  /// baseline does not have. The cart's own controls never produce it; the
  /// engine refuses to plan it rather than send a guaranteed refusal.
  final bool invalidLineChange;

  /// A removing change while `void_order` is KNOWN to be denied
  /// (`removal_not_permitted`). Unknown is not denied (decision D14).
  final bool removalNotPermitted;

  /// A removing change on a Ready / Served KDS line by a cashier while the
  /// finished-food switch is ON (`finished_food_needs_manager`).
  final bool finishedFoodNeedsManager;

  bool get noChanges => changes.isEmpty;

  int get deltaMinor => grandMinor - beforeGrandMinor;

  bool get hasRemoving => plannedChanges.any((c) => c.isRemoving);

  /// "Customer changed mind" is preselected only when EVERY removing change
  /// touches a KDS ticket that is still `submitted` (design §7.1 point 5). A
  /// convenience default only — the reason is still recorded.
  bool get preselectCustomerChangedMind {
    final removing = plannedChanges.where((c) => c.isRemoving).toList();
    return removing.isNotEmpty &&
        removing.every((c) => c.source?.isWaitingOnKds ?? false);
  }

  /// The reason chip to preselect, or null when the cashier must choose.
  String? get preselectedReasonCode =>
      preselectCustomerChangedMind ? kOrderEditPreselectedReason : null;

  /// The lines the finished-food confirm sheet lists (design §7.1 point 6).
  List<OrderEditPlannedChange> get finishedFoodChanges => [
    for (final c in plannedChanges)
      if (c.touchesFinishedFood) c,
  ];

  bool get needsFinishedFoodConfirm =>
      plannedChanges.any((c) => c.touchesFinishedFood);

  /// Dishes the kitchen will make again (decision D8: the plan's allotment).
  int get remakeCount {
    var n = 0;
    for (final c in plannedChanges) {
      n += c.remakeDishes;
    }
    return n;
  }

  OrderEditAttemptSummary get summary {
    var removed = 0;
    var quantity = 0;
    var modified = 0;
    var added = 0;
    for (final c in plannedChanges) {
      switch (c.kind) {
        case OrderEditChangeKind.remove:
          removed++;
        case OrderEditChangeKind.increase:
        case OrderEditChangeKind.reduce:
          quantity++;
        case OrderEditChangeKind.modify:
          modified++;
        case OrderEditChangeKind.add:
          added++;
      }
    }
    return OrderEditAttemptSummary(
      removedCount: removed,
      quantityChangedCount: quantity,
      modifiedCount: modified,
      addedCount: added,
      remakeDishCount: remakeCount,
    );
  }
}

/// Why "Send changes" is disabled, in the order the footer reports it
/// (design §7.1 point 4; ORDER-EDIT-001E plan §8a). Only the FIRST applicable
/// reason is shown.
enum OrderEditSendBlock {
  noChanges,
  wouldEmpty,
  discountExceeds,
  fullCompDenied,
  tooManyChanges,
  invalidLineChange,
  removalNotPermitted,
  finishedFoodNeedsManager,
  offline,
  reasonRequired,
  reasonOtherRequired,
}

/// The first reason [plan] may not be sent right now, or null when it may.
///
/// [reasonCode] / [reasonText] are the cashier's current chip and Other text;
/// they matter only when the plan has a removing change.
OrderEditSendBlock? orderEditSendBlock(
  OrderEditPlan plan, {
  required bool online,
  String? reasonCode,
  String? reasonText,
}) {
  if (plan.noChanges) return OrderEditSendBlock.noChanges;
  if (plan.wouldEmpty) return OrderEditSendBlock.wouldEmpty;
  if (plan.discountExceeds) return OrderEditSendBlock.discountExceeds;
  if (plan.zeroOut) return OrderEditSendBlock.fullCompDenied;
  if (plan.tooMany) return OrderEditSendBlock.tooManyChanges;
  if (plan.invalidLineChange) return OrderEditSendBlock.invalidLineChange;
  if (plan.removalNotPermitted) return OrderEditSendBlock.removalNotPermitted;
  if (plan.finishedFoodNeedsManager) {
    return OrderEditSendBlock.finishedFoodNeedsManager;
  }
  if (!online) return OrderEditSendBlock.offline;
  if (plan.hasRemoving) {
    if (reasonCode == null || !kOrderEditReasonCodes.contains(reasonCode)) {
      return OrderEditSendBlock.reasonRequired;
    }
    if (reasonCode == 'other' && _reasonText(reasonText) == null) {
      return OrderEditSendBlock.reasonOtherRequired;
    }
  }
  return null;
}

/// The `order.edit` payload (API_CONTRACT §4.45.1):
/// `{order_id, reason_code?, reason_text?, bill_presented_at?,
/// expected{subtotal_minor, tax_total_minor, grand_total_minor}, changes}`.
///
///  * the reason is sent only with a removing change (pure additions and
///    increases ask for none), and only a known code;
///  * `reason_text` only with `other`, trimmed and capped at 200 characters
///    (code points — the server's `char_length`);
///  * `bill_presented_at` is a UTC instant with its `Z`, the only form the
///    server accepts besides an explicit offset (`edit_order.sql:870-879`).
Map<String, Object?> buildOrderEditPayload(
  OrderEditPlan plan, {
  String? reasonCode,
  String? reasonText,
  DateTime? billPresentedAt,
}) {
  final withReason =
      plan.hasRemoving &&
      reasonCode != null &&
      kOrderEditReasonCodes.contains(reasonCode);
  final text = withReason && reasonCode == 'other'
      ? _reasonText(reasonText)
      : null;
  return <String, Object?>{
    'order_id': plan.orderId,
    if (withReason) 'reason_code': reasonCode,
    if (text != null) 'reason_text': text,
    if (billPresentedAt != null)
      'bill_presented_at': billPresentedAt.toUtc().toIso8601String(),
    'expected': <String, Object?>{
      'subtotal_minor': plan.subtotalMinor,
      'tax_total_minor': plan.taxMinor,
      'grand_total_minor': plan.grandMinor,
    },
    'changes': plan.changes,
  };
}

/// The total of ONE edit-cart line — the formula the cart view and the plan
/// share, so the screen can never show a figure the plan does not send.
///
///  * an added line ([source] null) is priced like any new line (002A, the
///    live price it was added at);
///  * a bound line unchanged from its source is its STORED total (exact even
///    for a legacy or discounted line);
///  * any other bound line is `quantity × (stored base + Σ option price ×
///    option quantity)`, where a kept option is charged its STORED price and
///    only a new option its own.
int orderEditLineTotalMinor({
  required OrderEditSourceLine? source,
  required int quantity,
  required Iterable<SelectedModifier> modifiers,
  required int unitPriceMinor,
  required String? note,
}) {
  if (source == null) {
    return configuredLineTotalMinor(
      basePriceMinor: unitPriceMinor,
      modifiers: modifiers,
      quantity: quantity,
    );
  }
  if (quantity == source.quantity &&
      _partKey(source, modifiers, note) == _sourceKey(source)) {
    return source.lineTotalMinor;
  }
  return quantity * _boundUnitMinor(source, modifiers);
}

/// Plans the edit of [baseline] into [cart].
///
/// [tax] is the branch's CURRENT tax setting (the server recomputes with its
/// current settings too). [capabilities] are advisory: they only add the
/// "known denied" flags; null means unknown and blocks nothing.
/// [prepByItemId] is the live menu's prep snapshot for ADDED lines (D-008),
/// exactly what the Add-items path freezes.
OrderEditPlan planOrderEdit(
  OrderEditBaseline baseline,
  List<OrderEditCartLine> cart, {
  required BranchTax tax,
  PosStaffCapabilities? capabilities,
  Map<String, List<KitchenPrepComponent>> prepByItemId =
      const <String, List<KitchenPrepComponent>>{},
}) {
  var invalid = false;
  var tooMany = false;
  final partsBySource = <String, List<CartLineView>>{};
  final adds = <CartLineView>[];
  for (final c in cart) {
    if (c.line.quantity < 1) {
      invalid = true;
      continue;
    }
    final bound = c.sourceOrderItemId;
    if (bound == null) {
      if (!c.removed) adds.add(c.line);
      continue;
    }
    final source = baseline.lineFor(bound);
    if (source == null) {
      invalid = true;
      continue;
    }
    if (c.removed) continue;
    partsBySource.putIfAbsent(source.orderItemId, () => []).add(c.line);
  }

  final changes = <Map<String, Object?>>[];
  final planned = <OrderEditPlannedChange>[];
  var subtotal = 0;
  var anyLineLeft = adds.isNotEmpty;

  for (final s in baseline.lines) {
    final parts = partsBySource[s.orderItemId] ?? const <CartLineView>[];
    if (parts.isEmpty) {
      changes.add(<String, Object?>{
        'op': 'remove',
        'order_item_id': s.orderItemId,
      });
      planned.add(
        OrderEditPlannedChange(
          kind: OrderEditChangeKind.remove,
          source: s,
          name: s.name,
          quantityBefore: s.quantity,
          quantityAfter: 0,
          totalBeforeMinor: s.lineTotalMinor,
          totalAfterMinor: 0,
        ),
      );
      continue;
    }
    anyLineLeft = true;
    final groups = _groupParts(s, parts);
    final sourceKey = _sourceKey(s);

    if (groups.length == 1 && groups.single.key == sourceKey) {
      // ONLY the line's own configuration: unchanged, or a set_quantity.
      final q = groups.single.quantity;
      if (q == s.quantity) {
        subtotal += s.lineTotalMinor;
        continue;
      }
      if (s.removeOnly) invalid = true;
      if (q > kOrderEditMaxQuantity) tooMany = true;
      final increase = q > s.quantity;
      // Mirrors the server: an increase KEEPS the old line and adds a +N
      // delta row; a reduction retires it and writes the remainder.
      final total = increase
          ? s.lineTotalMinor + (q - s.quantity) * s.configuredUnitMinor
          : q * s.configuredUnitMinor;
      subtotal += total;
      changes.add(<String, Object?>{
        'op': 'set_quantity',
        'order_item_id': s.orderItemId,
        'quantity': q,
      });
      planned.add(
        OrderEditPlannedChange(
          kind: increase
              ? OrderEditChangeKind.increase
              : OrderEditChangeKind.reduce,
          source: s,
          name: s.name,
          quantityBefore: s.quantity,
          quantityAfter: q,
          totalBeforeMinor: s.lineTotalMinor,
          totalAfterMinor: total,
        ),
      );
      continue;
    }

    // MODIFY: the line's own configuration (the continuation) first, then
    // every other configuration in line-id order — deterministic whatever the
    // cart's row order.
    if (s.removeOnly) invalid = true;
    final ordered = [
      for (final g in groups)
        if (g.key == sourceKey) g,
      for (final g in groups)
        if (g.key != sourceKey) g,
    ];
    if (ordered.length > kOrderEditMaxReplacements) tooMany = true;
    var total = 0;
    var quantityAfter = 0;
    var continuationQty = 0;
    final replacements = <Map<String, Object?>>[];
    for (final g in ordered) {
      if (g.quantity > kOrderEditMaxQuantity) tooMany = true;
      total += g.quantity * _boundUnitMinor(s, g.modifiers);
      quantityAfter += g.quantity;
      if (g.key == sourceKey) continuationQty = g.quantity;
      replacements.add(<String, Object?>{
        'quantity': g.quantity,
        'notes': g.note,
        'modifiers': _replacementModifiers(s, g.modifiers),
      });
    }
    subtotal += total;
    // The server's allotment: continuations take the old dishes first, the
    // changed replacements take what is left.
    final changedQty = quantityAfter - continuationQty;
    final left = s.quantity - continuationQty;
    final taken = left <= 0 ? 0 : (changedQty < left ? changedQty : left);
    changes.add(<String, Object?>{
      'op': 'modify',
      'order_item_id': s.orderItemId,
      'replacements': replacements,
    });
    planned.add(
      OrderEditPlannedChange(
        kind: OrderEditChangeKind.modify,
        source: s,
        name: s.name,
        quantityBefore: s.quantity,
        quantityAfter: quantityAfter,
        totalBeforeMinor: s.lineTotalMinor,
        totalAfterMinor: total,
        remakeDishes: s.isFinishedOnKds ? taken : 0,
      ),
    );
  }

  for (final l in adds) {
    final total = configuredLineTotalMinor(
      basePriceMinor: l.unitPriceMinor,
      modifiers: l.modifiers,
      quantity: l.quantity,
    );
    subtotal += total;
    changes.add(<String, Object?>{
      'op': 'add',
      'item': _addedItem(l, total, prepByItemId),
    });
    planned.add(
      OrderEditPlannedChange(
        kind: OrderEditChangeKind.add,
        name: l.name,
        quantityBefore: 0,
        quantityAfter: l.quantity,
        totalBeforeMinor: 0,
        totalAfterMinor: total,
      ),
    );
  }
  if (changes.length > kOrderEditMaxChanges) tooMany = true;

  final discount = baseline.discountMinor;
  final base = subtotal - discount;
  final taxMinor = tax.addsTax && base >= 0
      ? taxMinorExclusive(base, tax.rateBp)
      : 0;
  final grand = base + taxMinor;
  final before = baseline.grandBeforeMinor;
  final removing = planned.where((c) => c.isRemoving);

  return OrderEditPlan(
    orderId: baseline.orderId,
    changes: List<Map<String, Object?>>.unmodifiable(changes),
    plannedChanges: List<OrderEditPlannedChange>.unmodifiable(planned),
    beforeGrandMinor: before,
    subtotalMinor: subtotal,
    discountMinor: discount,
    taxMinor: taxMinor,
    grandMinor: grand,
    wouldEmpty: !anyLineLeft,
    discountExceeds: discount > subtotal,
    zeroOut: before > 0 && grand == 0 && capabilities?.applyFullComp == false,
    tooMany: tooMany,
    invalidLineChange: invalid,
    removalNotPermitted:
        removing.isNotEmpty && capabilities?.voidOrder == false,
    finishedFoodNeedsManager: removing.any(
      (c) => baseline.needsManagerFor(c.source!, capabilities),
    ),
  );
}

/// The edit cart's planned subtotal — the figure the cart's bottom bar shows,
/// by construction equal to [planOrderEdit]'s.
int orderEditSubtotalMinor(
  OrderEditBaseline baseline,
  List<OrderEditCartLine> cart,
) => planOrderEdit(baseline, cart, tax: BranchTax.disabled).subtotalMinor;

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

/// One configuration of a sent line in the cart: every part with the same
/// key, coalesced.
class _Group {
  _Group(this.key, this.firstLineId, this.modifiers, this.note);

  final String key;
  String firstLineId;
  List<SelectedModifier> modifiers;
  final String? note;
  int quantity = 0;
}

/// Coalesces [parts] by configuration. The representative of a group (whose
/// modifier order is emitted) is its part with the smallest line id, so the
/// result does not depend on where the parts sit in the cart.
List<_Group> _groupParts(OrderEditSourceLine s, List<CartLineView> parts) {
  final byKey = <String, _Group>{};
  for (final p in parts) {
    final key = _partKey(s, p.modifiers, p.note);
    final g = byKey.putIfAbsent(
      key,
      () => _Group(key, p.lineId, p.modifiers, _pgBtrim(p.note)),
    );
    g.quantity += p.quantity;
    if (p.lineId.compareTo(g.firstLineId) < 0) {
      g.firstLineId = p.lineId;
      g.modifiers = p.modifiers;
    }
  }
  return byKey.values.toList()
    ..sort((a, b) => a.firstLineId.compareTo(b.firstLineId));
}

/// A part's configuration key: the server's continuation key (the multiset
/// of lower-case option id and quantity, plus the space-trimmed note) — and,
/// for a NEW option, the snapshot it would be sent with, so two parts whose
/// new options differ in price or name are never merged into one replacement.
String _partKey(
  OrderEditSourceLine s,
  Iterable<SelectedModifier> modifiers,
  String? note,
) {
  final entries = <String>[
    for (final m in modifiers)
      jsonEncode(
        s.storedPriceOf(m.optionId) != null
            ? <Object?>[m.optionId.toLowerCase(), m.quantity]
            : <Object?>[
                m.optionId.toLowerCase(),
                m.quantity,
                m.optionName,
                m.groupName,
                m.priceDeltaMinor,
                m.kitchenMeat?.toJson(),
              ],
      ),
  ]..sort();
  return jsonEncode(<Object?>[entries, _pgBtrim(note)]);
}

/// The source line's own configuration key.
String _sourceKey(OrderEditSourceLine s) => jsonEncode(<Object?>[
  <String>[
    for (final m in s.modifiers)
      jsonEncode(<Object?>[m.optionId.toLowerCase(), m.quantity]),
  ]..sort(),
  _pgBtrim(s.notes),
]);

/// The configured unit price of a bound part: the source's stored base, each
/// kept option at its STORED price, each new option at its own.
int _boundUnitMinor(
  OrderEditSourceLine s,
  Iterable<SelectedModifier> modifiers,
) {
  var unit = s.unitPriceMinor;
  for (final m in modifiers) {
    unit += (s.storedPriceOf(m.optionId) ?? m.priceDeltaMinor) * m.quantity;
  }
  return unit;
}

/// A replacement's `modifiers[]`: a kept option is `{modifier_option_id,
/// quantity}` only (the server copies its snapshots); a new option carries its
/// full order-time snapshot, the kitchen-count answer resolved against the
/// replacement's FULL option set (the Add-items rule).
List<Map<String, Object?>> _replacementModifiers(
  OrderEditSourceLine s,
  List<SelectedModifier> modifiers,
) {
  final selected = selectedOptionIdsOf(modifiers);
  return [
    for (final m in modifiers)
      if (s.storedPriceOf(m.optionId) != null)
        <String, Object?>{
          'modifier_option_id': m.optionId,
          'quantity': m.quantity,
        }
      else
        OrderSubmissionModifier(
          modifierOptionId: m.optionId,
          optionNameSnapshot: m.optionName,
          modifierNameSnapshot: m.groupName,
          priceMinorSnapshot: m.priceDeltaMinor,
          quantity: m.quantity,
          meatSnapshot: resolveOrderTimeMeatSnapshot(m.kitchenMeat, selected),
        ).toJson(),
  ];
}

/// An added line's `item` — the `order.items_add` item shape, built exactly as
/// `AdditionController._serializeLines` builds it (addition_controller.dart),
/// with no `line_discount_minor` (the server reads absent as 0).
Map<String, Object?> _addedItem(
  CartLineView l,
  int lineTotalMinor,
  Map<String, List<KitchenPrepComponent>> prepByItemId,
) {
  final lineSelectedOptionIds = selectedOptionIdsOf(l.modifiers);
  return OrderSubmissionItem(
    menuItemId: l.menuItemId,
    nameSnapshot: l.name,
    quantity: l.quantity,
    unitPriceMinorSnapshot: l.unitPriceMinor,
    lineTotalMinor: lineTotalMinor,
    notes: l.note,
    prepComponents: classifiedPrepForLine(
      prepByItemId[l.menuItemId] ?? const <KitchenPrepComponent>[],
      l.modifiers,
    ),
    modifiers: [
      for (final m in l.modifiers)
        OrderSubmissionModifier(
          modifierOptionId: m.optionId,
          optionNameSnapshot: m.optionName,
          modifierNameSnapshot: m.groupName,
          priceMinorSnapshot: m.priceDeltaMinor,
          quantity: m.quantity,
          meatSnapshot: resolveOrderTimeMeatSnapshot(
            m.kitchenMeat,
            lineSelectedOptionIds,
          ),
        ),
    ],
  ).toJson();
}

/// PostgreSQL `nullif(btrim(coalesce(x, '')), '')`: spaces only are trimmed
/// (the server's continuation test), and empty is null.
String? _pgBtrim(String? s) {
  if (s == null) return null;
  var start = 0;
  var end = s.length;
  while (start < end && s.codeUnitAt(start) == 0x20) {
    start++;
  }
  while (end > start && s.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return start == end ? null : s.substring(start, end);
}

/// The Other text as sent: trimmed, at most 200 code points, null when empty.
String? _reasonText(String? raw) {
  final t = raw?.trim();
  if (t == null || t.isEmpty) return null;
  final runes = t.runes;
  if (runes.length <= kOrderEditReasonTextMaxLength) return t;
  return String.fromCharCodes(runes.take(kOrderEditReasonTextMaxLength));
}
