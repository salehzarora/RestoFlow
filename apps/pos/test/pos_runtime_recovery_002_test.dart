// POS-RUNTIME-RECOVERY-002 — the permanent «جارٍ التحقق من إعداد المطبخ…»
// regression, reproduced at the REAL seams the tablet exercises.
//
// THE DEFECT CLASS. The kitchen-readiness gate had THREE unowned-lifetime holes
// that PR #197's direct-construction tests could not see, because they drove the
// coordinator/controller by hand instead of materializing the LAZY provider
// through the real widget lifecycle:
//
//  1. `posKitchenReadinessHeartbeatProvider` is a lazy `Provider` that is ONLY
//     ever `ref.read` from `PosSyncLifecycle`'s post-frame callback and from app
//     resume. A device context published AFTER that read invalidates the
//     provider but nothing re-reads it, so the new scope never starts its own
//     verification (and a stale unscoped verdict silently stands).
//  2. The post-frame callback is one unprotected sequence: a synchronous throw
//     while materializing ANY earlier sibling (the spool runtime, the sync
//     controller, the ready poller) skips the heartbeat startup AND the
//     unscoped seed entirely — leaving the controller on its INITIAL unscoped
//     `Loading`, which armed NO watchdog. Loading became a terminal state with
//     a spinner and no Retry.
//  3. `bindScope` bumps the generation on a SAME-scope rebind without
//     re-arming the loading watchdog, so the already-armed watchdog's captured
//     generation goes stale and its fire becomes a no-op — another unbounded
//     Loading.
//
// Synthetic values only. No network, no printer, no orders, no prints.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/pos_sync_lifecycle.dart';

/// A transport that exists (so real mode composes) but never answers — every
/// bounded-exit assertion below must hold WITHOUT the network's help.
final class _HangingTransport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) =>
      Completer<Object?>().future;
}

const _ctxA = DeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  deviceId: 'dev-1',
);
const _ctxB = DeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-2',
  restaurantId: 'rest-1',
  deviceId: 'dev-1',
);
const _scopeA = PosKitchenModeScopeKey(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);
const _scopeB = PosKitchenModeScopeKey(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-2',
  deviceId: 'dev-1',
);

