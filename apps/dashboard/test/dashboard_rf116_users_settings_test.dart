import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_dashboard/src/admin/supabase_settings_repository.dart';
import 'package:restoflow_dashboard/src/admin/supabase_users_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-116 CLIENT: the real Users tab (list + change-role + revoke over the three
/// public member RPCs) and the owner-only editable Settings fields (branch /
/// restaurant name + receipt prefix). No fabricated members; every editable
/// control calls a real backend seam and reflects the true result.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// A fake transport driven by a per-test handler. Records every call so a test
/// can assert the exact RPC + params reached the seam.
class _FnTransport implements SyncRpcTransport {
  _FnTransport(this._handler);

  final Object? Function(String function, Map<String, dynamic> params) _handler;
  final List<String> calls = [];
  final List<Map<String, dynamic>> params = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    calls.add(function);
    params.add(p);
    final result = _handler(function, p);
    if (result is SyncTransportException) throw result;
    return result;
  }

  Map<String, dynamic>? paramsFor(String function) {
    final i = calls.indexOf(function);
    return i < 0 ? null : params[i];
  }
}

Map<String, dynamic> _manager({
  String membershipId = 'mm-2',
  bool isSelf = false,
  String status = 'active',
}) => <String, dynamic>{
  'membership_id': membershipId,
  'app_user_id': 'u2',
  'email': 'dana@olive.test',
  'display_name': 'Dana Field',
  'role': 'manager',
  'role_rank': 2,
  'organization_id': 'demo-org',
  'restaurant_id': 'rest-1',
  'restaurant_name': 'Olive North',
  'branch_id': 'branch-1',
  'branch_name': 'Main hall',
  'status': status,
  'is_self': isSelf,
  'has_pin': true,
};

Object? _membersOk(List<Map<String, dynamic>> members) => <String, dynamic>{
  'ok': true,
  'entity': 'members',
  'members': members,
  'server_ts': 't',
};

T _ok<T>(Result<T, AdminFailure> r) =>
    r.fold((v) => v, (f) => throw StateError('expected success, got $f'));

AdminFailure _fail<T>(Result<T, AdminFailure> r) =>
    r.fold((v) => throw StateError('expected failure, got success'), (f) => f);

SupabaseUsersRepository _usersRepo(SyncRpcTransport t) =>
    SupabaseUsersRepository(
      transport: t,
      scope: AdminScope.demo, // org_owner acting role, org 'demo-org'
      currentUserId: () => 'u',
      nonce: () => 1,
    );

