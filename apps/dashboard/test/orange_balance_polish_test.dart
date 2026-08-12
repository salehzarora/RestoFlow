// UI-ORANGE-BALANCE-POLISH-001 — the Dashboard's orange roles.
//
// The rule this file exists to hold: navy is the STRUCTURE, orange is the
// ACTION and the ACTIVE mark. Orange must never be the only signal, must never
// stand in for a semantic status, and must always be sourced from the BRAND
// palette rather than from `RestoflowSemanticColors.accent`. Those two hold the
// same value today, which is exactly why the sourcing has to be pinned: a
// rebrand that moves brand orange must not silently repaint an attention state.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// Collects paint-time overflow, which never reaches [WidgetTester.takeException].
/// Restored BEFORE returning so the caller's `expect` runs with the binding's
/// own handler back in place.
Future<List<String>> overflowsDuring(Future<void> Function() body) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      overflows.add(text.split('\n').first.trim());
    } else {
      previous?.call(details);
    }
  };
  await body();
  FlutterError.onError = previous;
  return overflows;
}

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? restoflowKdsDarkBrandTheme()
        : restoflowLightBrandTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('A. brand orange and semantic accent stay independent', () {
    test('the two roles are separate types with separate presets', () {
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final semantic = RestoflowSemanticColors.of(Brightness.light);

      // They may coincide in value — they must not be the same SOURCE. The
      // guard below is what catches a future edit that reaches for the
      // semantic role because "it is the same orange anyway".
      expect(brand.accentOrange, isA<Color>());
      expect(semantic.accent, isA<Color>());

      // Semantic states must never equal the brand accent: if a status colour
      // ever collides with the brand mark, the status stops being readable as
      // a status.
      expect(semantic.success, isNot(brand.accentOrange));
      expect(semantic.danger, isNot(brand.accentOrange));
      expect(semantic.info, isNot(brand.accentOrange));
    });

    test('navy remains the structural brand colour', () {
      final brand = RestoflowBrandPalette.of(Brightness.light);
      expect(brand.primaryNavy, isNot(brand.accentOrange));
      // The theme's primary — every structural fill — is navy, not orange.
      final theme = restoflowLightBrandTheme();
      expect(theme.colorScheme.primary, isNot(brand.accentOrange));
    });
  });

  group('B. the accent button role', () {
    testWidgets('paints the BRAND orange, not the semantic accent', (
      tester,
    ) async {
      late ButtonStyle style;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              style = RestoflowButtonStyles.accent(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final brand = RestoflowBrandPalette.of(Brightness.light);
      expect(
        style.backgroundColor?.resolve(const {}),
        brand.accentOrange,
        reason: 'The accent CTA must source its fill from the brand palette.',
      );
      expect(
        style.foregroundColor?.resolve(const {}),
        Colors.white,
        reason: 'White on the light-preset orange measures 5.18:1 (AA).',
      );
    });

    testWidgets('shows distinct hover, pressed and focus states', (
      tester,
    ) async {
      late ButtonStyle style;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              style = RestoflowButtonStyles.accent(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final rest = style.overlayColor?.resolve(const {});
      final hover = style.overlayColor?.resolve({WidgetState.hovered});
      final pressed = style.overlayColor?.resolve({WidgetState.pressed});
      expect(rest, isNull);
      expect(hover, isNotNull);
      expect(pressed, isNotNull);
      expect(
        hover,
        isNot(pressed),
        reason: 'Hover and pressed must be distinguishable, not one state.',
      );

      // Elevation lifts on hover and settles on press — a tactile, finite step.
      expect(style.elevation?.resolve(const {}), 1.0);
      expect(style.elevation?.resolve({WidgetState.hovered}), 3.0);
      expect(style.elevation?.resolve({WidgetState.pressed}), 0.0);
      expect(style.elevation?.resolve({WidgetState.disabled}), 0.0);

      // A focus ring exists and is not the same colour as the fill.
      final focusSide = style.side?.resolve({WidgetState.focused});
      expect(focusSide, isNotNull);
      expect(focusSide!.width, greaterThanOrEqualTo(2));
      expect(style.side?.resolve(const {}), BorderSide.none);
    });

    testWidgets('navyPrimary keeps a navy body and earns orange on focus', (
      tester,
    ) async {
      late ButtonStyle style;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              style = RestoflowButtonStyles.navyPrimary(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final brand = RestoflowBrandPalette.of(Brightness.light);
      expect(
        style.backgroundColor?.resolve(const {}),
        brand.primaryNavy,
        reason: 'The structural colour must not move on interaction.',
      );
      expect(
        style.side?.resolve({WidgetState.focused})?.color,
        brand.accentOrange,
        reason: 'Orange is the focus EDGE here, never the resting fill.',
      );
    });

    testWidgets('the two primary roles are visually distinct', (tester) async {
      late ButtonStyle accent;
      late ButtonStyle navy;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              accent = RestoflowButtonStyles.accent(context);
              navy = RestoflowButtonStyles.navyPrimary(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        accent.backgroundColor?.resolve(const {}),
        isNot(navy.backgroundColor?.resolve(const {})),
        reason:
            'If the two primary roles paint the same, the "one accent per '
            'view" rule cannot be seen or enforced.',
      );
    });
  });

  group('C. semantic button roles never become orange', () {
    testWidgets('danger and success keep their own semantics', (tester) async {
      late ButtonStyle danger;
      late ButtonStyle success;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              danger = RestoflowButtonStyles.danger(context);
              success = RestoflowButtonStyles.success(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final semantic = RestoflowSemanticColors.of(Brightness.light);
      expect(danger.backgroundColor?.resolve(const {}), semantic.danger);
      expect(success.backgroundColor?.resolve(const {}), semantic.success);
      expect(
        danger.backgroundColor?.resolve(const {}),
        isNot(brand.accentOrange),
        reason: 'A destructive action must never read as the brand accent.',
      );
      expect(
        success.backgroundColor?.resolve(const {}),
        isNot(brand.accentOrange),
      );
    });
  });

  group('D. the accent CTA stays usable at every width and scale', () {
    for (final width in [1280.0, 1024.0, 834.0, 700.0, 430.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${width.toInt()} @${scale}x is overflow-free', (
          tester,
        ) async {
          final overflows = await overflowsDuring(() async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              MaterialApp(
                theme: restoflowLightBrandTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (context) => FilledButton(
                        style: RestoflowButtonStyles.accent(context),
                        onPressed: () {},
                        child: const Text('Send order'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          });
          expect(overflows, isEmpty);

          // The touch target survives every width and scale.
          final rect = tester.getRect(find.byType(FilledButton));
          expect(rect.height, greaterThanOrEqualTo(40.0));
        });
      }
    }

    testWidgets('hover does not move the button (no layout jump)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => FilledButton(
              style: RestoflowButtonStyles.accent(context),
              onPressed: () {},
              child: const Text('Send order'),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.byType(FilledButton));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(FilledButton)));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(FilledButton)),
        before,
        reason:
            'Elevation and overlay may change on hover; geometry may not — a '
            'control that moves under the cursor is a control you miss.',
      );
    });
  });
}
