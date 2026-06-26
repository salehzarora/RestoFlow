import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';

DemoAdminStore storeAs(MembershipRole role) =>
    DemoAdminStore(scope: AdminScope.demo.copyWith(actingRole: role));

T success<T>(Result<T, AdminFailure> r) =>
    r.fold((v) => v, (f) => throw StateError('expected success, got $f'));

AdminFailure failure<T>(Result<T, AdminFailure> r) =>
    r.fold((v) => throw StateError('expected failure, got success'), (f) => f);

void main() {
  group('DemoAdminStore — settings role-rank (D-033)', () {
    test('org_owner can update organization settings', () async {
      final r = await storeAs(MembershipRole.orgOwner)
          .updateOrganizationSettings(
            defaultCurrency: 'eur',
            countryCode: 'de',
            status: 'active',
          );
      expect(success(r).defaultCurrency, 'EUR'); // uppercased
      expect(success(r).countryCode, 'DE');
    });

    test('restaurant_owner CANNOT update organization settings', () async {
      final r = await storeAs(
        MembershipRole.restaurantOwner,
      ).updateOrganizationSettings(defaultCurrency: 'USD', status: 'active');
      expect(failure(r), isA<AdminPermissionDenied>());
    });

    test('restaurant_owner CAN update branch settings', () async {
      final r = await storeAs(
        MembershipRole.restaurantOwner,
      ).updateBranchSettings(name: 'Riverside', status: 'active');
      expect(success(r).name, 'Riverside');
    });

    test(
      'manager CANNOT update branch settings (rank < restaurant_owner)',
      () async {
        final r = await storeAs(
          MembershipRole.manager,
        ).updateBranchSettings(name: 'X', status: 'active');
        expect(failure(r), isA<AdminPermissionDenied>());
      },
    );

    test('invalid currency is rejected', () async {
      final r = await storeAs(
        MembershipRole.orgOwner,
      ).updateOrganizationSettings(defaultCurrency: 'US', status: 'active');
      expect(failure(r), isA<AdminValidation>());
    });
  });

  group('DemoAdminStore — users role-rank guard (D-033)', () {
    test('org_owner can grant a cashier', () async {
      final r = await storeAs(MembershipRole.orgOwner).grantMembership(
        displayName: 'New Person',
        email: 'new@x.test',
        role: MembershipRole.cashier,
      );
      expect(success(r).role, MembershipRole.cashier);
    });

    test('manager can grant a cashier but NOT a manager or owner', () async {
      final store = storeAs(MembershipRole.manager);
      expect(
        success(
          await store.grantMembership(
            displayName: 'A',
            email: 'a@x.test',
            role: MembershipRole.cashier,
          ),
        ).role,
        MembershipRole.cashier,
      );
      expect(
        failure(
          await store.grantMembership(
            displayName: 'B',
            email: 'b@x.test',
            role: MembershipRole.manager,
          ),
        ),
        isA<AdminPermissionDenied>(),
      );
      expect(
        failure(
          await store.grantMembership(
            displayName: 'C',
            email: 'c@x.test',
            role: MembershipRole.orgOwner,
          ),
        ),
        isA<AdminPermissionDenied>(),
      );
    });

    test('a bad email is rejected', () async {
      final r = await storeAs(MembershipRole.orgOwner).grantMembership(
        displayName: 'X',
        email: 'not-an-email',
        role: MembershipRole.cashier,
      );
      expect(failure(r), isA<AdminValidation>());
    });

    test('updating the acting user (self) is denied', () async {
      final store = storeAs(MembershipRole.orgOwner);
      final users = success(await store.loadUsers());
      final self = users.firstWhere((u) => u.isSelf);
      final r = await store.updateRole(
        userId: self.id,
        newRole: MembershipRole.manager,
      );
      expect(failure(r), isA<AdminPermissionDenied>());
    });

    test('cannot update a membership at or above the actor rank', () async {
      final store = storeAs(MembershipRole.manager);
      final users = success(await store.loadUsers());
      final anotherManager = users.firstWhere(
        (u) => u.role == MembershipRole.manager && !u.isSelf,
      );
      final r = await store.updateRole(
        userId: anotherManager.id,
        newRole: MembershipRole.cashier,
      );
      expect(failure(r), isA<AdminPermissionDenied>());
    });
  });

  group('DemoAdminStore — device lifecycle (D-033/D-034)', () {
    test(
      'full forward path create→issue→redeem→approve→activate→session',
      () async {
        final store = storeAs(MembershipRole.orgOwner);
        final device = success(
          await store.createDevice(label: 'New POS', deviceType: 'pos'),
        );
        expect(device.status, DeviceLifecycleStatus.none);

        final issued = success(await store.issueEnrollmentCode(device.id));
        expect(issued.code, isNotEmpty);

        expect(
          success(await store.redeemEnrollmentCode(device.id)).status,
          DeviceLifecycleStatus.pending,
        );
        expect(
          success(await store.approveDevice(device.id)).status,
          DeviceLifecycleStatus.paired,
        );
        expect(
          success(await store.activateDevice(device.id)).status,
          DeviceLifecycleStatus.active,
        );
        final session = success(await store.startDeviceSession(device.id));
        expect(session.token, isNotEmpty);
      },
    );

    test('pending → active is impossible (must approve first)', () async {
      final store = storeAs(MembershipRole.orgOwner);
      final device = success(
        await store.createDevice(label: 'D', deviceType: 'pos'),
      );
      await store.issueEnrollmentCode(device.id);
      await store.redeemEnrollmentCode(device.id); // now pending
      final r = await store.activateDevice(device.id);
      expect(failure(r), isA<AdminConflict>());
    });

    test('a session requires an active pairing (paired is rejected)', () async {
      final store = storeAs(MembershipRole.orgOwner);
      final device = success(
        await store.createDevice(label: 'D', deviceType: 'pos'),
      );
      await store.issueEnrollmentCode(device.id);
      await store.redeemEnrollmentCode(device.id);
      await store.approveDevice(device.id); // now paired (not active)
      final r = await store.startDeviceSession(device.id);
      expect(failure(r), isA<AdminConflict>());
    });

    test('cashier cannot provision a device', () async {
      final r = await storeAs(
        MembershipRole.cashier,
      ).createDevice(label: 'D', deviceType: 'pos');
      expect(failure(r), isA<AdminPermissionDenied>());
    });

    test('two issued codes are distinct one-time secrets', () async {
      final store = storeAs(MembershipRole.orgOwner);
      final d1 = success(
        await store.createDevice(label: 'A', deviceType: 'pos'),
      );
      final d2 = success(
        await store.createDevice(label: 'B', deviceType: 'pos'),
      );
      final c1 = success(await store.issueEnrollmentCode(d1.id)).code;
      final c2 = success(await store.issueEnrollmentCode(d2.id)).code;
      expect(c1, isNot(c2));
    });
  });
}
