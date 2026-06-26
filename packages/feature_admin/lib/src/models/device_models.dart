/// The RF-112 device pairing lifecycle (DOMAIN_MODEL §3.4 / STATE_MACHINES §9 /
/// D-033/D-034). The forward path is:
///   codeIssued → pending → paired → active   ( + suspended/revoked/codeExpired/rejected )
/// where approve_device = pending→paired, activate_device = paired→active, and
/// pending→active is FORBIDDEN.
enum DeviceLifecycleStatus {
  none('none'), // a device with no pairing yet (just created)
  codeIssued('code_issued'),
  pending('pending'),
  paired('paired'),
  active('active'),
  suspended('suspended'),
  revoked('revoked'),
  codeExpired('code_expired'),
  rejected('rejected');

  const DeviceLifecycleStatus(this.wire);
  final String wire;
}

/// `pos` or `kds` (the existing `devices.device_type` set).
const List<String> kDeviceTypes = ['pos', 'kds'];

/// One device + its current pairing state, shown on the Devices screen.
class AdminDevice {
  const AdminDevice({
    required this.id,
    required this.label,
    required this.deviceType,
    required this.branchLabel,
    required this.status,
    this.pairingId,
    this.hasOpenSession = false,
  });

  final String id;
  final String label;
  final String deviceType; // pos | kds
  final String branchLabel;

  /// The current pairing lifecycle status (or [DeviceLifecycleStatus.none]).
  final DeviceLifecycleStatus status;

  /// The current pairing id (null when [status] is none).
  final String? pairingId;

  /// True once a device session has been started (demo flag).
  final bool hasOpenSession;

  AdminDevice copyWith({
    DeviceLifecycleStatus? status,
    String? pairingId,
    bool? hasOpenSession,
  }) => AdminDevice(
    id: id,
    label: label,
    deviceType: deviceType,
    branchLabel: branchLabel,
    status: status ?? this.status,
    pairingId: pairingId ?? this.pairingId,
    hasOpenSession: hasOpenSession ?? this.hasOpenSession,
  );
}

/// The one-time enrollment code result (issue_device_enrollment_code). The
/// plaintext [code] is shown to the caller EXACTLY ONCE; the store keeps only a
/// hash/ref. [expiresInLabel] is a short human TTL hint.
class EnrollmentCodeIssued {
  const EnrollmentCodeIssued({
    required this.deviceId,
    required this.pairingId,
    required this.code,
    required this.expiresInLabel,
  });

  final String deviceId;
  final String pairingId;
  final String code;
  final String expiresInLabel;
}

/// The one-time device session token result (start_device_session). The plaintext
/// [token] is returned EXACTLY ONCE; the store keeps only a hash/ref.
class SessionStarted {
  const SessionStarted({
    required this.deviceId,
    required this.sessionId,
    required this.token,
  });

  final String deviceId;
  final String sessionId;
  final String token;
}
