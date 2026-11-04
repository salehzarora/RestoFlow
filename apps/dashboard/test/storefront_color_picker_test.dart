import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_color_picker.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _sample = StorefrontColorSample(
  background: '#211a16',
  accent: '#eab082',
  text: '#fff1da',
  buttonText: '#211a16',
);

Future<void> _open(
  WidgetTester tester, {
  String locale = 'en',
  String? initial = '#336699',
  String? reset = '#13322a',
  StorefrontColorRole role = StorefrontColorRole.background,
  ValueChanged<StorefrontColorChoice?>? result,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: Locale(locale),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result?.call(
              await showModalBottomSheet<StorefrontColorChoice>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => StorefrontColorPickerSheet(
                  title: 'Storefront color',
                  initialHex: initial,
                  resetHex: reset,
                  role: role,
                  sample: _sample,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  // Always supply a callback: null-aware calls do not evaluate their arguments.
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Color _swatch(WidgetTester tester, String key) =>
    (tester
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(Key(key)),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration)
        .color!;

void main() {
  test('persistence accepts only complete opaque six-digit HEX', () {
    for (final invalid in [
      null,
      '',
      'red',
      '#fff',
      '#11223344',
      '112233',
      '#12345',
      '#12345g',
      '#112233\n',
    ]) {
      expect(storefrontParseColor(invalid), isNull, reason: '$invalid');
    }
    expect(storefrontFormatColor(storefrontParseColor('#AaBbCc')!), '#aabbcc');
  });

  for (final role in StorefrontColorRole.values) {
    testWidgets(
      '$role touch selection previews locally and Apply returns HEX',
      (tester) async {
        final results = <StorefrontColorChoice?>[];
        await _open(tester, role: role, result: results.add);
        expect(find.byKey(const Key('storefront-color-hex')), findsNothing);
        final field = find.byKey(const Key('storefront-color-sv-field'));
        await tester.ensureVisible(field);
        final rect = tester.getRect(field);
        expect(rect.width, rect.height, reason: 'saturation/value is a square');
        await tester.tapAt(
          Offset(rect.left + rect.width * .8, rect.top + rect.height * .25),
        );
        await tester.pumpAndSettle();
        expect(results, isEmpty, reason: 'live preview has no parent callback');
        final next = _swatch(tester, 'storefront-colorNew-swatch');
        expect(next, isNot(const Color(0xff336699)));
        expect(
          _swatch(tester, 'storefront-colorCurrent-swatch'),
          const Color(0xff336699),
        );
        await _tap(tester, 'storefront-color-apply');
        expect(results.single!.hex, storefrontFormatColor(next));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Cancel and dismiss return no choice after a visual edit', (
    tester,
  ) async {
    final results = <StorefrontColorChoice?>[];
    await _open(tester, result: results.add);
    await _tap(tester, 'storefront-color-restore');
    await _tap(tester, 'storefront-color-cancel');
    expect(results, [null]);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _tap(tester, 'storefront-color-restore');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(results, [null, null]);
  });

  testWidgets('inherit is explicit and only Apply returns null HEX', (
    tester,
  ) async {
    final results = <StorefrontColorChoice?>[];
    await _open(
      tester,
      role: StorefrontColorRole.text,
      initial: '#ff0000',
      reset: null,
      result: results.add,
    );
    await _tap(tester, 'storefront-color-restore');
    expect(find.byKey(const Key('storefront-color-inherited')), findsOneWidget);
    expect(results, isEmpty);
    await _tap(tester, 'storefront-color-apply');
    expect(results.single, isNotNull);
    expect(results.single!.hex, isNull);
  });

  testWidgets('Advanced keeps focus and caret through every partial HEX edit', (
    tester,
  ) async {
    final results = <StorefrontColorChoice?>[];
    await _open(tester, result: results.add);
    await _tap(tester, 'storefront-color-advanced');
    final field = find.byKey(const Key('storefront-color-hex'));
    await tester.showKeyboard(field);
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final state = tester.state<EditableTextState>(editable);
    final focus = state.widget.focusNode;
    for (var length = 0; length <= 7; length++) {
      final hex = '#aB12eF'.substring(0, length);
      tester.testTextInput.enterText(hex);
      await tester.pumpAndSettle();
      expect(tester.state<EditableTextState>(editable), same(state));
      expect(focus.hasFocus, isTrue);
      expect(state.widget.controller.selection.baseOffset, length);
      expect(
        tester
                .widget<FilledButton>(
                  find.byKey(const Key('storefront-color-apply')),
                )
                .onPressed !=
            null,
        length == 7,
      );
    }
    tester.testTextInput.enterText('#aB12eF88');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('storefront-color-apply')))
          .onPressed,
      isNull,
      reason: 'alpha must never be truncated into an accepted color',
    );
    tester.testTextInput.enterText('#aB12eF');
    await tester.pumpAndSettle();
    await _tap(tester, 'storefront-color-apply');
    expect(results.single!.hex, '#ab12ef');
  });

  for (final locale in ['en', 'ar', 'he']) {
    testWidgets('$locale keyboard arrows follow physical hue and SV axes', (
      tester,
    ) async {
      await _open(tester, locale: locale, result: (_) {});
      final picker = find.byKey(const Key('storefront-color-picker'));
      expect(
        Directionality.of(tester.element(picker)),
        locale == 'en' ? TextDirection.ltr : TextDirection.rtl,
      );
      final sv = find.byKey(const Key('storefront-color-sv-field'));
      await tester.ensureVisible(sv);
      Focus.of(tester.element(sv)).requestFocus();
      await tester.pumpAndSettle();
      final marker = find.byKey(const Key('storefront-color-sv-marker'));
      final before = tester.getCenter(marker);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(tester.getCenter(marker).dx, greaterThan(before.dx));
      expect(tester.getCenter(marker).dy, lessThan(before.dy));
      final hue = find.byKey(const Key('storefront-color-hue-rail'));
      await tester.ensureVisible(hue);
      Focus.of(tester.element(hue)).requestFocus();
      await tester.pumpAndSettle();
      final hueMarker = find.byKey(const Key('storefront-color-hue-marker'));
      final oldHue = tester.getCenter(hueMarker).dx;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.getCenter(hueMarker).dx, greaterThan(oldHue));
      await _tap(tester, 'storefront-color-advanced');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-color-hex')))
            .textDirection,
        TextDirection.ltr,
      );
      expect(
        tester.widget<Text>(find.text('#RRGGBB')).textDirection,
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('vertical touch drag changes value instead of scrolling sheet', (
    tester,
  ) async {
    await _open(tester, result: (_) {});
    final field = find.byKey(const Key('storefront-color-sv-field'));
    await tester.ensureVisible(field);
    final before = tester.getTopLeft(field);
    final rect = tester.getRect(field);
    final gesture = await tester.startGesture(
      rect.center,
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(Offset(0, rect.height * .3));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(field), before);
    final color = _swatch(tester, 'storefront-colorNew-swatch');
    expect(HSVColor.fromColor(color).value, closeTo(.2, .01));
  });

  for (final locale in ['ar', 'he', 'en']) {
    testWidgets('$locale 390px at large text keeps actions reachable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, locale: locale, textScale: 1.5, result: (_) {});
      await _tap(tester, 'storefront-color-advanced');
      expect(
        find.byKey(const Key('storefront-color-apply')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('storefront-color-cancel')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
