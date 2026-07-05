import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// DESIGN-002 design-system additions: the metric-card trend delta and the
/// static sales-by-hour bar chart. Both are pure presentation (no animation,
/// no money formatting, no l10n) so they stay pumpAndSettle-safe.
Widget _host(Widget child) => MaterialApp(
  theme: restoflowBaseTheme(),
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, child: child)),
  ),
);

void main() {
  group('RestoflowMetricCard delta (DESIGN-002)', () {
    testWidgets('a positive delta renders the up arrow in the success tone', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const RestoflowMetricCard(
            label: 'Gross sales',
            value: '₪626.00',
            delta: RestoflowMetricDelta(
              label: '9% vs yesterday',
              positive: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('9% vs yesterday'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);

      final theme = restoflowBaseTheme();
      final expected = RestoflowTone.success.styleOf(theme).accent;
      final text = tester.widget<Text>(find.text('9% vs yesterday'));
      expect(text.style?.color, expected);
    });

    testWidgets('a negative delta renders the down arrow in the danger tone', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const RestoflowMetricCard(
            label: 'Orders',
            value: '5',
            delta: RestoflowMetricDelta(
              label: '12% vs yesterday',
              positive: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      final theme = restoflowBaseTheme();
      final text = tester.widget<Text>(find.text('12% vs yesterday'));
      expect(text.style?.color, RestoflowTone.danger.styleOf(theme).accent);
    });

    testWidgets('no delta => no arrows (existing cards unchanged)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const RestoflowMetricCard(label: 'Orders', value: '7')),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });
  });

  group('RestoflowBarChart (DESIGN-002)', () {
    const bars = [
      RestoflowBarDatum(label: '12', value: 22400),
      RestoflowBarDatum(label: '13', value: 31000),
      RestoflowBarDatum(label: '14', value: 15600),
    ];

    testWidgets('renders bars + the peak value label, no exceptions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const RestoflowBarChart(bars: bars, peakValueLabel: '₪310.00')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RestoflowBarChart), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty series renders nothing (no chart chrome)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const RestoflowBarChart(bars: [])));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(RestoflowBarChart),
          matching: find.byType(LayoutBuilder),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders under RTL without exceptions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: restoflowBaseTheme(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 360,
                child: RestoflowBarChart(bars: bars, peakValueLabel: '₪310.00'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
