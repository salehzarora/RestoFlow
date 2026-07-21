@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show KitchenSpoolCountState;
import 'package:restoflow_pos/src/spool/flutter_secure_kitchen_spool_key_store.dart';
import 'package:restoflow_pos/src/spool/kitchen_spool_readiness_probe.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';

/// KITCHEN-MODE-001C3A — the NON-MUTATING spool capability probe against a
/// REAL on-disk factory + the real key store: absent state never grows a
/// footprint; existing state is counted and closed; corruption is a typed
/// safe blocker, never destructively recovered.
class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

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
  }) async => values[key] = value!;

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(values);
}

void main() {
  late Directory tempDir;
  late _FakeSecureStorage storage;

  const nativePlatform = PosKitchenSpoolPlatform(isWeb: false);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rf_probe_test');
    storage = _FakeSecureStorage();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  KitchenSpoolDatabaseFactory factory() => KitchenSpoolDatabaseFactory(
    documentsDirectoryProvider: () async => tempDir,
  );

  KitchenSpoolKeyManager keyManager() => KitchenSpoolKeyManager(
    FlutterSecureKitchenSpoolKeyStore(
      storage: storage,
      platform: nativePlatform,
    ),
  );

  KitchenSpoolReadinessProbe probe({PosKitchenSpoolPlatform? platform}) =>
      KitchenSpoolReadinessProbe(
        platform: platform ?? nativePlatform,
        databaseFactoryBuilder: factory,
        keyManagerBuilder: keyManager,
      );

  Future<KitchenSpoolJobRow> seedJob(
    DriftKitchenSpoolStore store, {
    required String deviceId,
    required String branchId,
    String dispatchId = 'disp-1',
  }) => store.insertImportedJob(
    NewKitchenSpoolJob(
      localJobId: 'probe-$dispatchId',
      dispatchId: dispatchId,
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: branchId,
      deviceId: deviceId,
      orderId: 'order-1',
      serviceRoundId: null,
      dispatchType: KitchenSpoolDispatchType.initialOrder,
      initialStatus: KitchenSpoolJobStatus.imported,
      encryptedPayloadBlob: Uint8List.fromList(const [1, 2, 3]),
      encryptionVersion: 1,
      destinationFingerprint: 'ab' * 32,
      destinationDisplayLabel: 'Kitchen',
      transportKind: 'network',
      paperWidth: '80mm',
      payloadVersion: 1,
      documentVersion: 1,
      rasterVersion: 1,
      createdAt: DateTime.utc(2026, 7, 21, 10),
    ),
  );

  test('web fails closed WITHOUT touching factory or key store', () async {
    var touched = false;
    final result = await KitchenSpoolReadinessProbe(
      platform: const PosKitchenSpoolPlatform(isWeb: true),
      databaseFactoryBuilder: () {
        touched = true;
        return factory();
      },
      keyManagerBuilder: () {
        touched = true;
        return keyManager();
      },
    ).probe(deviceId: 'dev-1', branchId: 'branch-1');
    expect(result.secureSpoolAvailable, isFalse);
    expect(result.unresolvedLocalJobs, 0);
    expect(result.spoolCountState, KitchenSpoolCountState.unknown);
    expect(result.blockerCode, 'web_unsupported');
    expect(touched, isFalse);
  });

  test('absent DB + absent key: plain false/0, NO footprint created, no '
      'blocker (a fresh device is simply not provisioned yet)', () async {
    final result = await probe().probe(deviceId: 'dev-1', branchId: 'branch-1');
    expect(result.secureSpoolAvailable, isFalse);
    expect(result.unresolvedLocalJobs, 0);
    expect(
      result.spoolCountState,
      KitchenSpoolCountState.absent,
      reason: 'no DB file => the count is a PROVEN 0, not unknown',
    );
    expect(result.blockerCode, isNull);
    // NON-MUTATING: neither the spool directory nor the key appeared.
    expect(await factory().spoolFileExists(), isFalse);
    expect(
      Directory(
        '${tempDir.path}${Platform.pathSeparator}restoflow_kitchen_spool',
      ).existsSync(),
      isFalse,
    );
    expect(storage.values, isEmpty);
  });

  test('existing DB + present key: available=true with the SCOPE-SPECIFIC '
      'unresolved count; the probe closes its handle', () async {
    await keyManager().provisionKey();
    final db = await factory().open();
    final store = DriftKitchenSpoolStore(db);
    await seedJob(store, deviceId: 'dev-1', branchId: 'branch-1');
    await seedJob(
      store,
      deviceId: 'dev-OTHER',
      branchId: 'branch-1',
      dispatchId: 'disp-2',
    );
    await db.close();

    final result = await probe().probe(deviceId: 'dev-1', branchId: 'branch-1');
    expect(result.secureSpoolAvailable, isTrue);
    expect(result.unresolvedLocalJobs, 1, reason: 'other scopes never count');
    expect(result.spoolCountState, KitchenSpoolCountState.counted);
    expect(result.blockerCode, isNull);
    // Closed handle: tearDown's recursive delete proves no Windows lock.
  });

  test('existing DB + MISSING key: false with kitchen_spool_key_missing and '
      'the count still reported; the key is NEVER provisioned', () async {
    await keyManager().provisionKey();
    final db = await factory().open();
    await seedJob(
      DriftKitchenSpoolStore(db),
      deviceId: 'dev-1',
      branchId: 'branch-1',
    );
    await db.close();
    storage.values.clear(); // simulate a lost key with surviving rows

    final result = await probe().probe(deviceId: 'dev-1', branchId: 'branch-1');
    expect(result.secureSpoolAvailable, isFalse);
    expect(result.unresolvedLocalJobs, 1);
    expect(
      result.spoolCountState,
      KitchenSpoolCountState.counted,
      reason: 'a readable DB is authoritatively COUNTED even with no key',
    );
    expect(result.blockerCode, 'kitchen_spool_key_missing');
    expect(storage.values, isEmpty, reason: 'probe must not provision');
  });

  test('corrupted key value: typed kitchen_spool_key_corrupted, never '
      'wiped/regenerated', () async {
    final store = FlutterSecureKitchenSpoolKeyStore(
      storage: storage,
      platform: nativePlatform,
    );
    await keyManager().provisionKey();
    final keyName = storage.values.keys.single;
    storage.values[keyName] = 'not-base64!!';
    final result = await probe().probe(deviceId: 'dev-1', branchId: 'branch-1');
    expect(result.secureSpoolAvailable, isFalse);
    expect(
      result.spoolCountState,
      KitchenSpoolCountState.absent,
      reason: 'no DB file was created; a corrupt KEY never fakes a count',
    );
    expect(result.blockerCode, 'kitchen_spool_key_corrupted');
    expect(
      storage.values[keyName],
      'not-base64!!',
      reason: 'corrupted evidence is preserved, never silently regenerated',
    );
    expect(store, isNotNull);
  });

  test('corrupt DB FILE: typed spool_database_unavailable; the file is left '
      'untouched', () async {
    await keyManager().provisionKey();
    final path = KitchenSpoolDatabaseFactory.databasePathUnder(tempDir);
    File(path).createSync(recursive: true);
    File(path).writeAsStringSync('THIS IS NOT A SQLITE DATABASE');

    final result = await probe().probe(deviceId: 'dev-1', branchId: 'branch-1');
    expect(result.secureSpoolAvailable, isFalse);
    expect(result.unresolvedLocalJobs, 0);
    expect(
      result.spoolCountState,
      KitchenSpoolCountState.unknown,
      reason: 'an unreadable DB yields an UNKNOWN count (0 is not a claim)',
    );
    expect(result.blockerCode, 'spool_database_unavailable');
    expect(
      File(path).readAsStringSync(),
      'THIS IS NOT A SQLITE DATABASE',
      reason: 'no destructive recovery, ever',
    );
  });

  test('KITCHEN-MODE-001C3B1A2: a secure-storage/key inspection FAILURE must '
      'NOT downgrade a successfully-counted DB to unknown', () async {
    // Seed a real, readable DB with one job (count is authoritatively 1)...
    await keyManager().provisionKey();
    final db = await factory().open();
    await seedJob(
      DriftKitchenSpoolStore(db),
      deviceId: 'dev-1',
      branchId: 'branch-1',
    );
    await db.close();

    // ...then make the WHOLE key path blow up (the harshest secure-storage
    // failure: even building the inspector throws).
    final result = await KitchenSpoolReadinessProbe(
      platform: nativePlatform,
      databaseFactoryBuilder: factory,
      keyManagerBuilder: () => throw const FileSystemException('keystore down'),
    ).probe(deviceId: 'dev-1', branchId: 'branch-1');

    expect(
      result.spoolCountState,
      KitchenSpoolCountState.counted,
      reason: 'the DB opened and counted; a key hiccup cannot erase that',
    );
    expect(result.unresolvedLocalJobs, 1, reason: 'the exact count is kept');
    expect(
      result.secureSpoolAvailable,
      isFalse,
      reason: 'still unprintable — no usable key',
    );
    expect(result.blockerCode, 'secure_storage_unavailable');
  });
}
