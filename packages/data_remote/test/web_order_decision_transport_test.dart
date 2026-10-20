import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  test(
    'decision uses same client JWT, fixed Edge path and exact body once',
    () async {
      var calls = 0;
      final body = <String, dynamic>{
        'action': 'reject',
        'request_id': 'synthetic-request',
        'decision_id': 'same-decision',
        'reason': 'نفد المخزون',
      };
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'public-test-key',
        httpClient: MockClient((request) async {
          calls++;
          expect(
            request.url.toString(),
            'https://synthetic.invalid/functions/v1/pos-web-order-decision',
          );
          expect(request.method, 'POST');
          expect(
            request.headers['Authorization'],
            'Bearer synthetic-device-jwt',
          );
          expect(jsonDecode(request.body), body);
          return http.Response(
            '{"ok":true,"replayed":false}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      client.functions.setAuth('synthetic-device-jwt');
      final transport = SupabaseSyncRpcTransport(client);
      expect(await transport.decideWebOrder(body), {
        'ok': true,
        'replayed': false,
      });
      expect(calls, 1);
    },
  );

  for (final status in [401, 403, 500]) {
    test('HTTP $status is sanitized with no decision fallback/retry', () async {
      var calls = 0;
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'public-test-key',
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('synthetic-sensitive-server-detail', status);
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseSyncRpcTransport(client).decideWebOrder({}),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.message,
            'details omitted',
            isNull,
          ),
        ),
      );
      expect(calls, 1);
    });
  }

  test(
    'offline upgrade retains decision boundary and never falls back to RPC',
    () async {
      final held = UpgradableSyncTransport();
      expect(
        () => held.decideWebOrder({}),
        throwsA(isA<SyncTransportException>()),
      );
      var calls = 0;
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'public-test-key',
        httpClient: MockClient((request) async {
          calls++;
          expect(request.url.path, '/functions/v1/pos-web-order-decision');
          return http.Response(
            '{"ok":false,"code":"decision_conflict"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      held.upgrade(SupabaseSyncRpcTransport(client));
      expect(await held.decideWebOrder({}), {
        'ok': false,
        'code': 'decision_conflict',
      });
      expect(calls, 1);
    },
  );
}
