import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/kiosk_chrome.dart';

/// 09 · Device settings (staff) — FIXTURE SHELL. Controls mutate in-memory
/// fixture settings only (table toggle, idle timeout, attract content,
/// printer binding, default language); diagnostics rows show fixture values.
/// No persistence, no backend, no real printer — those arrive in later
/// phases. Staff surfaces keep the artifact's LTR layout while text stays
/// localized.
class KioskSettingsScreen extends ConsumerWidget {
  const KioskSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);
    final settings = state.settings;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(44, 34, 44, 34),
            decoration: BoxDecoration(
              color: const Color(0xD9080F1C),
              border: Border(
                bottom: BorderSide(color: KioskColors.glass(.09), width: 1.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.kioskSettingsTitle,
                        style: KioskType.body(32, FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${KioskBrand.deviceLabel} · ${KioskBrand.wordmark} ${KioskBrand.subtitle} · ${l10n.kioskSettingsSignedIn}',
                        style: KioskType.body(
                          20,
                          FontWeight.w500,
                          color: KioskColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                KioskAccentPill(
                  key: const Key('kiosk-settings-exit'),
                  onTap: controller.exitSettings,
                  height: 84,
                  horizontalPadding: 44,
                  child: Text(
                    l10n.kioskSettingsExit,
                    style: KioskType.body(
                      24,
                      FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(44, 36, 44, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsCard(
                    title: l10n.kioskSettingsOrdering,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.kioskSettingsTableToggleTitle,
                                  style: KioskType.body(22, FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.kioskSettingsTableToggleSub,
                                  style: KioskType.body(
                                    19,
                                    FontWeight.w500,
                                    color: KioskColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 22),
                          _Toggle(
                            key: const Key('kiosk-settings-tables-toggle'),
                            value: settings.tablePickerEnabled,
                            onChanged: (v) => controller.updateSettings(
                              settings.copyWith(tablePickerEnabled: v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _SettingsCard(
                    title: l10n.kioskSettingsIdleSection,
                    children: [
                      Text(
                        l10n.kioskSettingsIdleAfter,
                        style: KioskType.body(22, FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          for (final seconds in KioskTiming.idleOptions) ...[
                            _PillOption(
                              key: Key('kiosk-idle-$seconds'),
                              label: l10n.kioskSecondsShort(seconds),
                              selected: settings.idleSeconds == seconds,
                              onTap: () => controller.updateSettings(
                                settings.copyWith(idleSeconds: seconds),
                              ),
                            ),
                            const SizedBox(width: 14),
                          ],
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.kioskSettingsAttractContent,
                        style: KioskType.body(22, FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _PillOption(
                            label: l10n.kioskSettingsAttractPhotos,
                            selected:
                                settings.attractMode == KioskAttractMode.photos,
                            onTap: () => controller.updateSettings(
                              settings.copyWith(
                                attractMode: KioskAttractMode.photos,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          _PillOption(
                            label: l10n.kioskSettingsAttractPromo,
                            selected:
                                settings.attractMode == KioskAttractMode.promo,
                            onTap: () => controller.updateSettings(
                              settings.copyWith(
                                attractMode: KioskAttractMode.promo,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          _PillOption(
                            label: l10n.kioskSettingsAttractVideo,
                            selected:
                                settings.attractMode == KioskAttractMode.video,
                            onTap: () => controller.updateSettings(
                              settings.copyWith(
                                attractMode: KioskAttractMode.video,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (settings.attractMode == KioskAttractMode.promo) ...[
                        const SizedBox(height: 16),
                        Text(
                          l10n.kioskSettingsPromoDropHint,
                          style: KioskType.body(
                            19,
                            FontWeight.w500,
                            color: KioskColors.textMuted,
                          ),
                        ),
                      ],
                      if (settings.attractMode == KioskAttractMode.video) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(26),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: KioskColors.glass(.22),
                              width: 2.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            l10n.kioskSettingsVideoHint,
                            style: KioskType.body(
                              19,
                              FontWeight.w500,
                              color: KioskColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  _SettingsCard(
                    title: l10n.kioskSettingsPrinterSection,
                    trailing: _GhostAccentButton(
                      key: const Key('kiosk-print-test'),
                      label: l10n.kioskSettingsPrintTest,
                      onTap: () {
                        final bound = kioskFixturePrinters.firstWhere(
                          (p) => p.id == settings.boundPrinterId,
                        );
                        controller.showStaffToast(
                          l10n.kioskTestSlipSent(bound.name),
                        );
                      },
                    ),
                    children: [
                      for (final printer in kioskFixturePrinters) ...[
                        _PrinterRow(
                          printer: printer,
                          bound: settings.boundPrinterId == printer.id,
                          onTap: () => controller.updateSettings(
                            settings.copyWith(boundPrinterId: printer.id),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        l10n.kioskSettingsPrinterNote,
                        style: KioskType.body(
                          18,
                          FontWeight.w500,
                          color: KioskColors.textFaint,
                        ),
                      ),
                    ],
                  ),
                  _SettingsCard(
                    title: l10n.kioskSettingsDefaultLang,
                    children: [
                      Row(
                        children: [
                          for (final entry in const [
                            ('en', 'English'),
                            ('he', 'עברית'),
                            ('ar', 'العربية'),
                          ]) ...[
                            _PillOption(
                              key: Key('kiosk-deflang-${entry.$1}'),
                              label: entry.$2,
                              selected: settings.defaultLang == entry.$1,
                              onTap: () => controller.updateSettings(
                                settings.copyWith(defaultLang: entry.$1),
                              ),
                            ),
                            const SizedBox(width: 14),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        l10n.kioskSettingsDefaultLangNote,
                        style: KioskType.body(
                          18,
                          FontWeight.w500,
                          color: KioskColors.textFaint,
                        ),
                      ),
                    ],
                  ),
                  _SettingsCard(
                    title: l10n.kioskSettingsDiagnostics,
                    children: [
                      Wrap(
                        spacing: 40,
                        runSpacing: 14,
                        children: [
                          _DiagRow(
                            label: l10n.kioskSettingsDevice,
                            value: KioskBrand.deviceLabel,
                          ),
                          _DiagRow(
                            label: l10n.kioskSettingsPairing,
                            value: l10n.kioskSettingsPairingActive,
                            valueColor: KioskColors.tableFree,
                          ),
                          _DiagRow(
                            label: l10n.kioskSettingsMenuSync,
                            value: '—',
                          ),
                          _DiagRow(
                            label: l10n.kioskSettingsOrdersToday,
                            value: '${state.dailySeq - 38}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _GhostAccentButton(
                        key: const Key('kiosk-resync'),
                        label: l10n.kioskSettingsResync,
                        onTap: () =>
                            controller.showStaffToast(l10n.kioskResyncDone),
                      ),
                    ],
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        l10n.kioskSettingsAccessNote,
                        textAlign: TextAlign.center,
                        style: KioskType.body(
                          18,
                          FontWeight.w500,
                          color: KioskColors.textFaint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.children,
    this.trailing,
  });
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 26),
    padding: const EdgeInsets.fromLTRB(38, 34, 38, 34),
    decoration: BoxDecoration(
      color: KioskColors.glass(.05),
      border: Border.all(color: KioskColors.glass(.11), width: 1.5),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: KioskType.body(25, FontWeight.w800)),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 22),
        ...children,
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 104,
      height: 58,
      padding: const EdgeInsets.all(6),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: value ? KioskColors.ring : KioskColors.glass(.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x59000000),
              offset: Offset(0, 3),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    ),
  );
}

class _PillOption extends StatelessWidget {
  const _PillOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: selected ? kioskAccentGradient : null,
        color: selected ? null : KioskColors.glass(.05),
        border: selected
            ? null
            : Border.all(color: KioskColors.glass(.16), width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: KioskType.body(
          22,
          FontWeight.w700,
          color: selected ? Colors.white : KioskColors.textSoft,
        ),
      ),
    ),
  );
}

class _GhostAccentButton extends StatelessWidget {
  const _GhostAccentButton({
    super.key,
    required this.label,
    required this.onTap,
  });
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: KioskColors.ring.withValues(alpha: .1),
        border: Border.all(
          color: KioskColors.ring.withValues(alpha: .6),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: KioskType.body(
          20,
          FontWeight.w700,
          color: KioskColors.accentTop,
        ),
      ),
    ),
  );
}

class _PrinterRow extends StatelessWidget {
  const _PrinterRow({
    required this.printer,
    required this.bound,
    required this.onTap,
  });
  final KioskFixturePrinter printer;
  final bool bound;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KioskPressable(
      onTap: onTap,
      child: Container(
        key: Key('kiosk-printer-${printer.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
        decoration: BoxDecoration(
          color: bound
              ? KioskColors.ring.withValues(alpha: .1)
              : KioskColors.glass(.03),
          border: Border.all(
            color: bound ? KioskColors.ring : KioskColors.glass(.11),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: printer.online
                    ? KioskColors.tableFree
                    : KioskColors.tableOccupied,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    printer.name,
                    style: KioskType.body(22, FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    printer.detail,
                    style: KioskType.body(
                      18,
                      FontWeight.w500,
                      color: KioskColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              bound
                  ? l10n.kioskPrinterBound
                  : printer.online
                  ? l10n.kioskPrinterAvailable
                  : l10n.kioskPrinterOffline,
              style: KioskType.body(
                19,
                FontWeight.w700,
                color: bound
                    ? KioskColors.accentTop
                    : printer.online
                    ? KioskColors.textMuted
                    : KioskColors.tableOccupied,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: '$label · ',
      children: [
        TextSpan(
          text: value,
          style: KioskType.body(
            20,
            FontWeight.w700,
            color: valueColor ?? KioskColors.textPrimary,
          ),
        ),
      ],
    ),
    style: KioskType.body(20, FontWeight.w500, color: KioskColors.textMuted),
  );
}
