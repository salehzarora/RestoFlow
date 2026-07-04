import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_auth.dart';

/// The real, GoTrue-backed [AdminAuthService] (RF-119-b). This is the ONLY admin
/// file that imports Supabase; the sign-in / MFA UI depends on the pure-Dart
/// [AdminAuthService] seam, so it stays fully widget-testable with a fake.
///
/// SECURITY: every call rides ONE PUBLIC anon-key [SupabaseClient] (DECISION
/// D-011 — no service-role key); the GoTrue session it establishes carries
/// `auth.uid()` + the assurance claim into `public.get_my_context` / the
/// platform RPCs. It NEVER grants platform-admin, NEVER fakes aal2, and NEVER
/// stores the TOTP secret/URI or any token (they live only in memory during
/// enrolment). Platform data reads stay gated by `app.platform_admin_guard`.
class SupabaseAdminAuthService implements AdminAuthService {
  SupabaseAdminAuthService(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  String? get currentEmail => _auth.currentUser?.email;

  @override
  Stream<bool> get sessionChanges =>
      _auth.onAuthStateChange.map((event) => event.session != null);

  @override
  Future<AdminSignInError?> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      // Fail closed: a missing session is never a successful sign-in.
      return response.session != null
          ? null
          : AdminSignInError.invalidCredentials;
    } on AuthException {
      // Never echo the provider message; a sign-in failure is a credential error.
      return AdminSignInError.invalidCredentials;
    } catch (_) {
      return AdminSignInError.network;
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<AdminMfaAssurance> assurance() async {
    final aal = _auth.mfa.getAuthenticatorAssuranceLevel();
    final isAal2 = aal.currentLevel == AuthenticatorAssuranceLevels.aal2;

    // A challenge needs an ENROLLED + VERIFIED TOTP factor. Prefer the explicit
    // factor list (gives the factor id); fall back to the AAL step-up signal
    // (nextLevel aal2 while at aal1 means a verified factor exists) if listing
    // fails, in which case no factor id is available (the UI re-enrols).
    var hasVerifiedFactor = false;
    String? verifiedFactorId;
    try {
      final factors = await _auth.mfa.listFactors();
      final verified = factors.totp
          .where((f) => f.status == FactorStatus.verified)
          .toList();
      hasVerifiedFactor = verified.isNotEmpty;
      verifiedFactorId = verified.isEmpty ? null : verified.first.id;
    } catch (_) {
      hasVerifiedFactor =
          aal.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
          aal.nextLevel == AuthenticatorAssuranceLevels.aal2;
    }
    return AdminMfaAssurance(
      isAal2: isAal2,
      hasVerifiedFactor: hasVerifiedFactor,
      verifiedFactorId: verifiedFactorId,
    );
  }

  @override
  Future<AdminTotpEnrollment> enrollTotp() async {
    try {
      final response = await _auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'RestoFlow Admin',
      );
      final totp = response.totp;
      if (totp == null) {
        throw const AdminMfaException('no totp payload in enrol response');
      }
      // secret/uri are held only for the enrolment screen; never persisted.
      return AdminTotpEnrollment(
        factorId: response.id,
        secret: totp.secret,
        uri: totp.uri,
      );
    } on AdminMfaException {
      rethrow;
    } on AuthException {
      throw const AdminMfaException('enrolment was denied by the server');
    } catch (_) {
      throw const AdminMfaException();
    }
  }

  @override
  Future<AdminMfaVerifyError?> verifyTotp({
    required String factorId,
    required String code,
  }) async {
    try {
      // Creates a challenge and verifies the code in one step; on success the
      // client saves the UPGRADED (aal2) session. Entry is still gated on the
      // server-derived assurance (the caller re-fetches get_my_context).
      await _auth.mfa.challengeAndVerify(factorId: factorId, code: code.trim());
      return null;
    } on AuthException {
      return AdminMfaVerifyError.invalidCode;
    } catch (_) {
      return AdminMfaVerifyError.network;
    }
  }
}
