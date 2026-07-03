import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';

import '../models/admin_failure.dart';
import '../models/admin_scope.dart';
import '../models/admin_user.dart';
import '../models/device_models.dart';
import '../models/role_rank.dart';
import '../models/settings_models.dart';
import 'admin_repository.dart';

/// A labelled, in-memory administration store (RF-113). It backs the dashboard
/// admin surfaces in demo mode and the widget tests, faithfully mirroring the
/// RF-112 contracts: the **role-rank guard** (D-033), the **device lifecycle**
/// (D-033/D-034: code_issued→pending→paired→active; pending→active forbidden),
/// and **return-once secrets** (enrollment code + session token returned once,
/// only a hash/ref retained). No Supabase, no real persistence — the real RPC
/// wiring is deferred to the auth/org-context bridge. A fresh instance per
/// session keeps demo edits isolated.
class DemoAdminStore implements AdminRepository {
  DemoAdminStore({required this.scope}) {
    _seedUsers();
    _seedDevices();
  }

  final AdminScope scope;

  MembershipRole get _actor => scope.actingRole;

  late SettingsBundle _settings = SettingsBundle(
    organization: OrganizationSettings(
      defaultCurrency: scope.currencyCode,
      countryCode: 'US',
      status: 'active',
    ),
    restaurant: RestaurantSettings(
      name: scope.restaurantName ?? 'Restaurant',
      currencyOverride: null,
      timezone: 'America/New_York',
      status: 'active',
    ),
    branch: BranchSettings(
      name: scope.branchName ?? 'Branch',
      address: '128 Main Street, Suite 4',
      timezone: 'America/New_York',
      receiptPrefix: 'MN-',
      status: 'active',
    ),
  );

  final List<AdminUser> _users = [];
  final List<AdminDevice> _devices = [];
  int _seq = 0;
  int _secretSeq = 0;

  String _id(String prefix) => '$prefix-${(++_seq).toString().padLeft(4, '0')}';

