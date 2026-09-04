// STALE-TABLE-ORDER-RECOVERY-001 — the Dashboard FLAGS stale active orders
// (display only) and maps the additive `shift_status` / `kitchen_work_open`
// facts; it never mutates an order from a warning.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/real_active_orders_repository.dart';
import 'package:restoflow_dashboard/src/orders/active_orders_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

final DateTime _now = DateTime.utc(2026, 9, 4, 12, 0);

OrderHistoryRow _row({
  String id = '298e598d-9709-4807-b46a-9be2758dd505',
  String status = 'submitted',
  SettlementState settlement = SettlementState.unpaid,
  Duration age = const Duration(hours: 53),
  String? shiftStatus,
  bool? kitchenWorkOpen,
}) => OrderHistoryRow(
  orderId: id,
  orderCode: '#8DD505',
  status: status,
  orderType: 'dine_in',
  createdAtLabel: '2026-09-01 21:41',
  itemCount: 4,
  grandTotalMinor: 23200,
  currencyCode: 'ILS',
  settlement: settlement,
  createdAtUtc: _now.subtract(age),
  tableLabel: 'T1',
  shiftStatus: shiftStatus,
  kitchenWorkOpen: kitchenWorkOpen,
);

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.response);
  final Object? response;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async =>
      response;
}

MembershipContext _owner() => const MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: 'rest-1',
  restaurantName: 'Rest 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: MembershipRole.orgOwner,
  status: 'active',
);

Map<String, Object?> _body(Map<String, Object?> order) => <String, Object?>{
  'ok': true,
  'entity': 'owner_active_orders',
  'currency_code': 'ILS',
  'queue': 'all_active',
  'sort': 'newest',
  'limit': 100,
  'count': 1,
  'matching': 1,
  'has_more': false,
  'truncated': false,
  'next_cursor': null,
  'summary': <String, Object?>{
    'total': 1,
    'unpaid': 1,
    'in_progress': 1,
    'awaiting_close': 0,
    'by_status': <String, Object?>{
      'submitted': 1,
      'accepted': 0,
      'preparing': 0,
      'ready': 0,
      'served': 0,
    },
  },
  'orders': <Object?>[order],
};

