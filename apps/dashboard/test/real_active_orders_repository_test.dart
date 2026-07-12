import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/active_orders_repository.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart'
    show AuditBranchOption;
import 'package:restoflow_dashboard/src/data/order_history_models.dart'
    show OrderTypeFilter, PaymentFilter;
import 'package:restoflow_dashboard/src/data/real_active_orders_repository.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RealRepoNotWiredError;

/// ACTIVE-ORDERS-001 — the REAL repository: it maps the `owner_active_orders`
/// payload faithfully, sends the scope the caller's ROLE covers (never a typed
/// UUID), and FAILS CLOSED on a missing transport or a rejected body — it never
/// falls back to demo data.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.response, {this.throwOnInvoke = false});

  final Object? response;
  final bool throwOnInvoke;

  String? lastFunction;
  Map<String, dynamic>? lastArgs;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async {
    lastFunction = function;
    lastArgs = args;
    if (throwOnInvoke) {
      throw const SyncTransportException(SyncTransportErrorKind.transient);
    }
    return response;
  }
}

MembershipContext _membership(MembershipRole role) => MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: 'rest-1',
  restaurantName: 'Rest 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: role,
  status: 'active',
);

Map<String, Object?> _okBody() => <String, Object?>{
  'ok': true,
  'entity': 'owner_active_orders',
  'currency_code': 'ILS',
  'limit': 100,
  'count': 2,
  'matching': 7,
  'truncated': true,
  'summary': <String, Object?>{
    'total': 7,
    'unpaid': 3,
    'by_status': <String, Object?>{
      'submitted': 2,
      'accepted': 1,
      'preparing': 2,
      'ready': 1,
      'served': 1,
    },
  },
  'orders': <Object?>[
    <String, Object?>{
      'order_id': 'o-1',
      'order_code': '#02A001',
      'receipt_number': null,
      'status': 'preparing',
      'order_type': 'dine_in',
      'customer_name': 'Layla',
      'table_label': 'T1',
      'branch_name': 'Downtown',
      'staff_name': 'Amira',
      'created_at': '2026-07-12 16:00',
      'created_at_utc': '2026-07-12T13:00:00Z',
      'timezone': 'Asia/Jerusalem',
      'item_count': 2,
      'grand_total_minor': 8400,
      'payment_method': null,
      'payment_status': 'unpaid',
      'paid_amount_minor': null,
    },
    <String, Object?>{
      'order_id': 'o-2',
      'order_code': '#02A002',
      'status': 'ready',
      'order_type': 'takeaway',
      'created_at': '2026-07-12 16:20',
      'created_at_utc': '2026-07-12T13:20:00Z',
      'timezone': 'Asia/Jerusalem',
      'item_count': 1,
      'grand_total_minor': 1000,
      'payment_method': 'cash',
      'payment_status': 'paid',
      'paid_amount_minor': 1000,
    },
  ],
};

