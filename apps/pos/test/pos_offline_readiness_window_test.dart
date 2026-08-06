// POS-OFFLINE-OPERATIONS-002 — C7 kitchen-mode 2-hour offline trust window.
//
// Covers OFFLINE-ARCH-SPEC tests 15 and 16:
//   15 — the 2h window in/out: a snapshot capture inside the window
//        reconstructs the SAME verified mode (kds / printer_only+revision,
//        original revision + verifiedAt carried through) and resolves the
//        readiness marked offlineTrusted; outside the window (or a future
//        claim, or a revision-less printer_only) no trust is extended — and a
//        RESTART never resets the clock, because the window derives ONLY from
//        the snapshot's server-verified verifiedAt;
//   16 — the Send block copy: while selling from the offline snapshot
//        (phase == offlineCached) an UNAVAILABLE kitchen mode blocks Send with
//        posOfflineKitchenModeStale (retry unchanged), and a restored session
//        past its own window blocks Send with posOfflineSendBlockedSession.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show
        KitchenModePrinterOnlyWithRevision,
        KitchenModeTransientFailure,
        KitchenModeVerifiedKds,
        RuntimeConfig,
        runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
import 'package:restoflow_pos/src/data/operational_snapshot_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart'
    show OrderDispatchMode;
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);

const _scopeKey = PosKitchenModeScopeKey(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);

PosOperationalSnapshot _snapshot({PosSnapshotKitchenMode? kitchenMode}) =>
    PosOperationalSnapshot(
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: 'branch-1',
      deviceId: 'dev-1',
      menu: const PosMenuData(categories: [], items: [], currencyCode: 'ILS'),
      fetchedAt: DateTime.utc(2026, 8, 6, 9),
      kitchenMode: kitchenMode,
    );

/// [POS-OFFLINE-OPERATIONS-002] Fixed offlineCached phase for the cart test —
/// the phase the menu fetch records when it serves the durable snapshot.
class _OfflineCachedPhase extends PosOfflineController {
  @override
  PosOfflineState build() => PosOfflineState(
    phase: PosOfflinePhase.offlineCached,
    snapshotFetchedAt: DateTime.utc(2026, 8, 6, 9),
    menuFromCache: true,
  );
}

/// A restored-offline session whose hard window already ENDED (C6).
class _ExpiredRestoreInfo extends PosSessionOfflineRestoreInfoController {
  @override
  PosSessionOfflineRestoreInfo build() => PosSessionOfflineRestoreInfo(
    restoredOffline: true,
    validUntil: DateTime.utc(2020, 1, 1),
  );
}

