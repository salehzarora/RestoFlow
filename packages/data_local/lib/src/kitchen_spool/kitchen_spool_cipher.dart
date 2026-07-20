/// KITCHEN-MODE-001C2A — field-level AES-256-GCM protection for the kitchen
/// spool payload blob.
///
/// This is deliberately FIELD-LEVEL encryption of ONE column
/// (`encrypted_payload_blob`) — it is NOT SQLCipher and makes no
/// database-wide encryption claim. There is NO plaintext fallback anywhere:
/// a missing key, malformed envelope, unknown version, or failed
/// authentication is a typed, fail-closed error.
///
/// Envelope binary format v1 (documented, versioned, rejected when unknown):
///
/// ```text
/// offset 0..3   magic 'RKS1' (0x52 0x4B 0x53 0x31)
/// offset 4      envelope version (0x01)
/// offset 5      nonce length     (must be 12 for v1)
/// offset 6..17  nonce            (12 random bytes, unique per encryption)
/// offset 18..N  ciphertext       (must be non-empty for v1 — every valid
///                                 kitchen payload serializes to >0 bytes)
/// last 16 bytes GCM authentication tag
/// ```
///
/// No key identifier and no key material are ever stored inside the blob.
library;

import 'dart:convert' show base64Url;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:restoflow_core/restoflow_core.dart';

import 'kitchen_spool_aad.dart';

/// Base type for every kitchen-spool crypto failure. Messages are static and
/// NEVER contain key material, plaintext, or ciphertext.
sealed class KitchenSpoolCryptoException implements Exception {
  const KitchenSpoolCryptoException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The provided key is not a valid 32-byte AES-256 key.
final class InvalidKitchenSpoolKeyException
    extends KitchenSpoolCryptoException {
  const InvalidKitchenSpoolKeyException()
    : super('Kitchen spool key is not a valid 32-byte AES-256 key');
}

/// The stored blob is not a well-formed envelope (bad magic, truncated,
/// wrong nonce length, or empty ciphertext).
final class MalformedKitchenSpoolEnvelopeException
    extends KitchenSpoolCryptoException {
  const MalformedKitchenSpoolEnvelopeException()
    : super('Kitchen spool envelope is malformed');
}

/// The envelope declares a version this build does not understand.
final class UnknownKitchenSpoolEnvelopeVersionException
    extends KitchenSpoolCryptoException {
  const UnknownKitchenSpoolEnvelopeVersionException()
    : super('Kitchen spool envelope version is not supported');
}

/// Authentication failed: tampered ciphertext, a wrong key, or any AAD
/// mismatch (the three are deliberately indistinguishable — GCM collapses
/// them, and distinguishing would leak which field an attacker got right).
final class KitchenSpoolDecryptionFailedException
    extends KitchenSpoolCryptoException {
  const KitchenSpoolDecryptionFailedException()
    : super('Kitchen spool payload failed authentication');
}

/// The bounded crypto contract for the kitchen spool. Implementations must be
/// fail-closed: no plaintext fallback of any kind.
abstract interface class KitchenSpoolCipher {
  /// The envelope version this cipher writes.
  int get encryptionVersion;

  /// Encrypts [plaintext] bound to [aad] with a fresh random nonce, returning
  /// the versioned envelope blob.
  Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required KitchenSpoolAad aad,
    required SecretValue key,
  });

  /// Decrypts an [envelope] previously produced by [encrypt], recomputing the
  /// binding from [aad]. Throws a [KitchenSpoolCryptoException] subtype on
  /// any malformed/unknown/tampered/mismatched input.
  Future<Uint8List> decrypt({
    required Uint8List envelope,
    required KitchenSpoolAad aad,
    required SecretValue key,
  });
}

/// AES-256-GCM implementation over `package:cryptography`.
final class AesGcmKitchenSpoolCipher implements KitchenSpoolCipher {
  AesGcmKitchenSpoolCipher();

  static const int _version = 1;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const int _keyLength = 32;
  static const List<int> _magic = [0x52, 0x4B, 0x53, 0x31]; // 'RKS1'
  static const int _headerLength = 4 + 1 + 1 + _nonceLength; // 18

  final AesGcm _algorithm = AesGcm.with256bits();

  @override
  int get encryptionVersion => _version;

  @override
  Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required KitchenSpoolAad aad,
    required SecretValue key,
  }) async {
    if (plaintext.isEmpty) {
      // v1 has no valid empty payload; refusing here keeps the envelope
      // contract symmetrical with decrypt's empty-ciphertext rejection.
      throw const MalformedKitchenSpoolEnvelopeException();
    }
    final secretKey = SecretKey(_keyBytes(key));
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad.encode(),
    );
    assert(box.nonce.length == _nonceLength);
    assert(box.mac.bytes.length == _tagLength);
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_version)
      ..addByte(_nonceLength)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  @override
  Future<Uint8List> decrypt({
    required Uint8List envelope,
    required KitchenSpoolAad aad,
    required SecretValue key,
  }) async {
    // Shape checks first (typed, fail-closed) — an envelope must at least
    // hold the header, one ciphertext byte and the full tag.
    if (envelope.length < _headerLength + 1 + _tagLength) {
      throw const MalformedKitchenSpoolEnvelopeException();
    }
    for (var i = 0; i < _magic.length; i++) {
      if (envelope[i] != _magic[i]) {
        throw const MalformedKitchenSpoolEnvelopeException();
      }
    }
    if (envelope[4] != _version) {
      throw const UnknownKitchenSpoolEnvelopeVersionException();
    }
    if (envelope[5] != _nonceLength) {
      throw const MalformedKitchenSpoolEnvelopeException();
    }
    final nonce = envelope.sublist(6, 6 + _nonceLength);
    final cipherText = envelope.sublist(
      _headerLength,
      envelope.length - _tagLength,
    );
    final tag = envelope.sublist(envelope.length - _tagLength);
    if (cipherText.isEmpty) {
      throw const MalformedKitchenSpoolEnvelopeException();
    }
    final secretKey = SecretKey(_keyBytes(key));
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: secretKey,
        aad: aad.encode(),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const KitchenSpoolDecryptionFailedException();
    }
  }

  /// Decodes the stored key through the audited crypto boundary and enforces
  /// the exact AES-256 key length.
  static Uint8List _keyBytes(SecretValue key) {
    final Uint8List bytes;
    try {
      bytes = decodeKitchenSpoolKey(key);
    } on FormatException {
      throw const InvalidKitchenSpoolKeyException();
    }
    if (bytes.length != _keyLength) {
      throw const InvalidKitchenSpoolKeyException();
    }
    return bytes;
  }
}

/// Decodes a [SecretValue]-wrapped kitchen-spool key (base64url of the raw
/// 32 key bytes) at the crypto boundary — the SINGLE greppable decode site.
/// Throws [FormatException] when the stored value is not valid base64url.
Uint8List decodeKitchenSpoolKey(SecretValue key) {
  var encoded = key.revealForCryptoBoundary();
  // Normalize missing padding (the encoder strips it); reject impossible
  // lengths instead of guessing.
  switch (encoded.length % 4) {
    case 2:
      encoded = '$encoded==';
    case 3:
      encoded = '$encoded=';
    case 1:
      throw const FormatException('Invalid base64url length');
  }
  return base64Url.decode(encoded);
}
