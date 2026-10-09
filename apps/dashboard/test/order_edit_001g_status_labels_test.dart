/// ORDER-EDIT-001G — the Dashboard status-label rule (STATE_MACHINES §1,
/// DECISION D-043) and the "Edited ×N" badge on the order lists.
///
/// A `served` order with a service round still in the kitchen
/// (`has_active_round`) must read the round's stage — "In kitchen", or "Ready"
/// where the drawer knows every active round is ready — and never "Served" or
/// "Picked up". Every other status and every order without an active round
/// reads exactly as before, including against a server that does not send the
/// new keys.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/data/real_active_orders_repository.dart';
import 'package:restoflow_dashboard/src/data/real_order_history_repository.dart';
import 'package:restoflow_dashboard/src/orders/active_orders_screen.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart';
import 'package:restoflow_dashboard/src/widgets/recent_order_tile.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

final DateTime _now = DateTime.utc(2026, 10, 9, 12);

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

const _statuses = [
  'draft',
  'submitted',
  'accepted',
  'preparing',
  'ready',
  'served',
  'completed',
  'cancelled',
  'voided',
];

OrderHistoryRow _row({
  String status = 'served',
  String type = 'dine_in',
  bool? hasActiveRound,
  int editCount = 0,
  SettlementState settlement = SettlementState.unpaid,
}) => OrderHistoryRow(
  orderId: 'o-1',
  orderCode: '#ABC123',
  status: status,
  orderType: type,
  createdAtLabel: '2026-10-09 11:50',
  itemCount: 2,
  grandTotalMinor: 5700,
  currencyCode: 'ILS',
  settlement: settlement,
  createdAtUtc: _now.subtract(const Duration(minutes: 10)),
  editCount: editCount,
  hasActiveRound: hasActiveRound,
);

Widget _host(Widget child, {String locale = 'en'}) => ProviderScope(
  child: MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: Scaffold(body: SizedBox(width: 900, child: child)),
  ),
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

Map<String, Object?> _wireRow({bool withKeys = true}) => <String, Object?>{
  'order_id': 'o-1',
  'order_code': '#ABC123',
  'status': 'served',
  'order_type': 'takeaway',
  'created_at': '2026-10-09 11:50',
  'created_at_utc': '2026-10-09T08:50:00Z',
  'item_count': 2,
  'grand_total_minor': 5700,
  'payment_method': null,
  'payment_status': 'unpaid',
  'paid_amount_minor': null,
  if (withKeys) 'edit_count': 2,
  if (withKeys) 'has_active_round': true,
};

