/// The REAL platform-console repository (ADMIN-125C.2) — reads the live
/// platform through the ADMIN-125C.1 public wrappers, READ-ONLY (D-026).
///
/// Selected ONLY in real mode; demo mode keeps [DemoPlatformAdminRepository] as
/// the DEFAULT. It calls five narrow, authenticated-only `public.*` SECURITY
/// INVOKER wrappers via the shared [SyncRpcTransport] (publishable key + the
/// signed-in platform-admin JWT — never a service-role key, D-011; never the
/// `app` schema directly, which `anon` cannot even reach):
///
///   * `public.platform_admin_console_overview(p_reason)`
///   * `public.platform_admin_list_subscribers(p_reason, p_limit, p_offset, ...)`
///   * `public.platform_admin_get_subscriber(p_organization_id, p_reason)`
///   * `public.platform_admin_list_restaurants(p_reason, p_limit, p_offset, ...)`
///   * `public.platform_admin_audit_search(p_reason, p_limit, p_cursor..., ...)`
///
/// Each call carries its OWN reason and is audited server-side under its own
/// action, so the platform log records which page an operator opened rather
/// than one undifferentiated "admin read".
///
/// NO CROSS-TENANT TABLE READS. Every figure comes from a guarded RPC; this
/// class never selects from `organizations`, `restaurants`, `memberships` or
/// `organization_subscriptions` directly. That matters beyond style:
/// `organization_subscriptions` is RLS FORCED to a tenant membership, and a
/// platform admin holds none — a direct read would silently return zero rows
/// rather than fail, and the console would quietly under-report.
///
/// FAIL-CLOSED: a missing transport (real mode selected but the Supabase config
/// is absent/invalid) and any backend error — `42501` (no active grant / missing
/// `aal2` MFA / rejected reason / unknown tenant), network, or server — surface
/// as a [PlatformAdminException] that the pages render as a safe state. No raw
/// JSON, SQLSTATE or stack trace ever reaches the user, and there is NEVER a
/// fallback to demo data.
library;

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'console_models.dart';
import 'platform_admin_repository.dart';

/// The fixed, READ-ONLY audit reasons. One per page, so the platform audit log
/// distinguishes which console surface an operator actually opened. The server
/// requires a non-empty reason and stores it verbatim.
const String kReasonConsoleOverview =
    'RestoFlow admin: platform overview (read-only)';
const String kReasonSubscriberList =
    'RestoFlow admin: subscriber list (read-only)';
const String kReasonSubscriberDetail =
    'RestoFlow admin: subscriber detail (read-only)';
const String kReasonRestaurantList =
    'RestoFlow admin: restaurant list (read-only)';
const String kReasonAuditLog = 'RestoFlow admin: audit log (read-only)';

/// Reads the platform console from the ADMIN-125C.1 public wrappers.
class RealPlatformAdminRepository implements PlatformAdminRepository {
  const RealPlatformAdminRepository(this._transport);

  /// The shared public-schema RPC transport (publishable key + authenticated
  /// JWT). Null when real mode was selected but the Supabase config was missing
  /// or invalid (fail-closed): every load then throws without contacting a
  /// backend.
  final SyncRpcTransport? _transport;

  Future<Map<String, dynamic>> _call(
    String rpc,
    Map<String, dynamic> args,
  ) async {
    final transport = _transport;
    if (transport == null) {
      throw const PlatformAdminException(
        'platform admin real mode is not configured (no Supabase URL / '
        'publishable key); staying fail-closed.',
        kind: PlatformAdminErrorKind.notConfigured,
      );
    }
    try {
      return _asMap(await transport.invoke(rpc, args));
    } on SyncTransportException catch (e) {
      throw _exceptionForTransport(e);
    }
  }

  @override
  Future<ConsoleOverview> loadConsoleOverview() async {
    final raw = await _call('platform_admin_console_overview', {
      'p_reason': kReasonConsoleOverview,
    });
    return ConsoleOverview(
      organizationsTotal: _int(raw['organizations_total']),
      organizationsActive: _int(raw['organizations_active']),
      organizationsSuspended: _int(raw['organizations_suspended']),
      restaurantsTotal: _int(raw['restaurants_total']),
      branchesTotal: _int(raw['branches_total']),
      activeMembershipsTotal: _int(raw['active_memberships_total']),
      subscriptionsTrialing: _int(raw['subscriptions_trialing']),
      subscriptionsActive: _int(raw['subscriptions_active']),
      subscriptionsPastDue: _int(raw['subscriptions_past_due']),
      subscriptionsCanceled: _int(raw['subscriptions_canceled']),
      serverDateLabel: dateLabelOf(raw['server_ts']),
    );
  }

