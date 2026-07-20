import 'dart:convert' show json;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';
import 'package:restoflow_pos/src/spool/pos_secure_kitchen_mode_cache.dart';

/// Recording fake of the secure-storage plugin (no channels; deterministic).
class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> values = {};
  int readCalls = 0;
  int writeCalls = 0;
  int deleteCalls = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readCalls++;
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writeCalls++;
    values[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deleteCalls++;
    values.remove(key);
  }
}

void main() {
  const native = PosKitchenSpoolPlatform(isWeb: false);
  const web = PosKitchenSpoolPlatform(isWeb: true);
  final verifiedAt = DateTime.utc(2026, 7, 20, 12);

  KitchenModeCacheRecord record({
    String branchId = 'branch-1',
    String fingerprint = 'fp-1',
    String mode = 'kds',
  }) => KitchenModeCacheRecord(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: branchId,
    deviceId: 'dev-1',
    sessionFingerprint: fingerprint,
    mode: mode,
    verifiedAt: verifiedAt,
  );

  Future<KitchenModeCacheRecord?> readScoped(
    PosSecureKitchenModeCache cache, {
    String branchId = 'branch-1',
    String fingerprint = 'fp-1',
  }) => cache.read(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: branchId,
    deviceId: 'dev-1',
    sessionFingerprint: fingerprint,
  );

  group('PosSecureKitchenModeCache — native', () {
    late _FakeSecureStorage fake;
    late PosSecureKitchenModeCache cache;

    setUp(() {
      fake = _FakeSecureStorage();
      cache = PosSecureKitchenModeCache(storage: fake, platform: native);
    });

    test('write/read round-trips under the kitchen-spool namespace', () async {
      await cache.write(record(mode: 'printer_only'));
      expect(
        fake.values.keys.single,
        'restoflow.pos.kitchen_spool.mode_cache.v1',
      );
      final back = await readScoped(cache);
      expect(back, isNotNull);
      expect(back!.mode, 'printer_only');
      expect(back.modeRevision, isNull); // D1: no trusted revision yet.
      expect(back.verifiedAt, verifiedAt);
      expect(back.sessionFingerprint, 'fp-1');
    });

    test(
      'scope-tuple mismatch INVALIDATES (deletes) and returns null',
      () async {
        await cache.write(record());
        final back = await readScoped(cache, branchId: 'branch-OTHER');
        expect(back, isNull);
        expect(fake.values, isEmpty, reason: 'mismatch must delete the record');
        // The record is gone even for the original scope now (fail closed).
        expect(await readScoped(cache), isNull);
      },
    );

    test('session-fingerprint mismatch INVALIDATES and returns null', () async {
      await cache.write(record());
      expect(await readScoped(cache, fingerprint: 'fp-ROTATED'), isNull);
      expect(fake.values, isEmpty);
    });

    test('malformed stored JSON invalidates and reads as UNKNOWN', () async {
      fake.values[PosSecureKitchenModeCache.storageKey] = '{not json';
      expect(await readScoped(cache), isNull);
      expect(fake.values, isEmpty);
    });

    test('unknown schema version invalidates (no forward-guessing)', () async {
      await cache.write(record());
      final raw =
          json.decode(fake.values[PosSecureKitchenModeCache.storageKey]!)
              as Map<String, dynamic>;
      raw['v'] = 99;
      fake.values[PosSecureKitchenModeCache.storageKey] = json.encode(raw);
      expect(await readScoped(cache), isNull);
      expect(fake.values, isEmpty);
    });

    test('a mode outside {kds, printer_only} invalidates', () async {
      await cache.write(record());
      final raw =
          json.decode(fake.values[PosSecureKitchenModeCache.storageKey]!)
              as Map<String, dynamic>;
      raw['mode'] = 'plaintext_fallback';
      fake.values[PosSecureKitchenModeCache.storageKey] = json.encode(raw);
      expect(await readScoped(cache), isNull);
      expect(fake.values, isEmpty);
    });

    test('invalidate() deletes the record', () async {
      await cache.write(record());
      await cache.invalidate();
      expect(fake.values, isEmpty);
      expect(await readScoped(cache), isNull);
    });

    test('freshness ladder: fresh <=10min, stale <=2h, expired beyond', () {
      final r = record();
      expect(
        kitchenModeCacheFreshness(
          r,
          verifiedAt.add(const Duration(minutes: 9)),
        ),
        KitchenModeCacheFreshness.fresh,
      );
      expect(
        kitchenModeCacheFreshness(
          r,
          verifiedAt.add(const Duration(minutes: 10)),
        ),
        KitchenModeCacheFreshness.fresh,
      );
      expect(
        kitchenModeCacheFreshness(
          r,
          verifiedAt.add(const Duration(minutes: 11)),
        ),
        KitchenModeCacheFreshness.stale,
      );
      expect(
        kitchenModeCacheFreshness(r, verifiedAt.add(const Duration(hours: 2))),
        KitchenModeCacheFreshness.stale,
      );
      expect(
        kitchenModeCacheFreshness(
          r,
          verifiedAt.add(const Duration(hours: 2, seconds: 1)),
        ),
        KitchenModeCacheFreshness.expired,
      );
    });
  });

  group('PosSecureKitchenModeCache — web fails closed', () {
    late _FakeSecureStorage fake;
    late PosSecureKitchenModeCache cache;

    setUp(() {
      fake = _FakeSecureStorage();
      cache = PosSecureKitchenModeCache(storage: fake, platform: web);
    });

    test('write throws unavailable and NEVER touches storage', () async {
      await expectLater(
        cache.write(record()),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
      expect(fake.writeCalls, 0);
      expect(fake.values, isEmpty);
    });

    test('read returns null (UNKNOWN) without touching storage', () async {
      expect(await readScoped(cache), isNull);
      expect(fake.readCalls, 0);
    });
  });
}
