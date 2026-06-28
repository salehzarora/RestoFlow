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

/// A failure loading the platform overview.
class PlatformAdminException implements Exception {
  const PlatformAdminException(this.message);

  final String message;

  @override
  String toString() => 'PlatformAdminException: $message';
}
