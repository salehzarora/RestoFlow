/// A device/station pairing context, scoped to an organization + branch (and,
/// when known, a restaurant + station) — the shared model consumed by the
/// dashboard, POS, and KDS (RF-152 foundation, extended for RF-153 pairing).
///
/// Present ONLY when a real device has been paired against the backend. RestoFlow
/// NEVER fabricates a paired device — [isPaired] is true only when a real
/// [deviceId] is present. Pure-Dart (no Flutter), so it is reusable across apps
/// and unit-testable. It carries NO device secret / session token — those are
/// handled per backend policy and never stored or logged here. The
/// [deviceSessionId] is a server-minted session HANDLE (not the token): it is
/// held in memory only, re-derived on every launch via `restore_device_session`,
/// and never persisted client-side (RF-161).
class DeviceContext {
  const DeviceContext({
    required this.organizationId,
    required this.branchId,
    this.restaurantId,
    this.stationId,
    this.stationType,
    this.deviceId,
    this.deviceType,
    this.deviceSessionId,
    this.displayName,
    this.pairedAt,
  });

  final String organizationId;
  final String branchId;

  /// The restaurant scope, when known.
  final String? restaurantId;

  /// The bound station id, or null when not yet bound to a station.
  final String? stationId;

  /// The app role the station serves: `pos` or `kds` (when known).
  final String? stationType;

  /// The paired device id, or null when no device is paired yet.
  final String? deviceId;

  /// The device kind: `pos` or `kds` (when known).
  final String? deviceType;

  /// The ACTIVE device session id (`p_device_session_id` for
  /// `start_pin_session`), or null. A capability HANDLE, not the token: held in
  /// memory only, re-derived each launch via restore, never persisted (RF-161).
  final String? deviceSessionId;

  /// A human display name for the device (non-secret), or null.
  final String? displayName;

  /// When the device was paired (server-provided), or null.
  final DateTime? pairedAt;

  /// True ONLY when a real (non-empty) device id is present — never fabricated.
  bool get isPaired => deviceId != null && deviceId!.isNotEmpty;

  /// Whether this context belongs to the given selected org/branch scope.
  /// Used to reject a device context that does not match the active selection.
  bool matchesScope({
    required String organizationId,
    required String branchId,
  }) => this.organizationId == organizationId && this.branchId == branchId;

  DeviceContext copyWith({
    String? stationId,
    String? stationType,
    String? deviceId,
    String? deviceType,
    String? deviceSessionId,
    String? displayName,
    DateTime? pairedAt,
  }) => DeviceContext(
    organizationId: organizationId,
    branchId: branchId,
    restaurantId: restaurantId,
    stationId: stationId ?? this.stationId,
    stationType: stationType ?? this.stationType,
    deviceId: deviceId ?? this.deviceId,
    deviceType: deviceType ?? this.deviceType,
    deviceSessionId: deviceSessionId ?? this.deviceSessionId,
    displayName: displayName ?? this.displayName,
    pairedAt: pairedAt ?? this.pairedAt,
  );
}
