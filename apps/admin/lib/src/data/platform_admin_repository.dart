/// The platform-console data SEAM (RF-120, extended for ADMIN-125C.2).
///
/// The single place every console page is sourced. The DEMO implementation
/// COMPUTES each page from a structured in-memory dataset (no Supabase, no RPC,
/// no backend) via `demo_console_calculator`; the REAL implementation calls the
/// ADMIN-125C.1 guarded `public.platform_admin_*` wrappers. Both return the same
/// models, so the pages are written once and cannot drift.
///
/// Every method is async and may fail (network, auth, MFA), so each page has an
/// honest loading / error / empty state. Real mode NEVER falls back to demo: a
/// real-mode failure surfaces as a [PlatformAdminException], never as demo data
/// wearing a live label.
///
/// READ-ONLY (DECISION D-026). There is no write method on this seam — not a
/// suspend, not a plan assignment, not a grant change. A future write phase must
/// add its own audited RPC and its own explicit ticket.
library;

import 'console_models.dart';
import 'demo_console_calculator.dart';
import 'platform_admin_source.dart';

/// The read seam every console page depends on.
abstract class PlatformAdminRepository {
  /// Platform-wide counts for the Overview page.
  Future<ConsoleOverview> loadConsoleOverview();

  /// One filtered, sorted, server-paged page of subscribers (organizations).
  Future<SubscriberPage> loadSubscribers(SubscriberQuery query);

  /// One subscriber's detail. Throws [PlatformAdminException] with
  /// [PlatformAdminErrorKind.accessDenied] for an unknown or tombstoned tenant —
  /// the SAME failure as a genuine denial, so the console cannot be used to
  /// probe which organization ids exist.
  Future<SubscriberDetail> loadSubscriberDetail(String organizationId);

  /// One filtered, sorted, server-paged page of restaurants, platform-wide.
  Future<RestaurantPage> loadRestaurants(RestaurantQuery query);

  /// One KEYSET page of the platform-admin audit log.
  Future<AuditPage> loadAuditPage(AuditQuery query);
}

/// Computes every console page from a structured demo dataset. There is no
/// backend: this is honest demo data, calculated locally.
class DemoPlatformAdminRepository implements PlatformAdminRepository {
  const DemoPlatformAdminRepository({this.dataset, this.failureMessage});

  /// Overrides the source dataset (e.g. an empty platform, or one with no
  /// subscriptions assigned) in tests. Null uses the standard demo dataset.
  final PlatformDataset? dataset;

  /// When non-null, every load throws a [PlatformAdminException] with this
  /// message (used to drive/test the error state).
  final String? failureMessage;

  PlatformDataset get _data => dataset ?? demoPlatformDataset();

  void _failIfConfigured() {
    final message = failureMessage;
    if (message != null) throw PlatformAdminException(message);
  }

  @override
  Future<ConsoleOverview> loadConsoleOverview() async {
    _failIfConfigured();
    return computeConsoleOverview(_data);
  }

  @override
  Future<SubscriberPage> loadSubscribers(SubscriberQuery query) async {
    _failIfConfigured();
    return computeSubscriberPage(_data, query);
  }

  @override
  Future<SubscriberDetail> loadSubscriberDetail(String organizationId) async {
    _failIfConfigured();
    final detail = computeSubscriberDetail(_data, organizationId);
    if (detail == null) {
      // Same failure shape as the server's 42501 for an unknown tenant.
      throw const PlatformAdminException(
        'platform admin: no such organization, or access denied.',
        kind: PlatformAdminErrorKind.accessDenied,
      );
    }
    return detail;
  }

  @override
  Future<RestaurantPage> loadRestaurants(RestaurantQuery query) async {
    _failIfConfigured();
    return computeRestaurantPage(_data, query);
  }

  @override
  Future<AuditPage> loadAuditPage(AuditQuery query) async {
    _failIfConfigured();
    return computeAuditPage(_data, query);
  }
}

/// Why a console read failed (RF-134). Drives a clear, honest safe state in the
/// UI: a generic retryable error, a "not configured" notice, or an "access
/// denied" notice. [PlatformAdminException.message] stays developer-facing and
/// is NEVER shown raw to the user.
enum PlatformAdminErrorKind {
  /// Real mode was selected but the Supabase config is missing/invalid, so the
  /// real repo is fail-closed with no transport: platform admin is NOT
  /// CONFIGURED. Retrying cannot help — the UI shows a config-needed notice.
  notConfigured,

  /// The backend refused the read (SQLSTATE 42501): an active platform-admin
  /// grant and aal2 (MFA) step-up are required (D-026). Also raised for an
  /// unknown/tombstoned target, deliberately indistinguishable from a denial.
  accessDenied,

  /// Any other failure (network, server, unexpected shape, or a demo-configured
  /// failure). Rendered as the generic, retryable error state.
  unexpected,
}

/// A failure loading a console page, categorized by [kind] so the UI can render
/// an honest, specific safe state (RF-134).
class PlatformAdminException implements Exception {
  const PlatformAdminException(
    this.message, {
    this.kind = PlatformAdminErrorKind.unexpected,
  });

  final String message;

  /// The failure category that drives the UI safe state. Defaults to
  /// [PlatformAdminErrorKind.unexpected] (the generic, retryable error).
  final PlatformAdminErrorKind kind;

  @override
  String toString() => 'PlatformAdminException($kind): $message';
}
