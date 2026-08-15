import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/design/pos_color_utils.dart';
import 'package:restoflow_pos/src/design/pos_theme.dart';
import 'package:restoflow_pos/src/design/pos_visual_tokens.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';
import 'package:restoflow_pos/src/widgets/pos_color_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DEVICE-THEME-COLOR-PICKER-032 — the VISUAL color picker behind the custom
/// device theme.
///
/// The contract this ticket adds: an owner who has never heard of a hex code
/// can set both custom colors by eye, and the pair still persists through the
/// SAME `custom:RRGGBB:RRGGBB` wire and the SAME per-device key that
/// POS-CUSTOM-DEVICE-THEME-010 shipped. Nothing about the stored format, the
/// presets, or the draft/Apply/Cancel/Reset semantics moves.

// ---------------------------------------------------------------------------
// Harnesses
// ---------------------------------------------------------------------------

/// Result of the last picker route — set by the host button below.
Color? _picked;

/// Whether the picker route has resolved at all (a cancel returns null, which
/// is indistinguishable from "never opened" without this).
bool _resolved = false;

/// Pushes the picker as a REAL route, so confirm/cancel exercise the actual
/// `Navigator.pop` contract rather than a pumped-in-place widget.
Future<void> _openPicker(
  WidgetTester tester, {
  required Color initial,
  Locale locale = const Locale('en'),
}) async {
  _picked = null;
  _resolved = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: locale,
      theme: posPremiumTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open-picker'),
              onPressed: () async {
                final l10n = AppLocalizations.of(context);
                final result = await showPosColorPicker(
                  context,
                  initial: initial,
                  title: l10n.posDeviceThemeCustomPrimaryLabel,
                );
                _picked = result;
                _resolved = true;
              },
              child: const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _tapVisible(tester, const Key('open-picker'));
}

/// The device-settings sheet harness (mirrors pos_custom_device_theme_010).
Widget _settingsApp({
  Locale locale = const Locale('en'),
  String segment = 'test-dev',
}) => ProviderScope(
  overrides: [posPrinterScopeSegmentProvider.overrideWith((ref) => segment)],
  child: MaterialApp(
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    locale: locale,
    theme: posPremiumTheme(),
    home: const Scaffold(body: PosDeviceSettingsSheet()),
  ),
);

Future<void> _scrollSheetTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('device-settings-sheet')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openCustomEditor(WidgetTester tester) async {
  await _scrollSheetTo(tester, find.byKey(const Key('device-theme-custom')));
  await _tapVisible(tester, const Key('device-theme-custom'));
}

/// The color a keyed [Container] actually paints.
Color _paintedColor(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(find.byKey(key));
  return (container.decoration! as BoxDecoration).color!;
}

/// The 56dp swatch inside a custom-theme tile: the first descendant Container
/// that paints a fill (the tile's own frame draws a border only).
Color _tileColor(WidgetTester tester, String key) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(Key(key)),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).color != null,
          ),
        )
        .first,
  );
  return (container.decoration! as BoxDecoration).color!;
}

Color _pickerColor(WidgetTester tester) =>
    _paintedColor(tester, const Key('pos-color-picker-preview'));

/// Taps a control after scrolling it into view. Both the settings sheet and
/// the picker scroll on short viewports (a 1024x600 tablet in landscape shows
/// about 80% of the picker), so a bare tap would silently miss — leaving the
/// route open and the assertion measuring the wrong thing.
Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

/// Taps inside a keyed box at the given fractional position.
Future<void> _tapFraction(
  WidgetTester tester,
  Key key,
  double fx,
  double fy,
) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  final rect = tester.getRect(find.byKey(key));
  await tester.tapAt(
    Offset(rect.left + rect.width * fx, rect.top + rect.height * fy),
  );
  await tester.pumpAndSettle();
}

/// Channel-wise comparison — the HSV round-trip rounds to 8-bit.
void _expectColorNear(Color actual, Color expected, {int tolerance = 2}) {
  final a = actual.toARGB32();
  final e = expected.toARGB32();
  for (final shift in [16, 8, 0]) {
    expect(
      ((a >> shift) & 0xFF) - ((e >> shift) & 0xFF),
      inInclusiveRange(-tolerance, tolerance),
      reason:
          'channel $shift differs: ${posFormatHexColor(actual)} vs '
          '${posFormatHexColor(expected)}',
    );
  }
}

