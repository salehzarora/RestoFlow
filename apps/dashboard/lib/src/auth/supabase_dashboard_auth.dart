import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminRepository, AdminScope;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show AuthContextFetcher, authRedirectUrlFromEnvironment;
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show
        MenuImageStorage,
        MenuReadSource,
        MenuWriter,
        RpcMenuReadSource,
        RpcMenuWriter;
import 'package:supabase/supabase.dart';

import '../admin/supabase_admin_device_repository.dart';
import '../admin/supabase_users_repository.dart';
import '../menu/supabase_menu_image_storage.dart';
import '../printers/printers_repository.dart';
import '../staff/staff_repository.dart';
import '../tables/tables_repository.dart';
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

/// Default onboarding currency. The pilot is Israel-only, so every new
/// organization defaults to ILS (₪). The jurisdiction decision remains OPEN
/// QUESTION Q-007 — when multi-region lands this becomes an onboarding choice.
const String kDefaultOnboardingCurrency = 'ILS';

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
  AdminRepository Function(AdminScope scope) deviceRepositoryFor,
  AdminRepository Function(AdminScope scope) usersRepositoryFor,
  MenuReadSource menuReadSource,
  MenuWriter menuWriter,
  MenuImageStorage menuImageStorage,
  PrintersRepository Function(AdminScope scope) printersRepositoryFor,
  StaffRepository Function(AdminScope scope) staffRepositoryFor,
  TablesAdminRepository Function(AdminScope scope) tablesRepositoryFor,
  SyncRpcTransport transport,
})
buildDashboardRealAuth(SupabaseClient client) {
  final transport = SupabaseSyncRpcTransport(client);
  String? currentUserId() => client.auth.currentUser?.id;
  return (
    auth: SupabaseDashboardAuthRepository(client),
    onboarding: SupabaseOnboardingRepository(
      transport,
      currentUserId: currentUserId,
    ),
    fetchContext: AuthContextRepository(transport).fetchMyContext,
    // RF-160: the real device repository, built per active admin scope. Only the
    // dashboard Devices tab consumes it (management-driven device provisioning).
    deviceRepositoryFor: (scope) => SupabaseAdminDeviceRepository(
      transport: transport,
      scope: scope,
      currentUserId: currentUserId,
    ),
    // RF-116: the real users repository, built per active admin scope. Only the
    // dashboard Users tab consumes it (list_members + update_role + revoke).
    usersRepositoryFor: (scope) => SupabaseUsersRepository(
      transport: transport,
      scope: scope,
      currentUserId: currentUserId,
    ),
    // Sprint: the REAL menu seams (list_menu + menu_upsert_*) — the Menu tab
    // manages the backend menu the POS sells from.
    menuReadSource: RpcMenuReadSource(transport),
    menuWriter: RpcMenuWriter(transport),
    // Menu/media sprint: REAL item image storage over the same authenticated
    // client (RF-110 bucket + policies; signed URLs only — D-032).
    menuImageStorage: SupabaseMenuImageStorage(client),
    // Sprint: real printers (RF-150 backend) + staff/PIN provisioning surfaces.
    printersRepositoryFor: (scope) => SupabasePrintersRepository(
      transport: transport,
      scope: scope,
      currentUserId: currentUserId,
    ),
    staffRepositoryFor: (scope) => SupabaseStaffRepository(
      transport: transport,
      scope: scope,
      currentUserId: currentUserId,
    ),
    // Sprint: real dining tables (the POS table picker sells from this list).
    tablesRepositoryFor: (scope) => SupabaseTablesRepository(
      transport: transport,
      scope: scope,
      currentUserId: currentUserId,
    ),
    // The session-carrying transport itself (sprint): the Overview's real
    // sales-summary read rides the SAME authenticated client.
    transport: transport,
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
      // RF-LIVE-002: the email-confirmation link returns to the CURRENT web
      // origin (or an explicit RESTOFLOW_AUTH_REDIRECT_URL override) so a hosted
      // Dashboard confirms on the right host — never a stale localhost/dev value.
      // Null (non-web) uses the SDK/project default. Never a secret.
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: authRedirectUrlFromEnvironment(),
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
///
/// IDEMPOTENT RETRIES (RF-151 review fix): both the `p_client_request_id` and the
/// non-Latin fallback slug are DERIVED DETERMINISTICALLY from the current auth
/// user id + the normalized form values — never randomly. Retrying the SAME
/// onboarding input (e.g. after an ambiguous success where the response was lost)
/// reuses the SAME request id, so `public.create_organization` replays the
/// existing tenant instead of creating a duplicate. Meaningfully different form
/// values produce a different key/slug (a new attempt). The auth user id is a
/// non-secret identifier (never the raw email); no value is persisted.
class SupabaseOnboardingRepository implements OnboardingRepository {
  SupabaseOnboardingRepository(this._transport, {required this.currentUserId});

  final SyncRpcTransport _transport;

  /// The current authenticated user's id (e.g. `auth.uid()`), used only as a
  /// non-secret salt so keys/slugs are stable per user + input. Null when there
  /// is no session (onboarding is never reached without one).
  final String? Function() currentUserId;

  @override
  Future<OnboardingOutcome> createOrganization({
    required String restaurantName,
    String? branchName,
  }) async {
    final name = restaurantName.trim();
    final branch = (branchName?.trim().isNotEmpty ?? false)
        ? branchName!.trim()
        : name; // backend requires a non-empty branch; default to the restaurant.
    final userId = currentUserId() ?? '';

    // Stable per (user + restaurant + branch): a retry of the same attempt reuses
    // the same idempotency key. The slug is stable per (user + restaurant).
    final requestSeed = _seed([userId, name, branch]);
    final slugSeed = _seed([userId, name]);

    final Object? raw;
    try {
      raw = await _transport.invoke('create_organization', <String, dynamic>{
        'p_client_request_id': _deterministicRequestId(requestSeed),
        'p_organization_name': name,
        'p_organization_slug': _slug(name, slugSeed),
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

/// Builds a stable seed from normalized [parts]. Each part is LENGTH-PREFIXED
/// (`<len>:<value>;`) so parts can't run together — name "a b" + branch "c" must
/// NOT collide with name "a" + branch "b c". Normalization collapses trivial
/// edits (case/whitespace) so a retry of the "same" input maps to the same seed.
String _seed(List<String> parts) {
  final buffer = StringBuffer();
  for (final part in parts) {
    final value = _normalize(part);
    buffer
      ..write(value.length)
      ..write(':')
      ..write(value)
      ..write(';');
  }
  return buffer.toString();
}

String _normalize(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// A DETERMINISTIC RFC-4122-shaped UUID (name-based, v5-style) from [seed] via
/// SHA-256. Same seed => same UUID, so retries replay instead of duplicating.
String _deterministicRequestId(String seed) {
  final bytes = sha256
      .convert(utf8.encode('rf151:onboarding:request:$seed'))
      .bytes
      .sublist(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5 (name-based)
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC-4122 variant
  String hx(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
}

/// Slugifies [name] to the backend's `^[a-z0-9]+(-[a-z0-9]+)*$` shape. A
/// non-Latin name (e.g. Arabic/Hebrew) that slugifies to empty falls back to a
/// STABLE, deterministic slug derived from [seed] (user id + restaurant name) —
/// so a retry never generates a new random slug that would duplicate the org.
String _slug(String name, String seed) {
  final base = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'(^-+)|(-+$)'), '');
  if (RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(base)) return base;
  final suffix = sha256
      .convert(utf8.encode('rf151:onboarding:slug:$seed'))
      .bytes
      .sublist(0, 5)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'r-$suffix';
}
