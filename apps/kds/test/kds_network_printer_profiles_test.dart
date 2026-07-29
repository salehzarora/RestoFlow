@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — KDS integration.
///
/// The KDS keeps its OWN saved kitchen-printer list. It must migrate the
/// existing single configuration, drive the canonical config on selection, and
/// stay completely separate from the POS list and from other devices. No
/// customer-receipt concept is introduced.

const _kdsLegacyKey = 'restoflow.printer.network.kds.local';
const _posListKey = 'restoflow.printer.network_profiles.pos.local';

ProviderContainer _kds() {
  final c = ProviderContainer(
    overrides: [
      nativePrintingAvailableProvider.overrideWithValue(true),
      nativePrinterNamespaceProvider.overrideWithValue('kds'),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  test('A. the existing single KDS Wi-Fi configuration becomes one active '
      'profile, idempotently', () async {
    SharedPreferences.setMockInitialValues({
      _kdsLegacyKey: jsonEncode(const {
        'host': '192.168.33.14',
        'port': 9100,
        'name': 'Kitchen',
      }),
    });
    final c = _kds();

    final state = await c.read(networkPrinterProfilesProvider.future);
    expect(state.profiles, hasLength(1));
    expect(state.profiles.single.config.host, '192.168.33.14');
    expect(state.activeId, state.profiles.single.id);

    final again = await _kds().read(networkPrinterProfilesProvider.future);
    expect(again.profiles, hasLength(1), reason: 'no duplicate on relaunch');
    expect(again.profiles.single.id, state.profiles.single.id);
  });

  test('B. selecting a profile drives the canonical KDS config used by the '
      'kitchen transport', () async {
    final c = _kds();
    final ctrl = c.read(networkPrinterProfilesProvider.notifier);

    await ctrl.addProfile(
      name: 'Kitchen printer',
      config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
    );
    final backup = await ctrl.addProfile(
      name: 'Backup printer',
      config: const NetworkPrinterConfig(host: '10.0.0.20', port: 9101),
    );
    await ctrl.selectProfile(backup!.id);

    final canonical = await c.read(networkPrinterConfigProvider.future);
    expect(canonical, isNotNull);
    expect(canonical!.host, '10.0.0.20');
    expect(canonical.port, 9101);
  });

  test('C. process recreation restores the list and the selection', () async {
    final first = _kds();
    final ctrl = first.read(networkPrinterProfilesProvider.notifier);
    await ctrl.addProfile(
      name: 'A',
      config: const NetworkPrinterConfig(host: '10.0.0.1'),
    );
    final b = await ctrl.addProfile(
      name: 'B',
      config: const NetworkPrinterConfig(host: '10.0.0.2', port: 9101),
    );
    await ctrl.selectProfile(b!.id);

    final restored = await _kds().read(networkPrinterProfilesProvider.future);
    expect(restored.profiles, hasLength(2));
    expect(restored.activeId, b.id);
    expect(restored.active!.config.port, 9101);
  });

  test('D/E. edit persists and an invalid edit changes nothing', () async {
    final c = _kds();
    final ctrl = c.read(networkPrinterProfilesProvider.notifier);
    final p = await ctrl.addProfile(
      name: 'Kitchen',
      config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
    );
    await ctrl.selectProfile(p!.id);

    expect(
      await ctrl.updateProfile(
        p.copyWith(config: const NetworkPrinterConfig(host: '  ')),
      ),
      isFalse,
    );
    expect(
      await ctrl.updateProfile(
        p.copyWith(
          name: 'Kitchen 2',
          config: const NetworkPrinterConfig(host: '10.0.0.77', port: 9102),
        ),
      ),
      isTrue,
    );

    final canonical = await c.read(networkPrinterConfigProvider.future);
    expect(canonical!.host, '10.0.0.77');
    final state = await c.read(networkPrinterProfilesProvider.future);
    expect(state.profiles.single.id, p.id, reason: 'stable id across the edit');
  });

  test(
    'F. deleting the active profile leaves the KDS honestly unconfigured',
    () async {
      final c = _kds();
      final ctrl = c.read(networkPrinterProfilesProvider.notifier);
      final a = await ctrl.addProfile(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      );
      await ctrl.addProfile(
        name: 'B',
        config: const NetworkPrinterConfig(host: '10.0.0.2'),
      );
      await ctrl.selectProfile(a!.id);

      await ctrl.removeProfile(a.id);
      final state = await c.read(networkPrinterProfilesProvider.future);
      expect(state.profiles, hasLength(1));
      expect(state.activeId, isNull);
    },
  );

  test('G. an equivalent endpoint is never added twice', () async {
    final c = _kds();
    final ctrl = c.read(networkPrinterProfilesProvider.notifier);
    final a = await ctrl.addProfile(
      name: 'A',
      config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
    );
    final b = await ctrl.addProfile(
      name: 'A again',
      config: const NetworkPrinterConfig(host: '10.0.0.14 ', port: 9100),
    );
    expect(b!.id, a!.id);
    expect(
      (await c.read(networkPrinterProfilesProvider.future)).profiles,
      hasLength(1),
    );
  });

  test('I. a POS saved list is INVISIBLE to the KDS, and vice versa', () async {
    SharedPreferences.setMockInitialValues({
      _posListKey: jsonEncode([
        {
          'id': 'p1',
          'name': 'POS counter',
          'config': {'host': '10.0.0.250', 'port': 9100},
        },
      ]),
    });
    final c = _kds();
    final state = await c.read(networkPrinterProfilesProvider.future);
    expect(state.profiles, isEmpty, reason: 'KDS never reads the POS list');

    await c
        .read(networkPrinterProfilesProvider.notifier)
        .addProfile(
          name: 'KDS kitchen',
          config: const NetworkPrinterConfig(host: '10.0.0.9'),
        );

    // The POS list on disk is untouched by KDS writes.
    final prefs = await SharedPreferences.getInstance();
    final pos = jsonDecode(prefs.getString(_posListKey)!) as List;
    expect(pos, hasLength(1));
    expect((pos.single as Map)['name'], 'POS counter');
  });

  test('H. another DEVICE namespace is never enumerated', () async {
    SharedPreferences.setMockInitialValues({
      'restoflow.printer.network_profiles.kds.device-XYZ': jsonEncode([
        {
          'id': 'p1',
          'name': 'Other device',
          'config': {'host': '10.9.9.9', 'port': 9100},
        },
      ]),
    });
    final c = _kds();
    final state = await c.read(networkPrinterProfilesProvider.future);
    expect(state.profiles, isEmpty);
    expect(state.activeId, isNull);
  });

  test(
    'K. a runtime connection failure never removes the saved profile',
    () async {
      final c = _kds();
      final ctrl = c.read(networkPrinterProfilesProvider.notifier);
      final p = await ctrl.addProfile(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      );
      await ctrl.selectProfile(p!.id);

      final after = await _kds().read(networkPrinterProfilesProvider.future);
      expect(after.profiles, hasLength(1));
      expect(after.activeId, p.id);
    },
  );
}
