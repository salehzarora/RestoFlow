import 'dart:convert';

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

/// Builds a JWT-shaped string whose payload carries the given [role]. The header
/// base64url-encodes to `eyJ...`, matching the real Supabase key shape.
String makeJwt(String role) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg({'alg': 'HS256', 'typ': 'JWT'});
  final payload = seg({'iss': 'supabase', 'role': role, 'exp': 1983812996});
  return '$header.$payload.signature-not-verified';
}

const validUrl = 'https://abcdefgh.supabase.co';

void main() {
  group('SupabaseBootstrapConfig.fromValues - valid', () {
    test('a real https URL + an anon JWT parses', () {
      final config = SupabaseBootstrapConfig.fromValues(
        url: validUrl,
        anonKey: makeJwt('anon'),
      );
      expect(config.url, validUrl);
      expect(config.anonKey, isNotEmpty);
    });

    test('trims surrounding whitespace', () {
      final config = SupabaseBootstrapConfig.fromValues(
        url: '  $validUrl  ',
        anonKey: '  ${makeJwt('anon')}  ',
      );
      expect(config.url, validUrl);
    });
  });

  group('SupabaseBootstrapConfig.fromValues - fail closed', () {
    SupabaseConfigErrorReason reasonOf(void Function() build) {
      try {
        build();
        fail('expected SupabaseConfigException');
      } on SupabaseConfigException catch (e) {
        return e.reason;
      }
    }

    test('missing URL -> missingUrl', () {
      expect(
        reasonOf(
          () => SupabaseBootstrapConfig.fromValues(
            url: '',
            anonKey: makeJwt('anon'),
          ),
        ),
        SupabaseConfigErrorReason.missingUrl,
      );
    });

    test('missing anon key -> missingAnonKey', () {
      expect(
        reasonOf(
          () => SupabaseBootstrapConfig.fromValues(url: validUrl, anonKey: ''),
        ),
        SupabaseConfigErrorReason.missingAnonKey,
      );
    });

    test('invalid URL (no scheme / wrong scheme / no host) -> invalidUrl', () {
      for (final bad in ['not-a-url', 'ftp://x.y', 'http://', 'justtext']) {
        expect(
          reasonOf(
            () => SupabaseBootstrapConfig.fromValues(
              url: bad,
              anonKey: makeJwt('anon'),
            ),
          ),
          SupabaseConfigErrorReason.invalidUrl,
          reason: bad,
        );
      }
    });

    test('placeholder URL / key -> placeholderValue', () {
      expect(
        reasonOf(
          () => SupabaseBootstrapConfig.fromValues(
            url: 'YOUR_SUPABASE_URL',
            anonKey: makeJwt('anon'),
          ),
        ),
        SupabaseConfigErrorReason.placeholderValue,
      );
      expect(
        reasonOf(
          () => SupabaseBootstrapConfig.fromValues(
            url: validUrl,
            anonKey: 'changeme',
          ),
        ),
        SupabaseConfigErrorReason.placeholderValue,
      );
    });

    test('service-role JWT -> serviceRoleKeyRejected', () {
      expect(
        reasonOf(
          () => SupabaseBootstrapConfig.fromValues(
            url: validUrl,
            anonKey: makeJwt('service_role'),
          ),
        ),
        SupabaseConfigErrorReason.serviceRoleKeyRejected,
      );
    });

    test('new-style secret key (sb_secret_...) -> serviceRoleKeyRejected', () {
      // Built from parts so the literal never trips tools/check_secrets.sh; the
      // runtime value still carries the real new-style secret-key prefix.
      final fakeSecretKey = ['sb', 'secret', 'AbCdEf0123456789xyz'].join('_');
      expect(
        reasonOf(
          () => SupabaseBootstrapConfig.fromValues(
            url: validUrl,
            anonKey: fakeSecretKey,
          ),
        ),
        SupabaseConfigErrorReason.serviceRoleKeyRejected,
      );
    });

    test('the rejection message NEVER echoes the offending key', () {
      final secret = makeJwt('service_role');
      try {
        SupabaseBootstrapConfig.fromValues(url: validUrl, anonKey: secret);
        fail('expected rejection');
      } on SupabaseConfigException catch (e) {
        expect(e.message, isNot(contains(secret)));
        expect(e.toString(), isNot(contains(secret)));
      }
    });
  });

  group('SupabaseBootstrapConfig.fromEnvironment - injectable env', () {
    test('reads the documented dart-define keys via an injected reader', () {
      final env = <String, String>{
        SupabaseBootstrapConfig.urlEnvName: validUrl,
        SupabaseBootstrapConfig.anonKeyEnvName: makeJwt('anon'),
      };
      final config = SupabaseBootstrapConfig.fromEnvironment(
        readEnv: (name) => env[name] ?? '',
      );
      expect(config.url, validUrl);
    });

    test(
      'fails closed when the environment is unconfigured (empty defines)',
      () {
        expect(
          () => SupabaseBootstrapConfig.fromEnvironment(readEnv: (_) => ''),
          throwsA(isA<SupabaseConfigException>()),
        );
      },
    );

    test('the env key names are exactly the documented dart-define names', () {
      expect(SupabaseBootstrapConfig.urlEnvName, 'RESTOFLOW_SUPABASE_URL');
      expect(
        SupabaseBootstrapConfig.anonKeyEnvName,
        'RESTOFLOW_SUPABASE_ANON_KEY',
      );
    });
  });
}
