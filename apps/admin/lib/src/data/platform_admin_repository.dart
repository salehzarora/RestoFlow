/// The platform-admin data SEAM (RF-120).
///
/// The single place the platform overview is sourced. The demo implementation
/// COMPUTES the overview from a structured in-memory dataset (no Supabase, no
/// RPC, no backend). A future ticket can drop in a Supabase-backed
/// implementation that calls the real RF-091 platform-admin RPCs
/// (`platform_admin_organization_overview` / `recent_audit`) behind public
/// wrappers — same return type, so the UI does not change. [loadOverview] is
/// async so the UI has honest loading / error / empty states.
library;

import 'platform_admin_source.dart';
import 'platform_overview.dart';
import 'platform_overview_calculator.dart';

/// Loads the [PlatformOverview]. Implementations may fail (network, auth, MFA) —
/// the UI renders that as an error state.
abstract class PlatformAdminRepository {
  Future<PlatformOverview> loadOverview();
}

/// Computes the platform overview from a structured demo dataset. There is no
/// backend: this is honest demo data, calculated locally.
class DemoPlatformAdminRepository implements PlatformAdminRepository {
  const DemoPlatformAdminRepository({this.dataset, this.failureMessage});

  /// Overrides the source dataset (e.g. an empty platform in tests). Null uses
  /// the standard demo dataset.
  final PlatformDataset? dataset;

  /// When non-null, [loadOverview] throws a [PlatformAdminException] with this
  /// message (used to drive/test the error state).
  final String? failureMessage;

  @override
  Future<PlatformOverview> loadOverview() async {
    final message = failureMessage;
    if (message != null) {
      throw PlatformAdminException(message);
    }
    return computePlatformOverview(dataset ?? demoPlatformDataset());
  }
}

/// Why the platform overview failed to load (RF-134). Drives a clear, honest
/// safe state in the UI: a generic retryable error, a "not configured" notice,
/// or an "access denied" notice. The exception [PlatformAdminException.message]
/// stays developer-facing and is NEVER shown raw to the user.
enum PlatformAdminErrorKind {
  /// Real mode was selected but the Supabase config is missing/invalid, so the
  /// real repo is fail-closed with no transport: platform admin is NOT
  /// CONFIGURED. Retrying cannot help — the UI shows a config-needed notice.
  notConfigured,

  /// The backend refused the read (SQLSTATE 42501): an active platform-admin
  /// grant and aal2 (MFA) step-up are required (D-026). The grant/step-up UX is
  /// not part of this build, so the UI shows an honest "access denied" notice
  /// rather than a retry.
  accessDenied,

  /// Any other failure (network, server, unexpected shape, or a demo-configured
  /// failure). Rendered as the generic, retryable error state.
  unexpected,
}

/// A failure loading the platform overview, categorized by [kind] so the UI can
/// render an honest, specific safe state (RF-134).
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
