import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/auth/dashboard_auth_repository.dart';
import 'package:restoflow_dashboard/src/auth/login_signup_screen.dart';
import 'package:restoflow_dashboard/src/auth/onboarding_repository.dart';
import 'package:restoflow_dashboard/src/auth/onboarding_screen.dart';
import 'package:restoflow_dashboard/src/context/device_context.dart';
import 'package:restoflow_dashboard/src/context/selected_context_store.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// A controllable fake real-auth seam (no Supabase, no network).
class FakeAuthRepository implements DashboardAuthRepository {
  FakeAuthRepository({
    AuthSessionStatus initialStatus = AuthSessionStatus.signedOut,
  }) : _status = initialStatus;

  AuthSessionStatus _status;
  final _controller = StreamController<AuthSessionStatus>.broadcast();

  @override
  AuthSessionStatus get status => _status;

  @override
  Stream<AuthSessionStatus> get statusChanges => _controller.stream;

  @override
  Future<AuthOutcome> signIn({
    required String email,
    required String password,
  }) async => const AuthSignedIn();

  @override
  Future<AuthOutcome> signUp({
    required String email,
    required String password,
  }) async => const AuthSignedIn();

  @override
  Future<void> signOut() async {
    _status = AuthSessionStatus.signedOut;
    _controller.add(_status);
  }
}

class FakeOnboardingRepository implements OnboardingRepository {
  @override
  Future<OnboardingOutcome> createOrganization({
    required String restaurantName,
    String? branchName,
  }) async => const OnboardingSucceeded();
}

/// A spy selected-context store: records clears/writes and can be pre-seeded.
class SpySelectedContextStore implements SelectedContextStore {
  SpySelectedContextStore([this._id]);
  String? _id;
  int clearCount = 0;
  final List<String> writes = <String>[];

  @override
  Future<String?> readSelectedMembershipId() async => _id;

  @override
  Future<void> writeSelectedMembershipId(String membershipId) async {
    writes.add(membershipId);
    _id = membershipId;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    _id = null;
  }
}

class SpyDeviceContext extends DeviceContextController {
  int clearCount = 0;
  @override
  void clear() {
    clearCount++;
    super.clear();
  }
}

MembershipContext _mem(
  MembershipRole role, {
  String id = 'm',
  String orgName = 'Org A',
}) => MembershipContext(
  id: id,
  organizationId: 'org-$id',
  organizationName: orgName,
  restaurantId: null,
  restaurantName: null,
  branchId: null,
  branchName: null,
  role: role,
  status: 'active',
);

MyContext _ctx({List<MembershipContext> memberships = const []}) => MyContext(
  appUser: const AppUserContext(
    id: 'u',
    email: 'owner@x.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: false,
  memberships: memberships,
);

AuthContextFetcher _fetch(MyContext context) =>
    () async => Success<MyContext, AuthFailure>(context);

Future<void> _pump(
  WidgetTester tester,
  Widget app, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: app));
  await tester.pumpAndSettle();
}

