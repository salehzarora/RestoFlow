import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/shift_repository.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_shift.dart';
import 'package:restoflow_pos/src/state/shift_close_controller.dart';
import 'package:restoflow_pos/src/widgets/shift_close_sheet.dart';

/// A fake shift repository returning a canned outcome (or throwing) so the real
/// close path can be tested without a transport.
class _FakeShiftRepo implements ShiftRepository {
  _FakeShiftRepo({this.outcome, this.error});
  final ShiftCloseOutcome? outcome;
  final ShiftException? error;
  int calls = 0;

  @override
  Future<ShiftCloseOutcome> closeShift({
    required String shiftId,
    required int countedMinor,
    String? reason,
    required String currencyCode,
  }) async {
    calls++;
    if (error != null) throw error!;
    return outcome!;
  }

  @override
  Future<OpenShiftInfo?> readOpenShift() async => null;
}

/// A transport returning a canned envelope for any RPC (for the sync_pull read).
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.response);
  final Object? response;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async =>
      response;
}

/// Seeds a real staff session (so posSyncSessionProvider is non-null).
class _SeededSession extends PosSessionController {
  @override
  FutureOr<SyncSession?> build() =>
      const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');
}

/// Seeds a real open-shift handle.
class _SeededHandle extends PosOpenShiftController {
  @override
  PosOpenShift? build() => PosOpenShift(
    shiftId: 'shift-1',
    cashDrawerSessionId: 'cd-1',
    openingFloatMinor: 0,
    openedAt: DateTime(2026, 7, 3, 9, 15),
  );
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: PosShiftCloseSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pump the sheet holding an explicit [container] so a test can read providers
/// (e.g. the session) after interacting.
Future<void> _pumpContainer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: PosShiftCloseSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('demo: counting cash shows the difference and closing shows the '
      'expected/counted/difference result', (tester) async {
    final l10n = await _en();
    await _pump(
      tester,
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: true),
        ),
      ],
    );

    // Demo store opens with a ₪200.00 float and no sales -> expected ₪200.00.
    expect(find.text('₪200.00'), findsWidgets);

    await tester.enterText(find.byKey(const Key('counted-cash-input')), '250');
    await tester.pump();
    // Over by ₪50.00 — a reason is now required before closing.
    expect(find.text('${l10n.posShiftOver} ₪50.00'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('shift-close-submit')))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const Key('shift-close-reason')), 'tip');
    await tester.pump();
    await tester.tap(find.byKey(const Key('shift-close-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shift-close-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shift-close-result')), findsOneWidget);
    expect(find.text(l10n.posShiftClosedTitle), findsOneWidget);
    // Result rows: expected ₪200.00, counted ₪250.00, over ₪50.00.
    expect(find.text('₪250.00'), findsWidgets);
    expect(find.text('${l10n.posShiftOver} ₪50.00'), findsOneWidget);
  });

  testWidgets('real: close posts to the repo and shows the server-authoritative '
      'balanced result', (tester) async {
    final l10n = await _en();
    final repo = _FakeShiftRepo(
      outcome: const ShiftCloseOutcome(
        expectedMinor: 15000,
        countedMinor: 15000,
        varianceMinor: 0,
        currencyCode: 'ILS',
      ),
    );
    await _pump(
      tester,
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posOpenShiftProvider.overrideWith(_SeededHandle.new),
        shiftRepositoryProvider.overrideWithValue(repo),
      ],
    );

    // The real handle (no client-side sales here) estimates ₪0.00 expected, so
    // any non-zero count needs a reason before we can submit.
    await tester.enterText(find.byKey(const Key('counted-cash-input')), '150');
    await tester.enterText(
      find.byKey(const Key('shift-close-reason')),
      'count',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('shift-close-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shift-close-confirm')));
    await tester.pumpAndSettle();

    expect(repo.calls, 1);
    expect(find.byKey(const Key('shift-close-result')), findsOneWidget);
    // The SERVER figures win: ₪150.00 expected/counted, balanced.
    expect(find.text('₪150.00'), findsWidgets);
    expect(find.text(l10n.posShiftBalanced), findsOneWidget);
  });

  testWidgets('real: with no open shift handle it shows the honest '
      '"no open shift" state, not a fake one', (tester) async {
    final l10n = await _en();
    await _pump(
      tester,
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
      ],
    );

    expect(find.byKey(const Key('shift-close-none')), findsOneWidget);
    expect(find.text(l10n.posShiftNoOpenShift), findsOneWidget);
    expect(find.byKey(const Key('counted-cash-input')), findsNothing);
  });

  testWidgets('real: a server rejection surfaces an honest error, not a fake '
      'close', (tester) async {
    final l10n = await _en();
    final repo = _FakeShiftRepo(error: const ShiftException('rejected_42501'));
    await _pump(
      tester,
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posOpenShiftProvider.overrideWith(_SeededHandle.new),
        shiftRepositoryProvider.overrideWithValue(repo),
      ],
    );

    await tester.enterText(find.byKey(const Key('counted-cash-input')), '0');
    await tester.pump();
    await tester.tap(find.byKey(const Key('shift-close-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shift-close-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shift-close-error')), findsOneWidget);
    expect(find.text(l10n.posShiftCloseServerRejected), findsOneWidget);
    expect(find.byKey(const Key('shift-close-result')), findsNothing);
  });

  testWidgets('real: authenticated but with no shift handle shows the honest '
      'recover state, and Sign out ends the session (returns to PIN)', (
    tester,
  ) async {
    final l10n = await _en();
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSessionControllerProvider.overrideWith(_SeededSession.new),
        shiftRepositoryProvider.overrideWithValue(_FakeShiftRepo()),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(posSyncSessionProvider), isNotNull);

    await _pumpContainer(tester, container);
    expect(find.byKey(const Key('shift-close-recover')), findsOneWidget);
    expect(find.text(l10n.posShiftCouldNotRestore), findsOneWidget);
    // No fake close form / no fake shift is shown.
    expect(find.byKey(const Key('counted-cash-input')), findsNothing);

    await tester.tap(find.byKey(const Key('shift-close-signout')));
    await tester.pumpAndSettle();
    expect(container.read(posSyncSessionProvider), isNull);
  });

  testWidgets('real: a successful close returns the POS to PIN so it is not '
      'left as an active cashier without a shift', (tester) async {
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSessionControllerProvider.overrideWith(_SeededSession.new),
        posOpenShiftProvider.overrideWith(_SeededHandle.new),
        shiftRepositoryProvider.overrideWithValue(
          _FakeShiftRepo(
            outcome: const ShiftCloseOutcome(
              expectedMinor: 0,
              countedMinor: 0,
              varianceMinor: 0,
              currencyCode: 'ILS',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(posSyncSessionProvider), isNotNull);

    await _pumpContainer(tester, container);
    // Counted 0 matches the estimate (float 0, no sales) -> no reason needed.
    await tester.enterText(find.byKey(const Key('counted-cash-input')), '0');
    await tester.pump();
    await tester.tap(find.byKey(const Key('shift-close-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shift-close-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shift-close-result')), findsOneWidget);
    // The staff session was ended -> POS returns to PIN sign-in.
    expect(container.read(posSyncSessionProvider), isNull);
  });

  test('PILOT-OPERATIONS-CORRECTIONS-001: readOpenShift recovers the SERVER '
      'expected cash from get_open_shift_summary (survives restart)', () async {
    // The get_open_shift_summary envelope carries the server-authoritative
    // expected (opening float 1000 + 4000 persisted cash = 5000) — the figure the
    // in-memory aggregation lost across a restart.
    final envelope = <String, dynamic>{
      'ok': true,
      'has_open_shift': true,
      'shift_id': 'shift-9',
      'cash_drawer_session_id': 'cd-9',
      'status': 'open',
      'revision': 1,
      'opened_at': '2026-07-03T09:00:00Z',
      'opening_float_minor': 1000,
      'cash_sales_minor': 4000,
      'expected_cash_minor': 5000,
    };
    final repo = RealShiftRepository(
      _FakeTransport(envelope),
      const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      RandomClientIdGenerator(),
    );
    final info = await repo.readOpenShift();
    expect(info, isNotNull);
    expect(info!.shiftId, 'shift-9');
    expect(info.cashDrawerSessionId, 'cd-9');
    expect(info.openingFloatMinor, 1000);
    expect(info.expectedCashMinor, 5000);
  });

  test('readOpenShift returns null when the server reports no open shift '
      '(honest, no fake handle)', () async {
    final repo = RealShiftRepository(
      _FakeTransport(<String, dynamic>{'ok': true, 'has_open_shift': false}),
      const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      RandomClientIdGenerator(),
    );
    expect(await repo.readOpenShift(), isNull);
  });

  testWidgets('PILOT-OPERATIONS-CORRECTIONS-001: after restart the shift-close '
      'expected shows the SERVER figure (not 0) so a correct close is accepted', (
    tester,
  ) async {
    // A recovered handle carrying the server expected (₪500.00) with NO in-memory
    // session sales — the exact post-restart state that used to collapse to 0.
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSessionControllerProvider.overrideWith(_SeededSession.new),
        posOpenShiftProvider.overrideWith(
          () => _SeededHandleExpected(50000),
        ),
        shiftRepositoryProvider.overrideWithValue(_FakeShiftRepo()),
      ],
    );
    addTearDown(container.dispose);
    await _pumpContainer(tester, container);
    // Expected shows ₪500.00 (server), not ₪0.00 — counting that amount balances.
    expect(find.text('₪500.00'), findsWidgets);
  });

  testWidgets('PILOT-OPERATIONS-CORRECTIONS-001: the shift-close sheet names the '
      'signed-in employee', (tester) async {
    final l10n = await _en();
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSessionControllerProvider.overrideWith(_SeededSession.new),
        posOpenShiftProvider.overrideWith(_SeededHandle.new),
        shiftRepositoryProvider.overrideWithValue(_FakeShiftRepo()),
      ],
    );
    addTearDown(container.dispose);
    container.read(posSignedInStaffNameProvider.notifier).set('Dana Cohen');
    await _pumpContainer(tester, container);
    expect(find.text(l10n.posShiftEmployee), findsOneWidget);
    expect(find.text('Dana Cohen'), findsOneWidget);
  });
}

/// A recovered open-shift handle carrying a server expected cash figure.
class _SeededHandleExpected extends PosOpenShiftController {
  _SeededHandleExpected(this.expectedMinor);
  final int expectedMinor;
  @override
  PosOpenShift? build() => PosOpenShift(
    shiftId: 'shift-1',
    cashDrawerSessionId: 'cd-1',
    openingFloatMinor: 0,
    openedAt: DateTime(2026, 7, 3, 9, 15),
    expectedCashMinor: expectedMinor,
  );
}
