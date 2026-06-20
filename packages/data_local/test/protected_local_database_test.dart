import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_core/testing.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// TEST-ONLY strategy: reports available, records the key handed to it at the
/// crypto boundary, and returns a non-persistent in-memory executor.
class _RecordingEncryptionStrategy implements DatabaseEncryptionStrategy {
  SecretValue? recordedKey;
  String? recordedPath;

  @override
  Future<bool> isAvailable() async => true;

  @override
  QueryExecutor openEncrypted(String path, SecretValue key) {
    recordedKey = key;
    recordedPath = path;
    return NativeDatabase.memory();
  }
}

void main() {
  const path = 'test-only.db';
  SecretValue genKey() => SecretValue('test-secret-placeholder');
  final keyRef = ProtectedLocalDatabaseFactory.dbKeyRef;

  group('openPersistent — always fail-closed, never creates a key '
      '(RF021-B1)', () {
    test('fails closed when secure storage is unavailable (no open)', () async {
      final enc = _RecordingEncryptionStrategy();
      final f = ProtectedLocalDatabaseFactory(
        keyStore: InMemorySecureKeyStore(available: false),
        encryption: enc,
      );
      await expectLater(
        f.openPersistent(path: path),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
      expect(enc.recordedKey, isNull, reason: 'no unencrypted/plaintext open');
    });

    test(
      'fails closed when encryption is unavailable (default strategy)',
      () async {
        final f = ProtectedLocalDatabaseFactory(
          keyStore: InMemorySecureKeyStore(),
        );
        await expectLater(
          f.openPersistent(path: path),
          throwsA(isA<DataAtRestProtectionUnavailableException>()),
        );
      },
    );

    test(
      'fails closed when the key is MISSING and never creates one',
      () async {
        final store = InMemorySecureKeyStore();
        final enc = _RecordingEncryptionStrategy();
        final f = ProtectedLocalDatabaseFactory(
          keyStore: store,
          encryption: enc,
        );

        await expectLater(
          f.openPersistent(path: path),
          throwsA(isA<SecretNotFoundException>()),
        );
        expect(
          await store.read(keyRef),
          isNull,
          reason: 'openPersistent must NOT create a key',
        );
        expect(enc.recordedKey, isNull, reason: 'crypto boundary not reached');
      },
    );

    test(
      'fails closed when the key was WIPED/REVOKED and never recreates it',
      () async {
        final store = InMemorySecureKeyStore();
        await store.write(keyRef, genKey());
        await store.wipeAll(); // revocation -> crypto-erase
        expect(await store.read(keyRef), isNull, reason: 'wipe erased the key');

        final enc = _RecordingEncryptionStrategy();
        final f = ProtectedLocalDatabaseFactory(
          keyStore: store,
          encryption: enc,
        );
        await expectLater(
          f.openPersistent(path: path),
          throwsA(isA<SecretNotFoundException>()),
        );
        expect(
          await store.read(keyRef),
          isNull,
          reason: 'must NOT silently recreate a revoked key',
        );
        expect(enc.recordedKey, isNull, reason: 'crypto boundary not reached');
      },
    );

    test('fails closed when the stored key is CORRUPTED', () async {
      final store = InMemorySecureKeyStore();
      await store.write(keyRef, genKey());
      store.markCorrupted(keyRef);

      final enc = _RecordingEncryptionStrategy();
      final f = ProtectedLocalDatabaseFactory(keyStore: store, encryption: enc);
      await expectLater(
        f.openPersistent(path: path),
        throwsA(isA<SecretCorruptedException>()),
      );
      expect(enc.recordedKey, isNull, reason: 'crypto boundary not reached');
    });
  });

  group('provisionPersistentKey — explicit first-time provisioning '
      '(RF-021)', () {
    test(
      'creates + stores a key ONLY when called directly (opens no DB)',
      () async {
        final store = InMemorySecureKeyStore();
        final f = ProtectedLocalDatabaseFactory(
          keyStore: store,
          encryption: _RecordingEncryptionStrategy(),
        );
        expect(await store.read(keyRef), isNull);

        await f.provisionPersistentKey(generateKey: genKey);

        expect(
          await store.read(keyRef),
          isNotNull,
          reason: 'key stored only via secure storage',
        );
      },
    );

    test('refuses to overwrite an existing key', () async {
      final store = InMemorySecureKeyStore();
      await store.write(keyRef, genKey());
      final f = ProtectedLocalDatabaseFactory(
        keyStore: store,
        encryption: _RecordingEncryptionStrategy(),
      );
      await expectLater(
        f.provisionPersistentKey(
          generateKey: () => fail('must not regenerate over an existing key'),
        ),
        throwsA(isA<SecretAlreadyExistsException>()),
      );
    });

    test('fails closed when secure storage is unavailable', () async {
      final f = ProtectedLocalDatabaseFactory(
        keyStore: InMemorySecureKeyStore(available: false),
        encryption: _RecordingEncryptionStrategy(),
      );
      await expectLater(
        f.provisionPersistentKey(generateKey: genKey),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
    });

    test('fails closed when encryption is unavailable', () async {
      final f = ProtectedLocalDatabaseFactory(
        keyStore: InMemorySecureKeyStore(),
      );
      await expectLater(
        f.provisionPersistentKey(generateKey: genKey),
        throwsA(isA<DataAtRestProtectionUnavailableException>()),
      );
    });
  });

  group('open after explicit provisioning (RF-021)', () {
    test('openPersistent uses the provisioned key, passed ONLY through the '
        'crypto boundary', () async {
      final store = InMemorySecureKeyStore();
      final enc = _RecordingEncryptionStrategy();
      final f = ProtectedLocalDatabaseFactory(keyStore: store, encryption: enc);

      await f.provisionPersistentKey(generateKey: genKey);
      final stored = await store.read(keyRef);
      expect(stored, isNotNull);

      final db = await f.openPersistent(path: path);
      addTearDown(db.close);

      expect(
        enc.recordedKey,
        same(stored),
        reason: 'open uses the stored key, handed to the cipher boundary',
      );
      expect(
        enc.recordedKey!.revealForCryptoBoundary(),
        'test-secret-placeholder',
      );
      expect(enc.recordedPath, path);
      expect(db.allTables.map((t) => t.actualTableName).toSet(), {
        'outbox_operations',
        'processed_pull_log',
      });
    });
  });

  group('in-memory DB is test-only (RF-021)', () {
    test('NativeDatabase.memory() is non-persistent; used only by tests', () {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(db.allTables, isNotEmpty);
    });
  });
}
