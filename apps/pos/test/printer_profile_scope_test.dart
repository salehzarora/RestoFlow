import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_pos/src/state/pos_bluetooth_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRINT-STARTUP-REPRINT-001 (Defect 3) — device-scoped printer profiles must
/// survive a cold process start.
///
/// Root cause pinned here: the preference key segment used to be chosen from
/// `posDeviceContextProvider` AT CALL TIME, and its `null` is ambiguous — demo,
/// unpaired, *or restore still pending*. The pairing gate publishes the real
/// device one frame later, so a cold paired start read/wrote the legacy `local`
/// namespace and the saved Wi-Fi profile looked lost.
///
/// The fix is an authoritative three-state scope (unresolved / device / local).
/// These tests drive the REAL providers over a REAL SharedPreferences mock and
/// recreate the ProviderContainer to simulate process death.

const _deviceA = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'device-A',
  deviceType: 'pos',
  displayName: 'Till A',
);

const _profileKeyA =
    '${kPosNetworkPrinterKeyPrefix}${''}device-A'; // customerReceipt slot
const _profileKeyLocal = '${kPosNetworkPrinterKeyPrefix}${''}local';
const _profileKeyOtherDevice = '${kPosNetworkPrinterKeyPrefix}${''}device-B';

String _json(String host, int port) =>
    jsonEncode(PosNetworkPrinterConfig(host: host, port: port).toJson());

