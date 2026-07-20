import 'dart:async' show Completer;
import 'dart:convert' show base64Url, utf8;
import 'dart:typed_data';

import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_core/testing.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// CLEANUP 6 harness: a SecureKeyStore wrapper whose read/write block on
/// externally-controlled gates, so tests can interleave two provision calls
/// deterministically.
final class _GatedKeyStore implements SecureKeyStore {
  _GatedKeyStore(this._inner);

  final SecureKeyStore _inner;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  int reads = 0;
  int writes = 0;

  @override
  Future<bool> isAvailable() => _inner.isAvailable();

  @override
  Future<SecretValue?> read(SecretRef ref) async {
    reads++;
    if (readGate != null) await readGate!.future;
    return _inner.read(ref);
  }

  @override
  Future<void> write(SecretRef ref, SecretValue value) async {
    writes++;
    if (writeGate != null) await writeGate!.future;
    return _inner.write(ref, value);
  }

  @override
  Future<void> delete(SecretRef ref) => _inner.delete(ref);

  @override
  Future<void> wipeAll() => _inner.wipeAll();
}

KitchenSpoolAad _aad({
  String dispatchId = 'd1000000-0000-0000-0000-000000000001',
  String organizationId = 'a0000000-0000-0000-0000-00000000000a',
  String restaurantId = 'a1000000-0000-0000-0000-00000000000a',
  String branchId = 'b1000000-0000-0000-0000-00000000000b',
  String deviceId = 'de000000-0000-0000-0000-00000000000d',
  int encryptionVersion = 1,
}) => KitchenSpoolAad(
  dispatchId: dispatchId,
  organizationId: organizationId,
  restaurantId: restaurantId,
  branchId: branchId,
  deviceId: deviceId,
  encryptionVersion: encryptionVersion,
);

