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
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show AuthContextFetcher;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A controllable fake real-auth seam (no Supabase, no network).
class FakeAuthRepository implements DashboardAuthRepository {
  FakeAuthRepository({
    AuthSessionStatus initialStatus = AuthSessionStatus.signedOut,
    this.signInOutcome = const AuthSignedIn(),
    this.signUpOutcome = const AuthSignedIn(),
  }) : _status = initialStatus;

  AuthSessionStatus _status;
  AuthOutcome signInOutcome;
  AuthOutcome signUpOutcome;
  final _controller = StreamController<AuthSessionStatus>.broadcast();
  int signOutCount = 0;
  String? lastSignInEmail;

  @override
  AuthSessionStatus get status => _status;

  @override
  Stream<AuthSessionStatus> get statusChanges => _controller.stream;

  @override
  Future<AuthOutcome> signIn({
    required String email,
    required String password,
  }) async {
    lastSignInEmail = email;
    if (signInOutcome is AuthSignedIn) _emit(AuthSessionStatus.signedIn);
    return signInOutcome;
  }

  @override
  Future<AuthOutcome> signUp({
    required String email,
    required String password,
  }) async {
    if (signUpOutcome is AuthSignedIn) _emit(AuthSessionStatus.signedIn);
    return signUpOutcome;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    _emit(AuthSessionStatus.signedOut);
  }

  void _emit(AuthSessionStatus status) {
    _status = status;
    _controller.add(status);
  }
}

/// A fake onboarding seam that records the call and returns [outcome].
class FakeOnboardingRepository implements OnboardingRepository {
  FakeOnboardingRepository([this.outcome = const OnboardingSucceeded()]);

  OnboardingOutcome outcome;
  int callCount = 0;
  String? lastRestaurantName;
  String? lastBranchName;

  @override
  Future<OnboardingOutcome> createOrganization({
    required String restaurantName,
    String? branchName,
  }) async {
    callCount++;
    lastRestaurantName = restaurantName;
    lastBranchName = branchName;
    return outcome;
  }
}

