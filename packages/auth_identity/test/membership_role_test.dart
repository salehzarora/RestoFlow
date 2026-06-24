import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

void main() {
  group('MembershipRole', () {
    test('exposes exactly the six tenant role keys', () {
      expect(MembershipRole.values, hasLength(6));
      expect(MembershipRole.values.map((r) => r.wire).toList(), [
        'org_owner',
        'restaurant_owner',
        'manager',
        'cashier',
        'kitchen_staff',
        'accountant',
      ]);
    });

    test('tryFromWire maps each wire key to its role', () {
      expect(MembershipRole.tryFromWire('org_owner'), MembershipRole.orgOwner);
      expect(
        MembershipRole.tryFromWire('restaurant_owner'),
        MembershipRole.restaurantOwner,
      );
      expect(MembershipRole.tryFromWire('manager'), MembershipRole.manager);
      expect(MembershipRole.tryFromWire('cashier'), MembershipRole.cashier);
      expect(
        MembershipRole.tryFromWire('kitchen_staff'),
        MembershipRole.kitchenStaff,
      );
      expect(
        MembershipRole.tryFromWire('accountant'),
        MembershipRole.accountant,
      );
    });

    test('platform_admin is NOT a membership role (fail-closed null)', () {
      expect(MembershipRole.tryFromWire('platform_admin'), isNull);
    });

    test('unknown / empty role fails closed to null', () {
      expect(MembershipRole.tryFromWire('superuser'), isNull);
      expect(MembershipRole.tryFromWire('OrgOwner'), isNull); // case-sensitive
      expect(MembershipRole.tryFromWire(''), isNull);
    });
  });
}
