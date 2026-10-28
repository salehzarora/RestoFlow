import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// Ephemeral evidence of an inactivity-only UI lock, not an authorization grant.
/// The native owner must independently confirm its already-bound delegation.
/// Nothing here persists, renews authority, or permits a privileged POS action.
class BackgroundAlertInactivityLock {
  BackgroundAlertInactivityLock._({
    required this.identity,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.deviceSessionId,
    required this.pinSessionId,
    required this.employeeProfileId,
    required this.validUntil,
    required this.nativeConfirmed,
    required Object transition,
  }) : _transition = transition;

  final String identity;
  final String organizationId;
  final String? restaurantId;
  final String branchId;
  final String deviceId;
  final String deviceSessionId;
  final String pinSessionId;
  final String employeeProfileId;
  final DateTime validUntil;
  final bool nativeConfirmed;
  final Object _transition;

  bool matchesContext(DeviceContext? context) =>
      context != null &&
      context.isPaired &&
      context.deviceType == 'pos' &&
      context.organizationId == organizationId &&
      context.restaurantId == restaurantId &&
      context.branchId == branchId &&
      context.deviceId == deviceId &&
      context.deviceSessionId == deviceSessionId;

  bool validAt(DateTime now) => now.isBefore(validUntil);

  BackgroundAlertInactivityLock _confirmed() => BackgroundAlertInactivityLock._(
    identity: identity,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    deviceId: deviceId,
    deviceSessionId: deviceSessionId,
    pinSessionId: pinSessionId,
    employeeProfileId: employeeProfileId,
    validUntil: validUntil,
    nativeConfirmed: true,
    transition: _transition,
  );
}

class BackgroundAlertInactivityLockController
    extends Notifier<BackgroundAlertInactivityLock?> {
  @override
  BackgroundAlertInactivityLock? build() => null;

  BackgroundAlertInactivityLock begin({
    required String identity,
    required String organizationId,
    required String? restaurantId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    required String pinSessionId,
    required String employeeProfileId,
    required DateTime validUntil,
  }) {
    final proof = BackgroundAlertInactivityLock._(
      identity: identity,
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      deviceId: deviceId,
      deviceSessionId: deviceSessionId,
      pinSessionId: pinSessionId,
      employeeProfileId: employeeProfileId,
      validUntil: validUntil,
      nativeConfirmed: false,
      transition: Object(),
    );
    state = proof;
    return proof;
  }

  bool isCurrent(BackgroundAlertInactivityLock proof) =>
      identical(state?._transition, proof._transition);

  bool confirm(BackgroundAlertInactivityLock proof) {
    if (!isCurrent(proof)) return false;
    state = proof._confirmed();
    return true;
  }

  void clear() => state = null;

  bool clearIfCurrent(BackgroundAlertInactivityLock proof) {
    if (!isCurrent(proof)) return false;
    clear();
    return true;
  }
}

final backgroundAlertInactivityLockProvider =
    NotifierProvider<
      BackgroundAlertInactivityLockController,
      BackgroundAlertInactivityLock?
    >(BackgroundAlertInactivityLockController.new);
