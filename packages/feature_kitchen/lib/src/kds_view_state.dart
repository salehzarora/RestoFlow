import 'package:restoflow_sync/restoflow_sync.dart';

import 'kds_ticket_view.dart';

/// The KDS-facing view state (RF-063): the sync [KdsSyncStatus] plus the mapped
/// tickets. This is what the app's KDS screen renders/observes.
class KdsViewState {
  const KdsViewState({required this.status, this.tickets = const []});

  /// The current sync lifecycle status (loading / data / offlineStale /
  /// reauthRequired / error).
  final KdsSyncStatus status;

  /// The KDS tickets mapped from the latest pulled rows (money-free).
  final List<KdsTicketView> tickets;

  /// Whether the session needs re-authentication (polling has stopped).
  bool get isReauthRequired => status == KdsSyncStatus.reauthRequired;

  /// Whether the displayed data is stale (a transient failure is being retried).
  bool get isStale => status == KdsSyncStatus.offlineStale;

  /// Whether a non-transient, non-auth error is current.
  bool get isError => status == KdsSyncStatus.error;
}
