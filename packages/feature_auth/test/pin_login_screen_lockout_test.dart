import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _FakeStaff implements DeviceStaffRepository {
  @override
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>>
  listStaff() async => const Success(<DeviceStaffMember>[
    DeviceStaffMember(
      employeeProfileId: 'emp-1',
      displayName: 'Amira K.',
      role: 'cashier',
    ),
  ]);
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required Future<PinLoginError?> Function(String, String) onStart,
  PinAttemptLimiter? limiter,
  bool expiredNotice = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: PinLoginScreen(
        staffRepository: _FakeStaff(),
        onStartSession: onStart,
        attemptLimiter: limiter,
        expiredNotice: expiredNotice,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'RF-118: repeated wrong PINs impose a visible client cooldown that '
    'disables the submit and blocks further attempts',
    (tester) async {
      final l10n = await _en();
      var serverCalls = 0;
      final limiter = PinAttemptLimiter(
        store: InMemoryPinAttemptStore(),
        maxAttempts: 3,
        lockoutDuration: const Duration(minutes: 15),
      );
      await _pump(
        tester,
        limiter: limiter,
        onStart: (_, _) async {
          serverCalls++;
          return PinLoginError.wrongPin;
        },
      );

      await tester.tap(find.byKey(const Key('pin-staff-emp-1')));
      await tester.pumpAndSettle();

      // Three wrong PINs reach the threshold.
      for (var i = 0; i < 3; i++) {
        await tester.enterText(find.byKey(const Key('pin-input')), '9999');
        await tester.tap(find.byKey(const Key('pin-submit')));
        await tester.pumpAndSettle();
      }
      expect(serverCalls, 3);

      // The visible lockout banner is shown and the submit is disabled.
      expect(find.text(l10n.pinLoginLocked), findsWidgets);
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('pin-submit')),
      );
      expect(submit.onPressed, isNull, reason: 'submit disabled while locked');

      // A further attempt does NOT call the server (blocked locally).
      await tester.enterText(find.byKey(const Key('pin-input')), '9999');
      await tester.tap(find.byKey(const Key('pin-submit')));
      await tester.pumpAndSettle();
      expect(
        serverCalls,
        3,
        reason: 'locked cooldown blocks more server calls',
      );
    },
  );

  testWidgets('RF-118: a correct PIN before the cap resets and signs in', (
    tester,
  ) async {
    final limiter = PinAttemptLimiter(
      store: InMemoryPinAttemptStore(),
      maxAttempts: 3,
    );
    var attempts = 0;
    await _pump(
      tester,
      limiter: limiter,
      onStart: (_, _) async {
        attempts++;
        return attempts < 2 ? PinLoginError.wrongPin : null; // 2nd try succeeds
      },
    );
    await tester.tap(find.byKey(const Key('pin-staff-emp-1')));
    await tester.pumpAndSettle();
    // One wrong, then a correct PIN -> success (host would swap the screen out).
    await tester.enterText(find.byKey(const Key('pin-input')), '0000');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '1234');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();
    // The success cleared the counter (no residual lockout for the scope).
    final state = await limiter.stateFor('emp-1');
    expect(state.failedAttempts, 0);
  });

  testWidgets('RF-118: expiredNotice shows the "enter PIN again" prompt', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester, expiredNotice: true, onStart: (_, _) async => null);
    expect(find.text(l10n.pinSessionExpired), findsOneWidget);
  });
}
