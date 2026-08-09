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
import 'analytics_branch_providers.dart'
    show
        analyticsBranchOptionsProvider,
        analyticsBranchStillApplies,
        operationalBranchItems;
import 'dashboard_membership_identity.dart';
import 'dashboard_providers.dart';

/// The activity-log data seam. Demo mode (the DEFAULT) uses the in-memory
/// [DemoAuditLogRepository]; real mode returns [RealAuditLogRepository] reading
/// `owner_audit_events` over the authenticated transport, scoped to the active
/// membership (fails closed with no transport/scope).
final auditLogRepositoryProvider = Provider<AuditLogRepository>(
  (ref) {
    final config = ref.watch(runtimeConfigProvider);
    if (config.isDemoMode) {
      return DemoAuditLogRepository();
    }
    return RealAuditLogRepository(
      config.supabase,
      // R1A-01: identity, not the labelled membership.
      scope: ref.watch(dashboardMembershipIdentityProvider)?.membership,
      transport: ref.watch(dashboardAuthTransportProvider),
    );
  },
  dependencies: [
    dashboardMembershipIdentityProvider,
    dashboardAuthTransportProvider,
  ],
);

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
          // R1A-01: identity, not the labelled membership. A rename must not
          // re-enumerate branches, because the enumeration is what the whole
          // authoritative-answer memory is built on.
          scope: ref.watch(dashboardMembershipIdentityProvider)?.membership,
          transport: ref.watch(dashboardAuthTransportProvider),
        );
      },
      dependencies: [
        dashboardMembershipIdentityProvider,
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
/// CODEX R1C-02 — the query this surface actually USES, raw filters reconciled
/// against what is authorized and what the last real branch answer said.
///
/// The control read its value from the CURRENT options while the repository
/// transported `query.branch`, so the two could disagree: after a successful
/// omission the dropdown fell back to "All" while every RPC stayed filtered to
/// the removed branch. The list said one thing and the data was another, with
/// nothing on screen to say which.
///
/// One value now feeds BOTH — the visible control and the transport — so they
/// cannot drift. The RAW query is left alone (no write during build); this is a
/// projection of it, and it is what the controller and the dropdown read.
/// CODEX FINDING 6 - the actor options, STAMPED with the membership they were
/// loaded for.
///
/// An `AuditBranchOption` carries its organization, so coverage can judge it
/// with no list at all - which is why a foreign branch goes inert the instant
/// the membership changes. An `AuditActorOption` carries an employee-profile id
/// and a name and nothing else, so the ONLY evidence that an actor belongs to
/// the current context is a list that says so. Absent that evidence there is
/// nothing to justify putting the id on the wire, and the old behaviour did
/// exactly that: the timeline kept filtering by a staff member from the
/// previous organization while the control showed "All staff".
///
/// The stamp is what makes a membership change immediate. Riverpod keeps a
/// provider's previous value across a rebuild caused by a dependency change, so
/// the previous organization's actor list is still sitting there when the new
/// one starts asking - the same trap the branch answer documents.
class AuditActorAnswer {
  const AuditActorAnswer({required this.context, required this.actors});

  final DashboardMembershipIdentity? context;
  final List<AuditActorOption> actors;
}

final auditActorAnswerProvider = FutureProvider<AuditActorAnswer>(
  (ref) async {
    final context = ref.watch(dashboardMembershipIdentityProvider);
    final actors = await ref.watch(auditActorOptionsProvider.future);
    return AuditActorAnswer(context: context, actors: actors);
  },
  dependencies: [
    dashboardMembershipIdentityProvider,
    auditActorOptionsProvider,
  ],
);

/// The actors this membership may filter by, or null when the question has not
/// been answered FOR THIS membership.
final auditActorChoicesProvider = Provider<List<AuditActorOption>?>(
  (ref) {
    final context = ref.watch(dashboardMembershipIdentityProvider);
    final async = ref.watch(auditActorAnswerProvider);
    if (!async.hasValue) return null;
    final answer = async.requireValue;
    if (answer.context != context) return null;
    return answer.actors;
  },
  dependencies: [dashboardMembershipIdentityProvider, auditActorAnswerProvider],
);

final effectiveAuditQueryProvider = Provider<AuditQuery>(
  (ref) {
    final raw = ref.watch(auditLogQueryProvider);
    var out = raw;

    final branch = raw.branch;
    if (branch != null &&
        !analyticsBranchStillApplies(
          branch,
          coverage: ref.watch(dashboardCoveredScopeIdentityProvider),
          answer: ref.watch(analyticsBranchOptionsProvider),
          // FINDING 3: demo mode has no coverage to require.
          coverageRequired: !ref.watch(runtimeConfigProvider).isDemoMode,
        )) {
      out = out.copyWith(clearBranch: true);
    }

    // FINDING 6. Unlike a branch, an actor cannot be checked without a list -
    // so no list for THIS membership means no actor. That is the fail-closed
    // direction, and it is applied to the visible control and the wire alike,
    // so the two still say the same thing.
    final actor = raw.actor;
    if (actor != null) {
      final choices = ref.watch(auditActorChoicesProvider);
      final ok =
          choices != null &&
          choices.any((a) => a.employeeProfileId == actor.employeeProfileId);
      if (!ok) out = out.copyWith(clearActor: true);
    }
    return out;
  },
  dependencies: [
    auditLogQueryProvider,
    dashboardCoveredScopeIdentityProvider,
    analyticsBranchOptionsProvider,
    auditActorChoicesProvider,
  ],
);

/// CODEX FINDING 1 - the branch items the Activity control must offer.
///
/// Built from the SAME effective query the repository transports, so the value
/// is always present exactly once and the control can never assert or lie.
final activityBranchItemsProvider = Provider<List<AuditBranchOption>>(
  (ref) => operationalBranchItems(
    answer: ref.watch(analyticsBranchOptionsProvider),
    effective: ref.watch(effectiveAuditQueryProvider).branch,
  ),
  dependencies: [analyticsBranchOptionsProvider, effectiveAuditQueryProvider],
);

final auditLogControllerProvider =
    StateNotifierProvider<AuditLogController, AuditLogState>((ref) {
      final repo = ref.watch(auditLogRepositoryProvider);
      // R1C-02: the EFFECTIVE query, so a retired branch stops being sent.
      final query = ref.watch(effectiveAuditQueryProvider);
      return AuditLogController(repo, query);
    }, dependencies: [auditLogRepositoryProvider, effectiveAuditQueryProvider]);
