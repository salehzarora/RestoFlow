/// Activity-log state seam (AUDIT-LOG-DASHBOARD-001).
///
/// Picks the demo vs real repository from [runtimeConfigProvider] (the one
/// audited mode switch), scoped to the active membership + authenticated
/// transport (both overridden by the shell's Activity surface). A
/// [StateNotifier] holds the paginated list so "load more" accumulates events.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/audit_filter_options_repository.dart';
import '../data/audit_log_models.dart';
import '../data/audit_log_repository.dart';
import '../data/real_audit_log_repository.dart';
import 'dashboard_providers.dart';

/// The activity-log data seam. Demo mode (the DEFAULT) uses the in-memory
/// [DemoAuditLogRepository]; real mode returns [RealAuditLogRepository] reading
/// `owner_audit_events` over the authenticated transport, scoped to the active
/// membership (fails closed with no transport/scope).
final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return DemoAuditLogRepository();
  }
  return RealAuditLogRepository(
    config.supabase,
    scope: ref.watch(dashboardMembershipProvider),
    transport: ref.watch(dashboardAuthTransportProvider),
  );
}, dependencies: [dashboardMembershipProvider, dashboardAuthTransportProvider]);

/// The active list controls (range + category + sensitive-only + branch +
/// actor). The screen's chips / dropdowns / toggle write this; changing it
/// rebuilds the controller, which reloads the first page (cursor reset).
final auditLogQueryProvider = StateProvider<AuditQuery>(
  (ref) => const AuditQuery(),
);

/// The scope-safe BRANCH + ACTOR filter option source (demo vs real), scoped to
/// the active membership + authenticated transport.
final auditFilterOptionsRepositoryProvider =
    Provider<AuditFilterOptionsRepository>(
      (ref) {
        final config = ref.watch(runtimeConfigProvider);
        if (config.isDemoMode) {
          return const DemoAuditFilterOptionsRepository();
        }
        return RealAuditFilterOptionsRepository(
          scope: ref.watch(dashboardMembershipProvider),
          transport: ref.watch(dashboardAuthTransportProvider),
        );
      },
      dependencies: [
        dashboardMembershipProvider,
        dashboardAuthTransportProvider,
      ],
    );

/// The branch options the caller covers ("all permitted branches" is added by
/// the UI). Fails soft to an empty list.
final auditBranchOptionsProvider = FutureProvider<List<AuditBranchOption>>(
  (ref) => ref.watch(auditFilterOptionsRepositoryProvider).loadBranches(),
  dependencies: [auditFilterOptionsRepositoryProvider],
);

/// The in-scope staff options ("all staff" is added by the UI). Names only;
/// fails soft to an empty list.
final auditActorOptionsProvider = FutureProvider<List<AuditActorOption>>(
  (ref) => ref.watch(auditFilterOptionsRepositoryProvider).loadActors(),
  dependencies: [auditFilterOptionsRepositoryProvider],
);

/// The paginated timeline state: initial load status, accumulated events, the
/// keyset continuation, and the currency for money formatting.
class AuditLogState {
  const AuditLogState({
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.events = const [],
    this.hasMore = false,
    this.cursor,
    this.currencyCode = '',
  });

  final bool loading;
  final bool loadingMore;
  final Object? error;
  final List<AuditEvent> events;
  final bool hasMore;
  final String? cursor;
  final String currencyCode;

  bool get isEmpty => !loading && error == null && events.isEmpty;

  AuditLogState copyWith({
    bool? loading,
    bool? loadingMore,
    Object? error,
    List<AuditEvent>? events,
    bool? hasMore,
    String? cursor,
    String? currencyCode,
  }) => AuditLogState(
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error,
    events: events ?? this.events,
    hasMore: hasMore ?? this.hasMore,
    cursor: cursor,
    currencyCode: currencyCode ?? this.currencyCode,
  );
}

/// Drives the paginated timeline for a fixed [AuditQuery]. Recreated whenever
/// the query changes (so a filter change reloads the first page).
class AuditLogController extends StateNotifier<AuditLogState> {
  AuditLogController(this._repo, this._query)
    : super(const AuditLogState(loading: true)) {
    _loadInitial();
  }

  final AuditLogRepository _repo;
  final AuditQuery _query;

  Future<void> _loadInitial() async {
    state = const AuditLogState(loading: true);
    try {
      final page = await _repo.loadEvents(_query);
      if (!mounted) return;
      state = AuditLogState(
        loading: false,
        events: page.events,
        hasMore: page.hasMore,
        cursor: page.nextCursor,
        currencyCode: page.currencyCode,
      );
    } catch (e) {
      if (!mounted) return;
      state = AuditLogState(loading: false, error: e);
    }
  }

  /// Re-runs the first-page load (the refresh button).
  Future<void> refresh() => _loadInitial();

  /// Appends the next keyset page. A load-more failure keeps the existing events
  /// (it just stops paging) rather than wiping the list.
  Future<void> loadMore() async {
    final cursor = state.cursor;
    if (state.loading ||
        state.loadingMore ||
        !state.hasMore ||
        cursor == null) {
      return;
    }
    state = state.copyWith(loadingMore: true, cursor: cursor);
    try {
      final page = await _repo.loadEvents(_query, cursor: cursor);
      if (!mounted) return;
      state = state.copyWith(
        loadingMore: false,
        events: [...state.events, ...page.events],
        hasMore: page.hasMore,
        cursor: page.nextCursor,
        currencyCode: page.currencyCode,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loadingMore: false, hasMore: false, cursor: null);
    }
  }
}

/// The timeline controller for the current query.
final auditLogControllerProvider =
    StateNotifierProvider<AuditLogController, AuditLogState>((ref) {
      final repo = ref.watch(auditLogRepositoryProvider);
      final query = ref.watch(auditLogQueryProvider);
      return AuditLogController(repo, query);
    }, dependencies: [auditLogRepositoryProvider, auditLogQueryProvider]);
