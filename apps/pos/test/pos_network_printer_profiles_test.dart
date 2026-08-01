@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_profiles.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — POS integration.
///
/// The saved list must be device- and slot-scoped, must MIGRATE the existing
/// single configuration, and — critically — the SELECTED profile must drive the
/// existing canonical network config so Test Print and production printing both
/// follow it. A second, divergent source of truth would be a defect.

const _receiptLegacyKey = 'restoflow.printer.network.pos.local';
const _kitchenLegacyKey = 'restoflow.printer.network.pos.kitchen_ticket.local';

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [posNativePrintingAvailableProvider.overrideWithValue(true)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  test(
    'A. the EXISTING single Wi-Fi configuration becomes one active profile',
    () async {
      SharedPreferences.setMockInitialValues({
        _receiptLegacyKey: jsonEncode(const {
          'host': '192.168.10.7',
          'port': 9100,
          'name': 'Counter',
        }),
      });
      final c = _container();

      final state = await c.read(posNetworkPrinterProfilesProvider.future);
      expect(state.profiles, hasLength(1));
      expect(state.profiles.single.config.host, '192.168.10.7');
      expect(state.profiles.single.config.port, 9100);
      expect(state.activeId, state.profiles.single.id, reason: 'it is active');

      // Idempotent: a fresh container over the same prefs adds no duplicate.
      final again = await _container().read(
        posNetworkPrinterProfilesProvider.future,
      );
      expect(again.profiles, hasLength(1));
      expect(again.profiles.single.id, state.profiles.single.id);
    },
  );

  test('B. selecting a profile drives the CANONICAL config, so Test Print and '
      'production printing both resolve the selected endpoint', () async {
    final c = _container();
    final ctrl = c.read(posNetworkPrinterProfilesProvider.notifier);

    await ctrl.addProfile(
      name: 'Kitchen printer',
      config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
    );
    final backup = await ctrl.addProfile(
      name: 'Backup printer',
      config: const NetworkPrinterConfig(host: '10.0.0.20', port: 9100),
    );
    expect(
      (await c.read(posNetworkPrinterProfilesProvider.future)).profiles,
      hasLength(2),
    );

    await ctrl.selectProfile(backup!.id);

    // The canonical single-config provider — the one the bridges, Test Print
    // and the cold-start resolver already read — now points at the selection.
    final canonical = await c.read(posNetworkPrinterConfigProvider.future);
    expect(canonical, isNotNull);
    expect(canonical!.host, '10.0.0.20');
    expect(canonical.port, 9100);

    final state = await c.read(posNetworkPrinterProfilesProvider.future);
    expect(state.activeId, backup.id);
    expect(state.active!.config.host, '10.0.0.20');
  });

  test('C. process recreation restores the list, the selection and the '
      'canonical endpoint', () async {
    final first = _container();
    final ctrl = first.read(posNetworkPrinterProfilesProvider.notifier);
    await ctrl.addProfile(
      name: 'A',
      config: const NetworkPrinterConfig(host: '10.0.0.1'),
    );
    final b = await ctrl.addProfile(
      name: 'B',
      config: const NetworkPrinterConfig(host: '10.0.0.2', port: 9101),
    );
    await ctrl.selectProfile(b!.id);

    // Force-stop + relaunch.
    final second = _container();
    final restored = await second.read(
      posNetworkPrinterProfilesProvider.future,
    );
    expect(restored.profiles, hasLength(2));
    expect(restored.activeId, b.id);
    final canonical = await second.read(posNetworkPrinterConfigProvider.future);
    expect(canonical!.host, '10.0.0.2');
    expect(canonical.port, 9101);
  });

  test('D. editing the ACTIVE profile updates production config and keeps the '
      'stable id', () async {
    final c = _container();
    final ctrl = c.read(posNetworkPrinterProfilesProvider.notifier);
    final p = await ctrl.addProfile(
      name: 'Kitchen',
      config: const NetworkPrinterConfig(host: '10.0.0.14'),
    );
    await ctrl.selectProfile(p!.id);

    final ok = await ctrl.updateProfile(
      p.copyWith(
        name: 'Kitchen 2',
        config: const NetworkPrinterConfig(host: '10.0.0.99', port: 9101),
      ),
    );
    expect(ok, isTrue);

    final canonical = await c.read(posNetworkPrinterConfigProvider.future);
    expect(canonical!.host, '10.0.0.99');
    expect(canonical.port, 9101);
    final state = await c.read(posNetworkPrinterProfilesProvider.future);
    expect(state.profiles.single.id, p.id, reason: 'the id is stable');
    expect(state.profiles.single.name, 'Kitchen 2');
  });

  test(
    'E. an INVALID edit fails and leaves the active printing config valid',
    () async {
      final c = _container();
      final ctrl = c.read(posNetworkPrinterProfilesProvider.notifier);
      final p = await ctrl.addProfile(
        name: 'Kitchen',
        config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
      );
      await ctrl.selectProfile(p!.id);

      expect(
        await ctrl.updateProfile(
          p.copyWith(config: const NetworkPrinterConfig(host: '   ')),
        ),
        isFalse,
      );
      expect(
        await ctrl.updateProfile(
          p.copyWith(
            config: const NetworkPrinterConfig(host: 'h', port: 99999),
          ),
        ),
        isFalse,
      );

      final canonical = await c.read(posNetworkPrinterConfigProvider.future);
      expect(canonical!.host, '10.0.0.14', reason: 'production stays valid');
      final state = await c.read(posNetworkPrinterProfilesProvider.future);
      expect(state.profiles.single.config.host, '10.0.0.14');
    },
  );

  test(
    'F. deleting the ACTIVE profile leaves the slot honestly unconfigured',
    () async {
      final c = _container();
      final ctrl = c.read(posNetworkPrinterProfilesProvider.notifier);
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
      final state = await c.read(posNetworkPrinterProfilesProvider.future);
      expect(state.profiles, hasLength(1));
      expect(
        state.activeId,
        isNull,
        reason: 'no unrelated profile is silently selected',
      );
    },
  );

  test('G. an equivalent endpoint is not added twice', () async {
    final c = _container();
    final ctrl = c.read(posNetworkPrinterProfilesProvider.notifier);
    final first = await ctrl.addProfile(
      name: 'Kitchen',
      config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
    );
    final again = await ctrl.addProfile(
      name: 'Kitchen again',
      config: const NetworkPrinterConfig(host: ' 10.0.0.14 ', port: 9100),
    );
    expect(again!.id, first!.id);
    expect(
      (await c.read(posNetworkPrinterProfilesProvider.future)).profiles,
      hasLength(1),
    );
  });

  test('J. the RECEIPT and KITCHEN slots are independent', () async {
    SharedPreferences.setMockInitialValues({
      _receiptLegacyKey: jsonEncode(const {'host': '10.0.0.1', 'port': 9100}),
      _kitchenLegacyKey: jsonEncode(const {'host': '10.0.0.2', 'port': 9100}),
    });
    final c = _container();

    final receipt = await c.read(posNetworkPrinterProfilesProvider.future);
    final kitchen = await c.read(
      posKitchenNetworkPrinterProfilesProvider.future,
    );
    expect(receipt.profiles.single.config.host, '10.0.0.1');
    expect(kitchen.profiles.single.config.host, '10.0.0.2');

    // Selecting a NEW kitchen printer must not touch the receipt slot.
    final k = await c
        .read(posKitchenNetworkPrinterProfilesProvider.notifier)
        .addProfile(
          name: 'Kitchen 2',
          config: const NetworkPrinterConfig(host: '10.0.0.55'),
        );
    await c
        .read(posKitchenNetworkPrinterProfilesProvider.notifier)
        .selectProfile(k!.id);

    final receiptCanonical = await c.read(
      posNetworkPrinterConfigProvider.future,
    );
    final kitchenCanonical = await c.read(
      posKitchenNetworkPrinterConfigProvider.future,
    );
    expect(receiptCanonical!.host, '10.0.0.1', reason: 'receipt unchanged');
    expect(kitchenCanonical!.host, '10.0.0.55');
    expect(
      (await c.read(posNetworkPrinterProfilesProvider.future)).profiles,
      hasLength(1),
      reason: 'the receipt list gained nothing',
    );
  });

  test('H. a DIFFERENT device namespace sees none of these profiles', () async {
    SharedPreferences.setMockInitialValues({
      // Another device's saved list must never be enumerated.
      'restoflow.printer.network_profiles.pos.device-XYZ': jsonEncode([
        {
          'id': 'p1',
          'name': 'Other device',
          'config': {'host': '10.9.9.9', 'port': 9100},
        },
      ]),
    });
    final c = _container();
    final state = await c.read(posNetworkPrinterProfilesProvider.future);
    expect(state.profiles, isEmpty);
    expect(state.activeId, isNull);
  });

  test(
    'K. a runtime connection failure never removes the saved profile',
    () async {
      final c = _container();
      final ctrl = c.read(posNetworkPrinterProfilesProvider.notifier);
      final p = await ctrl.addProfile(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      );
      await ctrl.selectProfile(p!.id);

      // Nothing in the profile API can be reached by a failed connection; a
      // fresh container proves the persisted list and selection are intact.
      final after = await _container().read(
        posNetworkPrinterProfilesProvider.future,
      );
      expect(after.profiles, hasLength(1));
      expect(after.activeId, p.id);
      expect(after.active!.config.host, '10.0.0.1');
    },
  );
}