void _useWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('real mode with NO session still shows login/sign-up', (
    tester,
  ) async {
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(),
        onboardingRepository: FakeOnboardingRepository(),
        fetchContext: _fetch(_ctx()),
      ),
    );
    expect(find.byType(LoginSignupScreen), findsOneWidget);
    expect(find.byType(DashboardHomeScreen), findsNothing);
  });

  testWidgets(
    'a RESTORED session loads the auth context and reaches the honest '
    'REAL dashboard (real-mode banner, not demo data)',
    (tester) async {
      _useWideSurface(tester);
      await _pump(
        tester,
        DashboardApp(
          demoMode: false,
          authRepository: FakeAuthRepository(
            initialStatus: AuthSessionStatus.signedIn,
          ),
          onboardingRepository: FakeOnboardingRepository(),
          fetchContext: _fetch(
            _ctx(memberships: [_mem(MembershipRole.orgOwner)]),
          ),
        ),
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          ownerReportsRepositoryProvider.overrideWithValue(
            const DemoOwnerReportsRepository(),
          ),
        ],
      );
      expect(find.byType(DashboardHomeScreen), findsOneWidget);
      expect(find.byType(LoginSignupScreen), findsNothing);
      // Honest real mode: the live-limited banner, never the demo banner.
      expect(find.byKey(const Key('reports-realmode-banner')), findsOneWidget);
      expect(find.byKey(const Key('reports-demo-banner')), findsNothing);
    },
  );

  testWidgets(
    'sign-out clears the selected-context store AND the device context',
    (tester) async {
      final store = SpySelectedContextStore();
      final device = SpyDeviceContext();
      await _pump(
        tester,
        DashboardApp(
          demoMode: false,
          authRepository: FakeAuthRepository(
            initialStatus: AuthSessionStatus.signedIn,
          ),
          onboardingRepository: FakeOnboardingRepository(),
          fetchContext: _fetch(
            _ctx(),
          ), // no org => onboarding (has a sign-out button)
          selectedContextStore: store,
          deviceContext: device,
        ),
      );
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding-signout')));
      await tester.pumpAndSettle();

      expect(store.clearCount, greaterThanOrEqualTo(1));
      expect(device.clearCount, greaterThanOrEqualTo(1));
      expect(find.byType(LoginSignupScreen), findsOneWidget);
    },
  );

  testWidgets('a SINGLE organization auto-selects (no picker)', (tester) async {
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(
          initialStatus: AuthSessionStatus.signedIn,
        ),
        onboardingRepository: FakeOnboardingRepository(),
        fetchContext: _fetch(_ctx(memberships: [_mem(MembershipRole.manager)])),
      ),
    );
    expect(find.byType(DashboardHomeScreen), findsOneWidget);
    expect(find.byType(MembershipPickerView), findsNothing);
  });

  testWidgets('MULTIPLE organizations show the selection picker', (
    tester,
  ) async {
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(
          initialStatus: AuthSessionStatus.signedIn,
        ),
        onboardingRepository: FakeOnboardingRepository(),
        fetchContext: _fetch(
          _ctx(
            memberships: [
              _mem(MembershipRole.orgOwner, id: 'a', orgName: 'Org A'),
              _mem(MembershipRole.orgOwner, id: 'b', orgName: 'Org B'),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(MembershipPickerView), findsOneWidget);
    expect(find.byType(DashboardHomeScreen), findsNothing);
  });

  testWidgets('picking an organization PERSISTS it and enters the dashboard', (
    tester,
  ) async {
    final store = SpySelectedContextStore();
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(
          initialStatus: AuthSessionStatus.signedIn,
        ),
        onboardingRepository: FakeOnboardingRepository(),
        selectedContextStore: store,
        fetchContext: _fetch(
          _ctx(
            memberships: [
              _mem(MembershipRole.orgOwner, id: 'a', orgName: 'Org A'),
              _mem(MembershipRole.orgOwner, id: 'b', orgName: 'Org B'),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(MembershipPickerView), findsOneWidget);

    await tester.tap(find.text('Org B'));
    await tester.pumpAndSettle();

    expect(store.writes, contains('b'));
    expect(find.byType(DashboardHomeScreen), findsOneWidget);
  });

  testWidgets('a VALID saved selection is restored (no re-pick)', (
    tester,
  ) async {
    final store = SpySelectedContextStore('b'); // previously selected Org B
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(
          initialStatus: AuthSessionStatus.signedIn,
        ),
        onboardingRepository: FakeOnboardingRepository(),
        selectedContextStore: store,
        fetchContext: _fetch(
          _ctx(
            memberships: [
              _mem(MembershipRole.orgOwner, id: 'a', orgName: 'Org A'),
              _mem(MembershipRole.orgOwner, id: 'b', orgName: 'Org B'),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(DashboardHomeScreen), findsOneWidget);
    expect(find.byType(MembershipPickerView), findsNothing);
    expect(store.clearCount, 0);
  });

  testWidgets(
    'an INVALID saved selection is rejected/cleared and falls back to '
    'the picker (fail-closed)',
    (tester) async {
      final store = SpySelectedContextStore('ghost'); // not in the memberships
      await _pump(
        tester,
        DashboardApp(
          demoMode: false,
          authRepository: FakeAuthRepository(
            initialStatus: AuthSessionStatus.signedIn,
          ),
          onboardingRepository: FakeOnboardingRepository(),
          selectedContextStore: store,
          fetchContext: _fetch(
            _ctx(
              memberships: [
                _mem(MembershipRole.orgOwner, id: 'a', orgName: 'Org A'),
                _mem(MembershipRole.orgOwner, id: 'b', orgName: 'Org B'),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(MembershipPickerView), findsOneWidget);
      expect(find.byType(DashboardHomeScreen), findsNothing);
      expect(store.clearCount, greaterThanOrEqualTo(1)); // stale id dropped
    },
  );

  testWidgets('a session with NO organization shows onboarding', (
    tester,
  ) async {
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(
          initialStatus: AuthSessionStatus.signedIn,
        ),
        onboardingRepository: FakeOnboardingRepository(),
        fetchContext: _fetch(_ctx()),
      ),
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(DashboardHomeScreen), findsNothing);
  });

  testWidgets('the device context is ABSENT by default and never paired', (
    tester,
  ) async {
    final device = SpyDeviceContext();
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(
          initialStatus: AuthSessionStatus.signedIn,
        ),
        onboardingRepository: FakeOnboardingRepository(),
        fetchContext: _fetch(
          _ctx(memberships: [_mem(MembershipRole.orgOwner)]),
        ),
        deviceContext: device,
      ),
    );
    // Reaching the dashboard never fabricates a paired device.
    expect(device.context, isNull);
    expect(device.hasPairedDevice, isFalse);
  });
}
