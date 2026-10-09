/// ORDER-EDIT-001G — "Load more" for the Overview Order edits list.
///
/// The block's FIRST page is [ownerOrderEditsForKeyProvider] (cached, refreshed
/// with the page). This controller only appends the keyset pages after it,
/// following `next_cursor` (API_CONTRACT §4.47), the same pattern as the Orders
/// history list. It is seeded from the first page and rebuilt whenever that page
/// is re-fetched, so a refresh always starts again from the newest edit and a
/// cursor minted for one window or scope can never be replayed under another
/// (the key is part of the family identity).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/owner_order_edits_query_key.dart';
import '../data/owner_order_edits.dart';
import '../data/owner_order_edits_repository.dart';
import 'dashboard_providers.dart';

/// The accumulated edit list for one Order edits request.
class OrderEditsPagesState {
  const OrderEditsPagesState({
    this.rows = const <OrderEditReportRow>[],
    this.hasMore = false,
    this.cursor,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  /// The first page followed by every appended page, newest first, each edit
  /// once.
  final List<OrderEditReportRow> rows;
  final bool hasMore;
  final String? cursor;
  final bool loadingMore;

  /// The last "Load more" failed. The rows and the cursor are kept, so the
  /// owner can simply try again.
  final bool loadMoreFailed;
}

/// Appends keyset pages to the first page of one [OwnerOrderEditsQueryKey].
class OrderEditsPagesController extends StateNotifier<OrderEditsPagesState> {
  OrderEditsPagesController(this._repo, this._key, OwnerOrderEdits? first)
    : super(
        first == null || !first.supported
            ? const OrderEditsPagesState()
            : OrderEditsPagesState(
                rows: _dedupe(const <OrderEditReportRow>[], first.edits),
                hasMore: first.hasMore,
                cursor: first.nextCursor,
              ),
      );

  final OwnerOrderEditsRepository _repo;
  final OwnerOrderEditsQueryKey _key;

  /// Loads the next page. Re-entrant presses while one is in flight are
  /// ignored, and nothing is requested once the server says there is no more.
  Future<void> loadMore() async {
    final cursor = state.cursor;
    if (state.loadingMore || !state.hasMore || cursor == null) return;
    state = OrderEditsPagesState(
      rows: state.rows,
      hasMore: state.hasMore,
      cursor: cursor,
      loadingMore: true,
    );
    try {
      final page = await _repo.loadOrderEdits(
        range: _key.range,
        analyticsScope: _key.analyticsScope,
        customWindow: _key.customWindow,
        limit: kOrderEditsPageSize,
        cursor: cursor,
      );
      if (!mounted) return;
      if (!page.supported) throw const OwnerOrderEditsException('unavailable');
      state = OrderEditsPagesState(
        rows: _dedupe(state.rows, page.edits),
        hasMore: page.hasMore,
        cursor: page.nextCursor,
      );
    } catch (_) {
      if (!mounted) return;
      state = OrderEditsPagesState(
        rows: state.rows,
        hasMore: state.hasMore,
        cursor: cursor,
        loadMoreFailed: true,
      );
    }
  }

  /// [existing] followed by the edits of [page] not already in it.
  static List<OrderEditReportRow> _dedupe(
    List<OrderEditReportRow> existing,
    List<OrderEditReportRow> page,
  ) {
    final seen = <String>{for (final r in existing) r.orderEditId};
    return List.unmodifiable(<OrderEditReportRow>[
      ...existing,
      for (final r in page)
        if (seen.add(r.orderEditId)) r,
    ]);
  }
}

/// The Order edits list for one exact request identity. Auto-disposed with the
/// card; seeded from, and reset by, the cached first page.
final orderEditsPagesControllerProvider = StateNotifierProvider.autoDispose
    .family<
      OrderEditsPagesController,
      OrderEditsPagesState,
      OwnerOrderEditsQueryKey
    >(
      (ref, key) {
        final first = ref.watch(
          ownerOrderEditsForKeyProvider(key).select((a) => a.valueOrNull),
        );
        return OrderEditsPagesController(
          ref.watch(ownerOrderEditsRepositoryProvider),
          key,
          first,
        );
      },
      dependencies: [
        ownerOrderEditsRepositoryProvider,
        ownerOrderEditsForKeyProvider,
      ],
    );
