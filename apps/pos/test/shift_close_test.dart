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
  _FakeShiftRepo({this.outcome, this.error, this.openShift});
  final ShiftCloseOutcome? outcome;
  final ShiftException? error;

  /// The SERVER-authoritative open-shift summary the fresh expected-cash read
  /// (A5) returns; null = the server reports no readable summary.
  final OpenShiftInfo? openShift;
  int calls = 0;
  int readCalls = 0;

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
  Future<OpenShiftInfo?> readOpenShift() async {
    readCalls++;
    return openShift;
  }
}

OpenShiftInfo _summary(int expectedMinor, {int openingFloatMinor = 0}) =>
    OpenShiftInfo(
      shiftId: 'shift-1',
      cashDrawerSessionId: 'cd-1',
      openingFloatMinor: openingFloatMinor,
      openedAt: DateTime(2026, 7, 3, 9, 15),
      expectedCashMinor: expectedMinor,
    );

/// A transport returning a canned envelope for any RPC (for the sync_pull read).
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.response);
  final Object? response;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async =>
      response;
}

/// Finding 3 (F3E): a transport that dispatches by RPC name so a test can drive the
/// PRODUCTION session→shift.open→get_open_shift_summary path end-to-end (no injected
/// handle). Records which functions were called.
class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport(this._handler);
  final Future<Object?> Function(String function, Map<String, dynamic> params)
  _handler;
  final List<String> functions = <String>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    functions.add(function);
    return _handler(function, params);
  }
}

/// A complete operator context so `posSessionControllerProvider` auto-establishes a
/// REAL session (Finding 3 E2E driver).
PosRealSessionConfig _realConfig() => PosRealSessionConfig.fromValues(
  deviceId: 'device-abc',
  deviceSessionId: 'devsess-1',
  employeeProfileId: 'emp-1',
  pinVerifier: 'verifier-xyz',
)!;

