import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/real_platform_admin_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// A recording fake [SyncRpcTransport] (house style: hand-written, no mocktail).
/// Records every invoked function + params and delegates to a handler, so a test
/// can assert WHICH public wrappers were called, with what reason - and that no
/// `app.*` or mutation RPC is ever invoked. No SupabaseClient, no network.
class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this._handler);

  final Future<Object?> Function(String function, Map<String, dynamic> params)
  _handler;

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    functions.add(function);
    params.add(p);
    return _handler(function, p);
  }
}

/// A representative `public.platform_admin_organization_overview` jsonb result.
Map<String, dynamic> _overviewJson() => <String, dynamic>{
  'ok': true,
  'organizations': <dynamic>[
    <String, dynamic>{
      'id': 'o1',
      'name': 'Bistro Co',
      'status': 'active',
      'created_by_app_user_id': 'u1',
      'creation_request_id': 'r1',
      'restaurants_count': 2,
      'branches_count': 3,
      'active_memberships_count': 5,
    },
    <String, dynamic>{
      'id': 'o2',
      'name': 'Aleph Foods',
      'status': 'suspended',
      'created_by_app_user_id': 'u2',
      'creation_request_id': 'r2',
      'restaurants_count': 1,
      'branches_count': 1,
      'active_memberships_count': 1,
    },
  ],
  'server_ts': '2026-06-28T10:15:30.123456Z',
};

/// A representative `public.platform_admin_recent_audit` jsonb result.
Map<String, dynamic> _auditJson() => <String, dynamic>{
  'ok': true,
  'events': <dynamic>[
    <String, dynamic>{
      'id': 'e1',
      'actor_app_user_id': 'u1',
      'target_organization_id': null,
      'action': 'platform.organizations.overview',
      'reason': kPlatformAdminOverviewReason,
      'occurred_at': '2026-06-28T10:15:30.000000Z',
    },
  ],
  'limit': 50,
  'server_ts': '2026-06-28T10:15:30.123456Z',
};

/// The RPC names that would mutate / are not part of this read-only overview.
const Set<String> _mutationOrForbiddenRpcs = <String>{
  'sync_push',
  'submit_order',
  'record_payment',
  'apply_discount',
  'open_shift',
  'close_shift',
  'reconcile_shift',
  'void_order',
  'revoke_device',
  'revoke_employee',
};

void main() {
  group('RealPlatformAdminRepository (RF-128)', () {
    test(
      'maps the public wrapper JSON into PlatformOverview, read-only, with the '
      'audit reason - and never calls app.* or a mutation RPC',
      () async {
        final transport = _RecordingTransport(
          (function, _) async =>
              function == 'platform_admin_organization_overview'
              ? _overviewJson()
              : _auditJson(),
        );
        final repo = RealPlatformAdminRepository(transport);

        final overview = await repo.loadOverview();

        // (6) successful JSON maps into the existing overview model.
        expect(overview.organizationCount, 2);
        expect(overview.activeOrganizationCount, 1);
        expect(overview.restaurantCount, 3); // 2 + 1
        expect(overview.branchCount, 4); // 3 + 1
        expect(overview.warningCount, 1); // non-active orgs
        expect(overview.generatedDateLabel, '2026-06-28');
        expect(overview.isEmpty, isFalse);
        // organizations sorted by name; counts/status mapped from real data.
        expect(overview.organizations.map((o) => o.organizationName), <String>[
          'Aleph Foods',
          'Bistro Co',
        ]);
        final bistro = overview.organizations.firstWhere(
          (o) => o.organizationName == 'Bistro Co',
        );
        expect(bistro.restaurantCount, 2);
        expect(bistro.branchCount, 3);
        expect(bistro.status, 'active');
        // activity mapped from the audit feed.
        expect(overview.activity, hasLength(1));
        expect(
          overview.activity.single.action,
          'platform.organizations.overview',
        );
        // narrow panel -> honest 0 / empty for what the read does not provide.
        expect(overview.deviceCount, 0);
        expect(overview.todayOrderCount, 0);
        expect(overview.activeBranchCount, 0);
        expect(overview.branchHealth, isEmpty);

        // (3) exactly the two read wrappers were called, in order.
        expect(transport.functions, <String>[
          'platform_admin_organization_overview',
          'platform_admin_recent_audit',
        ]);
        // (4) never the `app` schema - only bare public function names.
        expect(transport.functions.any((f) => f.contains('app.')), isFalse);
        // (8) no mutation / write RPC is ever called.
        expect(
          transport.functions.any(_mutationOrForbiddenRpcs.contains),
          isFalse,
        );
        // (5) the required non-empty audit reason is sent to every call.
        expect(transport.params[0]['p_reason'], kPlatformAdminOverviewReason);
        expect(transport.params[0]['p_reason'], isNotEmpty);
        expect(transport.params[1]['p_reason'], kPlatformAdminOverviewReason);
        expect(transport.params[1]['p_limit'], kPlatformAdminAuditLimit);
      },
    );

    test(
      '(7) an auth/aal2/grant error (42501) surfaces safely as a '
      'PlatformAdminException without leaking the raw code or JSON',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => throw const SyncTransportException(
            SyncTransportErrorKind.auth,
            code: '42501',
            message: 'insufficient_privilege: {"hint":"grant"}',
          ),
        );
        final repo = RealPlatformAdminRepository(transport);

        await expectLater(
          repo.loadOverview(),
          throwsA(isA<PlatformAdminException>()),
        );

        try {
          await repo.loadOverview();
          fail('expected a PlatformAdminException');
        } on PlatformAdminException catch (e) {
          expect(e.message.toLowerCase(), contains('denied'));
          // No raw backend code or JSON wall reaches the message.
          expect(e.message, isNot(contains('42501')));
          expect(e.message, isNot(contains('{')));
        }
      },
    );

    test(
      'a transient/server transport error surfaces as a PlatformAdminException',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => throw const SyncTransportException(
            SyncTransportErrorKind.transient,
            message: 'timeout',
          ),
        );
        final repo = RealPlatformAdminRepository(transport);
        await expectLater(
          repo.loadOverview(),
          throwsA(isA<PlatformAdminException>()),
        );
      },
    );

    test(
      'an unexpected response shape fails closed (PlatformAdminException)',
      () async {
        final transport = _RecordingTransport((_, _) async => 'not-a-map');
        final repo = RealPlatformAdminRepository(transport);
        await expectLater(
          repo.loadOverview(),
          throwsA(isA<PlatformAdminException>()),
        );
      },
    );

    test(
      '(9) missing/invalid config (null transport) fails closed and contacts '
      'no backend',
      () async {
        const repo = RealPlatformAdminRepository(null);
        await expectLater(
          repo.loadOverview(),
          throwsA(isA<PlatformAdminException>()),
        );
      },
    );
  });
}