  @override
  Future<SubscriberPage> loadSubscribers(SubscriberQuery query) async {
    final raw = await _call('platform_admin_list_subscribers', {
      'p_reason': kReasonSubscriberList,
      'p_limit': query.limit,
      'p_offset': query.offset,
      'p_search': _blankToNull(query.search),
      'p_org_status': query.organizationStatus,
      'p_plan_code': query.planCode,
      'p_subscription_status': query.subscriptionStatus,
      'p_sort': query.sort.wire,
    });
    return SubscriberPage(
      rows: [
        for (final row in _rows(raw['rows']))
          SubscriberRow(
            organizationId: _string(row['organization_id']),
            organizationName: _string(row['organization_name']),
            organizationStatus: _string(row['organization_status']),
            createdAtLabel: dateLabelOf(row['created_at']),
            defaultCurrency: _string(row['default_currency']),
            restaurantsCount: _int(row['restaurants_count']),
            branchesCount: _int(row['branches_count']),
            activeMembershipsCount: _int(row['active_memberships_count']),
            // Null-preserving: a tenant with no subscription must stay null all
            // the way to the widget, so the UI can say so instead of showing an
            // empty string that reads like missing data.
            planCode: _stringOrNull(row['plan_code']),
            planDisplayName: _stringOrNull(row['plan_display_name']),
            subscriptionStatus: _stringOrNull(row['subscription_status']),
            currentPeriodStartLabel: _dateOrNull(row['current_period_start']),
            currentPeriodEndLabel: _dateOrNull(row['current_period_end']),
          ),
      ],
      totalCount: _int(raw['total_count']),
      limit: _int(raw['limit']),
      offset: _int(raw['offset']),
    );
  }

  @override
  Future<SubscriberDetail> loadSubscriberDetail(String organizationId) async {
    final raw = await _call('platform_admin_get_subscriber', {
      'p_organization_id': organizationId,
      'p_reason': kReasonSubscriberDetail,
    });
    final org = _asMap(raw['organization']);
    final counts = _asMap(raw['counts']);
    final sub = raw['subscription'];
    return SubscriberDetail(
      organization: SubscriberOrganization(
        id: _string(org['id']),
        name: _string(org['name']),
        status: _string(org['status']),
        defaultCurrency: _string(org['default_currency']),
        createdAtLabel: dateLabelOf(org['created_at']),
      ),
      counts: SubscriberCounts(
        restaurantsCount: _int(counts['restaurants_count']),
        branchesCount: _int(counts['branches_count']),
        activeMembershipsCount: _int(counts['active_memberships_count']),
      ),
      subscription: sub is Map
          ? SubscriptionInfo(
              planCode: _string(sub['plan_code']),
              planDisplayName: _string(sub['plan_display_name']),
              status: _string(sub['status']),
              currentPeriodStartLabel: _dateOrNull(sub['current_period_start']),
              currentPeriodEndLabel: _dateOrNull(sub['current_period_end']),
            )
          : null,
      restaurants: [
        for (final r in _rows(raw['restaurants']))
          SubscriberRestaurant(
            id: _string(r['id']),
            name: _string(r['name']),
            status: _string(r['status']),
            branchesCount: _int(r['branches_count']),
          ),
      ],
    );
  }