/// A container whose device context is already published (a paired station).
ProviderContainer _pairedContainer() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(posDeviceContextProvider.notifier).set(_deviceA);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('authoritative printer scope', () {
    test('demo / unpaired resolves IMMEDIATELY to local (never hangs)', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final scope = c.read(posPrinterScopeProvider);
      expect(scope.resolved, isTrue);
      expect(scope.isDevice, isFalse);
      expect(scope.keySegment, kPosPrinterScopeLocalKey);

      // And a load completes rather than waiting for a device that never comes.
      await expectLater(
        c.read(posPrinterScopeSegmentProvider.future),
        completion(kPosPrinterScopeLocalKey),
      );
    });

    test('a pending restore is UNRESOLVED — a transient null is NOT local', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(posDeviceRestorePendingProvider.notifier).begin();

      final scope = c.read(posPrinterScopeProvider);
      expect(scope.resolved, isFalse, reason: 'restore is still in flight');
      expect(scope.keySegment, isNull);
    });

    test('publishing the device resolves to that device namespace', () {
      final c = _pairedContainer();
      final scope = c.read(posPrinterScopeProvider);
      expect(scope.isDevice, isTrue);
      expect(scope.keySegment, 'device-A');
    });

    test('publishing a null result ends the restore and resolves to local', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(posDeviceRestorePendingProvider.notifier).begin();
      expect(c.read(posPrinterScopeProvider).resolved, isFalse);

      c.read(posDeviceContextProvider.notifier).set(null); // restore found none
      expect(c.read(posPrinterScopeProvider).resolved, isTrue);
      expect(
        c.read(posPrinterScopeProvider).keySegment,
        kPosPrinterScopeLocalKey,
      );
    });
  });

  group('cold paired startup', () {
    test('does NOT resolve from local while the restore is pending, then '
        'returns the real device profile', () async {
      SharedPreferences.setMockInitialValues({
        _profileKeyA: _json('10.0.0.50', 9100),
        _profileKeyLocal: _json('192.0.2.9', 9100), // a stale local leftover
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(posDeviceRestorePendingProvider.notifier).begin();

      // While unresolved the provider must stay loading — never the local value.
      final sub = c.listen(posNetworkPrinterConfigProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(
        sub.read().hasValue,
        isFalse,
        reason: 'must not latch the legacy local profile during restore',
      );

      // The gate publishes the restored device.
      c.read(posDeviceContextProvider.notifier).set(_deviceA);
      final resolved = await c.read(posNetworkPrinterConfigProvider.future);
      expect(resolved?.host, '10.0.0.50');
    });

    test(
      'profile saved under the device namespace survives process death',
      () async {
        final c1 = _pairedContainer();
        await c1.read(posNetworkPrinterConfigProvider.future);
        await c1
            .read(posNetworkPrinterConfigProvider.notifier)
            .save(const PosNetworkPrinterConfig(host: '10.0.0.77', port: 9100));

        // Process death: a brand-new container over the SAME prefs store.
        final c2 = _pairedContainer();
        final restored = await c2.read(posNetworkPrinterConfigProvider.future);
        expect(restored?.host, '10.0.0.77');
      },
    );
  });

  group('legacy local adoption (same installation only)', () {
    test('adopts the legacy local profile ONCE into the device namespace, '
        'keeps the source, and survives recreation', () async {
      SharedPreferences.setMockInitialValues({
        _profileKeyLocal: _json('10.0.0.31', 9100),
      });
      final c1 = _pairedContainer();
      final adopted = await c1.read(posNetworkPrinterConfigProvider.future);
      expect(adopted?.host, '10.0.0.31', reason: 'legacy profile is served');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(_profileKeyA),
        isNotNull,
        reason: 'adopted into the CURRENT device namespace',
      );
      expect(
        prefs.getString(_profileKeyLocal),
        isNotNull,
        reason: 'source is kept — a half-finished migration must not lose it',
      );

      // A later cold start reads the device-scoped copy.
      final c2 = _pairedContainer();
      expect(
        (await c2.read(posNetworkPrinterConfigProvider.future))?.host,
        '10.0.0.31',
      );
    });

    test('NEVER adopts a profile from another device id', () async {
      SharedPreferences.setMockInitialValues({
        _profileKeyOtherDevice: _json('10.9.9.9', 9100),
      });
      final c = _pairedContainer();
      expect(
        await c.read(posNetworkPrinterConfigProvider.future),
        isNull,
        reason: 'no device -> local -> other-device chain may exist',
      );
    });
  });

  group('save contract', () {
    test(
      'a save issued during startup lands ONLY in the resolved namespace',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        c.read(posDeviceRestorePendingProvider.notifier).begin();

        // Save while the scope is still unresolved: it must WAIT, not write local.
        final saving = c
            .read(posNetworkPrinterConfigProvider.notifier)
            .save(const PosNetworkPrinterConfig(host: '10.0.0.44', port: 9100));
        await Future<void>.delayed(Duration.zero);
        final prefsMid = await SharedPreferences.getInstance();
        expect(
          prefsMid.getString(_profileKeyLocal),
          isNull,
          reason: 'no accidental local write during startup',
        );

        c.read(posDeviceContextProvider.notifier).set(_deviceA);
        await saving;

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_profileKeyA), isNotNull);
        expect(prefs.getString(_profileKeyLocal), isNull);
      },
    );

    test(
      'an INVALID save preserves the last valid persisted profile',
      () async {
        final c = _pairedContainer();
        await c
            .read(posNetworkPrinterConfigProvider.notifier)
            .save(const PosNetworkPrinterConfig(host: '10.0.0.5', port: 9100));

        // Invalid host + invalid port must not overwrite anything.
        await c
            .read(posNetworkPrinterConfigProvider.notifier)
            .save(const PosNetworkPrinterConfig(host: '   ', port: 0));

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_profileKeyA), contains('10.0.0.5'));
        expect(
          (await c.read(posNetworkPrinterConfigProvider.future))?.host,
          '10.0.0.5',
        );
      },
    );

    test('explicit edit persists; explicit removal clears', () async {
      final c1 = _pairedContainer();
      await c1
          .read(posNetworkPrinterConfigProvider.notifier)
          .save(const PosNetworkPrinterConfig(host: '10.0.0.5', port: 9100));
      await c1
          .read(posNetworkPrinterConfigProvider.notifier)
          .save(const PosNetworkPrinterConfig(host: '10.0.0.6', port: 9100));
      expect(
        (await _pairedContainer().read(
          posNetworkPrinterConfigProvider.future,
        ))?.host,
        '10.0.0.6',
      );

      await c1.read(posNetworkPrinterConfigProvider.notifier).clear();
      expect(
        await _pairedContainer().read(posNetworkPrinterConfigProvider.future),
        isNull,
      );
    });
  });

  group('isolation', () {
    test('Wi-Fi and Bluetooth profiles are independent', () async {
      final c = _pairedContainer();
      await c
          .read(posNetworkPrinterConfigProvider.notifier)
          .save(const PosNetworkPrinterConfig(host: '10.0.0.5', port: 9100));
      await c
          .read(posBluetoothPrinterConfigProvider.notifier)
          .save(const PosBluetoothPrinterConfig(address: 'AA:BB:CC:DD:EE:FF'));

      // Removing the Wi-Fi profile leaves Bluetooth untouched.
      await c.read(posNetworkPrinterConfigProvider.notifier).clear();
      final c2 = _pairedContainer();
      expect(await c2.read(posNetworkPrinterConfigProvider.future), isNull);
      expect(
        (await c2.read(posBluetoothPrinterConfigProvider.future))?.address,
        'AA:BB:CC:DD:EE:FF',
      );
    });

    test('customer-receipt and kitchen slots stay separate', () async {
      final c = _pairedContainer();
      await c
          .read(posNetworkPrinterConfigProvider.notifier)
          .save(const PosNetworkPrinterConfig(host: '10.0.0.5', port: 9100));
      expect(
        await c.read(posKitchenNetworkPrinterConfigProvider.future),
        isNull,
      );
    });
  });

  group('selected transport shares the authoritative namespace', () {
    test(
      'cold paired startup reads the device-scoped selection, not local',
      () async {
        SharedPreferences.setMockInitialValues({
          '${kPosPrinterTransportKeyPrefix}device-A': 'bluetooth',
          '${kPosPrinterTransportKeyPrefix}local': 'network',
        });
        final c = _pairedContainer();
        expect(
          await c.read(posSelectedPrinterTransportProvider.future),
          PosPrinterTransportKind.bluetooth,
        );
      },
    );
  });
}
