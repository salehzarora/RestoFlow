import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show
        AdminConflict,
        AdminFailure,
        AdminPermissionDenied,
        AdminResult,
        AdminScope,
        AdminTransient,
        AdminValidation;

import 'staff_models.dart';

/// The dashboard Staff/PIN repository seam (sprint staff-provisioning backend:
/// `list_staff` / `create_staff_member` / `set_employee_pin`).
///
/// SECURITY: the raw PIN passes through [setPin] transiently over the
/// authenticated TLS transport and is hashed server-side (bcrypt); it is never
/// stored, logged, or echoed client-side.
abstract class StaffRepository {
  Future<AdminResult<List<StaffMember>>> load();

  /// Creates a PIN-only staff member (no login account): server-side app_user
  /// (synthetic identifier) + membership (role, this branch) + employee profile.
  Future<AdminResult<StaffMember>> create({
    required String displayName,
    required MembershipRole role,
  });

  /// Sets/resets the 4–8 digit PIN; the backend stores a bcrypt hash only.
  Future<AdminResult<void>> setPin({
    required String employeeProfileId,
    required String pin,
  });
}

/// A clearly-labelled in-memory demo store (demo mode only).
class InMemoryStaffStore implements StaffRepository {
  InMemoryStaffStore()
    : _staff = [
        const StaffMember(
          employeeProfileId: 'demo-staff-1',
          displayName: 'Amira K.',
          role: MembershipRole.cashier,
          hasPin: true,
          employmentStatus: 'active',
        ),
        const StaffMember(
          employeeProfileId: 'demo-staff-2',
          displayName: 'Yosef L.',
          role: MembershipRole.kitchenStaff,
          hasPin: false,
          employmentStatus: 'active',
        ),
      ];

  final List<StaffMember> _staff;
  int _seq = 0;

  @override
  Future<AdminResult<List<StaffMember>>> load() async =>
      Success(List.unmodifiable(_staff));

  @override
  Future<AdminResult<StaffMember>> create({
    required String displayName,
    required MembershipRole role,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) return const Failure(AdminValidation('name'));
    final member = StaffMember(
      employeeProfileId: 'demo-staff-new-${++_seq}',
      displayName: name,
      role: role,
      hasPin: false,
      employmentStatus: 'active',
    );
    _staff.add(member);
    return Success(member);
  }

  @override
  Future<AdminResult<void>> setPin({
    required String employeeProfileId,
    required String pin,
  }) async {
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) {
      return const Failure(AdminValidation('pin'));
    }
    final index = _staff.indexWhere(
      (s) => s.employeeProfileId == employeeProfileId,
    );
    if (index < 0) return const Failure(AdminTransient());
    final s = _staff[index];
    _staff[index] = StaffMember(
      employeeProfileId: s.employeeProfileId,
      displayName: s.displayName,
      role: s.role,
      hasPin: true, // the demo stores NO pin value — only the flag.
      employmentStatus: s.employmentStatus,
      employeeNumber: s.employeeNumber,
    );
    return const Success(null);
  }
}

/// The real, Supabase-backed [StaffRepository]. Authenticated anon-key
/// transport (D-011); identity server-derived; scope from the active
/// membership. Writes are idempotent via server-side client_request_id ledger.
class SupabaseStaffRepository implements StaffRepository {
  SupabaseStaffRepository({
    required SyncRpcTransport transport,
    required AdminScope scope,
    required String? Function() currentUserId,
    int Function()? nonce,
  }) : _t = transport,
       _scope = scope,
       _uid = currentUserId,
       _nonce = nonce ?? _microNonce;

