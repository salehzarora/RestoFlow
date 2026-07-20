import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_pos/src/spool/flutter_secure_kitchen_spool_key_store.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_key_flow.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';

/// In-memory secure-storage fake (no platform channels).
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

/// Metadata-count-only store fake: the key flow may consult row COUNTS but
/// must never decrypt or mutate anything, so nothing else is implemented.
class _CountOnlyStore extends Fake implements KitchenSpoolStore {
  _CountOnlyStore(this.total);

  int total;

  @override
  Future<int> countTotalRows() async => total;
}

const String _namespacedKeyRef =
    'restoflow.pos.kitchen_spool.ref:kitchen-spool-aes-key-v1';

void main() {
  const native = PosKitchenSpoolPlatform(isWeb: false);
  const web = PosKitchenSpoolPlatform(isWeb: true);

  late _FakeSecureStorage fake;

  PosKitchenSpoolKeyFlow flow({
    required int totalRows,
    PosKitchenSpoolPlatform platform = native,
  }) => PosKitchenSpoolKeyFlow(
    keyManager: KitchenSpoolKeyManager(
      FlutterSecureKitchenSpoolKeyStore(storage: fake, platform: platform),
    ),
    store: _CountOnlyStore(totalRows),
  );

  setUp(() => fake = _FakeSecureStorage());

  test('provisioned key -> ready', () async {
    await KitchenSpoolKeyManager(
      FlutterSecureKitchenSpoolKeyStore(storage: fake, platform: native),
    ).provisionKey();
    expect(await flow(totalRows: 3).evaluate(), isA<KitchenSpoolKeyReady>());
  });

  test('missing key + ZERO rows -> provisionable (D3)', () async {
    expect(
      await flow(totalRows: 0).evaluate(),
      isA<KitchenSpoolKeyMissingProvisionable>(),
    );
    expect(fake.values, isEmpty, reason: 'evaluate must never provision');
  });

  test('missing key + ANY row -> BLOCKED with the row count; never regenerated '
      '(a new key would strand the existing ciphertext)', () async {
    final capability = await flow(totalRows: 7).evaluate();
    expect(capability, isA<KitchenSpoolKeyMissingWithRows>());
    expect((capability as KitchenSpoolKeyMissingWithRows).totalRows, 7);
    expect(fake.values, isEmpty);
  });

  test(
    'corrupted key slot -> BLOCKED; the slot is preserved as evidence',
    () async {
      fake.values[_namespacedKeyRef] = 'not-a-valid-base64url-32-byte-key!!';
      expect(
        await flow(totalRows: 0).evaluate(),
        isA<KitchenSpoolKeyCorrupted>(),
      );
      expect(
        fake.values[_namespacedKeyRef],
        'not-a-valid-base64url-32-byte-key!!',
        reason: 'no silent wipe/replacement of a corrupted slot',
      );
    },
  );

  test('unavailable secure storage (web) -> BLOCKED', () async {
    expect(
      await flow(totalRows: 0, platform: web).evaluate(),
      isA<KitchenSpoolKeyUnavailable>(),
    );
  });

  group('provisionIfEligible', () {
    test('provisions ONLY in the missing-with-zero-rows state', () async {
      expect(
        await flow(totalRows: 0).provisionIfEligible(),
        isA<KitchenSpoolKeyReady>(),
      );
      expect(fake.values.keys.single, _namespacedKeyRef);
    });

    test('missing-with-rows stays blocked and writes NO key', () async {
      final capability = await flow(totalRows: 2).provisionIfEligible();
      expect(capability, isA<KitchenSpoolKeyMissingWithRows>());
      expect(fake.values, isEmpty);
    });

    test('corrupted stays blocked; the stored value is untouched', () async {
      fake.values[_namespacedKeyRef] = 'corrupted-value';
      expect(
        await flow(totalRows: 0).provisionIfEligible(),
        isA<KitchenSpoolKeyCorrupted>(),
      );
      expect(fake.values[_namespacedKeyRef], 'corrupted-value');
    });
  });
}
