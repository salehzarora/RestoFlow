/// Resolves the `emailRedirectTo` URL used for GoTrue sign-up confirmation
/// emails (production email-confirmation redirect fix).
///
/// ROOT CAUSE this addresses: calling `SupabaseClient.auth.signUp` WITHOUT
/// `emailRedirectTo` makes GoTrue fall back to the project's Site URL, which
/// defaults to `http://localhost:3000`. In production that mails a confirmation
/// link pointing at localhost. We instead pass an explicit, production-safe URL.
///
/// Resolution order (it never invents a hardcoded localhost for production):
///   1. The `RESTOFLOW_APP_URL` compile-time define, when non-empty — set in the
///      Vercel production build (e.g. `https://resto-flow-phi.vercel.app`).
///   2. The current origin (`Uri.base.origin`) when it is an http(s) URL. In a
///      real web build this is exactly the serving domain, so it is correct for
///      BOTH production (the Vercel domain) and local dev (`localhost:<port>`)
///      with no configuration at all.
///   3. `null` — let GoTrue use its own configured Site URL (we never guess a
///      value; e.g. under `flutter test`, where `Uri.base` is a `file:` URI).
///
/// A localhost result therefore only ever occurs when the app is ACTUALLY served
/// from localhost (local dev), which is the desired behavior there.
library;

/// The compile-time production app URL (`--dart-define=RESTOFLOW_APP_URL=...`).
/// Empty when unset (local/dev builds), in which case the live web origin is
/// used instead. Never a secret — it is a public site URL.
const String kAppUrlFromEnvironment = String.fromEnvironment(
  'RESTOFLOW_APP_URL',
);

/// Pure resolver for the sign-up email redirect. [configuredAppUrl] and [base]
/// are injectable so the resolution rules are unit-testable without a real web
/// environment or compile-time defines; production calls it with no arguments.
String? resolveEmailRedirectUrl({
  String configuredAppUrl = kAppUrlFromEnvironment,
  Uri? base,
}) {
  final configured = configuredAppUrl.trim();
  if (configured.isNotEmpty) return configured;

  // Only an http(s) origin is a valid redirect target. On the web this is the
  // serving domain; off the web (tests/VM) `Uri.base` is a `file:` URI, so we
  // return null and let GoTrue use its configured Site URL.
  final origin = base ?? Uri.base;
  if (origin.scheme == 'http' || origin.scheme == 'https') {
    return origin.origin;
  }
  return null;
}
