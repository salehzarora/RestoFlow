import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/staff/staff_repository.dart';
import 'package:restoflow_dashboard/src/staff/staff_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminPermissionDenied, AdminScope, AdminValidation;
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

void main() {
  group('SupabaseStaffRepository', () {
    test('load parses staff rows (has_pin flag only, never a ref)', () async {
      final t = _FakeTransport(
        (fn, p) => {
          'ok': true,
          'staff': [
            {
              'employee_profile_id': 'emp-1',
              'display_name': 'Amira K.',
              'role': 'cashier',
              'employment_status': 'active',
              'has_pin': true,
            },
            {
              'employee_profile_id': 'emp-2',
              'display_name': 'Yosef L.',
              'role': 'kitchen_staff',
              'employment_status': 'active',
              'has_pin': false,
            },
          ],
        },
      );
      final repo = SupabaseStaffRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final staff = (await repo.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(t.calls.single.$1, 'list_staff');
      expect(staff, hasLength(2));
      expect(staff.first.hasPin, isTrue);
      expect(staff.last.role, MembershipRole.kitchenStaff);
    });

    test('create sends the wire role + branch scope', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': true, 'employee_profile_id': 'emp-3'},
      );
      final repo = SupabaseStaffRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final created = (await repo.create(
        displayName: 'New Cashier',
        role: MembershipRole.cashier,
      )).fold((s) => s, (f) => fail('expected success'));
      expect(created.employeeProfileId, 'emp-3');
      final params = t.calls.single.$2;
      expect(t.calls.single.$1, 'create_staff_member');
      expect(params['p_role'], 'cashier');
      expect(params['p_branch_id'], AdminScope.demo.branchId);
    });

    test('owner roles cannot be provisioned from this surface', () async {
      final t = _FakeTransport((fn, p) => fail('no backend call'));
      final repo = SupabaseStaffRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final result = await repo.create(
        displayName: 'X',
        role: MembershipRole.orgOwner,
      );
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminValidation>()),
      );
      expect(t.calls, isEmpty);
    });

    test(
      'setPin sends the PIN over the transport, never in the request id',
      () async {
        final t = _FakeTransport(
          (fn, p) => {'ok': true, 'employee_profile_id': 'emp-1'},
        );
        final repo = SupabaseStaffRepository(
          transport: t,
          scope: AdminScope.demo,
          currentUserId: () => 'u',
        );
        final result = await repo.setPin(
          employeeProfileId: 'emp-1',
          pin: '4321',
        );
        expect(result.isSuccess, isTrue);
        final params = t.calls.single.$2;
        expect(t.calls.single.$1, 'set_employee_pin');
        expect(params['p_pin'], '4321');
        // The idempotency key never embeds the raw PIN.
        expect('${params['p_client_request_id']}'.contains('4321'), isFalse);
      },
    );

    test('a malformed PIN fails closed without a backend call', () async {
      final t = _FakeTransport((fn, p) => fail('no backend call'));
      final repo = SupabaseStaffRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final result = await repo.setPin(employeeProfileId: 'emp-1', pin: '12');
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminValidation>()),
      );
      expect(t.calls, isEmpty);
    });

    test('permission_denied maps to a typed failure', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': false, 'error': 'permission_denied'},
      );
      final repo = SupabaseStaffRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final result = await repo.load();
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminPermissionDenied>()),
      );
    });
  });

  group('StaffScreen', () {
    Future<void> pump(WidgetTester tester, StaffRepository repo) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(body: StaffScreen(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders staff with PIN pills + the no-PIN warning', (
      tester,
    ) async {
      await pump(tester, InMemoryStaffStore());
      expect(find.text('Amira K.'), findsOneWidget);
      expect(find.text('PIN set'), findsOneWidget);
      expect(find.text('No PIN'), findsOneWidget);
      // Yosef has no PIN -> the order-loop warning shows.
      expect(
        find.text("Staff without a PIN can't sign in on POS/KDS."),
        findsOneWidget,
      );
    });

    testWidgets('adds a staff member through the dialog', (tester) async {
      final store = InMemoryStaffStore();
      await pump(tester, store);
      await tester.tap(find.text('Add staff member'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Nadia B.',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Nadia B.'), findsOneWidget);
    });

    testWidgets('sets a PIN through the obscured dialog (never echoed)', (
      tester,
    ) async {
      final store = InMemoryStaffStore();
      await pump(tester, store);
      // Yosef (demo-staff-2) has no PIN.
      await tester.tap(find.text('Set PIN').first);
      await tester.pumpAndSettle();
      expect(find.text('Set sign-in PIN'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'PIN (4–8 digits)'),
        '2468',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm PIN'),
        '2468',
      );
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      // The PIN itself never appears in the UI; the flag flips to set.
      expect(find.text('2468'), findsNothing);
      expect(find.text('PIN set'), findsNWidgets(2));
      final staff = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(staff.every((s) => s.hasPin), isTrue);
    });

    testWidgets('mismatched PIN confirmation blocks the save', (tester) async {
      await pump(tester, InMemoryStaffStore());
      await tester.tap(find.text('Set PIN').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'PIN (4–8 digits)'),
        '2468',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm PIN'),
        '8642',
      );
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(find.text("PINs don't match"), findsOneWidget);
    });
  });
}
