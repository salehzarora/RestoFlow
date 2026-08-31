/// The REAL platform-console repository (ADMIN-125C.2): proves each of the five
/// ADMIN-125C.1 wrappers is called with the right parameters and its JSON mapped
/// into the console models, WITHOUT a SupabaseClient or a network.
///
/// The mapping assertions that matter most are the NULL-PRESERVING ones. A
/// tenant with no `organization_subscriptions` row must arrive as `null`, not as
/// an empty string: every production tenant is in that state today, and an empty
/// string renders as a blank cell that reads like a failed load rather than the
/// real answer "no subscription".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/console_models.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/real_platform_admin_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);

  final Object? Function(String function, Map<String, dynamic> params) _handler;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    this.params.add(params);
    return _handler(function, params);
  }
}

/// A payload shaped exactly like production: four active tenants, one restaurant
/// and one branch each, ILS throughout, and NO subscription anywhere.
Object? _productionShaped(String function, Map<String, dynamic> params) {
  switch (function) {
    case 'platform_admin_console_overview':
      return <String, dynamic>{
        'ok': true,
        'organizations_total': 4,
        'organizations_active': 4,
        'organizations_suspended': 0,
        'restaurants_total': 4,
        'branches_total': 4,
        'active_memberships_total': 18,
        'subscriptions_trialing': 0,
        'subscriptions_active': 0,
        'subscriptions_past_due': 0,
        'subscriptions_canceled': 0,
        'server_ts': '2026-09-02T09:30:00.123456+00:00',
      };
    case 'platform_admin_list_subscribers':
      return <String, dynamic>{
        'ok': true,
        'rows': <Map<String, dynamic>>[
          {
            'organization_id': '2d31d850-3c50-4ed0-8abb-29c203130456',
            'organization_name': 'testo1',
            'organization_status': 'active',
            'created_at': '2026-07-04T10:00:00+00:00',
            'default_currency': 'ILS',
            'restaurants_count': 1,
            'branches_count': 1,
            'active_memberships_count': 7,
            // Every subscription field is genuinely null in production.
            'plan_code': null,
            'plan_display_name': null,
            'subscription_status': null,
            'current_period_start': null,
            'current_period_end': null,
          },
          {
            'organization_id': '32612928-b18c-46f5-8747-d291a82729e0',
            'organization_name': 'trt1',
            'organization_status': 'active',
            'created_at': '2026-07-04T11:00:00+00:00',
            'default_currency': 'ILS',
            'restaurants_count': 1,
            'branches_count': 1,
            'active_memberships_count': 1,
            'plan_code': 'basic',
            'plan_display_name': 'Basic',
            'subscription_status': 'active',
            'current_period_start': '2026-08-01T00:00:00+00:00',
            'current_period_end': '2026-09-01T00:00:00+00:00',
          },
        ],
        'total_count': 4,
        'limit': 25,
        'offset': 0,
        'server_ts': '2026-09-02T09:30:00+00:00',
      };
    case 'platform_admin_get_subscriber':
      return <String, dynamic>{
        'ok': true,
        'organization': {
          'id': params['p_organization_id'],
          'name': 'testo1',
          'status': 'active',
          'default_currency': 'ILS',
          'created_at': '2026-07-04T10:00:00+00:00',
        },
        'counts': {
          'restaurants_count': 1,
          'branches_count': 1,
          'active_memberships_count': 7,
        },
        'subscription': null,
        'restaurants': <Map<String, dynamic>>[
          {
            'id': 'fd0ee757-07fb-493f-9665-fe7d3ee52a8c',
            'name': 'Kafr Manda',
            'status': 'active',
            'branches_count': 1,
          },
        ],
        'server_ts': '2026-09-02T09:30:00+00:00',
      };
    case 'platform_admin_list_restaurants':
      return <String, dynamic>{
        'ok': true,
        'rows': <Map<String, dynamic>>[
          {
            'restaurant_id': 'fd0ee757-07fb-493f-9665-fe7d3ee52a8c',
            'restaurant_name': 'Kafr Manda',
            'restaurant_status': 'active',
            'organization_id': '2d31d850-3c50-4ed0-8abb-29c203130456',
            'organization_name': 'testo1',
            'organization_status': 'active',
            'branches_count': 1,
            'created_at': '2026-07-04T10:00:00+00:00',
            'currency_override': null,
            'effective_currency': 'ILS',
          },
          {
            'restaurant_id': '6c54b792-d82c-41d6-ac71-d23c9e13ab81',
            'restaurant_name': 'x1',
            'restaurant_status': 'active',
            'organization_id': '3f57f9d5-ce39-4c2a-a64e-38ff548f0726',
            'organization_name': 'x1',
            'organization_status': 'active',
            'branches_count': 1,
            'created_at': '2026-07-05T10:00:00+00:00',
            'currency_override': 'EUR',
            'effective_currency': 'EUR',
          },
        ],
        'total_count': 4,
        'limit': 25,
        'offset': 0,
        'server_ts': '2026-09-02T09:30:00+00:00',
      };
    case 'platform_admin_audit_search':
      return <String, dynamic>{
        'ok': true,
        'rows': <Map<String, dynamic>>[
          {
            'id': '077f065f-f7c9-468c-912d-db87e6703ee9',
            'actor_app_user_id': '92b4483f-0be3-462e-aced-e35e7493b337',
            'target_organization_id': null,
            'action': 'platform.console.overview',
            'reason': 'RestoFlow admin: platform overview (read-only)',
            'occurred_at': '2026-09-02T09:29:00+00:00',
          },
        ],
        'has_more': true,
        'next_cursor': {
          'occurred_at': '2026-09-02T09:29:00+00:00',
          'id': '077f065f-f7c9-468c-912d-db87e6703ee9',
        },
        'limit': 25,
        'server_ts': '2026-09-02T09:30:00+00:00',
      };
  }
  return null;
}

