import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show PerfDiagnosticsPanel, perfDiagnosticsEnabled;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../design/kiosk_theme.dart';
import '../media/kiosk_media_image.dart';

/// PERF-110: whether the TEST-BUILD-ONLY perf diagnostics card is present in
/// the staff settings. Reads the compile-time flag once; overridable in tests.
final kioskPerfDiagnosticsEnabledProvider = Provider<bool>(
  (ref) => perfDiagnosticsEnabled(),
);

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — the kiosk's TEST-BUILD-ONLY device
/// metrics + rolling frame-timing card (staff settings, real AND demo trees).
/// Shows the current STAGE SCALE (1080×1920 design px → logical px) alongside
/// the shared panel. Local only; nothing is logged, persisted or sent.
class KioskPerfDiagnosticsSection extends StatelessWidget {
  const KioskPerfDiagnosticsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stageScale = KioskStageScale.of(context);
    return Container(
      key: const Key('kiosk-settings-perf-diagnostics'),
      margin: const EdgeInsets.fromLTRB(44, 0, 44, 40),
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: KioskColors.cardGlass,
        border: Border.all(color: KioskColors.glass(.12), width: 1.5),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.deviceSettingsPerfDiagnosticsTitle,
            style: KioskType.body(30, FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.deviceSettingsPerfDiagnosticsNote,
            style: KioskType.body(
              20,
              FontWeight.w500,
              color: KioskColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          // The panel renders at stage scale like everything else on this
          // screen; the numbers it reads (MediaQuery) are the DEVICE's.
          DefaultTextStyle.merge(
            style: KioskType.body(20, FontWeight.w500),
            child: PerfDiagnosticsPanel(
              appLabel: 'Kiosk',
              resetLabel: l10n.deviceSettingsPerfDiagnosticsReset,
              textColor: KioskColors.textPrimary,
              mutedColor: KioskColors.textMuted,
              extraRows: [
                (
                  label: 'kiosk stage scale',
                  value: stageScale.toStringAsFixed(4),
                ),
                (
                  label: 'kiosk design px',
                  value:
                      '${kioskDesignSize.width.toInt()} × '
                      '${kioskDesignSize.height.toInt()}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
