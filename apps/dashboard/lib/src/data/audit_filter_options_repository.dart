/// Scope-safe option sources for the Activity-log BRANCH and ACTOR filters
/// (AUDIT-LOG-DASHBOARD-001).
///
/// Both dropdowns are populated ONLY from existing scope-safe Dashboard RPCs —
/// the caller never types an arbitrary UUID:
///   * branches  <- `list_org_structure` (manager+), then filtered to the
///                  caller's COVERED scope by role so a branch manager never
///                  even SEES a sibling branch as an option.
///   * staff     <- `list_staff` (scope-covering, names only — no email/phone),
///                  yielding `employee_profile_id` -> the RPC's
///                  `p_actor_employee_profile_id`.
/// The backend `owner_audit_events` remains authoritative and intersects any
/// chosen filter with the server-derived scope; these options only shape the UI.
///
/// FAIL-SOFT: a load failure returns an EMPTY list, so the dropdown degrades to
/// just "All …" and the timeline still works — never fabricated options.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'audit_log_models.dart';

/// The (restaurant, branch) scope a [membership] COVERS for the default "all
/// permitted branches" query. The tenant resolver pins a single concrete branch
/// onto every resolved membership, so coverage cannot be read off the ids — it
/// is derived from the role:
///   org_owner        -> (null, null)            (whole org)
///   restaurant_owner -> (restaurantId, null)    (whole restaurant)
///   otherwise        -> (restaurantId, branchId)(the one covered branch)
({String? restaurantId, String? branchId}) auditCoveredScope(
  MembershipContext m,
) {
  switch (m.role) {
    case MembershipRole.orgOwner:
      return (restaurantId: null, branchId: null);
    case MembershipRole.restaurantOwner:
      return (restaurantId: m.restaurantId, branchId: null);
    case MembershipRole.manager:
    case MembershipRole.cashier:
    case MembershipRole.kitchenStaff:
    case MembershipRole.accountant:
      return (restaurantId: m.restaurantId, branchId: m.branchId);
  }
}

/// Loads the scope-safe branch + actor filter options.
abstract class AuditFilterOptionsRepository {
  Future<List<AuditBranchOption>> loadBranches();
  Future<List<AuditActorOption>> loadActors();
}

/// Deterministic in-memory options for demo mode.
class DemoAuditFilterOptionsRepository implements AuditFilterOptionsRepository {
  const DemoAuditFilterOptionsRepository();

  @override
  Future<List<AuditBranchOption>> loadBranches() async => const [
    AuditBranchOption(
      branchId: 'demo-branch-downtown',
      restaurantId: 'demo-rest-1',
      label: 'RestoFlow · Downtown',
    ),
    AuditBranchOption(
      branchId: 'demo-branch-harbor',
      restaurantId: 'demo-rest-1',
      label: 'RestoFlow · Harbor',
    ),
  ];

  @override
  Future<List<AuditActorOption>> loadActors() async => const [
    AuditActorOption(employeeProfileId: 'demo-staff-amira', label: 'Amira'),
    AuditActorOption(employeeProfileId: 'demo-staff-sami', label: 'Sami'),
    AuditActorOption(employeeProfileId: 'demo-staff-nadia', label: 'Nadia'),
  ];
}

/// Real-mode options from `list_org_structure` + `list_staff` over the scoped
/// authenticated transport. Fails soft to an empty list (never throws).
class RealAuditFilterOptionsRepository implements AuditFilterOptionsRepository {
  const RealAuditFilterOptionsRepository({this.scope, this.transport});

  final MembershipContext? scope;
  final SyncRpcTransport? transport;

  @override
  Future<List<AuditBranchOption>> loadBranches() async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) return const [];
    final Object? raw;
    try {
      raw = await t.invoke('list_org_structure', <String, dynamic>{
        'p_organization_id': m.organizationId,
      });
    } catch (_) {
      return const [];
    }
    if (raw is! Map || raw['ok'] != true) return const [];
    final restaurants = raw['restaurants'];
    if (restaurants is! List) return const [];

    final out = <AuditBranchOption>[];
    for (final r in restaurants.whereType<Map>()) {
      final restaurantId = _str(r['id']);
      if (restaurantId == null) continue;
      // Role-derived coverage: never surface a branch the caller does not cover.
      if (m.role == MembershipRole.restaurantOwner &&
          restaurantId != m.restaurantId) {
        continue;
      }
      final restaurantName = _str(r['name']) ?? '';
      final branches = r['branches'];
      if (branches is! List) continue;
      for (final b in branches.whereType<Map>()) {
        final branchId = _str(b['id']);
        if (branchId == null) continue;
        // Managers (and any non-owner role) cover ONLY their own branch.
        if (m.role != MembershipRole.orgOwner &&
            m.role != MembershipRole.restaurantOwner &&
            branchId != m.branchId) {
          continue;
        }
        final branchName = _str(b['name']) ?? branchId;
        out.add(
          AuditBranchOption(
            branchId: branchId,
            restaurantId: restaurantId,
            label: restaurantName.isEmpty
                ? branchName
                : '$restaurantName · $branchName',
          ),
        );
      }
    }
    return out;
  }

  @override
  Future<List<AuditActorOption>> loadActors() async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) return const [];
    final covered = auditCoveredScope(m);
    final Object? raw;
    try {
      raw = await t.invoke('list_staff', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': covered.restaurantId,
        'p_branch_id': covered.branchId,
      });
    } catch (_) {
      return const [];
    }
    if (raw is! Map || raw['ok'] != true) return const [];
    final staff = raw['staff'];
    if (staff is! List) return const [];

    final out = <AuditActorOption>[];
    for (final s in staff.whereType<Map>()) {
      final id = _str(s['employee_profile_id']);
      final name = _str(s['display_name']);
      if (id == null || name == null) continue;
      out.add(AuditActorOption(employeeProfileId: id, label: name));
    }
    return out;
  }

  static String? _str(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
