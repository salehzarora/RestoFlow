import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/online_order_inbox.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

import 'online_order_inbox_fixtures.dart';

final _session = StateProvider<SyncSession?>(
  (ref) => const SyncSession(pinSessionId: pinId, deviceId: deviceId),
);
const _context = DeviceContext(
  organizationId: 'org',
  restaurantId: 'restaurant',
  branchId: 'branch',
  deviceId: deviceId,
  deviceType: 'pos',
  deviceSessionId: 'device-session',
);

ProviderContainer harness(
  FakeInboxRepository repo, {
  List<String>? refreshed,
  Duration? interval,
  DateTime Function()? clock,
}) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posSyncSessionProvider.overrideWith((ref) => ref.watch(_session)),
      onlineOrderInboxRepositoryProvider.overrideWithValue(repo),
      onlineOrderInboxPollIntervalProvider.overrideWithValue(interval),
      posSyncClockProvider.overrideWithValue(clock ?? () => inboxNow),
      clientIdGeneratorProvider.overrideWithValue(
        FixedClientIdGenerator([decisionId]),
      ),
      onlineInboxCanonicalRefreshProvider.overrideWithValue((id) async {
        refreshed?.add(id);
      }),
    ],
  );
  addTearDown(container.dispose);
  container.read(posDeviceContextProvider.notifier).set(_context);
  return container;
}

Future<OnlineOrderInboxController> ready(ProviderContainer container) async {
  final controller = container.read(
    onlineOrderInboxControllerProvider.notifier,
  );
  await pumpEventQueue(times: 10);
  return controller;
}

