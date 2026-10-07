import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// BIZBOT-DASHBOARD-REFRESH-001: presentation tokens owned by Overview only.
/// Keep the inherited brand/semantic extensions: tender colours use them.
abstract final class OverviewVisuals {
  static const primary = Color(0xFF059669);
  static const deep = Color(0xFF047857);
  static const mint = Color(0xFFA7F3D0);
  static const softMint = Color(0xFFD1FAE5);
  static const ink = Color(0xFF142D29);
  static const canvas = Color(0xFFF4FAF7);
  static const border = Color(0xFFE4EEE9);
  static const radius = BorderRadius.all(Radius.circular(16));
  static const metricPadding = 12.0;
  static const sage = Color(0xFFF5F9F3);
  static const paleMint = Color(0xFFF3FCF7);

  // Match the shell's phone breakpoint; narrow cards inside a desktop layout
  // must retain the owner-approved desktop treatment.
  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 560;

  static bool compactPhone(BuildContext context) =>
      isPhone(context) &&
      MediaQuery.textScalerOf(context).scale(14) / 14 <= 1.1;

  static double metricContentPadding(BuildContext context) =>
      compactPhone(context) ? 10 : metricPadding;

  static ThemeData theme(ThemeData inherited) => inherited.copyWith(
    scaffoldBackgroundColor: canvas,
    colorScheme: inherited.colorScheme.copyWith(
      primary: deep,
      onPrimary: Colors.white,
      primaryContainer: softMint,
      onPrimaryContainer: ink,
      surface: Colors.white,
      onSurface: ink,
      outlineVariant: border,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: Color(0x18047857),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}

enum OverviewSurface { standard, sage, analytics, payments }

/// Compact section chrome scoped to Overview; shared consumers are unchanged.
class OverviewSectionCard extends RestoflowSectionCard {
  const OverviewSectionCard({
    required super.children,
    super.title,
    super.subtitle,
    super.action,
    this.icon,
    this.surface = OverviewSurface.standard,
    super.key,
  });

  final IconData? icon;
  final OverviewSurface surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: surface == OverviewSurface.analytics ? 3 : 1.5,
      shadowColor: const Color(0x18047857),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: OverviewVisuals.radius,
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: switch (surface) {
              OverviewSurface.analytics => const [
                Colors.white,
                Color(0xFFEDFAF4),
              ],
              OverviewSurface.sage => const [
                Color(0xFFE7F5EC),
                Color(0xFFF9FCF9),
              ],
              OverviewSurface.payments => const [
                Colors.white,
                Color(0xFFF0F8F6),
              ],
              OverviewSurface.standard => const [
                Colors.white,
                Color(0xFFFEFFFF),
              ],
            },
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: surface == OverviewSurface.analytics
                        ? const Color(0xFFE5F5EE)
                        : const Color(0xFFF3F8F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final heading = Row(
                        children: [
                          if (icon != null) ...[
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: surface == OverviewSurface.analytics
                                    ? OverviewVisuals.deep
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                icon,
                                size: 20,
                                color: surface == OverviewSurface.analytics
                                    ? Colors.white
                                    : OverviewVisuals.deep,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title!,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: OverviewVisuals.ink,
                                  ),
                                ),
                                if (subtitle != null)
                                  Text(
                                    subtitle!,
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                      if (action == null) return heading;
                      final scale =
                          MediaQuery.textScalerOf(context).scale(14) / 14;
                      if (constraints.maxWidth < 420 * scale) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            heading,
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: action!,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: heading),
                          action!,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 2),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Theme scope never reaches authentication, other tabs, or the shell.
class OverviewVisualScope extends StatelessWidget {
  const OverviewVisualScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: OverviewVisuals.theme(Theme.of(context)), child: child);
}

/// Gives labels and financial values their full width on compact layouts.
class OverviewValueRow extends StatelessWidget {
  const OverviewValueRow({required this.label, required this.value, super.key});

  final Widget label;
  final Widget value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (constraints.maxWidth < 190 * scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [label, const SizedBox(height: 4), value],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: label),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: value,
            ),
          ),
        ],
      );
    },
  );
}
