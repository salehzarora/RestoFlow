import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'auth_failure.dart';
import 'membership_role.dart';
import 'my_context.dart';

/// Fetches the caller's own context from `public.get_my_context()` (RF-124) via
/// an injected [SyncRpcTransport] (the abstract RPC seam; the Supabase-backed
/// implementation is wired by the app from an authenticated, anon-key client).
///
/// SECURITY: NEVER accepts a user id (identity is server-derived from
/// `auth.uid()`); NEVER uses a service-role key (DECISION D-011); NEVER logs
/// memberships, email, or any raw response.
class AuthContextRepository {
  const AuthContextRepository(this._transport);

  final SyncRpcTransport _transport;

  /// Calls `get_my_context` (NO arguments) and parses the result.
  ///
  /// - 42501 -> [AuthDeniedFailure] (unauthenticated/unlinked/inactive).
  /// - transient transport error -> [AuthNetworkFailure].
  /// - other transport error -> [AuthUnknownFailure].
  /// - non-object / `ok != true` / malformed -> [AuthInvalidResponseFailure].
  /// - unknown membership role -> [AuthUnknownRoleFailure] (fail-closed).
  Future<Result<MyContext, AuthFailure>> fetchMyContext() async {
    final Object? raw;
    try {
      raw = await _transport.invoke(
        'get_my_context',
        const <String, dynamic>{}, // no args: identity is server-side only
      );
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      // Never echo the underlying error - it could carry sensitive detail.
      return const Failure(
        AuthNetworkFailure('get_my_context transport error'),
      );
    }
    try {
      return Success(MyContext.fromJson(raw));
    } on UnknownRoleException catch (e) {
      return Failure(AuthUnknownRoleFailure(e.role));
    } on FormatException catch (e) {
      // Our own FormatException messages are fixed strings (no PII/secrets).
      return Failure(
        AuthInvalidResponseFailure('invalid get_my_context: ${e.message}'),
      );
    }
  }

  static AuthFailure _mapTransport(SyncTransportException e) {
    // AUTH-257 — RESTORING THIS CLASS'S OWN DOCUMENTED CONTRACT (see above:
    // "42501 -> AuthDeniedFailure").
    //
    // The shared transport classifier deliberately narrowed 42501 -> `auth` to
    // an allowlist of PIN/device session messages (POS-OFFLINE-OPERATIONS-002),
    // so that a batch-validation or RLS 42501 could never strand the POS in a
    // re-auth hold. Correct for sync — but `get_my_context` is not sync. It
    // raises 42501 for exactly one reason, "no linked, authenticated
    // principal", and that message is not on a list written for PIN sessions.
    //
    // The consequence reached production: a freshly CONFIRMED owner with no
    // `app_users` row yet got `server` -> AuthUnknownFailure ->
    // AuthGateInvalidResponse -> the generic "Something went wrong" page,
    // instead of AuthGateAuthDenied -> ONBOARDING, which is the entire point of
    // that state. This RPC has one meaning for 42501, so it is classified here
    // rather than by widening the shared sync allowlist.
    if (e.code == '42501') return const AuthDeniedFailure();
    return switch (e.kind) {
      SyncTransportErrorKind.auth => const AuthDeniedFailure(),
      SyncTransportErrorKind.transient => const AuthNetworkFailure(),
      SyncTransportErrorKind.server => const AuthUnknownFailure('server error'),
      SyncTransportErrorKind.unknown => const AuthUnknownFailure(),
    };
  }
}
