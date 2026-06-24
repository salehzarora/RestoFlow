import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

void main() {
  test('restoflowBaseTheme returns a seeded light theme by default', () {
    final theme = restoflowBaseTheme();
    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.appBarTheme.elevation, 0);
    // The seed drives a non-default brand primary.
    expect(theme.colorScheme.primary, isNot(const ColorScheme.light().primary));
  });

  test('restoflowBaseTheme honours a custom seed and brightness', () {
    final dark = restoflowBaseTheme(
      seedColor: const Color(0xFF1B7A52),
      brightness: Brightness.dark,
    );
    expect(dark.colorScheme.brightness, Brightness.dark);
  });

  test('spacing and radius tokens are positive and ordered', () {
    expect(RestoflowSpacing.xs, greaterThan(0));
    expect(RestoflowSpacing.xs < RestoflowSpacing.sm, isTrue);
    expect(RestoflowSpacing.sm < RestoflowSpacing.lg, isTrue);
    expect(RestoflowSpacing.lg < RestoflowSpacing.xxl, isTrue);
    expect(RestoflowRadii.sm < RestoflowRadii.lg, isTrue);
    expect(RestoflowRadii.lg < RestoflowRadii.pill, isTrue);
  });
}
