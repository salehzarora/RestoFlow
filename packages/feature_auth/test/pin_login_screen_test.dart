import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _FakeStaff implements DeviceStaffRepository {
  _FakeStaff(this._result);
  final Result<List<DeviceStaffMember>, DeviceStaffFailure> _result;

  @override
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>>
  listStaff() async => _result;
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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: PinLoginScreen(staffRepository: staff, onStartSession: onStart),
    ),
  );
  await tester.pumpAndSettle();
}

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

  testWidgets('an empty staff list shows the honest empty state', (
    tester,
  ) async {
    await _pump(
      tester,
      staff: _FakeStaff(const Success([])),
      onStart: (_, _) async => null,
    );
    expect(find.text('No staff available'), findsOneWidget);
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
