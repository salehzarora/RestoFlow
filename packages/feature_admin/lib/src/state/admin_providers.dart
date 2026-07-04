import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

import '../data/admin_repository.dart';
import '../models/admin_failure.dart';
import '../models/admin_scope.dart';
import '../models/admin_user.dart';
import '../models/device_models.dart';
import '../models/settings_models.dart';

/// The active administration scope (RF-108 membership). MUST be overridden at the
/// surface root — unoverridden it throws (deny-by-default; never a guessed scope).
final adminScopeProvider = Provider<AdminScope>((ref) {
  throw UnimplementedError(
    'adminScopeProvider must be overridden with the active AdminScope (RF-108).',
  );
});

/// The administration repository. MUST be overridden with the demo store (today)
/// or an RPC-backed repository over the RF-112 public RPCs (deferred).
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  throw UnimplementedError('adminRepositoryProvider must be overridden.');
});

/// The settings bundle for the active scope (reloads on a successful save).
final adminSettingsProvider = FutureProvider.autoDispose<SettingsBundle>((
  ref,
) async {
  final result = await ref.watch(adminRepositoryProvider).loadSettings();
  return result.fold((v) => v, (f) => throw _AdminLoadError(f));
}, dependencies: [adminRepositoryProvider]);

/// The membership list for the active scope.
final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((
  ref,
) async {
  final result = await ref.watch(adminRepositoryProvider).loadUsers();
  return result.fold((v) => v, (f) => throw _AdminLoadError(f));
}, dependencies: [adminRepositoryProvider]);

/// The device list for the active scope.
final adminDevicesProvider = FutureProvider.autoDispose<List<AdminDevice>>((
  ref,
) async {
  final result = await ref.watch(adminRepositoryProvider).loadDevices();
  return result.fold((v) => v, (f) => throw _AdminLoadError(f));
}, dependencies: [adminRepositoryProvider]);

/// Wraps an [AdminFailure] thrown out of a FutureProvider so the UI can render a
/// typed error/permission-denied state.
class _AdminLoadError implements Exception {
  _AdminLoadError(this.failure);
  final AdminFailure failure;
}

/// Maps any FutureProvider error back to an [AdminFailure] for the state views.
AdminFailure adminFailureOf(Object error) =>
    error is _AdminLoadError ? error.failure : const AdminTransient();

/// Runs admin write actions, invalidating the relevant loader on success (the UI
/// shows the [AdminFailure] on failure). Writes are non-optimistic.
class AdminController {
  AdminController(this._ref);
  final Ref _ref;

  AdminRepository get _repo => _ref.read(adminRepositoryProvider);

  Future<AdminResult<T>> _run<T>(
    Future<AdminResult<T>> Function() op,
    ProviderOrFamily toInvalidate,
  ) async {
    final outcome = await op();
    if (outcome.isSuccess) _ref.invalidate(toInvalidate);
    return outcome;
  }

  // settings
  Future<AdminResult<OrganizationSettings>> updateOrganizationSettings({
    required String defaultCurrency,
    String? countryCode,
    required String status,
  }) => _run(
    () => _repo.updateOrganizationSettings(
      defaultCurrency: defaultCurrency,
      countryCode: countryCode,
      status: status,
    ),
    adminSettingsProvider,
  );

  Future<AdminResult<RestaurantSettings>> updateRestaurantSettings({
    required String name,
    String? currencyOverride,
    String? timezone,
    required String status,
  }) => _run(
    () => _repo.updateRestaurantSettings(
      name: name,
      currencyOverride: currencyOverride,
      timezone: timezone,
      status: status,
    ),
    adminSettingsProvider,
  );

  Future<AdminResult<BranchSettings>> updateBranchSettings({
    required String name,
    String? address,
    String? timezone,
    String? receiptPrefix,
    required String status,
  }) => _run(
    () => _repo.updateBranchSettings(
      name: name,
      address: address,
      timezone: timezone,
      receiptPrefix: receiptPrefix,
      status: status,
    ),
    adminSettingsProvider,
  );

  // users
  Future<AdminResult<AdminUser>> grantMembership({
    required String displayName,
    required String email,
    required MembershipRole role,
  }) => _run(
    () => _repo.grantMembership(
      displayName: displayName,
      email: email,
      role: role,
    ),
    adminUsersProvider,
  );

  Future<AdminResult<AdminUser>> updateRole({
    required String userId,
    required MembershipRole newRole,
  }) => _run(
    () => _repo.updateRole(userId: userId, newRole: newRole),
    adminUsersProvider,
  );

  Future<AdminResult<AdminUser>> revokeMembership(String membershipId) =>
      _run(() => _repo.revokeMembership(membershipId), adminUsersProvider);

  /// See [AdminRepository.supportsGrant].
  bool get supportsGrant => _repo.supportsGrant;

  // devices
  Future<AdminResult<AdminDevice>> createDevice({
    required String label,
    required String deviceType,
  }) => _run(
    () => _repo.createDevice(label: label, deviceType: deviceType),
    adminDevicesProvider,
  );

  Future<AdminResult<EnrollmentCodeIssued>> issueEnrollmentCode(
    String deviceId,
  ) => _run(() => _repo.issueEnrollmentCode(deviceId), adminDevicesProvider);

  Future<AdminResult<AdminDevice>> redeemEnrollmentCode(String deviceId) =>
      _run(() => _repo.redeemEnrollmentCode(deviceId), adminDevicesProvider);

  Future<AdminResult<AdminDevice>> approveDevice(String deviceId) =>
      _run(() => _repo.approveDevice(deviceId), adminDevicesProvider);

  Future<AdminResult<AdminDevice>> activateDevice(String deviceId) =>
      _run(() => _repo.activateDevice(deviceId), adminDevicesProvider);

  Future<AdminResult<SessionStarted>> startDeviceSession(String deviceId) =>
      _run(() => _repo.startDeviceSession(deviceId), adminDevicesProvider);

  Future<AdminResult<AdminDevice>> revokeDevice(String deviceId) =>
      _run(() => _repo.revokeDevice(deviceId), adminDevicesProvider);

  /// See [AdminRepository.supportsManualLifecycle].
  bool get supportsManualLifecycle => _repo.supportsManualLifecycle;
}

/// The admin write controller for the active scope.
final adminControllerProvider = Provider<AdminController>(
  (ref) => AdminController(ref),
  dependencies: [
    adminRepositoryProvider,
    adminSettingsProvider,
    adminUsersProvider,
    adminDevicesProvider,
  ],
);

/// Builds the [ProviderScope] overrides wiring the admin feature to a concrete
/// scope + repository. The dashboard uses this for the demo store; a real wiring
/// (RPC repository over an authenticated transport) is deferred.
List<Override> adminFeatureOverrides({
  required AdminScope scope,
  required AdminRepository repository,
}) => [
  adminScopeProvider.overrideWithValue(scope),
  adminRepositoryProvider.overrideWithValue(repository),
];
