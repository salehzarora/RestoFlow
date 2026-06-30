import 'dart:math';

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show AuthContextFetcher;
import 'package:supabase/supabase.dart';

import 'dashboard_auth_repository.dart';
import 'onboarding_repository.dart';

/// The real, Supabase-backed dashboard auth + onboarding implementations
/// (RF-151). This is the ONLY app file that imports the `supabase` SDK; the
/// rest of the dashboard auth flow depends on the pure-Dart
/// [DashboardAuthRepository] / [OnboardingRepository] seams, so it stays unit-
/// and widget-testable with fakes.
///
/// SECURITY: every call goes through a SINGLE anon-key [SupabaseClient] (DECISION
/// D-011 — no service-role key). The GoTrue session established by sign-in/up is
/// carried by that same client into the `public.*` RPC calls, so identity is
/// always server-derived from `auth.uid()`. No token, password, or raw provider
/// error is ever logged or surfaced.

/// Default onboarding currency. The jurisdiction / default-currency decision is
/// OPEN QUESTION Q-007; 'USD' is a safe ISO-4217 placeholder until it is frozen.
const String kDefaultOnboardingCurrency = 'USD';

/// Default onboarding timezone. A per-restaurant timezone picker is a follow-up
/// (RF-152/RF-153); 'UTC' is always a valid IANA zone, so onboarding never fails
/// the backend's timezone check.
const String kDefaultOnboardingTimezone = 'UTC';

/// Builds the three real seams from ONE anon-key [client] (RF-151). The SAME
/// client carries the GoTrue session established by sign-in/up into the
/// `public.*` RPC calls (`create_organization`, `get_my_context`), so identity is
/// always server-derived from `auth.uid()`. The `get_my_context` fetcher reuses
/// the shared [AuthContextRepository] error mapping.
({
  DashboardAuthRepository auth,
  OnboardingRepository onboarding,
  AuthContextFetcher fetchContext,
})
buildDashboardRealAuth(SupabaseClient client) {
  final transport = SupabaseSyncRpcTransport(client);
  return (
    auth: SupabaseDashboardAuthRepository(client),
    onboarding: SupabaseOnboardingRepository(transport),
    fetchContext: AuthContextRepository(transport).fetchMyContext,
  );
}

/// GoTrue-backed [DashboardAuthRepository].
class SupabaseDashboardAuthRepository implements DashboardAuthRepository {
  SupabaseDashboardAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  AuthSessionStatus get status => _client.auth.currentSession != null
      ? AuthSessionStatus.signedIn
      : AuthSessionStatus.signedOut;

  @override
  Stream<AuthSessionStatus> get statusChanges =>
      _client.auth.onAuthStateChange.map(
        (event) => event.session != null
            ? AuthSessionStatus.signedIn
            : AuthSessionStatus.signedOut,
      );

  @override
  Future<AuthOutcome> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      // Fail closed: a missing session is never treated as a successful sign-in.
      return response.session != null
          ? const AuthSignedIn()
          : const AuthError(AuthErrorKind.invalidCredentials);
    } on AuthException {
      // Never echo the provider message; sign-in failures are credential errors.
      return const AuthError(AuthErrorKind.invalidCredentials);
    } catch (_) {
      return const AuthError(AuthErrorKind.network);
    }
  }

  @override
  Future<AuthOutcome> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );
      // A session means auto-confirm is on; no session means the project requires
      // an email confirmation before a session is issued (honest pending state).
      return response.session != null
          ? const AuthSignedIn()
          : const AuthConfirmationRequired();
    } on AuthException {
      return const AuthError(AuthErrorKind.unknown);
    } catch (_) {
      return const AuthError(AuthErrorKind.network);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

/// `public.create_organization`-backed [OnboardingRepository].
class SupabaseOnboardingRepository implements OnboardingRepository {
  SupabaseOnboardingRepository(this._transport);

  final SyncRpcTransport _transport;

  @override
  Future<OnboardingOutcome> createOrganization({
    required String restaurantName,
    String? branchName,
  }) async {
    final name = restaurantName.trim();
    final branch = (branchName?.trim().isNotEmpty ?? false)
        ? branchName!.trim()
        : name; // backend requires a non-empty branch; default to the restaurant.

    final Object? raw;
    try {
      raw = await _transport.invoke('create_organization', <String, dynamic>{
        'p_client_request_id': _uuidV4(),
        'p_organization_name': name,
        'p_organization_slug': _slug(name),
        'p_restaurant_name': name,
        'p_branch_name': branch,
        'p_currency_code': kDefaultOnboardingCurrency,
        'p_timezone': kDefaultOnboardingTimezone,
        'p_default_station_name': null,
      });
    } on SyncTransportException catch (e) {
      return OnboardingFailed(_mapTransport(e));
    } catch (_) {
      return const OnboardingFailed(OnboardingErrorKind.network);
    }

    if (raw is Map && raw['ok'] == true) {
      return OnboardingSucceeded(
        idempotentReplay: raw['idempotent_replay'] == true,
      );
    }
    return const OnboardingFailed(OnboardingErrorKind.invalid);
  }

  static OnboardingErrorKind _mapTransport(SyncTransportException e) =>
      switch (e.kind) {
        SyncTransportErrorKind.auth => OnboardingErrorKind.denied,
        SyncTransportErrorKind.transient => OnboardingErrorKind.network,
        SyncTransportErrorKind.server => OnboardingErrorKind.unknown,
        SyncTransportErrorKind.unknown => OnboardingErrorKind.unknown,
      };
}

/// A random RFC-4122 v4 UUID for the create_organization idempotency key.
String _uuidV4() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Slugifies [name] to the backend's `^[a-z0-9]+(-[a-z0-9]+)*$` shape. A
/// non-Latin name (e.g. Arabic/Hebrew) that slugifies to empty falls back to a
/// generated, always-valid slug so onboarding never fails the slug check.
String _slug(String name) {
  final base = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'(^-+)|(-+$)'), '');
  if (RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(base)) return base;
  return 'r-${_uuidV4().substring(0, 8)}';
}
