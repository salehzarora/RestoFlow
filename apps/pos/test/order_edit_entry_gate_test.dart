import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;

/// ORDER-EDIT-001E — the "Edit order" gate (`canEditOrder`) in the ONE action
/// policy, `resolveOrderActions` (ORDER_EDIT_DESIGN §6 / §7.1 step 1).
///
/// It copies the `canAddItems` interlocks (not `canVoid`) and adds: real mode,
/// an acknowledged submit, a known open status, the branch rollout switch ON
/// (hidden while unknown) and a role `app.edit_order` accepts. `void_order`
/// is deliberately not part of it. A pending `orderEdit` withdraws the money
/// actions exactly like a pending `itemsAdd`.

PosRecentOrder _order({
  String status = 'preparing',
  String? orderType = 'dine_in',
  PosSettlement settlement = PosSettlement.unpaid,
}) => PosRecentOrder.discovered(
  PosOrderSnapshot(
    orderId: 'o-1',
    orderCode: '#O00001',
    revision: 2,
    status: status,
    settlement: settlement,
    subtotalMinor: 2500,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 2500,
    createdAt: DateTime.utc(2026, 10, 8, 12),
    updatedAt: DateTime.utc(2026, 10, 8, 12),
    syncAt: DateTime.utc(2026, 10, 8, 12),
    orderType: orderType,
    tableLabel: 'T1',
    currencyCode: 'ILS',
  ),
);

PosStaffCapabilities _caps({
  Object? role = 'cashier',
  Object? branchFeatures = const {
    'order_edit_enabled': true,
    'order_edit_finished_food_manager_only': false,
  },
  Map<Object?, Object?> json = const {
    'apply_discount': true,
    'void_order': true,
  },
}) => PosStaffCapabilities.fromJson(
  json,
  role: role,
  branchFeatures: branchFeatures,
);

PosOrderActions _resolve(
  PosRecentOrder order, {
  PosStaffCapabilities? capabilities,
  bool useDefaultCaps = true,
  PosPendingKind? pending,
  bool submitUnacknowledged = false,
  bool amendmentsHydrating = false,
  bool isRealMode = true,
}) => resolveOrderActions(
  order,
  capabilities: capabilities ?? (useDefaultCaps ? _caps() : null),
  pending: pending,
  submitUnacknowledged: submitUnacknowledged,
  amendmentsHydrating: amendmentsHydrating,
  isRealMode: isRealMode,
);

const _open = ['submitted', 'accepted', 'preparing', 'ready', 'served'];

