import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

MembershipContext m(
  String id, {
  MembershipRole role = MembershipRole.manager,
  String org = 'org',
}) => MembershipContext(
  id: id,
  organizationId: org,
  organizationName: 'Org $org',
  restaurantId: null,
  restaurantName: null,
  branchId: null,
  branchName: null,
  role: role,
  status: 'active',
);

void main() {
  group('MembershipSelection - zero memberships', () {
    test('no memberships, not platform admin -> noMemberships, no active', () {
      const sel = MembershipSelection(memberships: [], isPlatformAdmin: false);
      expect(sel.status, MembershipSelectionStatus.noMemberships);
      expect(sel.activeMembership, isNull);
    });

    test(
      'platform admin with zero memberships -> platformAdminNoMemberships',
      () {
        const sel = MembershipSelection(memberships: [], isPlatformAdmin: true);
        expect(
          sel.status,
          MembershipSelectionStatus.platformAdminNoMemberships,
        );
        expect(sel.activeMembership, isNull); // no tenant scope derived (D-026)
      },
    );
  });

  group('MembershipSelection - single membership', () {
    test(
      'exactly one -> autoSelected and active without any explicit selection',
      () {
        final sel = MembershipSelection(
          memberships: [m('a')],
          isPlatformAdmin: false,
        );
        expect(sel.status, MembershipSelectionStatus.autoSelected);
        expect(sel.activeMembership?.id, 'a');
      },
    );
  });

  group('MembershipSelection - multi membership', () {
    final twoOrgs = [m('a', org: 'a'), m('b', org: 'b')];

    test('more than one and none selected -> pickerNeeded, no active', () {
      final sel = MembershipSelection(
        memberships: twoOrgs,
        isPlatformAdmin: false,
      );
      expect(sel.status, MembershipSelectionStatus.pickerNeeded);
      expect(sel.activeMembership, isNull);
    });

    test('selecting a valid id -> selected and active', () {
      final sel = MembershipSelection(
        memberships: twoOrgs,
        isPlatformAdmin: false,
      ).select('b');
      expect(sel.status, MembershipSelectionStatus.selected);
      expect(sel.activeMembership?.id, 'b');
    });

    test('invalid selected id fails closed (no active, pickerNeeded)', () {
      final sel = MembershipSelection(
        memberships: twoOrgs,
        isPlatformAdmin: false,
      ).select('ghost');
      expect(sel.activeMembership, isNull);
      expect(sel.status, MembershipSelectionStatus.pickerNeeded);
    });

    test('cleared() drops the selection (modeled sign-out)', () {
      final sel = MembershipSelection(
        memberships: twoOrgs,
        isPlatformAdmin: false,
      ).select('a').cleared();
      expect(sel.selectedMembershipId, isNull);
      expect(sel.activeMembership, isNull);
    });
  });

  test('fromContext carries memberships + platform flag', () {
    final ctx = MyContext.fromJson({
      'ok': true,
      'app_user': {
        'id': 'u',
        'email': 'u@x.test',
        'display_name': null,
        'is_active': true,
      },
      'is_platform_admin': true,
      'memberships': const [],
    });
    final sel = MembershipSelection.fromContext(ctx);
    expect(sel.isPlatformAdmin, isTrue);
    expect(sel.status, MembershipSelectionStatus.platformAdminNoMemberships);
  });
}
