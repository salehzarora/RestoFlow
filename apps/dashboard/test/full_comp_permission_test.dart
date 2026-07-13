import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_dashboard/src/staff/staff_models.dart';
import 'package:restoflow_dashboard/src/staff/staff_repository.dart';
import 'package:restoflow_dashboard/src/staff/staff_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminResult, AdminScope;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// FULL-COMP-PERMISSION-001 — the Dashboard side of the SEPARATE "make an order
/// free" staff permission.
///
/// The permission is DEFAULT-OFF and GRANT-only, the exact inverse of the three
/// existing default-ON/deny-only capabilities. Every test here exists because
/// getting that inversion wrong renders an un-granted cashier as *allowed to give
/// food away* — so the parsing, the wire payload, and the UI are each pinned.
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

class _RecordingRepo implements StaffRepository {
  _RecordingRepo(this._staff);
  final List<StaffMember> _staff;
  final List<(String, MembershipRole, StaffCapabilities?)> createCalls = [];
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

SwitchListTile _switch(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(Key(key)));

Future<void> _openEditDialog(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.tune).first);
  await tester.pumpAndSettle();
}

void main() {
  // ===== A. The model's INVERTED polarity ==================================
  group('A. default-OFF parsing (the inversion that must not be got wrong)', () {
    test('A1 an ABSENT apply_full_comp key parses as DENIED', () {
      // The other three default to ON when absent. This one must NOT.
      final caps = StaffCapabilities.fromJson(const {});
      expect(caps.applyDiscount, isTrue, reason: 'default-ON key');
      expect(caps.voidOrder, isTrue, reason: 'default-ON key');
      expect(caps.closeShift, isTrue, reason: 'default-ON key');
      expect(
        caps.applyFullComp,
        isFalse,
        reason: 'default-OFF: absence must DENY, never grant',
      );
    });

    test('A2 an OLD server that never sends the field fails closed', () {
      final caps = StaffCapabilities.fromJson(const {
        'apply_discount': true,
        'void_order': true,
        'close_shift': true,
      });
      expect(caps.applyFullComp, isFalse);
    });

    test('A3 only a real boolean true grants; junk values deny', () {
      expect(
        StaffCapabilities.fromJson(const {
          'apply_full_comp': true,
        }).applyFullComp,
        isTrue,
      );
      for (final junk in <Object?>['true', 1, null, 'yes', <String>[]]) {
        expect(
          StaffCapabilities.fromJson({'apply_full_comp': junk}).applyFullComp,
          isFalse,
          reason: 'malformed value $junk must never manufacture a grant',
        );
      }
    });

    test('A4 a stored grant is INERT while ordinary discounts are denied', () {
      const granted = StaffCapabilities(
        applyDiscount: false,
        applyFullComp: true,
      );
      expect(
        granted.applyFullComp,
        isTrue,
        reason: 'the grant is still stored',
      );
      expect(
        granted.fullCompEffective,
        isFalse,
        reason:
            'but it has no effect — the server refuses at the discount gate',
      );
    });
  });

  // ===== B. The wire payload keeps the two polarities apart ================
  group('B. the RPC payload', () {
    test('B1 setCapabilities sends the 4th toggle explicitly', () async {
      final t = _FakeTransport((_, _) => {'ok': true});
      await _repo(t).setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(applyFullComp: true),
      );
      final params = t.calls.single.$2;
      expect(params['p_apply_full_comp'], isTrue);
      expect(params['p_apply_discount'], isTrue);
    });

    test('B2 the request id changes when ONLY full-comp flips', () async {
      // The server fingerprints the 4 booleans; if the client reused an id across
      // a full-comp-only change, the RPC would REPLAY the prior result and the
      // write would be silently skipped.
      final t = _FakeTransport((_, _) => {'ok': true});
      await _repo(t).setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(applyFullComp: false),
      );
      await _repo(t).setCapabilities(
        employeeProfileId: 'emp-1',
        capabilities: const StaffCapabilities(applyFullComp: true),
      );
      expect(
        t.calls[0].$2['p_client_request_id'],
        isNot(t.calls[1].$2['p_client_request_id']),
      );
    });

    test(
      'B3 create emits GRANT-only for full comp, DENY-only for the rest',
      () async {
        final t = _FakeTransport(
          (_, _) => {'ok': true, 'employee_profile_id': 'e'},
        );
        await _repo(t).create(
          displayName: 'C',
          role: MembershipRole.cashier,
          capabilities: const StaffCapabilities(
            applyDiscount: false, // default-ON -> send the DENY
            applyFullComp: true, // default-OFF -> send the GRANT
          ),
        );
        final caps =
            t.calls.single.$2['p_capabilities'] as Map<String, dynamic>;
        expect(caps['apply_discount'], 'false', reason: 'deny-only polarity');
        expect(caps['apply_full_comp'], 'true', reason: 'grant-only polarity');
      },
    );

    test('B4 an un-granted cashier sends NO full-comp key at all', () async {
      final t = _FakeTransport(
        (_, _) => {'ok': true, 'employee_profile_id': 'e'},
      );
      await _repo(t).create(
        displayName: 'C',
        role: MembershipRole.cashier,
        capabilities: const StaffCapabilities(), // full comp off (the default)
      );
      // No denies and no grants -> p_capabilities is omitted entirely, which keeps
      // the LEGACY idempotency fingerprint intact for existing clients.
      expect(t.calls.single.$2.containsKey('p_capabilities'), isFalse);
    });
  });

  // ===== C. The staff permission UI =======================================
  group('C. the staff permission surface', () {
    testWidgets('C1 the two permissions are SEPARATE controls', (tester) async {
      await _pump(tester, _RecordingRepo([_cashier()]));
      await _openEditDialog(tester);
      expect(find.byKey(const Key('cap-apply-discount')), findsOneWidget);
      expect(find.byKey(const Key('cap-apply-full-comp')), findsOneWidget);
    });

    testWidgets('C2 full comp defaults OFF for a cashier', (tester) async {
      await _pump(tester, _RecordingRepo([_cashier()]));
      await _openEditDialog(tester);
      expect(_switch(tester, 'cap-apply-discount').value, isTrue);
      expect(
        _switch(tester, 'cap-apply-full-comp').value,
        isFalse,
        reason: 'a cashier must not start out able to give food away',
      );
    });

    testWidgets('C3 turning ordinary discounts OFF makes full comp INEFFECTIVE '
        'and NOT editable', (tester) async {
      await _pump(
        tester,
        _RecordingRepo([
          _cashier(caps: const StaffCapabilities(applyFullComp: true)),
        ]),
      );
      await _openEditDialog(tester);
      expect(_switch(tester, 'cap-apply-full-comp').onChanged, isNotNull);

      await tester.tap(find.byKey(const Key('cap-apply-discount')));
      await tester.pumpAndSettle();

      final comp = _switch(tester, 'cap-apply-full-comp');
      expect(
        comp.onChanged,
        isNull,
        reason: 'ineffective without the discount right, so not editable',
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.staffCapApplyFullCompNeedsDiscount),
        findsOneWidget,
        reason: 'and it must SAY why, not just go grey',
      );
    });

    testWidgets('C4 manager/owner rights are stated honestly', (tester) async {
      await _pump(tester, _RecordingRepo([_cashier()]));
      await _openEditDialog(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.staffCapabilitiesRoleNote), findsOneWidget);
    });

    testWidgets('C5 an edit PERSISTS the grant through the repository', (
      tester,
    ) async {
      final repo = _RecordingRepo([_cashier()]);
      await _pump(tester, repo);
      await _openEditDialog(tester);
      await tester.tap(find.byKey(const Key('cap-apply-full-comp')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.capabilityCalls, hasLength(1));
      expect(repo.capabilityCalls.single.$2.applyFullComp, isTrue);
    });

    for (final locale in [
      const Locale('ar'),
      const Locale('he'),
      const Locale('en'),
    ]) {
      testWidgets('C6 renders in ${locale.languageCode} with a REAL localized '
          'label', (tester) async {
        await _pump(tester, _RecordingRepo([_cashier()]), locale: locale);
        await _openEditDialog(tester);
        final l10n = await AppLocalizations.delegate.load(locale);
        expect(find.byKey(const Key('cap-apply-full-comp')), findsOneWidget);
        expect(
          l10n.staffCapApplyFullComp,
          isNot('staffCapApplyFullComp'),
          reason: 'a label equal to its key is an untranslated string',
        );
        expect(find.text(l10n.staffCapApplyFullComp), findsOneWidget);
      });
    }

    testWidgets('C7 the control survives a narrow (phone) layout', (
      tester,
    ) async {
      await _pump(
        tester,
        _RecordingRepo([_cashier()]),
        size: const Size(390 * 3, 844 * 3),
      );
      await _openEditDialog(tester);
      expect(find.byKey(const Key('cap-apply-full-comp')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ===== D. The Activity Log =============================================
  group('D. the Activity Log renders the capability change safely', () {
    AuditEventView view(AppLocalizations l10n, AuditEvent e) =>
        AuditEventPresenter(l10n, 'ILS').present(e);

    AuditEvent capsEvent() => const AuditEvent(
      eventId: 'e1',
      action: 'staff.capabilities_updated',
      category: 'staff',
      occurredAtLabel: '2026-07-17 09:00',
      oldValues: {
        'capabilities': {'apply_full_comp': false},
      },
      newValues: {
        'capabilities': {'apply_full_comp': true},
        'employee_profile_id': 'SHOULD-NOT-RENDER',
      },
    );

    for (final locale in [
      const Locale('ar'),
      const Locale('he'),
      const Locale('en'),
    ]) {
      testWidgets('D1 the grant is a labelled before→after change in '
          '${locale.languageCode}', (tester) async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final v = view(l10n, capsEvent());

        final row = v.changes.firstWhere(
          (c) => c.label == l10n.activityLogCapApplyFullComp,
        );
        expect(
          row.oldValue,
          isNotNull,
          reason: 'the BEFORE state must be shown',
        );
        expect(row.newValue, isNotNull);
        expect(row.oldValue, isNot(row.newValue));
        expect(
          v.changes.any((c) => c.newValue.contains('SHOULD-NOT-RENDER')),
          isFalse,
          reason: 'the internal id must never surface',
        );
        expect(v.isKnownAction, isTrue, reason: 'never falls into Other');
      });
    }

    testWidgets('D2 a denied full comp shows WHY and WHAT it would have left', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final v = view(
        l10n,
        const AuditEvent(
          eventId: 'e2',
          action: 'order.discount_denied',
          category: 'discounts',
          occurredAtLabel: '2026-07-17 09:00',
          newValues: {
            'denied_reason': 'full_comp_permission_required',
            'resulting_charge_state': 'not_chargeable',
            'order_code': '#0A1B2C',
          },
        ),
      );
      expect(
        v.categoryLabel,
        l10n.activityLogCategoryDiscounts,
        reason: 'a denied comp belongs under Discounts, never Other',
      );
      final labels = v.changes.map((c) => c.label).toList();
      final values = v.changes.map((c) => c.newValue).toList();

      expect(labels, contains(l10n.activityLogFieldDeniedReason));
      expect(
        values,
        contains(l10n.activityLogDeniedFullCompPermissionRequired),
      );
      expect(labels, contains(l10n.activityLogFieldResultingChargeState));
      expect(values, contains(l10n.dashboardNoCharge));
      expect(v.isDenied, isTrue);
      expect(v.isKnownAction, isTrue, reason: 'categorized, never Other');
      // The raw server tokens must never leak to the operator.
      expect(values, isNot(contains('full_comp_permission_required')));
      expect(values, isNot(contains('not_chargeable')));
    });

    testWidgets('D3 HISTORICAL rows keep rendering (the trail is append-only)', (
      tester,
    ) async {
      // Rows written BEFORE this ticket carry the old role-only token. They still
      // exist and must not regress to a raw token.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final v = view(
        l10n,
        const AuditEvent(
          eventId: 'e3',
          action: 'order.discount_denied',
          category: 'discounts',
          occurredAtLabel: '2026-07-10 12:00',
          newValues: {'denied_reason': 'full_comp_requires_manager'},
        ),
      );
      expect(
        v.changes.map((c) => c.newValue),
        contains(l10n.activityLogDeniedFullCompRequiresManager),
      );
    });
  });
}