  final SyncRpcTransport _t;
  final AdminScope _scope;
  final String? Function() _uid;
  final int Function() _nonce;

  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<AdminResult<List<StaffMember>>> load() async {
    final Object? raw;
    try {
      raw = await _t.invoke('list_staff', <String, dynamic>{
        'p_organization_id': _scope.organizationId,
        'p_restaurant_id': _scope.restaurantId,
        'p_branch_id': _scope.branchId,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    final staff = <StaffMember>[];
    for (final row in (raw['staff'] as List?) ?? const []) {
      if (row is! Map) continue;
      final role = _roleOf(row['role']?.toString());
      if (role == null) continue;
      staff.add(
        StaffMember(
          employeeProfileId: (row['employee_profile_id'] ?? '').toString(),
          displayName: (row['display_name'] ?? '').toString(),
          role: role,
          hasPin: row['has_pin'] == true,
          employmentStatus: (row['employment_status'] ?? 'active').toString(),
          employeeNumber: row['employee_number']?.toString(),
        ),
      );
    }
    return Success(staff);
  }

  @override
  Future<AdminResult<StaffMember>> create({
    required String displayName,
    required MembershipRole role,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) return const Failure(AdminValidation('name'));
    if (!kProvisionableStaffRoles.contains(role)) {
      return const Failure(AdminValidation('role'));
    }
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    // Staff provisioning is branch-scoped from this surface (the PIN pad lists
    // branch staff): an org-wide membership must pick a branch scope first.
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    final Object? raw;
    try {
      raw = await _t.invoke('create_staff_member', <String, dynamic>{
        'p_client_request_id': _requestId('create', [role.name, name]),
        'p_organization_id': _scope.organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_display_name': name,
        'p_role': _wireRole(role),
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    return Success(
      StaffMember(
        employeeProfileId: (raw['employee_profile_id'] ?? '').toString(),
        displayName: name,
        role: role,
        hasPin: false,
        employmentStatus: 'active',
      ),
    );
  }

  @override
  Future<AdminResult<void>> setPin({
    required String employeeProfileId,
    required String pin,
  }) async {
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) {
      return const Failure(AdminValidation('pin'));
    }
    final Object? raw;
    try {
      raw = await _t.invoke('set_employee_pin', <String, dynamic>{
        // A FRESH request id per submission (per-call nonce; review fix): the
        // id carries NO PIN-derived material — a fast digest of a 4-8 digit
        // PIN would be brute-forceable from the server's idempotency ledger —
        // and every press is a distinct rotation (no stale-replay no-op).
        'p_client_request_id': _requestId('set-pin', [employeeProfileId]),
        'p_employee_profile_id': employeeProfileId,
        'p_pin': pin,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    return const Success(null);
  }

  static MembershipRole? _roleOf(String? wire) => switch (wire) {
    'cashier' => MembershipRole.cashier,
    'kitchen_staff' => MembershipRole.kitchenStaff,
    'manager' => MembershipRole.manager,
    'restaurant_owner' => MembershipRole.restaurantOwner,
    'org_owner' => MembershipRole.orgOwner,
    'accountant' => MembershipRole.accountant,
    _ => null,
  };

  static String _wireRole(MembershipRole role) => switch (role) {
    MembershipRole.cashier => 'cashier',
    MembershipRole.kitchenStaff => 'kitchen_staff',
    MembershipRole.manager => 'manager',
    MembershipRole.restaurantOwner => 'restaurant_owner',
    MembershipRole.orgOwner => 'org_owner',
    MembershipRole.accountant => 'accountant',
  };

  AdminFailure _mapError(Object? raw) {
    if (raw is Map && raw['error'] == 'permission_denied') {
      return const AdminPermissionDenied('role_rank');
    }
    if (raw is Map && raw['error'] == 'invalid_pin') {
      return const AdminValidation('pin');
    }
    if (raw is Map && raw['error'] != null) {
      return AdminConflict(raw['error'].toString());
    }
    return const AdminTransient();
  }

  static AdminFailure _mapTransport(SyncTransportException e) =>
      switch (e.kind) {
        SyncTransportErrorKind.auth => const AdminPermissionDenied('denied'),
        SyncTransportErrorKind.transient => const AdminTransient(),
        SyncTransportErrorKind.server => const AdminTransient(),
        SyncTransportErrorKind.unknown => const AdminTransient(),
      };

  /// RFC-4122-shaped UUID (v5-style) — same pattern as the RF-160 device repo,
  /// with a per-call nonce for EVERY op (two create presses = two staff; every
  /// set-pin press = a fresh rotation; no PIN-derived material anywhere).
  String _requestId(String op, List<String> parts) {
    final seed = [_uid() ?? '', op, ...parts, _nonce().toString()].join('|');
    final bytes = sha256
        .convert(utf8.encode('mvp:staff:$seed'))
        .bytes
        .sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hx(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
  }
}
