import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restoflow_pos/src/data/print_notice_review_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/spool/online_order_print_hooks.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/print_notice_review.dart';
import 'support/print_notice_preferences.dart';

const scope = PosSyncScope(
  organizationId: 'org',
  restaurantId: 'restaurant',
  branchId: 'branch',
  deviceId: 'device',
);

WebOrderPrintHistoryIssue issue({
  String job = 'one',
  int attempt = 1,
  String status = 'blocked_configuration',
  String? error = 'send_unavailable',
  PosSyncScope owner = scope,
}) => WebOrderPrintHistoryIssue(
  scope: owner,
  localJobId: 'web-initial:$job',
  dispatchId: 'dispatch-$job',
  createdAt: DateTime.utc(2026, 10, 1),
  localStatus: status,
  attemptCount: attempt,
  lastAttemptAt: DateTime.utc(2026, 10, 1, 0, attempt),
  errorCode: error,
  terminalCode: null,
  supersededByDispatchId: null,
  outcome: WebOrderPrintOutcome.failed,
);

class _Store extends PrintNoticeReviewStore {
  final marked = <String>{};
  int writes = 0;
  bool failRead = false, failWrite = false;
  Completer<void>? writeGate, readGate;
  Completer<void>? writeStarted;
  @override
  Future<bool> isReviewed(PosSyncScope scope, String fingerprint) async {
    if (readGate != null) await readGate!.future;
    if (failRead) throw StateError('synthetic_read_failure');
    return marked.contains(fingerprint);
  }

