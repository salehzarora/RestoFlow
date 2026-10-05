import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';

void main() {
  final now = DateTime.utc(2035, 1, 1);
  AdminDevice device({
    DateTime? expiresAt,
    DeviceLifecycleStatus status = DeviceLifecycleStatus.active,
    bool open = true,
    bool knownClock = true,
  }) => AdminDevice(
    id: 'device',
    label: 'POS',
    deviceType: 'pos',
    branchLabel: 'Branch',
    status: status,
    hasOpenSession: open,
    sessionExpiresAt: expiresAt,
    serverNow: knownClock ? now : null,
    lastSeenAt: now,
  );

  test('unexpired server-confirmed session is active', () {
    final value = device(expiresAt: now.add(const Duration(seconds: 1)));
    expect(value.isSessionActive, isTrue);
    expect(value.isSessionExpired, isFalse);
  });

  test('exact expiry boundary is expired even if the flag is stale', () {
    final value = device(expiresAt: now);
    expect(value.isSessionActive, isFalse);
    expect(value.isSessionExpired, isTrue);
  });

  test('past expiry stays expired', () {
    final value = device(
      expiresAt: now.subtract(const Duration(days: 1)),
      open: false,
    );
    expect(value.isSessionActive, isFalse);
    expect(value.isSessionExpired, isTrue);
  });

  test('legacy NULL is active only with the server flag', () {
    expect(device().isSessionActive, isTrue);
    expect(device(open: false).isSessionActive, isFalse);
    expect(device(open: false).isSessionExpired, isFalse);
  });

  test('future expiry alone does not imply an active session', () {
    expect(
      device(
        expiresAt: now.add(const Duration(days: 1)),
        open: false,
      ).isSessionActive,
      isFalse,
    );
  });

  test('unknown server time cannot classify a finite expiry', () {
    final value = device(expiresAt: now, knownClock: false);
    expect(value.isSessionActive, isFalse);
    expect(value.isSessionExpired, isFalse);
  });

  test('revoked and never-paired devices are not labelled expired', () {
    for (final status in [
      DeviceLifecycleStatus.none,
      DeviceLifecycleStatus.revoked,
    ]) {
      expect(
        device(expiresAt: now, status: status, open: false).isSessionExpired,
        isFalse,
      );
    }
  });

  test('copyWith preserves server session metadata', () {
    final copied = device(expiresAt: now).copyWith(hasOpenSession: false);
    expect(copied.sessionExpiresAt, now);
    expect(copied.serverNow, now);
    expect(copied.lastSeenAt, now);
  });
}
