import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<void> pump(WidgetTester tester, Widget screen, Locale locale) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const scope = AdminScope.demo;
  await tester.pumpWidget(
    ProviderScope(
      overrides: adminFeatureOverrides(
        scope: scope,
        repository: DemoAdminStore(scope: scope),
      ),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in const [Locale('ar'), Locale('he')]) {
    testWidgets(
      'admin screens render RTL + localized in ${locale.languageCode}',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(locale);

        await pump(tester, const AdminSettingsScreen(), locale);
        expect(tester.takeException(), isNull);
        expect(
          Directionality.of(tester.element(find.byType(AdminSettingsScreen))),
          TextDirection.rtl,
        );
        expect(find.text(l10n.adminSectionOrg), findsOneWidget);

        await pump(tester, const AdminUsersScreen(), locale);
        expect(tester.takeException(), isNull);
        expect(find.text(l10n.adminUsersTitle), findsWidgets);

        await pump(tester, const AdminDevicesScreen(), locale);
        expect(tester.takeException(), isNull);
        expect(find.text(l10n.adminDevicesTitle), findsWidgets);
      },
    );
  }
}