void main() {
  test('the overview maps every count and the SERVER day', () async {
    final transport = _FakeTransport(_productionShaped);
    final repo = RealPlatformAdminRepository(transport);

    final overview = await repo.loadConsoleOverview();

    expect(transport.calls, ['platform_admin_console_overview']);
    expect(transport.params.single['p_reason'], kReasonConsoleOverview);
    expect(overview.organizationsTotal, 4);
    expect(overview.organizationsActive, 4);
    expect(overview.organizationsSuspended, 0);
    expect(overview.restaurantsTotal, 4);
    expect(overview.branchesTotal, 4);
    expect(overview.activeMembershipsTotal, 18);
    expect(overview.hasNoSubscriptions, isTrue);
    expect(overview.serverDateLabel, '2026-09-02');
  });

  test(
    'subscribers: the query reaches the server and null stays NULL',
    () async {
      final transport = _FakeTransport(_productionShaped);
      final repo = RealPlatformAdminRepository(transport);

      final page = await repo.loadSubscribers(
        const SubscriberQuery(
          limit: 25,
          offset: 50,
          search: '  cafe  ',
          organizationStatus: 'active',
          planCode: 'basic',
          subscriptionStatus: 'past_due',
          sort: SubscriberSort.periodEndDesc,
        ),
      );

      final sent = transport.params.single;
      expect(sent['p_reason'], kReasonSubscriberList);
      expect(sent['p_limit'], 25);
      expect(sent['p_offset'], 50);
      // A blank-padded search is trimmed; a blank one becomes null (no filter).
      expect(sent['p_search'], 'cafe');
      expect(sent['p_org_status'], 'active');
      expect(sent['p_plan_code'], 'basic');
      expect(sent['p_subscription_status'], 'past_due');
      expect(sent['p_sort'], 'period_end_desc');

      expect(page.totalCount, 4);
      final unsubscribed = page.rows.first;
      expect(
        unsubscribed.organizationId,
        '2d31d850-3c50-4ed0-8abb-29c203130456',
      );
      expect(unsubscribed.hasSubscription, isFalse);
      expect(unsubscribed.subscriptionStatus, isNull);
      expect(unsubscribed.planCode, isNull);
      expect(unsubscribed.currentPeriodEndLabel, isNull);
      expect(unsubscribed.createdAtLabel, '2026-07-04');
      expect(unsubscribed.defaultCurrency, 'ILS');
      expect(unsubscribed.activeMembershipsCount, 7);

      final subscribed = page.rows[1];
      expect(subscribed.hasSubscription, isTrue);
      expect(subscribed.planDisplayName, 'Basic');
      expect(subscribed.currentPeriodEndLabel, '2026-09-01');
    },
  );

  test('a blank search is sent as null, not as an empty string', () async {
    final transport = _FakeTransport(_productionShaped);
    await RealPlatformAdminRepository(
      transport,
    ).loadSubscribers(const SubscriberQuery(search: '   '));
    expect(transport.params.single['p_search'], isNull);
  });

  test(
    'the detail maps the organization, counts and a NULL subscription',
    () async {
      final transport = _FakeTransport(_productionShaped);
      final repo = RealPlatformAdminRepository(transport);

      final detail = await repo.loadSubscriberDetail(
        '2d31d850-3c50-4ed0-8abb-29c203130456',
      );

      expect(transport.calls, ['platform_admin_get_subscriber']);
      expect(
        transport.params.single['p_organization_id'],
        '2d31d850-3c50-4ed0-8abb-29c203130456',
      );
      expect(transport.params.single['p_reason'], kReasonSubscriberDetail);
      expect(detail.organization.name, 'testo1');
      expect(detail.organization.createdAtLabel, '2026-07-04');
      expect(detail.counts.activeMembershipsCount, 7);
      expect(detail.hasSubscription, isFalse);
      expect(detail.restaurants.single.name, 'Kafr Manda');
    },
  );

  test('restaurants map the effective currency and the override', () async {
    final transport = _FakeTransport(_productionShaped);
    final repo = RealPlatformAdminRepository(transport);

    final page = await repo.loadRestaurants(
      const RestaurantQuery(sort: RestaurantSort.organizationAsc, search: 'x'),
    );

    expect(transport.params.single['p_sort'], 'organization_asc');
    expect(transport.params.single['p_reason'], kReasonRestaurantList);
    expect(page.rows.first.effectiveCurrency, 'ILS');
    expect(page.rows.first.hasCurrencyOverride, isFalse);
    expect(page.rows[1].currencyOverride, 'EUR');
    expect(page.rows[1].effectiveCurrency, 'EUR');
    expect(page.rows[1].hasCurrencyOverride, isTrue);
  });

  test(
    'the audit page maps the keyset cursor and keeps the RAW timestamp',
    () async {
      final transport = _FakeTransport(_productionShaped);
      final repo = RealPlatformAdminRepository(transport);

      final page = await repo.loadAuditPage(const AuditQuery(limit: 25));

      expect(transport.params.single['p_reason'], kReasonAuditLog);
      // Page 1 sends BOTH cursor halves as null — the server rejects half a
      // cursor with 22023 rather than quietly scanning from the top.
      expect(transport.params.single['p_cursor_occurred_at'], isNull);
      expect(transport.params.single['p_cursor_id'], isNull);

      expect(page.hasMore, isTrue);
      expect(page.nextCursor, isNotNull);
      final row = page.rows.single;
      expect(row.occurredAtRaw, '2026-09-02T09:29:00+00:00');
      expect(row.occurredAtLabel, '2026-09-02 09:29');
      expect(row.actorShortId, '92b4483f');
      expect(row.targetOrganizationId, isNull);
      expect(row.targetShortId, isNull);
    },
  );

  test('a cursor is sent as BOTH halves together', () async {
    final transport = _FakeTransport(_productionShaped);
    await RealPlatformAdminRepository(transport).loadAuditPage(
      const AuditQuery(
        cursor: AuditCursor(occurredAt: '2026-09-02T09:29:00+00:00', id: 'abc'),
      ),
    );
    expect(
      transport.params.single['p_cursor_occurred_at'],
      '2026-09-02T09:29:00+00:00',
    );
    expect(transport.params.single['p_cursor_id'], 'abc');
  });

  test('every page carries its OWN audit reason, so the platform log '
      'distinguishes which surface was opened', () async {
    final transport = _FakeTransport(_productionShaped);
    final repo = RealPlatformAdminRepository(transport);
    await repo.loadConsoleOverview();
    await repo.loadSubscribers(const SubscriberQuery());
    await repo.loadSubscriberDetail('2d31d850-3c50-4ed0-8abb-29c203130456');
    await repo.loadRestaurants(const RestaurantQuery());
    await repo.loadAuditPage(const AuditQuery());

    final reasons = transport.params.map((p) => p['p_reason']).toList();
    expect(reasons, [
      kReasonConsoleOverview,
      kReasonSubscriberList,
      kReasonSubscriberDetail,
      kReasonRestaurantList,
      kReasonAuditLog,
    ]);
    expect(reasons.toSet(), hasLength(5));
    expect(reasons.every((r) => (r as String).isNotEmpty), isTrue);
  });

  test('the repository calls ONLY the five public wrappers — never the app '
      'schema and never a table', () async {
    final transport = _FakeTransport(_productionShaped);
    final repo = RealPlatformAdminRepository(transport);
    await repo.loadConsoleOverview();
    await repo.loadSubscribers(const SubscriberQuery());
    await repo.loadSubscriberDetail('x');
    await repo.loadRestaurants(const RestaurantQuery());
    await repo.loadAuditPage(const AuditQuery());

    expect(transport.calls, [
      'platform_admin_console_overview',
      'platform_admin_list_subscribers',
      'platform_admin_get_subscriber',
      'platform_admin_list_restaurants',
      'platform_admin_audit_search',
    ]);
    // `anon` has no USAGE on schema `app` on hosted, so an `app.`-prefixed call
    // would fail closed — but it must never be attempted in the first place.
    expect(transport.calls.any((c) => c.startsWith('app')), isFalse);
  });

  test('no transport -> fail closed, no backend contacted', () async {
    const repo = RealPlatformAdminRepository(null);
    for (final read in <Future<Object?> Function()>[
      repo.loadConsoleOverview,
      () => repo.loadSubscribers(const SubscriberQuery()),
      () => repo.loadSubscriberDetail('x'),
      () => repo.loadRestaurants(const RestaurantQuery()),
      () => repo.loadAuditPage(const AuditQuery()),
    ]) {
      await expectLater(
        read(),
        throwsA(
          isA<PlatformAdminException>().having(
            (e) => e.kind,
            'kind',
            PlatformAdminErrorKind.notConfigured,
          ),
        ),
      );
    }
  });

  test(
    'a 42501 becomes accessDenied; the raw code never reaches the UI',
    () async {
      final transport = _FakeTransport(
        (function, params) => throw const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
          message: 'permission denied for function',
        ),
      );
      final repo = RealPlatformAdminRepository(transport);
      await expectLater(
        repo.loadConsoleOverview(),
        throwsA(
          isA<PlatformAdminException>()
              .having(
                (e) => e.kind,
                'kind',
                PlatformAdminErrorKind.accessDenied,
              )
              .having((e) => e.message, 'message', isNot(contains('42501')))
              .having(
                (e) => e.message,
                'message',
                isNot(contains('permission denied for function')),
              ),
        ),
      );
    },
  );

  test(
    'transient / server / unknown failures are retryable, not auth',
    () async {
      for (final kind in <SyncTransportErrorKind>[
        SyncTransportErrorKind.transient,
        SyncTransportErrorKind.server,
        SyncTransportErrorKind.unknown,
      ]) {
        final transport = _FakeTransport(
          (function, params) => throw SyncTransportException(kind),
        );
        await expectLater(
          RealPlatformAdminRepository(
            transport,
          ).loadRestaurants(const RestaurantQuery()),
          throwsA(
            isA<PlatformAdminException>().having(
              (e) => e.kind,
              'kind',
              PlatformAdminErrorKind.unexpected,
            ),
          ),
        );
      }
    },
  );

  test(
    'an unexpected response shape fails safely instead of rendering junk',
    () async {
      final transport = _FakeTransport((function, params) => 'not a map');
      await expectLater(
        RealPlatformAdminRepository(transport).loadConsoleOverview(),
        throwsA(isA<PlatformAdminException>()),
      );
    },
  );
}
