import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/audit_filter_options_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// AUDIT-LOG-DASHBOARD-001 — the branch/actor filter options are SCOPE-SAFE:
/// branches are role-filtered so a branch manager never sees a sibling; actors
/// come from the scope-covering `list_staff` (names only, no email).
///
/// CODEX F-1B-3 FOLLOW-UP: actors still fail soft to an empty list, branches no
/// longer do — the analytics scope reads them, and "could not ask" must not look
/// like "there are none".
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);

  final Object? Function(String fn, Map<String, dynamic> params) _handler;

  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String fn, Map<String, dynamic> params) async {
    calls.add((fn, params));
    return _handler(fn, params);
  }
}

MembershipContext _m({
  required MembershipRole role,
  String? restaurantId,
  String? branchId,
}) => MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: restaurantId,
  restaurantName: 'Rest',
  branchId: branchId,
  branchName: 'Branch',
  role: role,
  status: 'active',
);

Map<String, dynamic> _orgStructure() => <String, dynamic>{
  'ok': true,
  'entity': 'org_structure',
  'organization': {'id': 'org-1', 'name': 'Org 1', 'default_currency': 'ILS'},
  'restaurants': <Map<String, dynamic>>[
    {
      'id': 'r1',
      'name': 'Rest 1',
      'branches': [
        {'id': 'b1', 'name': 'Downtown'},
        {'id': 'b2', 'name': 'Harbor'},
      ],
    },
    {
      'id': 'r2',
      'name': 'Rest 2',
      'branches': [
        {'id': 'b3', 'name': 'Airport'},
      ],
    },
  ],
};

Map<String, dynamic> _staff() => <String, dynamic>{
  'ok': true,
  'staff': <Map<String, dynamic>>[
    {
      'employee_profile_id': 'ep1',
      'display_name': 'Amira',
      'role': 'cashier',
      'employment_status': 'active',
    },
    {
      'employee_profile_id': 'ep2',
      'display_name': 'Sami',
      'role': 'manager',
      'employment_status': 'active',
    },
  ],
};

Object? _dispatch(String fn, Map<String, dynamic> p) =>
    fn == 'list_org_structure' ? _orgStructure() : _staff();

