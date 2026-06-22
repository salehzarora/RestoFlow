/// The injected session seam for sync calls (RF-063, approved decision A1).
///
/// RF-063 deliberately does NOT build login / device pairing / PIN-entry. The
/// authenticated `SupabaseClient` and these two identifiers are supplied from
/// outside (a later auth/identity ticket); this package only consumes them.
///
/// Both ids are server-resolved scope keys for `app.sync_pull`: the org/branch/
/// role are derived from the PIN session server-side and are NEVER trusted from
/// the client payload (see supabase/migrations RF-057).
class SyncSession {
  const SyncSession({required this.pinSessionId, required this.deviceId});

  /// The human PIN session id (`p_pin_session_id`).
  final String pinSessionId;

  /// The paired device id (`p_device_id`).
  final String deviceId;

  @override
  bool operator ==(Object other) =>
      other is SyncSession &&
      other.pinSessionId == pinSessionId &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(pinSessionId, deviceId);
}
