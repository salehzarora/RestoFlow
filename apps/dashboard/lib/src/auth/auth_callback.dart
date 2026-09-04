/// AUTH-FLOW-256 — reading what a Supabase auth link actually asked for.
///
/// A confirmation or recovery email can come back in three different shapes,
/// and the Dashboard has to answer all of them because which one arrives is a
/// property of the PROJECT'S email templates and flow type, not of our code:
///
///   * `?code=…`                        — PKCE. The SDK exchanges it, but only
///                                        in the browser that started the flow.
///   * `?token_hash=…&type=recovery`    — the cross-browser shape, produced when
///                                        the email template uses `{{ .TokenHash }}`.
///                                        Verified with `verifyOtp`.
///   * `#access_token=…&type=recovery`  — the implicit shape.
///   * `?error=…&error_description=…`   — the link failed server-side.
///
/// Parsing lives here, as pure functions over a [Uri], so every shape is
/// unit-tested without a browser, an SDK or a network. Nothing here performs
/// authentication — it only says what the URL is claiming to be.
///
/// SECURITY: a token/code is carried in [AuthCallback.tokenHash] only long
/// enough to hand to the SDK. It is never logged, never rendered, and
/// [scrubbedUrl] is what the address bar must be rewritten to immediately after
/// — a recovery link left in history is a replayable credential.
library;

/// What a callback URL is asking the app to do.
enum AuthCallbackKind {
  /// Not an auth callback at all — an ordinary app load.
  none,

  /// A sign-up / email-change confirmation.
  confirmation,

  /// A password-recovery link: the operator must be offered a new password.
  recovery,

  /// The provider reported a failure in the URL itself (expired, already used).
  failure,
}

/// A parsed auth callback.
class AuthCallback {
  const AuthCallback({
    required this.kind,
    this.tokenHash,
    this.code,
    this.hasImplicitToken = false,
    this.errorCode,
  });

  static const AuthCallback none = AuthCallback(kind: AuthCallbackKind.none);

  final AuthCallbackKind kind;

  /// Present for the `token_hash` shape — the value to pass to `verifyOtp`.
  /// Never logged or displayed.
  final String? tokenHash;

  /// Present for the PKCE shape. The SDK handles the exchange; we only need to
  /// know it is there so a failure can be explained honestly.
  final String? code;

  /// True for the implicit shape (`#access_token=…`), which the SDK consumes.
  final bool hasImplicitToken;

  /// The provider's machine-readable failure code, when the URL carried one.
  final String? errorCode;

  bool get isAuthCallback => kind != AuthCallbackKind.none;
}

/// Parses [uri] into an [AuthCallback].
///
/// Both the query string and the fragment are inspected: Supabase puts the
/// implicit-flow token in the fragment, and some providers echo errors there
/// too, so looking at only one of them misses half the cases.
AuthCallback parseAuthCallback(Uri uri) {
  final query = uri.queryParameters;
  final fragment = _fragmentParameters(uri.fragment);
  String? pick(String key) => _firstNonEmpty(query[key], fragment[key]);

  // A failure in the URL wins: there is nothing to exchange, and pretending
  // otherwise would send the operator into a flow that cannot complete.
  final error = pick('error');
  final errorCode = pick('error_code');
  if (error != null || errorCode != null) {
    return AuthCallback(
      kind: AuthCallbackKind.failure,
      // `error_code` is the stable one; `error` ("access_denied") is the family.
      errorCode: errorCode ?? error,
    );
  }

  final type = pick('type')?.toLowerCase();
  final tokenHash = pick('token_hash') ?? pick('token');
  final code = pick('code');
  final hasImplicitToken = fragment.containsKey('access_token');

  if (tokenHash == null && code == null && !hasImplicitToken) {
    return AuthCallback.none;
  }

  // `type` is what distinguishes recovery from confirmation. Only the implicit
  // and token_hash shapes carry it; a bare `?code=` does not, so PKCE recovery
  // is recognised by the callback PATH instead (see [isRecoveryPath]).
  final kind = type == 'recovery'
      ? AuthCallbackKind.recovery
      : AuthCallbackKind.confirmation;

  return AuthCallback(
    kind: kind,
    tokenHash: tokenHash,
    code: code,
    hasImplicitToken: hasImplicitToken,
  );
}

