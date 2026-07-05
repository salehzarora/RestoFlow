import 'dart:convert';

/// Why a Supabase bootstrap config was rejected (fail-closed reasons).
enum SupabaseConfigErrorReason {
  /// The URL was empty / not provided.
  missingUrl,

  /// The URL was present but not a valid http(s) URL.
  invalidUrl,

  /// The anon key was empty / not provided.
  missingAnonKey,

  /// A known placeholder / default value was supplied (e.g. an unconfigured
  /// `--dart-define`).
  placeholderValue,

  /// The supplied key looked like a service-role / secret key. Clients must use
  /// the PUBLIC anon key only (DECISION D-011).
  serviceRoleKeyRejected,
}

/// Thrown when the Supabase bootstrap config is missing, invalid, or unsafe.
///
/// SECURITY: [message] is safe-to-log and NEVER contains the anon key, the
/// service-role key, or any secret material.
class SupabaseConfigException implements Exception {
  const SupabaseConfigException(this.reason, this.message);

  /// The fail-closed reason.
  final SupabaseConfigErrorReason reason;

  /// A safe-to-log developer diagnostic (no secret/key value).
  final String message;

  @override
  String toString() => 'SupabaseConfigException($reason): $message';
}

/// Validated Supabase connection config for the auth services (RF-108 Stage 2).
///
/// Holds ONLY the public project URL + anon key (DECISION D-011: a client never
/// holds a service-role key, and a URL/key is never hardcoded in source). Build
/// via [SupabaseBootstrapConfig.fromValues] or
/// [SupabaseBootstrapConfig.fromEnvironment]; both validate and FAIL CLOSED by
/// throwing [SupabaseConfigException]. The values come from `--dart-define`
/// (compile-time), never from a committed `.env` file.
class SupabaseBootstrapConfig {
  const SupabaseBootstrapConfig._({required this.url, required this.anonKey});

  /// The Supabase project URL (http/https).
  final String url;

  /// The PUBLIC anon key. Safe to ship in a client (RLS-gated); NEVER logged.
  final String anonKey;

  /// The `--dart-define` key for the project URL.
  static const String urlEnvName = 'RESTOFLOW_SUPABASE_URL';

  /// The `--dart-define` key for the anon key.
  static const String anonKeyEnvName = 'RESTOFLOW_SUPABASE_ANON_KEY';

  /// Validates raw [url] + [anonKey] and builds a config, or throws
  /// [SupabaseConfigException] (fail-closed).
  factory SupabaseBootstrapConfig.fromValues({
    required String url,
    required String anonKey,
  }) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw const SupabaseConfigException(
        SupabaseConfigErrorReason.missingUrl,
        'Supabase URL is missing (set --dart-define=$urlEnvName=...)',
      );
    }
    if (_isPlaceholder(trimmedUrl)) {
      throw const SupabaseConfigException(
        SupabaseConfigErrorReason.placeholderValue,
        'Supabase URL is a placeholder/default; provide a real project URL',
      );
    }
    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const SupabaseConfigException(
        SupabaseConfigErrorReason.invalidUrl,
        'Supabase URL is not a valid http(s) URL',
      );
    }

    final trimmedKey = anonKey.trim();
    if (trimmedKey.isEmpty) {
      throw const SupabaseConfigException(
        SupabaseConfigErrorReason.missingAnonKey,
        'Supabase anon key is missing (set --dart-define=$anonKeyEnvName=...)',
      );
    }
    if (_isPlaceholder(trimmedKey)) {
      throw const SupabaseConfigException(
        SupabaseConfigErrorReason.placeholderValue,
        'Supabase anon key is a placeholder/default; provide the real anon key',
      );
    }
    if (_looksLikeServiceRoleKey(trimmedKey)) {
      // NOTE: never echo the offending key value.
      throw const SupabaseConfigException(
        SupabaseConfigErrorReason.serviceRoleKeyRejected,
        'Rejected a service-role / secret-looking key: clients must use the '
        'PUBLIC anon key only (DECISION D-011)',
      );
    }

    return SupabaseBootstrapConfig._(url: trimmedUrl, anonKey: trimmedKey);
  }

  /// Reads the `--dart-define` values and builds the config (fail-closed).
  ///
  /// [readEnv] is injectable so unit tests can supply an environment map; the
  /// default reads the compile-time `String.fromEnvironment` values. No secret
  /// is ever hardcoded here - empty/default values fail closed.
  factory SupabaseBootstrapConfig.fromEnvironment({
    String Function(String name)? readEnv,
  }) {
    final read = readEnv ?? _readDartDefine;
    return SupabaseBootstrapConfig.fromValues(
      url: read(urlEnvName),
      anonKey: read(anonKeyEnvName),
    );
  }

  /// RF-LIVE-002 — true when a VALID real config (public URL + anon key) is
  /// present, WITHOUT throwing. Used to detect the dangerous "real credentials
  /// present but the app is in demo mode" case in a release build. Returns false
  /// for missing/placeholder/invalid/service-role config (all fail-closed). Reads
  /// no secret into any log; [readEnv] is injectable for tests.
  static bool isPresentAndValid({String Function(String name)? readEnv}) {
    try {
      SupabaseBootstrapConfig.fromEnvironment(readEnv: readEnv);
      return true;
    } on SupabaseConfigException {
      return false;
    }
  }
}

/// Reads a compile-time `--dart-define` value (the production source). Returns
/// '' when the define is absent, so the config fails closed.
String _readDartDefine(String name) {
  switch (name) {
    case SupabaseBootstrapConfig.urlEnvName:
      return const String.fromEnvironment('RESTOFLOW_SUPABASE_URL');
    case SupabaseBootstrapConfig.anonKeyEnvName:
      return const String.fromEnvironment('RESTOFLOW_SUPABASE_ANON_KEY');
    default:
      return '';
  }
}

/// Known placeholder/default values that must fail closed (lower-cased).
const Set<String> _placeholders = {
  'your_supabase_url',
  'your-supabase-url',
  'your_supabase_anon_key',
  'your-supabase-anon-key',
  'supabase_url',
  'supabase_anon_key',
  'changeme',
  'change_me',
  'replace_me',
  'replaceme',
  'placeholder',
  'todo',
  'xxx',
};

bool _isPlaceholder(String value) =>
    _placeholders.contains(value.toLowerCase());

/// Best-effort detection of a service-role / secret key, so a client can never
/// be configured with one (DECISION D-011). Detects:
/// - the new-style Supabase secret key prefix `sb_secret_`;
/// - a legacy JWT whose decoded payload carries `"role":"service_role"`.
/// The anon key (`"role":"anon"`) passes. The key value is never logged.
bool _looksLikeServiceRoleKey(String key) {
  if (key.startsWith('sb_secret_')) return true;
  final parts = key.split('.');
  if (parts.length == 3 && parts[0].startsWith('eyJ')) {
    final payload = _decodeBase64Url(parts[1]);
    if (payload != null) {
      final normalized = payload.replaceAll(' ', '');
      if (normalized.contains('"role":"service_role"')) return true;
    }
  }
  return false;
}

/// Decodes a base64url segment (with padding tolerance), or null on failure.
String? _decodeBase64Url(String segment) {
  try {
    var s = segment.replaceAll('-', '+').replaceAll('_', '/');
    switch (s.length % 4) {
      case 2:
        s += '==';
        break;
      case 3:
        s += '=';
        break;
    }
    return utf8.decode(base64.decode(s));
  } catch (_) {
    return null;
  }
}
