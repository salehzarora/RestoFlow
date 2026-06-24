import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';

/// Pumps the POS screen for [locale] and returns the resolved text direction
/// captured from a context below the MaterialApp's Directionality.
Future<TextDirection> _pumpAndReadDirection(
  WidgetTester tester,
  Locale locale,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
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
            return const PosMenuScreen();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return direction;
}

void main() {
  testWidgets('English renders left-to-right', (tester) async {
    final direction = await _pumpAndReadDirection(tester, const Locale('en'));
    expect(direction, TextDirection.ltr);
    expect(find.text('Cart'), findsOneWidget);
  });

  testWidgets('Arabic renders right-to-left with localized chrome', (
    tester,
  ) async {
    final direction = await _pumpAndReadDirection(tester, const Locale('ar'));
    expect(direction, TextDirection.rtl);
    expect(find.text('السلة'), findsOneWidget); // posCartTitle (ar)
  });

  testWidgets('Hebrew renders right-to-left with localized chrome', (
    tester,
  ) async {
    final direction = await _pumpAndReadDirection(tester, const Locale('he'));
    expect(direction, TextDirection.rtl);
    expect(find.text('עגלה'), findsOneWidget); // posCartTitle (he)
  });
}
