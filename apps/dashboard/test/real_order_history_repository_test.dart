import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/data/real_order_history_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RealRepoNotWiredError;

/// ORDERS-HISTORY-001 — the real repo maps `owner_order_history` /
/// `owner_order_detail` into the history models (integer minor throughout), calls
/// the right RPCs with the scoped `p_*` params, and fails closed with no
/// transport/scope or on a rejected/failed RPC.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);

  final Object? Function(String function, Map<String, dynamic> params) _handler;

  String? lastFunction;
  Map<String, dynamic>? lastParams;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    lastFunction = function;
    lastParams = params;
    return _handler(function, params);
  }
}

MembershipContext _scope() => const MembershipContext(
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

Map<String, dynamic> _historyPayload() => <String, dynamic>{
  'ok': true,
  'entity': 'owner_order_history',
  'currency_code': 'ILS',
  'range': 'today',
  'limit': 25,
  'orders': <Map<String, dynamic>>[
    {
      'order_id': 'o1',
      'order_code': '#01D001',
      'receipt_number': 'R-100',
      'status': 'completed',
      'order_type': 'dine_in',
      'customer_name': 'Layla',
      'table_label': 'T1',
      'staff_name': 'Amira K.',
      'created_at': '2026-07-09 10:00',
      'item_count': 2,
      'subtotal_minor': 1000,
      'discount_total_minor': 0,
      'tax_total_minor': 0,
      'grand_total_minor': 1000,
      'payment_method': 'cash',
      'payment_status': 'paid',
      'paid_amount_minor': 1000,
    },
    {
      'order_id': 'o2',
      'order_code': '#01D002',
      'receipt_number': null,
      'status': 'submitted',
      'order_type': 'takeaway',
      'customer_name': null,
      'table_label': null,
      'staff_name': 'Amira K.',
      'created_at': '2026-07-09 11:00',
      'item_count': 1,
      'subtotal_minor': 500,
      'discount_total_minor': 0,
      'tax_total_minor': 0,
      'grand_total_minor': 500,
      'payment_method': null,
      'payment_status': 'unpaid',
      'paid_amount_minor': null,
    },
  ],
  'has_more': true,
  'next_cursor': '2026-07-09 10:00:00+00|o1',
  'count': 2,
};

Map<String, dynamic> _detailPayload() => <String, dynamic>{
  'ok': true,
  'entity': 'owner_order_detail',
  'currency_code': 'ILS',
  'order': <String, dynamic>{
    'order_id': 'o1',
    'order_code': '#01D001',
    'receipt_number': 'R-100',
    'status': 'completed',
    'order_type': 'dine_in',
    'customer_name': 'Layla',
    'table_label': 'T1',
    'branch_name': 'Downtown',
    'staff_name': 'Amira K.',
    'notes': null,
    'created_at': '2026-07-09 10:00',
    'currency_code': 'ILS',
    'subtotal_minor': 1000,
    'discount_total_minor': 0,
    'tax_total_minor': 0,
    'grand_total_minor': 1000,
    'items': <Map<String, dynamic>>[
      {
        'order_item_id': 'i1',
        'name': 'Burger',
        'quantity': 2,
        'station_id': null,
        'notes': 'No pickles',
        'unit_price_minor': 500,
        'line_discount_minor': 0,
        'line_total_minor': 1000,
        'prep_snapshot': <Map<String, dynamic>>[
          {'name': 'Bun', 'quantity': 1, 'unit': 'pcs'},
        ],
        'modifiers': <Map<String, dynamic>>[
          {
            'option_name': 'Double',
            'modifier_name': 'Patty',
            'quantity': 1,
            'price_minor': 0,
            'meat_snapshot': {'quantity': 2, 'unit': 'patties'},
          },
        ],
      },
    ],
    'payments': <Map<String, dynamic>>[
      {
        'method': 'cash',
        'status': 'completed',
        'amount_minor': 1000,
        'tendered_minor': 1000,
        'change_minor': 0,
        'receipt_number': 'R-100',
        'created_at': '2026-07-09 10:01',
      },
    ],
  },
};

void main() {
  test('loadHistory calls owner_order_history with scoped params and maps rows '
      '(integer minor)', () async {
    final transport = _FakeTransport((_, _) => _historyPayload());
    final repo = RealOrderHistoryRepository(
      null,
      scope: _scope(),
      transport: transport,
    );

    final page = await repo.loadHistory(const OrderHistoryQuery());

    expect(transport.lastFunction, 'owner_order_history');
    expect(transport.lastParams, {
      'p_organization_id': 'org-1',
      'p_restaurant_id': 'rest-1',
      'p_branch_id': 'branch-1',
      'p_range': 'today',
      'p_search': null,
      'p_status': null,
      'p_order_type': null,
      'p_payment': null,
      'p_limit': 25,
      'p_cursor': null,
    });

    expect(page.rows.length, 2);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, '2026-07-09 10:00:00+00|o1');
    final r0 = page.rows.first;
    expect(r0.orderCode, '#01D001');
    expect(r0.customerName, 'Layla');
    expect(r0.tableLabel, 'T1');
    expect(r0.itemCount, 2);
    expect(r0.grandTotalMinor, 1000);
    expect(r0.grandTotalMinor, isA<int>());
    expect(r0.paid, isTrue);
    expect(r0.paymentMethod, 'cash');
    expect(r0.paidAmountMinor, 1000);
    final r1 = page.rows[1];
    expect(r1.customerName, isNull);
    expect(r1.paid, isFalse);
    expect(r1.paymentMethod, isNull);
    expect(r1.paidAmountMinor, isNull);
  });

  test('loadHistory threads filters + cursor into the RPC params', () async {
    final transport = _FakeTransport((_, _) => _historyPayload());
    final repo = RealOrderHistoryRepository(
      null,
      scope: _scope(),
      transport: transport,
    );

    await repo.loadHistory(
      const OrderHistoryQuery(
        range: OrderHistoryRange.last7,
        search: '  Layla ',
        status: OrderStatusFilter.completed,
        orderType: OrderTypeFilter.dineIn,
        payment: PaymentFilter.cash,
      ),
      cursor: 'cur-1',
    );

    expect(transport.lastParams, {
      'p_organization_id': 'org-1',
      'p_restaurant_id': 'rest-1',
      'p_branch_id': 'branch-1',
      'p_range': 'last7',
      'p_search': 'Layla',
      'p_status': 'completed',
      'p_order_type': 'dine_in',
      'p_payment': 'cash',
      'p_limit': 25,
      'p_cursor': 'cur-1',
    });
  });

  test('loadDetail calls owner_order_detail and maps items/modifiers(meat)/'
      'prep/payments (integer minor)', () async {
    final transport = _FakeTransport((_, _) => _detailPayload());
    final repo = RealOrderHistoryRepository(
      null,
      scope: _scope(),
      transport: transport,
    );

    final detail = await repo.loadDetail('o1');

    expect(transport.lastFunction, 'owner_order_detail');
    expect(transport.lastParams, {
      'p_organization_id': 'org-1',
      'p_restaurant_id': 'rest-1',
      'p_branch_id': 'branch-1',
      'p_order_id': 'o1',
    });

    expect(detail.orderCode, '#01D001');
    expect(detail.customerName, 'Layla');
    expect(detail.branchName, 'Downtown');
    expect(detail.grandTotalMinor, 1000);
    expect(detail.grandTotalMinor, isA<int>());
    expect(detail.items.length, 1);
    final item = detail.items.single;
    expect(item.name, 'Burger');
    expect(item.quantity, 2);
    expect(item.notes, 'No pickles');
    expect(item.lineTotalMinor, 1000);
    expect(item.prepComponents.single.name, 'Bun');
    expect(item.modifiers.single.optionName, 'Double');
    expect(item.modifiers.single.meatUnit, 'patties');
    expect(item.modifiers.single.meatQuantity, 2);
    expect(detail.payments.single.method, 'cash');
    expect(detail.completedPayment?.amountMinor, 1000);

    // The kitchen count aggregates 2 patties × 1 modifier × 2 items = 4.
    final counts = aggregateKitchenCounts(detail);
    expect(counts.single.unit, 'patties');
    expect(counts.single.quantity, 4);
  });

  test('fail-closed: no transport/scope -> RealRepoNotWiredError', () async {
    expect(
      RealOrderHistoryRepository(
        null,
        scope: _scope(),
        transport: null,
      ).loadHistory(const OrderHistoryQuery()),
      throwsA(isA<RealRepoNotWiredError>()),
    );
    final t = _FakeTransport((_, _) => _historyPayload());
    expect(
      RealOrderHistoryRepository(
        null,
        scope: null,
        transport: t,
      ).loadDetail('o1'),
      throwsA(isA<RealRepoNotWiredError>()),
    );
  });

  test(
    'fail-closed: ok!=true -> OrderHistoryException (list + detail)',
    () async {
      final t = _FakeTransport(
        (_, _) => <String, dynamic>{'ok': false, 'error': 'permission_denied'},
      );
      final repo = RealOrderHistoryRepository(
        null,
        scope: _scope(),
        transport: t,
      );
      expect(
        repo.loadHistory(const OrderHistoryQuery()),
        throwsA(isA<OrderHistoryException>()),
      );
      expect(repo.loadDetail('o1'), throwsA(isA<OrderHistoryException>()));
    },
  );

  test(
    'fail-closed: a transport failure (even auth) -> OrderHistoryException',
    () async {
      final t = _FakeTransport(
        (_, _) => throw const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
        ),
      );
      expect(
        RealOrderHistoryRepository(
          null,
          scope: _scope(),
          transport: t,
        ).loadHistory(const OrderHistoryQuery()),
        throwsA(isA<OrderHistoryException>()),
      );
    },
  );

  test('a not_found detail body fails closed (never fabricates)', () async {
    final t = _FakeTransport(
      (_, _) => <String, dynamic>{'ok': false, 'error': 'not_found'},
    );
    expect(
      RealOrderHistoryRepository(
        null,
        scope: _scope(),
        transport: t,
      ).loadDetail('missing'),
      throwsA(isA<OrderHistoryException>()),
    );
  });
}
