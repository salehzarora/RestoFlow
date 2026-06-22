import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The lifecycle status of the KDS pull loop (RF-063).
enum KdsSyncStatus {
  /// Before the first pull has started.
  initial,

  /// A pull is in flight and there is no prior data to show.
  loading,

  /// The last pull succeeded; [KdsSyncState.entities] is fresh.
  data,

  /// A transient failure occurred; the last successful data is retained and a
  /// backoff retry is scheduled (OFFLINE_SYNC §6/§15).
  offlineStale,

  /// `sync_pull` returned `42501`: the session is revoked/expired. Polling has
  /// stopped and re-authentication is required (approved decision A5).
  reauthRequired,

  /// A non-transient, non-auth error (e.g. a malformed response). No automatic
  /// retry; the prior data, if any, is retained.
  error,
}

/// An immutable snapshot of the coordinator's state (RF-063).
///
/// [entities] holds the accumulated, tombstone-applied rows per entity name
/// (e.g. `orders`, `order_items`, `order_item_modifiers`) as raw JSON maps. The
/// sync layer deliberately does NOT model business entities or money — mapping
/// to KDS view models is the `feature_kitchen` concern (approved decision A4).
class KdsSyncState {
  const KdsSyncState({
    required this.status,
    this.entities = const {},
    this.serverTs,
    this.failureMessage,
  });

  /// The initial, pre-pull state.
  static const KdsSyncState initial = KdsSyncState(
    status: KdsSyncStatus.initial,
  );

  final KdsSyncStatus status;

  /// entity name -> current rows (raw JSON), tombstones already removed.
  final Map<String, List<Map<String, dynamic>>> entities;

  /// The `server_ts` of the most recent successful pull (raw ISO), if any.
  final String? serverTs;

  /// A developer-facing diagnostic for a failure status (never UI chrome).
  final String? failureMessage;

  /// Rows currently held for [entity] (empty when none).
  List<Map<String, dynamic>> rowsFor(String entity) =>
      entities[entity] ?? const [];

  /// Whether any data has been successfully loaded at least once.
  bool get hasData => entities.isNotEmpty;

  KdsSyncState copyWith({
    KdsSyncStatus? status,
    Map<String, List<Map<String, dynamic>>>? entities,
    String? serverTs,
    String? failureMessage,
    bool clearFailure = false,
  }) {
    return KdsSyncState(
      status: status ?? this.status,
      entities: entities ?? this.entities,
      serverTs: serverTs ?? this.serverTs,
      failureMessage: clearFailure
          ? null
          : (failureMessage ?? this.failureMessage),
    );
  }
}

/// The read/observe surface the UI/repository depends on (RF-063).
///
/// Abstracting the coordinator behind this lets `feature_kitchen` and the app
/// inject a fake source in tests with no live Supabase (approved decision A1).
abstract class KdsSyncSource {
  /// The current state.
  KdsSyncState get state;

  /// A broadcast stream of state changes.
  Stream<KdsSyncState> get states;

  /// Begin syncing: an immediate pull, then poll on the configured cadence.
  Future<void> start();

  /// Trigger an out-of-band pull now (manual refresh).
  Future<void> refresh();

  /// Stop polling and release resources.
  Future<void> dispose();
}

/// Re-exported for convenience so consumers importing the sync package get the
/// cursor type without also importing data_remote directly.
typedef PullCursor = SyncCursor;