void main() {
  group('spec test 15 — the 2h window, in and out', () {
    final verifiedAt = DateTime.utc(2026, 8, 6, 10);

    test('inside the window both verified shapes reconstruct with their '
        'ORIGINAL revision + verifiedAt', () {
      final kds = reconstructOfflineTrustedKitchenMode(
        mode: 'kds',
        verifiedAt: verifiedAt,
        revision: 4,
        now: verifiedAt.add(const Duration(hours: 1, minutes: 59)),
      );
      expect(kds, isA<KitchenModeVerifiedKds>());
      expect((kds! as KitchenModeVerifiedKds).verifiedAt, verifiedAt);
      expect((kds as KitchenModeVerifiedKds).revision, 4);

      final printerOnly = reconstructOfflineTrustedKitchenMode(
        mode: 'printer_only',
        verifiedAt: verifiedAt,
        revision: 7,
        now: verifiedAt.add(const Duration(hours: 2)), // boundary INCLUSIVE
      );
      expect(printerOnly, isA<KitchenModePrinterOnlyWithRevision>());
      expect((printerOnly! as KitchenModePrinterOnlyWithRevision).revision, 7);
      expect(
        (printerOnly as KitchenModePrinterOnlyWithRevision).verifiedAt,
        verifiedAt,
      );
    });

    test('outside the window — and for every untrustworthy shape — no trust '
        'is extended', () {
      expect(
        reconstructOfflineTrustedKitchenMode(
          mode: 'kds',
          verifiedAt: verifiedAt,
          revision: 4,
          now: verifiedAt.add(const Duration(hours: 2, seconds: 1)),
        ),
        isNull,
      );
      // A revision-less printer_only was never importable trust online.
      expect(
        reconstructOfflineTrustedKitchenMode(
          mode: 'printer_only',
          verifiedAt: verifiedAt,
          now: verifiedAt.add(const Duration(minutes: 5)),
        ),
        isNull,
      );
      // A future claim beyond skew tolerance is suspect, never fresh trust.
      expect(
        reconstructOfflineTrustedKitchenMode(
          mode: 'kds',
          verifiedAt: verifiedAt.add(const Duration(minutes: 10)),
          revision: 4,
          now: verifiedAt,
        ),
        isNull,
      );
      // An unknown mode string fails closed.
      expect(
        reconstructOfflineTrustedKitchenMode(
          mode: 'drive_through',
          verifiedAt: verifiedAt,
          revision: 4,
          now: verifiedAt,
        ),
        isNull,
      );
    });

    test('a RESTART never resets the window: the clock derives only from the '
        'snapshot\'s server-verified verifiedAt', () async {
      SharedPreferences.setMockInitialValues(const {});
      final captured = DateTime.utc(2026, 8, 6, 10);
      await SharedPrefsOperationalSnapshotStore().save(
        _scope,
        _snapshot(
          kitchenMode: PosSnapshotKitchenMode(
            mode: 'printer_only',
            revision: 7,
            verifiedAt: captured,
          ),
        ),
      );

      // "Restart": a brand-new store instance over the SAME durable prefs.
      final reloaded =
          await SharedPrefsOperationalSnapshotStore().load(_scope)
              as PosOperationalSnapshotLoaded;
      final capture = reloaded.snapshot.kitchenMode!;
      // 90 minutes after capture (through however many restarts): trusted.
      expect(
        reconstructOfflineTrustedKitchenMode(
          mode: capture.mode,
          verifiedAt: capture.verifiedAt,
          revision: capture.revision,
          now: captured.add(const Duration(minutes: 90)),
        ),
        isNotNull,
      );
      // 2h10m after capture: expired — no restart/reconnect flag can revive it.
      expect(
        reconstructOfflineTrustedKitchenMode(
          mode: capture.mode,
          verifiedAt: capture.verifiedAt,
          revision: capture.revision,
          now: captured.add(const Duration(hours: 2, minutes: 10)),
        ),
        isNull,
      );
    });

    test('an offline-trusted publish resolves the readiness MARKED '
        'offlineTrusted and permits submission; a normal publish stays '
        'unmarked', () {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posKitchenModeVerificationTimeoutProvider.overrideWithValue(
            const Duration(minutes: 5),
          ),
        ],
      );
      addTearDown(c.dispose);
      final controller = c.read(posKitchenModeReadinessProvider.notifier);
      final binding = controller.bindScope(_scopeKey);
      final reconstructed = reconstructOfflineTrustedKitchenMode(
        mode: 'printer_only',
        verifiedAt: DateTime.utc(2026, 8, 6, 10),
        revision: 7,
        now: DateTime.utc(2026, 8, 6, 11),
      )!;
      binding.publish(reconstructed, offlineTrusted: true);

      final resolved =
          c.read(posKitchenModeReadinessProvider)
              as KitchenModeReadinessResolved;
      expect(resolved.offlineTrusted, isTrue);
      expect(resolved.mode, isA<KitchenModePrinterOnlyWithRevision>());
      final decision = resolvePosSubmissionDecision(resolved);
      expect(decision.canSubmit, isTrue);
      expect(decision.dispatchMode, OrderDispatchMode.directPrint);

      // A live publish through the SAME binding stays unmarked (additive
      // default) — no existing call site changes behavior.
      binding.publish(
        KitchenModeVerifiedKds(verifiedAt: DateTime.utc(2026, 8, 6, 11)),
      );
      final live =
          c.read(posKitchenModeReadinessProvider)
              as KitchenModeReadinessResolved;
      expect(live.offlineTrusted, isFalse);

      // A transient blip after resolution never downgrades (unchanged rule).
      binding.publish(const KitchenModeTransientFailure());
      expect(
        c.read(posKitchenModeReadinessProvider),
        isA<KitchenModeReadinessResolved>(),
      );
    });
  });

  group('spec test 16 — the Send block copy', () {
    Future<(ProviderContainer, AppLocalizations)> pumpCart(
      WidgetTester tester, {
      List<Override> extra = const [],
    }) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posKitchenModeVerificationTimeoutProvider.overrideWithValue(
              const Duration(milliseconds: 400),
            ),
            outboxRepositoryProvider.overrideWithValue(
              DemoOutboxStore(delay: (_) async {}),
            ),
            ...extra,
          ],
          child: const MaterialApp(
            locale: Locale('en'),
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

    testWidgets('kitchen mode UNAVAILABLE while offlineCached blocks Send '
        'with the STALE copy — retry unchanged', (tester) async {
      final (c, l10n) = await pumpCart(
        tester,
        extra: [posOfflineModeProvider.overrideWith(_OfflineCachedPhase.new)],
      );
      // Drive the gate to the retryable Unavailable state (the recovery-002
      // idiom): reset to Loading, then let the watchdog fire.
      c.read(posKitchenModeReadinessProvider.notifier).reset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // The C7 copy replaces the generic one ONLY in the offline phase…
      expect(find.text(l10n.posOfflineKitchenModeStale), findsOneWidget);
      expect(find.text(l10n.posCloseWorkflowUnavailable), findsNothing);
      // …and the retry affordance is untouched.
      expect(find.byKey(const Key('kitchen-mode-retry')), findsOneWidget);
    });

    testWidgets('kitchen mode UNAVAILABLE while ONLINE keeps the existing '
        'generic copy (no offline claim without offline evidence)', (
      tester,
    ) async {
      final (c, l10n) = await pumpCart(tester);
      c.read(posKitchenModeReadinessProvider.notifier).reset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text(l10n.posCloseWorkflowUnavailable), findsOneWidget);
      expect(find.text(l10n.posOfflineKitchenModeStale), findsNothing);
    });

    testWidgets('a restored session past ITS window blocks Send with the '
        'session copy (C6) — kitchen hints stay silent', (tester) async {
      final (_, l10n) = await pumpCart(
        tester,
        extra: [
          posSessionOfflineRestoreInfoProvider.overrideWith(
            _ExpiredRestoreInfo.new,
          ),
        ],
      );
      // The demo kitchen readiness resolves immediately, so the ONLY hint on
      // the row is the session reason.
      expect(find.text(l10n.posOfflineSendBlockedSession), findsOneWidget);
      expect(find.text(l10n.posOfflineKitchenModeStale), findsNothing);
      expect(find.byKey(const Key('kitchen-mode-retry')), findsNothing);
      // And Send is genuinely OFF.
      final send = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(l10n.posSendOrder),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(send.onPressed, isNull);
    });
  });
}