Future<void> _pumpUsers(
  WidgetTester tester, {
  required SyncRpcTransport transport,
}) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const scope = AdminScope.demo;
  await tester.pumpWidget(
    ProviderScope(
      overrides: adminFeatureOverrides(
        scope: scope,
        repository: _usersRepo(transport),
      ),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(body: AdminUsersScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MembershipContext _membership(MembershipRole role) => MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Olive Group',
  restaurantId: 'rest-1',
  restaurantName: 'Olive North',
  branchId: 'branch-1',
  branchName: 'Main hall',
  role: role,
  status: 'active',
);

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo({
    this.prefill,
    this.branchResult = SettingsWrite.ok,
    this.restaurantResult = SettingsWrite.ok,
  });

  final SettingsPrefill? prefill;
  final SettingsWrite branchResult;
  final SettingsWrite restaurantResult;
  int branchSaves = 0;
  int restaurantSaves = 0;
  String? lastBranchName;
  String? lastReceiptPrefix;
  String? lastBranchStatus;
  String? lastRestaurantName;

  @override
  Future<SettingsPrefill?> readPrefill() async => prefill;

  @override
  Future<SettingsWrite> saveBranch({
    required String name,
    String? receiptPrefix,
    required String status,
  }) async {
    branchSaves++;
    lastBranchName = name;
    lastReceiptPrefix = receiptPrefix;
    lastBranchStatus = status;
    return branchResult;
  }

  @override
  Future<SettingsWrite> saveRestaurant({
    required String name,
    required String status,
  }) async {
    restaurantSaves++;
    lastRestaurantName = name;
    return restaurantResult;
  }
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required MembershipRole role,
  required SettingsRepository repo,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: RealSettingsView(
            membership: _membership(role),
            currencyCode: 'ILS',
            settingsRepository: repo,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SupabaseUsersRepository — list_members / update_role / revoke', () {
    test('loadUsers maps members and targets the membership_id', () async {
      final t = _FnTransport(
        (fn, p) => fn == 'list_members' ? _membersOk([_manager()]) : null,
      );
      final list = _ok(await _usersRepo(t).loadUsers());
      expect(list, hasLength(1));
      expect(list.single.displayName, 'Dana Field');
      expect(list.single.membershipId, 'mm-2');
      expect(
        list.single.id,
        'mm-2',
      ); // id == membership_id (role-change target)
      expect(list.single.role, MembershipRole.manager);
      expect(list.single.scopeLabel, 'Main hall');
      // The list read is scoped to the active organization.
      expect(t.paramsFor('list_members')?['p_organization_id'], 'demo-org');
    });

    test(
      'a permission_denied list surfaces AdminPermissionDenied (no members)',
      () async {
        final t = _FnTransport(
          (fn, p) => fn == 'list_members'
              ? {'ok': false, 'error': 'permission_denied', 'entity': 'members'}
              : null,
        );
        expect(
          _fail(await _usersRepo(t).loadUsers()),
          isA<AdminPermissionDenied>(),
        );
      },
    );

    test('a 42501 list (cross-tenant / non-member) surfaces denied', () async {
      final t = _FnTransport(
        (fn, p) => fn == 'list_members'
            ? const SyncTransportException(
                SyncTransportErrorKind.auth,
                code: '42501',
              )
            : null,
      );
      expect(
        _fail(await _usersRepo(t).loadUsers()),
        isA<AdminPermissionDenied>(),
      );
    });

    test(
      'updateRole sends the membership_id + wire role and succeeds',
      () async {
        final t = _FnTransport(
          (fn, p) => fn == 'update_role'
              ? {
                  'ok': true,
                  'membership_id': p['p_membership_id'],
                  'role': p['p_new_role'],
                }
              : null,
        );
        final r = await _usersRepo(
          t,
        ).updateRole(userId: 'mm-2', newRole: MembershipRole.cashier);
        expect(r.isSuccess, isTrue);
        expect(t.paramsFor('update_role')?['p_membership_id'], 'mm-2');
        expect(t.paramsFor('update_role')?['p_new_role'], 'cashier');
      },
    );

    test('a denied update_role surfaces AdminPermissionDenied', () async {
      final t = _FnTransport(
        (fn, p) => fn == 'update_role'
            ? {
                'ok': false,
                'error': 'permission_denied',
                'entity': 'membership',
              }
            : null,
      );
      expect(
        _fail(
          await _usersRepo(
            t,
          ).updateRole(userId: 'mm-2', newRole: MembershipRole.cashier),
        ),
        isA<AdminPermissionDenied>(),
      );
    });

    test('revokeMembership sends the membership_id and succeeds', () async {
      final t = _FnTransport(
        (fn, p) => fn == 'revoke_membership'
            ? {
                'ok': true,
                'membership_id': p['p_membership_id'],
                'status': 'revoked',
              }
            : null,
      );
      final r = await _usersRepo(t).revokeMembership('mm-2');
      expect(_ok(r).status, 'revoked');
      expect(t.paramsFor('revoke_membership')?['p_membership_id'], 'mm-2');
    });

    test('a 42501 revoke (not-found / cross-tenant) surfaces denied', () async {
      final t = _FnTransport(
        (fn, p) => fn == 'revoke_membership'
            ? const SyncTransportException(
                SyncTransportErrorKind.auth,
                code: '42501',
              )
            : null,
      );
      expect(
        _fail(await _usersRepo(t).revokeMembership('mm-2')),
        isA<AdminPermissionDenied>(),
      );
    });

    test('grant is honestly unavailable (invites are out of scope)', () async {
      final t = _FnTransport((fn, p) => null);
      final repo = _usersRepo(t);
      expect(repo.supportsGrant, isFalse);
      final r = await repo.grantMembership(
        displayName: 'X',
        email: 'x@y.test',
        role: MembershipRole.cashier,
      );
      expect(r.isFailure, isTrue);
      // No fake success and no RPC pretending to invite.
      expect(t.calls, isEmpty);
    });
  });

  group('Users tab (real) — renders members + change-role + revoke', () {
    testWidgets('renders the real members; grant is hidden (out of scope)', (
      tester,
    ) async {
      final l10n = await _en();
      final t = _FnTransport(
        (fn, p) => fn == 'list_members' ? _membersOk([_manager()]) : null,
      );
      await _pumpUsers(tester, transport: t);

      expect(find.text('Dana Field'), findsOneWidget); // real member rendered
      expect(find.text('Dana Reyes'), findsNothing); // never a demo person
      expect(find.text(l10n.adminGrantUser), findsNothing); // grant hidden
    });

    testWidgets('revoke calls the seam and reflects success', (tester) async {
      final l10n = await _en();
      final t = _FnTransport(
        (fn, p) => fn == 'list_members'
            ? _membersOk([_manager()])
            : fn == 'revoke_membership'
            ? {
                'ok': true,
                'membership_id': p['p_membership_id'],
                'status': 'revoked',
              }
            : null,
      );
      await _pumpUsers(tester, transport: t);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.adminRevoke)); // the menu item
      await tester.pumpAndSettle();
      // The confirm dialog (member-specific, not the device copy).
      expect(find.text(l10n.adminRevokeMemberTitle), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, l10n.adminRevoke));
      await tester.pumpAndSettle();

      expect(t.calls, contains('revoke_membership'));
      expect(t.paramsFor('revoke_membership')?['p_membership_id'], 'mm-2');
      expect(find.text(l10n.adminMemberRevoked), findsOneWidget); // snackbar
    });

    testWidgets('a denied revoke shows the honest denied state', (
      tester,
    ) async {
      final l10n = await _en();
      final t = _FnTransport(
        (fn, p) => fn == 'list_members'
            ? _membersOk([_manager()])
            : fn == 'revoke_membership'
            ? {
                'ok': false,
                'error': 'permission_denied',
                'entity': 'membership',
              }
            : null,
      );
      await _pumpUsers(tester, transport: t);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.adminRevoke));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.adminRevoke));
      await tester.pumpAndSettle();

      expect(t.calls, contains('revoke_membership'));
      expect(find.text(l10n.adminPermissionDeniedTitle), findsOneWidget);
    });

    testWidgets('change role calls the seam and reflects success', (
      tester,
    ) async {
      final l10n = await _en();
      final t = _FnTransport(
        (fn, p) => fn == 'list_members'
            ? _membersOk([_manager()])
            : fn == 'update_role'
            ? {
                'ok': true,
                'membership_id': p['p_membership_id'],
                'role': p['p_new_role'],
              }
            : null,
      );
      await _pumpUsers(tester, transport: t);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.adminChangeRole));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.adminUpdate));
      await tester.pumpAndSettle();

      expect(t.calls, contains('update_role'));
      expect(t.paramsFor('update_role')?['p_membership_id'], 'mm-2');
      expect(find.text(l10n.adminRoleUpdated), findsOneWidget); // snackbar
    });
  });

  group('Settings tab (real) — owner-only editable fields', () {
    testWidgets('an owner sees the editable section; Save calls the seam', (
      tester,
    ) async {
      final l10n = await _en();
      final repo = _FakeSettingsRepo(
        prefill: const SettingsPrefill(
          branchName: 'Main hall',
          branchStatus: 'active',
          restaurantName: 'Olive North',
          restaurantStatus: 'active',
        ),
        branchResult: SettingsWrite.ok,
        restaurantResult: SettingsWrite.ok,
      );
      await _pumpSettings(tester, role: MembershipRole.orgOwner, repo: repo);

      expect(find.text(l10n.dashboardSettingsEditableTitle), findsOneWidget);
      expect(find.byKey(const Key('settings-branch-name')), findsOneWidget);
      // Currency is locked (a note), never an editable selector.
      expect(find.text(l10n.dashboardSettingsCurrencyLocked), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('settings-branch-name')),
        'Riverside',
      );
      await tester.tap(find.byKey(const Key('settings-save-branch')));
      await tester.pumpAndSettle();

      expect(repo.branchSaves, 1);
      expect(repo.lastBranchName, 'Riverside');
      expect(
        repo.lastBranchStatus,
        'active',
      ); // preserved, never silently flipped
      expect(
        find.text(l10n.dashboardShiftCloseSaved),
        findsOneWidget,
      ); // snackbar

      // The restaurant name (concrete restaurant in scope) has its own Save.
      await tester.enterText(
        find.byKey(const Key('settings-restaurant-name')),
        'Olive South',
      );
      await tester.tap(find.byKey(const Key('settings-save-restaurant')));
      await tester.pumpAndSettle();
      expect(repo.restaurantSaves, 1);
      expect(repo.lastRestaurantName, 'Olive South');
    });

    testWidgets('a denied save shows the honest denied snackbar', (
      tester,
    ) async {
      final l10n = await _en();
      final repo = _FakeSettingsRepo(
        prefill: const SettingsPrefill(
          branchName: 'Main hall',
          branchStatus: 'active',
        ),
        branchResult: SettingsWrite.denied,
      );
      await _pumpSettings(tester, role: MembershipRole.orgOwner, repo: repo);

      await tester.tap(find.byKey(const Key('settings-save-branch')));
      await tester.pumpAndSettle();

      expect(repo.branchSaves, 1);
      expect(find.text(l10n.dashboardShiftCloseDenied), findsOneWidget);
    });

    testWidgets('a manager sees it read-only — no editable section', (
      tester,
    ) async {
      final repo = _FakeSettingsRepo(
        prefill: const SettingsPrefill(branchName: 'Main hall'),
      );
      await _pumpSettings(tester, role: MembershipRole.manager, repo: repo);

      // The editable section is omitted; the read-only workspace view remains.
      expect(find.byKey(const Key('settings-branch-name')), findsNothing);
      expect(find.byKey(const Key('settings-save-branch')), findsNothing);
      expect(repo.branchSaves, 0);
    });
  });
}
