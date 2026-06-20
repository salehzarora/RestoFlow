import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_core/testing.dart';
import 'package:test/test.dart';

void main() {
  final ref = SecretRef('ref:test-device-secret');
  final value = SecretValue('test-secret-placeholder');

  group('SecureKeyStore fail-closed (RF-021)', () {
    test('available store round-trips read / write / delete', () async {
      final store = InMemorySecureKeyStore();
      expect(await store.read(ref), isNull); // missing key
      await store.write(ref, value);
      expect(await store.read(ref), same(value));
      await store.delete(ref);
      expect(await store.read(ref), isNull);
    });

    test('unavailable store fails closed on read and write', () {
      final store = InMemorySecureKeyStore(available: false);
      expect(
        store.read(ref),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
      expect(
        store.write(ref, value),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
    });

    test('missing key returns null (caller enforces fail-closed)', () async {
      final store = InMemorySecureKeyStore();
      expect(await store.read(SecretRef('ref:absent')), isNull);
    });

    test('corrupted key fails closed', () async {
      final store = InMemorySecureKeyStore();
      await store.write(ref, value);
      store.markCorrupted(ref);
      expect(store.read(ref), throwsA(isA<SecretCorruptedException>()));
    });

    test('wipeAll crypto-erases secrets (revocation path)', () async {
      final store = InMemorySecureKeyStore();
      await store.write(ref, value);
      await store.wipeAll();
      expect(await store.read(ref), isNull);
    });

    test('exception messages never contain raw secret material', () {
      expect(
        SecretNotFoundException(ref).toString(),
        isNot(contains('test-secret-placeholder')),
      );
      expect(
        SecretCorruptedException(ref).toString(),
        allOf(
          contains('ref:test-device-secret'),
          isNot(contains('test-secret-placeholder')),
        ),
      );
      expect(const SecureStorageUnavailableException().message, isNotEmpty);
      expect(
        const DataAtRestProtectionUnavailableException().message,
        isNotEmpty,
      );
    });
  });
}
