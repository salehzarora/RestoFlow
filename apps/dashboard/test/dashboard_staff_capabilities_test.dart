import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/staff/staff_models.dart';
import 'package:restoflow_dashboard/src/staff/staff_repository.dart';
import 'package:restoflow_dashboard/src/staff/staff_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show
        AdminPermissionDenied,
        AdminResult,
        AdminScope,
        AdminTransient,
        adminRoleLabel;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// STAFF-CASHIER-PERMISSIONS-001: the dashboard cashier-capability switches
/// (default-ON in the create form + an edit dialog on the card) and the
/// set_staff_capabilities write path. The backend is the authoritative gate;
/// these tests cover the presentation + the exact RPC payload.
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

SupabaseStaffRepository _repo(_FakeTransport t) => SupabaseStaffRepository(
  transport: t,
  scope: AdminScope.demo,
  currentUserId: () => 'u',
);

/// A repo that serves a fixed staff list and records create + setCapabilities
/// calls (STAFF-CASHIER-PERMISSIONS-001: creation is now a single atomic call
/// carrying the initial capabilities — no separate setCapabilities on create).
class _RecordingRepo implements StaffRepository {
  _RecordingRepo(this._staff, {this.createFails = false});
  final List<StaffMember> _staff;
  bool createFails;
  final List<(String, MembershipRole, StaffCapabilities?)> createCalls = [];
  final List<String?> createRequestIds = [];
  final List<(String, StaffCapabilities)> capabilityCalls = [];

  @override
  Future<AdminResult<List<StaffMember>>> load() async => Success(_staff);

  @override
  Future<AdminResult<StaffMember>> create({
    required String displayName,
    required MembershipRole role,
    StaffCapabilities? capabilities,
    String? clientRequestId,
  }) async {
    createCalls.add((displayName, role, capabilities));
    createRequestIds.add(clientRequestId);
    if (createFails) return const Failure(AdminTransient());
    return Success(
      StaffMember(
        employeeProfileId: 'new-emp',
        displayName: displayName,
        role: role,
        hasPin: false,
        employmentStatus: 'active',
        capabilities: capabilities,
      ),
    );
  }

  @override
  Future<AdminResult<void>> setPin({
    required String employeeProfileId,
    required String pin,
  }) async => const Success(null);

  @override
  Future<AdminResult<void>> setCapabilities({
    required String employeeProfileId,
    required StaffCapabilities capabilities,
  }) async {
    capabilityCalls.add((employeeProfileId, capabilities));
    return const Success(null);
  }
}

