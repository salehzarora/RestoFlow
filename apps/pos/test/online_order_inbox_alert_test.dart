import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/online_order_inbox.dart';
import 'package:restoflow_pos/src/media/online_order_alert_audio.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/spool/online_order_print_hooks.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition.dart'
    show posKitchenSpoolRuntimeProvider;

import 'online_order_inbox_fixtures.dart';

const _otherRequestId = '10000000-0000-4000-8000-000000000002';
final _session = StateProvider<SyncSession?>(
  (ref) => const SyncSession(pinSessionId: pinId, deviceId: deviceId),
);
const _device = DeviceContext(
  organizationId: 'org',
  restaurantId: 'restaurant',
  branchId: 'branch',
  deviceId: deviceId,
  deviceType: 'pos',
  deviceSessionId: 'device-session',
);

class _Audio implements OnlineOrderAlertAudio {
  int plays = 0;
  int stops = 0;
  bool fail = false;
  Completer<void>? blockedPlay;
  @override
  Future<void> play() async {
    plays++;
    if (fail) throw StateError('Audio unavailable');
    await blockedPlay?.future;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}
}

/// Unlike the static fixtures, a live server clock advances on every read.
class _ClockedRepository implements OnlineOrderInboxRepository {
  _ClockedRepository(this.delegate, this.clock);
  final FakeInboxRepository delegate;
  final DateTime Function() clock;
  @override
  Future<OnlineInboxPage> fetch({
    String? requestId,
    OnlineInboxCursor? cursor,
  }) async {
    final page = await delegate.fetch(requestId: requestId, cursor: cursor);
    return OnlineInboxPage(
      serverTime: clock(),
      requests: page.requests,
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }

  @override
  Future<OnlineInboxDecisionResult> decide({
    required String requestId,
    required String decisionId,
    required OnlineOrderDecision decision,
    String? reason,
  }) => delegate.decide(
    requestId: requestId,
    decisionId: decisionId,
    decision: decision,
    reason: reason,
  );
}

OnlineOrderRequest _request({String id = requestId, Duration? expiresIn}) {
  final json = requestJson()..['request_id'] = id;
  if (expiresIn != null) {
    json['expires_at'] = inboxNow.add(expiresIn).toIso8601String();
  }
  return OnlineOrderRequest.fromJson(json);
}

Future<void> _withInbox(
  WidgetTester tester,
  Future<void> Function(
    ProviderContainer,
    OnlineOrderInboxController,
    _Audio,
    FakeInboxRepository,
  )
  body, {
  FakeInboxRepository? repository,
}) async {
  final start = tester.binding.clock.now();
  final audio = _Audio();
  final repo = repository ?? FakeInboxRepository();
  DateTime clock() =>
      inboxNow.add(tester.binding.clock.now().difference(start));
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posSyncSessionProvider.overrideWith((ref) => ref.watch(_session)),
      onlineOrderInboxRepositoryProvider.overrideWithValue(
        _ClockedRepository(repo, clock),
      ),
      onlineOrderAlertAudioProvider.overrideWithValue(audio),
      onlineOrderInboxAlertIntervalProvider.overrideWithValue(
        const Duration(seconds: 10),
      ),
      posSyncClockProvider.overrideWithValue(
        () => inboxNow.add(tester.binding.clock.now().difference(start)),
      ),
      clientIdGeneratorProvider.overrideWithValue(
        FixedClientIdGenerator([
          decisionId,
          '30000000-0000-4000-8000-000000000002',
        ]),
      ),
      onlineInboxCanonicalRefreshProvider.overrideWithValue((_) async {}),
    ],
  );
  c.read(posDeviceContextProvider.notifier).set(_device);
  final controller = c.read(onlineOrderInboxControllerProvider.notifier);
  try {
    await tester.pump();
    await body(c, controller, audio, repo);
  } finally {
    c.dispose();
    await tester.pump();
  }
}

