import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';

/// ORDER-EDIT-001E — the POS reads the two ORDER-EDIT-001B additions to
/// `pin_session_capabilities` (API_CONTRACT §4.30b):
///
///  * `capabilities.void_order` — UNKNOWN IS NOT DENIED: an absent key is
///    null (the removing controls stay usable, the server decides); a present
///    non-boolean is malformed and reads false;
///  * the top-level `branch_features` sibling — parsed atomically, and an
///    unknown rollout gate is null (which HIDES "Edit order").
///
/// Plus the role gate `canEditOrders`: `kitchen_staff` reads `void_order`
/// FALSE, but `app.edit_order` refuses that role every edit, so the entry
/// gates on the role.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.response);

  final Object? response;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return response;
  }
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

/// The exact ORDER-EDIT-001B success envelope (migration 20261008190000,
/// app.pin_session_capabilities).
Map<String, Object?> _envelope001B({
  String role = 'cashier',
  bool voidOrder = true,
  bool enabled = true,
  bool finishedFood = false,
}) => {
  'ok': true,
  'entity': 'pin_session',
  'role': role,
  'capabilities': {
    'apply_discount': true,
    'apply_full_comp': false,
    'manage_menu_availability': true,
    'manage_table_operations': true,
    'open_cash_drawer': false,
    'void_order': voidOrder,
  },
  'branch_features': {
    'order_edit_enabled': enabled,
    'order_edit_finished_food_manager_only': finishedFood,
  },
};

/// A server that predates ORDER-EDIT-001B: no void_order, no branch_features.
Map<String, Object?> _envelopePre001B() => {
  'ok': true,
  'entity': 'pin_session',
  'role': 'cashier',
  'capabilities': {
    'apply_discount': true,
    'apply_full_comp': false,
    'manage_menu_availability': true,
    'manage_table_operations': true,
    'open_cash_drawer': false,
  },
};

