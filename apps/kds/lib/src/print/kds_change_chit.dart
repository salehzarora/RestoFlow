import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show
        OrderChangeAdded,
        OrderChangeModified,
        OrderChangeQuantity,
        OrderChangeRemoved,
        OrderChangeSlipEntry,
        OrderChangeSlipView,
        buildOrderChangeSlipPrintDocument,
        kitchenChangeSlipLabelsFromL10n;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsEditLineMark, KdsItemView, KdsOrderEdit, KdsTicketView;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_ticket_document.dart' show kitchenTicketPrintLabelsFromL10n;
import 'print_document.dart';

/// ORDER-EDIT-001D — what THIS display knows about one work unit's paper:
///
///  * [printed] — the unit's kitchen ticket is on paper (this device's own
///    job when [fromLocalJob], else the unit's stage as a proxy: a unit that
///    reached Acknowledged was printed on Acknowledge somewhere);
///  * [fromLocalJob] — [printed] comes from this device's print job, so the
///    paper's content is known exactly;
///  * [through] — the newest edit number the paper (or an earlier chit)
///    already shows; lines of edits at or below it never print again.
typedef KdsUnitPrintFacts = ({bool printed, bool fromLocalJob, int through});

/// The unit stages at edit time whose ticket was already on paper (printed on
/// Acknowledge). A line removed from a `submitted` unit was never printed.
const Set<String> _printedStages = {'accepted', 'preparing', 'ready'};

/// ORDER-EDIT-001D (design §7.2) — the money-free CHANGE CHIT one "Got it"
/// prints on an auto-printing KDS: what edits up to [upToEditNumber] changed
/// on the units of [orderId] whose ticket is ALREADY on paper, or null when
/// there is nothing to print.
///
/// Order-wide on purpose: one tap stamps EVERY pending edit of the order up
/// to N (§4.46), including the ones only named by the card's "also confirms"
/// caption, so every printed unit of the order with an unconfirmed change is
/// scanned. Units in New (never printed — an edit's own round included) add
/// nothing: their dishes print on that unit's own Acknowledge, so no dish
/// appears on two papers. REMAKE never prints (the paper has no REMAKE; that
/// dish prints with its round). Lines at or below a unit's
/// [KdsUnitPrintFacts.through] watermark are already on paper.
///
/// PURE: [board] is the board the cook confirmed and [facts] answers per
/// unit. MONEY-FREE by construction (SECURITY T-003): every entry reuses the
/// card's [KdsItemView]s and the header carries no staff or session field
/// (the KDS never plucks one).
OrderChangeSlipView? kdsChangeChitView({
  required String orderId,
  required int upToEditNumber,
  required List<KdsTicketView> board,
  required KdsUnitPrintFacts Function(KdsTicketView unit) facts,
}) {
  final units = [
    for (final t in board)
      if (t.orderId == orderId && t.change != null && !t.requiresAck) t,
  ]..sort((a, b) => a.kitchenTicketId.compareTo(b.kitchenTicketId));
  if (units.isEmpty) return null;

  final changes = <OrderChangeSlipEntry>[];
  for (final unit in units) {
    final unitFacts = facts(unit);
    if (!unitFacts.printed) continue;
    bool covered(int? editNumber) =>
        editNumber != null &&
        editNumber > unitFacts.through &&
        editNumber <= upToEditNumber;

    for (final removed in unit.change!.removed) {
      if (!covered(removed.editNumber)) continue;
      // Without this device's own job, only a line removed from a unit that
      // was on paper at edit time is news to the kitchen.
      if (!unitFacts.fromLocalJob &&
          !_printedStages.contains(removed.removedKitchenStage)) {
        continue;
      }
      changes.add(OrderChangeRemoved(removed.line));
    }

    // A modify's lines group under the line they replaced (its order item).
    final groups = <Object, List<KdsItemView>>{};
    for (final item in unit.items) {
      final was = item.editWas;
      if (item.editMark != KdsEditLineMark.changed || was == null) continue;
      if (!covered(item.editNumber)) continue;
      (groups[was.orderItemId ?? was] ??= <KdsItemView>[]).add(item);
    }
    final emitted = <Object>{};
    for (final item in unit.items) {
      if (!covered(item.editNumber)) continue;
      switch (item.editMark) {
        case KdsEditLineMark.changed:
          final was = item.editWas;
          if (was == null) continue;
          final groupKey = was.orderItemId ?? was;
          if (!emitted.add(groupKey)) continue;
          changes.add(
            OrderChangeModified(
              was: was,
              now: List.unmodifiable(groups[groupKey]!),
            ),
          );
        case KdsEditLineMark.increased:
          // The row's quantity IS the delta; the kept line it extends shares
          // its line position.
          final kept = _keptLine(unit, item);
          changes.add(
            kept == null
                ? OrderChangeAdded([item])
                : OrderChangeQuantity(
                    was: kept,
                    nowQuantity: kept.quantity + item.quantity,
                  ),
          );
        case KdsEditLineMark.added:
          changes.add(OrderChangeAdded([item]));
        case KdsEditLineMark.remake:
        case null:
          continue;
      }
    }
  }
  if (changes.isEmpty) return null;

  final header = units.first;
  final orderCode = header.orderNumber;
  if (orderCode == null) return null;
  final edit = _newestEdit(units, upToEditNumber);
  return OrderChangeSlipView(
    // Already carries its '#' (displayOrderCode).
    orderCode: orderCode,
    editNumber: upToEditNumber,
    orderType: header.orderType,
    tableLabel: header.tableLabel,
    customerName: header.customerName,
    editedAt: edit?.createdAt?.toLocal(),
    reasonCode: edit?.reasonCode,
    reasonText: edit?.reasonText,
    changes: List.unmodifiable(changes),
    // The chit path: no staff line (never plucked), no order note, no ORDER
    // NOW and no "replaces earlier tickets" footer — it replaces nothing.
  );
}

/// The live, unmarked line of [unit] a "+N" [delta] extends (same line
/// position), or null.
KdsItemView? _keptLine(KdsTicketView unit, KdsItemView delta) {
  if (delta.linePosition <= 0) return null;
  for (final item in unit.items) {
    if (item.editMark == null && item.linePosition == delta.linePosition) {
      return item;
    }
  }
  return null;
}

/// The newest pending edit numbered at most [upTo] on the order's [units] —
/// the edit the chit's title names, so its time and reason match it.
KdsOrderEdit? _newestEdit(List<KdsTicketView> units, int upTo) {
  KdsOrderEdit? newest;
  for (final unit in units) {
    for (final edit in unit.change!.pendingEdits) {
      if (edit.editNumber > upTo) continue;
      if (newest == null || edit.editNumber > newest.editNumber) newest = edit;
    }
  }
  return newest;
}

/// ORDER-EDIT-001D — renders a change chit through the ONE shared change-slip
/// layout, with this app's ticket labels (the same adapter its tickets use)
/// and the shared change-slip chrome. Money-free (T-003); ar/he take the
/// Q-015 raster path downstream like every kitchen ticket.
PrintDocument buildKdsChangeChitDocument(
  AppLocalizations l10n,
  OrderChangeSlipView view, {
  String? restaurantName,
}) => buildOrderChangeSlipPrintDocument(
  slip: view,
  labels: kitchenTicketPrintLabelsFromL10n(l10n),
  changeLabels: kitchenChangeSlipLabelsFromL10n(l10n),
  restaurantName: restaurantName,
);
