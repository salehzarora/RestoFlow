import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
import 'package:restoflow_pos/src/data/order_submission.dart'
    show OrderDispatchMode;
import 'package:restoflow_pos/src/spool/kitchen_readiness_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_readiness_evidence.dart';
import 'package:restoflow_pos/src/spool/kitchen_spool_readiness_probe.dart';

/// POS-KITCHEN-WORKFLOW-REGRESSION-001 — the order-submission gate must always
/// reach an explicit state.
///
/// THE DEFECT. `KitchenModeReadinessLoading` was a state with entrances but no
/// guaranteed exit, and the cart only offers a Retry affordance for
/// `Unavailable`. So every path that reached Loading without arranging its own
/// resolution stranded the cashier on `جارٍ التحقق من إعداد المطبخ…` with no
/// way forward. Two such paths existed on a REAL paired device:
///
///  1. The readiness heartbeat provider WATCHES the device context, which
///     starts null and is published asynchronously by the pairing gate. The
///     first instance bound a null scope and was started by the lifecycle; the
///     rebuild that followed the gate's publish bound the REAL scope (resetting
///     readiness to Loading) but was never started, because `onStartup` is only
///     called from initState's post-frame callback and from app resume.
///  2. A run that found no scope returned without publishing anything at all.
///
/// These tests pin the repaired contract at the seam each defect lived in.
class _ManualTimer implements Timer {
  _ManualTimer(this.onTick);

  final void Function() onTick;
  bool cancelled = false;
  int ticks = 0;

  void fire() {
    if (cancelled) return;
    ticks++;
    onTick();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => ticks;
}

const _context = DeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  deviceId: 'dev-1',
);

const _scope = PosKitchenModeScopeKey(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);

const _spoolResult = KitchenSpoolReadinessProbeResult(
  secureSpoolAvailable: true,
  unresolvedLocalJobs: 0,
  spoolCountState: KitchenSpoolCountState.counted,
);

/// A station with NO local printer of its own — the Separate-KDS shape.
const _blockedEvidence = BlockedKitchenPrinterEvidence('no_printer');

