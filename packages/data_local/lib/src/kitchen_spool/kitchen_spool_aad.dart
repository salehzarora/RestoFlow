/// KITCHEN-MODE-001C2A — canonical Authenticated Associated Data for the
/// encrypted kitchen-spool payload blob.
///
/// The AAD cryptographically BINDS a blob to the exact dispatch identity and
/// tenant/device scope it was written for: moving a ciphertext to another
/// row, organization, restaurant, branch, device, or encryption version makes
/// decryption fail with an authentication error. The AAD itself is NOT
/// secret — every bound field is a plaintext metadata column and the AAD is
/// recomputed from those columns at decrypt time; it is never persisted as
/// secret data.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The fixed, ordered, canonical AAD for one kitchen-spool blob.
///
/// Encoding (deliberately NOT a naive delimiter-joined string, which would be
/// ambiguous under crafted IDs): a fixed-order sequence of length-prefixed
/// UTF-8 fields —
///
/// ```text
/// magic 'RKAD' (4 bytes)
/// uint32 BE encryptionVersion
/// for each of [dispatchId, organizationId, restaurantId, branchId, deviceId]
///   in THIS fixed order:
///     uint32 BE byteLength, then that many UTF-8 bytes
/// ```
///
/// Every field is required and non-empty; IDs are normalized (trimmed,
/// lowercased) to match the repository's UUID conventions before binding.
final class KitchenSpoolAad {
  KitchenSpoolAad({
    required String dispatchId,
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required String deviceId,
    required this.encryptionVersion,
  }) : dispatchId = _normalizeId(dispatchId, 'dispatchId'),
       organizationId = _normalizeId(organizationId, 'organizationId'),
       restaurantId = _normalizeId(restaurantId, 'restaurantId'),
       branchId = _normalizeId(branchId, 'branchId'),
       deviceId = _normalizeId(deviceId, 'deviceId') {
    if (encryptionVersion <= 0) {
      throw ArgumentError.value(
        encryptionVersion,
        'encryptionVersion',
        'must be a positive version number',
      );
    }
  }

  final String dispatchId;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;
  final int encryptionVersion;

  static const List<int> _magic = [0x52, 0x4B, 0x41, 0x44]; // 'RKAD'

  static String _normalizeId(String raw, String field) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) {
      throw ArgumentError.value(raw, field, 'required AAD field is empty');
    }
    return v;
  }

  /// The canonical bytes handed to AES-GCM as associated data.
  Uint8List encode() {
    final builder = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(_uint32be(encryptionVersion));
    for (final field in [
      dispatchId,
      organizationId,
      restaurantId,
      branchId,
      deviceId,
    ]) {
      final bytes = utf8.encode(field);
      builder
        ..add(_uint32be(bytes.length))
        ..add(bytes);
    }
    return builder.toBytes();
  }

  static Uint8List _uint32be(int value) {
    final b = ByteData(4)..setUint32(0, value);
    return b.buffer.asUint8List();
  }

  @override
  String toString() =>
      'KitchenSpoolAad(dispatch: $dispatchId, org: $organizationId, '
      'v$encryptionVersion)'; // Non-secret metadata only.
}
