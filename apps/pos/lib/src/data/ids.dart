import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A seam for generating client-side identifiers, so tests can inject a
/// deterministic generator while production uses a CSPRNG.
abstract class ClientIdGenerator {
  /// A fresh, client-generated identifier.
  String newId();
}

/// Generates an RFC-4122 v4 UUID from a CSPRNG (mirrors the auth_identity
/// idempotency-key generator and feature_menu's image-id generator; no external
/// `uuid` dependency). Used for the client-generated `order_id` /
/// `local_operation_id` a REAL `order.submit` carries to `public.sync_push`
/// (RF-126 / DECISION D-010 / D-022) - never a demo label.
class RandomClientIdGenerator implements ClientIdGenerator {
  RandomClientIdGenerator([Random? random])
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    String hex(int index) => bytes[index].toRadixString(16).padLeft(2, '0');
    return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
        '${hex(4)}${hex(5)}-'
        '${hex(6)}${hex(7)}-'
        '${hex(8)}${hex(9)}-'
        '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
  }
}

/// A deterministic [ClientIdGenerator] for tests: returns the supplied ids in
/// order, repeating the last once exhausted.
class FixedClientIdGenerator implements ClientIdGenerator {
  FixedClientIdGenerator(this._ids) : assert(_ids.length > 0);

  final List<String> _ids;
  int _index = 0;

  @override
  String newId() {
    final id = _ids[_index];
    if (_index < _ids.length - 1) _index++;
    return id;
  }
}

/// The client id generator used to mint real-mode `order_id` /
/// `local_operation_id` UUIDs. Defaults to a CSPRNG; tests override it for
/// determinism.
final clientIdGeneratorProvider = Provider<ClientIdGenerator>(
  (ref) => RandomClientIdGenerator(),
);
