import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// RF-125 — the shared calm [RestoflowPageHeader]: backward-compatible content,
/// a semantic header, an optional warm hairline boundary, and actions that stack
/// safely (no overflow) at narrow widths in both LTR and RTL.

Widget _wrap(
  Widget child, {
  TextDirection dir = TextDirection.ltr,
  double width = 800,
}) => MaterialApp(
  theme: restoflowBaseTheme(),
  home: Directionality(
    textDirection: dir,
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('renders title, subtitle, icon and actions', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RestoflowPageHeader(
          title: 'Devices',
          subtitle: 'Pair POS and kitchen displays',
          icon: Icons.devices_other_outlined,
          actions: [FilledButton(onPressed: () {}, child: const Text('New'))],
        ),
      ),
    );
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Pair POS and kitchen displays'), findsOneWidget);
    expect(find.byIcon(Icons.devices_other_outlined), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('is exposed as a semantic header', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const RestoflowPageHeader(title: 'Orders')));
    expect(
      tester.getSemantics(find.byType(RestoflowPageHeader)),
      isSemantics(isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('bordered header renders without exception', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RestoflowPageHeader(
          title: 'Activity log',
          subtitle: 'Who did what, when',
          icon: Icons.history_outlined,
          bordered: true,
          padding: EdgeInsetsDirectional.all(RestoflowSpacing.lg),
        ),
      ),
    );
    expect(find.text('Activity log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dir in TextDirection.values) {
    final tag = dir == TextDirection.rtl ? 'RTL' : 'LTR';

    testWidgets('actions stack without overflow at a narrow width ($tag)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          dir: dir,
          width: 360,
          RestoflowPageHeader(
            title: 'A rather long operational page title that needs room',
            subtitle: 'And a supporting subtitle line beneath it',
            icon: Icons.receipt_long_outlined,
            bordered: true,
            padding: const EdgeInsetsDirectional.all(RestoflowSpacing.lg),
            actions: [
              FilledButton(onPressed: () {}, child: const Text('Primary')),
              OutlinedButton(onPressed: () {}, child: const Text('Secondary')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Primary'), findsOneWidget);
      expect(find.text('Secondary'), findsOneWidget);
    });

    testWidgets(
      'actions sit trailing without overflow at a wide width ($tag)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            dir: dir,
            width: 1100,
            RestoflowPageHeader(
              title: 'Orders',
              icon: Icons.receipt_long_outlined,
              actions: [
                FilledButton(onPressed: () {}, child: const Text('Primary')),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Primary'), findsOneWidget);
      },
    );
  }
}