/// A real-mode container wired to drive the production session bootstrap through
/// [transport] (Finding 3 E2E). The best-effort shift.open + authoritative summary run
/// fire-and-forget after the session resolves — `pumpEventQueue` lets them settle.
ProviderContainer _sessionContainer(SyncRpcTransport transport) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posRealSessionConfigProvider.overrideWithValue(_realConfig()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The canned per-op result for a shift.open push that the server APPLIED.
Object _shiftOpenApplied() => <String, dynamic>{
  'ok': true,
  'results': <dynamic>[
    <String, dynamic>{
      'operation_type': 'shift.open',
      'status': 'applied',
      'ok': true,
    },
  ],
};

/// Seeds a real staff session (so posSyncSessionProvider is non-null).
class _SeededSession extends PosSessionController {
  @override
  FutureOr<SyncSession?> build() =>
      const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');
}

/// Seeds a real, AUTHORITATIVELY-CLOSABLE open-shift handle (Finding 3: canClose no
/// longer defaults true, so an authorized seeded handle sets it explicitly).
class _SeededHandle extends PosOpenShiftController {
  @override
  PosOpenShift? build() => PosOpenShift(
    shiftId: 'shift-1',
    cashDrawerSessionId: 'cd-1',
    openingFloatMinor: 0,
    openedAt: DateTime(2026, 7, 3, 9, 15),
    canClose: true,
  );
}

/// Finding 3: a freshly opened shift whose authoritative verdict has not landed yet.
class _AuthPendingHandle extends PosOpenShiftController {
  @override
  PosOpenShift? build() => PosOpenShift(
    shiftId: 'shift-1',
    cashDrawerSessionId: 'cd-1',
    openingFloatMinor: 0,
    openedAt: DateTime(2026, 7, 3, 9, 15),
    authorizationPending: true, // canClose defaults false
  );
}

/// B1: an open-shift handle owned by ANOTHER employee (can_close=false).
class _MismatchHandle extends PosOpenShiftController {
  @override
  PosOpenShift? build() => PosOpenShift(
    shiftId: 'shift-A',
    cashDrawerSessionId: 'cd-A',
    openingFloatMinor: 0,
    openedAt: DateTime(2026, 7, 3, 9, 15),
    canClose: false,
    ownerMismatch: true,
    openedByEmployeeProfileId: 'emp-A',
  );
}

/// Finding 2: the current actor OWNS the shift but lacks the close_shift capability.
class _NoCapabilityHandle extends PosOpenShiftController {
  @override
  PosOpenShift? build() => PosOpenShift(
    shiftId: 'shift-1',
    cashDrawerSessionId: 'cd-1',
    openingFloatMinor: 0,
    openedAt: DateTime(2026, 7, 3, 9, 15),
    canClose: false,
    closeNotAllowed: true,
    openedByEmployeeProfileId: 'emp-self',
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
      // Finding 3: the server returns an EXPLICIT close verdict for an open shift; an
      // authorized owner recovering their shift carries can_close=true.
      'can_close': true,
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

  test('B1: readOpenShift parses an owner-mismatch (can_close=false, no money, '
      'the actual owner id)', () async {
    final repo = RealShiftRepository(
      _FakeTransport(<String, dynamic>{
        'ok': true,
        'has_open_shift': true,
        'can_close': false,
        'error': 'shift_owner_mismatch',
        'shift_id': 'shift-A',
        'status': 'open',
        'revision': 1,
        'opened_at': '2026-07-03T09:00:00Z',
        'opened_by_employee_profile_id': 'emp-A',
      }),
      const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      RandomClientIdGenerator(),
    );
    final info = await repo.readOpenShift();
    expect(info, isNotNull);
    expect(info!.ownerMismatch, isTrue);
    expect(info.canClose, isFalse);
    expect(info.expectedCashMinor, isNull); // NO money for a non-owner
    expect(info.openedByEmployeeProfileId, 'emp-A');
  });

  testWidgets(
    'B1: an owner-mismatch shift shows the mismatch state, NOT a close '
    'form under the current employee',
    (tester) async {
      final l10n = await _en();
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSessionControllerProvider.overrideWith(_SeededSession.new),
          posOpenShiftProvider.overrideWith(_MismatchHandle.new),
          shiftRepositoryProvider.overrideWithValue(_FakeShiftRepo()),
        ],
      );
      addTearDown(container.dispose);
      // Even though a different employee's name is set on this device...
      container.read(posSignedInStaffNameProvider.notifier).set('Employee B');
      await _pumpContainer(tester, container);
      // ...the sheet shows the owner-mismatch state, not a close form.
      expect(
        find.byKey(const Key('shift-close-owner-mismatch')),
        findsOneWidget,
      );
      expect(find.text(l10n.posShiftOwnerMismatch), findsOneWidget);
      expect(find.byKey(const Key('counted-cash-input')), findsNothing);
      expect(find.byKey(const Key('shift-close-submit')), findsNothing);
      // Signing out clears the stale owner state and ends the session.
      await tester.tap(find.byKey(const Key('shift-close-owner-signout')));
      await tester.pumpAndSettle();
      expect(container.read(posSyncSessionProvider), isNull);
      expect(container.read(posOpenShiftProvider), isNull);
    },
  );

  test(
    'F2: readOpenShift parses shift_close_not_allowed (owner, no capability, '
    'no money)',
    () async {
      final repo = RealShiftRepository(
        _FakeTransport(<String, dynamic>{
          'ok': true,
          'has_open_shift': true,
          'can_close': false,
          'error': 'shift_close_not_allowed',
          'shift_id': 'shift-1',
          'status': 'open',
          'revision': 1,
          'opened_at': '2026-07-03T09:00:00Z',
          'opened_by_employee_profile_id': 'emp-self',
        }),
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
        RandomClientIdGenerator(),
      );
      final info = await repo.readOpenShift();
      expect(info, isNotNull);
      expect(info!.closeNotAllowed, isTrue);
      expect(info.ownerMismatch, isFalse); // NOT misreported as owner mismatch
      expect(info.canClose, isFalse);
      expect(info.expectedCashMinor, isNull); // no money
    },
  );

  test(
    'Finding 3: an open-shift summary that OMITS can_close is FAIL-CLOSED — the '
    'recovered handle is not closable (a missing verdict is never permissive)',
    () async {
      final repo = RealShiftRepository(
        _FakeTransport(<String, dynamic>{
          'ok': true,
          'has_open_shift': true,
          // can_close deliberately ABSENT (an anomalous/older response).
          'shift_id': 'shift-1',
          'status': 'open',
          'revision': 1,
          'opened_at': '2026-07-03T09:00:00Z',
          'opening_float_minor': 0,
        }),
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
        RandomClientIdGenerator(),
      );
      final info = await repo.readOpenShift();
      expect(info, isNotNull);
      expect(
        info!.canClose,
        isFalse,
      ); // never default-true on a missing verdict
    },
  );

  testWidgets('F2: an owner cashier WITHOUT the close_shift capability sees a '
      'permission state — no close form, no money', (tester) async {
    final l10n = await _en();
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSessionControllerProvider.overrideWith(_SeededSession.new),
        // The server verdict (handle), not any local capability, drives the UI.
        posOpenShiftProvider.overrideWith(_NoCapabilityHandle.new),
        shiftRepositoryProvider.overrideWithValue(_FakeShiftRepo()),
      ],
    );
    addTearDown(container.dispose);
    container.read(posSignedInStaffNameProvider.notifier).set('Owner Cashier');
    await _pumpContainer(tester, container);
    // The capability-denied state, NOT a close form.
    expect(find.byKey(const Key('shift-close-not-allowed')), findsOneWidget);
    expect(find.text(l10n.posShiftCloseNotAllowed), findsOneWidget);
    // No close form, no counted-cash input, no expected/counted money, no submit.
    expect(find.byKey(const Key('counted-cash-input')), findsNothing);
    expect(find.byKey(const Key('shift-close-submit')), findsNothing);
    expect(find.text(l10n.posShiftExpectedCash), findsNothing);
    expect(find.byKey(const Key('shift-close-difference')), findsNothing);
  });

  testWidgets('PILOT-OPERATIONS-CORRECTIONS-001: after restart the shift-close '
      'expected shows the SERVER figure (not 0) so a correct close is accepted', (
    tester,
  ) async {
    // A5: the expected now comes from a FRESH server summary read (not a stale handle
    // field). The server reports ₪500.00 — the exact post-restart figure that used to
    // collapse to 0.
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSessionControllerProvider.overrideWith(_SeededSession.new),
        posOpenShiftProvider.overrideWith(_SeededHandle.new),
        shiftRepositoryProvider.overrideWithValue(
          _FakeShiftRepo(openShift: _summary(50000)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pumpContainer(tester, container);
    // Expected shows ₪500.00 (server), not ₪0.00 — counting that amount balances.
    expect(find.text('₪500.00'), findsWidgets);
  });

  group('A5: expected cash has ONE authoritative source (no double count)', () {
    test('1-5. race: server summary includes the mid-recovery payment; the '
        'client shows it ONCE, never server + local', () async {
      // The server summary already includes a cash payment that completed while the
      // summary was loading (expected 5000 = float 1000 + 4000 cash). The local
      // payment state ALSO holds that payment. The OLD code returned 5000 + 4000 =
      // 9000 (double-count). The provider must return exactly the server 5000.
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSessionControllerProvider.overrideWith(_SeededSession.new),
          posOpenShiftProvider.overrideWith(_SeededHandle.new),
          shiftRepositoryProvider.overrideWithValue(
            _FakeShiftRepo(openShift: _summary(5000, openingFloatMinor: 1000)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final expected = await container.read(shiftExpectedCashProvider.future);
      expect(expected, 5000); // exactly the server figure — not 9000
    });

    test('9/failure: a failed/absent server read yields null (never a false 0 '
        'or a local figure)', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSessionControllerProvider.overrideWith(_SeededSession.new),
          posOpenShiftProvider.overrideWith(_SeededHandle.new),
          // readOpenShift returns null (transport failure fails closed).
          shiftRepositoryProvider.overrideWithValue(_FakeShiftRepo()),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(shiftExpectedCashProvider.future), isNull);
    });

    test(
      'real currentShiftView never carries a combined expected (null)',
      () async {
        final container = ProviderContainer(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            posOpenShiftProvider.overrideWith(_SeededHandle.new),
          ],
        );
        addTearDown(container.dispose);
        expect(
          container.read(currentShiftViewProvider).expectedSoFarMinor,
          isNull,
        );
      },
    );

    test('8. a true-zero shift reads 0 from the server (not null)', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posOpenShiftProvider.overrideWith(_SeededHandle.new),
          shiftRepositoryProvider.overrideWithValue(
            _FakeShiftRepo(openShift: _summary(0)),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(shiftExpectedCashProvider.future), 0);
    });

    test(
      '7/11. demo expected is the in-memory drawer total (integer minor)',
      () async {
        final container = ProviderContainer(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: true),
            ),
          ],
        );
        addTearDown(container.dispose);
        // Demo opens with a ₪200.00 float, no sales -> 20000 minor.
        expect(await container.read(shiftExpectedCashProvider.future), 20000);
      },
    );
  });

  testWidgets(
    'PILOT-OPERATIONS-CORRECTIONS-001: the shift-close sheet names the '
    'signed-in employee',
    (tester) async {
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
    },
  );

  group('Finding 3: a fresh shift.open is not proof of close authorization', () {
    testWidgets(
      'a freshly opened shift awaiting its authoritative verdict shows a '
      'FAIL-CLOSED pending state — no close form, no money, no counted input, '
      'no close action',
      (tester) async {
        final l10n = await _en();
        await _pump(
          tester,
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            // A fresh-open handle: a shift IS open, but authorizationPending and
            // canClose defaults false (no server verdict yet).
            posOpenShiftProvider.overrideWith(_AuthPendingHandle.new),
            shiftRepositoryProvider.overrideWithValue(_FakeShiftRepo()),
          ],
        );

        expect(
          find.byKey(const Key('shift-close-authorization-pending')),
          findsOneWidget,
        );
        expect(find.text(l10n.posShiftAuthorizationPending), findsOneWidget);
        // Fail closed: NO form, NO counted input, NO money, NO close/submit action.
        expect(find.byKey(const Key('counted-cash-input')), findsNothing);
        expect(find.byKey(const Key('shift-close-submit')), findsNothing);
        expect(find.text(l10n.posShiftExpectedCash), findsNothing);
        expect(find.byKey(const Key('shift-close-difference')), findsNothing);
      },
    );

    test(
      'E2E: the production session→shift.open→get_open_shift_summary path first '
      'publishes a fail-closed handle, then the AUTHORITATIVE server verdict '
      'enables close for an allowed owner',
      () async {
        final transport = _ScriptedTransport((function, params) async {
          if (function == 'start_pin_session') return 'pin-session-id';
          if (function == 'sync_push') return _shiftOpenApplied();
          // get_open_shift_summary: the owner MAY close (server-authoritative).
          return <String, dynamic>{
            'ok': true,
            'has_open_shift': true,
            'can_close': true,
            'shift_id': 'shift-srv',
            'cash_drawer_session_id': 'cd-srv',
            'opening_float_minor': 0,
            'expected_cash_minor': 2500,
            'opened_at': '2026-07-16T09:00:00Z',
            'opened_by_employee_profile_id': 'emp-1',
          };
        });
        final container = _sessionContainer(transport);

        final session = await container.read(
          posSessionControllerProvider.future,
        );
        expect(session, isNotNull);
        // Let the fire-and-forget shift bootstrap + summary read settle.
        await pumpEventQueue(times: 20);

        final handle = container.read(posOpenShiftProvider);
        expect(handle, isNotNull);
        // The authoritative verdict landed — pending cleared, close permitted.
        expect(handle!.authorizationPending, isFalse);
        expect(handle.canClose, isTrue);
        expect(handle.expectedCashMinor, 2500);
        // The production path actually consulted the authoritative summary.
        expect(transport.functions, contains('get_open_shift_summary'));
      },
    );

    test('E2E: a disabled cashier who opens a fresh shift gets a fail-closed, '
        'close-not-allowed verdict from the summary — NEVER a permissive '
        'canClose handle, and no money', () async {
      final transport = _ScriptedTransport((function, params) async {
        if (function == 'start_pin_session') return 'pin-session-id';
        if (function == 'sync_push') return _shiftOpenApplied();
        // The owning cashier lacks the close_shift capability.
        return <String, dynamic>{
          'ok': true,
          'has_open_shift': true,
          'can_close': false,
          'error': 'shift_close_not_allowed',
          'shift_id': 'shift-srv',
          'cash_drawer_session_id': 'cd-srv',
          'opening_float_minor': 0,
          'opened_at': '2026-07-16T09:00:00Z',
          'opened_by_employee_profile_id': 'emp-1',
        };
      });
      final container = _sessionContainer(transport);

      await container.read(posSessionControllerProvider.future);
      await pumpEventQueue(times: 20);

      final handle = container.read(posOpenShiftProvider);
      expect(handle, isNotNull);
      expect(handle!.canClose, isFalse); // never permissive
      expect(handle.closeNotAllowed, isTrue); // derived from the SERVER summary
      expect(handle.authorizationPending, isFalse); // an authoritative denial
      expect(handle.expectedCashMinor, isNull); // no money for a denied close
    });

    test(
      'E2E: when the authoritative summary cannot be read after a fresh open, '
      'the handle stays FAIL-CLOSED (authorization pending, no money) — never '
      'a permissive canClose handle',
      () async {
        final transport = _ScriptedTransport((function, params) async {
          if (function == 'start_pin_session') return 'pin-session-id';
          if (function == 'sync_push') return _shiftOpenApplied();
          // get_open_shift_summary fails transiently -> readOpenShift returns null.
          throw const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: '503',
            message: 'unavailable',
          );
        });
        final container = _sessionContainer(transport);

        await container.read(posSessionControllerProvider.future);
        await pumpEventQueue(times: 20);

        final handle = container.read(posOpenShiftProvider);
        expect(handle, isNotNull); // a shift IS open on this device
        expect(handle!.authorizationPending, isTrue); // but fail-closed
        expect(handle.canClose, isFalse); // NEVER assume close permission
        expect(handle.expectedCashMinor, isNull);
      },
    );
  });
}
