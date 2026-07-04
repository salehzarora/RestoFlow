import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';

/// The real, Supabase-backed [AdminRepository] for the dashboard USERS surface
/// (RF-116). It maps 1:1 to the three public member RPCs through an
/// authenticated anon-key [SyncRpcTransport] (DECISION D-011 — no service-role
/// key; identity is server-derived from `auth.uid()`, never sent):
///
///   * [loadUsers]        -> `public.list_members`     (rank >= manager)
///   * [updateRole]       -> `public.update_role`      (strictly outrank both roles)
///   * [revokeMembership] -> `public.revoke_membership`(strictly outrank the target)
///
/// HONEST SCOPE. Inviting/creating BRAND-NEW accounts is intentionally out of
/// scope (there is no client email→app_user lookup), so [grantMembership] fails
/// closed and [supportsGrant] is false — the Users screen hides the grant
/// affordance rather than offering an action that always fails. This repository
/// backs ONLY the Users tab; its Settings/Devices methods fail closed (they are
/// never wired), exactly like [SupabaseAdminDeviceRepository] stubs the non-device
/// methods. Only safe, typed [AdminFailure]s cross the boundary — never a secret.
///
/// A server denial (`permission_denied`) surfaces as [AdminPermissionDenied]; a
/// revoked/expired session (SQLSTATE 42501 -> transport `auth`) also maps to a
/// permission-denied state; transient transport failures map to [AdminTransient].
/// Real members are NEVER fabricated: a failed/denied list shows an honest state.
class SupabaseUsersRepository implements AdminRepository {
  SupabaseUsersRepository({
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

  /// A per-call salt so each deliberate role-change / revoke press is its own
  /// idempotent request (single, `_busy`-guarded button actions — not an
  /// auto-retry loop). Injectable for deterministic tests.
  final int Function() _nonce;

  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  // -------------------------------------------------------------------- users ---

  @override
  Future<AdminResult<List<AdminUser>>> loadUsers() async {
    final Object? raw;
    try {
      raw = await _t.invoke('list_members', <String, dynamic>{
        'p_organization_id': _scope.organizationId,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    final users = <AdminUser>[];
    for (final row in (raw['members'] as List?) ?? const []) {
      if (row is! Map) continue;
      // Fail-closed: skip any membership whose role is not one of the six tenant
      // roles (never guess; platform_admin is not a membership role — D-026).
      final role = MembershipRole.tryFromWire((row['role'] ?? '').toString());
      if (role == null) continue;
      final membershipId = (row['membership_id'] ?? '').toString();
      if (membershipId.isEmpty) continue;
      final email = (row['email'] ?? '').toString();
      final displayName = (row['display_name'] ?? '').toString();
      users.add(
        AdminUser(
          // The membership_id is the stable key role-change/revoke target.
          id: membershipId,
          membershipId: membershipId,
          displayName: displayName.isNotEmpty ? displayName : email,
          email: email,
          role: role,
          scopeLabel: _scopeLabelOf(row),
          status: (row['status'] ?? 'active').toString(),
          isSelf: row['is_self'] == true,
        ),
      );
    }
    return Success(users);
  }

  String _scopeLabelOf(Map<dynamic, dynamic> row) {
    final branch = (row['branch_name'] ?? '').toString();
    if (branch.isNotEmpty) return branch;
    final restaurant = (row['restaurant_name'] ?? '').toString();
    if (restaurant.isNotEmpty) return restaurant;
    return _scope.organizationName; // org-wide membership
  }

  @override
  Future<AdminResult<AdminUser>> updateRole({
    required String userId,
    required MembershipRole newRole,
  }) async {
    // `userId` is the membership_id (this repo sets AdminUser.id = membership_id).
    final Object? raw;
    try {
      raw = await _t.invoke('update_role', <String, dynamic>{
        'p_client_request_id': _requestId('update-role', [
          userId,
          newRole.wire,
        ]),
        'p_membership_id': userId,
        'p_new_role': newRole.wire,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    // The screen discards the value and reloads the list; return a minimal row.
    return Success(
      AdminUser(
        id: userId,
        membershipId: userId,
        displayName: '',
        email: '',
        role: newRole,
        scopeLabel: _scope.scopeLabel,
        status: 'active',
      ),
    );
  }

  @override
  Future<AdminResult<AdminUser>> revokeMembership(String membershipId) async {
    final Object? raw;
    try {
      raw = await _t.invoke('revoke_membership', <String, dynamic>{
        'p_client_request_id': _requestId('revoke', [membershipId]),
        'p_membership_id': membershipId,
        'p_reason': null,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    // The screen discards the value and reloads the list; return a minimal row.
    return Success(
      AdminUser(
        id: membershipId,
        membershipId: membershipId,
        displayName: '',
        email: '',
        role: newRoleForRevokedPlaceholder,
        scopeLabel: _scope.scopeLabel,
        status: 'revoked',
      ),
    );
  }

  /// An ephemeral placeholder role for the revoke success value (the list
  /// reloads, so this is never displayed).
  static const MembershipRole newRoleForRevokedPlaceholder =
      MembershipRole.cashier;

  // Inviting/creating brand-new accounts is out of scope (RF-116): there is no
  // client email→app_user lookup. Fail closed and hide the affordance — never
  // fake a grant.
  @override
  Future<AdminResult<AdminUser>> grantMembership({
    required String displayName,
    required String email,
    required MembershipRole role,
  }) async => const Failure(AdminConflict('grant_unavailable'));

  @override
  bool get supportsGrant => false;

  // -------------------------------------------- settings + devices (never used) ---
  // This repository backs ONLY the Users tab; its Settings/Devices methods fail
  // closed (they are never invoked — the shell routes those tabs elsewhere).
  @override
  Future<AdminResult<SettingsBundle>> loadSettings() async =>
      const Failure(AdminTransient());

  @override
  Future<AdminResult<OrganizationSettings>> updateOrganizationSettings({
    required String defaultCurrency,
    String? countryCode,
    required String status,
  }) async => const Failure(AdminTransient());

  @override
  Future<AdminResult<RestaurantSettings>> updateRestaurantSettings({
    required String name,
    String? currencyOverride,
    String? timezone,
    required String status,
  }) async => const Failure(AdminTransient());

  @override
  Future<AdminResult<BranchSettings>> updateBranchSettings({
    required String name,
    String? address,
    String? timezone,
    String? receiptPrefix,
    required String status,
  }) async => const Failure(AdminTransient());

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async =>
      const Failure(AdminTransient());

  @override
  Future<AdminResult<AdminDevice>> createDevice({
    required String label,
    required String deviceType,
  }) async => const Failure(AdminTransient());

  @override
  Future<AdminResult<EnrollmentCodeIssued>> issueEnrollmentCode(
    String deviceId,
  ) async => const Failure(AdminTransient());

  @override
  Future<AdminResult<AdminDevice>> redeemEnrollmentCode(
    String deviceId,
  ) async => const Failure(AdminTransient());

  @override
  Future<AdminResult<AdminDevice>> approveDevice(String deviceId) async =>
      const Failure(AdminTransient());

  @override
  Future<AdminResult<AdminDevice>> activateDevice(String deviceId) async =>
      const Failure(AdminTransient());

  @override
  Future<AdminResult<SessionStarted>> startDeviceSession(
    String deviceId,
  ) async => const Failure(AdminTransient());

  @override
  Future<AdminResult<AdminDevice>> revokeDevice(String deviceId) async =>
      const Failure(AdminTransient());

  @override
  bool get supportsManualLifecycle => false;

  // ------------------------------------------------------------------ helpers ---

  AdminFailure _mapError(Object? raw) =>
      (raw is Map && raw['error'] == 'permission_denied')
      ? const AdminPermissionDenied('role_rank')
      : const AdminTransient();

  static AdminFailure _mapTransport(SyncTransportException e) =>
      switch (e.kind) {
        // 42501 = revoked/expired session or cross-tenant/not-found -> denied.
        SyncTransportErrorKind.auth => const AdminPermissionDenied('denied'),
        SyncTransportErrorKind.transient => const AdminTransient(),
        SyncTransportErrorKind.server => const AdminTransient(),
        SyncTransportErrorKind.unknown => const AdminTransient(),
      };

  /// A deterministic RFC-4122-shaped UUID (v5-style) from the auth user id + [op]
  /// + [parts] + a per-call [_nonce] — the same idempotency-key pattern as the
  /// RF-160 device repo. The auth user id is a non-secret salt (never the email);
  /// nothing is persisted client-side.
  String _requestId(String op, List<String> parts) {
    final seed = [_uid() ?? '', op, ...parts, _nonce().toString()].join('|');
    final bytes = sha256
        .convert(utf8.encode('rf116:users:$seed'))
        .bytes
        .sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5 (name-based)
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC-4122 variant
    String hx(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
  }
}
