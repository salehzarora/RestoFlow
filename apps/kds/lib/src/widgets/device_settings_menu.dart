import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'device_settings_sheet.dart';

/// The KDS app-bar ⋮ device menu (device settings sprint): the operational
/// entry for the KITCHEN STAFF working this display — never an owner/admin
/// surface, and (like everything on this surface) money-free. Opens the
/// device-settings sheet; connection maintenance actions (refresh / unpair)
/// ride the same menu.
class DeviceSettingsMenu extends StatelessWidget {
  const DeviceSettingsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_DeviceMenuAction>(
      key: const Key('device-settings-menu'),
      tooltip: l10n.deviceSettingsMenuTooltip,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => switch (action) {
        _DeviceMenuAction.settings => KdsDeviceSettingsSheet.show(context),
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
      ],
    );
  }
}

enum _DeviceMenuAction { settings }