void main() {
  group('void_order — unknown is not denied', () {
    test('true / false / missing / malformed', () {
      expect(
        PosStaffCapabilities.fromJson(const {'void_order': true}).voidOrder,
        isTrue,
      );
      expect(
        PosStaffCapabilities.fromJson(const {'void_order': false}).voidOrder,
        isFalse,
      );
      expect(
        PosStaffCapabilities.fromJson(const {}).voidOrder,
        isNull,
        reason: 'an older server that never sends the key is UNKNOWN',
      );
      for (final junk in <Object?>['yes', 'true', 1, null]) {
        expect(
          PosStaffCapabilities.fromJson({'void_order': junk}).voidOrder,
          isFalse,
          reason:
              'a present, malformed value never manufactures a grant: '
              '$junk',
        );
      }
    });

    test('the fail-closed default grants nothing and knows no switch', () {
      expect(PosStaffCapabilities.none.voidOrder, isFalse);
      expect(PosStaffCapabilities.none.branchFeatures, isNull);
      expect(PosStaffCapabilities.none.canEditOrders, isFalse);
    });
  });

  group('branch_features — atomic, unknown hides', () {
    test('a valid object parses both switches', () {
      final f = PosBranchFeatures.tryParse(const {
        'order_edit_enabled': true,
        'order_edit_finished_food_manager_only': false,
      });
      expect(f, isNotNull);
      expect(f!.orderEditEnabled, isTrue);
      expect(f.finishedFoodManagerOnly, isFalse);

      final g = PosBranchFeatures.tryParse(const {
        'order_edit_enabled': false,
        'order_edit_finished_food_manager_only': true,
        'some_future_switch': 'ignored',
      });
      expect(g!.orderEditEnabled, isFalse);
      expect(g.finishedFoodManagerOnly, isTrue);
    });

    test('missing, non-map or non-boolean values are null', () {
      for (final raw in <Object?>[
        null,
        'x',
        <Object?>[],
        const <String, Object?>{},
        const {'order_edit_enabled': true},
        const {
          'order_edit_enabled': 'true',
          'order_edit_finished_food_manager_only': false,
        },
        const {
          'order_edit_enabled': true,
          'order_edit_finished_food_manager_only': 1,
        },
        const {
          'order_edit_enabled': null,
          'order_edit_finished_food_manager_only': false,
        },
      ]) {
        expect(PosBranchFeatures.tryParse(raw), isNull, reason: '$raw');
      }
    });

    test('fromJson reads the sibling passed in, never the capability map', () {
      final inside = PosStaffCapabilities.fromJson(const {
        'branch_features': {
          'order_edit_enabled': true,
          'order_edit_finished_food_manager_only': false,
        },
      });
      expect(
        inside.branchFeatures,
        isNull,
        reason: 'branch_features is a top-level sibling of capabilities',
      );
      final sibling = PosStaffCapabilities.fromJson(
        const {},
        branchFeatures: const {
          'order_edit_enabled': true,
          'order_edit_finished_food_manager_only': false,
        },
      );
      expect(sibling.branchFeatures?.orderEditEnabled, isTrue);
    });
  });

  group('canEditOrders — the roles app.edit_order accepts', () {
    test('every role', () {
      const allowed = {'cashier', 'manager', 'restaurant_owner', 'org_owner'};
      for (final role in [...allowed, 'kitchen_staff', 'accountant', 'x']) {
        expect(
          PosStaffCapabilities.fromJson(const {}, role: role).canEditOrders,
          allowed.contains(role),
          reason: role,
        );
      }
      expect(PosStaffCapabilities.fromJson(const {}).canEditOrders, isFalse);
      expect(
        PosStaffCapabilities.fromJson(const {}, role: 7).canEditOrders,
        isFalse,
      );
    });

    test('kitchen_staff is refused even with void_order and the switch', () {
      final caps = PosStaffCapabilities.fromJson(
        const {'void_order': true},
        role: 'kitchen_staff',
        branchFeatures: const {
          'order_edit_enabled': true,
          'order_edit_finished_food_manager_only': false,
        },
      );
      expect(caps.canEditOrders, isFalse);
    });
  });

  group('RealStaffCapabilitiesRepository over the wire', () {
    test('the exact 001B envelope', () async {
      final transport = _FakeTransport(
        _envelope001B(role: 'manager', voidOrder: true, finishedFood: true),
      );
      final caps = await RealStaffCapabilitiesRepository(
        transport,
        _session,
      ).fetch();
      expect(transport.calls.single.$1, 'pin_session_capabilities');
      expect(caps, isNotNull);
      expect(caps!.role, 'manager');
      expect(caps.voidOrder, isTrue);
      expect(caps.branchFeatures?.orderEditEnabled, isTrue);
      expect(caps.branchFeatures?.finishedFoodManagerOnly, isTrue);
      expect(caps.canEditOrders, isTrue);
      // The existing capabilities are unaffected.
      expect(caps.applyDiscount, isTrue);
      expect(caps.applyFullComp, isFalse);
    });

    test('a cashier with void_order denied and the switch OFF', () async {
      final caps = await RealStaffCapabilitiesRepository(
        _FakeTransport(_envelope001B(voidOrder: false, enabled: false)),
        _session,
      ).fetch();
      expect(caps!.voidOrder, isFalse);
      expect(caps.branchFeatures?.orderEditEnabled, isFalse);
    });

    test('a pre-001B envelope: unknown, not denied, and Edit hidden', () async {
      final caps = await RealStaffCapabilitiesRepository(
        _FakeTransport(_envelopePre001B()),
        _session,
      ).fetch();
      expect(caps, isNotNull);
      expect(caps!.voidOrder, isNull);
      expect(caps.branchFeatures, isNull);
      expect(caps.applyDiscount, isTrue);
    });

    test('a malformed branch_features never fails the probe', () async {
      final envelope = _envelope001B()..['branch_features'] = 'on';
      final caps = await RealStaffCapabilitiesRepository(
        _FakeTransport(envelope),
        _session,
      ).fetch();
      expect(caps, isNotNull);
      expect(caps!.branchFeatures, isNull);
      expect(caps.voidOrder, isTrue);
    });
  });

  test('demo capabilities know no switch (Edit is hidden in demo)', () async {
    final caps = await const DemoStaffCapabilitiesRepository().fetch();
    expect(caps!.branchFeatures, isNull);
    expect(caps.voidOrder, isNull);
  });
}
