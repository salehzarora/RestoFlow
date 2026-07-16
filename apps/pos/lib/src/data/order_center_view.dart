/// POS-OPERATIONS-SYNC-001 (Commit 3) — the operational centre's view model.
///
/// Sections, filters, search and sort, as PURE functions over the ONE authoritative
/// order collection. There is a single collection and a single settlement rule; the
/// sections are views of it, never separate stores that can drift apart.
library;

import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;

import 'order_reconciler.dart' show isCountedUnpaid;
import 'order_snapshot.dart';
import 'recent_order.dart';

/// The operational sections. These are OPERATIONAL groupings — "what do I need to
/// deal with?" — and they are deliberately not the same thing as the settlement
/// FILTER below, which is exact.
enum PosOrderSection {
  /// Live work: submitted / accepted / preparing / ready / served.
  open,

  /// Still owes money AND is still operationally relevant. A comp owes nothing and a
  /// closed order is not a debt, so neither appears here.
  needsPayment,

  /// completed / cancelled / voided, within the loaded window.
  completedRecently,

  /// Everything loaded.
  all,
}

/// The EXACT settlement filter. Unlike the sections, this one is literal.
///
/// If the chip says "Paid" it means PAID — it does NOT quietly include "No charge".
/// A comped order was never paid; nobody handed over any money. Folding the two
/// together is how a cashier reconciling a drawer ends up hunting for cash that was
/// never taken.
enum PosSettlementFilter {
  all,
  needsPayment, // unpaid ONLY
  paid, //         paid ONLY
  noCharge; //     notChargeable ONLY

  bool matches(PosRecentOrder o) => switch (this) {
    PosSettlementFilter.all => true,
    PosSettlementFilter.needsPayment => o.settlement == PosSettlement.unpaid,
    PosSettlementFilter.paid => o.settlement == PosSettlement.paid,
    PosSettlementFilter.noCharge => o.settlement == PosSettlement.notChargeable,
  };
}

/// RESTAURANT-OPERATIONS-V1-001: the order-type filter. EXACT, like the
/// settlement filter — "Dine-in" means dine-in. An order whose type is unknown
/// (a pre-upgrade row the server never described) matches only "All": we do not
/// guess a type to make a filter look fuller.
enum PosOrderTypeFilter {
  all,
  dineIn,
  takeaway;

  bool matches(PosRecentOrder o) => switch (this) {
    PosOrderTypeFilter.all => true,
    PosOrderTypeFilter.dineIn => o.orderType == OrderType.dineIn,
    PosOrderTypeFilter.takeaway => o.orderType == OrderType.takeaway,
  };
}

/// Newest first is the default: a POS is about what just happened.
enum PosOrderSort { newestFirst, oldestFirst }

/// Whether [o] belongs in [section].
///
/// A LOCAL DRAFT is in NO server section — it was never submitted, and putting it in
/// "history" would claim the server knows about something it does not.
bool sectionContains(PosOrderSection section, PosRecentOrder o) {
  if (o.origin == PosOrderOrigin.localDraft) return false;

  // A3: a PERMANENTLY-REJECTED submit created no server order. It is not open work,
  // not needs-payment, not completed — it never happened. It stays visible ONLY in
  // the "All" tab, clearly marked "Not created", so the cashier can see (and discard)
  // the failed attempt without it masquerading as a live order anywhere operational.
  if (o.isNeverCreated) return section == PosOrderSection.all;

  final status = o.serverStatus;
  return switch (section) {
    // An order with no known status yet (submitted offline, never synced) counts as
    // OPEN: it is live work. Hiding it because the server has not spoken would drop
    // it off the cashier's board entirely.
    PosOrderSection.open =>
      !o.isTerminal && (status == null || kPosOpenStatuses.contains(status)),
    PosOrderSection.needsPayment => isCountedUnpaid(o),
    PosOrderSection.completedRecently => o.isTerminal,
    PosOrderSection.all => true,
  };
}

/// The full pipeline: section -> status filter -> settlement filter -> search -> sort.
///
/// One collection in, one list out. No section maintains its own store, so two
/// sections can never disagree about the same order.
List<PosRecentOrder> viewOrders(
  Iterable<PosRecentOrder> orders, {
  required PosOrderSection section,
  PosSettlementFilter settlement = PosSettlementFilter.all,
  PosOrderTypeFilter type = PosOrderTypeFilter.all,
  String? status,
  String query = '',
  PosOrderSort sort = PosOrderSort.newestFirst,
}) {
  final needle = _normalize(query);

  final list = <PosRecentOrder>[
    for (final o in orders)
      if (sectionContains(section, o) &&
          settlement.matches(o) &&
          type.matches(o) &&
          (status == null || o.serverStatus == status) &&
          (needle.isEmpty || _matchesQuery(o, needle)))
        o,
  ];

  list.sort(
    (a, b) => sort == PosOrderSort.newestFirst
        ? b.sortAt.compareTo(a.sortAt)
        : a.sortAt.compareTo(b.sortAt),
  );
  return list;
}

/// Counts per section, over the loaded collection.
///
/// HONEST BY CONSTRUCTION: this counts what is LOADED. The server contract returns a
/// bounded page, so presenting these as full-branch totals would be a fabrication —
/// the surface says so by offering "Load more" while more pages remain.
Map<PosOrderSection, int> sectionCounts(Iterable<PosRecentOrder> orders) => {
  for (final s in PosOrderSection.values)
    s: orders.where((o) => sectionContains(s, o)).length,
};

/// Order-code + table-label search. Tolerant of the '#' and of case, because a
/// cashier reading a code off a printed ticket types what they see, not what we
/// stored. RESTAURANT-OPERATIONS-V1-001 adds the TABLE LABEL — "which order is
/// table 7's?" is the floor's most common lookup, and a floor label is public
/// signage, not private data.
///
/// It searches NOTHING else. Not notes, not the customer — a search box that
/// quietly matches private fields is a data-leak surface, not a feature.
bool _matchesQuery(PosRecentOrder o, String needle) {
  if (_normalize(o.orderNumber).contains(needle)) return true;
  final table = o.tableLabel;
  return table != null &&
      table.trim().isNotEmpty &&
      _normalize(table).contains(needle);
}

String _normalize(String s) =>
    s.trim().toUpperCase().replaceAll('#', '').replaceAll(' ', '');
