import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/console_models.dart';
import '../data/platform_admin_repository.dart';
import '../data/real_platform_admin_repository.dart';
import '../admin_platform_gate.dart';
import '../data/support_access.dart';
import '../util/external_link.dart';

/// RF-119-b — the authenticated RPC transport the REAL console reads use. It
/// DEFAULTS TO NULL (fail-closed): real platform reads require the Admin app to
/// OVERRIDE this (in `main.dart`) with the SAME session-carrying
/// `SupabaseSyncRpcTransport(Supabase.instance.client)` it uses for
/// `get_my_context` — so the operator's signed-in aal2 session reaches
/// `app.platform_admin_guard` (grant + aal2 + reason).
///
/// Without that override the real repo has no transport and fails CLOSED (an
/// honest "not configured") — it NEVER builds a fresh sessionless client for
/// platform reads, and NEVER fakes data. No service-role key (D-011); the
/// server guard stays the authorization boundary and the client aal2 is UX only.
final platformAdminTransportProvider = Provider<SyncRpcTransport?>(
  (ref) => null,
);

/// The platform-console data seam (RF-120 / RF-128 / RF-119-b / ADMIN-125C.2).
///
/// The demo vs real choice is taken from [runtimeConfigProvider] (the one
/// audited RESTOFLOW_DEMO_MODE read): demo mode (the DEFAULT) keeps
/// [DemoPlatformAdminRepository]; real mode selects
/// [RealPlatformAdminRepository], reading through the ADMIN-125C.1
/// `public.platform_admin_*` wrappers (READ-ONLY, D-026) over the
/// [platformAdminTransportProvider] transport — the SAME authenticated session
/// client `get_my_context` uses (RF-119-b). Entry stays gated by
/// `is_platform_admin` + aal2 server-side.
final platformAdminRepositoryProvider = Provider<PlatformAdminRepository>((
  ref,
) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return const DemoPlatformAdminRepository();
  }
  // Real mode: read through the injected session-carrying transport (null =>
  // fail-closed, an honest "not configured" state; never a sessionless read,
  // and never a silent fall back to the demo repository).
  return RealPlatformAdminRepository(ref.watch(platformAdminTransportProvider));
});

// ---------------------------------------------------------------------------
// Page-scoped reads
// ---------------------------------------------------------------------------

/// The Overview page's counts. Refresh by invalidating it.
final consoleOverviewProvider = FutureProvider<ConsoleOverview>(
  (ref) => ref.watch(platformAdminRepositoryProvider).loadConsoleOverview(),
);

/// The CURRENT subscriber query (search / filters / sort / offset). Changing it
/// re-runs only [subscriberPageProvider] — the Overview, Restaurants and Audit
/// pages are untouched, because each page owns its own request.
final subscriberQueryProvider = StateProvider<SubscriberQuery>(
  (ref) => const SubscriberQuery(),
);

/// One page of subscribers for the current [subscriberQueryProvider]. Families
/// key on the query, so paging back to a page already fetched is instant and a
/// filter change is a genuinely new request.
final subscriberPageProvider =
    FutureProvider.family<SubscriberPage, SubscriberQuery>(
      (ref, query) =>
          ref.watch(platformAdminRepositoryProvider).loadSubscribers(query),
    );

/// One subscriber detail, KEYED BY organization id — so opening a second tenant
/// is a separate request and a stale detail can never be shown under a new name.
final subscriberDetailProvider =
    FutureProvider.family<SubscriberDetail, String>(
      (ref, organizationId) => ref
          .watch(platformAdminRepositoryProvider)
          .loadSubscriberDetail(organizationId),
    );

/// The CURRENT restaurant query.
final restaurantQueryProvider = StateProvider<RestaurantQuery>(
  (ref) => const RestaurantQuery(),
);

/// One page of restaurants for the current [restaurantQueryProvider].
final restaurantPageProvider =
    FutureProvider.family<RestaurantPage, RestaurantQuery>(
      (ref, query) =>
          ref.watch(platformAdminRepositoryProvider).loadRestaurants(query),
    );

/// The CURRENT audit filters (action / target / range). The keyset CURSOR is
/// deliberately NOT here: cursors accumulate as the operator loads more, and are
/// held by [auditFeedProvider] so a filter change resets them in one place.
final auditFilterProvider = StateProvider<AuditQuery>(
  (ref) => const AuditQuery(),
);

/// One keyset page of the audit log.
final auditPageProvider = FutureProvider.family<AuditPage, AuditQuery>(
  (ref, query) =>
      ref.watch(platformAdminRepositoryProvider).loadAuditPage(query),
);