void main() {
  group('statusLabelFor / statusTone: the full matrix', () {
    test('only a served order with an active round is overridden', () async {
      final l10n = await _l10n('en');
      for (final status in _statuses) {
        for (final type in ['dine_in', 'takeaway', null]) {
          final today = statusLabelFor(l10n, status, type);
          final todayTone = statusTone(status);
          for (final active in [false, true]) {
            for (final ready in [false, true]) {
              final label = statusLabelFor(
                l10n,
                status,
                type,
                hasActiveRound: active,
                activeRoundsReady: ready,
              );
              final tone = statusTone(
                status,
                hasActiveRound: active,
                activeRoundsReady: ready,
              );
              final why = '$status/$type active=$active ready=$ready';
              if (status == 'served' && active) {
                expect(
                  label,
                  ready ? l10n.ordersStatusReady : l10n.ordersStatusInKitchen,
                  reason: why,
                );
                expect(
                  tone,
                  ready ? RestoflowTone.info : RestoflowTone.warning,
                  reason: why,
                );
                expect(label, isNot(l10n.ordersStatusPickedUp), reason: why);
                expect(label, isNot(l10n.ordersStatusServed), reason: why);
              } else {
                expect(label, today, reason: why);
                expect(tone, todayTone, reason: why);
              }
            }
          }
        }
      }
    });

    test('"Picked up" only for a takeaway served order with no active '
        'round', () async {
      final l10n = await _l10n('en');
      expect(
        statusLabelFor(l10n, 'served', 'takeaway'),
        l10n.ordersStatusPickedUp,
      );
      expect(
        statusLabelFor(l10n, 'served', 'takeaway', hasActiveRound: true),
        l10n.ordersStatusInKitchen,
      );
      // Once the round is served the flag clears and Picked up returns.
      expect(
        statusLabelFor(l10n, 'served', 'takeaway', hasActiveRound: false),
        l10n.ordersStatusPickedUp,
      );
      // "activeRoundsReady" alone (no active round) changes nothing.
      expect(
        statusLabelFor(l10n, 'served', 'dine_in', activeRoundsReady: true),
        l10n.ordersStatusServed,
      );
    });

    test('statusLabel forwards the flags', () async {
      final l10n = await _l10n('en');
      expect(
        statusLabel(l10n, 'served', hasActiveRound: true),
        l10n.ordersStatusInKitchen,
      );
      expect(statusLabel(l10n, 'served'), l10n.ordersStatusServed);
    });

    test('ar and he carry their own In kitchen / Edited labels', () async {
      final en = await _l10n('en');
      for (final code in ['ar', 'he']) {
        final l10n = await _l10n(code);
        final label = statusLabelFor(
          l10n,
          'served',
          'takeaway',
          hasActiveRound: true,
        );
        expect(label, l10n.ordersStatusInKitchen);
        expect(label.trim(), isNotEmpty);
        expect(label, isNot(en.ordersStatusInKitchen));
        expect(l10n.ordersEditedBadge(2), isNot(en.ordersEditedBadge(2)));
      }
    });
  });

  group('every caller uses the flag', () {
    testWidgets('the active board tile: In kitchen, badge, no "paid, not '
        'completed" pill while a round is active', (tester) async {
      final l10n = await _l10n('en');
      final row = _row(
        hasActiveRound: true,
        editCount: 2,
        settlement: SettlementState.paid,
      );
      await tester.pumpWidget(
        _host(ActiveOrderTile(row: row, now: _now, l10n: l10n)),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.ordersStatusInKitchen), findsOneWidget);
      expect(find.text(l10n.ordersStatusServed), findsNothing);
      expect(find.text(l10n.ordersEditedBadge(2)), findsOneWidget);
      expect(
        find.byKey(Key('stale-paid-not-completed-${row.orderId}')),
        findsNothing,
      );
    });

    testWidgets('the stale pill returns once no round is active', (
      tester,
    ) async {
      final l10n = await _l10n('en');
      for (final flag in [false, null]) {
        final row = _row(
          hasActiveRound: flag,
          settlement: SettlementState.paid,
        );
        await tester.pumpWidget(
          _host(ActiveOrderTile(row: row, now: _now, l10n: l10n)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('stale-paid-not-completed-${row.orderId}')),
          findsOneWidget,
          reason: 'hasActiveRound=$flag',
        );
        expect(find.text(l10n.ordersStatusServed), findsOneWidget);
      }
    });

    testWidgets('the history card: In kitchen + badge; no badge when '
        'unedited', (tester) async {
      final l10n = await _l10n('en');
      await tester.pumpWidget(
        _host(
          OrderHistoryCard(
            row: _row(type: 'takeaway', hasActiveRound: true, editCount: 3),
            l10n: l10n,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.ordersStatusInKitchen), findsOneWidget);
      expect(find.text(l10n.ordersStatusPickedUp), findsNothing);
      expect(find.text(l10n.ordersEditedBadge(3)), findsOneWidget);

      await tester.pumpWidget(
        _host(
          OrderHistoryCard(
            row: _row(type: 'takeaway'),
            l10n: l10n,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.ordersStatusPickedUp), findsOneWidget);
      expect(find.byKey(const Key('order-edited-badge')), findsNothing);
    });

    testWidgets('the Overview recent-orders tile', (tester) async {
      final l10n = await _l10n('en');
      await tester.pumpWidget(
        _host(
          RecentOrderTile(
            row: RecentOrderRow.fromHistory(_row(hasActiveRound: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.ordersStatusInKitchen), findsOneWidget);
      expect(find.text(l10n.ordersStatusServed), findsNothing);
    });

    testWidgets('Arabic and Hebrew render the round label', (tester) async {
      for (final code in ['ar', 'he']) {
        final l10n = await _l10n(code);
        await tester.pumpWidget(
          _host(
            ActiveOrderTile(
              row: _row(hasActiveRound: true, editCount: 1),
              now: _now,
              l10n: l10n,
            ),
            locale: code,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.ordersStatusInKitchen), findsOneWidget);
        expect(find.text(l10n.ordersEditedBadge(1)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('parsers: additive keys, absent keys read as today', () {
    test(
      'owner_active_orders rows carry edit_count and has_active_round',
      () async {
        Future<OrderHistoryRow> load({required bool withKeys}) async {
          final repo = RealActiveOrdersRepository(
            null,
            scope: _owner(),
            transport: _FakeTransport(<String, Object?>{
              'ok': true,
              'entity': 'owner_active_orders',
              'currency_code': 'ILS',
              'has_more': false,
              'next_cursor': null,
              'summary': <String, Object?>{'total': 1, 'unpaid': 1},
              'orders': <Object?>[_wireRow(withKeys: withKeys)],
            }),
          );
          final snap = await repo.loadActive(
            const ActiveOrdersQuery(
              queue: ActiveOrderQueue.allActive,
              sort: ActiveOrdersSort.newest,
            ),
          );
          return snap.rows.single;
        }

        final withKeys = await load(withKeys: true);
        expect(withKeys.editCount, 2);
        expect(withKeys.hasActiveRound, isTrue);
        final older = await load(withKeys: false);
        expect(older.editCount, 0);
        expect(older.hasActiveRound, isNull);
        final l10n = await _l10n('en');
        expect(
          statusLabelFor(
            l10n,
            older.status,
            older.orderType,
            hasActiveRound: older.hasActiveRound == true,
          ),
          l10n.ordersStatusPickedUp,
          reason: 'an older server reads exactly as before',
        );
      },
    );

    test('owner_order_history rows carry the same keys', () async {
      Future<OrderHistoryRow> load({required bool withKeys}) async {
        final repo = RealOrderHistoryRepository(
          null,
          scope: _owner(),
          transport: _FakeTransport(<String, Object?>{
            'ok': true,
            'currency_code': 'ILS',
            'orders': <Object?>[_wireRow(withKeys: withKeys)],
            'has_more': false,
          }),
        );
        final page = await repo.loadHistory(const OrderHistoryQuery());
        return page.rows.single;
      }

      final withKeys = await load(withKeys: true);
      expect(withKeys.editCount, 2);
      expect(withKeys.hasActiveRound, isTrue);
      final older = await load(withKeys: false);
      expect(older.editCount, 0);
      expect(older.hasActiveRound, isNull);
    });

    test('the demo rows carry the fields from the order', () async {
      final repo = DemoOrderHistoryRepository(
        orders: [
          DemoOrder(
            daysAgo: 0,
            detail: const OrderDetail(
              orderId: 'd-1',
              orderCode: '#D00001',
              status: 'served',
              orderType: 'dine_in',
              currencyCode: 'ILS',
              subtotalMinor: 100,
              discountTotalMinor: 0,
              taxTotalMinor: 0,
              grandTotalMinor: 100,
              editCount: 2,
              hasActiveRound: true,
            ),
          ),
        ],
      );
      final row = (await repo.loadHistory(
        const OrderHistoryQuery(),
      )).rows.single;
      expect(row.editCount, 2);
      expect(row.hasActiveRound, isTrue);
      final recent = RecentOrderRow.fromHistory(row);
      expect(recent.hasActiveRound, isTrue);
    });
  });
}
