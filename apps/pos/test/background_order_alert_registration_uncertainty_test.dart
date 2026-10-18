// Separate test isolate: uncertain registration deliberately quarantines the
// process-wide native lane. It cannot be cleared by OFF or provider recreation.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/online_order_inbox.dart';
import 'package:restoflow_pos/src/media/background_order_alert_bridge.dart';
import 'package:restoflow_pos/src/state/background_order_alerts.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:supabase/supabase.dart' as sdk;

import 'online_order_inbox_fixtures.dart';

class _Wire extends http.BaseClient {
  final release = Completer<void>();
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host != 'synthetic.invalid' ||
        request.url.path != '/rest/v1/rpc/pos_register_order_alert') {
      throw StateError('unexpected synthetic request');
    }
    calls++;
    await release.future;
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'ok': true,
            'registration_id': '22222222-2222-4222-8222-222222222222',
            'authority_expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 15))
                .toIso8601String(),
          }),
        ),
      ),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _Bridge implements BackgroundOrderAlertBridge {
  int prepares = 0;
  int bindings = 0;
  void Function()? tokenHint;
  @override
  Future<Map<String, dynamic>> prepare({bool requestPermission = false}) async {
    prepares++;
    return {
      'available': true,
      'enabled': requestPermission,
      'installation_id': '11111111-1111-4111-8111-111111111111',
      'fcm_token': 'synthetic-token',
      'status_secret': '0' * 64,
      'generation': 1,
    };
  }

  @override
  Future<bool> bind(Map<String, dynamic> _) async {
    bindings++;
    return true;
  }

  @override
  Future<void> pending(Map<String, dynamic> _) async {}
  @override
  Future<void> suspend({bool retainOptIn = false}) async {}
  @override
  Future<void> disable() async {}
  @override
  Future<bool> consumeInboxTap() async => false;
  @override
  void setHints({
    required void Function() tokenChanged,
    required void Function() pendingHint,
  }) {
    tokenHint = tokenChanged;
  }

  @override
  Future<void> dispose() async {}
}

class _GatewayFailure extends SyncRpcTransport {
  _GatewayFailure(this.wire);
  final _Wire wire;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    wire.calls++;
    // Existing classifier uses `server` for 502; it is NOT proof of rollback.
    throw const SyncTransportException(
      SyncTransportErrorKind.server,
      code: '502',
    );
  }
}

void main() => registrationUncertaintyScenario();

// Reused by the tiny gateway test in a separate process/test isolate: each
// uncertainty quarantine must remain intact rather than being reset for tests.
void registrationUncertaintyScenario({bool gatewayFailure = false}) {
  testWidgets(
    '${gatewayFailure ? 'server-kind 502' : 'real SDK timeout'} never replays uncertain registration, even after OFF/recreation',
    (tester) async {
      final wire = _Wire();
      final client = (await tester.runAsync(
        () async => sdk.SupabaseClient(
          'https://synthetic.invalid',
          'synthetic-public-key',
          httpClient: wire,
        ),
      ))!;
      final SyncRpcTransport transport = gatewayFailure
          ? _GatewayFailure(wire)
          : SupabaseSyncRpcTransport(client); // unchanged real 15s timeout
      final bridge = _Bridge();
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(
          deviceId: deviceId,
          sessionToken: 'synthetic-device-token',
        ),
      );
      final inbox = FakeInboxRepository();
      ProviderContainer make() => ProviderContainer(
        overrides: [
          backgroundOrderAlertsBuildEnabledProvider.overrideWithValue(true),
          backgroundOrderAlertBridgeProvider.overrideWithValue(bridge),
          backgroundOrderAlertEndpointProvider.overrideWithValue(
            'https://synthetic.invalid/functions/v1/pos-order-alert-status',
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(deviceId: deviceId, pinSessionId: pinId),
          ),
          onlineOrderInboxSecretStoreProvider.overrideWithValue(store),
          onlineOrderInboxIdentityProvider.overrideWithValue(
            'synthetic-device|PIN',
          ),
          onlineOrderInboxRepositoryProvider.overrideWithValue(inbox),
          onlineOrderInboxPollIntervalProvider.overrideWithValue(null),
          onlineOrderInboxAlertIntervalProvider.overrideWithValue(null),
          onlineInboxAcceptedPrintProvider.overrideWithValue(
            (_, __) async => throw StateError('printing forbidden'),
          ),
          onlineInboxCancelPrintProvider.overrideWithValue(() {}),
        ],
      );
      final original = make();
      original.listen(backgroundOrderAlertsProvider, (_, __) {});
      await tester.pump();
      final controller = original.read(backgroundOrderAlertsProvider.notifier);
      final enabling = controller.setEnabled(true);
      await tester.pump();
      expect(wire.calls, 1);
      if (!gatewayFailure) await tester.pump(const Duration(seconds: 16));
      expect(original.read(backgroundOrderAlertsProvider).busy, false);
      await enabling;
      expect(original.read(backgroundOrderAlertsProvider).failed, true);
      expect(original.read(backgroundOrderAlertsProvider).busy, false);
      final prepares = bridge.prepares;
      await controller.setEnabled(false);
      await controller.setEnabled(true);
      bridge.tokenHint!();
      controller.onResume();
      await tester.pump(const Duration(minutes: 2));
      expect(bridge.prepares, prepares);
      expect(wire.calls, 1);
      expect(bridge.bindings, 0);
      wire.release.complete(); // underlying HTTP still existed AFTER timeout
      await tester.pump();
      expect(original.read(backgroundOrderAlertsProvider).enabled, false);
      original.dispose();
      await tester.pump(Duration.zero);
      final replacement = make();
      replacement.listen(backgroundOrderAlertsProvider, (_, __) {});
      await tester.pump();
      await replacement
          .read(backgroundOrderAlertsProvider.notifier)
          .setEnabled(true);
      expect(wire.calls, 1);
      expect(bridge.prepares, prepares);
      expect(bridge.bindings, 0);
      expect(inbox.decisions, isEmpty);
      replacement.dispose();
      // SDK JSON-isolate teardown uses real isolate messages, not fake timers.
      await tester.runAsync(client.dispose);
      await tester.pump(Duration.zero);
    },
  );
}
