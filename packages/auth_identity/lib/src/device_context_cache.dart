/// [POS-OFFLINE-OPERATIONS-002] Pass A — the DURABLE pairing-scope cache.
///
/// A cold boot with the network fully down must be able to prove "this device
/// was really paired here" WITHOUT a server round-trip, or the cashier can
/// never reach the offline cached menu. The evidence is a schema-versioned
/// JSON record of the last SERVER-VERIFIED [DeviceContext] (ids + the
/// device-session HANDLE + display fields — NEVER the bearer token or a PIN),
/// written by the pairing repository at exactly the two server-verified
/// moments (pair success, restore success) and stored NEXT TO the device
/// secret in the same secure store.
///
/// FAIL CLOSED everywhere: an unreadable/corrupt record, an unknown schema
/// version, a record whose `device_id` does not match the stored secret's, or
/// a record missing its tenant scope all decode to `null` (treated as absent)
/// — and the caller then behaves exactly as if no evidence existed. The
/// unreadable bytes are NEVER auto-deleted (a record we cannot read is not a
/// record we may destroy), and reading the cache never touches the token.
///
/// NOTE on the device-session id: it is a server-minted capability HANDLE
/// (`p_device_session_id` for `start_pin_session`), not the bearer token. The
/// offline session restore (C6) refuses any stored PIN session whose
/// `device_session_id` differs, so the handle MUST survive a cold boot for
/// offline continuity to work at all — which is precisely why it is part of
/// this record (approved Pass A design; the token itself never is).
library;

import 'dart:convert';

import 'device_context.dart';

/// The current schema version of the cached device-context record.
const int kCachedDeviceContextVersion = 1;

/// Encodes [context] as the v1 cached-record JSON. Ids + handle + display
/// fields only — no token, no PIN material.
String encodeCachedDeviceContext(DeviceContext context) =>
    jsonEncode(<String, Object?>{
      'v': kCachedDeviceContextVersion,
      'organization_id': context.organizationId,
      'branch_id': context.branchId,
      if (context.restaurantId != null) 'restaurant_id': context.restaurantId,
      if (context.stationId != null) 'station_id': context.stationId,
      if (context.stationType != null) 'station_type': context.stationType,
      if (context.deviceId != null) 'device_id': context.deviceId,
      if (context.deviceType != null) 'device_type': context.deviceType,
      if (context.deviceSessionId != null)
        'device_session_id': context.deviceSessionId,
      if (context.displayName != null) 'display_name': context.displayName,
      if (context.pairedAt != null)
        'paired_at': context.pairedAt!.toUtc().toIso8601String(),
    });

/// Decodes a cached-record string back into a [DeviceContext], or `null`
/// (treated as ABSENT — fail closed) when the record is unreadable, carries an
/// unknown schema version, names a different device than [expectedDeviceId]
/// (the stored secret's device id), or is missing its tenant scope.
DeviceContext? decodeCachedDeviceContext(
  String raw, {
  required String expectedDeviceId,
}) {
  if (expectedDeviceId.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  if (decoded['v'] != kCachedDeviceContextVersion) return null;
  final deviceId = (decoded['device_id'] ?? '').toString();
  if (deviceId.isEmpty || deviceId != expectedDeviceId) return null;
  final organizationId = (decoded['organization_id'] ?? '').toString();
  final branchId = (decoded['branch_id'] ?? '').toString();
  if (organizationId.isEmpty || branchId.isEmpty) return null;
  DateTime? pairedAt;
  final rawPairedAt = decoded['paired_at'];
  if (rawPairedAt is String) pairedAt = DateTime.tryParse(rawPairedAt);
  return DeviceContext(
    organizationId: organizationId,
    branchId: branchId,
    restaurantId: decoded['restaurant_id']?.toString(),
    stationId: decoded['station_id']?.toString(),
    stationType: decoded['station_type']?.toString(),
    deviceId: deviceId,
    deviceType: decoded['device_type']?.toString(),
    deviceSessionId: decoded['device_session_id']?.toString(),
    displayName: decoded['display_name']?.toString(),
    pairedAt: pairedAt,
  );
}

/// The cached pairing-scope FACET of a device-session secret store (Pass A).
///
/// Implemented by the same stores that hold the device secret so the record
/// lives (and dies) next to the credential it describes; the pairing
/// repository writes it on every server-verified pair/restore and clears it
/// whenever the server definitively rejects the session. Readers must pass
/// the stored secret's device id — a mismatched or unreadable record reads as
/// absent WITHOUT deleting anything (least destruction; the token is never
/// touched by cache operations).
abstract interface class DeviceContextCacheStore {
  /// Persists (overwriting any prior) the server-verified pairing scope.
  Future<void> writeCachedContext(DeviceContext context);

  /// Reads the cached scope, or null when absent/unreadable/mismatched
  /// (never throws, never deletes, never reads the token).
  Future<DeviceContext?> readCachedContext({required String expectedDeviceId});

  /// Clears the cached scope only (idempotent; the secret is untouched).
  Future<void> clearCachedContext();
}
