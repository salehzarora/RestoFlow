import 'dart:async';

import 'package:restoflow_admin/src/auth/admin_auth.dart';

/// An in-memory [AdminAuthService] for widget/flow tests — never contacts a
/// backend. It models the real GoTrue behaviour closely enough for the flow:
///  * sign-in flips the session (and emits on [sessionChanges]);
///  * a successful TOTP verify upgrades the SERVER assurance ([serverAal2]),
///    which the test's `get_my_context` fetcher reads to return `is_mfa_aal2`;
///  * sign-out clears the session (and emits).
class FakeAdminAuthService implements AdminAuthService {
  FakeAdminAuthService({
    bool signedIn = false,
    AdminMfaAssurance assurance = const AdminMfaAssurance(
      isAal2: false,
      hasVerifiedFactor: false,
    ),
    this.enrollment = const AdminTotpEnrollment(
      factorId: 'factor-1',
      secret: 'JBSWY3DPEHPK3PXP',
      uri:
          'otpauth://totp/RestoFlow%20Admin:op@example.test?secret=JBSWY3DPEHPK3PXP',
    ),
    this.signInError,
    this.verifyError,
    this.enrollThrows = false,
    this.serverAal2AfterVerify = true,
  }) : _signedIn = signedIn,
       _assurance = assurance;

  /// Models whether the SERVER session actually becomes aal2 after a successful
  /// client verify. Default true (the happy path). Set false to prove that entry
  /// is gated on the SERVER-derived context, NOT this client's verify success —
  /// a client-trust bypass would then wrongly reach the overview.
  final bool serverAal2AfterVerify;

  bool _signedIn;
  AdminMfaAssurance _assurance;
  final _sessions = StreamController<bool>.broadcast();

  /// The one-time enrolment returned by [enrollTotp].
  final AdminTotpEnrollment enrollment;

  /// When set, [signInWithPassword] returns it (no session established).
  final AdminSignInError? signInError;

  /// When set, [verifyTotp] returns it (the code is rejected).
  final AdminMfaVerifyError? verifyError;

  /// When true, [enrollTotp] throws [AdminMfaException].
  final bool enrollThrows;

  /// Set true by a SUCCESSFUL verify — models the server session becoming aal2.
  /// The test's fetchContext reads this to return `is_mfa_aal2`.
  bool serverAal2 = false;

  int enrollCalls = 0;
  int verifyCalls = 0;
  int signOutCalls = 0;
  String? lastVerifiedCode;

  @override
  bool get hasSession => _signedIn;

  @override
  String? get currentEmail => _signedIn ? 'op@example.test' : null;

  @override
  Stream<bool> get sessionChanges => _sessions.stream;

  @override
  Future<AdminSignInError?> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (signInError != null) return signInError;
    _signedIn = true;
    _sessions.add(true);
    return null;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _signedIn = false;
    serverAal2 = false;
    _sessions.add(false);
  }

  @override
  Future<AdminMfaAssurance> assurance() async => _assurance;

  @override
  Future<AdminTotpEnrollment> enrollTotp() async {
    enrollCalls++;
    if (enrollThrows) throw const AdminMfaException();
    return enrollment;
  }

  @override
  Future<AdminMfaVerifyError?> verifyTotp({
    required String factorId,
    required String code,
  }) async {
    verifyCalls++;
    lastVerifiedCode = code;
    if (verifyError != null) return verifyError;
    // Client verify succeeded. Whether the SERVER session becomes aal2 (so the
    // next get_my_context returns is_mfa_aal2 = true) is controlled by
    // [serverAal2AfterVerify] — false models a server that does NOT trust the
    // client (the flow must NOT reach the overview then).
    serverAal2 = serverAal2AfterVerify;
    _assurance = AdminMfaAssurance(
      isAal2: serverAal2AfterVerify,
      hasVerifiedFactor: true,
      verifiedFactorId: factorId,
    );
    return null;
  }

  void dispose() => _sessions.close();
}
