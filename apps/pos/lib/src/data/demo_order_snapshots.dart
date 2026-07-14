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

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
  }) async {
    final failure = _takeFailure();
    if (failure != null) throw failure;

    // The SAME keyset the server uses: strictly after (sync_at, id).
    final after = <PosOrderSnapshot>[
      for (final s in all)
        if (cursor == null || _isAfter(s, cursor)) s,
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