void main() {
  test('D55 auditCoveredScope is role-derived (owner/restaurant/branch)', () {
    expect(
      auditCoveredScope(
        _m(role: MembershipRole.orgOwner, restaurantId: 'r1', branchId: 'b1'),
      ),
      (restaurantId: null, branchId: null),
    );
    expect(
      auditCoveredScope(
        _m(
          role: MembershipRole.restaurantOwner,
          restaurantId: 'r1',
          branchId: 'b1',
        ),
      ),
      (restaurantId: 'r1', branchId: null),
    );
    expect(
      auditCoveredScope(
        _m(role: MembershipRole.manager, restaurantId: 'r1', branchId: 'b1'),
      ),
      (restaurantId: 'r1', branchId: 'b1'),
    );
  });

  test('D56 org_owner sees ALL branches as options', () async {
    final repo = RealAuditFilterOptionsRepository(
      scope: _m(
        role: MembershipRole.orgOwner,
        restaurantId: 'r1',
        branchId: 'b1',
      ),
      transport: _FakeTransport(_dispatch),
    );
    final branches = await repo.loadBranches();
    expect(branches.map((b) => b.branchId).toList(), ['b1', 'b2', 'b3']);
  });

  test('D57 restaurant_owner sees only their restaurant\'s branches', () async {
    final repo = RealAuditFilterOptionsRepository(
      scope: _m(
        role: MembershipRole.restaurantOwner,
        restaurantId: 'r1',
        branchId: 'b1',
      ),
      transport: _FakeTransport(_dispatch),
    );
    final branches = await repo.loadBranches();
    expect(branches.map((b) => b.branchId).toList(), ['b1', 'b2']);
    expect(
      branches.any((b) => b.branchId == 'b3'),
      isFalse,
    ); // sibling restaurant
  });

  test(
    'D58 a branch manager NEVER sees a sibling branch as an option',
    () async {
      final repo = RealAuditFilterOptionsRepository(
        scope: _m(
          role: MembershipRole.manager,
          restaurantId: 'r1',
          branchId: 'b1',
        ),
        transport: _FakeTransport(_dispatch),
      );
      final branches = await repo.loadBranches();
      expect(branches.map((b) => b.branchId).toList(), ['b1']);
      expect(
        branches.any((b) => b.branchId == 'b2' || b.branchId == 'b3'),
        isFalse,
      );
      expect(branches.single.restaurantId, 'r1');
    },
  );

  test(
    'D59 actor options are names only + list_staff called with covered scope',
    () async {
      final t = _FakeTransport(_dispatch);
      final repo = RealAuditFilterOptionsRepository(
        scope: _m(
          role: MembershipRole.manager,
          restaurantId: 'r1',
          branchId: 'b1',
        ),
        transport: t,
      );
      final actors = await repo.loadActors();
      expect(actors.map((a) => a.label).toList(), ['Amira', 'Sami']);
      expect(actors.map((a) => a.employeeProfileId).toList(), ['ep1', 'ep2']);
      final staffCall = t.calls.firstWhere((c) => c.$1 == 'list_staff');
      expect(staffCall.$2['p_restaurant_id'], 'r1');
      expect(staffCall.$2['p_branch_id'], 'b1');
    },
  );

  test(
    'D60 org_owner actor list is org-wide (covered scope null/null)',
    () async {
      final t = _FakeTransport(_dispatch);
      final repo = RealAuditFilterOptionsRepository(
        scope: _m(
          role: MembershipRole.orgOwner,
          restaurantId: 'r1',
          branchId: 'b1',
        ),
        transport: t,
      );
      await repo.loadActors();
      final staffCall = t.calls.firstWhere((c) => c.$1 == 'list_staff');
      expect(staffCall.$2['p_restaurant_id'], isNull);
      expect(staffCall.$2['p_branch_id'], isNull);
    },
  );

  // CODEX F-1B-3 FOLLOW-UP SUPERSEDES THE BRANCH HALF OF D61/D62.
  //
  // Both used to assert that a failure comes back as an empty branch list. That
  // was safe while the list only shaped a dropdown, and stopped being safe when
  // the analytics scope started treating a successful list as authoritative
  // about which branches exist: "could not ask" and "there are none" became the
  // same value, and a failed enumeration silently widened an owner's financial
  // scope. Branches now report failure; ACTORS still fail soft, because they
  // filter names and never scope.
  test(
    'D61 no transport -> branches report failure, actors fail soft',
    () async {
      const repo = RealAuditFilterOptionsRepository();
      expect(
        () => repo.loadBranches(),
        throwsA(isA<AuditFilterOptionsException>()),
      );
      expect(await repo.loadActors(), isEmpty);
    },
  );

  test('D62 a rejected RPC -> branches report failure (never fabricated, and '
      'never softened into "no branches")', () async {
    final repo = RealAuditFilterOptionsRepository(
      scope: _m(
        role: MembershipRole.orgOwner,
        restaurantId: 'r1',
        branchId: 'b1',
      ),
      transport: _FakeTransport((_, _) => <String, dynamic>{'ok': false}),
    );
    expect(
      () => repo.loadBranches(),
      throwsA(isA<AuditFilterOptionsException>()),
    );
    expect(await repo.loadActors(), isEmpty);
  });

  test('D63 a SUCCESSFUL response with no restaurants is an answer, not a '
      'failure', () async {
    final repo = RealAuditFilterOptionsRepository(
      scope: _m(
        role: MembershipRole.orgOwner,
        restaurantId: 'r1',
        branchId: 'b1',
      ),
      transport: _FakeTransport(
        (_, _) => <String, dynamic>{'ok': true, 'restaurants': <dynamic>[]},
      ),
    );
    expect(await repo.loadBranches(), isEmpty);
  });
}
