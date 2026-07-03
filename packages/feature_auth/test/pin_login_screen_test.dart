import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _FakeStaff implements DeviceStaffRepository {
  _FakeStaff(this._result);
  final Result<List<DeviceStaffMember>, DeviceStaffFailure> _result;
  int listCalls = 0;

  @override
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>>
  listStaff() async {
    listCalls++;
    return _result;
  }
}

const _staff = [
  DeviceStaffMember(
    employeeProfileId: 'emp-1',
    displayName: 'Amira K.',
    role: 'cashier',
  ),
  DeviceStaffMember(
    employeeProfileId: 'emp-2',
    displayName: 'Yosef L.',
    role: 'kitchen_staff',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required DeviceStaffRepository staff,
  required Future<PinLoginError?> Function(String, String) onStart,
  AppSurface? surface,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: PinLoginScreen(
        staffRepository: staff,
        onStartSession: onStart,
        surface: surface,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('lists staff, signs in with a correct PIN', (tester) async {
    String? gotEmployee;
    String? gotPin;
    await _pump(
      tester,
      staff: _FakeStaff(const Success(_staff)),
      onStart: (employeeProfileId, pin) async {
        gotEmployee = employeeProfileId;
        gotPin = pin;
        return null; // success
      },
    );
    expect(find.text('Amira K.'), findsOneWidget);
    expect(find.text('Yosef L.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pin-staff-emp-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '1234');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();

    expect(gotEmployee, 'emp-1');
    expect(gotPin, '1234');
  });

  testWidgets('the on-screen keypad feeds the same PIN field (digits + '
      'backspace), and the field stays enterText-compatible', (tester) async {
    String? gotPin;
    await _pump(
      tester,
      staff: _FakeStaff(const Success(_staff)),
      onStart: (_, pin) async {
        gotPin = pin;
        return null;
      },
    );
    await tester.tap(find.byKey(const Key('pin-staff-emp-1')));
    await tester.pumpAndSettle();

    // Keypad taps append to the field; backspace removes the last digit.
    for (final d in ['1', '2', '3', '9']) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('keypad-backspace')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('pin-input')))
          .controller!
          .text,
      '123',
    );

    // The field itself is still directly editable (single source of truth).
    await tester.enterText(find.byKey(const Key('pin-input')), '1234');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();
    expect(gotPin, '1234');
  });

  testWidgets('a wrong PIN shows the safe error and stays on the pad', (
    tester,
  ) async {
    await _pump(
      tester,
      staff: _FakeStaff(const Success(_staff)),
      onStart: (_, _) async => PinLoginError.wrongPin,
    );
    await tester.tap(find.byKey(const Key('pin-staff-emp-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '9999');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Wrong PIN — try again.'), findsOneWidget);
    expect(find.byKey(const Key('pin-input')), findsOneWidget);
  });

  testWidgets('a lockout shows the lockout message', (tester) async {
    await _pump(
      tester,
      staff: _FakeStaff(const Success(_staff)),
      onStart: (_, _) async => PinLoginError.locked,
    );
    await tester.tap(find.byKey(const Key('pin-staff-emp-2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '1234');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('Too many attempts. This sign-in is temporarily locked.'),
      findsOneWidget,
    );
  });

  group('no-staff guidance (sprint UX fix)', () {
    testWidgets('POS: action-oriented title, cashier wording, setup steps, '
        'and Try again refreshes the list', (tester) async {
      final l10n = await _en();
      final staff = _FakeStaff(const Success([]));
      await _pump(
        tester,
        staff: staff,
        onStart: (_, _) async => fail('no sign-in without staff'),
        surface: AppSurface.pos,
      );

      expect(find.text(l10n.pinLoginEmptyTitle), findsOneWidget);
      expect(find.text('No staff PINs yet'), findsOneWidget);
      // POS wording: cashier/manager + the Dashboard -> Staff path.
      expect(find.text(l10n.pinLoginEmptyBodyPos), findsOneWidget);
      expect(find.textContaining('cashier'), findsOneWidget);
      expect(find.textContaining('Dashboard'), findsWidgets);
      // The numbered setup steps.
      expect(find.text(l10n.pinLoginStepsTitle), findsOneWidget);
      expect(find.text(l10n.pinLoginStep1), findsOneWidget);
      expect(find.text(l10n.pinLoginStep5), findsOneWidget);
      // Never the misleading account denial, never fake staff.
      expect(find.text(l10n.authAccessDenied), findsNothing);
      expect(find.byKey(const Key('pin-input')), findsNothing);

      // Try again re-queries the token-proven staff directory.
      expect(staff.listCalls, 1);
      await tester.tap(find.text(l10n.authTryAgain));
      await tester.pumpAndSettle();
      expect(staff.listCalls, 2);
    });

    testWidgets('KDS: kitchen wording, steps, and still money-free (T-003)', (
      tester,
    ) async {
      final l10n = await _en();
      await _pump(
        tester,
        staff: _FakeStaff(const Success([])),
        onStart: (_, _) async => fail('no sign-in without staff'),
        surface: AppSurface.kds,
      );

      expect(find.text(l10n.pinLoginEmptyTitle), findsOneWidget);
      expect(find.text(l10n.pinLoginEmptyBodyKds), findsOneWidget);
      expect(find.textContaining('kitchen staff'), findsOneWidget);
      expect(find.text(l10n.pinLoginStepsTitle), findsOneWidget);
      // The kitchen no-staff state exposes no money (SECURITY T-003).
      expect(find.textContaining('₪'), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('no surface given: the generic fallback body', (tester) async {
      final l10n = await _en();
      await _pump(
        tester,
        staff: _FakeStaff(const Success([])),
        onStart: (_, _) async => null,
      );
      expect(find.text(l10n.pinLoginEmptyTitle), findsOneWidget);
      expect(find.text(l10n.pinLoginEmptyBody), findsOneWidget);
    });
  });

  testWidgets('an invalid device session shows the re-pair message', (
    tester,
  ) async {
    await _pump(
      tester,
      staff: _FakeStaff(const Failure(DeviceStaffFailure.invalidSession)),
      onStart: (_, _) async => null,
    );
    expect(find.textContaining('Pair the device again'), findsOneWidget);
  });

  testWidgets('the PIN screen is money-free (kitchen-safe, T-003)', (
    tester,
  ) async {
    await _pump(
      tester,
      staff: _FakeStaff(const Success(_staff)),
      onStart: (_, _) async => null,
    );
    expect(find.textContaining('₪'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });
}