  @override
  Future<RestaurantPage> loadRestaurants(RestaurantQuery query) async {
    final raw = await _call('platform_admin_list_restaurants', {
      'p_reason': kReasonRestaurantList,
      'p_limit': query.limit,
      'p_offset': query.offset,
      'p_search': _blankToNull(query.search),
      'p_org_status': query.organizationStatus,
      'p_sort': query.sort.wire,
    });
    return RestaurantPage(
      rows: [
        for (final row in _rows(raw['rows']))
          RestaurantRow(
            restaurantId: _string(row['restaurant_id']),
            restaurantName: _string(row['restaurant_name']),
            restaurantStatus: _string(row['restaurant_status']),
            organizationId: _string(row['organization_id']),
            organizationName: _string(row['organization_name']),
            organizationStatus: _string(row['organization_status']),
            branchesCount: _int(row['branches_count']),
            createdAtLabel: dateLabelOf(row['created_at']),
            currencyOverride: _stringOrNull(row['currency_override']),
            effectiveCurrency: _string(row['effective_currency']),
          ),
      ],
      totalCount: _int(raw['total_count']),
      limit: _int(raw['limit']),
      offset: _int(raw['offset']),
    );
  }

  @override
  Future<AuditPage> loadAuditPage(AuditQuery query) async {
    final cursor = query.cursor;
    final raw = await _call('platform_admin_audit_search', {
      'p_reason': kReasonAuditLog,
      'p_limit': query.limit,
      // BOTH cursor halves travel together or neither does — the server rejects
      // a half cursor with 22023 rather than quietly scanning from the top.
      'p_cursor_occurred_at': cursor?.occurredAt,
      'p_cursor_id': cursor?.id,
      'p_action': query.action,
      'p_target_organization_id': query.targetOrganizationId,
      'p_from': query.from,
      'p_to': query.to,
    });
    final next = raw['next_cursor'];
    return AuditPage(
      rows: [
        for (final row in _rows(raw['rows']))
          AuditEvent(
            id: _string(row['id']),
            actorAppUserId: _string(row['actor_app_user_id']),
            action: _string(row['action']),
            reason: _string(row['reason']),
            // Kept RAW: this value seeds the next keyset cursor, and a
            // reformatted timestamp would land the next page in the wrong place.
            occurredAtRaw: _string(row['occurred_at']),
            targetOrganizationId: _stringOrNull(row['target_organization_id']),
          ),
      ],
      hasMore: raw['has_more'] == true,
      limit: _int(raw['limit']),
      nextCursor: next is Map
          ? AuditCursor(
              occurredAt: _string(next['occurred_at']),
              id: _string(next['id']),
            )
          : null,
    );
  }
}

/// Maps a transport failure to a categorized [PlatformAdminException]. The raw
/// code and backend message are deliberately omitted so nothing leaks to the
/// UI. A `42501` is the one auth case and surfaces as
/// [PlatformAdminErrorKind.accessDenied]; everything else is the generic,
/// retryable [PlatformAdminErrorKind.unexpected].
PlatformAdminException _exceptionForTransport(SyncTransportException e) =>
    switch (e.kind) {
      SyncTransportErrorKind.auth => const PlatformAdminException(
        'platform admin access denied: an active platform-admin grant and '
        'multi-factor (aal2) sign-in are required (D-026 read-only).',
        kind: PlatformAdminErrorKind.accessDenied,
      ),
      SyncTransportErrorKind.transient => const PlatformAdminException(
        'platform admin: a temporary network or server issue occurred - please '
        'retry.',
      ),
      SyncTransportErrorKind.server => const PlatformAdminException(
        'platform admin: the server could not complete the request.',
      ),
      SyncTransportErrorKind.unknown => const PlatformAdminException(
        'platform admin: an unexpected error occurred.',
      ),
    };

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) return value.cast<String, dynamic>();
  throw const PlatformAdminException(
    'platform admin: unexpected response shape from the server.',
  );
}

Iterable<Map<String, dynamic>> _rows(Object? value) sync* {
  if (value is! List) return;
  for (final row in value) {
    if (row is Map) yield row.cast<String, dynamic>();
  }
}

String _string(Object? value) =>
    value is String ? value : (value?.toString() ?? '');

/// Null-PRESERVING string read. `_string` would turn a null into `''`, which the
/// UI cannot distinguish from a real empty value — and "no subscription" is a
/// state the operator must be able to see.
String? _stringOrNull(Object? value) => value == null ? null : _string(value);

String? _dateOrNull(Object? value) {
  if (value == null) return null;
  final label = dateLabelOf(value);
  return label.isEmpty ? null : label;
}

int _int(Object? value) => switch (value) {
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

/// A blank search box means "no filter", not "match the empty string".
String? _blankToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