  /// A demo one-time secret (never crypto): unique per call; the store keeps only
  /// a redacted ref, never the plaintext.
  String _oneTimeSecret(String prefix) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final n = ++_secretSeq;
    final buf = StringBuffer(prefix);
    var v = n * 2654435761 + 1013904223; // a cheap, dart:math-free spreader
    for (var i = 0; i < 12; i++) {
      if (i % 4 == 0) buf.write('-');
      buf.write(alphabet[(v.abs() + i * 17) % alphabet.length]);
      v = v ~/ 7 + n * (i + 3);
    }
    return buf.toString();
  }

  void _seedUsers() {
    final org = scope.organizationName;
    final rest = scope.restaurantName ?? org;
    final branch = scope.branchName ?? rest;
    _users.addAll([
      AdminUser(
        id: 'u-self',
        displayName: 'You (Owner)',
        email: 'owner@olivethyme.test',
        role: MembershipRole.orgOwner,
        scopeLabel: org,
        status: 'active',
        isSelf: true,
      ),
      AdminUser(
        id: 'u-2',
        displayName: 'Dana Reyes',
        email: 'dana@olivethyme.test',
        role: MembershipRole.restaurantOwner,
        scopeLabel: rest,
        status: 'active',
      ),
      AdminUser(
        id: 'u-3',
        displayName: 'Sam Okoro',
        email: 'sam@olivethyme.test',
        role: MembershipRole.manager,
        scopeLabel: branch,
        status: 'active',
      ),
      AdminUser(
        id: 'u-4',
        displayName: 'Priya Nair',
        email: 'priya@olivethyme.test',
        role: MembershipRole.cashier,
        scopeLabel: branch,
        status: 'active',
      ),
      AdminUser(
        id: 'u-5',
        displayName: 'Marco Bianchi',
        email: 'marco@olivethyme.test',
        role: MembershipRole.kitchenStaff,
        scopeLabel: branch,
        status: 'active',
      ),
      AdminUser(
        id: 'u-6',
        displayName: 'Lena Fischer',
        email: 'lena@olivethyme.test',
        role: MembershipRole.accountant,
        scopeLabel: org,
        status: 'revoked',
      ),
    ]);
  }

  void _seedDevices() {
    final branch = scope.branchName ?? scope.restaurantName ?? 'Branch';
    _devices.addAll([
      AdminDevice(
        id: 'd-1',
        label: 'Front Counter POS',
        deviceType: 'pos',
        branchLabel: branch,
        status: DeviceLifecycleStatus.active,
        pairingId: 'p-1',
        hasOpenSession: true,
      ),
      AdminDevice(
        id: 'd-2',
        label: 'Kitchen Display',
        deviceType: 'kds',
        branchLabel: branch,
        status: DeviceLifecycleStatus.paired,
        pairingId: 'p-2',
      ),
      AdminDevice(
        id: 'd-3',
        label: 'Patio Tablet',
        deviceType: 'pos',
        branchLabel: branch,
        status: DeviceLifecycleStatus.pending,
        pairingId: 'p-3',
      ),
      AdminDevice(
        id: 'd-4',
        label: 'Backup POS',
        deviceType: 'pos',
        branchLabel: branch,
        status: DeviceLifecycleStatus.none,
      ),
    ]);
  }

  // ---------------------------------------------------------------- settings ---
  @override
  Future<AdminResult<SettingsBundle>> loadSettings() async =>
      Success(_settings);

  String? _validateCurrency(String raw) {
    final v = raw.trim().toUpperCase();
    return RegExp(r'^[A-Z]{3}$').hasMatch(v) ? null : 'currency';
  }

  @override
  Future<AdminResult<OrganizationSettings>> updateOrganizationSettings({
    required String defaultCurrency,
    String? countryCode,
    required String status,
  }) async {
    // Org-wide settings require org_owner (D-033).
    if (roleRank(_actor) < roleRank(MembershipRole.orgOwner)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    if (_validateCurrency(defaultCurrency) != null) {
      return const Failure(AdminValidation('currency'));
    }
    final cc = countryCode?.trim().toUpperCase();
    if (cc != null && cc.isNotEmpty && !RegExp(r'^[A-Z]{2}$').hasMatch(cc)) {
      return const Failure(AdminValidation('country'));
    }
    if (!kSettingsStatuses.contains(status)) {
      return const Failure(AdminValidation('status'));
    }
    final next = _settings.organization.copyWith(
      defaultCurrency: defaultCurrency.trim().toUpperCase(),
      countryCode: (cc == null || cc.isEmpty) ? null : cc,
      status: status,
    );
    _settings = _settings.copyWith(organization: next);
    return Success(next);
  }

  @override
  Future<AdminResult<RestaurantSettings>> updateRestaurantSettings({
    required String name,
    String? currencyOverride,
    String? timezone,
    required String status,
  }) async {
    if (!canEditSettings(_actor)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    if (name.trim().isEmpty) return const Failure(AdminValidation('name'));
    final co = currencyOverride?.trim().toUpperCase();
    if (co != null && co.isNotEmpty && _validateCurrency(co) != null) {
      return const Failure(AdminValidation('currency'));
    }
    if (!kSettingsStatuses.contains(status)) {
      return const Failure(AdminValidation('status'));
    }
    final next = _settings.restaurant.copyWith(
      name: name.trim(),
      currencyOverride: (co == null || co.isEmpty) ? null : co,
      timezone: timezone?.trim().isEmpty ?? true ? null : timezone!.trim(),
      status: status,
    );
    _settings = _settings.copyWith(restaurant: next);
    return Success(next);
  }

  @override
  Future<AdminResult<BranchSettings>> updateBranchSettings({
    required String name,
    String? address,
    String? timezone,
    String? receiptPrefix,
    required String status,
  }) async {
    if (!canEditSettings(_actor)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    if (name.trim().isEmpty) return const Failure(AdminValidation('name'));
    if (!kSettingsStatuses.contains(status)) {
      return const Failure(AdminValidation('status'));
    }
    final next = _settings.branch.copyWith(
      name: name.trim(),
      address: address?.trim().isEmpty ?? true ? null : address!.trim(),
      timezone: timezone?.trim().isEmpty ?? true ? null : timezone!.trim(),
      receiptPrefix: receiptPrefix?.trim().isEmpty ?? true
          ? null
          : receiptPrefix!.trim(),
      status: status,
    );
    _settings = _settings.copyWith(branch: next);
    return Success(next);
  }

  // ------------------------------------------------------------------- users ---
  @override
  Future<AdminResult<List<AdminUser>>> loadUsers() async =>
      Success(List.unmodifiable(_users));

  @override
  Future<AdminResult<AdminUser>> grantMembership({
    required String displayName,
    required String email,
    required MembershipRole role,
  }) async {
    if (!canManage(_actor)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    if (!canAssignRole(_actor, role)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    if (displayName.trim().isEmpty) {
      return const Failure(AdminValidation('name'));
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      return const Failure(AdminValidation('email'));
    }
    final user = AdminUser(
      id: _id('u'),
      displayName: displayName.trim(),
      email: email.trim(),
      role: role,
      scopeLabel: scope.scopeLabel,
      status: 'active',
    );
    _users.add(user);
    return Success(user);
  }

  @override
  Future<AdminResult<AdminUser>> updateRole({
    required String userId,
    required MembershipRole newRole,
  }) async {
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx < 0) return const Failure(AdminNotFound());
    final user = _users[idx];
    if (user.isSelf) {
      return const Failure(AdminPermissionDenied('self_escalation'));
    }
    if (!canManage(_actor)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    // The actor must strictly outrank BOTH the existing and the new role (D-033).
    if (roleRank(_actor) <= roleRank(user.role) ||
        !canAssignRole(_actor, newRole)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    final next = user.copyWith(role: newRole);
    _users[idx] = next;
    return Success(next);
  }

  // ----------------------------------------------------------------- devices ---
  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async =>
      Success(List.unmodifiable(_devices));

  int _deviceIndex(String deviceId) =>
      _devices.indexWhere((d) => d.id == deviceId);

  AdminResult<AdminDevice>? _manageGuard(String deviceId, int idx) {
    if (!canManage(_actor)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    if (idx < 0) return const Failure(AdminNotFound());
    return null;
  }

  @override
  Future<AdminResult<AdminDevice>> createDevice({
    required String label,
    required String deviceType,
  }) async {
    if (!canManage(_actor)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    if (label.trim().isEmpty) return const Failure(AdminValidation('name'));
    if (!kDeviceTypes.contains(deviceType)) {
      return const Failure(AdminValidation('device_type'));
    }
    final device = AdminDevice(
      id: _id('d'),
      label: label.trim(),
      deviceType: deviceType,
      branchLabel: scope.branchName ?? scope.restaurantName ?? 'Branch',
      status: DeviceLifecycleStatus.none,
    );
    _devices.add(device);
    return Success(device);
  }

  @override
  Future<AdminResult<EnrollmentCodeIssued>> issueEnrollmentCode(
    String deviceId,
  ) async {
    final idx = _deviceIndex(deviceId);
    if (!canManage(_actor)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    if (idx < 0) return const Failure(AdminNotFound());
    final s = _devices[idx].status;
    // Re-enroll only from a non-in-progress state.
    const inProgress = {
      DeviceLifecycleStatus.codeIssued,
      DeviceLifecycleStatus.pending,
      DeviceLifecycleStatus.paired,
      DeviceLifecycleStatus.active,
    };
    if (inProgress.contains(s)) {
      return const Failure(AdminConflict('in_progress'));
    }
    final pairingId = _id('p');
    _devices[idx] = _devices[idx].copyWith(
      status: DeviceLifecycleStatus.codeIssued,
      pairingId: pairingId,
    );
    return Success(
      EnrollmentCodeIssued(
        deviceId: deviceId,
        pairingId: pairingId,
        code: _oneTimeSecret('ENR'),
        expiresInLabel: '15m',
      ),
    );
    // The plaintext code is NOT retained — only the (simulated) hash/ref.
  }

  Future<AdminResult<AdminDevice>> _transition(
    String deviceId,
    DeviceLifecycleStatus from,
    DeviceLifecycleStatus to,
  ) async {
    final idx = _deviceIndex(deviceId);
    final guard = _manageGuard(deviceId, idx);
    if (guard != null) return guard;
    if (_devices[idx].status != from) {
      return const Failure(AdminConflict('bad_state'));
    }
    final next = _devices[idx].copyWith(status: to);
    _devices[idx] = next;
    return Success(next);
  }

  @override
  Future<AdminResult<AdminDevice>> redeemEnrollmentCode(String deviceId) =>
      _transition(
        deviceId,
        DeviceLifecycleStatus.codeIssued,
        DeviceLifecycleStatus.pending,
      );

  @override
  Future<AdminResult<AdminDevice>> approveDevice(String deviceId) =>
      _transition(
        deviceId,
        DeviceLifecycleStatus.pending,
        DeviceLifecycleStatus.paired,
      );

  @override
  Future<AdminResult<AdminDevice>> activateDevice(String deviceId) =>
      _transition(
        deviceId,
        DeviceLifecycleStatus.paired,
        DeviceLifecycleStatus.active,
      );

  @override
  Future<AdminResult<SessionStarted>> startDeviceSession(
    String deviceId,
  ) async {
    final idx = _deviceIndex(deviceId);
    if (!canManage(_actor)) {
      return const Failure(AdminPermissionDenied('role_rank'));
    }
    if (idx < 0) return const Failure(AdminNotFound());
    if (_devices[idx].status != DeviceLifecycleStatus.active) {
      return const Failure(AdminConflict('requires_active'));
    }
    _devices[idx] = _devices[idx].copyWith(hasOpenSession: true);
    return Success(
      SessionStarted(
        deviceId: deviceId,
        sessionId: _id('s'),
        token: _oneTimeSecret('SES'),
      ),
    );
    // The plaintext token is NOT retained — only the (simulated) session_token_ref.
  }

  @override
  Future<AdminResult<AdminDevice>> revokeDevice(String deviceId) async {
    final idx = _deviceIndex(deviceId);
    final guard = _manageGuard(deviceId, idx);
    if (guard != null) return guard;
    if (_devices[idx].status == DeviceLifecycleStatus.revoked) {
      return const Failure(AdminConflict('bad_state'));
    }
    final next = _devices[idx].copyWith(
      status: DeviceLifecycleStatus.revoked,
      hasOpenSession: false,
    );
    _devices[idx] = next;
    return Success(next);
  }

  /// The demo store simulates the full manager-side RF-112 lifecycle.
  @override
  bool get supportsManualLifecycle => true;
}
