import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:test/test.dart';

MembershipContext mem(String id, MembershipRole role, {String org = 'org-a'}) =>
    MembershipContext(
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

MyContext ctx({
  bool admin = false,
  List<MembershipContext> memberships = const [],
}) => MyContext(
  appUser: const AppUserContext(
    id: 'u',
    email: 'u@x.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: admin,
  memberships: memberships,
);

Result<MyContext, AuthFailure> ok(MyContext c) => Success(c);
Result<MyContext, AuthFailure> err(AuthFailure f) => Failure(f);

AuthGateState resolve(
  AppSurface surface,
  Result<MyContext, AuthFailure>? result, {
  String? selected,
}) => resolveAuthGateState(
  surface: surface,
  contextResult: result,
  selectedMembershipId: selected,
);

void main() {
  test('null result -> loading', () {
    expect(resolve(AppSurface.pos, null), isA<AuthGateLoading>());
  });

  group('failure mapping', () {
    test('unauthenticated', () {
      expect(
        resolve(AppSurface.pos, err(const AuthUnauthenticatedFailure())),
        isA<AuthGateUnauthenticated>(),
      );
    });
    test('42501 -> auth denied', () {
      expect(
        resolve(AppSurface.pos, err(const AuthDeniedFailure())),
        isA<AuthGateAuthDenied>(),
      );
    });
    test('invalid / network / unknown -> invalid response', () {
      expect(
        resolve(AppSurface.pos, err(const AuthInvalidResponseFailure())),
        isA<AuthGateInvalidResponse>(),
      );
      expect(
        resolve(AppSurface.pos, err(const AuthNetworkFailure())),
        isA<AuthGateInvalidResponse>(),
      );
      expect(
        resolve(AppSurface.pos, err(const AuthUnknownRoleFailure('x'))),
        isA<AuthGateInvalidResponse>(),
      );
    });
  });

  group('tenant surface membership states', () {
    test('no memberships (not platform admin) -> noMemberships', () {
      expect(resolve(AppSurface.pos, ok(ctx())), isA<AuthGateNoMemberships>());
    });

    test(
      'platform admin with no memberships -> platformAdminNoMemberships',
      () {
        expect(
          resolve(AppSurface.pos, ok(ctx(admin: true))),
          isA<AuthGatePlatformAdminNoMemberships>(),
        );
      },
    );

    test(
      'multiple memberships, none selected -> pickerNeeded with the list',
      () {
        final state = resolve(
          AppSurface.pos,
          ok(
            ctx(
              memberships: [
                mem('a', MembershipRole.cashier),
                mem('b', MembershipRole.manager, org: 'org-b'),
              ],
            ),
          ),
        );
        expect(state, isA<AuthGatePickerNeeded>());
        expect((state as AuthGatePickerNeeded).memberships, hasLength(2));
      },
    );

    test('single allowed membership -> ready with that membership', () {
      final state = resolve(
        AppSurface.pos,
        ok(ctx(memberships: [mem('a', MembershipRole.cashier)])),
      );
      expect(state, isA<AuthGateReady>());
      expect((state as AuthGateReady).membership.id, 'a');
    });

    test('multi + valid selection -> ready', () {
      final state = resolve(
        AppSurface.pos,
        ok(
          ctx(
            memberships: [
              mem('a', MembershipRole.cashier),
              mem('b', MembershipRole.manager, org: 'org-b'),
            ],
          ),
        ),
        selected: 'b',
      );
      expect(state, isA<AuthGateReady>());
      expect((state as AuthGateReady).membership.id, 'b');
    });

    test('wrong role for the surface -> wrongRole', () {
      // kitchen_staff cannot enter POS.
      final state = resolve(
        AppSurface.pos,
        ok(ctx(memberships: [mem('a', MembershipRole.kitchenStaff)])),
      );
      expect(state, isA<AuthGateWrongRole>());
      expect((state as AuthGateWrongRole).role, MembershipRole.kitchenStaff);
    });

    test('accountant -> deferredRole (never crashes/grants)', () {
      final state = resolve(
        AppSurface.dashboard,
        ok(ctx(memberships: [mem('a', MembershipRole.accountant)])),
      );
      expect(state, isA<AuthGateDeferredRole>());
      expect((state as AuthGateDeferredRole).role, MembershipRole.accountant);
    });

    test('invalid selected membership id fails closed -> pickerNeeded', () {
      final state = resolve(
        AppSurface.pos,
        ok(
          ctx(
            memberships: [
              mem('a', MembershipRole.cashier),
              mem('b', MembershipRole.manager, org: 'org-b'),
            ],
          ),
        ),
        selected: 'ghost',
      );
      expect(state, isA<AuthGatePickerNeeded>());
    });
  });

  group('admin surface (gated by platform-admin flag, D-026)', () {
    test('platform admin -> platformAdminReady (no membership needed)', () {
      expect(
        resolve(AppSurface.admin, ok(ctx(admin: true))),
        isA<AuthGatePlatformAdminReady>(),
      );
    });

    test(
      'a tenant role (even org_owner) without the flag -> wrongRole(null)',
      () {
        final state = resolve(
          AppSurface.admin,
          ok(ctx(memberships: [mem('a', MembershipRole.orgOwner)])),
        );
        expect(state, isA<AuthGateWrongRole>());
        expect((state as AuthGateWrongRole).role, isNull);
      },
    );
  });
}