  @override
  Future<bool> review(
    PosSyncScope scope,
    String fingerprint, {
    required bool Function() isCurrent,
  }) async {
    writeStarted?.complete();
    if (writeGate != null) await writeGate!.future;
    if (!isCurrent() || failWrite) return false;
    writes++;
    marked.add(fingerprint);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrintNoticeTestPreferences platform;
  setUp(() {
    SharedPreferences.setMockInitialValues({'unrelated': 'kept'});
    platform = installPrintNoticePreferences();
  });

  test(
    'opaque presentation marker survives restart and is full-scope isolated',
    () async {
      final original = issue();
      final store = PrintNoticeReviewStore();
      expect(
        await store.review(scope, original.fingerprint, isCurrent: () => true),
        isTrue,
      );
      final restarted = PrintNoticeReviewStore();
      expect(await restarted.isReviewed(scope, original.fingerprint), isTrue);
      for (final other in [
        const PosSyncScope(
          organizationId: 'other',
          restaurantId: 'restaurant',
          branchId: 'branch',
          deviceId: 'device',
        ),
        const PosSyncScope(
          organizationId: 'org',
          restaurantId: 'other',
          branchId: 'branch',
          deviceId: 'device',
        ),
        const PosSyncScope(
          organizationId: 'org',
          restaurantId: 'restaurant',
          branchId: 'other',
          deviceId: 'device',
        ),
        const PosSyncScope(
          organizationId: 'org',
          restaurantId: 'restaurant',
          branchId: 'branch',
          deviceId: 'other',
        ),
      ]) {
        expect(
          await restarted.isReviewed(other, original.fingerprint),
          isFalse,
        );
      }
      expect(platform.values.keys, hasLength(1));
      expect(
        platform.values.keys.single,
        matches(
          r'^restoflow\.pos\.print_notice_review\.v1\.[0-9a-f]{64}\.[0-9a-f]{64}$',
        ),
      );
      expect(platform.values.values.single, true);
      expect(
        await restarted.isReviewed(scope, issue(job: 'two').fingerprint),
        isFalse,
      );
      expect(
        await restarted.isReviewed(scope, issue(attempt: 2).fingerprint),
        isFalse,
      );
      expect(
        await restarted.isReviewed(
          scope,
          issue(error: 'another_failure').fingerprint,
        ),
        isFalse,
      );
      expect(
        await restarted.isReviewed(
          scope,
          issue(status: 'possibly_printed').fingerprint,
        ),
        isFalse,
      );
      platform.values[platform.values.keys.single] = 'corrupt';
      await expectLater(
        restarted.isReviewed(scope, original.fingerprint),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test('stale caller cannot persist a review', () async {
    final store = PrintNoticeReviewStore();
    expect(
      await store.review(scope, issue().fingerprint, isCurrent: () => false),
      isFalse,
    );
    expect(platform.values, isEmpty);
  });

  for (final throws in [false, true]) {
    test(
      'async preferences platform ${throws ? 'throw' : 'no write'} cannot hide notice on reopen',
      () async {
        platform.throwWrites = throws;
        platform.dropWrites = !throws;
        final store = PrintNoticeReviewStore();
        final container = ProviderContainer(
          overrides: [
            onlineOrderInboxIdentityProvider.overrideWithValue('session|pin'),
            posSyncScopeProvider.overrideWithValue(scope),
            onlineInboxPrintRecoveryProvider.overrideWith(
              (_) async => WebOrderPrintHistory(issues: [issue()]),
            ),
            printNoticeReviewStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(container.dispose);
        await container.read(printNoticeReviewProvider.future);
        expect(
          await container
              .read(printNoticeReviewProvider.notifier)
              .review(issue()),
          false,
        );
        expect(platform.writeAttempts, 1);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), {'unrelated'});
        container.invalidate(printNoticeReviewProvider);
        final refreshed = await container.read(
          printNoticeReviewProvider.future,
        );
        expect(refreshed.isReviewed(issue()), false);
        expect(refreshed.history!.issues, hasLength(1));
        expect(
          await PrintNoticeReviewStore().isReviewed(scope, issue().fingerprint),
          false,
        );
        expect(prefs.get('unrelated'), 'kept');
        expect(platform.values, isEmpty);
      },
    );
  }

  group('authenticated presentation controller', () {
    late _Store store;
    late ProviderContainer container;
    final authority = StateProvider<String?>((_) => 'device-session|pin-a');
    final currentScope = StateProvider<PosSyncScope?>((_) => scope);
    final snapshot = StateProvider<WebOrderPrintHistory?>(
      (_) => WebOrderPrintHistory(issues: [issue()]),
    );
    setUp(() {
      store = _Store();
      container = ProviderContainer(
        overrides: [
          onlineOrderInboxIdentityProvider.overrideWith(
            (ref) => ref.watch(authority),
          ),
          posSyncScopeProvider.overrideWith((ref) => ref.watch(currentScope)),
          onlineInboxPrintRecoveryProvider.overrideWith(
            (ref) async => ref.watch(snapshot),
          ),
          printNoticeReviewStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
    });

    test(
      'review keeps unresolved row; refresh/reopen retains exact marker',
      () async {
        final initial = await container.read(printNoticeReviewProvider.future);
        expect(initial.isReviewed(issue()), false);
        expect(
          await container
              .read(printNoticeReviewProvider.notifier)
              .review(issue()),
          true,
        );
        expect(
          container
              .read(printNoticeReviewProvider)
              .value!
              .history!
              .issues
              .single
              .fingerprint,
          issue().fingerprint,
        );
        container.invalidate(printNoticeReviewProvider);
        final reopened = await container.read(printNoticeReviewProvider.future);
        expect(reopened.isReviewed(issue()), true);
        expect(
          reopened.history!.issues.single.localStatus,
          'blocked_configuration',
        );
        expect(store.writes, 1);
      },
    );

    test('new issue arriving during review stays unreviewed', () async {
      await container.read(printNoticeReviewProvider.future);
      store.writeGate = Completer<void>();
      store.writeStarted = Completer<void>();
      final pending = container
          .read(printNoticeReviewProvider.notifier)
          .review(issue());
      await store.writeStarted!.future;
      container.read(snapshot.notifier).state = WebOrderPrintHistory(
        issues: [
          issue(),
          issue(job: 'two'),
        ],
      );
      final updated = await container.read(printNoticeReviewProvider.future);
      store.writeGate!.complete();
      expect(await pending, false);
      expect(updated.isReviewed(issue(job: 'two')), false);
      expect(updated.history!.issues, hasLength(2));
      expect(store.writes, 0);
    });

    test('review of changed/unknown snapshot is refused', () async {
      await container.read(printNoticeReviewProvider.future);
      expect(
        await container
            .read(printNoticeReviewProvider.notifier)
            .review(issue(attempt: 2)),
        false,
      );
      expect(
        await container
            .read(printNoticeReviewProvider.notifier)
            .review(issue(job: 'other')),
        false,
      );
      expect(store.writes, 0);
    });

    test('failed write/read never hides an unresolved notice', () async {
      await container.read(printNoticeReviewProvider.future);
      store.failWrite = true;
      expect(
        await container
            .read(printNoticeReviewProvider.notifier)
            .review(issue()),
        false,
      );
      var view = container.read(printNoticeReviewProvider).value!;
      expect(view.storageFailed, true);
      expect(view.isReviewed(issue()), false);
      store.failRead = true;
      container.invalidate(printNoticeReviewProvider);
      view = await container.read(printNoticeReviewProvider.future);
      expect(view.storageFailed, true);
      expect(view.history!.issues, hasLength(1));
      expect(view.reviewed, isEmpty);
    });

    for (final boundary in ['pin', 'device-session', 'scope', 'logout']) {
      test('$boundary change rejects pending review completion', () async {
        await container.read(printNoticeReviewProvider.future);
        store.writeGate = Completer<void>();
        store.writeStarted = Completer<void>();
        final pending = container
            .read(printNoticeReviewProvider.notifier)
            .review(issue());
        await store.writeStarted!.future;
        if (boundary == 'scope') {
          container.read(currentScope.notifier).state = const PosSyncScope(
            organizationId: 'foreign',
            restaurantId: 'restaurant',
            branchId: 'branch',
            deviceId: 'device',
          );
        } else {
          container.read(authority.notifier).state = boundary == 'logout'
              ? null
              : '$boundary-new';
        }
        await container.read(printNoticeReviewProvider.future);
        store.writeGate!.complete();
        expect(await pending, false);
        expect(store.writes, 0);
        expect(
          container.read(printNoticeReviewProvider).value!.reviewed,
          isEmpty,
        );
      });
    }

    test(
      'authority change during load cannot expose previous reviewed data',
      () async {
        store.marked.add(issue().fingerprint);
        store.readGate = Completer<void>();
        container.read(printNoticeReviewProvider.future);
        await Future<void>.delayed(Duration.zero);
        container.read(authority.notifier).state = null;
        final current = await container.read(printNoticeReviewProvider.future);
        store.readGate!.complete();
        await Future<void>.delayed(Duration.zero);
        expect(current.history, null);
        expect(container.read(printNoticeReviewProvider).value!.history, null);
      },
    );
  });
}
