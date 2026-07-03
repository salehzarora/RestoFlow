import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/admin/branch_shift_close_policy_repository.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-113: the real-mode Settings tab's per-branch shift-close policy toggle.
/// Owners can flip it (write goes to the backend seam); managers/cashiers see
/// it read-only; a failed read shows an honest unavailable state; a denied or
/// failed write reverts the optimistic value.
class _FakePolicyRepo implements BranchShiftClosePolicyRepository {
  _FakePolicyRepo({
    this.initial = true,
    this.writeResult = BranchPolicyWrite.ok,
  });

  final bool? initial;
  final BranchPolicyWrite writeResult;
  int writes = 0;
  bool? lastWrite;

  @override
  Future<bool?> read() async => initial;

  @override
  Future<BranchPolicyWrite> setEnabled(bool enabled) async {
    writes++;
    lastWrite = enabled;
    return writeResult;
  }
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

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required MembershipRole role,
  required BranchShiftClosePolicyRepository repo,
}) async {
  tester.view.physicalSize = const Size(1400, 2200);
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
            policyRepository: repo,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SwitchListTile _tile(WidgetTester tester) => tester.widget<SwitchListTile>(
  find.byKey(const Key('shift-close-policy-toggle')),
);

void main() {
  testWidgets('owner can toggle the policy off — the write reaches the seam', (
    tester,
  ) async {
    final repo = _FakePolicyRepo(initial: true);
    await _pump(tester, role: MembershipRole.restaurantOwner, repo: repo);

    expect(_tile(tester).value, isTrue);
    await tester.tap(find.byKey(const Key('shift-close-policy-toggle')));
    await tester.pumpAndSettle();

    expect(repo.writes, 1);
    expect(repo.lastWrite, isFalse);
    expect(_tile(tester).value, isFalse); // optimistic value committed
  });

  testWidgets(
    'manager sees the current value read-only — no write is possible',
    (tester) async {
      final l10n = await _en();
      final repo = _FakePolicyRepo(initial: true);
      await _pump(tester, role: MembershipRole.manager, repo: repo);

      // The switch is disabled (onChanged null) and the owner-only note shows.
      expect(_tile(tester).onChanged, isNull);
      expect(find.text(l10n.dashboardShiftCloseOwnerOnly), findsOneWidget);
      await tester.tap(find.byKey(const Key('shift-close-policy-toggle')));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
    },
  );

  testWidgets('a failed read shows the honest unavailable state — no toggle', (
    tester,
  ) async {
    final l10n = await _en();
    final repo = _FakePolicyRepo(initial: null);
    await _pump(tester, role: MembershipRole.restaurantOwner, repo: repo);

    expect(find.text(l10n.dashboardShiftCloseUnavailable), findsOneWidget);
    expect(find.byKey(const Key('shift-close-policy-toggle')), findsNothing);
  });

  testWidgets('a denied write reverts the optimistic value', (tester) async {
    final repo = _FakePolicyRepo(
      initial: true,
      writeResult: BranchPolicyWrite.denied,
    );
    await _pump(tester, role: MembershipRole.restaurantOwner, repo: repo);

    await tester.tap(find.byKey(const Key('shift-close-policy-toggle')));
    await tester.pumpAndSettle();

    expect(repo.writes, 1);
    expect(_tile(tester).value, isTrue); // reverted after denial
  });
}
