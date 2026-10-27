import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/print_notice_review_store.dart';
import '../data/sync_cursor_store.dart';
import '../spool/online_order_print_hooks.dart';
import 'online_order_inbox_controller.dart'
    show onlineOrderInboxIdentityProvider;
import 'pos_sync_scope_provider.dart';

final printNoticeReviewStoreProvider = Provider<PrintNoticeReviewStore>(
  (_) => PrintNoticeReviewStore(),
);

class PrintNoticeHistoryView {
  PrintNoticeHistoryView({
    required this.history,
    this.reviewed = const {},
    this.saving = false,
    this.storageFailed = false,
  });
  final WebOrderPrintHistory? history;
  final Set<String> reviewed;
  final bool saving, storageFailed;

  bool isReviewed(WebOrderPrintHistoryIssue issue) =>
      reviewed.contains(issue.fingerprint);
}

final printNoticeReviewProvider =
    AsyncNotifierProvider<PrintNoticeReview, PrintNoticeHistoryView>(
      PrintNoticeReview.new,
    );

class PrintNoticeReview extends AsyncNotifier<PrintNoticeHistoryView> {
  var _generation = 0;
  String? _identity;
  PosSyncScope? _scope;

  bool _current(int generation) =>
      generation == _generation &&
      _identity != null &&
      _scope != null &&
      ref.read(onlineOrderInboxIdentityProvider) == _identity &&
      ref.read(posSyncScopeProvider) == _scope;

  @override
  Future<PrintNoticeHistoryView> build() async {
    final generation = ++_generation;
    ref.onDispose(() {
      if (_generation == generation) _generation++;
    });
    _identity = ref.watch(onlineOrderInboxIdentityProvider);
    _scope = ref.watch(posSyncScopeProvider);
    final store = ref.watch(printNoticeReviewStoreProvider);
    if (_identity == null || _scope == null) {
      return PrintNoticeHistoryView(history: null);
    }
    final history = await ref.watch(onlineInboxPrintRecoveryProvider.future);
    if (!_current(generation)) return PrintNoticeHistoryView(history: null);
    final scoped = history == null
        ? null
        : WebOrderPrintHistory(
            issues: history.issues.where((i) => i.scope == _scope),
            unidentifiedOutcome: history.unidentifiedOutcome,
          );
    final reviewed = <String>{};
    try {
      for (final issue in scoped?.issues ?? <WebOrderPrintHistoryIssue>[]) {
        if (await store.isReviewed(_scope!, issue.fingerprint)) {
          reviewed.add(issue.fingerprint);
        }
        if (!_current(generation)) return PrintNoticeHistoryView(history: null);
      }
      return PrintNoticeHistoryView(
        history: scoped,
        reviewed: Set.unmodifiable(reviewed),
      );
    } catch (_) {
      // Failed/corrupt persistence never suppresses unresolved evidence.
      return PrintNoticeHistoryView(history: scoped, storageFailed: true);
    }
  }

  Future<bool> review(WebOrderPrintHistoryIssue displayedIssue) async {
    final generation = _generation;
    final view = state.valueOrNull;
    if (!_current(generation) ||
        state.isLoading ||
        view == null ||
        view.saving ||
        !displayedIssue.reviewable ||
        displayedIssue.scope != _scope ||
        view.isReviewed(displayedIssue) ||
        !(view.history?.issues.any(
              (i) => i.fingerprint == displayedIssue.fingerprint,
            ) ??
            false)) {
      return false;
    }
    state = AsyncData(
      PrintNoticeHistoryView(
        history: view.history,
        reviewed: view.reviewed,
        saving: true,
      ),
    );
    var saved = false;
    try {
      saved = await ref
          .read(printNoticeReviewStoreProvider)
          .review(
            _scope!,
            displayedIssue.fingerprint,
            isCurrent: () => _current(generation),
          );
    } catch (_) {
      /* Keep the exact notice visible on storage failure. */
    }
    if (!_current(generation)) return false;
    state = AsyncData(
      PrintNoticeHistoryView(
        history: view.history,
        reviewed: saved
            ? Set.unmodifiable({...view.reviewed, displayedIssue.fingerprint})
            : view.reviewed,
        storageFailed: !saved,
      ),
    );
    return saved;
  }
}
