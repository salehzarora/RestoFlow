/// POS-OPERATIONS-SYNC-001 — DEMO snapshot source.
///
/// Demo mode must be able to show the reconciliation engine actually working,
/// because the whole point of the engine is behaviour you cannot see in a static
/// fixture: a total that CHANGES, an order that COMPLETES itself, a payment that
/// arrives from somewhere else.
///
/// Deterministic by construction: a scripted queue of pages, an injected clock, no
/// randomness and no delays. Nothing here ever talks to a network.
library;

import 'order_snapshot.dart';
import 'order_snapshot_repository.dart';

/// A scriptable in-memory [OrderSnapshotRepository].
///
/// Tests and demo mode push the server's "next answer" onto it, then trigger a
/// sync. That is how a demo can show an order the SERVER completed while the till
/// was not looking — the one thing the POS could never do before.
class DemoOrderSnapshotRepository implements OrderSnapshotRepository {
  DemoOrderSnapshotRepository({List<PosOrderSnapshot>? seed})
    : _byOrderId = <String, PosOrderSnapshot>{
        for (final s in seed ?? const <PosOrderSnapshot>[]) s.orderId: s,
      };

  /// The server's current view, keyed by order id. Mutating this IS the demo's
  /// "something happened on the server" lever.
  final Map<String, PosOrderSnapshot> _byOrderId;

  /// When set, the next call throws this instead of answering — used to exercise
  /// the offline/refused/malformed paths without a network.
  PosSnapshotException? nextFailure;

  /// Pages already handed out, so `hasMore` can be exercised deterministically.
  int pageLimit = 50;

  /// Replaces (or inserts) the server's view of one order.
  void upsert(PosOrderSnapshot snapshot) {
    _byOrderId[snapshot.orderId] = snapshot;
  }

  /// Everything the demo server currently holds, oldest change first — the same
  /// ordering the real RPC guarantees.
  List<PosOrderSnapshot> get all {
    final list = _byOrderId.values.toList()
      ..sort((a, b) {
        final c = a.syncAt.compareTo(b.syncAt);
        return c != 0 ? c : a.orderId.compareTo(b.orderId);
      });
    return list;
  }

  PosSnapshotException? _takeFailure() {
    final f = nextFailure;
    nextFailure = null;
    return f;
  }

  /// The demo "now". Injected, never DateTime.now() — a demo that drifts with the
  /// wall clock is a demo that cannot be tested.
  DateTime clock = DateTime.utc(2026, 7, 14, 12);

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) async {
    final failure = _takeFailure();
    if (failure != null) throw failure;

    // The SAME window the server applies: orders CREATED within the last N days.
    // Widening it is exactly what "Load more" does.
    final windowStart = DateTime.utc(
      clock.year,
      clock.month,
      clock.day,
    ).subtract(Duration(days: windowDays - 1));

    // The SAME keyset the server uses: strictly after (sync_at, id).
    final after = <PosOrderSnapshot>[
      for (final s in all)
        if (!s.createdAt.isBefore(windowStart) &&
            (cursor == null || _isAfter(s, cursor)))
          s,
    ];
    final effective = limit < pageLimit ? limit : pageLimit;
    final page = after.take(effective).toList();
    final hasMore = after.length > page.length;
    return PosSnapshotPage(
      orders: page,
      hasMore: hasMore,
      nextCursor: page.isEmpty ? null : page.last.cursor,
    );
  }

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async {
    final failure = _takeFailure();
    if (failure != null) throw failure;
    return PosSnapshotPage(
      orders: <PosOrderSnapshot>[
        for (final id in orderIds)
          if (_byOrderId[id] != null) _byOrderId[id]!,
      ],
      hasMore: false,
    );
  }

  static bool _isAfter(PosOrderSnapshot s, PosSyncCursor cursor) {
    if (s.syncAt.isAfter(cursor.at)) return true;
    if (s.syncAt.isAtSameMomentAs(cursor.at)) {
      return s.orderId.compareTo(cursor.id) > 0;
    }
    return false;
  }
}

/// The DEMO branch, as the server would report it.
///
/// Every state the operational centre must handle, deterministically: an order in
/// each lifecycle stage, each settlement, a comped one, a cancelled one, a voided
/// one — and, crucially, orders THIS device never submitted (another till's), which
/// is the whole point of a branch view.
///
/// Deterministic by construction: derived from [now], never from the wall clock.
List<PosOrderSnapshot> demoBranchSnapshots(DateTime now) {
  PosOrderSnapshot s({
    required String id,
    required String status,
    required PosSettlement settlement,
    required int grand,
    int discount = 0,
    int minutesAgo = 0,
    String? table,
  }) {
    final at = now.subtract(Duration(minutes: minutesAgo));
    return PosOrderSnapshot(
      orderId: id,
      orderCode: '#${id.toUpperCase().padLeft(6, '0')}',
      revision: 2,
      status: status,
      settlement: settlement,
      subtotalMinor: grand + discount,
      discountTotalMinor: discount,
      taxTotalMinor: 0,
      grandTotalMinor: grand,
      createdAt: at,
      updatedAt: at,
      syncAt: at,
      orderType: 'dine_in',
      tableLabel: table,
      currencyCode: 'ILS',
    );
  }

  return <PosOrderSnapshot>[
    // --- OPEN, in every stage the kitchen moves through -----------------------
    s(
      id: 'd10001',
      status: 'submitted',
      settlement: PosSettlement.unpaid,
      grand: 4200,
      minutesAgo: 3,
      table: '4',
    ),
    s(
      id: 'd10002',
      status: 'accepted',
      settlement: PosSettlement.unpaid,
      grand: 6800,
      minutesAgo: 8,
      table: '7',
    ),
    // paid but still cooking — payment and fulfilment are INDEPENDENT axes (D-025)
    s(
      id: 'd10003',
      status: 'preparing',
      settlement: PosSettlement.paid,
      grand: 3100,
      minutesAgo: 12,
      table: '2',
    ),
    s(
      id: 'd10004',
      status: 'ready',
      settlement: PosSettlement.unpaid,
      grand: 5500,
      minutesAgo: 18,
      table: '9',
    ),
    s(
      id: 'd10005',
      status: 'served',
      settlement: PosSettlement.unpaid,
      grand: 7400,
      minutesAgo: 25,
      table: '1',
    ),
    // --- TERMINAL --------------------------------------------------------------
    s(
      id: 'd10006',
      status: 'completed',
      settlement: PosSettlement.paid,
      grand: 2900,
      minutesAgo: 40,
    ),
    // a COMPED order: closed, owes nothing, and NO money was ever taken for it
    s(
      id: 'd10007',
      status: 'completed',
      settlement: PosSettlement.notChargeable,
      grand: 0,
      discount: 3600,
      minutesAgo: 55,
    ),
    s(
      id: 'd10008',
      status: 'cancelled',
      settlement: PosSettlement.unpaid,
      grand: 1800,
      minutesAgo: 70,
    ),
    s(
      id: 'd10009',
      status: 'voided',
      settlement: PosSettlement.unpaid,
      grand: 2300,
      minutesAgo: 90,
    ),
    // --- OLDER than the default 2-day window: only "Load more" reaches these ----
    s(
      id: 'd1000a',
      status: 'completed',
      settlement: PosSettlement.paid,
      grand: 4400,
      minutesAgo: 60 * 24 * 3,
    ),
  ];
}
