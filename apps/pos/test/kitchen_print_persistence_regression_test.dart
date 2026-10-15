import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/spool/kitchen_print_containment.dart';

// This file deliberately uses only the reviewed guard's public API, so the
// SAME safety assertions can be run against the preserved before candidate.
const _dispatch = '50000000-0000-4000-8000-000000000001';
const _request = '60000000-0000-4000-8000-000000000001';
final _now = DateTime.utc(2026, 10, 15);
int _nextScope = 0;

class _Transport implements SyncRpcTransport {
  Object? response;
  int calls = 0;
  Future<Object?> Function()? handler;
  @override
  Future<Object?> invoke(String rpc, Map<String, dynamic> params) async {
    calls++;
    return handler == null ? response : handler!();
  }
}

class _Row extends Fake implements KitchenSpoolJobRow {
  _Row(this.context);
  final DeviceContext context;
  @override
  String get organizationId => context.organizationId;
  @override
  String get restaurantId => context.restaurantId!;
  @override
  String get branchId => context.branchId;
  @override
  String get deviceId => context.deviceId!;
  @override
  String get dispatchId => _dispatch;
  @override
  String get localJobId => 'ordinary';
}

class _Fixture {
  _Fixture()
    : context = DeviceContext(
        organizationId: '10000000-0000-4000-8000-000000000001',
        restaurantId: '20000000-0000-4000-8000-000000000001',
        branchId:
            '30000000-0000-4000-8000-${(++_nextScope).toString().padLeft(12, '0')}',
        deviceId: '40000000-0000-4000-8000-000000000001',
      );
  final DeviceContext context;
  final transport = _Transport();
  final secrets = InMemoryDeviceSessionSecretStore();
  final cache = <String, String>{};
  bool offline = false, current = true, failWrite = false;
  Future<void> Function(String key, String value)? onWrite;
  Future<void> initialize() async {
    await secrets.write(
      DeviceSessionCredential(
        deviceId: context.deviceId!,
        sessionToken: 'synthetic-r2-session',
      ),
    );
    transport.response = policy('ordinary', 1);
  }

  Map<String, Object?> policy(
    String mode,
    int revision, {
    bool hold = false,
    DeviceContext? scope,
  }) {
    final c = scope ?? context;
    return {
      'ok': true,
      'organization_id': c.organizationId,
      'restaurant_id': c.restaurantId,
      'branch_id': c.branchId,
      'device_id': c.deviceId,
      'mode': mode,
      'revision': revision,
      'held_dispatch_ids': hold ? [_dispatch] : <String>[],
      'target_request_id': mode == 'target_only' ? _request : null,
      'expires_at': mode == 'target_only'
          ? _now.add(const Duration(minutes: 5)).toIso8601String()
          : null,
    };
  }

  KitchenPrintContainment build({DeviceContext? scope}) =>
      KitchenPrintContainment(
        context: scope ?? context,
        secretStore: secrets,
        transport: transport,
        isCurrent: () => current,
        isOffline: () => offline,
        readCache: (key) async => cache[key],
        writeCache: (key, value) async {
          if (failWrite) throw StateError('synthetic secure write failure');
          final hook = onWrite;
          if (hook != null) {
            await hook(key, value);
          } else {
            cache[key] = value;
          }
        },
        now: () => _now,
      );
  Map<String, String> scopeJson() => {
    'organization': context.organizationId,
    'restaurant': context.restaurantId!,
    'branch': context.branchId,
    'device': context.deviceId!,
  };
}

// A new VM isolate has a fresh static synchronization domain and zero process
// authority. It reopens only the exact persisted bytes, not parent memory.
void _offlineIsolate(List<Object?> message) async {
  final reply = message[0] as SendPort;
  try {
    final cache = Map<String, String>.from(message[1] as Map);
    final ids = Map<String, String>.from(message[2] as Map);
    final context = DeviceContext(
      organizationId: ids['organization']!,
      restaurantId: ids['restaurant'],
      branchId: ids['branch']!,
      deviceId: ids['device'],
    );
    final secrets = InMemoryDeviceSessionSecretStore();
    await secrets.write(
      DeviceSessionCredential(
        deviceId: context.deviceId!,
        sessionToken: 'synthetic-r2-session',
      ),
    );
    final transport = _Transport();
    final guard = KitchenPrintContainment(
      context: context,
      secretStore: secrets,
      transport: transport,
      isCurrent: () => true,
      isOffline: () => true,
      readCache: (key) async => cache[key],
      writeCache: (key, value) async {
        throw StateError('offline probe must never write');
      },
      now: () => _now,
    );
    reply.send({
      'ordinary': await guard.allowsOrdinary(),
      'job': await guard.allowsJob(_Row(context)),
      'dispatch': await guard.allowsDispatch(_dispatch),
      'rpcCalls': transport.calls,
    });
  } catch (error) {
    reply.send({'error': error.runtimeType.toString()});
  }
}

