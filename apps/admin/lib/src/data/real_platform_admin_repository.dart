/// The REAL platform-admin repository (RF-128) - reads the RF-091 platform panel
/// through the RF-125 public wrappers, READ-ONLY (DECISION D-026).
///
/// Selected ONLY in real mode; demo mode keeps [DemoPlatformAdminRepository] as
/// the DEFAULT. It calls two narrow, authenticated-only `public.*` SECURITY
/// INVOKER wrappers via the shared [SyncRpcTransport] (anon key + the signed-in
/// platform-admin JWT - never a service-role key, D-011; never the `app` schema):
///   * `public.platform_admin_organization_overview(p_reason)`  (RF-125 / RF-091)
///   * `public.platform_admin_recent_audit(p_reason, p_limit)`   (RF-125 / RF-091)
/// and maps their JSON into the existing [PlatformOverview] the UI already
/// renders. It NEVER mutates, impersonates, or grants/revokes (D-026 read-only),
/// and never calls `public.platform_admin_get_organization` here (the overview
/// needs only the two list reads).
///
/// NARROW PANEL: the RF-091 platform panel exposes per-org summaries + counts +
/// recent platform-admin audit events only. It does NOT expose device counts,
/// today's orders, active-branch counts, or per-branch health, so those KPIs are
/// mapped to 0 / empty here (an honest "not provided by this read", not a
/// fabricated value); the org/restaurant/branch counts, the active-org count,
/// and the organization + activity lists are mapped from real data. The screen
/// (RF-134) gates the demo banner to demo mode and HIDES these unavailable KPIs
/// (and the per-branch health section) in real mode, so the 0 / empty
/// placeholders here are never presented to the user as real figures.
///
/// FAIL-CLOSED: a missing transport (real mode selected but the Supabase config
/// is absent/invalid) and any backend error - `42501` (no active
/// `platform_admin_grant` / missing `aal2` MFA / rejected reason), network, or
/// server - surface as a [PlatformAdminException], which the existing error
/// state renders as a safe, generic message. No raw JSON or stack trace ever
/// reaches the user.
library;

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'platform_admin_repository.dart';
import 'platform_overview.dart';

/// The fixed, READ-ONLY audit reason sent to the platform-admin wrappers. The
/// RPCs require a non-empty reason and tag the (audited) read with it; this is a
/// clear developer/audit reason describing the overview load.
const String kPlatformAdminOverviewReason =
    'RestoFlow admin app: platform overview (read-only)';

/// How many recent platform-admin audit events to request (server clamps the
/// value to `[1, 200]`).
const int kPlatformAdminAuditLimit = 50;

/// Reads the platform overview from the RF-125 public platform-admin wrappers.
class RealPlatformAdminRepository implements PlatformAdminRepository {
  const RealPlatformAdminRepository(
    this._transport, {
    this.reason = kPlatformAdminOverviewReason,
    this.auditLimit = kPlatformAdminAuditLimit,
  });

  /// The shared public-schema RPC transport (anon key + authenticated JWT).
  /// Null when real mode was selected but the Supabase config was missing or
  /// invalid (fail-closed): [loadOverview] then throws without contacting a
  /// backend.
  final SyncRpcTransport? _transport;

  /// The non-empty audit reason sent to every wrapper call (D-026 reason-tagged).
  final String reason;

  /// The recent-audit page size (server clamps to `[1, 200]`).
  final int auditLimit;

  @override
  Future<PlatformOverview> loadOverview() async {
    final transport = _transport;
    if (transport == null) {
      throw const PlatformAdminException(
        'platform admin real mode is not configured (no Supabase URL / anon '
        'key); staying fail-closed.',
        kind: PlatformAdminErrorKind.notConfigured,
      );
    }
    try {
      final overviewRaw = await transport.invoke(
        'platform_admin_organization_overview',
        <String, dynamic>{'p_reason': reason},
      );
      final auditRaw = await transport.invoke(
        'platform_admin_recent_audit',
        <String, dynamic>{'p_reason': reason, 'p_limit': auditLimit},
      );
      return _mapOverview(overviewRaw, auditRaw);
    } on SyncTransportException catch (e) {
      // Surface backend failures through a categorized safe state with a safe,
      // developer-facing message - never the raw code/JSON (no wall of text).
      throw _exceptionForTransport(e);
    }
  }

  PlatformOverview _mapOverview(Object? overviewRaw, Object? auditRaw) {
    final overview = _asMap(overviewRaw);
    final audit = _asMap(auditRaw);

    final organizations = <OrgSummary>[];
    var activeOrganizationCount = 0;
    var restaurantCount = 0;
    var branchCount = 0;
    for (final row in _asList(overview['organizations'])) {
      if (row is! Map) continue;
      final org = row.cast<String, dynamic>();
      final status = _string(org['status']);
      final restaurants = _intValue(org['restaurants_count']);
      final branches = _intValue(org['branches_count']);
      if (status == 'active') activeOrganizationCount++;
      restaurantCount += restaurants;
      branchCount += branches;
      organizations.add(
        OrgSummary(
          organizationName: _string(org['name']),
          restaurantCount: restaurants,
          branchCount: branches,
          status: status,
          // Not provided by the RF-091 read panel - honest placeholders, not
          // fabricated data.
          plan: '—',
          createdAtLabel: '—',
        ),
      );
    }
    organizations.sort(
      (a, b) => a.organizationName.compareTo(b.organizationName),
    );

    final activity = <ActivityEvent>[];
    for (final row in _asList(audit['events'])) {
      if (row is! Map) continue;
      final event = row.cast<String, dynamic>();
      activity.add(
        ActivityEvent(
          timestampLabel: _timestampLabel(_string(event['occurred_at'])),
          action: _string(event['action']),
          summary: _string(event['reason']),
        ),
      );
    }
    activity.sort((a, b) => b.timestampLabel.compareTo(a.timestampLabel));

    final organizationCount = organizations.length;
    return PlatformOverview(
      generatedDateLabel: _dateLabel(overview['server_ts']),
      organizationCount: organizationCount,
      activeOrganizationCount: activeOrganizationCount,
      restaurantCount: restaurantCount,
      branchCount: branchCount,
      // The RF-091 read panel does not expose these operational metrics, so they
      // stay at an honest 0 / empty (see the class doc; UI follow-up tracked).
      activeBranchCount: 0,
      deviceCount: 0,
      warningCount: organizationCount - activeOrganizationCount,
      todayOrderCount: 0,
      organizations: organizations,
      branchHealth: const <BranchHealth>[],
      activity: activity,
    );
  }
}

/// Maps a transport failure to a categorized [PlatformAdminException]. The raw
/// code and backend message are deliberately omitted so nothing leaks to the
/// UI. A `42501` (no active platform-admin grant / missing aal2 MFA / rejected
/// reason) is the one auth case and surfaces as
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

List<dynamic> _asList(Object? value) =>
    value is List ? value : const <dynamic>[];

String _string(Object? value) =>
    value is String ? value : (value?.toString() ?? '');

int _intValue(Object? value) => value is num ? value.toInt() : 0;

/// `2026-06-28T10:15:30.123Z` -> `2026-06-28` (date only; empty when absent).
String _dateLabel(Object? serverTs) =>
    serverTs is String && serverTs.length >= 10
    ? serverTs.substring(0, 10)
    : '';

/// `2026-06-28T10:15:30Z` -> `2026-06-28 10:15` (matches the demo label shape).
String _timestampLabel(String iso) =>
    iso.length >= 16 ? iso.substring(0, 16).replaceFirst('T', ' ') : iso;
