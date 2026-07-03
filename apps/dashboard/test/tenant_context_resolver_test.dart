import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/context/tenant_context_resolver.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Future<Object?> Function(String function, Map<String, dynamic> params)
  _handler;
  String? lastFunction;
  Map<String, dynamic>? lastParams;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    lastFunction = function;
    lastParams = params;
    return _handler(function, params);
  }
}

const _orgWideOwner = MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Olive Group',
  restaurantId: null,
  restaurantName: null,
  branchId: null,
  branchName: null,
  role: MembershipRole.orgOwner,
  status: 'active',
);

/// The verbatim `public.list_org_structure` ok-envelope
/// (mvp_org_structure_read migration).
Map<String, Object?> _structure() => {
  'ok': true,
  'entity': 'org_structure',
  'organization': {
    'id': 'org-1',
    'name': 'Olive Group',
    'default_currency': 'ILS',
  },
  'restaurants': [
    {
      'id': 'rest-1',
      'name': 'Olive North',
      'currency_override': null,
      'timezone': 'UTC',
      'status': 'active',
      'branches': [
        {
          'id': 'branch-1',
          'name': 'Main hall',
          'timezone': 'UTC',
          'status': 'active',
        },
        {
          'id': 'branch-2',
          'name': 'Terrace',
          'timezone': 'UTC',
          'status': 'active',
        },
      ],
    },
    {
      'id': 'rest-2',
      'name': 'Olive South',
      'currency_override': 'EUR',
      'timezone': 'UTC',
      'status': 'active',
      'branches': <Object?>[],
    },
  ],
  'server_ts': '2026-07-03T10:00:00Z',
};

void main() {
  test('an org-wide owner resolves to the FIRST restaurant + branch and the '
      'org default currency', () async {
    final transport = _FakeTransport((_, _) async => _structure());
    final resolved = await resolveTenantContext(
      transport: transport,
      membership: _orgWideOwner,
    );

    expect(transport.lastFunction, 'list_org_structure');
    expect(transport.lastParams, {'p_organization_id': 'org-1'});
    expect(resolved.membership.restaurantId, 'rest-1');
    expect(resolved.membership.restaurantName, 'Olive North');
    expect(resolved.membership.branchId, 'branch-1');
    expect(resolved.membership.branchName, 'Main hall');
    expect(resolved.currencyCode, 'ILS');
    // Identity/role/status pass through untouched.
    expect(resolved.membership.id, 'm-1');
    expect(resolved.membership.role, MembershipRole.orgOwner);
  });

  test('a scoped membership keeps ITS restaurant/branch; the restaurant '
      'currency override wins', () async {
    const scoped = MembershipContext(
      id: 'm-2',
      organizationId: 'org-1',
      organizationName: 'Olive Group',
      restaurantId: 'rest-2',
      restaurantName: 'Olive South',
      branchId: null,
      branchName: null,
      role: MembershipRole.restaurantOwner,
      status: 'active',
    );
    final transport = _FakeTransport((_, _) async => _structure());
    final resolved = await resolveTenantContext(
      transport: transport,
      membership: scoped,
    );

    expect(resolved.membership.restaurantId, 'rest-2');
    expect(resolved.currencyCode, 'EUR');
    // rest-2 has no branches: the membership's (null) branch is kept.
    expect(resolved.membership.branchId, isNull);
  });

  test('a denied/failed structure read passes the membership through with a '
      'NULL currency (fail closed, never USD-by-default)', () async {
    final transport = _FakeTransport(
      (_, _) async => throw const SyncTransportException(
        SyncTransportErrorKind.auth,
        code: '42501',
        message: 'denied',
      ),
    );
    final resolved = await resolveTenantContext(
      transport: transport,
      membership: _orgWideOwner,
    );
    expect(resolved.membership, same(_orgWideOwner));
    expect(resolved.currencyCode, isNull);
  });

  test('a permission_denied envelope also passes through unresolved', () async {
    final transport = _FakeTransport(
      (_, _) async => const {
        'ok': false,
        'error': 'permission_denied',
        'entity': 'org_structure',
      },
    );
    final resolved = await resolveTenantContext(
      transport: transport,
      membership: _orgWideOwner,
    );
    expect(resolved.membership.restaurantId, isNull);
    expect(resolved.currencyCode, isNull);
  });

  test('an org with no restaurants keeps the membership but still surfaces '
      'the org currency', () async {
    final empty = _structure()..['restaurants'] = <Object?>[];
    final transport = _FakeTransport((_, _) async => empty);
    final resolved = await resolveTenantContext(
      transport: transport,
      membership: _orgWideOwner,
    );
    expect(resolved.membership.restaurantId, isNull);
    expect(resolved.currencyCode, 'ILS');
  });
}
