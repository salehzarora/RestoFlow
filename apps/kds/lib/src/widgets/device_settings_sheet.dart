import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/kds_device_context.dart';
import '../state/kds_session.dart';

/// The KDS operational device-settings sheet (device settings sprint).
///
/// STAFF-scope only and MONEY-FREE (T-003): it shows what THIS paired
/// kitchen display is (app type, restaurant/branch, device label, pairing +
/// staff-session status) and, in later parts, the branch's kitchen-printer
/// assignments and the per-device auto-print toggles. Configuration itself
/// stays in the owner Dashboard — nothing here can touch other devices,
/// other branches, or any owner/admin/payment data. Demo mode shows an
/// honest "no paired device" note.
class KdsDeviceSettingsSheet extends ConsumerWidget {
  const KdsDeviceSettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const KdsDeviceSettingsSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final device = ref.watch(kdsDeviceContextProvider);
    final hasStaffSession = ref.watch(kdsSyncSessionProvider) != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            key: const Key('device-settings-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, color: theme.colorScheme.primary),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.deviceSettingsTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.md),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (isDemo)
                      RestoflowNoticeBanner(
                        body: l10n.deviceSettingsDemoNote,
                        tone: RestoflowTone.info,
                      )
                    else if (device == null)
                      RestoflowNoticeBanner(
                        body: l10n.deviceSettingsUnavailable,
                        tone: RestoflowTone.warning,
                      )
                    else
                      _DeviceInfoSection(
                        l10n: l10n,
                        deviceLabel: device.displayName,
                        hasStaffSession: hasStaffSession,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The paired-device identity rows. Values not known client-side yet render
/// as an em dash — the printer-assignments read (Part B) fills the names in.
class _DeviceInfoSection extends StatelessWidget {
  const _DeviceInfoSection({
    required this.l10n,
    required this.hasStaffSession,
    this.deviceLabel,
  });

  final AppLocalizations l10n;
  final bool hasStaffSession;
  final String? deviceLabel;

  String? get restaurantName => null; // Part B fills these from the RPC.
  String? get branchName => null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(
          label: l10n.deviceSettingsAppTypeLabel,
          value: l10n.deviceSettingsAppTypeKds,
        ),
        _Row(
          label: l10n.deviceSettingsRestaurantLabel,
          value: restaurantName ?? '—',
        ),
        _Row(label: l10n.deviceSettingsBranchLabel, value: branchName ?? '—'),
        _Row(label: l10n.deviceSettingsDeviceLabel, value: deviceLabel ?? '—'),
        _PillRow(
          label: l10n.deviceSettingsPairingLabel,
          pill: RestoflowStatusPill(
            label: l10n.deviceSettingsPairingActive,
            tone: RestoflowTone.success,
            icon: Icons.link,
          ),
        ),
        _PillRow(
          label: l10n.deviceSettingsPinSessionLabel,
          pill: RestoflowStatusPill(
            label: hasStaffSession
                ? l10n.deviceSettingsPinSessionActive
                : l10n.deviceSettingsPinSessionNone,
            tone: hasStaffSession
                ? RestoflowTone.success
                : RestoflowTone.neutral,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillRow extends StatelessWidget {
  const _PillRow({required this.label, required this.pill});

  final String label;
  final Widget pill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          pill,
        ],
      ),
    );
  }
}
