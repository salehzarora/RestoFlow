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
        RpcMenuWriter,
        signedUrlCacheFor;
import 'package:supabase/supabase.dart';

import '../admin/supabase_admin_device_repository.dart';
import '../branding/restaurant_logo_storage.dart';
import '../admin/supabase_users_repository.dart';
import '../menu/supabase_menu_image_storage.dart';
import '../printers/printers_repository.dart';
import '../staff/staff_repository.dart';
import '../tables/tables_repository.dart';
import 'auth_callback.dart';
import 'auth_failure_classifier.dart';
import 'dashboard_auth_repository.dart';
import 'onboarding_repository.dart';
import 'web_session_isolation.dart';

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

/// Default onboarding timezone. The pilot is Israel-only (ILS / ₪), so new
/// organizations default to Asia/Jerusalem — NOT 'UTC'. This matters for
/// reporting: sales-by-hour and the branch-local business day bucket by the
/// branch's timezone, so a 'UTC' default shifted every hour bucket by the Israel
/// offset (the RF-REPORT-004 fix). Owners can change it later in Settings; a
/// per-restaurant onboarding picker remains a follow-up (RF-152/RF-153).
/// 'Asia/Jerusalem' is a valid IANA zone, so onboarding still passes the
/// backend's timezone check.
const String kDefaultOnboardingTimezone = 'Asia/Jerusalem';

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
  RestaurantLogoStorage brandingLogoStorage,
  PrintersRepository Function(AdminScope scope) printersRepositoryFor,
  StaffRepository Function(AdminScope scope) staffRepositoryFor,
  TablesAdminRepository Function(AdminScope scope) tablesRepositoryFor,
  SyncRpcTransport transport,
})
buildDashboardRealAuth(SupabaseClient client) {
  final transport = SupabaseSyncRpcTransport(client);
  String? currentUserId() => client.auth.currentUser?.id;
  // EGRESS-REMEDIATION-001.1: the two media storages are built HERE so the
  // sign-out boundary below can wipe their signed-URL caches — the ONE true
  // authorization boundary. Ordinary navigation, tab switches and media
  // refreshes never touch this path, so normal dashboard usage keeps its
  // cached URLs for the whole validity window.
  final menuImageStorage = SupabaseMenuImageStorage(client);
  final brandingLogoStorage = SupabaseRestaurantLogoStorage(client);
  return (
    auth: SupabaseDashboardAuthRepository(
      client,
      onSignedOut: () {
        signedUrlCacheFor(menuImageStorage).clear();
        signedUrlCacheFor(brandingLogoStorage).clear();
      },
    ),
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
    menuImageStorage: menuImageStorage,
    // PRINT-BRANDING-LOGO-001: the restaurant-logo blob store over the same
    // authenticated anon-key client (D-011).
    brandingLogoStorage: brandingLogoStorage,
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

/// AUTH-256 — completes an auth callback the SDK cannot finish on its own, and
/// then scrubs the URL.
///
/// Two shapes need help:
///
///   * `?token_hash=…&type=…` — the CROSS-BROWSER shape. `verifyOtp` accepts it
///     anywhere, unlike PKCE's `?code=`, which can only be exchanged in the
///     browser that started the flow. This is the shape a project gets by
///     pointing its email templates at `{{ .TokenHash }}`, and handling it here
///     means that change becomes a config edit rather than a code change.
///
///   * `?error=…` — the link was expired or already used. The SDK has nothing
///     to exchange, so without this the app would simply look broken.
///
/// The plain PKCE `?code=` case is left to the SDK, which already exchanges it
/// and clears the URL. When the verifier is missing (a different browser) it
/// raises, and [SupabaseDashboardAuthRepository] classifies that as
/// [AuthErrorKind.linkExpired] rather than pretending the account is at fault.
///
/// Returns the callback that was seen, so the caller can render an honest state.
/// SECURITY: the token is passed straight to the SDK and never logged; the URL
/// is rewritten immediately so a recovery link cannot be replayed from history.
Future<AuthCallback> completeAuthCallback({
  required SupabaseClient client,
  required Uri uri,
  required void Function(Uri cleaned) replaceUrl,
}) async {
  final callback = parseAuthCallback(uri);
  if (!callback.isAuthCallback) return callback;

  final tokenHash = callback.tokenHash;
  if (tokenHash != null) {
    final kind = resolveCallbackKind(uri);
    try {
      await client.auth.verifyOTP(
        tokenHash: tokenHash,
        type: kind == AuthCallbackKind.recovery
            ? OtpType.recovery
            : OtpType.email,
      );
    } on AuthException {
      // Swallowed on purpose: the app decides what to SAY about a failed link
      // (see AuthErrorKind.linkExpired). Rethrowing here would crash the very
      // first frame instead.
    } catch (_) {
      // Same reasoning for transport failures.
    }
  }

  // Always scrub, success or failure. A `token_hash` or `code` sitting in the
  // address bar survives into history, screenshots and shared links.
  replaceUrl(scrubbedUrl(uri));
  return callback;
}

/// GoTrue-backed [DashboardAuthRepository].
class SupabaseDashboardAuthRepository implements DashboardAuthRepository {
  SupabaseDashboardAuthRepository(this._client, {void Function()? onSignedOut})
    : _onSignedOut = onSignedOut;

  final SupabaseClient _client;

  /// EGRESS-REMEDIATION-001.1: auth-boundary cleanup (drops cached signed
  /// media URLs). Runs on EVERY sign-out attempt — even one whose network
  /// call failed, because the local session is being torn down either way.
  final void Function()? _onSignedOut;

  // WEB-AUTH-SESSION-ISOLATION-001: "there is a session" is NOT the same as
  // "this dashboard is signed in". On one origin, GoTrue's cross-tab broadcast
  // could hand this client the ANONYMOUS session a POS/KDS tab just created, and
  // treating that as signed-in produced a shell whose every tenant RPC returned
  // 403 — the permanent generic error the operator could only escape by clearing
  // site data. A device principal can never be a staff identity, so it reads as
  // signed OUT and the operator gets an honest sign-in screen instead.
  @override
  AuthSessionStatus get status =>
      isUsableDashboardSession(_client.auth.currentSession)
      ? AuthSessionStatus.signedIn
      : AuthSessionStatus.signedOut;

  @override
  Stream<AuthSessionStatus> get statusChanges => _client.auth.onAuthStateChange
      // Another tab's device sign-in is not a Dashboard event. Its own events,
      // and genuine staff events broadcast by another DASHBOARD tab, still pass.
      .where(isOwnDashboardAuthEvent)
      .map(
        (event) => isUsableDashboardSession(event.session)
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
    } on AuthException catch (e) {
      // AUTH-FLOW-256: classify instead of assuming. A 402/429/5xx or an
      // unconfirmed email is NOT a wrong password, and saying so sent owners
      // to re-type a credential that was never the problem. The raw provider
      // message is still never surfaced — only the safe kind.
      return AuthError(_kindOf(e));
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
        emailRedirectTo:
            confirmationRedirectUrl(authRedirectUrlFromEnvironment()) ??
            authRedirectUrlFromEnvironment(),
      );
      // A session means auto-confirm is on; no session means the project requires
      // an email confirmation before a session is issued (honest pending state).
      return response.session != null
          ? const AuthSignedIn()
          : const AuthConfirmationRequired();
    } on AuthException catch (e) {
      return AuthError(_kindOf(e));
    } catch (_) {
      return const AuthError(AuthErrorKind.network);
    }
  }

  // -- AUTH-FLOW-256: password recovery ------------------------------------

  /// True once GoTrue reports a `passwordRecovery` event and until the password
  /// is replaced (or recovery is abandoned).
  bool _recovering = false;

  @override
  bool get isPasswordRecovery => _recovering;

  @override
  Stream<bool> get passwordRecoveryChanges => _client.auth.onAuthStateChange
      .where(
        (event) =>
            event.event == AuthChangeEvent.passwordRecovery ||
            event.event == AuthChangeEvent.signedOut ||
            event.event == AuthChangeEvent.userUpdated,
      )
      .map((event) {
        // The provider's own event is the authoritative signal — far more
        // reliable than the callback URL, which the project's redirect
        // allowlist and email templates can reshape without warning.
        _recovering = event.event == AuthChangeEvent.passwordRecovery;
        return _recovering;
      });

  @override
  Future<AuthOutcome> requestPasswordReset({required String email}) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo:
            recoveryRedirectUrl(authRedirectUrlFromEnvironment()) ??
            authRedirectUrlFromEnvironment(),
      );
      return const AuthPasswordResetRequested();
    } on AuthException catch (e) {
      final kind = _kindOf(e);
      // NON-ENUMERATION: an unknown address must be indistinguishable from a
      // known one, so only failures that are genuinely about US (rate limiting,
      // the service being down) are reported. Anything the provider says about
      // the ADDRESS is answered with the same success the caller would have
      // seen for a real account.
      if (kind == AuthErrorKind.rateLimited ||
          kind == AuthErrorKind.serviceUnavailable) {
        return AuthError(kind);
      }
      return const AuthPasswordResetRequested();
    } catch (_) {
      return const AuthError(AuthErrorKind.network);
    }
  }

  @override
  Future<AuthOutcome> completePasswordRecovery({
    required String newPassword,
  }) async {
    // Fail closed: without a session there is nothing to update, and calling
    // the SDK anyway would surface a confusing provider error.
    if (_client.auth.currentSession == null) {
      return const AuthError(AuthErrorKind.linkExpired);
    }
    try {
      final response = await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      if (response.user == null) {
        return const AuthError(AuthErrorKind.unknown);
      }
      // Recovery is over: this is an ordinary authenticated session now, and the
      // normal context gate takes it from here.
      _recovering = false;
      return const AuthPasswordUpdated();
    } on AuthException catch (e) {
      return AuthError(_kindOf(e));
    } catch (_) {
      return const AuthError(AuthErrorKind.network);
    }
  }

  @override
  Future<void> cancelPasswordRecovery() async {
    _recovering = false;
    // The recovery session is signed out rather than kept: an abandoned
    // recovery must not leave behind a session that could be used as an
    // ordinary one without the password ever being replaced.
    await signOut();
  }

  /// Maps a provider exception to a safe kind. The message is passed only as a
  /// classification hint for older servers that send no `code`; it is never
  /// stored, logged or displayed.
  static AuthErrorKind _kindOf(AuthException e) => classifyAuthFailure(
    statusCode: int.tryParse(e.statusCode ?? ''),
    errorCode: e.code,
    message: e.message,
  );

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } finally {
      // Best-effort, never throwing: a cache-cleanup failure must not turn a
      // completed sign-out into an error.
      try {
        _onSignedOut?.call();
      } catch (_) {
        // Swallowed by design.
      }
    }
  }
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
