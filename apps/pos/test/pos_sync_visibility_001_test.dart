import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/widgets/device_settings_menu.dart';
import 'package:restoflow_pos/src/widgets/language_selector.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_indicator.dart';
import 'package:restoflow_pos/src/widgets/ready_notification_bell.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// POS-SYNC-VISIBILITY-001 — the POS tablet header must always be able to PROVE
/// its sync state, and reading that state must never change it.
///
/// The defect: [OutboxStatusIndicator] rendered `SizedBox.shrink()` whenever the
/// durable queue was empty and storage was healthy. A tablet that had taken no
/// orders yet therefore showed NO sync state at all — which is exactly the
/// moment the pre-migration gate has to read "All orders synced" before the app
/// is uninstalled. An absent chip and a healthy chip looked identical.
///
/// The second defect: tapping the chip ran retry-all or clear-resolved
/// depending on which state happened to be showing. Reading a till's status
/// could re-queue its failed orders.

const Key kChip = Key('outbox-status-indicator');
const Key kSheet = Key('sync-details-sheet');

class _Seeded extends OutboxController {
  _Seeded(this._seed);
  final List<OutboxEntry> _seed;
  int retryAllCalls = 0;
  int dismissCalls = 0;

  @override
  List<OutboxEntry> build() => _seed;

  @override
  Future<void> retryAllFailed() async => retryAllCalls++;

  @override
  Future<int> dismissResolvedFailures() async {
    dismissCalls++;
    return 1;
  }
}

OutboxEntry _e(OutboxSyncState state, {String op = 'op', String? errorCode}) =>
    OutboxEntry(
      id: 'outbox-$op',
      deviceId: 'd',
      localOperationId: op,
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: 'order-$op',
      payloadJson: '{}',
      summary: const OrderSummary(
        orderNumber: 'DEMO-1',
        orderType: OrderType.dineIn,
        tableLabel: 'T1',
        itemCount: 1,
        subtotalMinor: 1000,
        currencyCode: 'ILS',
      ),
      syncState: state,
      clientCreatedAt: DateTime.utc(2026, 8, 4, 9),
      lastErrorCode: errorCode,
    );

Future<_Seeded> _pumpShell(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  List<OutboxEntry> seed = const [],
  // A spinner animates forever, so pumpAndSettle would time out on the
  // in-flight state. Those cases pump a fixed number of frames instead.
  bool settle = true,
}) async {
  final controller = _Seeded(seed);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [outboxControllerProvider.overrideWith(() => controller)],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
  return controller;
}