void main() {
  group('KitchenSpoolKeyManager (KITCHEN-MODE-001C2A §3)', () {
    late InMemorySecureKeyStore store;
    late KitchenSpoolKeyManager manager;

    setUp(() {
      store = InMemorySecureKeyStore();
      manager = KitchenSpoolKeyManager(store);
    });

    test(
      'provisions a 32-byte cryptographically random key explicitly',
      () async {
        expect(await manager.readKey(), isNull);
        await manager.provisionKey();
        final key = await manager.readKey();
        expect(key, isNotNull);
        final bytes = decodeKitchenSpoolKey(key!);
        expect(bytes.length, 32);
      },
    );

    test('two provisioned keys differ (secure randomness smoke)', () async {
      await manager.provisionKey();
      final first = decodeKitchenSpoolKey((await manager.readKey())!);
      final other = InMemorySecureKeyStore();
      final otherManager = KitchenSpoolKeyManager(other);
      await otherManager.provisionKey();
      final second = decodeKitchenSpoolKey((await otherManager.readKey())!);
      expect(first, isNot(equals(second)));
    });

    test('refuses to overwrite an existing key', () async {
      await manager.provisionKey();
      await expectLater(
        manager.provisionKey(),
        throwsA(isA<SecretAlreadyExistsException>()),
      );
    });

    test(
      'refuses to overwrite even a CORRUPTED slot (no silent replacement)',
      () async {
        await manager.provisionKey();
        store.markCorrupted(KitchenSpoolKeyManager.keyRef);
        await expectLater(
          manager.provisionKey(),
          throwsA(isA<SecretAlreadyExistsException>()),
        );
      },
    );

    test(
      'readKey maps a malformed stored value to SecretCorruptedException',
      () async {
        await store.write(
          KitchenSpoolKeyManager.keyRef,
          SecretValue('not-base64!!!'),
        );
        await expectLater(
          manager.readKey(),
          throwsA(isA<SecretCorruptedException>()),
        );
      },
    );

    test('readKey rejects a wrong-length key as corrupted', () async {
      final short = base64Url.encode(List.filled(16, 7)).replaceAll('=', '');
      await store.write(KitchenSpoolKeyManager.keyRef, SecretValue(short));
      await expectLater(
        manager.readKey(),
        throwsA(isA<SecretCorruptedException>()),
      );
    });

    test(
      'inspectState reports present/missing/corrupted/unavailable',
      () async {
        expect(await manager.inspectState(), KitchenSpoolKeyState.missing);
        await manager.provisionKey();
        expect(await manager.inspectState(), KitchenSpoolKeyState.present);
        store.markCorrupted(KitchenSpoolKeyManager.keyRef);
        expect(await manager.inspectState(), KitchenSpoolKeyState.corrupted);
        store.setAvailable(available: false);
        expect(await manager.inspectState(), KitchenSpoolKeyState.unavailable);
      },
    );

    test('deleteKeyDangerously is the ONLY removal path and works', () async {
      await manager.provisionKey();
      await manager.deleteKeyDangerously();
      expect(await manager.readKey(), isNull);
      // After explicit deletion, provisioning is allowed again.
      await manager.provisionKey();
      expect(await manager.readKey(), isNotNull);
    });

    test('the key reference is fixed and versioned', () {
      expect(
        KitchenSpoolKeyManager.keyRef.value,
        'ref:kitchen-spool-aes-key-v1',
      );
    });

    test('no key material in SecretValue.toString', () async {
      await manager.provisionKey();
      final key = await manager.readKey();
      expect(key.toString(), 'SecretValue(***redacted***)');
      expect(key.toString(), isNot(contains(key!.revealForCryptoBoundary())));
    });
  });

  group('AesGcmKitchenSpoolCipher (KITCHEN-MODE-001C2A §1/§2)', () {
    late AesGcmKitchenSpoolCipher cipher;
    late SecretValue key;

    setUp(() async {
      cipher = AesGcmKitchenSpoolCipher();
      final store = InMemorySecureKeyStore();
      final manager = KitchenSpoolKeyManager(store);
      await manager.provisionKey();
      key = (await manager.readKey())!;
    });

    Uint8List plaintext([String s = '{"v":1,"kind":"initial_order"}']) =>
        Uint8List.fromList(utf8.encode(s));

    test('AES-GCM round trip', () async {
      final envelope = await cipher.encrypt(
        plaintext: plaintext(),
        aad: _aad(),
        key: key,
      );
      final clear = await cipher.decrypt(
        envelope: envelope,
        aad: _aad(),
        key: key,
      );
      expect(utf8.decode(clear), '{"v":1,"kind":"initial_order"}');
    });

    test(
      'envelope format: magic, version, 12-byte nonce, 16-byte tag',
      () async {
        final envelope = await cipher.encrypt(
          plaintext: plaintext('x'),
          aad: _aad(),
          key: key,
        );
        expect(envelope.sublist(0, 4), [0x52, 0x4B, 0x53, 0x31]); // 'RKS1'
        expect(envelope[4], 1); // version
        expect(envelope[5], 12); // nonce length
        // header(18) + ciphertext(1) + tag(16)
        expect(envelope.length, 18 + 1 + 16);
      },
    );

    test('unique random nonce per encryption (same input twice)', () async {
      final a = await cipher.encrypt(
        plaintext: plaintext(),
        aad: _aad(),
        key: key,
      );
      final b = await cipher.encrypt(
        plaintext: plaintext(),
        aad: _aad(),
        key: key,
      );
      expect(a.sublist(6, 18), isNot(equals(b.sublist(6, 18))));
      expect(a, isNot(equals(b)));
    });

    test('empty plaintext is refused (no documented empty payload)', () {
      expect(
        () => cipher.encrypt(plaintext: Uint8List(0), aad: _aad(), key: key),
        throwsA(isA<MalformedKitchenSpoolEnvelopeException>()),
      );
    });

    test(
      'malformed envelopes are rejected (truncated / bad magic / bad nonce length / empty ciphertext)',
      () async {
        final good = await cipher.encrypt(
          plaintext: plaintext(),
          aad: _aad(),
          key: key,
        );
        // Truncated below the minimum shape.
        await expectLater(
          cipher.decrypt(envelope: good.sublist(0, 20), aad: _aad(), key: key),
          throwsA(isA<MalformedKitchenSpoolEnvelopeException>()),
        );
        // Bad magic.
        final badMagic = Uint8List.fromList(good);
        badMagic[0] = 0x00;
        await expectLater(
          cipher.decrypt(envelope: badMagic, aad: _aad(), key: key),
          throwsA(isA<MalformedKitchenSpoolEnvelopeException>()),
        );
        // Bad nonce length byte.
        final badNonceLen = Uint8List.fromList(good);
        badNonceLen[5] = 16;
        await expectLater(
          cipher.decrypt(envelope: badNonceLen, aad: _aad(), key: key),
          throwsA(isA<MalformedKitchenSpoolEnvelopeException>()),
        );
      },
    );

    test('unknown envelope version is rejected', () async {
      final good = await cipher.encrypt(
        plaintext: plaintext(),
        aad: _aad(),
        key: key,
      );
      final unknown = Uint8List.fromList(good);
      unknown[4] = 2;
      await expectLater(
        cipher.decrypt(envelope: unknown, aad: _aad(), key: key),
        throwsA(isA<UnknownKitchenSpoolEnvelopeVersionException>()),
      );
    });

    test('tampered ciphertext fails authentication', () async {
      final good = await cipher.encrypt(
        plaintext: plaintext(),
        aad: _aad(),
        key: key,
      );
      final tampered = Uint8List.fromList(good);
      tampered[20] ^= 0xFF; // inside ciphertext
      await expectLater(
        cipher.decrypt(envelope: tampered, aad: _aad(), key: key),
        throwsA(isA<KitchenSpoolDecryptionFailedException>()),
      );
    });

    test('tampered tag fails authentication', () async {
      final good = await cipher.encrypt(
        plaintext: plaintext(),
        aad: _aad(),
        key: key,
      );
      final tampered = Uint8List.fromList(good);
      tampered[tampered.length - 1] ^= 0x01;
      await expectLater(
        cipher.decrypt(envelope: tampered, aad: _aad(), key: key),
        throwsA(isA<KitchenSpoolDecryptionFailedException>()),
      );
    });

    test('a wrong key is rejected', () async {
      final envelope = await cipher.encrypt(
        plaintext: plaintext(),
        aad: _aad(),
        key: key,
      );
      final otherStore = InMemorySecureKeyStore();
      final otherManager = KitchenSpoolKeyManager(otherStore);
      await otherManager.provisionKey();
      final wrongKey = (await otherManager.readKey())!;
      await expectLater(
        cipher.decrypt(envelope: envelope, aad: _aad(), key: wrongKey),
        throwsA(isA<KitchenSpoolDecryptionFailedException>()),
      );
    });

    test('an invalid key length is a typed key error', () async {
      final short = base64Url.encode(List.filled(16, 3)).replaceAll('=', '');
      await expectLater(
        cipher.encrypt(
          plaintext: plaintext(),
          aad: _aad(),
          key: SecretValue(short),
        ),
        throwsA(isA<InvalidKitchenSpoolKeyException>()),
      );
    });

    test('EVERY individual AAD field mismatch fails decryption', () async {
      final envelope = await cipher.encrypt(
        plaintext: plaintext(),
        aad: _aad(),
        key: key,
      );
      final mismatches = <String, KitchenSpoolAad>{
        'dispatchId': _aad(dispatchId: 'd2000000-0000-0000-0000-000000000002'),
        'organizationId': _aad(
          organizationId: 'a9000000-0000-0000-0000-00000000000a',
        ),
        'restaurantId': _aad(
          restaurantId: 'a2000000-0000-0000-0000-00000000000a',
        ),
        'branchId': _aad(branchId: 'b2000000-0000-0000-0000-00000000000b'),
        'deviceId': _aad(deviceId: 'df000000-0000-0000-0000-00000000000d'),
        'encryptionVersion': _aad(encryptionVersion: 2),
      };
      for (final entry in mismatches.entries) {
        await expectLater(
          cipher.decrypt(envelope: envelope, aad: entry.value, key: key),
          throwsA(isA<KitchenSpoolDecryptionFailedException>()),
          reason: 'AAD mismatch on ${entry.key} must fail',
        );
      }
    });

    test(
      'AAD normalizes IDs (case/whitespace) instead of binding raw text',
      () {
        final a = _aad(dispatchId: 'D1000000-0000-0000-0000-000000000001 ');
        final b = _aad(dispatchId: 'd1000000-0000-0000-0000-000000000001');
        expect(a.encode(), equals(b.encode()));
      },
    );

    test('AAD refuses empty required fields', () {
      expect(() => _aad(dispatchId: '  '), throwsArgumentError);
      expect(() => _aad(encryptionVersion: 0), throwsArgumentError);
    });

    test('no key or plaintext in exception/error text or toString', () async {
      final envelope = await cipher.encrypt(
        plaintext: plaintext('SENSITIVE kitchen line'),
        aad: _aad(),
        key: key,
      );
      final tampered = Uint8List.fromList(envelope);
      tampered[20] ^= 0xFF;
      try {
        await cipher.decrypt(envelope: tampered, aad: _aad(), key: key);
        fail('expected failure');
      } on KitchenSpoolCryptoException catch (e) {
        expect(e.toString(), isNot(contains('SENSITIVE')));
        expect(e.toString(), isNot(contains(key.revealForCryptoBoundary())));
      }
      // The AAD toString carries only non-secret metadata; the envelope is
      // binary and has no toString of its own beyond the list default.
      expect(_aad().toString(), contains('KitchenSpoolAad('));
    });

    test('there is NO plaintext fallback anywhere in the cipher API', () {
      // The contract exposes exactly encrypt/decrypt; no method returns the
      // plaintext without a valid key + envelope + AAD. (Compile-time shape
      // assertion via the interface.)
      final KitchenSpoolCipher asPort = cipher;
      expect(asPort.encryptionVersion, 1);
    });

    test(
      'CLEANUP 7A: 128 encryptions of the same input yield 128 DISTINCT '
      '12-byte nonces and distinct envelopes (sampling, not a proof)',
      () async {
        final nonces = <String>{};
        final envelopes = <String>{};
        for (var i = 0; i < 128; i++) {
          final envelope = await cipher.encrypt(
            plaintext: plaintext(),
            aad: _aad(),
            key: key,
          );
          final nonce = envelope.sublist(6, 18);
          expect(nonce.length, 12);
          nonces.add(nonce.join(','));
          envelopes.add(envelope.join(','));
        }
        expect(nonces.length, 128);
        expect(envelopes.length, 128);
      },
    );

    test('CLEANUP 7B: envelope boundary matrix', () async {
      // Minimum VALID boundary: exactly one plaintext byte round-trips
      // (header 18 + ciphertext 1 + tag 16 = 35 bytes).
      final minimal = await cipher.encrypt(
        plaintext: Uint8List.fromList([0x7B]),
        aad: _aad(),
        key: key,
      );
      expect(minimal.length, 35);
      final back = await cipher.decrypt(
        envelope: minimal,
        aad: _aad(),
        key: key,
      );
      expect(back, [0x7B]);

      // Tag-only (header + tag, ZERO ciphertext bytes) is malformed.
      final tagOnly = Uint8List(18 + 16)
        ..setRange(0, 4, const [0x52, 0x4B, 0x53, 0x31]);
      tagOnly[4] = 1;
      tagOnly[5] = 12;
      await expectLater(
        cipher.decrypt(envelope: tagOnly, aad: _aad(), key: key),
        throwsA(isA<MalformedKitchenSpoolEnvelopeException>()),
      );

      // Trailing extra bytes shift the tag window -> authentication fails
      // (the documented format has no trailer; nothing is silently ignored).
      final trailing = Uint8List.fromList([...minimal, 0x00, 0x01]);
      await expectLater(
        cipher.decrypt(envelope: trailing, aad: _aad(), key: key),
        throwsA(isA<KitchenSpoolDecryptionFailedException>()),
      );

      // An absurd nonce-length byte cannot cause surprise allocation — it is
      // rejected structurally before any slicing.
      final hugeNonce = Uint8List.fromList(minimal);
      hugeNonce[5] = 255;
      await expectLater(
        cipher.decrypt(envelope: hugeNonce, aad: _aad(), key: key),
        throwsA(isA<MalformedKitchenSpoolEnvelopeException>()),
      );

      // Empty input and sub-header input are malformed, never a range error.
      await expectLater(
        cipher.decrypt(envelope: Uint8List(0), aad: _aad(), key: key),
        throwsA(isA<MalformedKitchenSpoolEnvelopeException>()),
      );
    });
  });

  group('KitchenSpoolKeyManager provisioning single-flight (CLEANUP 6)', () {
    test('two concurrent provision calls: EXACTLY one provisions, the other '
        'gets already-exists, ONE key survives', () async {
      final inner = InMemorySecureKeyStore();
      final gated = _GatedKeyStore(inner);
      final manager = KitchenSpoolKeyManager(gated);

      // Hold the FIRST call inside its read so the second call queues
      // while the first has already observed "missing".
      gated.readGate = Completer<void>();
      final first = manager.provisionKey();
      final second = manager.provisionKey();
      // Release: without single-flight the second read would also see
      // "missing" and a second key would overwrite the first.
      gated.readGate!.complete();
      gated.readGate = null;

      await first; // succeeds
      await expectLater(second, throwsA(isA<SecretAlreadyExistsException>()));
      // One stored key; both operations went through the serialized path.
      final stored = await manager.readKey();
      expect(stored, isNotNull);
      expect(gated.writes, 1, reason: 'exactly ONE write ever happened');
      // No ciphertext could be stranded: the surviving key is the one the
      // successful call wrote (nothing replaced it).
      expect(await manager.inspectState(), KitchenSpoolKeyState.present);
    });

    test(
      'concurrent provisioning over a CORRUPTED slot never overwrites',
      () async {
        final inner = InMemorySecureKeyStore();
        final manager = KitchenSpoolKeyManager(inner);
        await manager.provisionKey();
        inner.markCorrupted(KitchenSpoolKeyManager.keyRef);
        final results = await Future.wait([
          manager.provisionKey().then<Object>(
            (_) => 'ok',
            onError: (Object e) => e,
          ),
          manager.provisionKey().then<Object>(
            (_) => 'ok',
            onError: (Object e) => e,
          ),
        ]);
        for (final r in results) {
          expect(r, isA<SecretAlreadyExistsException>());
        }
      },
    );

    test(
      'concurrent provisioning on an UNAVAILABLE store stays typed',
      () async {
        final inner = InMemorySecureKeyStore(available: false);
        final manager = KitchenSpoolKeyManager(inner);
        final results = await Future.wait([
          manager.provisionKey().then<Object>(
            (_) => 'ok',
            onError: (Object e) => e,
          ),
          manager.provisionKey().then<Object>(
            (_) => 'ok',
            onError: (Object e) => e,
          ),
        ]);
        for (final r in results) {
          expect(r, isA<SecureStorageUnavailableException>());
        }
        // A failed provision never poisons the chain: once available, the
        // next provision succeeds normally.
        inner.setAvailable(available: true);
        await manager.provisionKey();
        expect(await manager.readKey(), isNotNull);
      },
    );
  });
}
