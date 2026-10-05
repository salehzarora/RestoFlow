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

/// `pos`, `kds` or `kiosk` — the `devices.device_type` set the server
/// enforces (kiosk added by KIOSK-001; the customer self-service surface).
const List<String> kDeviceTypes = ['pos', 'kds', 'kiosk'];

/// A monotonic clock owned by a fetched snapshot, never by a mounted tile.
/// Start it before the request so network latency cannot extend a deadline.
class AdminDeviceSnapshotClock {
  AdminDeviceSnapshotClock({Duration Function()? elapsed})
    : _elapsed = elapsed ?? _startStopwatch();

  final Duration Function() _elapsed;
  Duration get elapsed => _elapsed();

  static Duration Function() _startStopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }
}

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
    this.sessionExpiresAt,
    this.lastSeenAt,
    this.serverNow,
    this.codeExpiresAt,
    this.snapshotClock,
  });

  final String id;
  final String label;
  final String deviceType; // pos | kds
  final String branchLabel;

  /// The current pairing lifecycle status (or [DeviceLifecycleStatus.none]).
  final DeviceLifecycleStatus status;

  /// The current pairing id (null when [status] is none).
  final String? pairingId;

  /// Server-confirmed active, unrevoked, unexpired session (or demo flag).
  final bool hasOpenSession;

  /// Expiry of the selected session; null also supports legacy sessions.
  final DateTime? sessionExpiresAt;
  final DateTime? lastSeenAt;

  /// Server time when the session metadata was read; never the browser clock.
  final DateTime? serverNow;
  final DateTime? codeExpiresAt;
  final AdminDeviceSnapshotClock? snapshotClock;

  DateTime? get estimatedServerNow =>
      serverNow?.add(snapshotClock?.elapsed ?? Duration.zero);

  bool get isCodeExpired =>
      status == DeviceLifecycleStatus.codeIssued &&
      codeExpiresAt != null &&
      estimatedServerNow != null &&
      !codeExpiresAt!.isAfter(estimatedServerNow!);

  bool get isSessionActive =>
      hasOpenSession &&
      (sessionExpiresAt == null ||
          (estimatedServerNow != null &&
              sessionExpiresAt!.isAfter(estimatedServerNow!)));

  /// A missing session, or a revoked pairing, is not an expired session.
  bool get isSessionExpired =>
      status == DeviceLifecycleStatus.active &&
      sessionExpiresAt != null &&
      estimatedServerNow != null &&
      !sessionExpiresAt!.isAfter(estimatedServerNow!);

  AdminDevice copyWith({
    DeviceLifecycleStatus? status,
    String? pairingId,
    bool? hasOpenSession,
    DateTime? sessionExpiresAt,
    DateTime? lastSeenAt,
    DateTime? serverNow,
    DateTime? codeExpiresAt,
  }) => AdminDevice(
    id: id,
    label: label,
    deviceType: deviceType,
    branchLabel: branchLabel,
    status: status ?? this.status,
    pairingId: pairingId ?? this.pairingId,
    hasOpenSession: hasOpenSession ?? this.hasOpenSession,
    sessionExpiresAt: sessionExpiresAt ?? this.sessionExpiresAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    serverNow: serverNow ?? this.serverNow,
    codeExpiresAt: codeExpiresAt ?? this.codeExpiresAt,
    snapshotClock: snapshotClock,
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
