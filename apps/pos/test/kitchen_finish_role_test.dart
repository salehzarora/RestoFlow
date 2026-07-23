import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';

/// KITCHEN-PRINT-DUAL-001D — the bulk-finish visibility role gate. The role is
/// surfaced from the SAME `pin_session_capabilities` envelope (no new permission
/// model); the button is offered only to roles the server already authorizes to
/// change order kitchen statuses (kitchen_staff is a KDS role, not a POS one).
void main() {
  test('fromJson surfaces the top-level role', () {
    final caps = PosStaffCapabilities.fromJson(const {
      'apply_discount': true,
    }, role: 'manager');
    expect(caps.role, 'manager');
    expect(caps.applyDiscount, isTrue);
  });

  test('canFinishKitchenOrders is true for POS-authorized roles', () {
    for (final role in [
      'cashier',
      'manager',
      'restaurant_owner',
      'org_owner',
    ]) {
      expect(
        PosStaffCapabilities.fromJson(
          const {},
          role: role,
        ).canFinishKitchenOrders,
        isTrue,
        reason: role,
      );
    }
  });

  test('canFinishKitchenOrders is false for unauthorized/unknown roles', () {
    for (final role in ['accountant', 'kitchen_staff', 'nonsense', '']) {
      expect(
        PosStaffCapabilities.fromJson(
          const {},
          role: role,
        ).canFinishKitchenOrders,
        isFalse,
        reason: role,
      );
    }
    // A missing/malformed role resolves to DENIED (fail closed).
    expect(
      PosStaffCapabilities.fromJson(const {}).canFinishKitchenOrders,
      isFalse,
    );
    expect(
      PosStaffCapabilities.fromJson(const {}, role: 42).canFinishKitchenOrders,
      isFalse,
    );
    expect(PosStaffCapabilities.none.canFinishKitchenOrders, isFalse);
  });
}
