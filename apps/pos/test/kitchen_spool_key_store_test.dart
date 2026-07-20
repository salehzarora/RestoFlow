import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_pos/src/spool/flutter_secure_kitchen_spool_key_store.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';

/// Recording fake of the platform plugin (no channels; deterministic).
class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> values = {};
  int readCalls = 0;
  int writeCalls = 0;
  int deleteCalls = 0;
  bool throwOnRead = false;
  bool throwOnWrite = false;

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
    if (throwOnRead) {
      throw Exception('keystore boom SECRET-SHOULD-NOT-LEAK');
    }
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
    if (throwOnWrite) {
      throw Exception('keystore boom');
    }
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
  const native = PosKitchenSpoolPlatform(isWeb: false);
  const web = PosKitchenSpoolPlatform(isWeb: true);
  final ref = SecretRef('ref:kitchen-spool-aes-key-v1');

  group('FlutterSecureKitchenSpoolKeyStore — native Android path', () {
    late _FakeSecureStorage fake;
    late FlutterSecureKitchenSpoolKeyStore store;

    setUp(() {
      fake = _FakeSecureStorage();
      store = FlutterSecureKitchenSpoolKeyStore(
        storage: fake,
        platform: native,
      );
    });

    test('read missing returns null', () async {
      expect(await store.isAvailable(), isTrue);
      expect(await store.read(ref), isNull);
    });

    test('write then read round-trips under the kitchen namespace', () async {
      await store.write(ref, SecretValue('a-key-value'));
      expect(
        fake.values.keys.single,
        'restoflow.pos.kitchen_spool.ref:kitchen-spool-aes-key-v1',
      );
      final back = await store.read(ref);
      expect(back!.revealForStorageBoundary(), 'a-key-value');
    });

    test('overwrite is refused (SecretAlreadyExistsException)', () async {
      await store.write(ref, SecretValue('first'));
      await expectLater(
        store.write(ref, SecretValue('second')),
        throwsA(isA<SecretAlreadyExistsException>()),
      );
      expect((await store.read(ref))!.revealForStorageBoundary(), 'first');
    });

    test('delete removes and is idempotent', () async {
      await store.write(ref, SecretValue('v'));
      await store.delete(ref);
      expect(await store.read(ref), isNull);
      await store.delete(ref); // no throw
    });

    test('a present-but-empty value is CORRUPTED, not missing', () async {
      fake.values['restoflow.pos.kitchen_spool.${ref.value}'] = '  ';
      await expectLater(
        store.read(ref),
        throwsA(isA<SecretCorruptedException>()),
      );
    });

    test(
      'platform-channel failure maps to unavailable, with redaction',
      () async {
        fake.throwOnRead = true;
        try {
          await store.read(ref);
          fail('expected SecureStorageUnavailableException');
        } on SecureStorageUnavailableException catch (e) {
          expect(e.toString(), isNot(contains('SECRET-SHOULD-NOT-LEAK')));
        }
        fake.throwOnRead = false;
        fake.throwOnWrite = true;
        await expectLater(
          store.write(ref, SecretValue('v')),
          throwsA(isA<SecureStorageUnavailableException>()),
        );
      },
    );

    test(
      'wipeAll erases ONLY kitchen-spool keys (auth keys survive)',
      () async {
        fake.values['restoflow.device_session_token'] = 'auth-token';
        await store.write(ref, SecretValue('kitchen-key'));
        await store.wipeAll();
        expect(await store.read(ref), isNull);
        expect(fake.values['restoflow.device_session_token'], 'auth-token');
      },
    );

    test(
      'KitchenSpoolKeyManager provisions through the adapter end-to-end',
      () async {
        // Pure-Dart manager over the POS adapter: the full explicit lifecycle.
        // (The manager lives in restoflow_data_local; here we only need the
        // SecureKeyStore contract to hold, which the adapter satisfies.)
        final SecureKeyStore asPort = store;
        expect(await asPort.isAvailable(), isTrue);
        await asPort.write(ref, SecretValue('once'));
        await expectLater(
          asPort.write(ref, SecretValue('twice')),
          throwsA(isA<SecretAlreadyExistsException>()),
        );
      },
    );
  });

  group('FlutterSecureKitchenSpoolKeyStore — web fails closed', () {
    late _FakeSecureStorage fake;
    late FlutterSecureKitchenSpoolKeyStore store;

    setUp(() {
      fake = _FakeSecureStorage();
      store = FlutterSecureKitchenSpoolKeyStore(storage: fake, platform: web);
    });

    test('isAvailable is false and the capability seam reports no spool', () {
      expect(web.supportsSecureSpool, isFalse);
      expect(store.isAvailable(), completion(isFalse));
    });

    test(
      'read/write/delete throw unavailable and NEVER touch any storage',
      () async {
        await expectLater(
          store.read(ref),
          throwsA(isA<SecureStorageUnavailableException>()),
        );
        await expectLater(
          store.write(ref, SecretValue('v')),
          throwsA(isA<SecureStorageUnavailableException>()),
        );
        await expectLater(
          store.delete(ref),
          throwsA(isA<SecureStorageUnavailableException>()),
        );
        expect(fake.readCalls, 0, reason: 'no fallback storage of ANY kind');
        expect(fake.writeCalls, 0);
        expect(fake.deleteCalls, 0);
      },
    );

    test('native platform seam defaults report spool support', () {
      expect(native.supportsSecureSpool, isTrue);
    });
  });
}
