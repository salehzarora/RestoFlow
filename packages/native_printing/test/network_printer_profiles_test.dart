import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — the shared saved-profile store.
///
/// Today each device stores exactly ONE network printer configuration per slot
/// (`restoflow.printer.network.<ns>.<slot><deviceSegment>`). The user needs a
/// SAVED LIST they can add to, select, edit and delete, still device-local and
/// still separate per app and per printer slot.
///
/// These drive the real prefs-backed store, not a helper in isolation.

const _listKey = 'restoflow.printer.network_profiles.pos.dev-1';
const _activeKey = 'restoflow.printer.network_profile_active.pos.dev-1';
const _legacyKey = 'restoflow.printer.network.pos.dev-1';

Future<NetworkPrinterProfileStore> _store({
  String listKey = _listKey,
  String activeKey = _activeKey,
  String legacyKey = _legacyKey,
}) async => NetworkPrinterProfileStore(
  prefs: await SharedPreferences.getInstance(),
  listKey: listKey,
  activeKey: activeKey,
  legacyConfigKey: legacyKey,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('A. migration of the existing single configuration', () {
    test('an existing saved config becomes ONE active profile, preserving '
        'host/port/name/options', () async {
      SharedPreferences.setMockInitialValues({
        _legacyKey: jsonEncode(const {
          'host': '192.168.10.7',
          'port': 9100,
          'name': 'Counter',
          'mediaProfile': 'label80x80',
        }),
      });
      final store = await _store();

      final profiles = await store.list();
      expect(profiles, hasLength(1), reason: 'exactly one migrated profile');
      final p = profiles.single;
      expect(p.config.host, '192.168.10.7');
      expect(p.config.port, 9100);
      expect(p.name, 'Counter');
      expect(p.config.mediaProfileId, 'label80x80');
      expect(p.id, isNotEmpty, reason: 'a stable id, never the list index');
      expect(await store.activeProfileId(), p.id, reason: 'it becomes active');
    });

    test('re-running migration NEVER creates a duplicate', () async {
      SharedPreferences.setMockInitialValues({
        _legacyKey: jsonEncode(const {'host': '10.0.0.5', 'port': 9100}),
      });
      final first = await _store();
      final a = await first.list();
      // A brand-new store over the SAME prefs — i.e. process recreation.
      final second = await _store();
      final b = await second.list();

      expect(a, hasLength(1));
      expect(b, hasLength(1), reason: 'migration is idempotent');
      expect(b.single.id, a.single.id, reason: 'the stable id survives');
    });

    test('the legacy key is KEPT, never erased by migration', () async {
      SharedPreferences.setMockInitialValues({
        _legacyKey: jsonEncode(const {'host': '10.0.0.5', 'port': 9100}),
      });
      final store = await _store();
      await store.list();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyKey), isNotNull);
    });

    test('an INVALID legacy config migrates nothing', () async {
      SharedPreferences.setMockInitialValues({
        _legacyKey: jsonEncode(const {'host': '   ', 'port': 9100}),
      });
      final store = await _store();
      expect(await store.list(), isEmpty);
      expect(await store.activeProfileId(), isNull);
    });
  });

  group('B/D/F. add, select, edit, remove', () {
    test(
      'two profiles persist; selecting the second makes it active',
      () async {
        final store = await _store();
        final kitchen = await store.add(
          name: 'Kitchen printer',
          config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
        );
        final backup = await store.add(
          name: 'Backup printer',
          config: const NetworkPrinterConfig(host: '10.0.0.20', port: 9100),
        );

        expect(await store.list(), hasLength(2));
        await store.setActiveProfileId(backup!.id);
        expect(await store.activeProfileId(), backup.id);
        expect(
          (await store.get(backup.id))!.config.host,
          '10.0.0.20',
          reason: 'the active endpoint is the selected profile',
        );
        expect(kitchen, isNotNull);
      },
    );

    test('D. editing preserves the stable id and persists', () async {
      final store = await _store();
      final p = (await store.add(
        name: 'Kitchen',
        config: const NetworkPrinterConfig(host: '10.0.0.14'),
      ))!;
      await store.setActiveProfileId(p.id);

      final ok = await store.update(
        p.copyWith(
          name: 'Kitchen 2',
          config: const NetworkPrinterConfig(host: '10.0.0.99', port: 9101),
        ),
      );
      expect(ok, isTrue);

      final reloaded = await (await _store()).get(p.id);
      expect(reloaded!.id, p.id, reason: 'the id is stable across an edit');
      expect(reloaded.name, 'Kitchen 2');
      expect(reloaded.config.host, '10.0.0.99');
      expect(reloaded.config.port, 9101);
    });

    test(
      'E. an INVALID edit fails honestly and leaves the profile intact',
      () async {
        final store = await _store();
        final p = (await store.add(
          name: 'Kitchen',
          config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
        ))!;

        final blankHost = await store.update(
          p.copyWith(config: const NetworkPrinterConfig(host: '  ')),
        );
        final badPort = await store.update(
          p.copyWith(
            config: const NetworkPrinterConfig(host: 'x', port: 70000),
          ),
        );
        expect(blankHost, isFalse);
        expect(badPort, isFalse);

        final reloaded = await (await _store()).get(p.id);
        expect(reloaded!.config.host, '10.0.0.14');
        expect(reloaded.config.port, 9100);
      },
    );

    test('an invalid ADD is refused and stores nothing', () async {
      final store = await _store();
      expect(
        await store.add(
          name: 'x',
          config: const NetworkPrinterConfig(host: ''),
        ),
        isNull,
      );
      expect(
        await store.add(
          name: 'x',
          config: const NetworkPrinterConfig(host: 'h', port: 0),
        ),
        isNull,
      );
      expect(await store.list(), isEmpty);
    });

    test(
      'F. removing an INACTIVE profile leaves the active one alone',
      () async {
        final store = await _store();
        final a = (await store.add(
          name: 'A',
          config: const NetworkPrinterConfig(host: '10.0.0.1'),
        ))!;
        final b = (await store.add(
          name: 'B',
          config: const NetworkPrinterConfig(host: '10.0.0.2'),
        ))!;
        await store.setActiveProfileId(a.id);

        await store.remove(b.id);
        expect(await store.list(), hasLength(1));
        expect(await store.activeProfileId(), a.id);
      },
    );

    test('F. removing the ACTIVE profile leaves the slot honestly '
        'unconfigured — never a silent unrelated selection', () async {
      final store = await _store();
      final a = (await store.add(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      ))!;
      await store.add(
        name: 'B',
        config: const NetworkPrinterConfig(host: '10.0.0.2'),
      );
      await store.setActiveProfileId(a.id);

      await store.remove(a.id);
      expect(
        await store.activeProfileId(),
        isNull,
        reason: 'no unrelated profile is silently promoted',
      );
      // ...and the deletion survives a reload.
      expect(await (await _store()).get(a.id), isNull);
    });
  });

  group('G. duplicate prevention', () {
    test('the same normalized host+port is not added twice', () async {
      final store = await _store();
      final first = await store.add(
        name: 'Kitchen',
        config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
      );
      final again = await store.add(
        name: 'Kitchen again',
        config: const NetworkPrinterConfig(host: ' 10.0.0.14 ', port: 9100),
      );

      expect(await store.list(), hasLength(1), reason: 'one logical profile');
      expect(
        again!.id,
        first!.id,
        reason: 'the existing profile is returned, not a duplicate',
      );
      // ...and no duplicate appears after a reload.
      expect(await (await _store()).list(), hasLength(1));
    });

    test('host case is normalized for equality', () async {
      final store = await _store();
      await store.add(
        name: 'A',
        config: const NetworkPrinterConfig(host: 'Printer.Local', port: 9100),
      );
      await store.add(
        name: 'B',
        config: const NetworkPrinterConfig(host: 'printer.local', port: 9100),
      );
      expect(await store.list(), hasLength(1));
    });

    test('the same host on a DIFFERENT port is a distinct profile', () async {
      final store = await _store();
      await store.add(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9100),
      );
      await store.add(
        name: 'B',
        config: const NetworkPrinterConfig(host: '10.0.0.14', port: 9101),
      );
      expect(await store.list(), hasLength(2));
    });
  });

  group('stable ids are never REUSED after a deletion', () {
    test('a deleted id is not handed to the next profile', () async {
      final store = await _store();
      final a = (await store.add(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      ))!;
      final b = (await store.add(
        name: 'B',
        config: const NetworkPrinterConfig(host: '10.0.0.2'),
      ))!;
      await store.remove(b.id);

      final c = (await store.add(
        name: 'C',
        config: const NetworkPrinterConfig(host: '10.0.0.3'),
      ))!;
      expect(
        c.id,
        isNot(b.id),
        reason:
            'reusing a deleted id would let a stale reference edit or '
            'select a DIFFERENT printer',
      );
      expect(c.id, isNot(a.id));
      // ...and the counter survives process recreation.
      final fresh = await _store();
      final d = (await fresh.add(
        name: 'D',
        config: const NetworkPrinterConfig(host: '10.0.0.4'),
      ))!;
      expect({a.id, b.id, c.id}.contains(d.id), isFalse);
    });
  });

  group('C. process recreation', () {
    test('the list and the active selection both restore', () async {
      final store = await _store();
      await store.add(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      );
      final b = (await store.add(
        name: 'B',
        config: const NetworkPrinterConfig(host: '10.0.0.2', port: 9101),
      ))!;
      await store.setActiveProfileId(b.id);

      final fresh = await _store();
      expect(await fresh.list(), hasLength(2));
      expect(await fresh.activeProfileId(), b.id);
      final active = await fresh.get(b.id);
      expect(active!.config.host, '10.0.0.2');
      expect(active.config.port, 9101);
    });
  });

  group('H/I/J. namespace isolation', () {
    test('H. another DEVICE namespace sees none of these profiles', () async {
      final deviceA = await _store();
      await deviceA.add(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      );

      final deviceB = await _store(
        listKey: 'restoflow.printer.network_profiles.pos.dev-2',
        activeKey: 'restoflow.printer.network_profile_active.pos.dev-2',
        legacyKey: 'restoflow.printer.network.pos.dev-2',
      );
      expect(await deviceB.list(), isEmpty);
      expect(await deviceB.activeProfileId(), isNull);
    });

    test('I. the KDS namespace is unaffected by POS profiles', () async {
      final pos = await _store();
      await pos.add(
        name: 'POS',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      );

      final kds = await _store(
        listKey: 'restoflow.printer.network_profiles.kds.dev-1',
        activeKey: 'restoflow.printer.network_profile_active.kds.dev-1',
        legacyKey: 'restoflow.printer.network.kds.dev-1',
      );
      expect(await kds.list(), isEmpty);

      await kds.add(
        name: 'KDS',
        config: const NetworkPrinterConfig(host: '10.0.0.9'),
      );
      expect(await pos.list(), hasLength(1), reason: 'POS list is unchanged');
      expect((await pos.list()).single.name, 'POS');
    });

    test('J. a different SLOT on the same device is independent', () async {
      final receipt = await _store();
      await receipt.add(
        name: 'Receipt',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      );

      final kitchen = await _store(
        listKey: 'restoflow.printer.network_profiles.pos.kitchen_ticket.dev-1',
        activeKey:
            'restoflow.printer.network_profile_active.pos.kitchen_ticket.dev-1',
        legacyKey: 'restoflow.printer.network.pos.kitchen_ticket.dev-1',
      );
      expect(await kitchen.list(), isEmpty);

      final k = (await kitchen.add(
        name: 'Kitchen',
        config: const NetworkPrinterConfig(host: '10.0.0.2'),
      ))!;
      await kitchen.setActiveProfileId(k.id);

      expect(await receipt.list(), hasLength(1));
      expect(
        await receipt.activeProfileId(),
        isNot(k.id),
        reason: 'selecting a kitchen profile never changes the receipt slot',
      );
    });
  });

  group('ordering + corruption', () {
    test(
      'a corrupt stored list degrades to empty instead of crashing',
      () async {
        SharedPreferences.setMockInitialValues({_listKey: 'not json at all'});
        final store = await _store();
        expect(await store.list(), isEmpty);
        // ...and the store is still usable.
        expect(
          await store.add(
            name: 'A',
            config: const NetworkPrinterConfig(host: '10.0.0.1'),
          ),
          isNotNull,
        );
      },
    );

    test('ordering is deterministic and NOT rewritten on every read', () async {
      final store = await _store();
      await store.add(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      );
      await store.add(
        name: 'B',
        config: const NetworkPrinterConfig(host: '10.0.0.2'),
      );
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_listKey);

      final ids = [for (final p in await store.list()) p.id];
      expect([for (final p in await store.list()) p.id], ids);
      expect(
        prefs.getString(_listKey),
        raw,
        reason: 'reading the list never rewrites persisted ordering',
      );
    });
  });

  group('K. runtime failure never touches persistence', () {
    test('the store holds no connection state and keeps the profile', () async {
      final store = await _store();
      final p = (await store.add(
        name: 'A',
        config: const NetworkPrinterConfig(host: '10.0.0.1'),
      ))!;
      await store.setActiveProfileId(p.id);

      // A runtime connection failure is not a store operation at all: there is
      // no API here that could clear a profile, and a reload proves it.
      final fresh = await _store();
      expect(await fresh.list(), hasLength(1));
      expect(await fresh.activeProfileId(), p.id);
      final json = jsonDecode(
        (await SharedPreferences.getInstance()).getString(_listKey)!,
      );
      final stored = (json as List).single as Map<String, Object?>;
      for (final banned in const [
        'connected',
        'status',
        'socket',
        'stream',
        'error',
        'online',
      ]) {
        expect(
          stored.containsKey(banned),
          isFalse,
          reason: 'never persist $banned',
        );
      }
    });
  });
}