void main() {
  // ---------------------------------------------------------------------
  // 1. Workflow resolution — the gate always terminates.
  // ---------------------------------------------------------------------
  group('001-1 workflow resolution', () {
    late ProviderContainer container;

    PosKitchenModeReadinessController controllerOf(ProviderContainer c) =>
        c.read(posKitchenModeReadinessProvider.notifier);

    setUp(() {
      container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          // A short, deterministic watchdog so the bound is observable without
          // a 30-second test.
          posKitchenModeVerificationTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    test('Separate KDS resolves to READY without any local printer', () {
      final c = controllerOf(container);
      c
          .bindScope(_scope)
          .publish(
            KitchenModeVerifiedKds(
              verifiedAt: DateTime.utc(2026, 8, 5),
              revision: 4,
            ),
          );

      final decision = resolvePosSubmissionDecision(
        container.read(posKitchenModeReadinessProvider),
      );
      // No printer was configured, assigned or even consulted here.
      expect(decision.canSubmit, isTrue);
      expect(decision.dispatchMode, OrderDispatchMode.kds);
      expect(decision.blockReason, isNull);
    });

    test('Single POS + kitchen printer resolves to READY and dispatches '
        'direct_print', () {
      final c = controllerOf(container);
      c
          .bindScope(_scope)
          .publish(
            KitchenModePrinterOnlyWithRevision(
              revision: 7,
              verifiedAt: DateTime.utc(2026, 8, 5),
            ),
          );

      final decision = resolvePosSubmissionDecision(
        container.read(posKitchenModeReadinessProvider),
      );
      expect(decision.canSubmit, isTrue);
      expect(decision.dispatchMode, OrderDispatchMode.directPrint);
    });

    test('a SCOPED loading state cannot stay loading forever — the watchdog '
        'hands over an actionable, RETRYABLE state', () async {
      final c = controllerOf(container);
      c.bindScope(_scope); // binds and leaves the gate Loading

      expect(
        container.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessLoading>(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      final state = container.read(posKitchenModeReadinessProvider);
      expect(
        state,
        isA<KitchenModeReadinessUnavailable>(),
        reason: 'the spinner must convert into a state the operator can act on',
      );
      // Unavailable is the reason the cart renders WITH a Retry button; loading
      // is the one that renders without one.
      final decision = resolvePosSubmissionDecision(state);
      expect(decision.canSubmit, isFalse);
      expect(
        decision.blockReason,
        PosSubmissionBlockReason.kitchenModeUnavailable,
      );
    });

    test('a mode that arrives before the watchdog fires wins, and the '
        'watchdog never downgrades it afterwards', () async {
      final c = controllerOf(container);
      c
          .bindScope(_scope)
          .publish(
            KitchenModeVerifiedKds(
              verifiedAt: DateTime.utc(2026, 8, 5),
              revision: 4,
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        container.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessResolved>(),
        reason: 'a resolved mode must survive its own loading watchdog',
      );
    });

    test('DEMO mode resolves immediately and arms no watchdog', () async {
      final demo = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          posKitchenModeVerificationTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
      );
      addTearDown(demo.dispose);

      expect(
        demo.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessResolved>(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        demo.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessResolved>(),
      );
    });
  });

  // ---------------------------------------------------------------------
  // 2. The heartbeat seam — no silent no-scope run, no duplicate fetches.
  // ---------------------------------------------------------------------
  group('001-2 heartbeat reporting', () {
    late List<_ManualTimer> timers;
    late int modeFetches;
    late int noScopeCalls;
    late List<KitchenModeResult> published;
    late int unavailableCalls;
    DeviceContext? context;

    setUp(() {
      timers = [];
      modeFetches = 0;
      noScopeCalls = 0;
      published = [];
      unavailableCalls = 0;
      context = _context;
    });

    KitchenReadinessHeartbeat build() => KitchenReadinessHeartbeat(
      deviceContext: () => context,
      fetchMode: () async {
        modeFetches++;
        return KitchenModeVerifiedKds(
          verifiedAt: DateTime.utc(2026, 8, 5),
          revision: 3,
        );
      },
      // Deliberately a station with NO printer: the Separate-KDS shape must not
      // stop the MODE from being published.
      printerEvidence: () async => _blockedEvidence,
      probeSpool: ({required deviceId, required branchId}) async =>
          _spoolResult,
      sendStatus: (_) async => const KitchenPosStatusAccepted(),
      sendReport: (_) async =>
          const KitchenReadinessAccepted(activationReady: true),
      invalidateModeCache: () async {},
      onMode: published.add,
      onModeUnavailable: () => unavailableCalls++,
      onNoScope: () => noScopeCalls++,
      appBuild: 'pos-test',
      periodicTimerFactory: (duration, tick) {
        final t = _ManualTimer(tick);
        timers.add(t);
        return t;
      },
    );

    test(
      'a run with NO paired scope announces it instead of going silent',
      () async {
        context = null;
        final hb = build();

        final report = await hb.reportNow(trigger: 'startup');

        expect(report.outcome, KitchenReadinessRunOutcome.skippedNoScope);
        // The regression: this used to publish NOTHING, leaving the gate Loading
        // with nothing scheduled to move it.
        expect(noScopeCalls, 1);
      },
    );

    test(
      'no local printer does NOT stop the kitchen mode being published',
      () async {
        final hb = build();

        final report = await hb.reportNow(trigger: 'startup');

        expect(published, hasLength(1));
        expect(published.single, isA<KitchenModeVerifiedKds>());
        expect(unavailableCalls, 0);
        // Readiness itself is correctly skipped — but only AFTER the mode landed.
        expect(
          report.outcome,
          KitchenReadinessRunOutcome.skippedEvidenceBlocked,
        );
        expect(report.statusReported, isTrue);
      },
    );

    test('concurrent triggers JOIN one run — repeated rebuilds cannot fan out '
        'into duplicate configuration fetches', () async {
      final hb = build();

      await Future.wait([
        hb.reportNow(trigger: 'startup'),
        hb.reportNow(trigger: 'printer_config_changed'),
        hb.reportNow(trigger: 'spool_state_changed'),
      ]);

      expect(modeFetches, 1);
    });

    test('startup arms exactly one foreground timer, and a second startup does '
        'not stack another', () async {
      final hb = build();
      hb.onStartup();
      hb.onStartup();
      await hb.reportNow(trigger: 'join');

      expect(timers, hasLength(1));
      expect(timers.single.isActive, isTrue);
      hb.dispose();
      expect(timers.single.isActive, isFalse);
    });
  });

  // ---------------------------------------------------------------------
  // 3. Source of truth — the central workflow decides kitchen printing.
  // ---------------------------------------------------------------------
  group('001-3 source of truth', () {
    test('while the workflow is unresolved nothing is FORCED, so a stale local '
        'preference can never masquerade as the central decision', () {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Unresolved -> null verified mode -> resolveOrderDispatchMode(null)==kds.
      expect(container.read(posVerifiedKitchenModeProvider), isNull);
    });

    test('a verified printer_only workflow is what makes kitchen printing '
        'mandatory — not a device toggle', () {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(posKitchenModeReadinessProvider.notifier)
          .bindScope(_scope)
          .publish(
            KitchenModePrinterOnlyWithRevision(
              revision: 2,
              verifiedAt: DateTime.utc(2026, 8, 5),
            ),
          );

      expect(
        container.read(posVerifiedKitchenModeProvider),
        isA<KitchenModePrinterOnlyWithRevision>(),
      );
    });
  });
}