/// The accumulated audit feed: page 1, plus every "load more" page appended.
///
/// A keyset log cannot be paged with previous/next buttons the way an offset
/// list can — there is no way to jump to page 5 — so the console grows one
/// visible list instead, exactly as the underlying contract intends.
class AuditFeedState {
  const AuditFeedState({
    this.events = const [],
    this.hasMore = false,
    this.nextCursor,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<AuditEvent> events;
  final bool hasMore;
  final AuditCursor? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;

  /// The failure that ended the LAST request, if any. A failed "load more"
  /// keeps the rows already shown — losing them would be a worse answer than
  /// the partial list the operator is reading.
  final Object? error;

  bool get isEmpty => events.isEmpty;
}

/// Drives [AuditFeedState]: loads the first page, appends "load more" pages, and
/// resets both list and cursor whenever the filters change.
class AuditFeedController extends StateNotifier<AuditFeedState> {
  AuditFeedController(this._read, this._filter)
    : super(const AuditFeedState(isLoading: true)) {
    _loadFirst();
  }

  final Future<AuditPage> Function(AuditQuery) _read;
  final AuditQuery _filter;

  Future<void> _loadFirst() async {
    state = const AuditFeedState(isLoading: true);
    try {
      final page = await _read(_filter.resetToFirstPage());
      state = AuditFeedState(
        events: page.rows,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );
    } catch (e) {
      state = AuditFeedState(error: e);
    }
  }

  /// Re-reads the first page for the current filters.
  Future<void> refresh() => _loadFirst();

  /// Appends the next keyset page. A no-op while a request is in flight or when
  /// there is nothing more — double-tapping "load more" must not skip a page.
  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (!state.hasMore ||
        cursor == null ||
        state.isLoading ||
        state.isLoadingMore) {
      return;
    }
    state = AuditFeedState(
      events: state.events,
      hasMore: state.hasMore,
      nextCursor: cursor,
      isLoadingMore: true,
    );
    try {
      final page = await _read(_filter.copyWith(cursor: cursor));
      state = AuditFeedState(
        events: [...state.events, ...page.rows],
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );
    } catch (e) {
      // Keep what the operator can already see; report the failure beside it.
      state = AuditFeedState(
        events: state.events,
        hasMore: state.hasMore,
        nextCursor: cursor,
        error: e,
      );
    }
  }
}

/// The audit feed for the current [auditFilterProvider]. Rebuilt from scratch
/// when the filters change (a cursor from the old filter set would resume at a
/// position that does not exist in the new one).
final auditFeedProvider =
    StateNotifierProvider<AuditFeedController, AuditFeedState>((ref) {
      final repo = ref.watch(platformAdminRepositoryProvider);
      return AuditFeedController(
        repo.loadAuditPage,
        ref.watch(auditFilterProvider),
      );
    });

// ---------------------------------------------------------------------------
// Restaurant operations (ADMIN-126)
// ---------------------------------------------------------------------------

/// The CURRENT restaurant-operations query. Defaults to sales high-to-low,
/// because the first question an operator asks of this page is "who is trading
/// and who is not".
final restaurantOperationsQueryProvider =
    StateProvider<RestaurantOperationsQuery>(
      (ref) => const RestaurantOperationsQuery(),
    );

/// One page of restaurant operations for the current query.
final restaurantOperationsPageProvider =
    FutureProvider.family<RestaurantOperationsPage, RestaurantOperationsQuery>(
      (ref, query) => ref
          .watch(platformAdminRepositoryProvider)
          .loadRestaurantOperations(query),
    );

// ---------------------------------------------------------------------------
// Support access (ADMIN-126B)
// ---------------------------------------------------------------------------

/// Opens read-only support sessions. Demo mode gets the launcher that REFUSES —
/// there is no live tenant behind demo data, and a fabricated session would open
/// a dashboard full of invented numbers under a real-looking banner.
final platformSupportLauncherProvider = Provider<PlatformSupportLauncher>((
  ref,
) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) return const DemoPlatformSupportLauncher();
  return RealPlatformSupportLauncher(ref.watch(platformAdminTransportProvider));
});

/// Opens the Dashboard launch URL. Overridden in tests so a widget test never
/// opens a real browser tab — and so a test can READ the URL that would have
/// been opened, which is the only place the handoff token is ever observable.
final supportUrlOpenerProvider = Provider<void Function(String url)>(
  (ref) => openExternalUrl,
);

/// The Dashboard origin a support session is handed off to: the hosted
/// `RESTOFLOW_DASHBOARD_URL` when built with one, else the local fallback.
final dashboardUrlProvider = Provider<String>((ref) => resolveDashboardUrl());
