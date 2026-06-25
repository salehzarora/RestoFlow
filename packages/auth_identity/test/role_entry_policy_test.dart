import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

void main() {
  const policy = RoleEntryPolicy();

  EntryDecision decide(
    AppSurface surface,
    MembershipRole? role, {
    bool admin = false,
  }) => policy.evaluate(surface: surface, role: role, isPlatformAdmin: admin);

  group('POS entry', () {
    test('allows org_owner / restaurant_owner / manager / cashier', () {
      for (final role in [
        MembershipRole.orgOwner,
        MembershipRole.restaurantOwner,
        MembershipRole.manager,
        MembershipRole.cashier,
      ]) {
        expect(
          decide(AppSurface.pos, role),
          EntryDecision.allowed,
          reason: '$role',
        );
      }
    });
    test('denies kitchen_staff', () {
      expect(
        decide(AppSurface.pos, MembershipRole.kitchenStaff),
        EntryDecision.denied,
      );
    });
  });

  group('KDS entry', () {
    test('allows org_owner / restaurant_owner / manager / kitchen_staff', () {
      for (final role in [
        MembershipRole.orgOwner,
        MembershipRole.restaurantOwner,
        MembershipRole.manager,
        MembershipRole.kitchenStaff,
      ]) {
        expect(
          decide(AppSurface.kds, role),
          EntryDecision.allowed,
          reason: '$role',
        );
      }
    });
    test('denies cashier', () {
      expect(
        decide(AppSurface.kds, MembershipRole.cashier),
        EntryDecision.denied,
      );
    });
  });

  group('Dashboard entry', () {
    test('allows org_owner / restaurant_owner / manager', () {
      for (final role in [
        MembershipRole.orgOwner,
        MembershipRole.restaurantOwner,
        MembershipRole.manager,
      ]) {
        expect(
          decide(AppSurface.dashboard, role),
          EntryDecision.allowed,
          reason: '$role',
        );
      }
    });
    test('denies cashier and kitchen_staff', () {
      expect(
        decide(AppSurface.dashboard, MembershipRole.cashier),
        EntryDecision.denied,
      );
      expect(
        decide(AppSurface.dashboard, MembershipRole.kitchenStaff),
        EntryDecision.denied,
      );
    });
  });

  group('Admin entry (platform_admin flag only, D-026)', () {
    test('allowed only when isPlatformAdmin is true', () {
      expect(
        decide(AppSurface.admin, null, admin: true),
        EntryDecision.allowed,
      );
    });
    test('denied for any tenant role without the flag (even org_owner)', () {
      expect(
        decide(AppSurface.admin, MembershipRole.orgOwner),
        EntryDecision.denied,
      );
      expect(decide(AppSurface.admin, null), EntryDecision.denied);
    });
  });

  group('accountant is deferred (Q-017), never crashes', () {
    test('deferred on every tenant surface', () {
      expect(
        decide(AppSurface.pos, MembershipRole.accountant),
        EntryDecision.deferred,
      );
      expect(
        decide(AppSurface.kds, MembershipRole.accountant),
        EntryDecision.deferred,
      );
      expect(
        decide(AppSurface.dashboard, MembershipRole.accountant),
        EntryDecision.deferred,
      );
    });
  });

  group('no active role', () {
    test('null role is denied on tenant surfaces', () {
      expect(decide(AppSurface.pos, null), EntryDecision.denied);
      expect(decide(AppSurface.kds, null), EntryDecision.denied);
      expect(decide(AppSurface.dashboard, null), EntryDecision.denied);
    });
  });
}
