import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceSessionCredential', () {
    test('value equality + token-redacted toString', () {
      const a = DeviceSessionCredential(deviceId: 'd1', sessionToken: 'secret');
      const b = DeviceSessionCredential(deviceId: 'd1', sessionToken: 'secret');
      const c = DeviceSessionCredential(deviceId: 'd1', sessionToken: 'other');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      // the secret token is never exposed by toString.
      expect(a.toString(), contains('d1'));
      expect(a.toString(), isNot(contains('secret')));
    });
  });

  group('InMemoryDeviceSessionSecretStore', () {
    test('read is null before any write', () async {
      final store = InMemoryDeviceSessionSecretStore();
      expect(await store.read(), isNull);
    });

    test('write then read returns the same credential', () async {
      final store = InMemoryDeviceSessionSecretStore();
      const cred = DeviceSessionCredential(deviceId: 'd1', sessionToken: 't1');
      await store.write(cred);
      expect(await store.read(), equals(cred));
    });

    test('write overwrites the prior credential', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'd1', sessionToken: 't1'),
      );
      await store.write(
        const DeviceSessionCredential(deviceId: 'd2', sessionToken: 't2'),
      );
      expect(
        await store.read(),
        equals(
          const DeviceSessionCredential(deviceId: 'd2', sessionToken: 't2'),
        ),
      );
    });

    test('clear removes the credential and is idempotent', () async {
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'd1', sessionToken: 't1'),
      );
      await store.clear();
      expect(await store.read(), isNull);
      await store.clear();
      expect(await store.read(), isNull);
    });
  });
}
