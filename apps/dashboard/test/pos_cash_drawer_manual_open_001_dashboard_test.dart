import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/data/audit_action_registry.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_dashboard/src/staff/staff_models.dart';
import 'package:restoflow_dashboard/src/staff/staff_repository.dart';
import 'package:restoflow_dashboard/src/staff/staff_screen.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show RestoflowTone;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminResult, AdminScope;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// POS-CASH-DRAWER-MANUAL-OPEN-001 — the Dashboard side of the manual
/// ("no-sale") cash-drawer permission and its Activity Log trail.
///
/// The permission is GRANT-ONLY and DEFAULT-OFF (the full-comp polarity), and
/// the save path sends it ONLY when it changed, so a save that never touched
/// the drawer switch stays compatible with a server that predates it.
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

int _n = 0;
SupabaseStaffRepository _repo(_FakeTransport t, {int Function()? nonce}) =>
    SupabaseStaffRepository(
      transport: t,
      scope: AdminScope.demo,
      currentUserId: () => 'u',
      nonce: nonce ?? () => ++_n,
    );

/// A `list_staff` reply. [newServer] = false models a server that predates the
/// migration: it never returns the `open_cash_drawer` key and only has the
/// 8-arg `set_staff_capabilities`.
Map<String, Object?> _listStaff({bool drawer = false, bool newServer = true}) =>
    {
      'ok': true,
      'staff': [
        {
          'employee_profile_id': 'emp-1',
          'display_name': 'Cashier One',
          'role': 'cashier',
          'has_pin': true,
          'employment_status': 'active',
          'capabilities': {
            'apply_discount': true,
            'void_order': true,
            'close_shift': true,
            'apply_full_comp': false,
            'manage_menu_availability': true,
            'manage_table_operations': true,
            if (newServer) 'open_cash_drawer': drawer,
          },
        },
      ],
    };

Map<String, dynamic> _capsCall(_FakeTransport t) =>
    t.calls.lastWhere((c) => c.$1 == 'set_staff_capabilities').$2;

class _RecordingRepo implements StaffRepository {
  _RecordingRepo(this._staff);
  final List<StaffMember> _staff;
  final List<(String, StaffCapabilities)> capabilityCalls = [];
  final List<StaffCapabilities?> createCalls = [];

  @override
  Future<AdminResult<List<StaffMember>>> load() async => Success(_staff);

