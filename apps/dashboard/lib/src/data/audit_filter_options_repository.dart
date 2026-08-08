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
/// FAIL-SOFT, AT THE POINT OF USE. The Activity and Active Orders filters both
/// read these through `asData ?? []`, so an unavailable list degrades to just
/// "All …" and the timeline still works — never fabricated options.
///
/// CODEX F-1B-3 FOLLOW-UP — `loadBranches` no longer does that degrading ITSELF.
/// It used to return an empty list for a missing transport, a thrown transport
/// error, an `ok:false` rejection and a malformed envelope alike, which was
/// harmless while the list only shaped a dropdown. It stopped being harmless
/// when the ANALYTICS SCOPE began treating a successful list as authoritative
/// about which branches exist: "the enumeration failed" and "this organization
/// has no selectable branches" became the same value, so a network blip or a
/// denied `list_org_structure` would retire an owner's selected branch and
/// silently widen every figure on the page to the whole organization.
///
/// A failure is now reported as [AuditFilterOptionsException] and only a real
/// answer comes back as a list — including a genuinely empty one. `loadActors`
/// keeps the old behaviour: it feeds no scope, only a name filter.
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

/// The branch enumeration could not be ANSWERED — as distinct from answering
/// that there are no branches.
///
/// CODEX F-1B-3 FOLLOW-UP. The two are different facts and only one of them
/// says anything about which branches exist, so they must not share a value.
/// Consumers that only shape a dropdown may still treat both as "no options";
/// the analytics scope must not, because widening a financial query on a failed
/// fetch changes what every figure means with nothing on screen to say so.
class AuditFilterOptionsException implements Exception {
  const AuditFilterOptionsException(this.message);

  final String message;

  @override
  String toString() => 'AuditFilterOptionsException: $message';
}

/// Loads the scope-safe branch + actor filter options.
abstract class AuditFilterOptionsRepository {
  /// The branches the caller covers.
  ///
  /// An empty list is an ANSWER: the caller covers no selectable branch.
  /// Throws [AuditFilterOptionsException] when the question could not be
  /// answered at all.
  Future<List<AuditBranchOption>> loadBranches();

  /// The in-scope staff. Still fails soft to an empty list — it filters names,
  /// never scope.
  Future<List<AuditActorOption>> loadActors();
}

/// Deterministic in-memory options for demo mode.
class DemoAuditFilterOptionsRepository implements AuditFilterOptionsRepository {
  const DemoAuditFilterOptionsRepository();

