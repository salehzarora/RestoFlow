import 'package:flutter/material.dart';

/// TRUE semantic colours for RestoFlow (design-polish sprint).
///
/// The green-seeded Material 3 [ColorScheme] cannot express real operational
/// status colours: its `secondaryContainer` ("success") and
/// `tertiaryContainer` ("warning") are both desaturated green-beige pastels.
/// This [ThemeExtension] carries a fixed, brand-harmonised palette so that
/// success is GREEN, warning is AMBER, danger is RED, and info is BLUE on
/// every surface — plus the warm restaurant accent and the dark-sidebar
/// palette the dashboard shell uses.
///
/// Consumed through `RestoflowTone.styleOf(theme)` (tone.dart), which falls
/// back to scheme roles when the extension is absent, so widgets keep working
/// in test harnesses that pump a bare [MaterialApp] without the RestoFlow
/// theme.
@immutable
class RestoflowSemanticColors extends ThemeExtension<RestoflowSemanticColors> {
  const RestoflowSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.sidebarSurface,
    required this.sidebarOnSurface,
    required this.sidebarMuted,
    required this.sidebarActiveBackground,
    required this.sidebarActiveForeground,
  });

  /// Positive / healthy / paid / ready.
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// Needs attention / pending / preparing.
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// Error / blocking / revoked.
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  /// Informational / demo / in-flight.
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  /// The warm restaurant accent (terracotta) — brand moments only
  /// (hero panels, active nav, highlights), never for statuses.
  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;

  /// Dashboard dark-sidebar palette (soft dark green-black over the light
  /// content area).
  final Color sidebarSurface;
  final Color sidebarOnSurface;
  final Color sidebarMuted;
  final Color sidebarActiveBackground;
  final Color sidebarActiveForeground;

  /// Light-theme preset.
  static const light = RestoflowSemanticColors(
    success: Color(0xFF15803D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCFCE7),
    onSuccessContainer: Color(0xFF14532D),
    warning: Color(0xFFB45309),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF78350F),
    danger: Color(0xFFB91C1C),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFEE2E2),
    onDangerContainer: Color(0xFF7F1D1D),
    info: Color(0xFF1D4ED8),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFDBEAFE),
    onInfoContainer: Color(0xFF1E3A8A),
    accent: Color(0xFFC2410C),
    onAccent: Color(0xFFFFFFFF),
    accentContainer: Color(0xFFFFEDD5),
    onAccentContainer: Color(0xFF7C2D12),
    sidebarSurface: Color(0xFF10201A),
    sidebarOnSurface: Color(0xFFE7F2EC),
    sidebarMuted: Color(0xFF8BA79A),
    sidebarActiveBackground: Color(0xFF1B7A52),
    sidebarActiveForeground: Color(0xFFFFFFFF),
  );

  /// Dark-theme preset (high-contrast kitchen surfaces).
  static const dark = RestoflowSemanticColors(
    success: Color(0xFF4ADE80),
    onSuccess: Color(0xFF052E16),
    successContainer: Color(0xFF166534),
    onSuccessContainer: Color(0xFFDCFCE7),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF451A03),
    warningContainer: Color(0xFF92400E),
    onWarningContainer: Color(0xFFFEF3C7),
    danger: Color(0xFFF87171),
    onDanger: Color(0xFF450A0A),
    dangerContainer: Color(0xFF991B1B),
    onDangerContainer: Color(0xFFFEE2E2),
    info: Color(0xFF60A5FA),
    onInfo: Color(0xFF172554),
    infoContainer: Color(0xFF1E40AF),
    onInfoContainer: Color(0xFFDBEAFE),
    accent: Color(0xFFFB923C),
    onAccent: Color(0xFF431407),
    accentContainer: Color(0xFF9A3412),
    onAccentContainer: Color(0xFFFFEDD5),
    sidebarSurface: Color(0xFF0B1712),
    sidebarOnSurface: Color(0xFFE7F2EC),
    sidebarMuted: Color(0xFF7E998C),
    sidebarActiveBackground: Color(0xFF1B7A52),
    sidebarActiveForeground: Color(0xFFFFFFFF),
  );

  /// The preset matching [brightness].
  static RestoflowSemanticColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  RestoflowSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? accent,
    Color? onAccent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? sidebarSurface,
    Color? sidebarOnSurface,
    Color? sidebarMuted,
    Color? sidebarActiveBackground,
    Color? sidebarActiveForeground,
  }) {
    return RestoflowSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentContainer: accentContainer ?? this.accentContainer,
      onAccentContainer: onAccentContainer ?? this.onAccentContainer,
      sidebarSurface: sidebarSurface ?? this.sidebarSurface,
      sidebarOnSurface: sidebarOnSurface ?? this.sidebarOnSurface,
      sidebarMuted: sidebarMuted ?? this.sidebarMuted,
      sidebarActiveBackground:
          sidebarActiveBackground ?? this.sidebarActiveBackground,
      sidebarActiveForeground:
          sidebarActiveForeground ?? this.sidebarActiveForeground,
    );
  }

  @override
  RestoflowSemanticColors lerp(RestoflowSemanticColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RestoflowSemanticColors(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      onDangerContainer: l(onDangerContainer, other.onDangerContainer),
      info: l(info, other.info),
      onInfo: l(onInfo, other.onInfo),
      infoContainer: l(infoContainer, other.infoContainer),
      onInfoContainer: l(onInfoContainer, other.onInfoContainer),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentContainer: l(accentContainer, other.accentContainer),
      onAccentContainer: l(onAccentContainer, other.onAccentContainer),
      sidebarSurface: l(sidebarSurface, other.sidebarSurface),
      sidebarOnSurface: l(sidebarOnSurface, other.sidebarOnSurface),
      sidebarMuted: l(sidebarMuted, other.sidebarMuted),
      sidebarActiveBackground: l(
        sidebarActiveBackground,
        other.sidebarActiveBackground,
      ),
      sidebarActiveForeground: l(
        sidebarActiveForeground,
        other.sidebarActiveForeground,
      ),
    );
  }
}