  @override
  Future<AdminResult<StaffMember>> create({
    required String displayName,
    required MembershipRole role,
    StaffCapabilities? capabilities,
    String? clientRequestId,
  }) async {
    createCalls.add(capabilities);
    return Success(
      StaffMember(
        employeeProfileId: 'new',
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

StaffMember _cashier({StaffCapabilities? caps}) => StaffMember(
  employeeProfileId: 'emp-c',
  displayName: 'Cashier One',
  role: MembershipRole.cashier,
  hasPin: true,
  employmentStatus: 'active',
  capabilities: caps ?? const StaffCapabilities(),
);

Future<void> _pump(
  WidgetTester tester,
  StaffRepository repo, {
  Locale locale = const Locale('en'),
  Size size = const Size(1400, 2400),
}) async {
  tester.view.physicalSize = size;
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

Future<void> _openEditDialog(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.tune).first);
  await tester.pumpAndSettle();
}

SwitchListTile _drawerSwitch(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.byKey(const Key('cap-open-cash-drawer')));

const _locales = [Locale('ar'), Locale('he'), Locale('en')];

void main() {
  // ===== A. Default-OFF parsing ===========================================
  group('A. the drawer permission is grant-only (default OFF)', () {
    test('A1 an ABSENT key (older server) parses as DENIED', () {
      expect(StaffCapabilities.fromJson(const {}).openCashDrawer, isFalse);
      expect(const StaffCapabilities().openCashDrawer, isFalse);
    });

    test('A2 only a real boolean true grants; junk values deny', () {
      expect(
        StaffCapabilities.fromJson(const {
          'open_cash_drawer': true,
        }).openCashDrawer,
        isTrue,
      );
      for (final junk in <Object?>['true', 1, null, 'yes', false]) {
        expect(
          StaffCapabilities.fromJson({'open_cash_drawer': junk}).openCashDrawer,
          isFalse,
          reason: 'malformed value $junk must never manufacture a grant',
        );
      }
    });

    test('A3 a fresh cashier without the drawer grant is still "all '
        'enabled" (it is not a deviation from the preset)', () {
      expect(const StaffCapabilities().allEnabled, isTrue);
      expect(const StaffCapabilities(openCashDrawer: true).allEnabled, isTrue);
    });
  });

  // ===== B. The wire payload ===============================================
  group('B. the RPC payload sends the drawer toggle only when it changed', () {
    test('B1 OLD server, unchanged since load -> p_open_cash_drawer is '
        'OMITTED (the 8-arg function still resolves)', () async {
      final t = _FakeTransport(
        (fn, _) =>
            fn == 'list_staff' ? _listStaff(newServer: false) : {'ok': true},
      );
      final repo = _repo(t);
      await repo.load();
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(applyDiscount: false),
      );
      final params = _capsCall(t);
      expect(
        params.containsKey('p_open_cash_drawer'),
        isFalse,
        reason: 'a save that never touched the drawer must not send it',
      );
      expect(params['p_apply_discount'], isFalse);
    });

    test('B2 a GRANT is sent explicitly', () async {
      final t = _FakeTransport(
        (fn, _) => fn == 'list_staff' ? _listStaff() : {'ok': true},
      );
      final repo = _repo(t);
      await repo.load();
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(openCashDrawer: true),
      );
      expect(_capsCall(t)['p_open_cash_drawer'], isTrue);
    });

    test('B3 a REVOKE is sent explicitly', () async {
      final t = _FakeTransport(
        (fn, _) => fn == 'list_staff' ? _listStaff(drawer: true) : {'ok': true},
      );
      final repo = _repo(t);
      await repo.load();
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(),
      );
      expect(_capsCall(t)['p_open_cash_drawer'], isFalse);
    });

    test('B4 unknown prior state (never loaded) -> sent explicitly', () async {
      final t = _FakeTransport((_, _) => {'ok': true});
      await _repo(t).setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(),
      );
      expect(_capsCall(t)['p_open_cash_drawer'], isFalse);
    });

    test('B5 OLD server: a successful save becomes the new baseline', () async {
      final t = _FakeTransport(
        (fn, _) =>
            fn == 'list_staff' ? _listStaff(newServer: false) : {'ok': true},
      );
      final repo = _repo(t);
      await repo.load();
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(openCashDrawer: true),
      );
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(
          openCashDrawer: true,
          voidOrder: false,
        ),
      );
      expect(_capsCall(t).containsKey('p_open_cash_drawer'), isFalse);
    });

    test('B6 OLD server: a FAILED save keeps the old baseline (the grant is '
        'resent)', () async {
      var fail = true;
      final t = _FakeTransport((fn, _) {
        if (fn == 'list_staff') return _listStaff(newServer: false);
        if (fail) {
          fail = false;
          return {'ok': false, 'error': 'permission_denied'};
        }
        return {'ok': true};
      });
      final repo = _repo(t);
      await repo.load();
      const granted = StaffCapabilities(openCashDrawer: true);
      final first = await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: granted,
      );
      expect(first, isA<Failure<void, Object>>());
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: granted,
      );
      expect(_capsCall(t)['p_open_cash_drawer'], isTrue);
    });

    test('B7 the request id changes when ONLY the drawer flips', () async {
      final t = _FakeTransport(
        (fn, _) => fn == 'list_staff' ? _listStaff() : {'ok': true},
      );
      // A FIXED nonce: the id can only differ through its input parts.
      final repo = _repo(t, nonce: () => 7);
      await repo.load();
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(openCashDrawer: true),
      );
      final grantId = _capsCall(t)['p_client_request_id'];
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(),
      );
      expect(_capsCall(t)['p_client_request_id'], isNot(grantId));
      expect(_capsCall(t)['p_open_cash_drawer'], isFalse);
    });

    test('B9 NEW server: the toggle is ALWAYS sent, exactly as shown — a '
        'stale baseline can neither drop nor invent a change', () async {
      final t = _FakeTransport(
        (fn, _) => fn == 'list_staff' ? _listStaff(drawer: true) : {'ok': true},
      );
      final repo = _repo(t);
      await repo.load();
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(openCashDrawer: true),
      );
      expect(
        _capsCall(t)['p_open_cash_drawer'],
        isTrue,
        reason: 'unchanged, but a new server always receives the value',
      );
      await repo.setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(),
      );
      expect(_capsCall(t)['p_open_cash_drawer'], isFalse);
    });

    test(
      'B10 once a reload shows the NEW server, the key is always sent',
      () async {
        var newServer = false;
        final t = _FakeTransport(
          (fn, _) => fn == 'list_staff'
              ? _listStaff(newServer: newServer)
              : {'ok': true},
        );
        final repo = _repo(t);
        await repo.load();
        await repo.setCapabilities(
          employeeProfileId: 'emp-1',
          capabilities: const StaffCapabilities(),
        );
        expect(_capsCall(t).containsKey('p_open_cash_drawer'), isFalse);
        newServer = true; // the migration lands
        await repo.load();
        await repo.setCapabilities(
          employeeProfileId: 'emp-1',
          capabilities: const StaffCapabilities(),
        );
        expect(_capsCall(t)['p_open_cash_drawer'], isFalse);
      },
    );

    test('B8 create sends ONLY a grant, never a deny', () async {
      final t = _FakeTransport(
        (_, _) => {'ok': true, 'employee_profile_id': 'e'},
      );
      await _repo(t).create(
        displayName: 'C',
        role: MembershipRole.cashier,
        capabilities: const StaffCapabilities(openCashDrawer: true),
      );
      final caps = t.calls.single.$2['p_capabilities'] as Map<String, dynamic>;
      expect(caps['open_cash_drawer'], 'true');

      final t2 = _FakeTransport(
        (_, _) => {'ok': true, 'employee_profile_id': 'e'},
      );
      await _repo(t2).create(
        displayName: 'C',
        role: MembershipRole.cashier,
        capabilities: const StaffCapabilities(),
      );
      expect(
        t2.calls.single.$2.containsKey('p_capabilities'),
        isFalse,
        reason: 'no grant -> no key -> the legacy create fingerprint holds',
      );
    });
  });

  // ===== C. The staff permission UI =======================================
  group('C. the staff permission switch', () {
    testWidgets('C1 defaults OFF for a cashier', (tester) async {
      await _pump(tester, _RecordingRepo([_cashier()]));
      await _openEditDialog(tester);
      expect(_drawerSwitch(tester).value, isFalse);
      expect(_drawerSwitch(tester).onChanged, isNotNull);
    });

    testWidgets('C2 a granted cashier shows ON', (tester) async {
      await _pump(
        tester,
        _RecordingRepo([
          _cashier(caps: const StaffCapabilities(openCashDrawer: true)),
        ]),
      );
      await _openEditDialog(tester);
      expect(_drawerSwitch(tester).value, isTrue);
    });

    testWidgets('C3 a grant PERSISTS through the repository', (tester) async {
      final repo = _RecordingRepo([_cashier()]);
      await _pump(tester, repo);
      await _openEditDialog(tester);
      await tester.ensureVisible(find.byKey(const Key('cap-open-cash-drawer')));
      await tester.tap(find.byKey(const Key('cap-open-cash-drawer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.capabilityCalls, hasLength(1));
      final saved = repo.capabilityCalls.single.$2;
      expect(saved.openCashDrawer, isTrue);
      expect(saved.applyFullComp, isFalse, reason: 'no other right changed');
    });

    for (final locale in _locales) {
      testWidgets('C4 renders in ${locale.languageCode} with a real label', (
        tester,
      ) async {
        await _pump(tester, _RecordingRepo([_cashier()]), locale: locale);
        await _openEditDialog(tester);
        final l10n = await AppLocalizations.delegate.load(locale);
        expect(l10n.staffCapOpenCashDrawer, isNot('staffCapOpenCashDrawer'));
        expect(find.text(l10n.staffCapOpenCashDrawer), findsOneWidget);
        expect(find.text(l10n.staffCapOpenCashDrawerHint), findsOneWidget);
      });
    }

    // A 1366x768 laptop browser leaves ~625 logical px of viewport. Before
    // the dialogs scrolled, the extra switch overflowed here and sat below
    // the dialog's own buttons, out of reach.
    const laptop = Size(1366, 625);

    testWidgets('C5 EDIT dialog on a short laptop viewport: no overflow, the '
        'switch is reachable and the grant persists', (tester) async {
      final repo = _RecordingRepo([_cashier()]);
      await _pump(tester, repo, size: laptop);
      await _openEditDialog(tester);
      expect(tester.takeException(), isNull);
      final sw = find.byKey(const Key('cap-open-cash-drawer'));
      await tester.ensureVisible(sw);
      await tester.pumpAndSettle();
      await tester.tap(sw);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.capabilityCalls.single.$2.openCashDrawer, isTrue);
    });

    testWidgets('C6 CREATE dialog on a short laptop viewport: the drawer can '
        'be granted at creation', (tester) async {
      final repo = _RecordingRepo([]);
      await _pump(tester, repo, size: laptop);
      await tester.tap(find.text('Add staff member'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextFormField).first, 'New Cashier');
      // Let the field's own scroll-into-view settle before scrolling down.
      await tester.pumpAndSettle();
      final sw = find.byKey(const Key('cap-open-cash-drawer'));
      await tester.ensureVisible(sw);
      await tester.pumpAndSettle();
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(_drawerSwitch(tester).value, isTrue);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.createCalls.single?.openCashDrawer, isTrue);
    });
  });

  // ===== D. The Activity Log ==============================================
  group('D. the Activity Log', () {
    AuditEventView view(AppLocalizations l10n, AuditEvent e) =>
        AuditEventPresenter(l10n, 'ILS').present(e);

    test('D1 the registry contracts all three actions to Shifts, titled', () {
      for (final a in const [
        'cash_drawer.no_sale_opened',
        'cash_drawer.no_sale_denied',
        'cash_drawer.unlock_failed',
      ]) {
        expect(kAuditActionRegistry[a]?.category, 'shifts', reason: a);
        expect(kAuditActionRegistry[a]?.hasTitle, isTrue, reason: a);
      }
    });

    for (final locale in _locales) {
      testWidgets('D2 each action has its own title in '
          '${locale.languageCode}, never Other', (tester) async {
        final l10n = await AppLocalizations.delegate.load(locale);
        AuditEvent ev(String action, Map<String, Object?> nv) => AuditEvent(
          eventId: action,
          action: action,
          category: 'shifts',
          occurredAtLabel: '2026-10-06 10:00',
          newValues: nv,
        );

        final opened = view(
          l10n,
          ev('cash_drawer.no_sale_opened', {'role': 'cashier'}),
        );
        expect(opened.title, l10n.activityLogTitleDrawerNoSaleOpened);
        expect(opened.categoryLabel, l10n.activityLogCategoryShifts);
        expect(opened.isKnownAction, isTrue);
        expect(opened.isDenied, isFalse);

        final denied = view(
          l10n,
          ev('cash_drawer.no_sale_denied', {
            'role': 'cashier',
            'denied_reason': 'permission_denied',
          }),
        );
        expect(denied.title, l10n.activityLogTitleDrawerNoSaleDenied);
        expect(denied.isDenied, isTrue);
        expect(
          denied.changes.map((c) => c.newValue),
          contains(l10n.activityLogDeniedPermission),
          reason: 'WHY it was refused, localized — never the raw token',
        );

        final failed = view(
          l10n,
          ev('cash_drawer.unlock_failed', {
            'role': 'cashier',
            'failed_attempt_count': 2,
            'locked': false,
          }),
        );
        expect(failed.title, l10n.activityLogTitleDrawerUnlockFailed);
        expect(
          failed.changes.map((c) => c.label),
          containsAll([
            l10n.activityLogFieldFailedAttempts,
            l10n.activityLogFieldLocked,
          ]),
        );
      });
    }

    testWidgets('D5 a late (offline) open says so; a wrong PIN reads as a '
        'warning', (tester) async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await AppLocalizations.delegate.load(Locale(code));
        final late = view(
          l10n,
          const AuditEvent(
            eventId: 'late',
            action: 'cash_drawer.no_sale_opened',
            category: 'shifts',
            occurredAtLabel: '2026-10-06 12:00',
            newValues: {'role': 'cashier', 'recorded_offline': true},
          ),
        );
        expect(
          late.changes.map((c) => c.label),
          contains(l10n.activityLogFieldRecordedOffline),
          reason: code,
        );
        expect(
          l10n.activityLogFieldRecordedOffline,
          isNot('activityLogFieldRecordedOffline'),
        );
        final failed = view(
          l10n,
          const AuditEvent(
            eventId: 'f',
            action: 'cash_drawer.unlock_failed',
            category: 'shifts',
            occurredAtLabel: '2026-10-06 12:00',
            newValues: {'failed_attempt_count': 3, 'locked': false},
          ),
        );
        expect(failed.tone, RestoflowTone.warning, reason: code);
      }
    });

    testWidgets('D3 internal ids in the payload never render', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final v = view(
        l10n,
        const AuditEvent(
          eventId: 'e',
          action: 'cash_drawer.no_sale_opened',
          category: 'shifts',
          occurredAtLabel: '2026-10-06 10:00',
          newValues: {
            'role': 'cashier',
            'shift_id': 'SHIFT-UUID',
            'cash_drawer_session_id': 'DRAWER-UUID',
            'resolved_membership_id': 'MEMBERSHIP-UUID',
            'client_occurred_at': '2026-10-06T10:00:00Z',
          },
        ),
      );
      final rendered = v.changes.map((c) => '${c.oldValue} ${c.newValue}');
      for (final leak in ['SHIFT-UUID', 'DRAWER-UUID', 'MEMBERSHIP-UUID']) {
        expect(rendered.any((s) => s.contains(leak)), isFalse, reason: leak);
      }
    });

    for (final locale in _locales) {
      testWidgets('D4 granting the permission is a labelled before→after row '
          'in ${locale.languageCode}', (tester) async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final v = view(
          l10n,
          const AuditEvent(
            eventId: 'caps',
            action: 'staff.capabilities_updated',
            category: 'staff',
            occurredAtLabel: '2026-10-06 10:00',
            oldValues: {
              'capabilities': {'open_cash_drawer': false},
            },
            newValues: {
              'capabilities': {'open_cash_drawer': true},
            },
          ),
        );
        expect(
          l10n.activityLogCapOpenCashDrawer,
          isNot('activityLogCapOpenCashDrawer'),
        );
        final row = v.changes.firstWhere(
          (c) => c.label == l10n.activityLogCapOpenCashDrawer,
        );
        expect(row.oldValue, isNotNull);
        expect(row.oldValue, isNot(row.newValue));
      });
    }
  });
}
