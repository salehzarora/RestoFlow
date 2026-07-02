import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';

/// The real, Supabase-backed [AdminRepository] for the dashboard DEVICES surface
/// (RF-160 Phase B). It is the ONLY dashboard admin repository that talks to a real
/// backend: device list / create / issue-code map 1:1 to the RF-112 + RF-160 public
/// RPCs through an authenticated anon-key [SyncRpcTransport] (DECISION D-011 — no
/// service-role key; identity is server-derived from `auth.uid()`, never sent).
///
/// HONEST SCOPE. The RF-112 device backend is MANAGEMENT-driven and still has NO
/// device-auth bridge (a device cannot yet authenticate as itself), so from the
/// dashboard an owner/manager can:
///   * list the branch/restaurant/org devices with their live lifecycle status,
///   * create a device, and
///   * issue a one-time enrollment code (shown exactly once).
/// The device-side redemption (`code_issued -> pending`) and every edge past it are
/// DEFERRED WITH the device-auth bridge, so [redeemEnrollmentCode] / [approveDevice]
/// / [activateDevice] / [startDeviceSession] return a typed, localized conflict
/// rather than FAKING a transition. The SETTINGS + USERS reads have no public list
/// RPC yet, so this repo is wired ONLY behind the Devices tab; Settings/Users keep
/// the demo store (their methods here are never invoked and fail closed).
///
/// No secret is ever logged or surfaced; only safe, typed [AdminFailure]s cross the
/// boundary. The `list_devices` read RPC is pending RISK R-003 human RLS sign-off.
class SupabaseAdminDeviceRepository implements AdminRepository {
  SupabaseAdminDeviceRepository({
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

  /// A per-call unique salt so a deliberate re-issue mints a FRESH code (and two
  /// distinct create presses make two devices) — these are single, `_busy`-guarded
  /// button actions, never an auto-retry loop (unlike RF-151 onboarding), so a
  /// per-call id is correct here. Injectable for deterministic tests.
  final int Function() _nonce;

  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  // ----------------------------------------------------------------- devices ---

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async {
    final Object? raw;
    try {
      raw = await _t.invoke('list_devices', <String, dynamic>{
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
    final rows = (raw['devices'] as List?) ?? const [];
    final devices = <AdminDevice>[];
    for (final row in rows) {
      if (row is! Map) continue;
      devices.add(
        AdminDevice(
          id: (row['device_id'] ?? '').toString(),
          label: (row['label'] ?? '').toString(),
          deviceType: (row['device_type'] ?? 'pos').toString(),
          branchLabel: (row['branch_label'] ?? _scope.scopeLabel).toString(),
          status: _statusOf((row['status'] ?? 'none').toString()),
          pairingId: row['device_pairing_id']?.toString(),
          hasOpenSession: row['has_open_session'] == true,
        ),
      );
    }
    return Success(devices);
  }

  @override
  Future<AdminResult<AdminDevice>> createDevice({
    required String label,
    required String deviceType,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return const Failure(AdminValidation('name'));
    if (!kDeviceTypes.contains(deviceType)) {
      return const Failure(AdminValidation('device_type'));
    }
    final restaurantId = _scope.restaurantId;
    final branchId = _scope.branchId;
    // create_device is branch-scoped (org/restaurant/branch NOT NULL). An org-wide
    // membership cannot target a branch from here -> honest validation error (a
    // branch picker for org/restaurant-scoped owners is the follow-up).
    if (restaurantId == null || branchId == null) {
      return const Failure(AdminValidation('scope'));
    }
    final Object? raw;
    try {
      raw = await _t.invoke('create_device', <String, dynamic>{
        'p_client_request_id': _requestId('create', [deviceType, trimmed]),
        'p_organization_id': _scope.organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_device_type': deviceType,
        'p_label': trimmed,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    return Success(
      AdminDevice(
        id: (raw['device_id'] ?? '').toString(),
        label: trimmed,
        deviceType: deviceType,
        branchLabel: _scope.branchName ?? _scope.scopeLabel,
        status: DeviceLifecycleStatus.none,
      ),
    );
  }

  @override
  Future<AdminResult<EnrollmentCodeIssued>> issueEnrollmentCode(
    String deviceId,
  ) async {
    final Object? raw;
    try {
      raw = await _t.invoke('issue_device_enrollment_code', <String, dynamic>{
        'p_client_request_id': _requestId('issue', [deviceId]),
        'p_device_id': deviceId,
      });
    } on SyncTransportException catch (e) {
      return Failure(_mapTransport(e));
    } catch (_) {
      return const Failure(AdminTransient());
    }
    if (raw is! Map || raw['ok'] != true) return Failure(_mapError(raw));
    final code = raw['enrollment_code']?.toString();
    if (code == null || code.isEmpty) {
      // A committed idempotent replay serves NO code (the one-time secret is never
      // re-returned); surface a conflict rather than an empty code.
      return const Failure(AdminConflict('code_consumed'));
    }
    return Success(
      EnrollmentCodeIssued(
        deviceId: (raw['device_id'] ?? deviceId).toString(),
        pairingId: (raw['device_pairing_id'] ?? '').toString(),
        code: code,
        expiresInLabel: '15m',
      ),
    );
  }

  // The device-side redemption + the lifecycle beyond `code_issued` are DEFERRED
  // with the device-auth bridge (RF-112 is management-driven; a device cannot yet
  // authenticate as itself). Return an honest, localized conflict — never a fake move.
  @override
  Future<AdminResult<AdminDevice>> redeemEnrollmentCode(
    String deviceId,
  ) async => const Failure(AdminConflict('device_bridge_pending'));

  @override
  Future<AdminResult<AdminDevice>> approveDevice(String deviceId) async =>
      const Failure(AdminConflict('device_bridge_pending'));

  @override
  Future<AdminResult<AdminDevice>> activateDevice(String deviceId) async =>
      const Failure(AdminConflict('device_bridge_pending'));

  @override
  Future<AdminResult<SessionStarted>> startDeviceSession(
    String deviceId,
  ) async => const Failure(AdminConflict('device_bridge_pending'));

  // -------------------------------------------- settings + users (never used) ---
  // This repository backs ONLY the Devices tab; Settings/Users use the demo store
  // until their read RPCs land. Fail closed if ever invoked.
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
  Future<AdminResult<List<AdminUser>>> loadUsers() async =>
      const Failure(AdminTransient());

  @override
  Future<AdminResult<AdminUser>> grantMembership({
    required String displayName,
    required String email,
    required MembershipRole role,
  }) async => const Failure(AdminTransient());

  @override
  Future<AdminResult<AdminUser>> updateRole({
    required String userId,
    required MembershipRole newRole,
  }) async => const Failure(AdminTransient());

  // ------------------------------------------------------------------ helpers ---

  DeviceLifecycleStatus _statusOf(String wire) =>
      DeviceLifecycleStatus.values.firstWhere(
        (s) => s.wire == wire,
        orElse: () => DeviceLifecycleStatus.none,
      );

  AdminFailure _mapError(Object? raw) =>
      (raw is Map && raw['error'] == 'permission_denied')
      ? const AdminPermissionDenied('role_rank')
      : const AdminTransient();

  static AdminFailure _mapTransport(SyncTransportException e) =>
      switch (e.kind) {
        SyncTransportErrorKind.auth => const AdminPermissionDenied('denied'),
        SyncTransportErrorKind.transient => const AdminTransient(),
        SyncTransportErrorKind.server => const AdminTransient(),
        SyncTransportErrorKind.unknown => const AdminTransient(),
      };

  /// A deterministic RFC-4122-shaped UUID (v5-style) from the auth user id + [op] +
  /// [parts] + a per-call [_nonce]. The auth user id is a non-secret salt (never the
  /// email); nothing is persisted client-side.
  String _requestId(String op, List<String> parts) {
    final seed = [_uid() ?? '', op, ...parts, _nonce().toString()].join('|');
    final bytes = sha256
        .convert(utf8.encode('rf160:device:$seed'))
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
