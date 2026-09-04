/// AUTH-FLOW-256 — turning a provider failure into something we can honestly
/// say out loud.
///
/// Before this existed, `supabase_dashboard_auth.dart` mapped EVERY
/// `AuthException` from sign-in to [AuthErrorKind.invalidCredentials]. That is a
/// lie in the cases that matter most: a rate-limited project, a suspended
/// project (402), a 5xx, or an unconfirmed email all told the owner "Incorrect
/// email or password" — sending them off to re-type a password that was never
/// wrong. This function is the single place that decision is made, and it takes
/// primitives rather than an `AuthException` so it can be tested without the SDK.
///
/// It classifies on the STATUS CODE and the provider's stable machine-readable
/// `error_code`. It deliberately does not parse human-readable message text for
/// meaning beyond a last-resort hint, and the message NEVER reaches the user —
/// the UI renders a localized string chosen from [AuthErrorKind] alone.
library;

import 'dashboard_auth_repository.dart';

/// Classifies a provider auth failure into a user-safe [AuthErrorKind].
///
/// [statusCode] is the HTTP status GoTrue returned (null when the failure never
/// reached the server). [errorCode] is GoTrue's stable machine code
/// (e.g. `invalid_credentials`, `email_not_confirmed`, `over_request_rate_limit`).
/// [message] is used only as a weak fallback hint for older server builds that
/// send no `error_code`; it is never shown to anyone.
AuthErrorKind classifyAuthFailure({
  int? statusCode,
  String? errorCode,
  String? message,
}) {
  final code = errorCode?.trim().toLowerCase() ?? '';

  // 1. The stable machine code wins whenever the provider sends one.
  switch (code) {
    case 'invalid_credentials':
    case 'invalid_grant':
      return AuthErrorKind.invalidCredentials;
    case 'email_not_confirmed':
    case 'email_address_not_authorized':
      return AuthErrorKind.emailNotConfirmed;
    case 'user_banned':
      return AuthErrorKind.accountUnavailable;
    case 'weak_password':
      return AuthErrorKind.weakPassword;
    case 'same_password':
      return AuthErrorKind.samePassword;
    case 'otp_expired':
    case 'flow_state_expired':
    case 'flow_state_not_found':
      return AuthErrorKind.linkExpired;
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
    case 'over_sms_send_rate_limit':
      return AuthErrorKind.rateLimited;
  }

  // 2. Then the status code. 402/429/5xx must NEVER read as a wrong password:
  //    they are the project's condition, not the operator's typing.
  if (statusCode != null) {
    if (statusCode == 429) return AuthErrorKind.rateLimited;
    if (statusCode == 402 || statusCode >= 500) {
      return AuthErrorKind.serviceUnavailable;
    }
    if (statusCode == 422) {
      // 422 is GoTrue's validation status; without a code the only safe reading
      // for a password-bearing call is that the password was rejected.
      return AuthErrorKind.weakPassword;
    }
    if (statusCode == 400 || statusCode == 401) {
      // The classic credential rejection — but only once the codes above have
      // had their say, so `email_not_confirmed` (also a 400) never lands here.
      return _hintFromMessage(message) ?? AuthErrorKind.invalidCredentials;
    }
  }

  return _hintFromMessage(message) ?? AuthErrorKind.unknown;
}

/// A last-resort hint for server builds that send no `error_code`. Kept narrow
/// and phrase-based on purpose: a broad match here would silently reintroduce
/// exactly the over-classification this file exists to remove.
AuthErrorKind? _hintFromMessage(String? message) {
  final m = message?.toLowerCase() ?? '';
  if (m.isEmpty) return null;
  if (m.contains('email not confirmed')) return AuthErrorKind.emailNotConfirmed;
  if (m.contains('rate limit')) return AuthErrorKind.rateLimited;
  if (m.contains('password should be') || m.contains('password is too weak')) {
    return AuthErrorKind.weakPassword;
  }
  if (m.contains('code verifier') || m.contains('code challenge')) {
    // PKCE: the link was opened somewhere without the verifier that started the
    // flow. Nothing is wrong with the account — see [AuthErrorKind.linkExpired].
    return AuthErrorKind.linkExpired;
  }
  return null;
}