/// Collects paint-time overflow (which never reaches takeException) scoped to
/// the two files this ticket owns — the shared sheet also hosts
/// native_printing's saved-printers section, whose PRE-EXISTING 390/ar
/// overflow belongs to its own ticket.
Future<List<String>> _overflowsDuring(Future<void> Function() body) async {
  final found = <String>[];
  final prior = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) {
      found.add(details.toString());
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = prior;
  }
  return found
      .where(
        (d) =>
            d.contains('device_settings_sheet.dart') ||
            d.contains('pos_color_picker_sheet.dart'),
      )
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const seed = Color(0xFF2C5F8A); // sky — mid hue, mid saturation, mid value

  group('A. The visual picker', () {
    testWidgets('A1. opens on the color it was handed and states it both as a '
        'swatch and as quiet secondary hex', (tester) async {
      await _openPicker(tester, initial: seed);
      expect(find.byKey(const Key('pos-color-picker')), findsOneWidget);
      _expectColorNear(_pickerColor(tester), seed);
      expect(find.text(posFormatHexColor(seed)), findsOneWidget);
    });

    testWidgets('A2. every visual control is present — palette, field, hue '
        'rail and shade steps', (tester) async {
      await _openPicker(tester, initial: seed);
      expect(
        find.byKey(const Key('pos-color-picker-sv-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pos-color-picker-hue-rail')),
        findsOneWidget,
      );
      for (final swatch in kPosColorPickerPalette) {
        final hex = posFormatHexColor(swatch).substring(1);
        expect(
          find.byKey(Key('pos-color-picker-swatch-$hex')),
          findsOneWidget,
          reason: 'palette entry $hex missing',
        );
      }
      for (var i = 0; i < kPosColorPickerShadeStops.length; i++) {
        expect(find.byKey(Key('pos-color-picker-shade-$i')), findsOneWidget);
      }
    });

    testWidgets('A3. a palette tap selects that EXACT color and marks it', (
      tester,
    ) async {
      await _openPicker(tester, initial: seed);
      const target = Color(0xFFA62B2B); // crimson
      final key = Key(
        'pos-color-picker-swatch-${posFormatHexColor(target).substring(1)}',
      );
      await _tapVisible(tester, key);
      _expectColorNear(_pickerColor(tester), target);
      // The chosen swatch carries a check — a marker, not just a fill.
      expect(
        find.descendant(
          of: find.byKey(key),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
    });

    testWidgets('A4. tapping the saturation/brightness field sets saturation '
        'from x and brightness from y, at the SAME hue', (tester) async {
      await _openPicker(tester, initial: seed);
      final hue = HSVColor.fromColor(seed).hue;
      await _tapFraction(
        tester,
        const Key('pos-color-picker-sv-field'),
        0.75,
        0.25,
      );
      final got = _pickerColor(tester);
      _expectColorNear(got, HSVColor.fromAHSV(1, hue, 0.75, 0.75).toColor());
      expect(HSVColor.fromColor(got).hue, closeTo(hue, 1.0));
    });

    testWidgets('A5. dragging down the field darkens without changing hue — '
        'the enclosing scrollable never steals the gesture', (tester) async {
      await _openPicker(tester, initial: seed);
      final before = _pickerColor(tester);
      await tester.ensureVisible(
        find.byKey(const Key('pos-color-picker-sv-field')),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find.byKey(const Key('pos-color-picker-sv-field')),
      );
      await tester.dragFrom(rect.center, Offset(0, rect.height * 0.45));
      await tester.pumpAndSettle();
      final after = _pickerColor(tester);
      expect(
        after.computeLuminance(),
        lessThan(before.computeLuminance()),
        reason: 'a downward drag must darken, not scroll the sheet',
      );
      // 8-bit quantisation moves the MEASURED hue a little once the colour
      // is dark; the instrument itself keeps hue exactly.
      expect(
        HSVColor.fromColor(after).hue,
        closeTo(HSVColor.fromColor(before).hue, 4.0),
      );
    });

    testWidgets('A6. the hue rail re-hues while keeping saturation and '
        'brightness', (tester) async {
      await _openPicker(tester, initial: seed);
      final before = HSVColor.fromColor(_pickerColor(tester));
      await _tapFraction(
        tester,
        const Key('pos-color-picker-hue-rail'),
        0.9,
        0.5,
      );
      final after = HSVColor.fromColor(_pickerColor(tester));
      expect(after.hue, closeTo(324, 4));
      expect(after.saturation, closeTo(before.saturation, 0.02));
      expect(after.value, closeTo(before.value, 0.02));
    });

    testWidgets('A7. the shade steps go lighter and darker at a FIXED hue and '
        'saturation', (tester) async {
      await _openPicker(tester, initial: seed);
      final start = HSVColor.fromColor(_pickerColor(tester));

      await _tapVisible(tester, const Key('pos-color-picker-shade-0'));
      final lightest = HSVColor.fromColor(_pickerColor(tester));
      expect(lightest.value, closeTo(kPosColorPickerShadeStops.first, 0.01));

      await _tapVisible(
        tester,
        Key('pos-color-picker-shade-${kPosColorPickerShadeStops.length - 1}'),
      );
      final darkest = HSVColor.fromColor(_pickerColor(tester));
      expect(darkest.value, closeTo(kPosColorPickerShadeStops.last, 0.01));
      expect(darkest.value, lessThan(lightest.value));
      for (final step in [lightest, darkest]) {
        expect(step.hue, closeTo(start.hue, 4.0));
        expect(step.saturation, closeTo(start.saturation, 0.03));
      }
    });

    testWidgets('A8. both instruments carry a selection marker that survives '
        'a white bed AND a black bed — a white ring inside a dark ring', (
      tester,
    ) async {
      await _openPicker(tester, initial: seed);
      for (final key in const [
        Key('pos-color-picker-sv-marker'),
        Key('pos-color-picker-hue-marker'),
      ]) {
        expect(find.byKey(key), findsOneWidget);
        final outer = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byKey(key),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final dark = (outer.decoration as BoxDecoration).border!.top.color;
        expect(dark.a, greaterThan(0.4), reason: 'dark ring must be opaque');
        expect(dark.computeLuminance(), lessThan(0.2));
        final inner = tester.widget<Container>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(Container),
          ),
        );
        expect(
          (inner.decoration! as BoxDecoration).border!.top.color,
          Colors.white,
        );
      }
    });

    testWidgets('A9. the marker tracks the chosen point physically — it does '
        'NOT mirror in Arabic, so it stays on the color it names', (
      tester,
    ) async {
      await _openPicker(tester, initial: seed, locale: const Locale('ar'));
      await _tapFraction(
        tester,
        const Key('pos-color-picker-sv-field'),
        0.8,
        0.3,
      );
      final field = tester.getRect(
        find.byKey(const Key('pos-color-picker-sv-field')),
      );
      final marker = tester.getRect(
        find.byKey(const Key('pos-color-picker-sv-marker')),
      );
      expect(marker.center.dx, closeTo(field.left + field.width * 0.8, 2));
      expect(marker.center.dy, closeTo(field.top + field.height * 0.3, 2));
    });

    testWidgets('A10. Advanced is collapsed by default; opening it reveals a '
        'hex field already synced to the visual choice', (tester) async {
      await _openPicker(tester, initial: seed);
      expect(find.byKey(const Key('pos-color-picker-hex')), findsNothing);
      await _tapVisible(tester, const Key('pos-color-picker-advanced-toggle'));
      final field = tester.widget<TextField>(
        find.byKey(const Key('pos-color-picker-hex')),
      );
      expect(field.controller?.text, posFormatHexColor(seed));

      // ...and it keeps following the visual controls.
      await _tapVisible(tester, const Key('pos-color-picker-shade-0'));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('pos-color-picker-hex')))
            .controller
            ?.text,
        posFormatHexColor(_pickerColor(tester)),
      );
    });

    testWidgets('A11. typing a valid hex under Advanced drives the visual '
        'controls — the sync runs both ways', (tester) async {
      await _openPicker(tester, initial: seed);
      await _tapVisible(tester, const Key('pos-color-picker-advanced-toggle'));
      await tester.enterText(
        find.byKey(const Key('pos-color-picker-hex')),
        '1a3d34',
      );
      await tester.pumpAndSettle();
      _expectColorNear(_pickerColor(tester), const Color(0xFF1A3D34));
      final field = tester.getRect(
        find.byKey(const Key('pos-color-picker-sv-field')),
      );
      final marker = tester.getRect(
        find.byKey(const Key('pos-color-picker-sv-marker')),
      );
      final hsv = HSVColor.fromColor(const Color(0xFF1A3D34));
      expect(
        marker.center.dx,
        closeTo(field.left + field.width * hsv.saturation, 2),
      );
    });

    testWidgets('A12. an invalid hex keeps the EXISTING validation: localized '
        'error, confirm disabled, visual state untouched', (tester) async {
      await _openPicker(tester, initial: seed);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _tapVisible(tester, const Key('pos-color-picker-advanced-toggle'));
      await tester.enterText(
        find.byKey(const Key('pos-color-picker-hex')),
        '#12F',
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.posDeviceThemeCustomInvalidHex), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('pos-color-picker-confirm')),
            )
            .onPressed,
        isNull,
      );
      // The visual controls never followed the garbage.
      _expectColorNear(_pickerColor(tester), seed);
    });

    testWidgets('A13. confirm returns the visually chosen color; cancel '
        'returns nothing at all', (tester) async {
      await _openPicker(tester, initial: seed);
      const target = Color(0xFF146B6B); // teal
      await tester.tap(
        find.byKey(
          Key(
            'pos-color-picker-swatch-${posFormatHexColor(target).substring(1)}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('pos-color-picker-confirm'));
      expect(_resolved, isTrue);
      _expectColorNear(_picked!, target);

      await _openPicker(tester, initial: seed);
      await tester.tap(
        find.byKey(
          Key(
            'pos-color-picker-swatch-${posFormatHexColor(target).substring(1)}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('pos-color-picker-cancel'));
      expect(_resolved, isTrue);
      expect(_picked, isNull);
    });

    testWidgets('A14. every tappable control clears 44dp', (tester) async {
      await _openPicker(tester, initial: seed);
      final keys = <Key>[
        Key(
          'pos-color-picker-swatch-'
          '${posFormatHexColor(kPosColorPickerPalette.first).substring(1)}',
        ),
        const Key('pos-color-picker-shade-0'),
        const Key('pos-color-picker-advanced-toggle'),
        const Key('pos-color-picker-confirm'),
        const Key('pos-color-picker-cancel'),
      ];
      for (final key in keys) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(44), reason: '$key height');
        expect(size.width, greaterThanOrEqualTo(44), reason: '$key width');
      }
    });
  });

  group('B. The custom-theme editor drives the picker', () {
    testWidgets('B1. the editor offers two color TILES and no hex text field '
        'at all', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-secondary-swatch')),
      );
      expect(
        find.byKey(const Key('custom-theme-primary-swatch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('custom-theme-secondary-swatch')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('custom-theme-primary-hex')), findsNothing);
      expect(find.byKey(const Key('custom-theme-secondary-hex')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('custom-theme-editor')),
          matching: find.byType(TextField),
        ),
        findsNothing,
        reason: 'hex must not be the primary interaction any more',
      );
      // The tiles open on the ACTIVE pair (default navy + ember).
      _expectColorNear(
        _tileColor(tester, 'custom-theme-primary-swatch'),
        PosThemePair.navyEmber.primary,
      );
      _expectColorNear(
        _tileColor(tester, 'custom-theme-secondary-swatch'),
        PosThemePair.navyEmber.action,
      );
    });

    testWidgets('B2. choosing a PRIMARY color visually updates the draft tile '
        'and the live preview, and persists nothing yet', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-primary-swatch')),
      );
      await _tapVisible(tester, const Key('custom-theme-primary-swatch'));

      const target = Color(0xFF1A3D34); // forest
      await tester.tap(
        find.byKey(
          Key(
            'pos-color-picker-swatch-${posFormatHexColor(target).substring(1)}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('pos-color-picker-confirm'));

      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-primary-swatch')),
      );
      _expectColorNear(
        _tileColor(tester, 'custom-theme-primary-swatch'),
        target,
      );
      // The secondary half is untouched.
      _expectColorNear(
        _tileColor(tester, 'custom-theme-secondary-swatch'),
        PosThemePair.navyEmber.action,
      );
      // The preview repainted with the new pair...
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-preview')),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('custom-theme-preview')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).color == target,
          ),
        ),
        findsWidgets,
      );
      // ...but nothing was written.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('restoflow.pos.device_theme.test-dev'), isNull);
    });

    testWidgets('B3. choosing a SECONDARY color updates only that half', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-secondary-swatch')),
      );
      await _tapVisible(tester, const Key('custom-theme-secondary-swatch'));

      const target = Color(0xFFD89A2B); // saffron
      await tester.tap(
        find.byKey(
          Key(
            'pos-color-picker-swatch-${posFormatHexColor(target).substring(1)}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('pos-color-picker-confirm'));

      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-secondary-swatch')),
      );
      _expectColorNear(
        _tileColor(tester, 'custom-theme-secondary-swatch'),
        target,
      );
      _expectColorNear(
        _tileColor(tester, 'custom-theme-primary-swatch'),
        PosThemePair.navyEmber.primary,
      );
    });

    testWidgets('B4. cancelling the picker leaves the draft exactly where it '
        'was', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-primary-swatch')),
      );
      final before = _tileColor(tester, 'custom-theme-primary-swatch');
      await _tapVisible(tester, const Key('custom-theme-primary-swatch'));
      // Move the picker somewhere obviously different, THEN cancel.
      await _tapVisible(tester, const Key('pos-color-picker-swatch-A62B2B'));
      await _tapVisible(tester, const Key('pos-color-picker-cancel'));

      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-primary-swatch')),
      );
      expect(_tileColor(tester, 'custom-theme-primary-swatch'), before);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('restoflow.pos.device_theme.test-dev'), isNull);
    });

    testWidgets('B5. HEX KNOWLEDGE IS NOT REQUIRED: two visual choices plus '
        'Apply persist the EXISTING custom wire, with zero characters typed', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);

      for (final (tile, target) in const [
        ('custom-theme-primary-swatch', Color(0xFF3B2A44)), // aubergine
        ('custom-theme-secondary-swatch', Color(0xFFD9642B)), // ember
      ]) {
        await _scrollSheetTo(tester, find.byKey(Key(tile)));
        await _tapVisible(tester, Key(tile));
        await tester.tap(
          find.byKey(
            Key(
              'pos-color-picker-swatch-'
              '${posFormatHexColor(target).substring(1)}',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tapVisible(tester, const Key('pos-color-picker-confirm'));
      }

      await _scrollSheetTo(tester, find.byKey(const Key('custom-theme-apply')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('custom-theme-apply')))
            .onPressed,
        isNotNull,
        reason: 'Apply must never depend on typed input',
      );
      await _tapVisible(tester, const Key('custom-theme-apply'));

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.test-dev'),
        'custom:3B2A44:D9642B',
        reason: 'the stored format must not change',
      );
    });

    testWidgets('B6. Cancel restores the PREVIOUSLY SAVED colors, discarding '
        'the visual draft', (tester) async {
      SharedPreferences.setMockInitialValues({
        'restoflow.pos.device_theme.test-dev': 'custom:0E2A3F:B9822D',
      });
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-primary-swatch')),
      );
      _expectColorNear(
        _tileColor(tester, 'custom-theme-primary-swatch'),
        const Color(0xFF0E2A3F),
      );

      await _tapVisible(tester, const Key('custom-theme-primary-swatch'));
      await _tapVisible(tester, const Key('pos-color-picker-swatch-A62B2B'));
      await _tapVisible(tester, const Key('pos-color-picker-confirm'));
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-primary-swatch')),
      );
      _expectColorNear(
        _tileColor(tester, 'custom-theme-primary-swatch'),
        const Color(0xFFA62B2B),
      );

      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-cancel')),
      );
      await _tapVisible(tester, const Key('custom-theme-cancel'));

      // The pair is custom, so the editor stays open — reseeded to the SAVED
      // colors, and nothing was written.
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('custom-theme-primary-swatch')),
      );
      _expectColorNear(
        _tileColor(tester, 'custom-theme-primary-swatch'),
        const Color(0xFF0E2A3F),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.test-dev'),
        'custom:0E2A3F:B9822D',
      );
    });

    testWidgets('B7. Reset still restores the default preset, unchanged', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'restoflow.pos.device_theme.test-dev': 'custom:0E2A3F:B9822D',
      });
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      await _scrollSheetTo(tester, find.byKey(const Key('custom-theme-reset')));
      await _tapVisible(tester, const Key('custom-theme-reset'));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.test-dev'),
        'navy_ember',
      );
      expect(find.byKey(const Key('custom-theme-editor')), findsNothing);
    });

    testWidgets('B8. the preset swatches are untouched by this ticket', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      await _scrollSheetTo(
        tester,
        find.byKey(const Key('device-theme-custom')),
      );
      for (final preset in PosThemePair.presets) {
        expect(
          find.byKey(Key('device-theme-${preset.wire}')),
          findsOneWidget,
          reason: preset.wire,
        );
      }
      await _tapVisible(tester, const Key('device-theme-forest_charcoal'));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.test-dev'),
        'forest_charcoal',
      );
    });

    testWidgets('B9. the swatch tiles are comfortable targets', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      await _openCustomEditor(tester);
      for (final key in const [
        'custom-theme-primary-swatch',
        'custom-theme-secondary-swatch',
      ]) {
        await _scrollSheetTo(tester, find.byKey(Key(key)));
        expect(
          tester.getSize(find.byKey(Key(key))).height,
          greaterThanOrEqualTo(44),
          reason: '$key target below 44dp',
        );
      }
    });
  });

  group('C. Locales and layout', () {
    testWidgets('C1. Arabic lays the picker out RTL while the hex readout '
        'stays a Latin LTR run', (tester) async {
      await _openPicker(tester, initial: seed, locale: const Locale('ar'));
      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(find.text(l10n.posColorPickerQuickColors), findsOneWidget);
      expect(find.text(l10n.posColorPickerConfirm), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('pos-color-picker'))),
        ),
        TextDirection.rtl,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('pos-color-picker-hex-readout')))
            .textDirection,
        TextDirection.ltr,
      );
    });

    for (final locale in const [Locale('en'), Locale('he')]) {
      testWidgets('C2. the picker renders its localized controls in '
          '${locale.languageCode}', (tester) async {
        await _openPicker(tester, initial: seed, locale: locale);
        final l10n = await AppLocalizations.delegate.load(locale);
        expect(find.text(l10n.posColorPickerQuickColors), findsOneWidget);
        expect(find.text(l10n.posColorPickerHue), findsOneWidget);
        expect(find.text(l10n.posColorPickerShade), findsOneWidget);
        expect(find.text(l10n.posColorPickerAdvanced), findsOneWidget);
        expect(find.text(l10n.posColorPickerConfirm), findsOneWidget);
      });
    }

    for (final (locale, size) in const [
      (Locale('ar'), Size(1024, 600)), // the pilot tablet, landscape
      (Locale('ar'), Size(390, 844)),
      (Locale('he'), Size(390, 844)),
      (Locale('en'), Size(430, 932)),
    ]) {
      testWidgets('C3. no overflow with the picker open at '
          '${size.width.toInt()}x${size.height.toInt()} in '
          '${locale.languageCode}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final overflows = await _overflowsDuring(() async {
          await _openPicker(tester, initial: seed, locale: locale);
          await _tapVisible(
            tester,
            const Key('pos-color-picker-advanced-toggle'),
          );
        });
        expect(
          overflows,
          isEmpty,
          reason: '${locale.languageCode}@${size.width}: picker overflow',
        );
      });
    }

    testWidgets('C4. no overflow on the editor + picker round trip at '
        '1024x600 in Arabic — the pilot tablet scene', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1024, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final overflows = await _overflowsDuring(() async {
        await tester.pumpWidget(_settingsApp(locale: const Locale('ar')));
        await tester.pumpAndSettle();
        await _openCustomEditor(tester);
        await _scrollSheetTo(
          tester,
          find.byKey(const Key('custom-theme-primary-swatch')),
        );
        await _tapVisible(tester, const Key('custom-theme-primary-swatch'));
        await _tapVisible(tester, const Key('pos-color-picker-swatch-146B6B'));
        await _tapVisible(tester, const Key('pos-color-picker-confirm'));
        await _scrollSheetTo(
          tester,
          find.byKey(const Key('custom-theme-apply')),
        );
        await _tapVisible(tester, const Key('custom-theme-apply'));
      });
      expect(overflows, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.pos.device_theme.test-dev'),
        'custom:146B6B:D9642B',
      );
    });
  });
}
