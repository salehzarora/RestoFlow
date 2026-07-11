/// Real-mode Activity-log repository (AUDIT-LOG-DASHBOARD-001).
///
/// Reads the `public.owner_audit_events` RPC — GUC-free, management-only
/// authorized, RLS-safe, keyset-paginated, with SERVER-secret-scrubbed old/new
/// payloads (D-011/D-013) — over the SAME authenticated anon-key transport the
/// rest of the real dashboard uses (the GoTrue session rides the client;
/// identity is server-derived).
///
/// FAIL-CLOSED: with no transport/scope it throws [RealRepoNotWiredError]; a
/// transport failure or a rejected (`ok != true`) body throws
/// [AuditLogException] — never fabricated data, never a silent demo fallback. A
/// permission / tenant / auth denial stays fail-closed (it is NOT "missing").
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'audit_filter_options_repository.dart' show auditCoveredScope;
import 'audit_log_models.dart';
import 'audit_log_repository.dart';

/// Reads the operational audit timeline from the AUDIT-LOG-DASHBOARD-001 RPC.
class RealAuditLogRepository implements AuditLogRepository {
  const RealAuditLogRepository(this.config, {this.scope, this.transport});

  /// The validated client runtime config (anon key only). Null when real mode
  /// was selected but the Supabase config was missing/invalid (fail-closed
  /// upstream in `RuntimeConfig`).
  final SupabaseBootstrapConfig? config;

  /// The active membership (org/restaurant/branch) the reads are scoped to.
  final MembershipContext? scope;

  /// The AUTHENTICATED transport. Null => not wired (fail-closed).
  final SyncRpcTransport? transport;

  @override
  Future<AuditPage> loadEvents(AuditQuery query, {String? cursor}) async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const RealRepoNotWiredError(
        'activity-log: no authenticated transport/scope - real read not wired',
      );
    }
    // Scope: a selected branch narrows to that (restaurant, branch); otherwise
    // the caller's COVERED default scope ("all permitted branches") — org-wide
    // for an org_owner, restaurant-wide for a restaurant_owner, the one branch
    // for a manager. The backend re-checks coverage and intersects (a stale /
    // out-of-scope branch fails closed with 42501, no existence leak).
    final covered = auditCoveredScope(m);
    final restaurantId = query.branch?.restaurantId ?? covered.restaurantId;
    final branchId = query.branch?.branchId ?? covered.branchId;
    final Object? raw;
    try {
      raw = await t.invoke('owner_audit_events', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_range': query.range.wire,
        'p_category': query.category.wire,
        'p_sensitive_only': query.sensitiveOnly,
        'p_actor_employee_profile_id': query.actor?.employeeProfileId,
        'p_limit': 25,
        'p_cursor': cursor,
      });
    } on SyncTransportException {
      throw const AuditLogException('owner_audit_events transport failure');
    }
    if (raw is! Map || raw['ok'] != true) {
      throw const AuditLogException('owner_audit_events rejected');
    }
    final currency = (raw['currency_code'] ?? '').toString();
    final eventsRaw = raw['events'];
    final events = <AuditEvent>[];
    if (eventsRaw is List) {
      for (final row in eventsRaw) {
        if (row is! Map) continue;
        events.add(_event(row));
      }
    }
    return AuditPage(
      events: events,
      hasMore: raw['has_more'] == true,
      nextCursor: _strOrNull(raw['next_cursor']),
      currencyCode: currency,
    );
  }

  AuditEvent _event(Map row) => AuditEvent(
    eventId: (row['event_id'] ?? '').toString(),
    action: (row['action'] ?? '').toString(),
    category: (row['category'] ?? 'other').toString(),
    occurredAtLabel: (row['occurred_at'] ?? '').toString(),
    actorName: _strOrNull(row['actor_name']),
    restaurantName: _strOrNull(row['restaurant_name']),
    branchName: _strOrNull(row['branch_name']),
    deviceLabel: _strOrNull(row['device_label']),
    reason: _strOrNull(row['reason']),
    oldValues: _map(row['old_values']),
    newValues: _map(row['new_values']),
  );

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }

  static String? _strOrNull(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
