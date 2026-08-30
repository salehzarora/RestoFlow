/// ADMIN-126B — PLATFORM SUPPORT MODE, the tenant-side half.
///
/// A RestoFlow operator opens this Dashboard for a restaurant they are helping,
/// WITHOUT the owner's password and WITHOUT becoming the owner. The operator
/// stays the actor: every server read is attributed to their platform account,
/// and every write is refused by the server, not by a hidden button.
///
/// The client's job here is small and deliberately so:
///   1. spend the one-time handoff exactly once,
///   2. ask the SERVER whether a support session is live,
///   3. say so, loudly and permanently, while it is.
///
/// Nothing in this file decides what a support operator may do. That is settled
/// in `20260903090001_platform_support_sessions_126.sql`: fifteen named read
/// RPCs accept a support session, every mutating RPC still requires a
/// membership, a device token or a PIN session, and a support operator has none
/// of those. If this file were deleted the security posture would not change —
/// only the honesty of the UI would.
library;

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// A live support session, as the SERVER describes it.
///
/// Every field comes from `platform_support_current`. The client never computes
/// whether a session is valid — it asks, and it asks again on every refresh,
/// because the operator's tab may have been open across the expiry.
class PlatformSupportSession {
  const PlatformSupportSession({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.reason,
    required this.expiresAt,
    this.restaurantId,
    this.restaurantName,
  });

  final String id;
  final String organizationId;
  final String organizationName;

  /// The typed reason the operator gave when starting the session. Shown in the
  /// banner so the person being helped can see why someone is looking.
  final String reason;

  /// Server-set expiry. The countdown is cosmetic; the server re-checks this on
  /// every single read, so a stale tab gains nothing by not counting down.
  final DateTime expiresAt;

  final String? restaurantId;
  final String? restaurantName;

  /// What the banner calls the tenant: the restaurant when the session was
  /// scoped to one, otherwise the organization.
  String get targetLabel =>
      (restaurantName != null && restaurantName!.isNotEmpty)
      ? '$organizationName · $restaurantName'
      : organizationName;

  Duration remaining(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  static PlatformSupportSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['ok'] != true || raw['active'] != true) return null;
    final org = raw['organization'];
    final rest = raw['restaurant'];
    final expires = DateTime.tryParse('${raw['expires_at']}');
    if (org is! Map || expires == null) return null;
    return PlatformSupportSession(
      id: '${raw['support_session_id']}',
      organizationId: '${org['id']}',
      organizationName: '${org['name']}',
      reason: '${raw['reason']}',
      expiresAt: expires,
      restaurantId: rest is Map ? '${rest['id']}' : null,
      restaurantName: rest is Map ? '${rest['name']}' : null,
    );
  }
}

/// Reads the support plane. Four RPCs, all authenticated, none of them writing
/// tenant data.
class PlatformSupportRepository {
  const PlatformSupportRepository(this._transport);

  final SyncRpcTransport? _transport;

  /// Spends a one-time handoff. Returns the session it opened, or null if the
  /// handoff was already used, expired, or never valid — the server answers all
  /// three identically on purpose, and so does this.
  Future<PlatformSupportSession?> exchange(String token) async {
    final transport = _transport;
    if (transport == null) return null;
    try {
      final raw = await transport.invoke('platform_support_exchange', {
        'p_token': token,
      });
      // The exchange response and the status response carry the same shape,
      // except `active` — which exchange implies.
      if (raw is Map && raw['ok'] == true) {
        return PlatformSupportSession.fromJson({...raw, 'active': true});
      }
      return null;
    } catch (_) {
      // A failed handoff is never fatal: the Dashboard simply carries on as an
      // ordinary tenant session (which, for a platform admin, means no access).
      return null;
    }
  }

  /// Asks the server whether a support session is live RIGHT NOW.
  Future<PlatformSupportSession?> current() async {
    final transport = _transport;
    if (transport == null) return null;
    try {
      return PlatformSupportSession.fromJson(
        await transport.invoke('platform_support_current', const {}),
      );
    } catch (_) {
      return null;
    }
  }

  /// Ends the session immediately. The server stops honouring it on the next
  /// read, so this is not a client-side courtesy.
  Future<void> end() async {
    final transport = _transport;
    if (transport == null) return;
    try {
      await transport.invoke('platform_support_end', const {
        'p_support_session_id': null,
      });
    } catch (_) {
      // Best effort: the TTL closes the session regardless.
    }
  }
}

/// Extracts a one-time handoff token from the launch URL and REMOVES it.
///
/// The token travels in the URL FRAGMENT, never the query string: a fragment is
/// not sent to the server, does not appear in access logs, and is not passed on
/// in a Referer header. It is stripped from the address bar as soon as it is
/// read, so a shared screenshot or a copied URL carries nothing — and even a
/// leaked one is single-use with a ~60 second window.
String? takeSupportHandoffToken(
  String fragment,
  void Function(String cleanedFragment) replaceFragment,
) {
  if (fragment.isEmpty) return null;
  final raw = fragment.startsWith('#') ? fragment.substring(1) : fragment;
  final parts = raw.split('&').where((p) => p.isNotEmpty).toList();
  String? token;
  final kept = <String>[];
  for (final part in parts) {
    if (part.startsWith('support=')) {
      final value = part.substring('support='.length).trim();
      if (value.isNotEmpty) token = value;
    } else {
      kept.add(part);
    }
  }
  if (token == null) return null;
  replaceFragment(kept.join('&'));
  return token;
}
