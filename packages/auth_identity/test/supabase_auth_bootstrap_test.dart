import 'dart:convert';

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

import 'fake_rpc_transport.dart';

String anonJwt() {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256'})}.${seg({'role': 'anon'})}.sig';
}

void main() {
  group('SupabaseAuthBootstrap', () {
    final config = SupabaseBootstrapConfig.fromValues(
      url: 'https://abcdefgh.supabase.co',
      anonKey: anonJwt(),
    );

    test(
      'createRpcTransport hands the injected builder the validated url + anon key',
      () {
        SupabaseBootstrapConfig? received;
        final fake = FakeRpcTransport(value: null);
        final boot = SupabaseAuthBootstrap(
          config: config,
          transportBuilder: (cfg) {
            received = cfg;
            return fake;
          },
        );

        final transport = boot.createRpcTransport();

        expect(identical(transport, fake), isTrue);
        expect(received, isNotNull);
        expect(received!.url, config.url);
        expect(received!.anonKey, config.anonKey);
      },
    );

    test(
      'the produced transport drives AuthContextRepository (no real client/network)',
      () async {
        final fake = FakeRpcTransport(
          value: {
            'ok': true,
            'app_user': {
              'id': 'u',
              'email': 'u@x.test',
              'display_name': null,
              'is_active': true,
            },
            'is_platform_admin': false,
            'memberships': const [],
          },
        );
        final boot = SupabaseAuthBootstrap(
          config: config,
          transportBuilder: (_) => fake,
        );

        final repo = AuthContextRepository(boot.createRpcTransport());
        final result = await repo.fetchMyContext();

        expect(result.isSuccess, isTrue);
        // get_my_context is called with no user id (identity is server-side).
        expect(fake.lastFunction, 'get_my_context');
        expect(fake.lastParams, isEmpty);
      },
    );

    test('the produced transport drives PinSessionService', () async {
      final fake = FakeRpcTransport(value: 'pin-uuid');
      final boot = SupabaseAuthBootstrap(
        config: config,
        transportBuilder: (_) => fake,
      );

      final service = PinSessionService(
        boot.createRpcTransport(),
        generateLocalOperationId: () => 'op',
      );
      final result = await service.startPinSession(
        deviceSessionId: 'd',
        employeeProfileId: 'e',
        pinVerifier: 'ref:A',
      );

      expect(result.isSuccess, isTrue);
      expect(fake.lastFunction, 'start_pin_session');
    });
  });
}