Future<void> _pump(
  WidgetTester tester,
  StaffRepository repo, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(body: StaffScreen(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

StaffMember _cashier({
  String id = 'emp-c',
  String name = 'Cashier One',
  StaffCapabilities? caps,
}) => StaffMember(
  employeeProfileId: id,
  displayName: name,
  role: MembershipRole.cashier,
  hasPin: true,
  employmentStatus: 'active',
  capabilities: caps ?? const StaffCapabilities(),
);

void main() {
  group('SupabaseStaffRepository.setCapabilities', () {
    test(
      'sends set_staff_capabilities with the three boolean states',
      () async {
        final t = _FakeTransport((fn, p) => {'ok': true});
        await _repo(t).setCapabilities(
          employeeProfileId: 'emp-9',
          capabilities: const StaffCapabilities(voidOrder: false),
        );
        expect(t.calls.single.$1, 'set_staff_capabilities');
        final p = t.calls.single.$2;
        expect(p['p_employee_profile_id'], 'emp-9');
        expect(p['p_apply_discount'], true);
        expect(p['p_void_order'], false);
        expect(p['p_close_shift'], true);
        // Never any money / PIN material in the payload.
        expect(p.keys.where((k) => '$k'.contains('minor')), isEmpty);
      },
    );

    test(
      'PILOT-OPERATIONS-CORRECTIONS-001: sends the two new operational '
      'capability booleans (default ON; a deny is false)',
      () async {
        final t = _FakeTransport((fn, p) => {'ok': true});
        await _repo(t).setCapabilities(
          employeeProfileId: 'emp-9',
          capabilities: const StaffCapabilities(manageTableOperations: false),
        );
        final p = t.calls.single.$2;
        expect(p['p_manage_menu_availability'], true); // default ON
        expect(p['p_manage_table_operations'], false); // explicitly denied
      },
    );

    test('maps permission_denied to AdminPermissionDenied', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': false, 'error': 'permission_denied'},
      );
      final r = await _repo(t).setCapabilities(
        employeeProfileId: 'emp-9',
        capabilities: const StaffCapabilities(),
      );
      r.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<AdminPermissionDenied>()),
      );
    });

    test('load parses the capabilities object (deny reflected)', () async {
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
              'capabilities': {
                'apply_discount': true,
                'void_order': false,
                'close_shift': true,
              },
            },
          ],
        },
      );
      final staff = (await _repo(
        t,
      ).load()).fold((s) => s, (f) => fail('want ok'));
      final caps = staff.single.capabilities!;
      expect(caps.applyDiscount, isTrue);
      expect(caps.voidOrder, isFalse);
      expect(caps.closeShift, isTrue);
    });

    test(
      'create sends deny-only p_capabilities (atomic) for OFF switches',
      () async {
        final t = _FakeTransport(
          (fn, p) => {'ok': true, 'employee_profile_id': 'e'},
        );
        await SupabaseStaffRepository(
          transport: t,
          scope: AdminScope.demo,
          currentUserId: () => 'u',
        ).create(
          displayName: 'C',
          role: MembershipRole.cashier,
          capabilities: const StaffCapabilities(
            voidOrder: false,
            closeShift: false,
          ),
        );
        expect(t.calls.single.$1, 'create_staff_member');
        // One RPC; the initial denies ride along atomically (no second call).
        expect(t.calls, hasLength(1));
        expect(t.calls.single.$2['p_capabilities'], {
          'void_order': 'false',
          'close_shift': 'false',
        });
      },
    );

    test('create sends NULL p_capabilities when all switches are ON', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': true, 'employee_profile_id': 'e'},
      );
      await SupabaseStaffRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      ).create(
        displayName: 'C',
        role: MembershipRole.cashier,
        capabilities: const StaffCapabilities(),
      );
      expect(t.calls.single.$2['p_capabilities'], isNull);
    });

    test('create never sends capabilities for a non-cashier role', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': true, 'employee_profile_id': 'e'},
      );
      await SupabaseStaffRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      ).create(
        displayName: 'K',
        role: MembershipRole.kitchenStaff,
        capabilities: const StaffCapabilities(voidOrder: false),
      );
      expect(t.calls.single.$2['p_capabilities'], isNull);
    });
  });

  group('StaffScreen — create dialog capability switches', () {
    testWidgets('a new cashier shows all three switches ON by default', (
      tester,
    ) async {
      await _pump(tester, _RecordingRepo([]));
      await tester.tap(find.text('Add staff member'));
      await tester.pumpAndSettle();
      // Default role is cashier -> the three switches are present and ON.
      expect(find.byKey(const Key('cap-apply-discount')), findsOneWidget);
      expect(_switchValue(tester, 'cap-apply-discount'), isTrue);
      expect(_switchValue(tester, 'cap-void-order'), isTrue);
      expect(_switchValue(tester, 'cap-close-shift'), isTrue);
    });

    testWidgets('switching the role to a non-cashier hides the switches', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(tester, _RecordingRepo([]));
      await tester.tap(find.text('Add staff member'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cap-void-order')), findsOneWidget);
      // Pick "Kitchen staff" from the role dropdown.
      await tester.tap(find.byType(DropdownButtonFormField<MembershipRole>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(adminRoleLabel(l10n, MembershipRole.kitchenStaff)).last,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cap-void-order')), findsNothing);
    });

    testWidgets(
      'creating a cashier with a switch OFF passes the deny to the ATOMIC '
      'create — no separate setCapabilities call',
      (tester) async {
        final repo = _RecordingRepo([]);
        await _pump(tester, repo);
        await tester.tap(find.text('Add staff member'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Display name'),
          'Nadia B.',
        );
        // Turn OFF "Can cancel unpaid orders".
        await tester.tap(find.byKey(const Key('cap-void-order')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        // Exactly ONE create carrying the deny; NO fail-open create-then-set.
        expect(repo.createCalls, hasLength(1));
        final (name, role, caps) = repo.createCalls.single;
        expect(name, 'Nadia B.');
        expect(role, MembershipRole.cashier);
        expect(caps!.voidOrder, isFalse);
        expect(caps.applyDiscount, isTrue);
        expect(caps.closeShift, isTrue);
        expect(repo.capabilityCalls, isEmpty);
      },
    );

    testWidgets(
      'creating an all-default cashier passes all-enabled capabilities in one '
      'create; no setCapabilities',
      (tester) async {
        final repo = _RecordingRepo([]);
        await _pump(tester, repo);
        await tester.tap(find.text('Add staff member'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Display name'),
          'Sara Q.',
        );
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        expect(repo.createCalls, hasLength(1));
        expect(repo.createCalls.single.$3!.allEnabled, isTrue);
        expect(repo.capabilityCalls, isEmpty);
      },
    );

    testWidgets('a double tap on Create does not create duplicate staff', (
      tester,
    ) async {
      final repo = _RecordingRepo([]);
      await _pump(tester, repo);
      await tester.tap(find.text('Add staff member'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Rapid R.',
      );
      // Two taps before the frame settles -> the _busy guard admits one.
      await tester.tap(find.text('Create'));
      await tester.tap(find.text('Create'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.createCalls, hasLength(1));
    });

    testWidgets(
      'a failed create keeps the dialog open, shows an error, preserves inputs, '
      'adds no staff row',
      (tester) async {
        final repo = _RecordingRepo([], createFails: true);
        await _pump(tester, repo);
        await tester.tap(find.text('Add staff member'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Display name'),
          'Fails F.',
        );
        await tester.tap(find.byKey(const Key('cap-void-order')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        // One atomic attempt; NO separate capability write.
        expect(repo.createCalls, hasLength(1));
        expect(repo.capabilityCalls, isEmpty);
        // The dialog stays OPEN with a localized error; inputs + switch preserved.
        expect(find.byKey(const Key('create-staff-error')), findsOneWidget);
        expect(find.text('Create'), findsOneWidget);
        expect(_switchValue(tester, 'cap-void-order'), isFalse);
        expect(find.widgetWithText(TextFormField, 'Fails F.'), findsOneWidget);
      },
    );

    testWidgets(
      'an ambiguous retry of the SAME inputs reuses the request id (no dup); '
      'success then pops',
      (tester) async {
        final repo = _RecordingRepo([], createFails: true);
        await _pump(tester, repo);
        await tester.tap(find.text('Add staff member'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Display name'),
          'Retry R.',
        );
        await tester.tap(find.text('Create')); // attempt 1 -> transient failure
        await tester.pumpAndSettle();
        repo.createFails = false; // the server actually succeeded / recovers
        await tester.tap(find.text('Create')); // attempt 2, UNCHANGED inputs
        await tester.pumpAndSettle();

        expect(repo.createCalls, hasLength(2));
        // SAME stable client_request_id across the unchanged retry (idempotent).
        expect(repo.createRequestIds[0], isNotNull);
        expect(repo.createRequestIds[0], repo.createRequestIds[1]);
        // Success on attempt 2 -> the dialog closed.
        expect(find.byKey(const Key('create-staff-error')), findsNothing);
        expect(find.text('Create'), findsNothing);
      },
    );

    testWidgets('changing inputs after a failure mints a NEW request id', (
      tester,
    ) async {
      final repo = _RecordingRepo([], createFails: true);
      await _pump(tester, repo);
      await tester.tap(find.text('Add staff member'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Alice',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      // Change the name, then retry -> a NEW intent id (not reused with new input).
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Alice'),
        'Bob',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(repo.createCalls, hasLength(2));
      expect(repo.createRequestIds[0], isNot(repo.createRequestIds[1]));
    });
  });

  group('StaffScreen — edit capabilities', () {
    testWidgets(
      'the edit dialog shows effective values (a denied capability is OFF)',
      (tester) async {
        final repo = _RecordingRepo([
          _cashier(caps: const StaffCapabilities(applyDiscount: false)),
        ]);
        await _pump(tester, repo);
        await tester.tap(find.byKey(const Key('staff-capabilities-emp-c')));
        await tester.pumpAndSettle();
        // apply_discount was denied -> OFF; the other two -> ON.
        expect(_switchValue(tester, 'cap-apply-discount'), isFalse);
        expect(_switchValue(tester, 'cap-void-order'), isTrue);
        expect(_switchValue(tester, 'cap-close-shift'), isTrue);
      },
    );

    testWidgets('saving the edit dialog calls setCapabilities once', (
      tester,
    ) async {
      final repo = _RecordingRepo([_cashier()]);
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('staff-capabilities-emp-c')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cap-close-shift'))); // turn OFF
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('capabilities-save-button')));
      await tester.pumpAndSettle();

      expect(repo.capabilityCalls, hasLength(1));
      expect(repo.capabilityCalls.single.$2.closeShift, isFalse);
    });

    testWidgets('a non-cashier staff card has NO capabilities action', (
      tester,
    ) async {
      final repo = _RecordingRepo([
        const StaffMember(
          employeeProfileId: 'emp-k',
          displayName: 'Kitchen One',
          role: MembershipRole.kitchenStaff,
          hasPin: true,
          employmentStatus: 'active',
        ),
      ]);
      await _pump(tester, repo);
      expect(find.byKey(const Key('staff-capabilities-emp-k')), findsNothing);
    });

    testWidgets('renders the switches in Arabic (RTL) without overflow', (
      tester,
    ) async {
      final repo = _RecordingRepo([_cashier()]);
      await _pump(tester, repo, locale: const Locale('ar'));
      await tester.tap(find.byKey(const Key('staff-capabilities-emp-c')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cap-void-order')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
