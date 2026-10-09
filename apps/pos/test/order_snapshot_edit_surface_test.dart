import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/order_reconciler.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';

/// ORDER-EDIT-001E — the POS reads the three ORDER-EDIT-001B additions to
/// `pos_order_snapshots` (API_CONTRACT §4.30c): `edit_count`,
/// `kitchen_edit_ack_pending` and `has_active_round`.
///
///  * TOLERANT, unlike the rest of the snapshot: a persisted snapshot that
///    fails to parse bricks the restore, so these three never reject one;
///  * persisted only when the server actually said them ([editSurfaceKnown]);
///  * a ONE-TIME backfill: at exactly equal (revision, sync_at), a snapshot
///    that carries the surface is newer than a cached one that does not —
///    and only that (RISK R-002: an older revision never wins).
void main() {
  final t0 = DateTime.utc(2026, 10, 8, 12);

  Map<String, Object?> row({
    int revision = 3,
    String status = 'served',
    DateTime? syncAt,
    bool with001B = true,
    Object? editCount = 1,
    Object? ackPending = true,
    Object? activeRound = true,
  }) => {
    'order_id': 'o-1',
    'order_code': '#0000O1',
    'revision': revision,
    'status': status,
    'order_type': 'takeaway',
    'table_label': null,
    'currency_code': 'ILS',
    'created_at': t0.toIso8601String(),
    'updated_at': (syncAt ?? t0).toIso8601String(),
    'sync_at': (syncAt ?? t0).toIso8601String(),
    'subtotal_minor': 4000,
    'discount_total_minor': 0,
    'tax_total_minor': 0,
    'grand_total_minor': 4000,
    'payment_status': 'unpaid',
    if (with001B) 'edit_count': editCount,
    if (with001B) 'kitchen_edit_ack_pending': ackPending,
    if (with001B) 'has_active_round': activeRound,
  };

  PosOrderSnapshot parse(Map<String, Object?> raw) =>
      PosOrderSnapshot.fromJson(raw)!;

  group('parse', () {
    test('a 001B row carries the surface', () {
      final s = parse(row());
      expect(s.editCount, 1);
      expect(s.kitchenEditAckPending, isTrue);
      expect(s.hasActiveRound, isTrue);
      expect(s.editSurfaceKnown, isTrue);
    });

    test('a pre-001B row parses with the defaults, surface unknown', () {
      final s = parse(row(with001B: false));
      expect(s.editCount, 0);
      expect(s.kitchenEditAckPending, isFalse);
      expect(s.hasActiveRound, isFalse);
      expect(s.editSurfaceKnown, isFalse);
    });

    test('malformed values read the defaults and never reject', () {
      final s = PosOrderSnapshot.fromJson(
        row(editCount: '2', ackPending: 'true', activeRound: 1),
      );
      expect(s, isNotNull, reason: 'the snapshot is never rejected for these');
      expect(s!.editCount, 0);
      expect(s.kitchenEditAckPending, isFalse);
      expect(s.hasActiveRound, isFalse);
      expect(
        s.editSurfaceKnown,
        isFalse,
        reason: 'a non-boolean has_active_round is not the server speaking',
      );
      expect(parse(row(editCount: -4)).editCount, 0);
      expect(parse(row(editCount: 1.0)).editCount, 0);
    });

    test('the strict money rules are unchanged', () {
      final r = row()..['grand_total_minor'] = 4000.0;
      expect(PosOrderSnapshot.fromJson(r), isNull);
    });
  });

  group('round trips', () {
    test('PosOrderSnapshot toJson/fromJson keeps the surface', () {
      final s = parse(row(editCount: 2, ackPending: false));
      final back = parse(s.toJson());
      expect(back.editCount, 2);
      expect(back.kitchenEditAckPending, isFalse);
      expect(back.hasActiveRound, isTrue);
      expect(back.editSurfaceKnown, isTrue);
    });

    test('a surface-less snapshot persists WITHOUT the keys', () {
      final s = parse(row(with001B: false));
      final json = s.toJson();
      expect(json.containsKey('edit_count'), isFalse);
      expect(json.containsKey('kitchen_edit_ack_pending'), isFalse);
      expect(json.containsKey('has_active_round'), isFalse);
      expect(parse(json).editSurfaceKnown, isFalse);
    });

    test('PosRecentOrder toJson/fromJson keeps the surface', () {
      final order = PosRecentOrder.discovered(parse(row(editCount: 3)));
      expect(order.hasActiveRound, isTrue);
      expect(order.editCount, 3);
      expect(order.kitchenEditAckPending, isTrue);
      final back = PosRecentOrder.fromJson(order.toJson());
      expect(back.hasActiveRound, isTrue);
      expect(back.editCount, 3);
      expect(back.kitchenEditAckPending, isTrue);
      expect(back.snapshot!.editSurfaceKnown, isTrue);
    });

    test('a row cached before 001E restores with the defaults', () {
      final cached = PosRecentOrder.discovered(parse(row(with001B: false)));
      final back = PosRecentOrder.fromJson(cached.toJson());
      expect(back.hasActiveRound, isFalse);
      expect(back.editCount, 0);
      expect(back.kitchenEditAckPending, isFalse);
      expect(back.snapshot!.editSurfaceKnown, isFalse);
    });
  });

  group('isNewerThan — the one-time backfill tiebreak', () {
    test('equal (revision, sync_at): surface beats no surface', () {
      final fresh = parse(row());
      final cached = parse(row(with001B: false));
      expect(fresh.isNewerThan(cached), isTrue);
      expect(cached.isNewerThan(fresh), isFalse);
    });

    test('equal (revision, sync_at), both carry it: never newer', () {
      final a = parse(row());
      final b = parse(row(activeRound: false));
      expect(a.isNewerThan(b), isFalse);
      expect(b.isNewerThan(a), isFalse);
    });

    test('equal (revision, sync_at), neither carries it: never newer', () {
      final a = parse(row(with001B: false));
      final b = parse(row(with001B: false));
      expect(a.isNewerThan(b), isFalse);
    });

    test('an OLDER revision with the surface never wins', () {
      final older = parse(row(revision: 2));
      final cached = parse(row(revision: 3, with001B: false));
      expect(older.isNewerThan(cached), isFalse);
    });

    test('an older sync_at with the surface never wins', () {
      final older = parse(row(syncAt: t0.subtract(const Duration(seconds: 1))));
      final cached = parse(row(with001B: false));
      expect(older.isNewerThan(cached), isFalse);
    });

    test('a newer sync_at still wins regardless of the surface', () {
      final newer = parse(
        row(with001B: false, syncAt: t0.add(const Duration(seconds: 1))),
      );
      final cached = parse(row());
      expect(newer.isNewerThan(cached), isTrue);
    });
  });

  group('reconciliation backfills a cached row exactly once', () {
    test('applied 1, then 0', () {
      final cached = PosRecentOrder.discovered(parse(row(with001B: false)));
      expect(cached.hasActiveRound, isFalse);

      final fresh = parse(row());
      final first = reconcileSnapshots(<PosRecentOrder>[cached], [fresh]);
      expect(first.applied, 1);
      expect(first.orders.single.hasActiveRound, isTrue);
      expect(first.orders.single.editCount, 1);

      final second = reconcileSnapshots(first.orders, [fresh]);
      expect(second.applied, 0);
      expect(identical(second.orders.single, first.orders.single), isTrue);
    });

    test('a later flip of the flag arrives through the widened stamp', () {
      final withRound = PosRecentOrder.discovered(parse(row()));
      final roundServed = parse(
        row(activeRound: false, syncAt: t0.add(const Duration(minutes: 1))),
      );
      final result = reconcileSnapshots(
        <PosRecentOrder>[withRound],
        [roundServed],
      );
      expect(result.applied, 1);
      expect(result.orders.single.hasActiveRound, isFalse);
    });
  });
}
