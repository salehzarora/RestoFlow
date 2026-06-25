import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

MembershipContext membership({
  required String id,
  required String orgName,
  String? restaurantName,
  String? branchName,
  MembershipRole role = MembershipRole.manager,
}) => MembershipContext(
  id: id,
  organizationId: 'orgid-$id',
  organizationName: orgName,
  restaurantId: restaurantName == null ? null : 'restid-$id',
  restaurantName: restaurantName,
  branchId: branchName == null ? null : 'branchid-$id',
  branchName: branchName,
  role: role,
  status: 'active',
);

Future<({AppLocalizations l10n, TextDirection dir})> pumpPicker(
  WidgetTester tester,
  List<MembershipContext> memberships, {
  ValueChanged<String>? onSelect,
  Locale locale = const Locale('en'),
}) async {
  late AppLocalizations l10n;
  late TextDirection dir;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            dir = Directionality.of(context);
            return MembershipPickerView(
              memberships: memberships,
              onSelect: onSelect ?? (_) {},
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (l10n: l10n, dir: dir);
}

void main() {
  final twoMemberships = [
    membership(
      id: 'a',
      orgName: 'Acme Org',
      restaurantName: 'Downtown',
      branchName: 'Main St',
      role: MembershipRole.cashier,
    ),
    membership(id: 'b', orgName: 'Beta Group', role: MembershipRole.manager),
  ];

  testWidgets('renders the localized header + every membership by name', (
    tester,
  ) async {
    final r = await pumpPicker(tester, twoMemberships);
    expect(find.text(r.l10n.authChooseLocation), findsOneWidget);
    expect(find.text('Acme Org'), findsOneWidget);
    expect(find.text('Beta Group'), findsOneWidget);
    // role labels render (per-membership, not a global role)
    expect(find.text(r.l10n.authRoleCashier), findsOneWidget);
    expect(find.text(r.l10n.authRoleManager), findsOneWidget);
    // scoped membership shows restaurant + branch names
    expect(find.text('Downtown'), findsOneWidget);
    expect(find.text('Main St'), findsOneWidget);
  });

  testWidgets('tapping a membership reports its id via the callback', (
    tester,
  ) async {
    String? selected;
    await pumpPicker(tester, twoMemberships, onSelect: (id) => selected = id);
    await tester.tap(find.text('Beta Group'));
    await tester.pumpAndSettle();
    expect(selected, 'b');
  });

  testWidgets('org-wide membership renders without restaurant/branch rows', (
    tester,
  ) async {
    final r = await pumpPicker(tester, [
      membership(id: 'b', orgName: 'Beta Group', role: MembershipRole.manager),
    ]);
    expect(find.text('Beta Group'), findsOneWidget);
    // no restaurant/branch field labels for an org-wide membership
    expect(find.text('${r.l10n.authRestaurant}: '), findsNothing);
    expect(find.text('${r.l10n.authBranch}: '), findsNothing);
  });

  testWidgets('never renders a raw membership/org UUID when names exist', (
    tester,
  ) async {
    await pumpPicker(tester, twoMemberships);
    // ids used only for the callback, never shown
    expect(find.textContaining('orgid-'), findsNothing);
    expect(find.textContaining('restid-'), findsNothing);
    expect(find.textContaining('branchid-'), findsNothing);
  });

  testWidgets('Arabic renders RTL', (tester) async {
    final r = await pumpPicker(
      tester,
      twoMemberships,
      locale: const Locale('ar'),
    );
    expect(r.dir, TextDirection.rtl);
    expect(find.text(r.l10n.authChooseLocation), findsOneWidget);
    expect(find.text('Acme Org'), findsOneWidget);
  });
}
