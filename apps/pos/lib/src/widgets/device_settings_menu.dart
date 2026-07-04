import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/pos_shift_close_policy.dart';
import 'device_settings_sheet.dart';
import 'shift_close_sheet.dart';

/// The POS app-bar ⋮ device menu (device settings sprint): the operational
/// entry for the STAFF working this station — never an owner/admin surface.
/// Opens the device-settings sheet; connection maintenance actions (refresh /
/// unpair) ride the same menu.
class DeviceSettingsMenu extends ConsumerWidget {
  const DeviceSettingsMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // RF-113: the owner can DISABLE the shift-close workflow per branch from the
    // Dashboard. Only a confirmed `false` hides the entry; demo mode, an
    // in-flight read, or a read glitch keep it visible (default-true policy).
    final shiftCloseEnabled =
        ref.watch(posShiftCloseEnabledProvider).valueOrNull ?? true;
    return PopupMenuButton<_DeviceMenuAction>(
      key: const Key('device-settings-menu'),
      tooltip: l10n.deviceSettingsMenuTooltip,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => switch (action) {
        _DeviceMenuAction.settings => PosDeviceSettingsSheet.show(context),
        _DeviceMenuAction.closeShift => PosShiftCloseSheet.show(context),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('device-settings-item'),
          value: _DeviceMenuAction.settings,
          child: Row(
            children: [
              const Icon(Icons.tune, size: 20),
              const SizedBox(width: 12),
              Text(l10n.deviceSettingsTitle),
            ],
          ),
        ),
        // RF-113: the shift close / cash reconciliation entry for the staff on
        // this station (still operational-only — never an owner/admin surface).
        // Hidden when the branch's owner-controlled policy is disabled.
        if (shiftCloseEnabled)
          PopupMenuItem(
            key: const Key('shift-close-item'),
            value: _DeviceMenuAction.closeShift,
            child: Row(
              children: [
                const Icon(Icons.point_of_sale_outlined, size: 20),
                const SizedBox(width: 12),
                Text(l10n.posShiftCloseMenuItem),
              ],
            ),
          ),
      ],
    );
  }
}

enum _DeviceMenuAction { settings, closeShift }