/// The path segment a recovery link is sent to, so a bare PKCE `?code=` can
/// still be told apart from a sign-up confirmation.
const String kRecoveryPath = '/auth/recovery';

/// The path a confirmation link is sent to.
const String kConfirmationPath = '/auth/confirmed';

/// Builds the URL a recovery email should return to, from the resolved origin.
///
/// Returns null when there is no origin (a non-web build), so the SDK/project
/// default is used rather than a fabricated link.
///
/// The path matters only for the bare-PKCE shape, which carries no `type`. Every
/// other shape is recognised by the provider's own `passwordRecovery` event, so
/// a project whose redirect allowlist lacks this exact URL still completes
/// recovery — it just arrives at the root instead.
String? recoveryRedirectUrl(String? origin) => _withPath(origin, kRecoveryPath);

/// Builds the URL a sign-up confirmation should return to.
String? confirmationRedirectUrl(String? origin) =>
    _withPath(origin, kConfirmationPath);

String? _withPath(String? origin, String path) {
  final base = origin?.trim();
  if (base == null || base.isEmpty) return null;
  return '${base.replaceAll(RegExp(r"/+$"), "")}$path';
}

/// True when [uri]'s path is the recovery callback path.
///
/// Needed because the PKCE shape (`?code=…`) carries no `type`, so the path is
/// the only thing distinguishing "reset my password" from "confirm my email".
bool isRecoveryPath(Uri uri) {
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return path == kRecoveryPath;
}

/// Resolves the effective callback kind from BOTH the URL parameters and the
/// path, so every shape lands in the right flow.
AuthCallbackKind resolveCallbackKind(Uri uri) {
  final callback = parseAuthCallback(uri);
  if (callback.kind == AuthCallbackKind.confirmation && isRecoveryPath(uri)) {
    return AuthCallbackKind.recovery;
  }
  return callback.kind;
}

/// [uri] with every auth parameter removed, query and fragment alike.
///
/// This is what the address bar is rewritten to the moment a callback is read.
/// A recovery link sitting in browser history is a replayable credential; a
/// screenshot or a shared URL carrying `token_hash` hands someone the account.
/// Non-auth parameters are preserved so an unrelated deep link survives.
Uri scrubbedUrl(Uri uri) {
  const authKeys = {
    'code',
    'token',
    'token_hash',
    'type',
    'access_token',
    'refresh_token',
    'expires_in',
    'expires_at',
    'provider_token',
    'provider_refresh_token',
    'token_type',
    'error',
    'error_code',
    'error_description',
  };
  final keptQuery = <String, String>{
    for (final e in uri.queryParameters.entries)
      if (!authKeys.contains(e.key)) e.key: e.value,
  };
  final keptFragment = <String, String>{
    for (final e in _fragmentParameters(uri.fragment).entries)
      if (!authKeys.contains(e.key)) e.key: e.value,
  };
  final fragment = keptFragment.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return uri.replace(
    queryParameters: keptQuery.isEmpty ? null : keptQuery,
    fragment: fragment.isEmpty ? '' : fragment,
  );
}

Map<String, String> _fragmentParameters(String fragment) {
  if (fragment.isEmpty) return const {};
  final raw = fragment.startsWith('#') ? fragment.substring(1) : fragment;
  final out = <String, String>{};
  for (final part in raw.split('&')) {
    if (part.isEmpty) continue;
    final i = part.indexOf('=');
    if (i <= 0) continue;
    try {
      out[Uri.decodeQueryComponent(part.substring(0, i))] =
          Uri.decodeQueryComponent(part.substring(i + 1));
    } catch (_) {
      // A malformed fragment is not a callback; skip the pair rather than
      // throwing on the app's very first frame.
    }
  }
  return out;
}

String? _firstNonEmpty(String? a, String? b) {
  if (a != null && a.trim().isNotEmpty) return a.trim();
  if (b != null && b.trim().isNotEmpty) return b.trim();
  return null;
}
