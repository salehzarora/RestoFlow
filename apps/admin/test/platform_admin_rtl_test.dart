import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<TextDirection> _pumpAndReadDirection(
  WidgetTester tester,
  Locale locale,
) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late TextDirection direction;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Builder(
          builder: (context) {
            direction = Directionality.of(context);
            return const PlatformAdminScreen();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return direction;
}

void main() {
  testWidgets('English renders left-to-right with localized chrome', (
    tester,
  ) async {
    final direction = await _pumpAndReadDirection(tester, const Locale('en'));
    expect(direction, TextDirection.ltr);
    expect(find.text('Platform overview'), findsOneWidget);
  });

  testWidgets('Arabic renders right-to-left with localized chrome', (
    tester,
  ) async {
    final direction = await _pumpAndReadDirection(tester, const Locale('ar'));
    expect(direction, TextDirection.rtl);
    expect(
      find.text('نظرة عامة على المنصة'),
      findsOneWidget,
    ); // adminOverviewTitle (ar)
  });

  testWidgets('Hebrew renders right-to-left with localized chrome', (
    tester,
  ) async {
    final direction = await _pumpAndReadDirection(tester, const Locale('he'));
    expect(direction, TextDirection.rtl);
    expect(
      find.text('סקירת הפלטפורמה'),
      findsOneWidget,
    ); // adminOverviewTitle (he)
  });
}