void main() {
  test('R1 maps rows, summary, currency and honest truncation', () async {
    final transport = _FakeTransport(_okBody());
    final repo = RealActiveOrdersRepository(
      null,
      scope: _membership(MembershipRole.orgOwner),
      transport: transport,
    );

    final snap = await repo.loadActive(const ActiveOrdersQuery());

    expect(transport.lastFunction, 'owner_active_orders');
    expect(snap.currencyCode, 'ILS');
    expect(snap.rows.length, 2);
    expect(snap.matching, 7);
    expect(snap.truncated, isTrue);
    expect(snap.summary.total, 7);
    expect(snap.summary.unpaid, 3);
    expect(snap.summary.ready, 1);
    expect(snap.summary.served, 1);
    expect(snap.summary.stage('preparing'), 2);

    final first = snap.rows.first;
    expect(first.orderId, 'o-1');
    expect(first.orderCode, '#02A001');
    expect(first.status, 'preparing');
    expect(first.customerName, 'Layla');
    expect(first.tableLabel, 'T1');
    expect(first.branchName, 'Downtown');
    expect(first.itemCount, 2);
    // Money stays an exact integer minor value.
    expect(first.grandTotalMinor, 8400);
    expect(first.paid, isFalse);
    // The branch-local display string AND the absolute instant both survive.
    expect(first.createdAtLabel, '2026-07-12 16:00');
    expect(first.createdAtUtc, DateTime.utc(2026, 7, 12, 13, 0));
    expect(openMinutes(first, DateTime.utc(2026, 7, 12, 13, 45)), 45);

    final second = snap.rows[1];
    expect(second.paid, isTrue);
    expect(second.paymentMethod, 'cash');
    expect(second.paidAmountMinor, 1000);
  });

  test('R2 sends the ROLE-covered scope and the validated filter tokens', () async {
    final transport = _FakeTransport(_okBody());

    // An org_owner covers the WHOLE org: no restaurant/branch is pinned.
    await RealActiveOrdersRepository(
      null,
      scope: _membership(MembershipRole.orgOwner),
      transport: transport,
    ).loadActive(const ActiveOrdersQuery());
    expect(transport.lastArgs!['p_organization_id'], 'org-1');
    expect(transport.lastArgs!['p_restaurant_id'], isNull);
    expect(transport.lastArgs!['p_branch_id'], isNull);

    // A manager covers exactly ONE branch — it is pinned, so a sibling branch is
    // never even requested.
    await RealActiveOrdersRepository(
      null,
      scope: _membership(MembershipRole.manager),
      transport: transport,
    ).loadActive(const ActiveOrdersQuery());
    expect(transport.lastArgs!['p_restaurant_id'], 'rest-1');
    expect(transport.lastArgs!['p_branch_id'], 'branch-1');

    // A picked branch comes from the scope-safe option list.
    await RealActiveOrdersRepository(
      null,
      scope: _membership(MembershipRole.orgOwner),
      transport: transport,
    ).loadActive(
      const ActiveOrdersQuery(
        branch: AuditBranchOption(
          branchId: 'branch-9',
          restaurantId: 'rest-9',
          label: 'Harbor',
        ),
        stage: ActiveOrderStageFilter.ready,
        payment: PaymentFilter.unpaid,
        orderType: OrderTypeFilter.takeaway,
        search: '  #02A001  ',
      ),
    );
    expect(transport.lastArgs!['p_restaurant_id'], 'rest-9');
    expect(transport.lastArgs!['p_branch_id'], 'branch-9');
    expect(transport.lastArgs!['p_status'], 'ready');
    expect(transport.lastArgs!['p_payment'], 'unpaid');
    expect(transport.lastArgs!['p_order_type'], 'takeaway');
    expect(transport.lastArgs!['p_search'], '#02A001');
    expect(transport.lastArgs!['p_limit'], 100);
  });

  test('R3 an unfiltered query sends NULL tokens (never a made-up default)', () async {
    final transport = _FakeTransport(_okBody());
    await RealActiveOrdersRepository(
      null,
      scope: _membership(MembershipRole.orgOwner),
      transport: transport,
    ).loadActive(const ActiveOrdersQuery());
    expect(transport.lastArgs!['p_status'], isNull);
    expect(transport.lastArgs!['p_payment'], isNull);
    expect(transport.lastArgs!['p_order_type'], isNull);
    expect(transport.lastArgs!['p_search'], isNull);
  });

  test('R4 FAILS CLOSED with no transport / no scope', () async {
    expect(
      () => const RealActiveOrdersRepository(
        null,
        scope: null,
        transport: null,
      ).loadActive(const ActiveOrdersQuery()),
      throwsA(isA<RealRepoNotWiredError>()),
    );
  });

  test('R5 a rejected body or a transport failure throws (no demo fallback)', () async {
    final denied = _FakeTransport(<String, Object?>{
      'ok': false,
      'error': 'permission_denied',
    });
    await expectLater(
      RealActiveOrdersRepository(
        null,
        scope: _membership(MembershipRole.cashier),
        transport: denied,
      ).loadActive(const ActiveOrdersQuery()),
      throwsA(isA<ActiveOrdersException>()),
    );

    final broken = _FakeTransport(null, throwOnInvoke: true);
    await expectLater(
      RealActiveOrdersRepository(
        null,
        scope: _membership(MembershipRole.orgOwner),
        transport: broken,
      ).loadActive(const ActiveOrdersQuery()),
      throwsA(isA<ActiveOrdersException>()),
    );
  });

  test('R6 a malformed row degrades safely (no age fabricated)', () async {
    final transport = _FakeTransport(<String, Object?>{
      'ok': true,
      'currency_code': 'ILS',
      'orders': <Object?>[
        <String, Object?>{
          'order_id': 'o-x',
          'order_code': '#X',
          'status': 'ready',
          'order_type': 'dine_in',
          // no created_at_utc at all, and a junk timestamp shape elsewhere
          'created_at': '',
          'item_count': 0,
          'grand_total_minor': 0,
          'payment_status': 'unpaid',
        },
        'not-a-row',
      ],
    });
    final snap = await RealActiveOrdersRepository(
      null,
      scope: _membership(MembershipRole.orgOwner),
      transport: transport,
    ).loadActive(const ActiveOrdersQuery());

    expect(snap.rows.length, 1);
    expect(snap.rows.first.createdAtUtc, isNull);
    expect(openMinutes(snap.rows.first, DateTime.utc(2026, 7, 12)), isNull);
    // A missing summary block degrades to zeroes, never to invented counts.
    expect(snap.summary.total, 0);
    expect(snap.summary.unpaid, 0);
    expect(snap.summary.stage('ready'), 0);
    expect(snap.summary.served, 0);
  });
}
