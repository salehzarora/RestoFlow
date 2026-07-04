import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

import '../models/admin_failure.dart';
import '../models/admin_user.dart';
import '../models/device_models.dart';
import '../models/settings_models.dart';

/// The RF-113 administration repository seam. Today the dashboard injects a
/// labelled in-memory [DemoAdminStore]; the real wiring calls the RF-112 public
/// RPCs once the auth/org-context bridge lands. Each method maps 1:1 to an RF-112
/// RPC (named in the doc comment) and returns an [AdminResult] — never throws.
abstract class AdminRepository {
  // ---- Settings (API_CONTRACT §4.25 / D-033) --------------------------------
  Future<AdminResult<SettingsBundle>> loadSettings();

  /// `public.update_organization_settings` — org_owner only.
  Future<AdminResult<OrganizationSettings>> updateOrganizationSettings({
    required String defaultCurrency,
    String? countryCode,
    required String status,
  });

  /// `public.update_restaurant_settings` — org_owner / restaurant_owner.
  Future<AdminResult<RestaurantSettings>> updateRestaurantSettings({
    required String name,
    String? currencyOverride,
    String? timezone,
    required String status,
  });

  /// `public.update_branch_settings` — org_owner / restaurant_owner.
  Future<AdminResult<BranchSettings>> updateBranchSettings({
    required String name,
    String? address,
    String? timezone,
    String? receiptPrefix,
    required String status,
  });

  // ---- Users / roles (API_CONTRACT §4.26 / D-033) ---------------------------
  Future<AdminResult<List<AdminUser>>> loadUsers();

  /// `public.grant_membership` — role-rank guarded (actor strictly outranks the
  /// assigned role; existing app_user only; no invite/pending).
  Future<AdminResult<AdminUser>> grantMembership({
    required String displayName,
    required String email,
    required MembershipRole role,
  });

  /// `public.update_role` — role-rank guarded (actor strictly outranks both the
  /// existing and the new role; no self-escalation).
  Future<AdminResult<AdminUser>> updateRole({
    required String userId,
    required MembershipRole newRole,
  });

  /// `public.revoke_membership` (RF-116) — deactivates a membership
  /// (status → `revoked`, PIN sign-in terminated). Role-rank guarded: the actor
  /// must strictly outrank the target and can never revoke their own membership.
  Future<AdminResult<AdminUser>> revokeMembership(String membershipId);

  /// Whether this repository can grant a brand-new membership to an existing
  /// user. The demo store simulates it (true); the real dashboard repository
  /// returns false — inviting/creating brand-new accounts is intentionally out
  /// of scope (RF-116: there is no client email→app_user lookup), so the Users
  /// screen hides the grant affordance rather than offering an action that
  /// always fails. List + change-role + revoke remain fully wired.
  bool get supportsGrant => true;

  // ---- Devices (API_CONTRACT §4.27–§4.29 / D-033/D-034) ---------------------
  Future<AdminResult<List<AdminDevice>>> loadDevices();

  /// `public.create_device` — manager+ in scope.
  Future<AdminResult<AdminDevice>> createDevice({
    required String label,
    required String deviceType,
  });

  /// `public.issue_device_enrollment_code` — returns the plaintext code ONCE.
  Future<AdminResult<EnrollmentCodeIssued>> issueEnrollmentCode(
    String deviceId,
  );

  /// `public.redeem_device_enrollment_code` — code_issued → pending (the demo
  /// simulates the device submitting its code).
  Future<AdminResult<AdminDevice>> redeemEnrollmentCode(String deviceId);

  /// `public.approve_device` — pending → paired (manager approval edge).
  Future<AdminResult<AdminDevice>> approveDevice(String deviceId);

  /// `public.activate_device` — paired → active (NEVER pending → active).
  Future<AdminResult<AdminDevice>> activateDevice(String deviceId);

  /// `public.start_device_session` — requires `active`; returns the plaintext
  /// session token ONCE.
  Future<AdminResult<SessionStarted>> startDeviceSession(String deviceId);

  /// `public.revoke_device_management` — manager+ revokes a device: its pairing
  /// and sessions are ended and the device falls back to the pairing screen.
  Future<AdminResult<AdminDevice>> revokeDevice(String deviceId);

  /// Whether the MANAGER-side lifecycle simulation (redeem/approve/activate/
  /// start-session buttons) applies. The demo store simulates the full RF-112
  /// lifecycle (true). The REAL backend pairs device-originated (RF-161): the
  /// device redeems its code itself and `code_issued -> active` collapses, so
  /// the real repository returns false and the UI hides those manual actions
  /// (issue-code + revoke remain).
  bool get supportsManualLifecycle => true;
}
