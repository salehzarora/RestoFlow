/// POS-OPERATIONS-SYNC-001 — the client seam over `public.pos_order_snapshots`.
///
/// This is the POS's FIRST authoritative order read. Before it, the device
/// recorded what it submitted and never heard from the server again.
library;

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'order_snapshot.dart';

/// One page of authoritative snapshots.
class PosSnapshotPage {
  const PosSnapshotPage({
    required this.orders,
    required this.hasMore,
    this.nextCursor,
  });

  static const PosSnapshotPage empty = PosSnapshotPage(
    orders: <PosOrderSnapshot>[],
    hasMore: false,
  );

  final List<PosOrderSnapshot> orders;

  /// True when the page filled its limit and more may lie behind it.
  ///
  /// A bounded page is NOT a deletion: an order missing from this page has not
  /// been deleted, it simply is not on this page. Nothing may infer removal here.
  final bool hasMore;

  /// Where to resume. Null at the end of the feed.
  final PosSyncCursor? nextCursor;
}

/// Why a pull failed. The distinction is load-bearing: a TRANSPORT failure is
/// retryable and must NOT clear the rows already on screen; a REFUSED session is
/// not retryable by the same means; a MALFORMED page must never advance the cursor.
enum PosSnapshotFailure { transport, session, malformed }

class PosSnapshotException implements Exception {
  const PosSnapshotException(this.failure, [this.message]);

  final PosSnapshotFailure failure;
  final String? message;

  bool get isRetryable => failure == PosSnapshotFailure.transport;

  @override
  String toString() => 'PosSnapshotException(${failure.name})';
}

/// Reads authoritative order snapshots for THIS device's branch.
abstract class OrderSnapshotRepository {
  /// INCREMENTAL: everything that changed after [cursor]. With a null cursor this
  /// is the WINDOW mode — the whole bounded operational window from its start.
  Future<PosSnapshotPage> fetchChanges({PosSyncCursor? cursor, int limit = 50});

  /// TARGETED: authoritative snapshots for specific orders, ignoring the window.
  /// Used after a write, a conflict, or a typed refusal, so the device learns the
  /// truth about exactly the order it just touched.
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds);
}

/// REAL repository — `public.pos_order_snapshots` over the same anon-key +
/// PIN/device-session transport as every other POS RPC. Never the `app` schema,
/// never a service-role key (D-011).
///
/// FAIL CLOSED: with no session/transport it throws rather than returning an empty
/// page. An empty page means "the server says nothing changed"; silence from a
/// missing session means "we have no idea" — and reconciling against "no idea" as
/// though it were "nothing changed" is precisely how stale data gets blessed.
class RealOrderSnapshotRepository implements OrderSnapshotRepository {
  const RealOrderSnapshotRepository(this._transport, this._session);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
  }) => _invoke(<String, dynamic>{
    'p_since_at': cursor?.at.toUtc().toIso8601String(),
    'p_since_id': cursor?.id,
    'p_limit': limit,
  });

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) {
    final ids = orderIds.where((id) => id.trim().isNotEmpty).toList();
    if (ids.isEmpty)
      return Future<PosSnapshotPage>.value(PosSnapshotPage.empty);
    return _invoke(<String, dynamic>{
      'p_order_ids': ids,
      'p_limit': ids.length > 100 ? 100 : ids.length,
    });
  }

  Future<PosSnapshotPage> _invoke(Map<String, dynamic> extra) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const PosSnapshotException(
        PosSnapshotFailure.session,
        'no authenticated PIN session on a paired device',
      );
    }

    final Object? raw;
    try {
      raw = await transport.invoke('pos_order_snapshots', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        ...extra,
      });
    } on SyncTransportException catch (e) {
      throw PosSnapshotException(
        PosSnapshotFailure.transport,
        e.code ?? e.kind.name,
      );
    }

    if (raw is! Map) {
      throw const PosSnapshotException(PosSnapshotFailure.malformed);
    }
    if (raw['ok'] != true) {
      // invalid_session / invalid_cursor / invalid_limit / invalid_window all land
      // here. None is fixed by blindly retrying the same call.
      throw PosSnapshotException(
        PosSnapshotFailure.session,
        raw['error'] is String ? raw['error'] as String : null,
      );
    }

    final list = raw['orders'];
    if (list is! List) {
      throw const PosSnapshotException(PosSnapshotFailure.malformed);
    }

    // ATOMIC: one malformed row rejects the WHOLE page. A page is a coherent view
    // of the branch at a moment; applying the half we could parse and advancing
    // the cursor past the half we could not would silently lose those orders
    // forever — the cursor never goes back.
    final orders = <PosOrderSnapshot>[];
    for (final e in list) {
      final snap = PosOrderSnapshot.fromJson(e);
      if (snap == null) {
        throw const PosSnapshotException(PosSnapshotFailure.malformed);
      }
      orders.add(snap);
    }

    final hasMore = raw['has_more'] == true;
    final cursor = PosSyncCursor.fromJson(raw['next_cursor']);
    // A page that claims more but carries no usable cursor cannot be resumed.
    // Treating it as "the end" would silently truncate the feed.
    if (hasMore && cursor == null) {
      throw const PosSnapshotException(PosSnapshotFailure.malformed);
    }
    return PosSnapshotPage(
      orders: orders,
      hasMore: hasMore,
      nextCursor: cursor,
    );
  }
}
