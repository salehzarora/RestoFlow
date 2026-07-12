import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// Renders [child] under the RestoFlow theme in the given [direction] (both
/// LTR and RTL are exercised so the new "1c" widgets are proven RTL-safe).
Widget _app(Widget child, TextDirection direction) => MaterialApp(
  theme: restoflowBaseTheme(),
  home: Directionality(
    textDirection: direction,
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  for (final dir in TextDirection.values) {
    final tag = dir == TextDirection.rtl ? 'RTL' : 'LTR';

    testWidgets('RestoflowGradientHeader standard + hero render ($tag)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              RestoflowGradientHeader(
                icon: Icons.restaurant_menu,
                title: 'Menu',
                subtitle: 'Branch items',
                actions: [
                  Builder(
                    builder: (ctx) => FilledButton(
                      style: RestoflowGradientHeader.whiteActionStyle(ctx),
                      onPressed: () {},
                      child: const Text('New item'),
                    ),
                  ),
                ],
              ),
              const RestoflowGradientHeader(
                hero: Text('hero-body', key: Key('hero-body')),
              ),
            ],
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Branch items'), findsOneWidget);
      expect(find.text('New item'), findsOneWidget);
      expect(find.byKey(const Key('hero-body')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('RestoflowMetricCard filled tinted variant renders ($tag)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 220,
            child: RestoflowMetricCard(
              label: 'Cash sales',
              value: '₪2,777.00',
              caption: '82% of total',
              icon: Icons.account_balance_wallet_outlined,
              tone: RestoflowTone.success,
              filled: true,
            ),
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cash sales'), findsOneWidget);
      expect(find.text('₪2,777.00'), findsOneWidget);
      expect(find.text('82% of total'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('RestoflowDonutChart renders with segments and empty ($tag)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              RestoflowDonutChart(
                segments: [
                  RestoflowDonutSegment(
                    value: 82,
                    color: Color(0xFF1B7A52),
                    label: 'Cash',
                  ),
                  RestoflowDonutSegment(
                    value: 18,
                    color: Color(0xFFC2410C),
                    label: 'Card',
                  ),
                ],
                centerLabel: '82%',
                centerSub: 'cash',
              ),
              // All-zero -> honest empty ring, no exception, no center.
              RestoflowDonutChart(
                segments: [
                  RestoflowDonutSegment(
                    value: 0,
                    color: Color(0xFF1B7A52),
                    label: 'Cash',
                  ),
                ],
              ),
            ],
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('82%'), findsOneWidget);
      expect(find.byType(RestoflowDonutChart), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('RestoflowReadinessStrip ready + pending render ($tag)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              RestoflowReadinessStrip(
                ready: true,
                readyLabel: 'Branch ready for service',
                pendingLabel: 'Finishing setup',
                percent: 100,
                stats: [
                  RestoflowReadinessStat(
                    icon: Icons.restaurant_menu,
                    label: 'Menu',
                    done: 4,
                    total: 4,
                  ),
                  RestoflowReadinessStat(
                    icon: Icons.devices,
                    label: 'Devices',
                    done: 9,
                    total: 10,
                  ),
                ],
              ),
              RestoflowReadinessStrip(
                ready: false,
                readyLabel: 'Ready',
                pendingLabel: 'Finishing setup',
                percent: 60,
                stats: [],
              ),
            ],
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Branch ready for service'), findsOneWidget);
      expect(find.text('Finishing setup'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      // RF-132: each stat box renders the label over its own done/total count
      // (previously one concatenated 'Menu 4/4' chip text).
      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('4/4'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('9/10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('RestoflowRankRow renders badge, name, meta, bar ($tag)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RestoflowRankRow(
                  rank: 1,
                  name: 'Chicken shawarma',
                  meta: '×32 · ₪640.00',
                  fraction: 1,
                ),
                RestoflowRankRow(
                  rank: 4,
                  name: 'Fries',
                  meta: '×5 · ₪80.00',
                  fraction: 0.1,
                ),
              ],
            ),
          ),
          dir,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chicken shawarma'), findsOneWidget);
      expect(find.text('×32 · ₪640.00'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