void main() {
  group('G1. eligible: dine-in and takeaway, submitted..served', () {
    test('every open status, both types', () {
      for (final type in ['dine_in', 'takeaway']) {
        for (final status in _open) {
          final a = _resolve(_order(status: status, orderType: type));
          expect(a.canEditOrder, isTrue, reason: '$type $status');
          expect(a.isEmpty, isFalse);
        }
      }
    });

    test('every role app.edit_order accepts', () {
      for (final role in [
        'cashier',
        'manager',
        'restaurant_owner',
        'org_owner',
      ]) {
        expect(
          _resolve(_order(), capabilities: _caps(role: role)).canEditOrder,
          isTrue,
          reason: role,
        );
      }
    });
  });

  group('G2. each interlock alone hides Edit', () {
    test('a terminal order', () {
      for (final s in ['completed', 'cancelled', 'voided']) {
        expect(_resolve(_order(status: s)).canEditOrder, isFalse, reason: s);
      }
    });

    test('a local draft, a never-created shell, no server id', () {
      final draft = PosRecentOrder(
        order: const SubmittedOrderView(
          orderNumber: '#D1',
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 2500,
          lines: [],
        ),
        submittedAt: DateTime.utc(2026, 10, 8, 12),
      );
      expect(draft.orderId, isNull);
      expect(_resolve(draft).canEditOrder, isFalse);

      final neverCreated = PosRecentOrder(
        order: const SubmittedOrderView(
          orderNumber: '#N1',
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 2500,
          orderId: 'o-n1',
          lines: [],
        ),
        submittedAt: DateTime.utc(2026, 10, 8, 12),
        neverCreated: true,
      );
      expect(neverCreated.isNeverCreated, isTrue);
      expect(_resolve(neverCreated).canEditOrder, isFalse);

      final localDraft = PosRecentOrder(
        order: const SubmittedOrderView(
          orderNumber: '#L1',
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 2500,
          orderId: 'o-l1',
          lines: [],
        ),
        submittedAt: DateTime.utc(2026, 10, 8, 12),
        syncState: PosOrderSyncState.localDraft,
        origin: PosOrderOrigin.localDraft,
      );
      expect(_resolve(localDraft).canEditOrder, isFalse);
    });

    test('charged: the server settlement, or no charge left to edit', () {
      expect(
        _resolve(_order(settlement: PosSettlement.paid)).canEditOrder,
        isFalse,
      );
    });

    test('every pending kind', () {
      for (final p in PosPendingKind.values) {
        expect(
          _resolve(_order(), pending: p).canEditOrder,
          isFalse,
          reason: p.name,
        );
      }
    });

    test('an unacknowledged submit', () {
      expect(
        _resolve(_order(), submitUnacknowledged: true).canEditOrder,
        isFalse,
      );
    });

    test('demo / not real mode, and the default fails closed', () {
      expect(_resolve(_order(), isRealMode: false).canEditOrder, isFalse);
      expect(
        resolveOrderActions(_order(), capabilities: _caps()).canEditOrder,
        isFalse,
        reason: 'a caller that does not say real mode never offers Edit',
      );
    });

    test('capabilities unknown, switch unknown, switch OFF', () {
      expect(
        _resolve(_order(), useDefaultCaps: false).canEditOrder,
        isFalse,
        reason: 'unknown capabilities: the rollout gate is unknown too',
      );
      expect(
        _resolve(
          _order(),
          capabilities: _caps(branchFeatures: null),
        ).canEditOrder,
        isFalse,
      );
      expect(
        _resolve(
          _order(),
          capabilities: _caps(
            branchFeatures: const {
              'order_edit_enabled': false,
              'order_edit_finished_food_manager_only': false,
            },
          ),
        ).canEditOrder,
        isFalse,
      );
      expect(
        _resolve(
          _order(),
          capabilities: _caps(
            branchFeatures: const {'order_edit_enabled': true},
          ),
        ).canEditOrder,
        isFalse,
        reason: 'a half-readable switch object is unknown',
      );
    });

    test('a role the server refuses, or none', () {
      for (final role in <Object?>['kitchen_staff', 'accountant', null]) {
        expect(
          _resolve(_order(), capabilities: _caps(role: role)).canEditOrder,
          isFalse,
          reason: '$role',
        );
      }
    });

    test('no order type, an unknown status, no status', () {
      expect(_resolve(_order(orderType: null)).canEditOrder, isFalse);
      expect(_resolve(_order(orderType: 'delivery')).canEditOrder, isFalse);
      expect(_resolve(_order(status: 'on_hold')).canEditOrder, isFalse);
      final unsynced = PosRecentOrder(
        order: const SubmittedOrderView(
          orderNumber: '#Q1',
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 2500,
          orderId: 'o-q1',
          lines: [],
        ),
        submittedAt: DateTime.utc(2026, 10, 8, 12),
      );
      expect(unsynced.serverStatus, isNull);
      expect(_resolve(unsynced).canAddItems, isTrue);
      expect(
        _resolve(unsynced).canEditOrder,
        isFalse,
        reason: 'an unknown status is never guessed editable',
      );
    });
  });

  group('G3. canAddItems is unchanged by every edit input', () {
    test('switch off, unacknowledged, demo, unknown role', () {
      final base = resolveOrderActions(_order()).canAddItems;
      expect(base, isTrue);
      for (final a in [
        _resolve(_order(), isRealMode: false),
        _resolve(_order(), submitUnacknowledged: true),
        _resolve(_order(), capabilities: _caps(branchFeatures: null)),
        _resolve(_order(), capabilities: _caps(role: 'kitchen_staff')),
        _resolve(_order(), useDefaultCaps: false),
      ]) {
        expect(a.canAddItems, base);
      }
    });
  });

  test('G4. void_order denied (or unknown) keeps Edit', () {
    expect(
      _resolve(
        _order(),
        capabilities: _caps(json: const {'void_order': false}),
      ).canEditOrder,
      isTrue,
      reason: 'additions and +1 stay possible without void_order',
    );
    expect(
      _resolve(_order(), capabilities: _caps(json: const {})).canEditOrder,
      isTrue,
    );
  });

  test('G5. a row offering only Edit is not empty', () {
    const onlyEdit = PosOrderActions(
      canPay: false,
      canDiscount: false,
      canFullComp: false,
      canVoid: false,
      canMoveTable: false,
      canOpenReceipt: false,
      pendingKind: null,
      canEditOrder: true,
    );
    expect(onlyEdit.isEmpty, isFalse);
    expect(onlyEdit.copyWith(canEditOrder: false).isEmpty, isTrue);
  });

  group('G6. a pending orderEdit withdraws the money actions', () {
    test('pay, discount, void, add, move and edit are withdrawn', () {
      final idle = _resolve(_order());
      expect(idle.canPay, isTrue);
      expect(idle.canDiscount, isTrue);
      expect(idle.canVoid, isTrue);
      expect(idle.canMoveTable, isTrue);
      expect(idle.canAddItems, isTrue);
      expect(idle.canPrintBill, isTrue);

      final a = _resolve(_order(), pending: PosPendingKind.orderEdit);
      expect(a.pendingKind, PosPendingKind.orderEdit);
      expect(a.canPay, isFalse);
      expect(a.canDiscount, isFalse);
      expect(a.canFullComp, isFalse);
      expect(a.canVoid, isFalse);
      expect(a.canMoveTable, isFalse);
      expect(a.canAddItems, isFalse);
      expect(a.canEditOrder, isFalse);
      expect(a.canPrintBill, isFalse, reason: 'the total is moving');
    });

    test('the startup blanket relaxes ONLY the pre-bill', () {
      final a = _resolve(
        _order(),
        pending: PosPendingKind.orderEdit,
        amendmentsHydrating: true,
      );
      expect(a.canPrintBill, isTrue);
      expect(a.canPay, isFalse);
      expect(a.canDiscount, isFalse);
      expect(a.canVoid, isFalse);
      expect(a.canMoveTable, isFalse);
      expect(a.canAddItems, isFalse);
      expect(a.canEditOrder, isFalse);
    });

    test('it matches a pending itemsAdd field for field', () {
      for (final hydrating in [false, true]) {
        final edit = _resolve(
          _order(),
          pending: PosPendingKind.orderEdit,
          amendmentsHydrating: hydrating,
        );
        final add = _resolve(
          _order(),
          pending: PosPendingKind.itemsAdd,
          amendmentsHydrating: hydrating,
        );
        expect(
          [
            edit.canPay,
            edit.canPrintBill,
            edit.canDiscount,
            edit.canFullComp,
            edit.canVoid,
            edit.canMoveTable,
            edit.canAddItems,
            edit.canEditOrder,
          ],
          [
            add.canPay,
            add.canPrintBill,
            add.canDiscount,
            add.canFullComp,
            add.canVoid,
            add.canMoveTable,
            add.canAddItems,
            add.canEditOrder,
          ],
        );
      }
    });
  });

  test('copyWith round-trips every field and keeps the pending kind', () {
    final a = _resolve(_order(status: 'served'));
    final same = a.copyWith();
    expect(
      [
        same.canPay,
        same.canPrintBill,
        same.canDiscount,
        same.canFullComp,
        same.canVoid,
        same.canMoveTable,
        same.canOpenReceipt,
        same.canAddItems,
        same.canComplete,
        same.submitUnacknowledged,
        same.canEditOrder,
        same.pendingKind,
      ],
      [
        a.canPay,
        a.canPrintBill,
        a.canDiscount,
        a.canFullComp,
        a.canVoid,
        a.canMoveTable,
        a.canOpenReceipt,
        a.canAddItems,
        a.canComplete,
        a.submitUnacknowledged,
        a.canEditOrder,
        a.pendingKind,
      ],
    );
    final flipped = a.copyWith(
      canPay: !a.canPay,
      canPrintBill: !a.canPrintBill,
      canDiscount: !a.canDiscount,
      canFullComp: !a.canFullComp,
      canVoid: !a.canVoid,
      canMoveTable: !a.canMoveTable,
      canOpenReceipt: !a.canOpenReceipt,
      canAddItems: !a.canAddItems,
      canComplete: !a.canComplete,
      submitUnacknowledged: !a.submitUnacknowledged,
      canEditOrder: !a.canEditOrder,
    );
    expect(flipped.canPay, !a.canPay);
    expect(flipped.canPrintBill, !a.canPrintBill);
    expect(flipped.canDiscount, !a.canDiscount);
    expect(flipped.canFullComp, !a.canFullComp);
    expect(flipped.canVoid, !a.canVoid);
    expect(flipped.canMoveTable, !a.canMoveTable);
    expect(flipped.canOpenReceipt, !a.canOpenReceipt);
    expect(flipped.canAddItems, !a.canAddItems);
    expect(flipped.canComplete, !a.canComplete);
    expect(flipped.submitUnacknowledged, !a.submitUnacknowledged);
    expect(flipped.canEditOrder, !a.canEditOrder);

    final pending = _resolve(_order(), pending: PosPendingKind.orderEdit);
    expect(
      pending.copyWith(canVoid: false).pendingKind,
      PosPendingKind.orderEdit,
    );
  });
}