Map<String, Object?> _order({
  Object? shiftStatus,
  Object? kitchenWorkOpen,
  bool includeFlags = true,
}) => <String, Object?>{
  'order_id': 'o-1',
  'order_code': '#8DD505',
  'status': 'submitted',
  'order_type': 'dine_in',
  'table_label': 'T1',
  'created_at': '2026-09-01 21:41',
  'created_at_utc': '2026-09-01T18:41:55Z',
  'timezone': 'Asia/Jerusalem',
  'item_count': 4,
  'grand_total_minor': 23200,
  'payment_method': null,
  'payment_status': 'unpaid',
  'paid_amount_minor': null,
  if (includeFlags) 'shift_status': shiftStatus,
  if (includeFlags) 'kitchen_work_open': kitchenWorkOpen,
};

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pumpTile(WidgetTester tester, OrderHistoryRow row) async {
  final l10n = await _en();
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: ActiveOrderTile(row: row, now: _now, l10n: l10n),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('stale flags are DISPLAY ONLY warnings', () {
    testWidgets('an order open beyond the threshold gets the stale-age pill', (
      tester,
    ) async {
      final l10n = await _en();
      final row = _row(age: const Duration(hours: 53));
      await _pumpTile(tester, row);
      expect(find.byKey(Key('stale-age-${row.orderId}')), findsOneWidget);
      expect(find.text(l10n.ordersStaleOpenFor(53)), findsOneWidget);
      // the canonical recovery path is stated next to the warning
      expect(find.byKey(Key('stale-hint-${row.orderId}')), findsOneWidget);
      expect(find.text(l10n.ordersStaleHint), findsOneWidget);
    });

    testWidgets('a fresh order gets NO stale pill', (tester) async {
      final row = _row(age: const Duration(minutes: 30));
      await _pumpTile(tester, row);
      expect(find.byKey(Key('stale-age-${row.orderId}')), findsNothing);
      expect(find.byKey(Key('stale-hint-${row.orderId}')), findsNothing);
      expect(
        find.byKey(Key('stale-shift-closed-${row.orderId}')),
        findsNothing,
      );
      expect(
        find.byKey(Key('stale-paid-not-completed-${row.orderId}')),
        findsNothing,
      );
      expect(
        find.byKey(Key('stale-no-kitchen-work-${row.orderId}')),
        findsNothing,
      );
    });

    testWidgets('the threshold is exact: 11h59 is not stale, 12h00 is', (
      tester,
    ) async {
      final fresh = _row(age: const Duration(hours: 11, minutes: 59));
      await _pumpTile(tester, fresh);
      expect(find.byKey(Key('stale-age-${fresh.orderId}')), findsNothing);
      final stale = _row(age: kActiveOrderStaleAfter);
      await _pumpTile(tester, stale);
      expect(find.byKey(Key('stale-age-${stale.orderId}')), findsOneWidget);
    });

    testWidgets('a closed originating shift is flagged', (tester) async {
      final l10n = await _en();
      final row = _row(age: const Duration(minutes: 10), shiftStatus: 'closed');
      await _pumpTile(tester, row);
      expect(
        find.byKey(Key('stale-shift-closed-${row.orderId}')),
        findsOneWidget,
      );
      expect(find.text(l10n.ordersStaleShiftClosed), findsOneWidget);
      // the terminal RECONCILED state is a closed shift too (defensive: the
      // server normalizes to 'closed'; an older server might not)
      final rec = _row(
        age: const Duration(minutes: 10),
        shiftStatus: 'reconciled',
      );
      await _pumpTile(tester, rec);
      expect(
        find.byKey(Key('stale-shift-closed-${rec.orderId}')),
        findsOneWidget,
      );
      // an OPEN shift is not a warning
      final open = _row(age: const Duration(minutes: 10), shiftStatus: 'open');
      await _pumpTile(tester, open);
      expect(
        find.byKey(Key('stale-shift-closed-${open.orderId}')),
        findsNothing,
      );
    });

    testWidgets('served + fully paid but still active = auto-completion gap', (
      tester,
    ) async {
      final l10n = await _en();
      final row = _row(
        age: const Duration(minutes: 10),
        status: 'served',
        settlement: SettlementState.paid,
      );
      await _pumpTile(tester, row);
      expect(
        find.byKey(Key('stale-paid-not-completed-${row.orderId}')),
        findsOneWidget,
      );
      expect(find.text(l10n.ordersStalePaidNotCompleted), findsOneWidget);
      // a served ZERO-TOTAL (not_chargeable) order is SETTLED too: same gap
      final free = _row(
        age: const Duration(minutes: 10),
        status: 'served',
        settlement: SettlementState.notChargeable,
      );
      await _pumpTile(tester, free);
      expect(
        find.byKey(Key('stale-paid-not-completed-${free.orderId}')),
        findsOneWidget,
      );
      // served + UNPAID is the normal "awaiting close" state, not a gap
      final unpaid = _row(age: const Duration(minutes: 10), status: 'served');
      await _pumpTile(tester, unpaid);
      expect(
        find.byKey(Key('stale-paid-not-completed-${unpaid.orderId}')),
        findsNothing,
      );
    });

    testWidgets(
      'no live kitchen work on an in-progress order is flagged; unknown (null) is NOT',
      (tester) async {
        final l10n = await _en();
        final row = _row(
          age: const Duration(minutes: 10),
          kitchenWorkOpen: false,
        );
        await _pumpTile(tester, row);
        expect(
          find.byKey(Key('stale-no-kitchen-work-${row.orderId}')),
          findsOneWidget,
        );
        expect(find.text(l10n.ordersStaleNoKitchenWork), findsOneWidget);
        final unknown = _row(age: const Duration(minutes: 10));
        await _pumpTile(tester, unknown);
        expect(
          find.byKey(Key('stale-no-kitchen-work-${unknown.orderId}')),
          findsNothing,
        );
        // a SERVED order is awaiting close, not "missing" kitchen work
        final served = _row(
          age: const Duration(minutes: 10),
          status: 'served',
          kitchenWorkOpen: false,
        );
        await _pumpTile(tester, served);
        expect(
          find.byKey(Key('stale-no-kitchen-work-${served.orderId}')),
          findsNothing,
        );
      },
    );

    test(
      'staleOrderPills is a pure projection of the row and the clock',
      () async {
        final l10n = await _en();
        final row = _row(
          age: const Duration(hours: 53),
          shiftStatus: 'closed',
          kitchenWorkOpen: false,
        );
        final pills = staleOrderPills(l10n, row, _now);
        expect(pills, hasLength(4));
        // same inputs → same output; a later clock only changes the age word
        expect(staleOrderPills(l10n, row, _now), hasLength(4));
        expect(
          staleOrderPills(l10n, _row(age: const Duration(minutes: 1)), _now),
          isEmpty,
        );
      },
    );
  });

  group('additive flags are mapped, never fabricated', () {
    test('shift_status + kitchen_work_open are read when present', () async {
      final repo = RealActiveOrdersRepository(
        null,
        scope: _owner(),
        transport: _FakeTransport(
          _body(_order(shiftStatus: 'closed', kitchenWorkOpen: false)),
        ),
      );
      final snap = await repo.loadActive(
        const ActiveOrdersQuery(
          queue: ActiveOrderQueue.allActive,
          sort: ActiveOrdersSort.newest,
        ),
      );
      final r = snap.rows.single;
      expect(r.shiftStatus, 'closed');
      expect(r.kitchenWorkOpen, isFalse);
    });

    test(
      'an older server without the keys yields null (no stale hint)',
      () async {
        final repo = RealActiveOrdersRepository(
          null,
          scope: _owner(),
          transport: _FakeTransport(_body(_order(includeFlags: false))),
        );
        final snap = await repo.loadActive(
          const ActiveOrdersQuery(
            queue: ActiveOrderQueue.allActive,
            sort: ActiveOrdersSort.newest,
          ),
        );
        final r = snap.rows.single;
        expect(r.shiftStatus, isNull);
        expect(r.kitchenWorkOpen, isNull);
      },
    );
  });
}
