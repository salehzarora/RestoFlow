import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// Pumps [child] under the shared theme, in [direction] (LTR by default), inside
/// a Material/Scaffold so Card/Theme ancestors resolve.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  TextDirection direction = TextDirection.ltr,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: restoflowBaseTheme(),
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  group('RestoflowTone model', () {
    final scheme = ColorScheme.fromSeed(seedColor: kRestoflowSeedColor);

    test('has the five semantic tones', () {
      expect(RestoflowTone.values, hasLength(5));
    });

    test('each tone resolves to a DISTINCT container colour (separable)', () {
      final containers = {
        for (final tone in RestoflowTone.values) tone.style(scheme).container,
      };
      expect(containers, hasLength(RestoflowTone.values.length));
    });
  });

  group('RestoflowStatusPill', () {
    testWidgets('renders its label', (tester) async {
      await _pump(tester, const RestoflowStatusPill(label: 'active'));
      expect(find.text('active'), findsOneWidget);
    });

    testWidgets('renders the optional leading icon', (tester) async {
      await _pump(
        tester,
        const RestoflowStatusPill(
          label: 'live',
          tone: RestoflowTone.success,
          icon: Icons.bolt_outlined,
        ),
      );
      expect(find.byIcon(Icons.bolt_outlined), findsOneWidget);
    });

    testWidgets('every tone renders without error', (tester) async {
      for (final tone in RestoflowTone.values) {
        await _pump(tester, RestoflowStatusPill(label: tone.name, tone: tone));
        expect(find.text(tone.name), findsOneWidget);
      }
    });

    testWidgets('a non-dense pill uses larger text than the dense default '
        '(RF-141E)', (tester) async {
      await _pump(tester, const RestoflowStatusPill(label: 'ready'));
      final denseSize = tester.widget<Text>(find.text('ready')).style?.fontSize;

      await _pump(
        tester,
        const RestoflowStatusPill(label: 'ready', dense: false),
      );
      final largeSize = tester.widget<Text>(find.text('ready')).style?.fontSize;

      expect(denseSize, isNotNull);
      expect(largeSize, isNotNull);
      expect(largeSize, greaterThan(denseSize!));
    });
  });

  group('RestoflowNoticeBanner', () {
    testWidgets('renders the body (no title)', (tester) async {
      await _pump(tester, const RestoflowNoticeBanner(body: 'Demo data.'));
      expect(find.text('Demo data.'), findsOneWidget);
    });

    testWidgets('renders an optional title above the body', (tester) async {
      await _pump(
        tester,
        const RestoflowNoticeBanner(
          title: 'Heads up',
          body: 'Live · limited.',
          tone: RestoflowTone.warning,
        ),
      );
      expect(find.text('Heads up'), findsOneWidget);
      expect(find.text('Live · limited.'), findsOneWidget);
    });

    testWidgets('uses the tone default icon, overridable', (tester) async {
      await _pump(
        tester,
        const RestoflowNoticeBanner(body: 'x', tone: RestoflowTone.danger),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await _pump(
        tester,
        const RestoflowNoticeBanner(body: 'x', icon: Icons.campaign_outlined),
      );
      expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    });
  });

  group('RestoflowMetricCard', () {
    testWidgets('renders label + value, and the optional caption + icon', (
      tester,
    ) async {
      await _pump(
        tester,
        const RestoflowMetricCard(
          label: 'Orders',
          value: '215',
          caption: 'Active: 2',
          icon: Icons.receipt_long_outlined,
        ),
      );
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('215'), findsOneWidget);
      expect(find.text('Active: 2'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    });

    testWidgets('a semantic tone renders without error', (tester) async {
      await _pump(
        tester,
        const RestoflowMetricCard(
          label: 'Alerts',
          value: '2',
          tone: RestoflowTone.danger,
          icon: Icons.warning_amber_outlined,
        ),
      );
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('is display-only (no ink) without onTap (RF-141D)', (
      tester,
    ) async {
      await _pump(
        tester,
        const RestoflowMetricCard(label: 'Orders', value: '7'),
      );
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets(
      'becomes tappable with hover/ripple when onTap is set (RF-141D)',
      (tester) async {
        var taps = 0;
        await _pump(
          tester,
          RestoflowMetricCard(label: 'Orders', value: '7', onTap: () => taps++),
        );
        expect(find.byType(InkWell), findsOneWidget);
        await tester.tap(find.byType(RestoflowMetricCard));
        expect(taps, 1);
      },
    );
  });

  group('RestoflowSectionCard', () {
    testWidgets('renders title, subtitle, action and children', (tester) async {
      await _pump(
        tester,
        const RestoflowSectionCard(
          title: 'Organizations',
          subtitle: '3 total',
          action: Icon(Icons.more_horiz),
          children: [Text('Bistro Group')],
        ),
      );
      expect(find.text('Organizations'), findsOneWidget);
      expect(find.text('3 total'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.text('Bistro Group'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('with no title shows children and no divider', (tester) async {
      await _pump(tester, const RestoflowSectionCard(children: [Text('row')]));
      expect(find.text('row'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    });
  });

  testWidgets('components render right-to-left without error', (tester) async {
    await _pump(
      tester,
      const RestoflowSectionCard(
        title: 'تقرير',
        children: [
          RestoflowStatusPill(label: 'نشط', tone: RestoflowTone.success),
          RestoflowNoticeBanner(
            body: 'بيانات تجريبية',
            tone: RestoflowTone.info,
          ),
          RestoflowMetricCard(label: 'الطلبات', value: '215'),
        ],
      ),
      direction: TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('تقرير'), findsOneWidget);
    expect(find.text('نشط'), findsOneWidget);
  });
}