Future<Map<String, Object?>> _coldProcess(_Fixture f) async {
  final port = ReceivePort();
  await Isolate.spawn(_offlineIsolate, [
    port.sendPort,
    Map<String, String>.of(f.cache),
    f.scopeJson(),
  ]);
  try {
    return Map<String, Object?>.from(
      await port.first.timeout(const Duration(seconds: 10)) as Map,
    );
  } finally {
    port.close();
  }
}

void main() {
  for (final mode in ['blocked', 'target_only', 'ordinary']) {
    test(
      '$mode failed restrictive write: memory, controller and cold process deny',
      () async {
        final f = _Fixture();
        await f.initialize();
        final guard = f.build();
        expect(await guard.allowsOrdinary(), isTrue);
        final oldBytes = Map<String, String>.of(f.cache);
        f.transport.response = f.policy(mode, 2, hold: mode == 'ordinary');
        f.failWrite = true;
        expect(await guard.allowsOrdinary(), isFalse);
        expect(
          f.cache,
          oldBytes,
          reason: 'proof cannot assume deletion or another successful write',
        );
        f.offline = true;
        expect(await guard.allowsOrdinary(), isFalse);
        expect(await guard.allowsJob(_Row(f.context)), isFalse);
        expect(await guard.allowsDispatch(_dispatch), isFalse);
        expect(await f.build().allowsOrdinary(), isFalse);
        expect(await _coldProcess(f), {
          'ordinary': false,
          'job': false,
          'dispatch': false,
          'rpcCalls': 0,
        });
      },
    );

    test(
      '$mode restriction is effective before a failed pending write completes',
      () async {
        final f = _Fixture();
        await f.initialize();
        final guard = f.build();
        expect(await guard.allowsOrdinary(), isTrue);
        final entered = Completer<void>(), release = Completer<void>();
        f.onWrite = (key, value) async {
          entered.complete();
          await release.future;
        };
        f.transport.response = f.policy(mode, 2, hold: mode == 'ordinary');
        final observe = guard.allowsOrdinary();
        await entered.future;
        f.offline = true;
        var completedBeforeWrite = false;
        final permission = guard.allowsJob(_Row(f.context)).then((value) {
          completedBeforeWrite = true;
          return value;
        });
        await Future<void>.delayed(Duration.zero);
        final early = completedBeforeWrite;
        release.completeError(StateError('synthetic pending-write failure'));
        expect(await observe, isFalse);
        expect(await permission, isFalse);
        expect(
          early,
          isTrue,
          reason: 'learned restriction must not await persistence',
        );
        expect(await _coldProcess(f), {
          'ordinary': false,
          'job': false,
          'dispatch': false,
          'rpcCalls': 0,
        });
      },
    );
  }

  test(
    'current verified ordinary spool stays offline-capable; cold cache never grants',
    () async {
      final f = _Fixture();
      await f.initialize();
      final guard = f.build();
      expect(await guard.allowsOrdinary(), isTrue);
      f.offline = true;
      expect(await guard.allowsOrdinary(), isTrue);
      expect(await guard.allowsJob(_Row(f.context)), isTrue);
      expect(
        f.transport.calls,
        1,
        reason: 'no unconditional RPC added to valid offline continuation',
      );
      expect(await _coldProcess(f), {
        'ordinary': false,
        'job': false,
        'dispatch': false,
        'rpcCalls': 0,
      });
      final restarted = f.build();
      expect(await restarted.allowsOrdinary(), isFalse);
      f.offline = false;
      expect(await restarted.allowsOrdinary(), isTrue);
      f.offline = true;
      expect(await restarted.allowsJob(_Row(f.context)), isTrue);
    },
  );

  test(
    'lost cache-write reply after durable restriction cannot restore permission',
    () async {
      final f = _Fixture();
      await f.initialize();
      final guard = f.build();
      expect(await guard.allowsOrdinary(), isTrue);
      f.onWrite = (key, value) async {
        f.cache[key] = value;
        throw StateError('synthetic lost completion');
      };
      f.transport.response = f.policy('ordinary', 2, hold: true);
      expect(await guard.allowsOrdinary(), isFalse);
      f.offline = true;
      expect(await guard.allowsJob(_Row(f.context)), isFalse);
      expect(await _coldProcess(f), {
        'ordinary': false,
        'job': false,
        'dispatch': false,
        'rpcCalls': 0,
      });
    },
  );

  test(
    'restoring old permissive cache bytes cannot mint restart authority',
    () async {
      final f = _Fixture();
      await f.initialize();
      final guard = f.build();
      expect(await guard.allowsOrdinary(), isTrue);
      final oldBytes = Map<String, String>.of(f.cache);
      f.transport.response = f.policy('ordinary', 2, hold: true);
      expect(
        await guard.allowsOrdinary(),
        isTrue,
      ); // other unheld work remains valid
      f.cache
        ..clear()
        ..addAll(
          oldBytes,
        ); // simulated cache recovery, never a production operation
      f.offline = true;
      expect(await guard.allowsJob(_Row(f.context)), isFalse);
      expect(await _coldProcess(f), {
        'ordinary': false,
        'job': false,
        'dispatch': false,
        'rpcCalls': 0,
      });
    },
  );

  test(
    'late old RPC response cannot overwrite a newer controller restriction',
    () async {
      final f = _Fixture();
      await f.initialize();
      final response = Completer<Object?>(), entered = Completer<void>();
      f.transport.handler = () {
        entered.complete();
        return response.future;
      };
      final old = f.build().allowsOrdinary();
      await entered.future;
      f.transport.handler = null;
      f.transport.response = f.policy('blocked', 2);
      final current = f.build();
      expect(await current.allowsOrdinary(), isFalse);
      response.complete(f.policy('ordinary', 1));
      expect(await old, isFalse);
      expect(
        (jsonDecode(f.cache.values.single) as Map)['policy']['mode'],
        'blocked',
      );
      f.offline = true;
      expect(await current.allowsJob(_Row(f.context)), isFalse);
    },
  );

  test(
    'pending old write finishes before newer scoped write, never after it',
    () async {
      final f = _Fixture();
      await f.initialize();
      final entered = Completer<void>(), release = Completer<void>();
      var writes = 0;
      f.onWrite = (key, value) async {
        if (++writes == 1) {
          entered.complete();
          await release.future;
        }
        f.cache[key] = value;
      };
      final old = f.build().allowsOrdinary();
      await entered.future;
      f.transport.response = f.policy('blocked', 2);
      final current = f.build();
      final newer = current.allowsOrdinary();
      while (f.transport.calls < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);
      expect(await current.allowsJob(_Row(f.context)), isFalse);
      release.complete();
      expect(await old, isFalse);
      expect(await newer, isFalse);
      expect(writes, 2);
      expect(
        (jsonDecode(f.cache.values.single) as Map)['policy']['mode'],
        'blocked',
      );
    },
  );

  test(
    'scope and credential changes during writes cannot grant or cross cache keys',
    () async {
      final f = _Fixture();
      await f.initialize();
      final entered = Completer<void>(), release = Completer<void>();
      f.onWrite = (key, value) async {
        entered.complete();
        await release.future;
        f.cache[key] = value;
      };
      final old = f.build().allowsOrdinary();
      await entered.future;
      f.current = false;
      await f.secrets.write(
        DeviceSessionCredential(
          deviceId: f.context.deviceId!,
          sessionToken: 'rotated-synthetic-session',
        ),
      );
      release.complete();
      expect(await old, isFalse);
      f.current = true;
      f.offline = true;
      expect(await f.build().allowsOrdinary(), isFalse);
      final other = DeviceContext(
        organizationId: f.context.organizationId,
        restaurantId: f.context.restaurantId,
        branchId: '30000000-0000-4000-8000-999999999999',
        deviceId: f.context.deviceId,
      );
      expect(await f.build(scope: other).allowsOrdinary(), isFalse);
    },
  );
}
