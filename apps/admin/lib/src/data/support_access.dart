/// ADMIN-126B — starting a read-only platform SUPPORT session.
///
/// Deliberately a SEPARATE seam from [PlatformAdminRepository], which is
/// documented and enforced as read-only. Opening a support session does write a
/// row — on the PLATFORM plane (`platform_support_sessions` + an audit event),
/// never on tenant data — and folding that onto a seam whose contract says "no
/// write method exists" would make that contract a lie for the next reader.
///
/// What this seam CANNOT do, by construction:
///   * it cannot create a membership — the server never issues one;
///   * it cannot grant a write rank — support raises the READ rank only;
///   * it cannot log the operator in as the owner — the actor stays the
///     platform account for every subsequent read and every audit row.
///
/// The token returned here is the ONLY copy: the server stores a SHA-256 hash
/// and nothing else. It is handed straight to the Dashboard in a URL fragment,
/// spent within ~60 seconds, and never persisted, logged, or shown.
library;

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'platform_admin_repository.dart';

/// The audit reason prefix for a support start. The operator's typed reason is
/// appended, so the platform log records WHY someone opened a tenant's
/// dashboard, in their own words.
const String kReasonSupportStart = 'VEYRO support (read-only): ';

/// A freshly opened support session plus its single-use handoff.
class SupportHandoff {
  const SupportHandoff({
    required this.supportSessionId,
    required this.handoffToken,
    required this.organizationName,
    this.restaurantName,
  });

  final String supportSessionId;

  /// The one-time plaintext token. Held only long enough to build the launch
  /// URL — never stored, never rendered, never logged.
  final String handoffToken;

  final String organizationName;
  final String? restaurantName;

  /// The Dashboard launch URL for this handoff.
  ///
  /// The token goes in the FRAGMENT, not the query string: a fragment is never
  /// sent to the server, so it cannot land in an access log, a proxy trace, or
  /// a `Referer` header on the way out.
  String launchUrl(String dashboardUrl) {
    final base = dashboardUrl.endsWith('/')
        ? dashboardUrl.substring(0, dashboardUrl.length - 1)
        : dashboardUrl;
    return '$base/#support=${Uri.encodeComponent(handoffToken)}';
  }
}

/// Opens support sessions. One implementation talks to the server; the demo one
/// refuses, because there is no live tenant behind demo data to support.
abstract class PlatformSupportLauncher {
  Future<SupportHandoff> start({
    required String organizationId,
    String? restaurantId,
    required String reason,
  });
}

/// Demo mode has no tenant to support, and says so rather than fabricating a
/// session that would open a dashboard full of demo numbers.
class DemoPlatformSupportLauncher implements PlatformSupportLauncher {
  const DemoPlatformSupportLauncher();

  @override
  Future<SupportHandoff> start({
    required String organizationId,
    String? restaurantId,
    required String reason,
  }) async => throw const PlatformAdminException(
    'platform support: unavailable in demo mode (there is no live tenant).',
    kind: PlatformAdminErrorKind.notConfigured,
  );
}

/// Calls `public.platform_admin_start_support_session`, which requires an active
/// platform-admin grant, an `aal2` session, and a non-empty reason — the same
/// three conditions as every other platform read (D-026).
class RealPlatformSupportLauncher implements PlatformSupportLauncher {
  const RealPlatformSupportLauncher(this._transport);

  final SyncRpcTransport? _transport;

  @override
  Future<SupportHandoff> start({
    required String organizationId,
    String? restaurantId,
    required String reason,
  }) async {
    final transport = _transport;
    if (transport == null) {
      throw const PlatformAdminException(
        'platform support: real mode is not configured; staying fail-closed.',
        kind: PlatformAdminErrorKind.notConfigured,
      );
    }
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      // The server refuses an empty reason too; refusing here as well means a
      // blank one never becomes a round trip that looks like a server fault.
      throw const PlatformAdminException(
        'platform support: a reason is required.',
        kind: PlatformAdminErrorKind.accessDenied,
      );
    }
    final Object? raw;
    try {
      raw = await transport.invoke('platform_admin_start_support_session', {
        'p_organization_id': organizationId,
        'p_restaurant_id': restaurantId,
        'p_reason': '$kReasonSupportStart$trimmed',
      });
    } on SyncTransportException catch (e) {
      throw _supportException(e);
    }
    if (raw is! Map || raw['ok'] != true) {
      throw const PlatformAdminException(
        'platform support: unexpected response shape from the server.',
      );
    }
    final token = raw['handoff_token'];
    if (token is! String || token.isEmpty) {
      throw const PlatformAdminException(
        'platform support: the server returned no handoff.',
      );
    }
    final org = raw['organization'];
    final rest = raw['restaurant'];
    return SupportHandoff(
      supportSessionId: '${raw['support_session_id']}',
      handoffToken: token,
      organizationName: org is Map ? '${org['name']}' : '',
      restaurantName: rest is Map ? '${rest['name']}' : null,
    );
  }
}

PlatformAdminException _supportException(SyncTransportException e) =>
    switch (e.kind) {
      SyncTransportErrorKind.auth => const PlatformAdminException(
        'platform support denied: an active platform-admin grant and '
        'multi-factor (aal2) sign-in are required (D-026).',
        kind: PlatformAdminErrorKind.accessDenied,
      ),
      SyncTransportErrorKind.transient => const PlatformAdminException(
        'platform support: a temporary network or server issue occurred - '
        'please retry.',
      ),
      SyncTransportErrorKind.server => const PlatformAdminException(
        'platform support: the server could not open a session.',
      ),
      SyncTransportErrorKind.unknown => const PlatformAdminException(
        'platform support: an unexpected error occurred.',
      ),
    };