void main() {
  test(
    'expiry advances after successful fetch even when later polls fail',
    () async {
      var clock = inboxNow;
      final repo = FakeInboxRepository();
      final c = harness(repo, clock: () => clock);
      final controller = await ready(c);
      expect(
        c
            .read(onlineOrderInboxControllerProvider)
            .pendingCountAt(controller.now()),
        1,
      );
      clock = inboxNow.add(const Duration(minutes: 21));
      repo.onFetch = (_, _) async {
        throw const OnlineInboxException(OnlineInboxFailure.transport);
      };
      await controller.refresh();
      final state = c.read(onlineOrderInboxControllerProvider);
      expect(state.pendingCountAt(controller.now()), 0);
      expect(state.serverTime, clock);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      expect(repo.decisions, isEmpty);
      expect(
        c.read(onlineOrderInboxControllerProvider).failure,
        OnlineInboxFailure.requestExpired,
      );
    },
  );
  test(
    'single flight prevents double tap and refreshes canonical order once',
    () async {
      final gate = Completer<OnlineInboxDecisionResult>();
      final repo = FakeInboxRepository()..onDecide = (_) => gate.future;
      final refreshed = <String>[];
      final c = harness(repo, refreshed: refreshed);
      final controller = await ready(c);
      final first = controller.decide(requestId, OnlineOrderDecision.accept);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      await controller.decide(
        requestId,
        OnlineOrderDecision.reject,
        reason: 'Sold out',
      );
      expect(repo.decisions, hasLength(1));
      gate.complete(OnlineInboxDecisionResult.fromJson(decisionJson()));
      await first;
      expect(refreshed, [canonicalId]);
      expect(c.read(onlineOrderInboxControllerProvider).requests, isEmpty);
    },
  );
  test(
    'uncertain write waits for targeted lookup then retries SAME intent',
    () async {
      final lookup = Completer<OnlineInboxPage>();
      final repo = FakeInboxRepository();
      repo.onFetch = (id, _) =>
          id == null ? Future.value(inboxPage()) : lookup.future;
      repo.onDecide = (_) async {
        if (repo.decisions.length == 1) {
          throw const OnlineInboxException(OnlineInboxFailure.transport);
        }
        return OnlineInboxDecisionResult.fromJson(
          decisionJson(status: 'rejected'),
        );
      };
      final c = harness(repo);
      final controller = await ready(c);
      final first = controller.decide(
        requestId,
        OnlineOrderDecision.reject,
        reason: ' Sold out ',
      );
      await pumpEventQueue(times: 5);
      expect(repo.fetches.last, requestId);
      expect(c.read(onlineOrderInboxControllerProvider).deciding, isTrue);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      expect(repo.decisions, hasLength(1));
      lookup.complete(inboxPage());
      await first;
      expect(repo.decisions, hasLength(2));
      expect(repo.decisions.map((d) => d.decisionId).toSet(), {decisionId});
      expect(repo.decisions.map((d) => d.decision).toSet(), {
        OnlineOrderDecision.reject,
      });
      expect(repo.decisions.map((d) => d.reason).toSet(), {'Sold out'});
    },
  );
  test(
    'failed targeted lookup keeps opposite action locked across manual refresh',
    () async {
      final repo = FakeInboxRepository();
      repo.onDecide = (_) async =>
          throw const OnlineInboxException(OnlineInboxFailure.transport);
      repo.onFetch = (id, _) async {
        if (id != null)
          throw const OnlineInboxException(OnlineInboxFailure.transport);
        return inboxPage();
      };
      final c = harness(repo);
      final controller = await ready(c);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      expect(c.read(onlineOrderInboxControllerProvider).uncertain, isTrue);
      expect(
        c.read(onlineOrderInboxControllerProvider).intent!.decisionId,
        decisionId,
      );
      await controller.refresh();
      await controller.decide(
        requestId,
        OnlineOrderDecision.reject,
        reason: 'Sold out',
      );
      expect(repo.decisions, hasLength(1));
      repo.onFetch = (_, _) async =>
          inboxPage(requests: [inboxRequest(status: 'accepted')]);
      await controller.recoverDecision();
      expect(repo.decisions, hasLength(1));
      expect(c.read(onlineOrderInboxControllerProvider).intent, isNull);
    },
  );
  test(
    'terminal accepted recovery refreshes canonical without submitting twice',
    () async {
      final refreshed = <String>[];
      final repo = FakeInboxRepository();
      repo.onDecide = (_) async {
        throw const OnlineInboxException(OnlineInboxFailure.malformed);
      };
      repo.onFetch = (id, _) async => inboxPage(
        requests: [inboxRequest(status: id == null ? 'pending' : 'accepted')],
      );
      final c = harness(repo, refreshed: refreshed);
      await (await ready(c)).decide(requestId, OnlineOrderDecision.accept);
      expect(repo.decisions, hasLength(1));
      expect(refreshed, [canonicalId]);
    },
  );
  test(
    'offline acceptance never creates an outbox or attempts a decision',
    () async {
      final repo = FakeInboxRepository();
      final c = harness(repo);
      final controller = await ready(c);
      c
          .read(posOfflineModeProvider.notifier)
          .recordOfflineCacheServed(snapshotFetchedAt: inboxNow);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      expect(repo.decisions, isEmpty);
      expect(
        c.read(onlineOrderInboxControllerProvider).failure,
        OnlineInboxFailure.transport,
      );
    },
  );
  test(
    'PIN boundary clears PII and discards a late prior-session read',
    () async {
      final gate = Completer<OnlineInboxPage>();
      final repo = FakeInboxRepository();
      final c = harness(repo);
      final controller = await ready(c);
      expect(c.read(onlineOrderInboxControllerProvider).requests, isNotEmpty);
      repo.onFetch = (_, _) => gate.future;
      final pending = controller.refresh();
      c.read(_session.notifier).state = null;
      expect(c.read(onlineOrderInboxControllerProvider).requests, isEmpty);
      gate.complete(inboxPage());
      await pending;
      expect(c.read(onlineOrderInboxControllerProvider).requests, isEmpty);
    },
  );
  test(
    'branch, device session and unpair boundaries clear sensitive state',
    () async {
      for (final context in <DeviceContext?>[
        const DeviceContext(
          organizationId: 'org',
          restaurantId: 'restaurant',
          branchId: 'other-branch',
          deviceId: deviceId,
          deviceType: 'pos',
          deviceSessionId: 'device-session',
        ),
        _context.copyWith(deviceSessionId: 'new-device-session'),
        null,
      ]) {
        final c = harness(FakeInboxRepository());
        await ready(c);
        c.read(posDeviceContextProvider.notifier).set(context);
        expect(c.read(onlineOrderInboxControllerProvider).requests, isEmpty);
      }
    },
  );
  test(
    'invalid session clears customer data and latches manual polling',
    () async {
      final repo = FakeInboxRepository();
      final c = harness(repo);
      final controller = await ready(c);
      repo.onFetch = (_, _) async =>
          throw const OnlineInboxException(OnlineInboxFailure.invalidSession);
      await controller.refresh();
      final calls = repo.fetches.length;
      expect(c.read(onlineOrderInboxControllerProvider).requests, isEmpty);
      controller.onResume();
      await controller.refresh();
      expect(repo.fetches, hasLength(calls));
    },
  );
  test(
    'background stops discovery and foreground resumes one bounded page',
    () async {
      final repo = FakeInboxRepository();
      final c = harness(repo);
      final controller = await ready(c);
      controller.onPaused();
      final calls = repo.fetches.length;
      await controller.refresh();
      expect(repo.fetches, hasLength(calls));
      controller.onResume();
      await pumpEventQueue(times: 5);
      expect(repo.fetches, hasLength(calls + 1));
    },
  );
  test(
    'expired lookup ends uncertainty and has zero canonical effects',
    () async {
      final refreshed = <String>[];
      final repo = FakeInboxRepository();
      repo.onDecide = (_) async {
        throw const OnlineInboxException(OnlineInboxFailure.transport);
      };
      repo.onFetch = (id, _) async => inboxPage(
        requests: [inboxRequest(status: id == null ? 'pending' : 'expired')],
      );
      final c = harness(repo, refreshed: refreshed);
      await (await ready(c)).decide(requestId, OnlineOrderDecision.accept);
      expect(c.read(onlineOrderInboxControllerProvider).intent, isNull);
      expect(
        c.read(onlineOrderInboxControllerProvider).failure,
        OnlineInboxFailure.requestExpired,
      );
      expect(refreshed, isEmpty);
      expect(repo.decisions, hasLength(1));
    },
  );
}
