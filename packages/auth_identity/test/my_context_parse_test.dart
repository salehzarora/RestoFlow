import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

/// A minimal valid `app_user` object.
Map<String, dynamic> appUser({
  String? displayName = 'Multi U',
  bool isActive = true,
}) => {
  'id': 'user-1',
  'email': 'multi@example.test',
  'display_name': displayName,
  'is_active': isActive,
};

/// A membership object with sensible defaults; override any field.
Map<String, dynamic> membership({
  String id = 'm-a',
  String organizationId = 'org-a',
  String organizationName = 'Org A',
  String? restaurantId,
  String? restaurantName,
  String? branchId,
  String? branchName,
  String role = 'org_owner',
  String status = 'active',
}) => {
  'id': id,
  'organization_id': organizationId,
  'organization_name': organizationName,
  'restaurant_id': restaurantId,
  'restaurant_name': restaurantName,
  'branch_id': branchId,
  'branch_name': branchName,
  'role': role,
  'status': status,
};

Map<String, dynamic> context({
  Map<String, dynamic>? user,
  bool isPlatformAdmin = false,
  List<Map<String, dynamic>>? memberships,
}) => {
  'ok': true,
  'app_user': user ?? appUser(),
  'is_platform_admin': isPlatformAdmin,
  'memberships': memberships ?? [membership()],
};

void main() {
  group('MyContext.fromJson - valid', () {
    test(
      'parses a full multi-membership context (per-membership role, no global role)',
      () {
        final ctx = MyContext.fromJson(
          context(
            memberships: [
              membership(
                id: 'm-a',
                organizationId: 'org-a',
                organizationName: 'Org A',
                restaurantId: 'rest-a1',
                restaurantName: 'Rest A1',
                branchId: 'branch-a1',
                branchName: 'Branch A1',
                role: 'org_owner',
              ),
              membership(
                id: 'm-b',
                organizationId: 'org-b',
                organizationName: 'Org B',
                role: 'manager',
              ),
            ],
          ),
        );
        expect(ctx.appUser.id, 'user-1');
        expect(ctx.appUser.email, 'multi@example.test');
        expect(ctx.appUser.isActive, isTrue);
        expect(ctx.isPlatformAdmin, isFalse);
        expect(ctx.memberships, hasLength(2));
        // role is per-membership, not a single global role.
        expect(ctx.memberships[0].role, MembershipRole.orgOwner);
        expect(ctx.memberships[1].role, MembershipRole.manager);
        expect(ctx.memberships[0].organizationName, 'Org A');
        expect(ctx.memberships[0].restaurantName, 'Rest A1');
        expect(ctx.memberships[0].branchName, 'Branch A1');
      },
    );

    test('null display_name is allowed', () {
      final ctx = MyContext.fromJson(context(user: appUser(displayName: null)));
      expect(ctx.appUser.displayName, isNull);
      expect(ctx.appUser.email, isNotNull);
    });

    test('org-wide membership has null restaurant/branch fields', () {
      final ctx = MyContext.fromJson(
        context(memberships: [membership(role: 'manager')]),
      );
      final m = ctx.memberships.single;
      expect(m.restaurantId, isNull);
      expect(m.restaurantName, isNull);
      expect(m.branchId, isNull);
      expect(m.branchName, isNull);
    });

    test('empty memberships parse to an empty list (ok:true, not 42501)', () {
      final ctx = MyContext.fromJson(context(memberships: const []));
      expect(ctx.memberships, isEmpty);
      expect(ctx.isPlatformAdmin, isFalse);
    });

    test('platform admin with empty memberships', () {
      final ctx = MyContext.fromJson(
        context(isPlatformAdmin: true, memberships: const []),
      );
      expect(ctx.isPlatformAdmin, isTrue);
      expect(ctx.memberships, isEmpty);
    });
  });

  group('MyContext.fromJson - fail-closed', () {
    test('unknown membership role throws UnknownRoleException', () {
      expect(
        () => MyContext.fromJson(
          context(memberships: [membership(role: 'superuser')]),
        ),
        throwsA(isA<UnknownRoleException>()),
      );
    });

    test(
      'platform_admin as a membership role is rejected (not a tenant role)',
      () {
        expect(
          () => MyContext.fromJson(
            context(memberships: [membership(role: 'platform_admin')]),
          ),
          throwsA(isA<UnknownRoleException>()),
        );
      },
    );

    test('ok != true throws FormatException (no ok:false envelope)', () {
      final bad = context()..['ok'] = false;
      expect(() => MyContext.fromJson(bad), throwsFormatException);
    });

    test('missing app_user throws FormatException', () {
      final bad = context()..remove('app_user');
      expect(() => MyContext.fromJson(bad), throwsFormatException);
    });

    test('missing is_platform_admin throws FormatException', () {
      final bad = context()..remove('is_platform_admin');
      expect(() => MyContext.fromJson(bad), throwsFormatException);
    });

    test('non-object input throws FormatException', () {
      expect(() => MyContext.fromJson('not an object'), throwsFormatException);
      expect(() => MyContext.fromJson(null), throwsFormatException);
    });

    test('app_user missing required id throws FormatException', () {
      final bad = context(user: {'email': 'x@y.z', 'is_active': true});
      expect(() => MyContext.fromJson(bad), throwsFormatException);
    });
  });
}