Future<AppLocalizations> _l10n(Locale l) => AppLocalizations.delegate.load(l);

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // 1. HEADER INTEGRATION — visible in the real shell, at real tablet sizes.
  // ───────────────────────────────────────────────────────────────────────────
  group('001-1 header integration', () {
    const tabletSizes = <String, Size>{
      '1024x600': Size(1024, 600),
      '1280x800': Size(1280, 800),
      '1366x768': Size(1366, 768),
    };

    for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
      tabletSizes.forEach((name, size) {
        testWidgets(
          'visible with an EMPTY queue at $name (${locale.languageCode})',
          (tester) async {
            await _pumpShell(tester, size: size, locale: locale);
            final l10n = await _l10n(locale);

            // THE REGRESSION GUARD: an empty queue must still say so.
            expect(find.byKey(kChip), findsOneWidget);
            expect(find.text(l10n.posOutboxSynced), findsOneWidget);
            expect(
              tester.takeException(),
              isNull,
              reason: 'a RenderFlex overflow throws in tests',
            );

            // It sits with the other actions, not inside an overflow menu.
            expect(find.byType(ReadyNotificationBell), findsOneWidget);
            expect(find.byType(RecentOrdersButton), findsOneWidget);
            expect(find.byType(LanguageSelector), findsOneWidget);
            expect(find.byType(DeviceSettingsMenu), findsOneWidget);

            // And it does not sit on top of any of them.
            final chip = tester.getRect(find.byKey(kChip));
            for (final other in [
              find.byType(ReadyNotificationBell),
              find.byType(RecentOrdersButton),
              find.byType(LanguageSelector),
              find.byType(DeviceSettingsMenu),
            ]) {
              expect(
                chip.overlaps(tester.getRect(other)),
                isFalse,
                reason: 'sync chip overlaps a neighbouring action at $name',
              );
            }
          },
        );
      });
    }

    testWidgets('the tap target is at least 44dp', (tester) async {
      await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('en'),
      );
      final s = tester.getSize(find.byKey(kChip));
      expect(s.height, greaterThanOrEqualTo(44));
      expect(s.width, greaterThanOrEqualTo(44));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. STATE MAPPING — every state distinguishable, never colour alone.
  // ───────────────────────────────────────────────────────────────────────────
  group('001-2 state mapping', () {
    Future<void> expectLabel(
      WidgetTester tester,
      List<OutboxEntry> seed,
      String Function(AppLocalizations) label, {
      bool settle = true,
    }) async {
      await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('en'),
        seed: seed,
        settle: settle,
      );
      final l10n = await _l10n(const Locale('en'));
      expect(find.text(label(l10n)), findsOneWidget);
    }

    testWidgets('all applied', (tester) async {
      await expectLabel(tester, [
        _e(OutboxSyncState.applied),
      ], (l) => l.posOutboxSynced);
    });

    testWidgets('syncing', (tester) async {
      await expectLabel(
        tester,
        [_e(OutboxSyncState.inFlight)],
        (l) => l.posOutboxSyncing,
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('pending shows the real count', (tester) async {
      await expectLabel(tester, [
        _e(OutboxSyncState.pending, op: 'a'),
        _e(OutboxSyncState.pending, op: 'b'),
      ], (l) => l.posOutboxPending(2));
    });

    testWidgets('failed shows the real count', (tester) async {
      await expectLabel(tester, [
        _e(OutboxSyncState.rejected, op: 'a', errorCode: 'transport'),
      ], (l) => l.posOutboxFailed(1));
    });

    testWidgets('attention is explicit and never reads as success', (
      tester,
    ) async {
      await expectLabel(tester, [
        _e(OutboxSyncState.conflict),
      ], (l) => l.posOutboxAttention);
      final l10n = await _l10n(const Locale('en'));
      expect(find.text(l10n.posOutboxSynced), findsNothing);
    });

    testWidgets('the state is spoken, not signalled by colour alone', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('en'),
      );
      final l10n = await _l10n(const Locale('en'));
      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label)
          .whereType<String>();
      expect(labels.any((l) => l.contains(l10n.posOutboxSynced)), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. SAFE INTERACTION — reading never mutates; acting always asks.
  // ───────────────────────────────────────────────────────────────────────────
  group('001-3 safe interaction', () {
    testWidgets('tapping the chip OPENS details and mutates nothing', (
      tester,
    ) async {
      final c = await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('en'),
        seed: [_e(OutboxSyncState.rejected, op: 'a', errorCode: 'transport')],
      );
      await tester.tap(find.byKey(kChip));
      await tester.pumpAndSettle();

      expect(find.byKey(kSheet), findsOneWidget);
      expect(c.retryAllCalls, 0);
      expect(c.dismissCalls, 0);
    });

    testWidgets('closing details mutates nothing', (tester) async {
      final c = await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('en'),
        seed: [_e(OutboxSyncState.rejected, op: 'a', errorCode: 'transport')],
      );
      await tester.tap(find.byKey(kChip));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync-details-close')));
      await tester.pumpAndSettle();

      expect(find.byKey(kSheet), findsNothing);
      expect(c.retryAllCalls, 0);
      expect(c.dismissCalls, 0);
    });

    testWidgets('cancelling the retry confirmation performs no retry', (
      tester,
    ) async {
      final c = await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('en'),
        seed: [_e(OutboxSyncState.rejected, op: 'a', errorCode: 'transport')],
      );
      await tester.tap(find.byKey(kChip));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('outbox-retry-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sync-action-confirm')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sync-action-cancel')));
      await tester.pumpAndSettle();
      expect(c.retryAllCalls, 0);
    });

    testWidgets('a confirmed retry invokes the controller exactly once', (
      tester,
    ) async {
      final c = await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('en'),
        seed: [_e(OutboxSyncState.rejected, op: 'a', errorCode: 'transport')],
      );
      await tester.tap(find.byKey(kChip));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('outbox-retry-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync-action-confirm-run')));
      await tester.pumpAndSettle();
      expect(c.retryAllCalls, 1);
    });

    testWidgets('cancelling the clear confirmation clears nothing', (
      tester,
    ) async {
      final c = await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('en'),
        seed: [
          for (var i = 1; i <= 6; i++)
            _e(OutboxSyncState.rejected, op: 'old-$i', errorCode: 'rejected'),
        ],
      );
      await tester.tap(find.byKey(kChip));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('outbox-clear-resolved')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync-action-cancel')));
      await tester.pumpAndSettle();
      expect(c.dismissCalls, 0);
    });

    testWidgets('an all-synced till offers no destructive action at all', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('en'),
      );
      await tester.tap(find.byKey(kChip));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('outbox-retry-all')), findsNothing);
      expect(find.byKey(const Key('outbox-clear-resolved')), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. MIGRATION GATE — the exact evidence the operator must be able to read.
  // ───────────────────────────────────────────────────────────────────────────
  group('001-4 migration gate', () {
    for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
      testWidgets(
        'all-applied is an EXPLICIT localized state (${locale.languageCode})',
        (tester) async {
          await _pumpShell(
            tester,
            size: const Size(1280, 800),
            locale: locale,
            seed: [_e(OutboxSyncState.applied)],
          );
          final l10n = await _l10n(locale);

          // Explicit words, in the operator's language — not a green dot.
          expect(find.text(l10n.posOutboxSynced), findsOneWidget);

          // And the details sheet says what it MEANS.
          await tester.tap(find.byKey(kChip));
          await tester.pumpAndSettle();
          expect(
            find.text(l10n.posSyncDetailsExplainSynced),
            findsOneWidget,
            reason: 'the migration decision rests on this sentence',
          );
          expect(find.byKey(const Key('sync-count-pending')), findsOneWidget);
          expect(find.byKey(const Key('sync-count-failed')), findsOneWidget);
        },
      );
    }

    testWidgets('reading the state twice never triggers an action', (
      tester,
    ) async {
      final c = await _pumpShell(
        tester,
        size: const Size(1280, 800),
        locale: const Locale('ar'),
      );
      final l10n = await _l10n(const Locale('ar'));
      // Observation 1.
      expect(find.text(l10n.posOutboxSynced), findsOneWidget);
      // Navigate away and back, exactly as the gate instructs.
      await tester.tap(find.byKey(kChip));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync-details-close')));
      await tester.pumpAndSettle();
      // Observation 2.
      expect(find.text(l10n.posOutboxSynced), findsOneWidget);
      expect(c.retryAllCalls, 0);
      expect(c.dismissCalls, 0);
    });
  });
}