  @override
  Future<List<AuditBranchOption>> loadBranches() async => const [
    AuditBranchOption(
      organizationId: 'demo-org-1',
      branchId: 'demo-branch-downtown',
      restaurantId: 'demo-rest-1',
      label: 'RestoFlow · Downtown',
    ),
    AuditBranchOption(
      organizationId: 'demo-org-1',
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
/// authenticated transport. Branches report failure
/// ([AuditFilterOptionsException]) so an unanswerable enumeration is never
/// mistaken for an empty organization; actors still fail soft to an empty list.
class RealAuditFilterOptionsRepository implements AuditFilterOptionsRepository {
  const RealAuditFilterOptionsRepository({this.scope, this.transport});

  final MembershipContext? scope;
  final SyncRpcTransport? transport;

  @override
  Future<List<AuditBranchOption>> loadBranches() async {
    // CODEX F-1B-3 FOLLOW-UP — each of these four is a FAILURE TO ANSWER, and
    // each used to return `const []`, which reads as "this organization has no
    // branches". The analytics scope now trusts a successful list, so the
    // difference has to survive the repository.
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const AuditFilterOptionsException(
        'list_org_structure: no authenticated transport/scope - branch options not wired',
      );
    }
    final Object? raw;
    try {
      raw = await t.invoke('list_org_structure', <String, dynamic>{
        'p_organization_id': m.organizationId,
      });
    } catch (_) {
      throw const AuditFilterOptionsException(
        'list_org_structure transport failure',
      );
    }
    // A DEPLOYED RPC that refused the caller is a denial, never "no branches" —
    // an authorization failure must not be handed back as a softer story.
    if (raw is! Map || raw['ok'] != true) {
      throw const AuditFilterOptionsException('list_org_structure rejected');
    }
    final restaurants = raw['restaurants'];
    if (restaurants is! List) {
      throw const AuditFilterOptionsException(
        'list_org_structure returned a malformed payload',
      );
    }

    // Past this point the RPC ANSWERED. Individual unusable rows are skipped
    // rather than fatal — one bad branch row is not evidence that the rest of
    // the payload is wrong — so an empty result here means the caller really
    // covers no selectable branch.
    //
    // CODEX F-1B-2-R1 — DECODE EVERYTHING, THEN DETECT CONFLICTS, THEN FILTER
    // BY ROLE. In that order, and the order is the whole point.
    //
    // Role filtering used to happen while decoding, so a branch id delivered
    // twice under two different restaurants could lose one of its two rows
    // before anything compared them. For a restaurant owner of rest-2 the
    // rest-CONFLICT row simply vanished, the client-side sanitiser saw one
    // clean tuple, and branch-2 was offered as if nothing were wrong. The
    // conflict check was documented as whole-response and in production it was
    // not.
    //
    // Conflicts are therefore decided over EVERY decoded row, including rows
    // this caller may not read, and only the surviving branch ids are then
    // narrowed to the caller's coverage. Unauthorized rows still never leave
    // this method — they are evidence about a branch id, not options.
    final decoded = <AuditBranchOption>[];
    for (final r in restaurants.whereType<Map>()) {
      final restaurantId = _str(r['id']);
      if (restaurantId == null) continue;
      final restaurantName = _str(r['name']) ?? '';
      final branches = r['branches'];
      if (branches is! List) continue;
      for (final b in branches.whereType<Map>()) {
        final branchId = _str(b['id']);
        if (branchId == null) continue;
        final branchName = _str(b['name']) ?? branchId;
        decoded.add(
          AuditBranchOption(
            // CODEX F-1: the organization this call was AUTHORIZED under —
            // `list_org_structure` was invoked with exactly this id, so the
            // option is stamped with it rather than re-read. No extra query.
            organizationId: m.organizationId,
            branchId: branchId,
            restaurantId: restaurantId,
            label: restaurantName.isEmpty
                ? branchName
                : '$restaurantName · $branchName',
          ),
        );
      }
    }

    final conflicting = _conflictingBranchIds(decoded);
    final out = <AuditBranchOption>[];
    final taken = <String>{};
    for (final option in decoded) {
      if (conflicting.contains(option.branchId)) continue;
      // Role-derived coverage: never surface a branch the caller does not
      // cover. Unchanged rules, applied AFTER the conflict pass.
      if (m.role == MembershipRole.restaurantOwner &&
          option.restaurantId != m.restaurantId) {
        continue;
      }
      // Managers (and any non-owner role) cover ONLY their own branch.
      if (m.role != MembershipRole.orgOwner &&
          m.role != MembershipRole.restaurantOwner &&
          option.branchId != m.branchId) {
        continue;
      }
      // Rows agreeing on all three ids are one branch; a differing label is
      // cosmetic. First occurrence wins, which is deterministic because the
      // server orders stably — and safe, because every row still carrying this
      // branch id shares its composite.
      if (!taken.add(option.branchId)) continue;
      out.add(option);
    }
    return out;
  }

  /// Branch ids that arrived under more than one composite identity.
  ///
  /// Same id, different restaurant or organization: the payload contradicts
  /// itself about where that branch lives, so the id is unusable. Whole-list
  /// and symmetric — the answer cannot depend on which of the two rows came
  /// first.
  static Set<String> _conflictingBranchIds(List<AuditBranchOption> decoded) {
    final firstById = <String, AuditBranchOption>{};
    final conflicting = <String>{};
    for (final option in decoded) {
      final seen = firstById[option.branchId];
      if (seen == null) {
        firstById[option.branchId] = option;
      } else if (seen.restaurantId != option.restaurantId ||
          seen.organizationId != option.organizationId) {
        conflicting.add(option.branchId);
      }
    }
    return conflicting;
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