const _shortTimeout = Duration(milliseconds: 120);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The real composition constructs FlutterSecureDeviceSessionStore; on the
  // test VM its channel would throw. A null-returning handler makes every
  // secure read an honest MISS (no credential, no cached mode) — which is
  // exactly the deterministic InvalidSession/no-seed world these repros need.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  ProviderContainer realModeContainer({List<Override> extra = const []}) {
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posKitchenModeVerificationTimeoutProvider.overrideWithValue(
          _shortTimeout,
        ),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> elapse() => Future<void>.delayed(_shortTimeout * 3);

  group('controller determinism (POS-RUNTIME-RECOVERY-002)', () {
    test('R1 REPRO: the initial unscoped Loading has a bounded exit through '
        'the last-resort bound even when every startup path failed', () async {
      final c = realModeContainer();
      final controller = c.read(posKitchenModeReadinessProvider.notifier);
      expect(
        c.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessLoading>(),
      );
      // The tablet shape: seed/heartbeat/bind never arrive. The lifecycle's
      // final guarded step (and the subscription error path) invoke the
      // last-resort bound; it must be idempotent — a second call may not
      // reset the running clock.
      controller.ensureBoundedVerification();
      controller.ensureBoundedVerification();
      await elapse();
      expect(
        c.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessUnavailable>(),
        reason:
            'Loading must never be a terminal state: with no owner, the '
            'watchdog must hand the operator the retryable Unavailable state.',
      );
    });

    test(
      'R2 REPRO: a same-scope rebind must not orphan the loading watchdog',
      () async {
        final c = realModeContainer();
        final controller = c.read(posKitchenModeReadinessProvider.notifier);
        controller.bindScope(_scopeA); // Loading(scoped) + watchdog(gen G)
        controller.bindScope(_scopeA); // gen bump — the OLD watchdog goes stale
        await elapse();
        final state = c.read(posKitchenModeReadinessProvider);
        expect(
          state,
          isA<KitchenModeReadinessUnavailable>(),
          reason:
              'The rebind bumped the generation; unless the watchdog is '
              're-armed for the new generation, its fire is a no-op and Loading '
              'never exits.',
        );
        expect(state.scope, _scopeA);
      },
    );

    test('R3: a superseded binding cannot overwrite the new scope, which still '
        'resolves through its own binding', () async {
      final c = realModeContainer();
      final controller = c.read(posKitchenModeReadinessProvider.notifier);
      final b1 = controller.bindScope(_scopeA);
      final b2 = controller.bindScope(_scopeB);
      // The scope-change transition lands one microtask later (it may not be
      // written synchronously from a provider build — the vc23 root cause).
      await Future<void>.delayed(Duration.zero);
      b1.publish(KitchenModeVerifiedKds(verifiedAt: DateTime.utc(2026, 8, 6)));
      final afterStale = c.read(posKitchenModeReadinessProvider);
      expect(afterStale, isA<KitchenModeReadinessLoading>());
      expect(afterStale.scope, _scopeB);
      b2.publish(KitchenModeVerifiedKds(verifiedAt: DateTime.utc(2026, 8, 6)));
      final resolved = c.read(posKitchenModeReadinessProvider);
      expect(resolved, isA<KitchenModeReadinessResolved>());
      expect(resolved.scope, _scopeB);
    });

    test(
      'R4 REPRO: retry with no bound resolver is still a bounded episode',
      () async {
        final c = realModeContainer();
        final controller = c.read(posKitchenModeReadinessProvider.notifier);
        controller.bindScope(_scopeA);
        await elapse(); // watchdog -> Unavailable
        expect(
          c.read(posKitchenModeReadinessProvider),
          isA<KitchenModeReadinessUnavailable>(),
        );
        controller.requestResolution();
        expect(
          c.read(posKitchenModeReadinessProvider),
          isA<KitchenModeReadinessLoading>(),
          reason:
              'Retry must visibly re-open the gate even when no resolver is '
              'bound (the heartbeat may have failed to compose at all).',
        );
        await elapse();
        expect(
          c.read(posKitchenModeReadinessProvider),
          isA<KitchenModeReadinessUnavailable>(),
          reason: 'And that retry episode must itself be bounded.',
        );
      },
    );

    test(
      'R5: every non-trusted publish exits Loading into the retryable state',
      () async {
        final results = <KitchenModeResult>[
          const KitchenModeInvalidSession(),
          const KitchenModeTransientFailure(),
          const KitchenModeServerFailure(),
          const KitchenModeMalformedResponse(),
          const KitchenModeRevisionUnavailable(),
        ];
        for (final result in results) {
          final c = ProviderContainer(
            overrides: [
              runtimeConfigProvider.overrideWithValue(
                RuntimeConfig.test(isDemoMode: false),
              ),
              posKitchenModeVerificationTimeoutProvider.overrideWithValue(
                const Duration(minutes: 5), // watchdog may NOT be the rescuer
              ),
            ],
          );
          addTearDown(c.dispose);
          final binding = c
              .read(posKitchenModeReadinessProvider.notifier)
              .bindScope(_scopeA);
          binding.publish(result);
          expect(
            c.read(posKitchenModeReadinessProvider),
            isA<KitchenModeReadinessUnavailable>(),
            reason: '$result must not leave the gate Loading',
          );
        }
      },
    );

    test(
      'R6: a resolved mode is never downgraded by a stale watchdog',
      () async {
        final c = realModeContainer();
        final controller = c.read(posKitchenModeReadinessProvider.notifier);
        final binding = controller.bindScope(_scopeA);
        binding.publish(
          KitchenModePrinterOnlyWithRevision(
            revision: 4,
            verifiedAt: DateTime.utc(2026, 8, 6),
          ),
        );
        await elapse();
        final state = c.read(posKitchenModeReadinessProvider);
        expect(state, isA<KitchenModeReadinessResolved>());
        expect(
          (state as KitchenModeReadinessResolved).mode,
          isA<KitchenModePrinterOnlyWithRevision>(),
        );
      },
    );
  });

  group('real lifecycle wiring (delayed pairing restoration)', () {
    Future<ProviderContainer> pumpLifecycle(
      WidgetTester tester, {
      required List<Override> extra,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            posKitchenModeVerificationTimeoutProvider.overrideWithValue(
              const Duration(milliseconds: 400),
            ),
            posAuthTransportProvider.overrideWithValue(_HangingTransport()),
            ...extra,
          ],
          child: const MaterialApp(
            home: PosSyncLifecycle(child: SizedBox.shrink()),
          ),
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(PosSyncLifecycle)),
      );
    }

    testWidgets(
      'W1 REPRO(tablet): a throwing startup sibling must not strand the '
      'readiness on Loading — and must not escape as an unhandled error',
      (tester) async {
        final c = await pumpLifecycle(
          tester,
          extra: [
            // Simulates ANY member of the startup callback failing — on the
            // tablet the same shape kills the lines that would have started
            // the heartbeat and the unscoped seed.
            posKitchenSpoolRuntimeProvider.overrideWith(
              (ref) => throw StateError('simulated composition failure'),
            ),
          ],
        );
        await tester.pump(); // post-frame startup callback runs
        expect(
          tester.takeException(),
          isNull,
          reason:
              'A failed startup seam must be contained, not thrown through '
              'the post-frame callback.',
        );
        c.read(posDeviceContextProvider.notifier).set(_ctxA);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 200));
        final state = c.read(posKitchenModeReadinessProvider);
        expect(
          state is KitchenModeReadinessLoading,
          isFalse,
          reason:
              'The cashier saw «جارٍ التحقق من إعداد المطبخ…» forever: '
              'after the bounded window the gate must be actionable '
              '(Resolved or retryable Unavailable), whatever failed at '
              'startup. Actual: $state',
        );
      },
    );

    testWidgets(
      'W2 REPRO: a device scope restored AFTER startup re-triggers '
      'verification — a stale unscoped verdict cannot stand for a paired device',
      (tester) async {
        final c = await pumpLifecycle(
          tester,
          extra: [posKitchenSpoolRuntimeProvider.overrideWith((ref) => null)],
        );
        // Startup with NO restored context: the no-scope run honestly settles
        // the unscoped normal-KDS workflow (PR #197's onNoScope contract).
        await tester.pump(const Duration(milliseconds: 50));
        final beforeRestore = c.read(posKitchenModeReadinessProvider);
        expect(beforeRestore, isA<KitchenModeReadinessResolved>());
        expect(beforeRestore.scope, isNull);

        // The pairing gate publishes the restored context LATER — the real
        // tablet's cold-boot order.
        c.read(posDeviceContextProvider.notifier).set(_ctxA);
        await tester.pump(const Duration(milliseconds: 50));
        final afterRestore = c.read(posKitchenModeReadinessProvider);
        expect(
          afterRestore.scope,
          _scopeA,
          reason:
              'Every new valid scope must automatically own a fresh '
              'readiness resolution; the unscoped verdict must not survive '
              'the restore. Actual: $afterRestore',
        );
        // ... and that scoped episode is itself bounded (the secure store has
        // no credential here, so the fetch resolves InvalidSession -> the
        // retryable Unavailable; the watchdog is the outer belt).
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 200));
        final terminal = c.read(posKitchenModeReadinessProvider);
        expect(terminal is KitchenModeReadinessLoading, isFalse);
        expect(terminal.scope, _scopeA);
      },
    );

    testWidgets(
      'W3: a scope change while the previous scope is mid-verification follows '
      'the NEW scope and stays bounded (no duplicate watchdog, no stale write)',
      (tester) async {
        final c = await pumpLifecycle(
          tester,
          extra: [posKitchenSpoolRuntimeProvider.overrideWith((ref) => null)],
        );
        await tester.pump(const Duration(milliseconds: 50));
        c.read(posDeviceContextProvider.notifier).set(_ctxA);
        await tester.pump(const Duration(milliseconds: 20));
        c.read(posDeviceContextProvider.notifier).set(_ctxB);
        await tester.pump(const Duration(milliseconds: 50));
        expect(c.read(posKitchenModeReadinessProvider).scope, _scopeB);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 200));
        final terminal = c.read(posKitchenModeReadinessProvider);
        expect(terminal is KitchenModeReadinessLoading, isFalse);
        expect(terminal.scope, _scopeB);
      },
    );
  });

  group('real cart binding (Arabic operator view)', () {
    Future<(ProviderContainer, AppLocalizations)> pumpCart(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posKitchenModeVerificationTimeoutProvider.overrideWithValue(
              const Duration(milliseconds: 400),
            ),
            outboxRepositoryProvider.overrideWithValue(
              DemoOutboxStore(delay: (_) async {}),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: PosMenuScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
      await tester.pumpAndSettle();
      return (
        ProviderScope.containerOf(tester.element(find.byType(PosMenuScreen))),
        l10n,
      );
    }

    testWidgets(
      'D1 REPRO: the spinner the user was stuck on becomes a bounded, '
      'retryable, actionable state — and readiness checking never creates work',
      (tester) async {
        final (c, l10n) = await pumpCart(tester);
        // Force the gate back to Loading — the exact state the tablet froze in.
        c.read(posKitchenModeReadinessProvider.notifier).reset();
        await tester.pump();
        expect(find.text(l10n.posKitchenModeLoading), findsOneWidget);

        // Bounded: the watchdog must convert the spinner into the retryable
        // unavailable state the cart renders WITH a Retry affordance.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(find.text(l10n.posKitchenModeLoading), findsNothing);
        expect(find.text(l10n.posCloseWorkflowUnavailable), findsOneWidget);
        expect(find.text(l10n.posKitchenModeRetry), findsOneWidget);

        // Retry re-opens the gate (Loading again) and stays bounded.
        await tester.tap(find.text(l10n.posKitchenModeRetry));
        await tester.pump();
        expect(find.text(l10n.posKitchenModeLoading), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(find.text(l10n.posCloseWorkflowUnavailable), findsOneWidget);

        // The whole episode created NO order, NO outbox operation, NO print.
        expect(c.read(outboxControllerProvider), isEmpty);
      },
    );
  });
}