void main() {
  for (final otherPending in [false, true]) {
    testWidgets(
      'trusted expiry refusal suppresses only expired request (other pending: $otherPending)',
      (tester) async {
        final repo = FakeInboxRepository()
          ..onFetch = (_, _) async => inboxPage(
            requests: [
              _request(),
              if (otherPending) _request(id: _otherRequestId),
            ],
          );
        await _withInbox(tester, (c, controller, audio, repo) async {
          repo.onDecide = (_) async => throw const OnlineInboxException(
            OnlineInboxFailure.requestExpired,
          );
          await controller.decide(requestId, OnlineOrderDecision.accept);
          expect(audio.stops, otherPending ? 0 : 1);
          await tester.pump(const Duration(seconds: 10));
          expect(audio.plays, otherPending ? 2 : 1);
          expect(repo.decisions, hasLength(1));
        }, repository: repo);
      },
    );
  }

  testWidgets(
    'new arrival alerts once while the existing single loop continues',
    (tester) async {
      await _withInbox(tester, (c, controller, audio, repo) async {
        await tester.pump(const Duration(seconds: 4));
        repo.onFetch = (_, _) async => inboxPage(
          requests: [
            _request(),
            _request(id: _otherRequestId),
          ],
        );
        await controller.refresh();
        expect(audio.plays, 2);
        await controller.refresh();
        expect(audio.plays, 2);
        await tester.pump(const Duration(seconds: 10));
        expect(audio.plays, 3);
        expect(repo.fetches, hasLength(3));
      });
    },
  );

  testWidgets('late old-scope discovery cannot restart sound after logout', (
    tester,
  ) async {
    final firstRead = Completer<OnlineInboxPage>();
    final repo = FakeInboxRepository()..onFetch = (_, _) => firstRead.future;
    await _withInbox(tester, (c, controller, audio, repo) async {
      expect(audio.plays, 0);
      expect(c.exists(onlineInboxPrintRecoveryProvider), isFalse);
      expect(c.exists(posKitchenSpoolRuntimeProvider), isFalse);
      c.read(_session.notifier).state = null;
      expect(c.read(onlineOrderInboxControllerProvider).requests, isEmpty);
      firstRead.complete(inboxPage());
      await tester.pump(const Duration(seconds: 20));
      expect(audio.plays, 0);
    }, repository: repo);
  });

  testWidgets(
    'first pending alert and ten-second cadence do not depend on sheet',
    (tester) async {
      await _withInbox(tester, (c, controller, audio, repo) async {
        expect(audio.plays, 1);
        await tester.pump(const Duration(seconds: 9));
        expect(audio.plays, 1);
        await tester.pump(const Duration(seconds: 1));
        expect(audio.plays, 2);
        await controller.refresh();
        controller.onResume();
        await tester.pump();
        expect(audio.plays, 2);
        await tester.pump(const Duration(seconds: 10));
        expect(audio.plays, 3);
        expect(repo.fetches, hasLength(3)); // no audio-triggered polling
      });
    },
  );

  testWidgets(
    'multiple pending requests share one cadence and remaining request keeps ringing',
    (tester) async {
      final repo = FakeInboxRepository()
        ..onFetch = (_, _) async => inboxPage(
          requests: [
            _request(),
            _request(id: _otherRequestId),
          ],
        );
      await _withInbox(tester, (c, controller, audio, repo) async {
        expect(audio.plays, 1);
        await controller.refresh();
        await controller.decide(requestId, OnlineOrderDecision.accept);
        expect(
          c.read(onlineOrderInboxControllerProvider).requests.single.id,
          _otherRequestId,
        );
        expect(audio.stops, 0);
        await tester.pump(const Duration(seconds: 10));
        expect(audio.plays, 2);
        repo.onDecide = (call) async => OnlineInboxDecisionResult.fromJson(
          decisionJson(status: 'rejected')..['request_id'] = call.requestId,
        );
        await controller.decide(
          _otherRequestId,
          OnlineOrderDecision.reject,
          reason: 'Unavailable',
        );
        expect(audio.stops, 1);
        await tester.pump(const Duration(seconds: 20));
        expect(audio.plays, 2);
      }, repository: repo);
    },
  );

  for (final decision in OnlineOrderDecision.values) {
    testWidgets(
      'only confirmed final ${decision.name} stops alert immediately',
      (tester) async {
        final result = Completer<OnlineInboxDecisionResult>();
        final repo = FakeInboxRepository()..onDecide = (_) => result.future;
        await _withInbox(tester, (c, controller, audio, repo) async {
          final sending = controller.decide(
            requestId,
            decision,
            reason: decision == OnlineOrderDecision.reject
                ? 'Unavailable'
                : null,
          );
          await tester.pump(const Duration(seconds: 10));
          expect(audio.plays, 2); // a local tap is not confirmation
          expect(audio.stops, 0);
          result.complete(
            OnlineInboxDecisionResult.fromJson(
              decisionJson(
                status: decision == OnlineOrderDecision.accept
                    ? 'accepted'
                    : 'rejected',
              ),
            ),
          );
          await sending;
          expect(audio.stops, 1);
          await tester.pump(const Duration(seconds: 20));
          expect(audio.plays, 2);
        }, repository: repo);
      },
    );
  }

  testWidgets(
    'expiry stops at exact server deadline between cadence ticks despite failed reads',
    (tester) async {
      final repo = FakeInboxRepository()
        ..onFetch = (_, _) async => inboxPage(
          requests: [_request(expiresIn: const Duration(seconds: 3))],
        );
      await _withInbox(tester, (c, controller, audio, repo) async {
        repo.onFetch = (_, _) async =>
            throw const OnlineInboxException(OnlineInboxFailure.transport);
        await controller.refresh();
        await tester.pump(const Duration(seconds: 2));
        expect(audio.stops, 0);
        await tester.pump(const Duration(seconds: 1));
        expect(audio.stops, 1);
        expect(
          c
              .read(onlineOrderInboxControllerProvider)
              .pendingCountAt(controller.now()),
          0,
        );
        await tester.pump(const Duration(seconds: 20));
        expect(audio.plays, 1);
      }, repository: repo);
    },
  );

  testWidgets(
    'uncertain decision and failed reads retain alert until locking accepted recovery',
    (tester) async {
      await _withInbox(tester, (c, controller, audio, repo) async {
        repo.onDecide = (_) async =>
            throw const OnlineInboxException(OnlineInboxFailure.transport);
        repo.onFetch = (_, _) async =>
            throw const OnlineInboxException(OnlineInboxFailure.transport);
        await controller.decide(requestId, OnlineOrderDecision.accept);
        expect(c.read(onlineOrderInboxControllerProvider).uncertain, isTrue);
        expect(audio.stops, 0);
        await tester.pump(const Duration(seconds: 10));
        expect(audio.plays, 2);
        repo.onFetch = (_, _) async =>
            inboxPage(requests: [inboxRequest(status: 'accepted')]);
        await controller.recoverDecision();
        expect(audio.stops, 1);
        expect(repo.decisions, hasLength(1));
      });
    },
  );

  testWidgets(
    'pause stops immediately and resume alerts for existing pending request',
    (tester) async {
      await _withInbox(tester, (c, controller, audio, repo) async {
        controller.onPaused();
        expect(audio.stops, 1);
        await tester.pump(const Duration(seconds: 20));
        expect(audio.plays, 1);
        controller.onResume();
        await tester.pump();
        expect(audio.plays, 2);
        await tester.pump(const Duration(seconds: 10));
        expect(audio.plays, 3);
      });
    },
  );

  testWidgets('new pending discovery on resume alerts without opening sheet', (
    tester,
  ) async {
    final repo = FakeInboxRepository()
      ..onFetch = (_, _) async => inboxPage(requests: []);
    await _withInbox(tester, (c, controller, audio, repo) async {
      expect(audio.plays, 0);
      controller.onPaused();
      repo.onFetch = (_, _) async => inboxPage();
      controller.onResume();
      await tester.pump();
      expect(audio.plays, 1);
      expect(c.exists(onlineInboxPrintRecoveryProvider), isFalse);
      expect(c.exists(posKitchenSpoolRuntimeProvider), isFalse);
    }, repository: repo);
  });

  testWidgets(
    'offline and security lock stop notification without changing decision',
    (tester) async {
      await _withInbox(tester, (c, controller, audio, repo) async {
        c
            .read(posOfflineModeProvider.notifier)
            .recordOfflineCacheServed(snapshotFetchedAt: inboxNow);
        expect(audio.stops, 1);
        await tester.pump(const Duration(seconds: 20));
        expect(audio.plays, 1);
        c.read(posOfflineModeProvider.notifier).recordOnlineFetch();
        await tester.pump();
        expect(audio.plays, 2);
        repo.onFetch = (_, _) async => throw const OnlineInboxException(
          OnlineInboxFailure.permissionDenied,
        );
        await controller.refresh();
        expect(audio.stops, 2);
        controller.onResume();
        await tester.pump(const Duration(seconds: 20));
        expect(audio.plays, 2);
        expect(repo.decisions, isEmpty);
      });
    },
  );

  for (final boundary in [
    'logout',
    'pin',
    'branch',
    'device-session',
    'unpair',
  ]) {
    testWidgets('$boundary cancels old schedule and clears old scope', (
      tester,
    ) async {
      await _withInbox(tester, (c, controller, audio, repo) async {
        repo.onFetch = (_, _) async => inboxPage(requests: []);
        switch (boundary) {
          case 'logout':
            c.read(_session.notifier).state = null;
          case 'pin':
            c.read(_session.notifier).state = const SyncSession(
              pinSessionId: 'new-pin',
              deviceId: deviceId,
            );
          case 'branch':
            c
                .read(posDeviceContextProvider.notifier)
                .set(
                  const DeviceContext(
                    organizationId: 'org',
                    restaurantId: 'restaurant',
                    branchId: 'other',
                    deviceId: deviceId,
                    deviceType: 'pos',
                    deviceSessionId: 'device-session',
                  ),
                );
          case 'device-session':
            c
                .read(posDeviceContextProvider.notifier)
                .set(_device.copyWith(deviceSessionId: 'new-session'));
          case 'unpair':
            c.read(posDeviceContextProvider.notifier).set(null);
        }
        expect(c.read(onlineOrderInboxControllerProvider).requests, isEmpty);
        expect(audio.stops, 1);
        await tester.pump(const Duration(seconds: 20));
        expect(audio.plays, 1);
      });
    });
  }

  testWidgets('slow audio never overlaps and pause cancels it', (tester) async {
    final repo = FakeInboxRepository()
      ..onFetch = (_, _) async => inboxPage(requests: []);
    await _withInbox(tester, (c, controller, audio, repo) async {
      audio.blockedPlay = Completer<void>();
      repo.onFetch = (_, _) async => inboxPage();
      await controller.refresh();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(audio.plays, 1);
      controller.onPaused();
      expect(audio.stops, 1);
      audio.blockedPlay!.complete();
      await tester.pump();
      expect(audio.plays, 1);
    }, repository: repo);
  });

  testWidgets(
    'audio unavailable fails silently and does not affect acceptance',
    (tester) async {
      await _withInbox(tester, (c, controller, audio, repo) async {
        audio.fail = true;
        await tester.pump(const Duration(seconds: 10));
        await controller.decide(requestId, OnlineOrderDecision.accept);
        expect(c.read(onlineOrderInboxControllerProvider).requests, isEmpty);
        expect(repo.decisions, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets('dispose releases active audio and cancels scheduled repeats', (
    tester,
  ) async {
    final start = tester.binding.clock.now();
    final audio = _Audio();
    final c = ProviderContainer(
      overrides: [
        onlineOrderInboxIdentityProvider.overrideWithValue('identity'),
        onlineOrderInboxRepositoryProvider.overrideWithValue(
          FakeInboxRepository(),
        ),
        onlineOrderAlertAudioProvider.overrideWithValue(audio),
        onlineOrderInboxAlertIntervalProvider.overrideWithValue(
          const Duration(seconds: 10),
        ),
        posSyncClockProvider.overrideWithValue(
          () => inboxNow.add(tester.binding.clock.now().difference(start)),
        ),
      ],
    );
    c.read(onlineOrderInboxControllerProvider);
    await tester.pump();
    expect(audio.plays, 1);
    c.dispose();
    expect(audio.stops, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(audio.plays, 1);
  });
}