MembershipContext _mem(MembershipRole role) => MembershipContext(
  id: 'm',
  organizationId: 'org-a',
  organizationName: 'Org A',
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

Future<void> _pump(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(ProviderScope(child: app));
  await tester.pumpAndSettle();
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('real mode with NO session shows login/sign-up, not demo data', (
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
    expect(find.byKey(const Key('auth-submit')), findsOneWidget);
  });

  testWidgets('demo mode still renders the existing demo dashboard', (
    tester,
  ) async {
    await _pump(tester, const DashboardApp(demoMode: true));
    expect(find.byType(DashboardHomeScreen), findsOneWidget);
    expect(find.byType(LoginSignupScreen), findsNothing);
  });

  testWidgets('sign-up validates required fields (email/password/restaurant)', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(),
        onboardingRepository: FakeOnboardingRepository(),
        fetchContext: _fetch(_ctx()),
      ),
    );
    // Switch to the "Create account" tab (the segment is unique in sign-in mode).
    await tester.tap(find.text(l10n.authCreateAccountTab));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.authEmailRequired), findsOneWidget);
    expect(find.text(l10n.authPasswordRequired), findsOneWidget);
    expect(find.text(l10n.onboardingRestaurantNameRequired), findsOneWidget);
  });

  testWidgets('a login failure shows a SAFE error and no dashboard data', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(
          signInOutcome: const AuthError(AuthErrorKind.invalidCredentials),
        ),
        onboardingRepository: FakeOnboardingRepository(),
        fetchContext: _fetch(_ctx()),
      ),
    );
    await tester.enterText(find.byKey(const Key('auth-email')), 'owner@x.test');
    await tester.enterText(find.byKey(const Key('auth-password')), 'secret1');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.authInvalidCredentials), findsOneWidget);
    expect(find.byType(DashboardHomeScreen), findsNothing);
  });

  testWidgets(
    'onboarding submits the entered restaurant + branch to the repo',
    (tester) async {
      final onboarding = FakeOnboardingRepository();
      var calls = 0;
      // session but no org => onboarding; after create, the reload resolves a
      // membership so the flow settles on the dashboard.
      Future<Result<MyContext, AuthFailure>> fetch() async {
        calls++;
        return Success(
          calls == 1
              ? _ctx()
              : _ctx(memberships: [_mem(MembershipRole.orgOwner)]),
        );
      }

      await _pump(
        tester,
        DashboardApp(
          demoMode: false,
          authRepository: FakeAuthRepository(
            initialStatus: AuthSessionStatus.signedIn,
          ),
          onboardingRepository: onboarding,
          fetchContext: fetch,
        ),
      );
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('onboarding-restaurant')),
        'Bistro 21',
      );
      await tester.enterText(
        find.byKey(const Key('onboarding-branch')),
        'Downtown',
      );
      await tester.tap(find.byKey(const Key('onboarding-submit')));
      await tester.pumpAndSettle();

      expect(onboarding.callCount, 1);
      expect(onboarding.lastRestaurantName, 'Bistro 21');
      expect(onboarding.lastBranchName, 'Downtown');
    },
  );

  testWidgets('a successful onboarding transitions to the real dashboard', (
    tester,
  ) async {
    var calls = 0;
    Future<Result<MyContext, AuthFailure>> fetch() async {
      calls++;
      // First load: no org (onboarding). After create: an org_owner membership.
      return Success(
        calls == 1
            ? _ctx()
            : _ctx(memberships: [_mem(MembershipRole.orgOwner)]),
      );
    }

    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(
          initialStatus: AuthSessionStatus.signedIn,
        ),
        onboardingRepository: FakeOnboardingRepository(),
        fetchContext: fetch,
      ),
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('onboarding-restaurant')),
      'Bistro',
    );
    await tester.tap(find.byKey(const Key('onboarding-submit')));
    await tester.pumpAndSettle();

    // Honest real dashboard (not demo) after onboarding completes.
    expect(find.byType(DashboardHomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('session missing fails closed: a valid context is NOT shown '
      'without a session', (tester) async {
    await _pump(
      tester,
      DashboardApp(
        demoMode: false,
        authRepository: FakeAuthRepository(), // signed out
        onboardingRepository: FakeOnboardingRepository(),
        // A context that WOULD grant the dashboard — but there is no session.
        fetchContext: _fetch(
          _ctx(memberships: [_mem(MembershipRole.orgOwner)]),
        ),
      ),
    );
    expect(find.byType(LoginSignupScreen), findsOneWidget);
    expect(find.byType(DashboardHomeScreen), findsNothing);
  });

  testWidgets(
    'login + onboarding screens render in Arabic (RTL) without error',
    (tester) async {
      await tester.pumpWidget(
        // ProviderScope: the login app bar hosts the language selector (I).
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: LoginSignupScreen(
              authRepository: FakeAuthRepository(),
              onSignedUpWithSession: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(find.byType(LoginSignupScreen))),
        TextDirection.rtl,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: OnboardingScreen(
            onboardingRepository: FakeOnboardingRepository(),
            onCreated: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(find.byType(OnboardingScreen))),
        TextDirection.rtl,
      );
    },
  );

  test('new auth/onboarding l10n keys resolve for en/ar/he', () async {
    for (final code in ['en', 'ar', 'he']) {
      final l10n = await AppLocalizations.delegate.load(Locale(code));
      expect(l10n.authWelcomeTitle, isNotEmpty);
      expect(l10n.authSignInAction, isNotEmpty);
      expect(l10n.authInvalidCredentials, isNotEmpty);
      expect(l10n.authEmailConfirmationSent, isNotEmpty);
      expect(l10n.onboardingTitle, isNotEmpty);
      expect(l10n.onboardingCreateAction, isNotEmpty);
      expect(l10n.onboardingRestaurantNameRequired, isNotEmpty);
    }
  });
}
