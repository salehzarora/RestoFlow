import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_repository.dart';
import 'package:restoflow_dashboard/src/data/real_audit_log_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RealRepoNotWiredError;

/// AUDIT-LOG-DASHBOARD-001 — the real repo maps `owner_audit_events` into the
/// audit models, calls the RPC with the scoped `p_*` params, and fails closed
/// with no transport/scope or on a rejected/failed RPC (never fabricates).
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);

  final Object? Function(String function, Map<String, dynamic> params) _handler;

  String? lastFunction;
  Map<String, dynamic>? lastParams;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    lastFunction = function;
    lastParams = params;
    return _handler(function, params);
  }
}

MembershipContext _scope() => const MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: 'rest-1',
  restaurantName: 'Rest 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: MembershipRole.orgOwner,
  status: 'active',
);

Map<String, dynamic> _payload() => <String, dynamic>{
  'ok': true,
  'entity': 'owner_audit_events',
  'currency_code': 'ILS',
  'range': 'today',
  'limit': 25,
  'events': <Map<String, dynamic>>[
    {
      'event_id': 'ae1',
      'action': 'order.voided',
      'category': 'voids',
      'occurred_at': '2026-07-11 14:00',
      'actor_name': 'Amira K.',
      'restaurant_name': 'Rest 1',
      'branch_name': 'Downtown',
      'device_label': 'POS-1',
      'reason': 'wrong table',
      'old_values': {'status': 'submitted'},
      'new_values': {'status': 'voided', 'voided_item_count': 2},
    },
  ],
  'has_more': true,
  'next_cursor': '2026-07-11 14:00:00+00|ae1',
  'count': 1,
};

void main() {
  test(
    'D40 loadEvents calls owner_audit_events with scoped params + maps',
    () async {
      final transport = _FakeTransport((_, _) => _payload());
      final repo = RealAuditLogRepository(
        null,
        scope: _scope(),
        transport: transport,
      );

      final page = await repo.loadEvents(const AuditQuery());

      expect(transport.lastFunction, 'owner_audit_events');
      // org_owner default = "all permitted branches" -> covered scope (null/null).
      expect(transport.lastParams, {
        'p_organization_id': 'org-1',
        'p_restaurant_id': null,
        'p_branch_id': null,
        'p_range': 'today',
        'p_category': null,
        'p_sensitive_only': false,
        'p_actor_employee_profile_id': null,
        'p_limit': 25,
        'p_cursor': null,
      });

      expect(page.events.length, 1);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, '2026-07-11 14:00:00+00|ae1');
      expect(page.currencyCode, 'ILS');
      final e = page.events.single;
      expect(e.action, 'order.voided');
      expect(e.category, 'voids');
      expect(e.actorName, 'Amira K.');
      expect(e.branchName, 'Downtown');
      expect(e.deviceLabel, 'POS-1');
      expect(e.reason, 'wrong table');
      expect(e.newValues['status'], 'voided');
      expect(e.newValues['voided_item_count'], 2);
    },
  );

  test(
    'D41 filters (category + sensitive-only) + cursor thread into params',
    () async {
      final transport = _FakeTransport((_, _) => _payload());
      final repo = RealAuditLogRepository(
        null,
        scope: _scope(),
        transport: transport,
      );

      await repo.loadEvents(
        const AuditQuery(
          range: AuditRange.last7,
          category: AuditCategory.voids,
          sensitiveOnly: true,
        ),
        cursor: 'cur-1',
      );

      expect(transport.lastParams, {
        'p_organization_id': 'org-1',
        'p_restaurant_id': null,
        'p_branch_id': null,
        'p_range': 'last7',
        'p_category': 'voids',
        'p_sensitive_only': true,
        'p_actor_employee_profile_id': null,
        'p_limit': 25,
        'p_cursor': 'cur-1',
      });
    },
  );

  test('D63 a MANAGER default sends its covered branch scope', () async {
    final transport = _FakeTransport((_, _) => _payload());
    const managerScope = MembershipContext(
      id: 'm2',
      organizationId: 'org-1',
      organizationName: 'Org 1',
      restaurantId: 'rest-1',
      restaurantName: 'Rest 1',
      branchId: 'branch-1',
      branchName: 'Branch 1',
      role: MembershipRole.manager,
      status: 'active',
    );
    final repo = RealAuditLogRepository(
      null,
      scope: managerScope,
      transport: transport,
    );
    await repo.loadEvents(const AuditQuery());
    expect(transport.lastParams!['p_restaurant_id'], 'rest-1');
    expect(transport.lastParams!['p_branch_id'], 'branch-1');
  });

  test('D64 selecting a branch narrows scope to that branch', () async {
    final transport = _FakeTransport((_, _) => _payload());
    final repo = RealAuditLogRepository(
      null,
      scope: _scope(),
      transport: transport,
    );
    await repo.loadEvents(
      const AuditQuery(
        branch: AuditBranchOption(
          branchId: 'branch-9',
          restaurantId: 'rest-9',
          label: 'Rest 9 · North',
        ),
      ),
    );
    expect(transport.lastParams!['p_restaurant_id'], 'rest-9');
    expect(transport.lastParams!['p_branch_id'], 'branch-9');
  });

  test('D65 selecting an actor sends p_actor_employee_profile_id', () async {
    final transport = _FakeTransport((_, _) => _payload());
    final repo = RealAuditLogRepository(
      null,
      scope: _scope(),
      transport: transport,
    );
    await repo.loadEvents(
      const AuditQuery(
        actor: AuditActorOption(employeeProfileId: 'ep-7', label: 'Nadia'),
      ),
    );
    expect(transport.lastParams!['p_actor_employee_profile_id'], 'ep-7');
  });

  test(
    'D42 fail-closed: no transport/scope -> RealRepoNotWiredError',
    () async {
      expect(
        RealAuditLogRepository(
          null,
          scope: _scope(),
          transport: null,
        ).loadEvents(const AuditQuery()),
        throwsA(isA<RealRepoNotWiredError>()),
      );
      final t = _FakeTransport((_, _) => _payload());
      expect(
        RealAuditLogRepository(
          null,
          scope: null,
          transport: t,
        ).loadEvents(const AuditQuery()),
        throwsA(isA<RealRepoNotWiredError>()),
      );
    },
  );

  test(
    'D43 fail-closed: ok!=true (permission_denied) -> AuditLogException',
    () async {
      final t = _FakeTransport(
        (_, _) => <String, dynamic>{'ok': false, 'error': 'permission_denied'},
      );
      expect(
        RealAuditLogRepository(
          null,
          scope: _scope(),
          transport: t,
        ).loadEvents(const AuditQuery()),
        throwsA(isA<AuditLogException>()),
      );
    },
  );

  test(
    'D44 fail-closed: a transport failure (even auth) -> AuditLogException',
    () async {
      final t = _FakeTransport(
        (_, _) => throw const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
        ),
      );
      expect(
        RealAuditLogRepository(
          null,
          scope: _scope(),
          transport: t,
        ).loadEvents(const AuditQuery()),
        throwsA(isA<AuditLogException>()),
      );
    },
  );
}
