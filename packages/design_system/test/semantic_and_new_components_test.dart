import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

Widget _app(Widget child, {bool themed = true, TextDirection? direction}) {
  final body = direction == null
      ? child
      : Directionality(textDirection: direction, child: child);
  return MaterialApp(
    theme: themed ? restoflowBaseTheme() : null,
    home: Scaffold(body: body),
  );
}

void main() {
  group('RestoflowSemanticColors', () {
    test('the RestoFlow theme registers the semantic extension', () {
      final theme = restoflowBaseTheme();
      final semantic = theme.extension<RestoflowSemanticColors>();
      expect(semantic, isNotNull);
      expect(semantic, same(RestoflowSemanticColors.light));
      final dark = restoflowBaseTheme(brightness: Brightness.dark);
      expect(
        dark.extension<RestoflowSemanticColors>(),
        same(RestoflowSemanticColors.dark),
      );
    });

    test(
      'tones resolve to TRUE distinct semantic containers under the theme',
      () {
        final theme = restoflowBaseTheme();
        final containers = RestoflowTone.values
            .map((t) => t.styleOf(theme).container)
            .toSet();
        expect(containers, hasLength(RestoflowTone.values.length));
        // The point of the sprint: success is green-family, warning amber,
        // danger red, info blue — not seed-derived pastels.
        expect(
          RestoflowTone.success.styleOf(theme).container,
          RestoflowSemanticColors.light.successContainer,
        );
        expect(
          RestoflowTone.warning.styleOf(theme).container,
          RestoflowSemanticColors.light.warningContainer,
        );
        expect(
          RestoflowTone.danger.styleOf(theme).container,
          RestoflowSemanticColors.light.dangerContainer,
        );
        expect(
          RestoflowTone.info.styleOf(theme).container,
          RestoflowSemanticColors.light.infoContainer,
        );
      },
    );

    test('styleOf falls back to scheme roles without the extension '
        '(bare-MaterialApp test harnesses keep working)', () {
      final bare = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kRestoflowSeedColor),
      );
      expect(bare.extension<RestoflowSemanticColors>(), isNull);
      for (final tone in RestoflowTone.values) {
        expect(
          tone.styleOf(bare).container,
          tone.style(bare.colorScheme).container,
        );
      }
    });

    test('lerp and copyWith are total (no null fields)', () {
      final mid = RestoflowSemanticColors.light.lerp(
        RestoflowSemanticColors.dark,
        0.5,
      );
      expect(mid.success, isNot(RestoflowSemanticColors.light.success));
      final copied = RestoflowSemanticColors.light.copyWith(
        accent: const Color(0xFF000000),
      );
      expect(copied.accent, const Color(0xFF000000));
      expect(copied.success, RestoflowSemanticColors.light.success);
    });
  });

  group('expanded tokens', () {
    test('new scales are positive and ordered', () {
      expect(RestoflowSpacing.xxs, greaterThan(0));
      expect(RestoflowSpacing.xxs < RestoflowSpacing.xs, isTrue);
      expect(RestoflowRadii.lg < RestoflowRadii.xl, isTrue);
      expect(RestoflowRadii.xl < RestoflowRadii.pill, isTrue);
      expect(RestoflowIconSizes.xs < RestoflowIconSizes.sm, isTrue);
      expect(RestoflowIconSizes.sm < RestoflowIconSizes.md, isTrue);
      expect(RestoflowIconSizes.md < RestoflowIconSizes.lg, isTrue);
      expect(RestoflowIconSizes.lg < RestoflowIconSizes.xl, isTrue);
      expect(RestoflowIconSizes.xl < RestoflowIconSizes.hero, isTrue);
      expect(
        RestoflowBreakpoints.compact < RestoflowBreakpoints.posTwoPane,
        isTrue,
      );
      expect(
        RestoflowBreakpoints.posTwoPane < RestoflowBreakpoints.wide,
        isTrue,
      );
      // The exact values the widget-test corpus was written against.
      expect(RestoflowBreakpoints.wide, 900);
      expect(RestoflowBreakpoints.posTwoPane, 820);
      expect(RestoflowBreakpoints.compact, 560);
      expect(RestoflowDurations.fast < RestoflowDurations.base, isTrue);
      expect(RestoflowDurations.base < RestoflowDurations.slow, isTrue);
    });
  });

  group('theme coverage', () {
    test('inputs, dialogs, sheets, buttons and typography are themed', () {
      final theme = restoflowBaseTheme();
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
      expect(theme.bottomSheetTheme.shape, isA<RoundedRectangleBorder>());
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.textTheme.titleLarge?.fontWeight, FontWeight.w700);
      expect(theme.textTheme.headlineSmall?.fontWeight, FontWeight.w800);
      // Arabic-safe: the scale carries no letter-spacing.
      expect(theme.textTheme.titleLarge?.letterSpacing, 0);
    });
  });

  group('RestoflowStateView', () {
    testWidgets('renders icon, title, message and actions', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _app(
          RestoflowStateView(
            icon: Icons.inbox_outlined,
            title: 'Nothing here',
            message: 'Add your first item to get started.',
            actions: [
              FilledButton(onPressed: () => tapped++, child: const Text('Add')),
            ],
          ),
        ),
      );
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Add your first item to get started.'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      await tester.tap(find.text('Add'));
      expect(tapped, 1);
      // Deliberately not Card-based (an empty-state test in the dashboard
      // asserts find.byType(Card) findsNothing).
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('spinner mode shows exactly one progress indicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const RestoflowStateView(showSpinner: true, title: 'Loading')),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('danger tone renders without the brand-green icon color', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const RestoflowStateView(
            icon: Icons.error_outline,
            title: 'Failed',
            tone: RestoflowTone.danger,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, RestoflowSemanticColors.light.onDangerContainer);
    });

    testWidgets('builds in a bare harness (no RestoFlow theme)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const RestoflowStateView(icon: Icons.info_outline, title: 'Plain'),
          themed: false,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Plain'), findsOneWidget);
    });
  });

  group('RestoflowPageHeader', () {
    testWidgets('renders title, subtitle, icon and actions', (tester) async {
      await tester.pumpWidget(
        _app(
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
    });
  });

  group('RestoflowStepTile', () {
    testWidgets('numbered while pending, check + strike-through when done', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              RestoflowStepTile(index: 1, title: 'Add a menu item'),
              RestoflowStepTile(index: 2, title: 'Pair a device', done: true),
            ],
          ),
        ),
      );
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing); // replaced by the check
      expect(find.byIcon(Icons.check), findsOneWidget);
      final doneTitle = tester.widget<Text>(find.text('Pair a device'));
      expect(doneTitle.style?.decoration, TextDecoration.lineThrough);
    });
  });

  group('RestoflowNumericKeypad', () {
    testWidgets('emits digits and backspace; disabled blocks input', (
      tester,
    ) async {
      final digits = <String>[];
      var backspaces = 0;
      await tester.pumpWidget(
        _app(
          RestoflowNumericKeypad(
            onDigit: digits.add,
            onBackspace: () => backspaces++,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('keypad-4')));
      await tester.tap(find.byKey(const Key('keypad-0')));
      await tester.tap(find.byKey(const Key('keypad-backspace')));
      expect(digits, ['4', '0']);
      expect(backspaces, 1);

      await tester.pumpWidget(
        _app(
          RestoflowNumericKeypad(
            onDigit: digits.add,
            onBackspace: () => backspaces++,
            enabled: false,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('keypad-4')));
      expect(digits, ['4', '0']); // unchanged
    });
  });

  group('RestoflowLanguageSelector', () {
    testWidgets('keeps the language-selector contract and marks the current '
        'locale', (tester) async {
      Locale? selected;
      await tester.pumpWidget(
        _app(
          RestoflowLanguageSelector(
            entries: const [
              (Locale('en'), 'English'),
              (Locale('ar'), 'العربية'),
              (Locale('he'), 'עברית'),
            ],
            current: const Locale('ar'),
            onSelected: (l) => selected = l,
          ),
        ),
      );
      expect(find.byKey(const Key('language-selector')), findsOneWidget);
      expect(find.byIcon(Icons.translate), findsOneWidget);
      await tester.tap(find.byKey(const Key('language-selector')));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('עברית'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget); // current = ar
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(selected, const Locale('en'));
    });
  });

  group('misc components', () {
    testWidgets('brand mark, code block, skeleton and inline spinner render '
        'under RTL without exceptions', (tester) async {
      await tester.pumpWidget(
        _app(
          const SingleChildScrollView(
            child: Column(
              children: [
                RestoflowBrandMark(title: 'ريستوفلو', tagline: 'نظام المطاعم'),
                RestoflowCodeBlock(
                  lines: ['RESTOFLOW_DEMO_MODE=false', 'PORT=57026'],
                ),
                RestoflowSkeleton(width: 120),
                RestoflowInlineSpinner(),
              ],
            ),
          ),
          direction: TextDirection.rtl,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('ريستوفلو'), findsOneWidget);
      final code = tester.widget<Text>(find.text('RESTOFLOW_DEMO_MODE=false'));
      expect(code.textDirection, TextDirection.ltr); // code stays LTR
    });

    testWidgets('button style helpers resolve semantic colors', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final danger = RestoflowButtonStyles.danger(ctx);
      expect(
        danger.backgroundColor?.resolve({}),
        RestoflowSemanticColors.light.danger,
      );
      final success = RestoflowButtonStyles.success(ctx);
      expect(
        success.backgroundColor?.resolve({}),
        RestoflowSemanticColors.light.success,
      );
      final big = RestoflowButtonStyles.big(ctx);
      expect(big.minimumSize?.resolve({})?.height, 52);
    });
  });
}
