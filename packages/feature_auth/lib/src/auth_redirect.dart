import 'package:flutter/foundation.dart' show kIsWeb;

/// RF-LIVE-002 — resolves the URL Supabase auth should redirect back to after an
/// email confirmation (`emailRedirectTo`), so a hosted Dashboard on Vercel gets a
/// correct redirect automatically instead of relying on the Supabase project's
/// Site URL being kept in sync.
///
/// Precedence (safe on localhost dev, Vercel preview/production, and custom
/// domains later, WITHOUT hardcoding any single production URL):
///   1. an explicit build-time override ([configuredOverride], the optional
///      `RESTOFLOW_AUTH_REDIRECT_URL` dart-define) — for a custom domain or when
///      origin-derivation is not wanted;
///   2. the CURRENT web origin ([currentUri].origin) — the natural default for a
///      web SPA: the confirmation link returns to whatever host is serving the
///      app (localhost:57026 in dev, the Vercel domain in prod);
///   3. `null` on a non-web build — the SDK/project default is used.
///
/// SECURITY: this only ever returns a public origin/URL — never a secret, token,
/// or key. It reads no credential. A `null` result means "use the SDK default".
String? resolveAuthRedirectUrl({
  required bool isWeb,
  Uri? currentUri,
  String configuredOverride = '',
}) {
  final override = configuredOverride.trim();
  if (override.isNotEmpty) return override;
  if (isWeb && currentUri != null) {
    final origin = _originOf(currentUri);
    if (origin != null) return origin;
  }
  return null;
}

/// The compile-time override name (optional). Absent by default so the origin is
/// used; set it only for a custom domain or to force a specific redirect host.
const String kAuthRedirectUrlEnvName = 'RESTOFLOW_AUTH_REDIRECT_URL';

/// Production wiring: reads the current web origin ([Uri.base]) and the optional
/// `RESTOFLOW_AUTH_REDIRECT_URL` override. On a non-web build it returns the
/// override or null — it NEVER falls back to a localhost/dev value. Safe to call
/// from the one SDK-facing auth file; the decision itself is
/// [resolveAuthRedirectUrl] (unit-tested).
String? authRedirectUrlFromEnvironment() => resolveAuthRedirectUrl(
  isWeb: kIsWeb,
  currentUri: kIsWeb ? Uri.base : null,
  configuredOverride: const String.fromEnvironment(kAuthRedirectUrlEnvName),
);

/// Returns `scheme://host[:port]` for an http(s) [uri], or null if it is not a
/// usable web origin (so we fall through to the SDK default rather than emit a
/// `file://`/opaque origin).
String? _originOf(Uri uri) {
  if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    return null;
  }
  return uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
}
