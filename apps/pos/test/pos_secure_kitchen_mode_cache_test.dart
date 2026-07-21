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
    int? modeRevision,
  }) => KitchenModeCacheRecord(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: branchId,
    deviceId: 'dev-1',
    sessionFingerprint: fingerprint,
    mode: mode,
    modeRevision: modeRevision,
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
      // Deterministic clock pinned to the record time: the CORRECTION-001
      // future-timestamp guard must never depend on the wall clock here.
      cache = PosSecureKitchenModeCache(
        storage: fake,
        platform: native,
        now: () => verifiedAt,
      );
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
      '001C3A: BOTH verified modes round-trip the server revision',
      () async {
        await cache.write(record(mode: 'kds', modeRevision: 7));
        expect((await readScoped(cache))!.modeRevision, 7);
        await cache.write(record(mode: 'printer_only', modeRevision: 4));
        expect((await readScoped(cache))!.modeRevision, 4);
        // Old records without a revision stay readable (normal KDS operation;
        // readiness-INELIGIBLE by the coordinator's rules, not the cache's).
        await cache.write(record(mode: 'kds'));
        expect(await readScoped(cache), isNotNull);
        expect((await readScoped(cache))!.modeRevision, isNull);
      },
    );

    test('001C3A: a stored NON-POSITIVE revision is corruption — invalidated, '
        'never clamped', () async {
      for (final bad in ['0', '-2', '"seven"']) {
        fake.values['restoflow.pos.kitchen_spool.mode_cache.v1'] =
            '{"v":1,"organization_id":"org-1","restaurant_id":"rest-1",'
            '"branch_id":"branch-1","device_id":"dev-1",'
            '"session_fingerprint":"fp-1","mode":"kds",'
            '"mode_revision":$bad,'
            '"verified_at":"2026-07-20T12:00:00.000Z"}';
        expect(
          await readScoped(cache),
          isNull,
          reason: 'mode_revision=$bad must invalidate',
        );
        expect(fake.values, isEmpty);
      }
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

  group(
    'CORRECTION-001: clock handling (future verifiedAt is never fresh)',
    () {
      KitchenModeCacheRecord at(DateTime t) => KitchenModeCacheRecord(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        deviceId: 'dev-1',
        sessionFingerprint: 'fp-1',
        mode: 'kds',
        verifiedAt: t,
      );

      test('exact-boundary freshness ladder', () {
        final now = DateTime.utc(2026, 7, 20, 12);
        // verifiedAt == now.
        expect(
          kitchenModeCacheFreshness(at(now), now),
          KitchenModeCacheFreshness.fresh,
        );
        // Slightly in the future WITHIN the deterministic tolerance (1 min).
        expect(
          kitchenModeCacheFreshness(
            at(now.add(const Duration(seconds: 30))),
            now,
          ),
          KitchenModeCacheFreshness.fresh,
        );
        expect(
          kitchenModeCacheFreshness(
            at(now.add(kKitchenModeCacheClockSkewTolerance)),
            now,
          ),
          KitchenModeCacheFreshness.fresh,
        );
        // Beyond tolerance: SUSPECT — expired, never fresh trust.
        expect(
          kitchenModeCacheFreshness(
            at(
              now.add(
                kKitchenModeCacheClockSkewTolerance +
                    const Duration(seconds: 1),
              ),
            ),
            now,
          ),
          KitchenModeCacheFreshness.expired,
        );
        expect(
          kitchenModeCacheFreshness(
            at(now.add(const Duration(days: 400))),
            now,
          ),
          KitchenModeCacheFreshness.expired,
        );
        // Exactly 10 minutes old -> still fresh; just over -> stale.
        expect(
          kitchenModeCacheFreshness(
            at(now.subtract(const Duration(minutes: 10))),
            now,
          ),
          KitchenModeCacheFreshness.fresh,
        );
        expect(
          kitchenModeCacheFreshness(
            at(now.subtract(const Duration(minutes: 10, seconds: 1))),
            now,
          ),
          KitchenModeCacheFreshness.stale,
        );
        // Exactly 2 hours -> stale; just over -> expired.
        expect(
          kitchenModeCacheFreshness(
            at(now.subtract(const Duration(hours: 2))),
            now,
          ),
          KitchenModeCacheFreshness.stale,
        );
        expect(
          kitchenModeCacheFreshness(
            at(now.subtract(const Duration(hours: 2, seconds: 1))),
            now,
          ),
          KitchenModeCacheFreshness.expired,
        );
      });

      test('read() INVALIDATES a record verified beyond the future tolerance '
          '(suspect record: deleted like corruption, never trusted)', () async {
        final fixedNow = DateTime.utc(2026, 7, 20, 12);
        final fake = _FakeSecureStorage();
        final cache = PosSecureKitchenModeCache(
          storage: fake,
          platform: native,
          now: () => fixedNow,
        );
        await cache.write(at(fixedNow.add(const Duration(minutes: 5))));
        expect(await readScoped(cache), isNull);
        expect(fake.values, isEmpty, reason: 'suspect record deleted');
      });

      test(
        'read() tolerates a future verifiedAt WITHIN the tolerance',
        () async {
          final fixedNow = DateTime.utc(2026, 7, 20, 12);
          final fake = _FakeSecureStorage();
          final cache = PosSecureKitchenModeCache(
            storage: fake,
            platform: native,
            now: () => fixedNow,
          );
          await cache.write(at(fixedNow.add(const Duration(seconds: 30))));
          final record = await readScoped(cache);
          expect(record, isNotNull);
          // Even so, freshness treats it as no fresher than NOW-equivalent.
          expect(
            kitchenModeCacheFreshness(record!, fixedNow),
            KitchenModeCacheFreshness.fresh,
          );
        },
      );
    },
  );
}
