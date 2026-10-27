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
import 'package:restoflow_pos/src/spool/online_order_print_hooks.dart';

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
  List<(String, String)>? printed,
  Future<WebOrderPrintOutcome> Function(String, String)? print,
  Future<WebOrderPrintOutcome?> Function()? readRecovery,
  List<String> decisionIds = const [decisionId],
  DeviceContext deviceContext = _context,
}) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posSyncSessionProvider.overrideWith((ref) => ref.watch(_session)),
      _session.overrideWith(
        (ref) =>
            SyncSession(pinSessionId: pinId, deviceId: deviceContext.deviceId!),
      ),
      onlineOrderInboxRepositoryProvider.overrideWithValue(repo),
      onlineOrderInboxPollIntervalProvider.overrideWithValue(interval),
      posSyncClockProvider.overrideWithValue(clock ?? () => inboxNow),
      clientIdGeneratorProvider.overrideWithValue(
        FixedClientIdGenerator(decisionIds),
      ),
      onlineInboxCanonicalRefreshProvider.overrideWithValue((id) async {
        refreshed?.add(id);
      }),
      onlineInboxCancelPrintProvider.overrideWithValue(() {}),
      if (readRecovery != null)
        onlineInboxPrintRecoveryProvider.overrideWith((ref) async {
          final outcome = await readRecovery();
          return outcome == null
              ? null
              : WebOrderPrintHistory(unidentifiedOutcome: outcome);
        }),
      onlineInboxAcceptedPrintProvider.overrideWithValue(
        print ??
            (request, order) async {
              printed?.add((request, order));
              return WebOrderPrintOutcome.sent;
            },
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(posDeviceContextProvider.notifier).set(deviceContext);
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
    'ETA is frozen through locked pending recovery and never replaced',
    () async {
      final lookup = Completer<OnlineInboxPage>();
      final repo = FakeInboxRepository();
      repo.onFetch = (id, _) =>
          id == null ? Future.value(inboxPage()) : lookup.future;
      repo.onDecide = (_) async {
        if (repo.decisions.length == 1) {
          throw const OnlineInboxException(OnlineInboxFailure.transport);
        }
        return OnlineInboxDecisionResult.fromJson(decisionJson());
      };
      final c = harness(repo);
      final controller = await ready(c);
      final deciding = controller.decide(
        requestId,
        OnlineOrderDecision.accept,
        preparationMinutes: 45,
      );
      await pumpEventQueue(times: 5);
      expect(
        c.read(onlineOrderInboxControllerProvider).intent!.preparationMinutes,
        45,
      );
      await controller.decide(
        requestId,
        OnlineOrderDecision.accept,
        preparationMinutes: 10,
      );
      await controller.decide(
        requestId,
        OnlineOrderDecision.reject,
        reason: 'No',
      );
      expect(repo.decisions, hasLength(1));
      lookup.complete(inboxPage());
      await deciding;
      expect(repo.decisions, hasLength(2));
      expect(repo.decisions.map((call) => call.decisionId).toSet(), {
        decisionId,
      });
      expect(repo.decisions.map((call) => call.preparationMinutes).toSet(), {
        45,
      });
      expect(
        repo.decisions.every(
          (call) => call.decision == OnlineOrderDecision.accept,
        ),
        true,
      );
    },
  );

  test('terminal locked reconciliation never resends or changes ETA', () async {
    final repo = FakeInboxRepository();
    repo.onDecide = (_) async =>
        throw const OnlineInboxException(OnlineInboxFailure.transport);
    repo.onFetch = (id, _) async => id == null
        ? inboxPage()
        : inboxPage(requests: [inboxRequest(status: 'accepted')]);
    final c = harness(repo);
    final controller = await ready(c);
    await controller.decide(
      requestId,
      OnlineOrderDecision.accept,
      preparationMinutes: 240,
    );
    expect(repo.decisions, hasLength(1));
    expect(repo.decisions.single.preparationMinutes, 240);
    expect(c.read(onlineOrderInboxControllerProvider).intent, isNull);
  });

  test(
    'invalid ETA or reject ETA cannot create an intent or decision',
    () async {
      for (final minutes in [0, -1, 241]) {
        final repo = FakeInboxRepository();
        final c = harness(repo);
        final controller = await ready(c);
        await controller.decide(
          requestId,
          OnlineOrderDecision.accept,
          preparationMinutes: minutes,
        );
        expect(repo.decisions, isEmpty);
        expect(c.read(onlineOrderInboxControllerProvider).intent, isNull);
        expect(
          c.read(onlineOrderInboxControllerProvider).failure,
          OnlineInboxFailure.invalidRequest,
        );
      }
      final repo = FakeInboxRepository();
      final c = harness(repo);
      final controller = await ready(c);
      await controller.decide(
        requestId,
        OnlineOrderDecision.reject,
        reason: 'Sold out',
        preparationMinutes: 15,
      );
      expect(repo.decisions, isEmpty);
      expect(c.read(onlineOrderInboxControllerProvider).intent, isNull);
    },
  );

  test('paused or resolved request cannot confirm a chosen ETA', () async {
    final repo = FakeInboxRepository();
    final c = harness(repo);
    final controller = await ready(c);
    controller.onPaused();
    await controller.decide(
      requestId,
      OnlineOrderDecision.accept,
      preparationMinutes: 15,
    );
    expect(repo.decisions, isEmpty);
    repo.onFetch = (_, _) async => inboxPage(requests: []);
    controller.onResume();
    await pumpEventQueue(times: 10);
    await controller.decide(
      requestId,
      OnlineOrderDecision.accept,
      preparationMinutes: 15,
    );
    expect(repo.decisions, isEmpty);
  });

  test(
    'new authenticated POS devices join their own branch without an allowlist',
    () async {
      final identities = <String>{};
      for (var tenant = 1; tenant <= 2; tenant++) {
        for (var station = 1; station <= 2; station++) {
          final context = DeviceContext(
            organizationId: 'synthetic-organization-$tenant',
            restaurantId: 'synthetic-restaurant-$tenant',
            branchId: 'synthetic-branch-$tenant',
            deviceId: 'synthetic-pos-$tenant-$station',
            deviceType: 'pos',
            deviceSessionId: 'synthetic-pairing-$tenant-$station',
          );
          final repository = FakeInboxRepository();
          final container = harness(repository, deviceContext: context);
          await ready(container);
          final identity = container.read(onlineOrderInboxIdentityProvider);
          expect(identity, isNotNull);
          identities.add(identity!);
          expect(
            container
                .read(onlineOrderInboxControllerProvider)
                .pendingCountAt(inboxNow),
            1,
          );
          expect(repository.fetches, isNotEmpty);
          expect(repository.decisions, isEmpty);
        }
      }
      expect(identities, hasLength(4));
    },
  );
  test(
    'another POS observes accepted state without dispatching a second print',
    () async {
      var accepted = false;
      final firstPrints = <(String, String)>[];
      final secondPrints = <(String, String)>[];
      FakeInboxRepository repository() {
        final result = FakeInboxRepository();
        result.onFetch = (_, _) async =>
            inboxPage(requests: accepted ? [] : [inboxRequest()]);
        result.onDecide = (intent) async {
          if (accepted)
            throw const OnlineInboxException(
              OnlineInboxFailure.decisionConflict,
            );
          accepted = true;
          return OnlineInboxDecisionResult.fromJson(decisionJson());
        };
        return result;
      }

      final first = harness(repository(), printed: firstPrints);
      final secondRepo = repository();
      final second = harness(
        secondRepo,
        printed: secondPrints,
        deviceContext: _context.copyWith(
          deviceId: 'another-new-pos',
          deviceSessionId: 'another-pairing',
        ),
      );
      final firstController = await ready(first);
      final secondController = await ready(second);
      expect(
        first.read(onlineOrderInboxControllerProvider).pendingCountAt(inboxNow),
        1,
      );
      expect(
        second
            .read(onlineOrderInboxControllerProvider)
            .pendingCountAt(inboxNow),
        1,
      );
      await firstController.decide(requestId, OnlineOrderDecision.accept);
      await secondController.refresh();
      expect(
        second
            .read(onlineOrderInboxControllerProvider)
            .pendingCountAt(inboxNow),
        0,
      );
      await secondController.decide(requestId, OnlineOrderDecision.accept);
      expect(firstPrints, [(requestId, canonicalId)]);
      expect(secondPrints, isEmpty);
      expect(secondRepo.decisions, isEmpty);
    },
  );
  test(
    'missing printer retains accepted canonical order without a fallback resend',
    () async {
      final refreshed = <String>[];
      var targetCallbacks = 0;
      final repo = FakeInboxRepository();
      final c = harness(
        repo,
        refreshed: refreshed,
        print: (_, __) async {
          targetCallbacks++;
          return WebOrderPrintOutcome.blocked;
        },
      );
      final controller = await ready(c);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      expect(refreshed, [canonicalId]);
      expect(repo.decisions, hasLength(1));
      expect(targetCallbacks, 1);
      expect(c.read(onlineOrderInboxControllerProvider).printResultSequence, 1);
      expect(c.read(onlineOrderInboxControllerProvider).uncertain, isFalse);
      expect(
        c.read(onlineOrderInboxControllerProvider).printOutcome,
        WebOrderPrintOutcome.blocked,
      );
    },
  );
  test(
    'distinct completed failed callbacks get fresh presentation identities',
    () async {
      const secondRequest = '10000000-0000-4000-8000-000000000002';
      const secondDecision = '30000000-0000-4000-8000-000000000002';
      final secondJson = requestJson()..['request_id'] = secondRequest;
      final repo = FakeInboxRepository();
      repo.onFetch = (_, _) async => inboxPage(
        requests: [inboxRequest(), OnlineOrderRequest.fromJson(secondJson)],
      );
      repo.onDecide = (call) async => OnlineInboxDecisionResult.fromJson({
        ...decisionJson(),
        'request_id': call.requestId,
        'decision_id': call.decisionId,
        'canonical_order_id': call.requestId == requestId
            ? canonicalId
            : '20000000-0000-4000-8000-000000000002',
      });
      final callbacks = <String>[];
      final c = harness(
        repo,
        decisionIds: const [decisionId, secondDecision],
        print: (request, _) async {
          callbacks.add(request);
          return WebOrderPrintOutcome.failed;
        },
      );
      final controller = await ready(c);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      expect(c.read(onlineOrderInboxControllerProvider).printResultSequence, 1);
      await controller.decide(secondRequest, OnlineOrderDecision.accept);
      expect(c.read(onlineOrderInboxControllerProvider).printResultSequence, 2);
      expect(
        c.read(onlineOrderInboxControllerProvider).printOutcome,
        WebOrderPrintOutcome.failed,
      );
      expect(callbacks, [requestId, secondRequest]);
      expect(repo.decisions, hasLength(2));
      await controller.decide(secondRequest, OnlineOrderDecision.accept);
      expect(callbacks, [requestId, secondRequest]);
      expect(c.read(onlineOrderInboxControllerProvider).printResultSequence, 2);
    },
  );
  test(
    'an observed durable recovery view refreshes on existing discovery and resume cadence',
    () async {
      var reads = 0;
      var outcome = WebOrderPrintOutcome.attention;
      final c = harness(
        FakeInboxRepository(),
        readRecovery: () async {
          reads++;
          return outcome;
        },
      );
      final listener = c.listen(onlineInboxPrintRecoveryProvider, (_, _) {});
      addTearDown(listener.close);
      await c.read(onlineInboxPrintRecoveryProvider.future);
      final controller = await ready(c);
      await c.read(onlineInboxPrintRecoveryProvider.future);
      final beforeRefresh = reads;
      outcome = WebOrderPrintOutcome.failed;
      await controller.refresh();
      expect(
        (await c.read(onlineInboxPrintRecoveryProvider.future))?.outcome,
        WebOrderPrintOutcome.failed,
      );
      expect(reads, beforeRefresh + 1);
      controller.onPaused();
      final beforeResume = reads;
      controller.onResume();
      await pumpEventQueue(times: 10);
      expect(
        (await c.read(onlineInboxPrintRecoveryProvider.future))?.outcome,
        WebOrderPrintOutcome.failed,
      );
      expect(reads, beforeResume + 1);
    },
  );
  test(
    'confirmed Accept invokes exact target once; duplicate UI callback does not',
    () async {
      final printed = <(String, String)>[];
      final repo = FakeInboxRepository();
      final c = harness(repo, printed: printed);
      final controller = await ready(c);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      await controller.decide(requestId, OnlineOrderDecision.accept);
      expect(printed, [(requestId, canonicalId)]);
      expect(repo.decisions, hasLength(1));
      final resultSequence = c
          .read(onlineOrderInboxControllerProvider)
          .printResultSequence;
      expect(resultSequence, 1);
      await controller.refresh();
      expect(
        c.read(onlineOrderInboxControllerProvider).printResultSequence,
        resultSequence,
      );
      expect(
        c.read(onlineOrderInboxControllerProvider).printOutcome,
        WebOrderPrintOutcome.sent,
      );
    },
  );
  test('uncertain Accept prints only after locked accepted recovery', () async {
    final printed = <(String, String)>[];
    final repo = FakeInboxRepository();
    repo.onDecide = (_) async =>
        throw const OnlineInboxException(OnlineInboxFailure.transport);
    repo.onFetch = (id, _) async {
      if (id != null)
        throw const OnlineInboxException(OnlineInboxFailure.transport);
      return inboxPage();
    };
    final c = harness(repo, printed: printed);
    final controller = await ready(c);
    await controller.decide(requestId, OnlineOrderDecision.accept);
    expect(printed, isEmpty);
    repo.onFetch = (_, _) async =>
        inboxPage(requests: [inboxRequest(status: 'accepted')]);
    await controller.recoverDecision();
    await controller.recoverDecision();
    expect(printed, [(requestId, canonicalId)]);
  });
  test('Reject and expired never invoke targeted printing', () async {
    final printed = <(String, String)>[];
    final repo = FakeInboxRepository();
    final c = harness(repo, printed: printed);
    await (await ready(
      c,
    )).decide(requestId, OnlineOrderDecision.reject, reason: 'Unavailable');
    expect(printed, isEmpty);
  });
  test(
    'print failure cannot undo confirmed acceptance or recreate order',
    () async {
      final repo = FakeInboxRepository();
      final c = harness(
        repo,
        print: (_, _) async => throw StateError('lost reply'),
      );
      await (await ready(c)).decide(requestId, OnlineOrderDecision.accept);
      final state = c.read(onlineOrderInboxControllerProvider);
      expect(state.requests, isEmpty);
      expect(state.intent, isNull);
      expect(state.uncertain, isFalse);
      expect(state.printOutcome, WebOrderPrintOutcome.reconciliationRequired);
      expect(repo.decisions, hasLength(1));
    },
  );
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
