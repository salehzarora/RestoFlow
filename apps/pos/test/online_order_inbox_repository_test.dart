import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/main.dart' as pos;
import 'package:restoflow_pos/src/data/online_order_inbox.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_order_inbox_fixtures.dart';

class _Transport extends SyncRpcTransport {
  Object? result = inboxPageJson();
  SyncTransportException? error;
  String? function;
  Map<String, dynamic>? params;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    this.function = function;
    this.params = params;
    if (error != null) throw error!;
    return result;
  }
}

class _Images implements DeviceImageUrlResolver {
  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async => {};
}

class _Logo implements DeviceReceiptLogoReader {
  @override
  Future<ReceiptLogoBytes?> load(String objectPath) async => null;
}

class _GatedStore extends InMemoryDeviceSessionSecretStore {
  final gate = Completer<DeviceSessionCredential?>();
  @override
  Future<DeviceSessionCredential?> read() => gate.future;
}

void main() {
  test(
    'trusted menu item ID is retained without changing priced snapshots',
    () {
      final json = requestJson();
      final item = OnlineOrderRequest.fromJson(json).items.single;
      expect(item.menuItemId, json['items'][0]['menu_item_id']);
      expect(item.name, json['items'][0]['item_name_snapshot']);
      expect(item.unitPriceMinor, 1000);
      expect(item.lineTotalMinor, 2800);
      for (final id in [null, 9, 'not-an-id']) {
        final invalid = requestJson();
        final line = Map<String, dynamic>.from(invalid['items'][0]);
        line['menu_item_id'] = id;
        invalid['items'] = [line];
        expect(
          () => OnlineOrderRequest.fromJson(invalid),
          throwsA(isA<OnlineInboxException>()),
        );
      }
    },
  );
  test('optional item notes preserve old snapshots and remain per-line', () {
    final old = OnlineOrderRequest.fromJson(requestJson());
    expect(old.items.single.notes, isNull);
    final json = requestJson();
    json['items'][0]['notes'] = 'بدون بصل\nבלי בצל 🍽';
    json['items'] = [
      json['items'][0],
      {...json['items'][0], 'notes': 'Extra onion'},
    ];
    json['totals']['subtotal_minor'] = 5600;
    json['totals']['tax_total_minor'] = 280;
    json['totals']['grand_total_minor'] = 5880;
    final request = OnlineOrderRequest.fromJson(json);
    expect(request.items.map((i) => i.notes), [
      'بدون بصل\nבלי בצל 🍽',
      'Extra onion',
    ]);
    expect(request.notes, 'بدون بصل / בלי בצל');
    for (final notes in [7, 'n' * 141, 'a\tb', 'a\u0085b']) {
      final invalid = requestJson();
      invalid['items'][0]['notes'] = notes;
      expect(
        () => OnlineOrderRequest.fromJson(invalid),
        throwsA(isA<OnlineInboxException>()),
      );
    }
  });
  test(
    'branch change during secret read prevents sending prior-scope RPC',
    () async {
      final transport = _Transport();
      final store = _GatedStore();
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: pinId, deviceId: deviceId),
          ),
          onlineOrderInboxSecretStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org',
              restaurantId: 'restaurant',
              branchId: 'branch',
              deviceId: deviceId,
              deviceType: 'pos',
              deviceSessionId: 'device-session',
            ),
          );
      final repo = container.read(onlineOrderInboxRepositoryProvider);
      final pending = repo.fetch();
      container
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org',
              restaurantId: 'restaurant',
              branchId: 'other-branch',
              deviceId: deviceId,
              deviceType: 'pos',
              deviceSessionId: 'new-device-session',
            ),
          );
      store.gate.complete(
        const DeviceSessionCredential(
          deviceId: deviceId,
          sessionToken: 'test-only-device-token',
        ),
      );
      await expectLater(pending, throwsA(isA<OnlineInboxException>()));
      expect(transport.function, isNull);
    },
  );
  test(
    'strict priced snapshots keep quantities, modifiers and integer totals',
    () {
      final page = OnlineInboxPage.fromJson(inboxPageJson());
      expect(page.requests.single.items.single.quantity, 2);
      expect(page.requests.single.items.single.modifiers.single.quantity, 2);
      expect(page.requests.single.grandTotalMinor, 2940);
      expect(page.requests.single.customerPhone, '+972501234567');
      expect(
        OnlineInboxDecisionResult.fromJson(decisionJson()).canonicalOrderId,
        canonicalId,
      );
    },
  );
  test(
    'floating money, inconsistent totals and incomplete cursors fail closed',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => (j['requests'][0]['totals'])['grand_total_minor'] = 2940.0,
        (j) => (j['requests'][0]['items'][0])['line_total_minor'] = 2799,
        (j) => j['has_more'] = true,
        (j) => j['next_cursor'] = {'id': requestId},
        (j) => j['requests'][0]['canonical_order_id'] = canonicalId,
      ]) {
        final json = inboxPageJson();
        mutate(json);
        expect(
          () => OnlineInboxPage.fromJson(json),
          throwsA(isA<OnlineInboxException>()),
        );
      }
    },
  );
  test(
    'real RPCs use existing raw device credential and personal PIN',
    () async {
      final transport = _Transport();
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(
          deviceId: deviceId,
          sessionToken: 'test-only-device-token',
        ),
      );
      final repo = RealOnlineOrderInboxRepository(
        transport: transport,
        session: const SyncSession(pinSessionId: pinId, deviceId: deviceId),
        secretStore: store,
      );
      await repo.fetch();
      expect(transport.function, 'pos_web_order_inbox');
      expect(transport.params!['p_device_id'], deviceId);
      expect(transport.params!['p_pin_session_id'], pinId);
      expect(
        transport.params!['p_device_session_token'],
        'test-only-device-token',
      );
      transport.result = decisionJson(status: 'rejected');
      await repo.decide(
        requestId: requestId,
        decisionId: decisionId,
        decision: OnlineOrderDecision.reject,
        reason: '  Sold out  ',
      );
      expect(transport.function, 'pos_reject_web_order');
      expect(transport.params!['p_reason'], 'Sold out');
    },
  );
  test(
    'missing, wrong-device and replaced-session credentials never invoke',
    () async {
      final transport = _Transport();
      final store = InMemoryDeviceSessionSecretStore();
      Future<void> refused({bool current = true}) async {
        final repo = RealOnlineOrderInboxRepository(
          transport: transport,
          session: const SyncSession(pinSessionId: pinId, deviceId: deviceId),
          secretStore: store,
          isCurrent: () => current,
        );
        await expectLater(repo.fetch(), throwsA(isA<OnlineInboxException>()));
        expect(transport.function, isNull);
      }

      await refused();
      await store.write(
        const DeviceSessionCredential(
          deviceId: requestId,
          sessionToken: 'test-only-device-token',
        ),
      );
      await refused();
      await store.write(
        const DeviceSessionCredential(
          deviceId: deviceId,
          sessionToken: 'test-only-device-token',
        ),
      );
      await refused(current: false);
    },
  );
  test(
    'missing hosted RPC becomes unavailable without SQL diagnostics',
    () async {
      final transport = _Transport()
        ..error = const SyncTransportException(
          SyncTransportErrorKind.server,
          code: 'PGRST202',
          message: 'private diagnostic',
        );
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(
          deviceId: deviceId,
          sessionToken: 'test-only-device-token',
        ),
      );
      final repo = RealOnlineOrderInboxRepository(
        transport: transport,
        session: const SyncSession(pinSessionId: pinId, deviceId: deviceId),
        secretStore: store,
      );
      await expectLater(
        repo.fetch(),
        throwsA(
          predicate(
            (e) =>
                e is OnlineInboxException &&
                e.failure == OnlineInboxFailure.unavailable &&
                !e.toString().contains('private diagnostic'),
          ),
        ),
      );
    },
  );
  test(
    'real boot composition activates inbox with the same secret store',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(
          deviceId: deviceId,
          sessionToken: 'test-only-device-token',
        ),
      );
      final transport = _Transport();
      final boot = pos.PosBootCoordinator(
        prefs: prefs,
        demoMode: false,
        secretStore: store,
        createSession: () async => (
          transport: transport,
          imageUrlResolver: _Images(),
          receiptLogoReader: _Logo(),
          invalidationSourceFactory: (_) => const DisabledInvalidationSource(),
        ),
      );
      final root =
          pos.buildPosBootRoot(
                prefs: prefs,
                locale: const Locale('en'),
                coordinator: boot,
                includePeriodicWork: false,
                extraOverrides: [
                  runtimeConfigProvider.overrideWithValue(
                    RuntimeConfig.test(isDemoMode: false),
                  ),
                  posSyncSessionProvider.overrideWithValue(
                    const SyncSession(pinSessionId: pinId, deviceId: deviceId),
                  ),
                ],
              )
              as DeviceBootGate<pos.PosBootResult>;
      final scope = root.builder(await boot.bootstrap()) as ProviderScope;
      final container = ProviderContainer(overrides: scope.overrides);
      addTearDown(container.dispose);
      container
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org',
              restaurantId: 'restaurant',
              branchId: 'branch',
              deviceId: deviceId,
              deviceType: 'pos',
              deviceSessionId: 'device-session',
            ),
          );
      expect(container.read(onlineOrderInboxSecretStoreProvider), same(store));
      expect(
        container.read(onlineOrderInboxRepositoryProvider),
        isA<RealOnlineOrderInboxRepository>(),
      );
      await container.read(onlineOrderInboxRepositoryProvider).fetch();
      expect(transport.function, 'pos_web_order_inbox');
    },
  );
}
