import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Widget _wrap(Locale locale) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const DashboardHomeScreen(),
  ),
);

void _useWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders KPI cards, daily summary, sections, and demo notice', (
    tester,
  ) async {
    _useWideSurface(tester);
    await tester.pumpWidget(_wrap(const Locale('en')));
    await tester.pumpAndSettle();

    // Demo notice + section headings.
    expect(find.text('Demo data — not from a live backend.'), findsOneWidget);
    expect(find.text('Daily summary'), findsOneWidget);
    expect(find.text('Sales by branch'), findsOneWidget);
    expect(find.text('Top items'), findsOneWidget);

    // KPI labels.
    expect(find.text("Today's sales"), findsOneWidget);
    expect(find.text('Avg. order value'), findsOneWidget);
    expect(find.text('Completed orders'), findsOneWidget);

    // Money values rendered from integer minor units (no thousands separator).
    expect(find.text('₪12345.00'), findsWidgets); // today's sales + net sales
    expect(find.text('₪141.89'), findsOneWidget); // average order value
    expect(find.text('-₪13.00'), findsOneWidget); // cash variance (negative)

    // Demo data rows.
    expect(find.text('Downtown'), findsOneWidget);
    expect(find.text('Classic Burger'), findsOneWidget);
  });
}
