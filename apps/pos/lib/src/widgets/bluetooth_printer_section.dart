import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../print/bluetooth_printer.dart';
import '../print/bluetooth_printer_tester.dart';
import '../print/kitchen_test_document.dart';
import '../state/pos_bluetooth_printer_config.dart';
import '../state/pos_device_context.dart';
import '../state/pos_printer_purpose.dart';

enum _BtStatus { idle, testing, success, failure }

/// The on-device Bluetooth printer setup (ANDROID-003): list bonded/paired
/// Bluetooth devices, pick one, Save it locally, Test print raw ESC/POS bytes,
/// and Remove it — NO print bridge required. The MVP uses devices already paired
/// in Android Bluetooth settings (no in-app discovery). Money-free.
class BluetoothPrinterSection extends ConsumerStatefulWidget {
  const BluetoothPrinterSection({
    super.key,
    this.purpose = PosPrinterPurpose.customerReceipt,
  });

  /// KITCHEN-MODE-001B: which LOCAL purpose slot this section configures
  /// (customerReceipt = the legacy slot, byte-identical behavior; the kitchen
  /// slot is preparation-only and tests with the money-free kitchen document).
  final PosPrinterPurpose purpose;

  @override
  ConsumerState<BluetoothPrinterSection> createState() =>
      _BluetoothPrinterSectionState();
}

class _BluetoothPrinterSectionState
    extends ConsumerState<BluetoothPrinterSection> {
  BluetoothPairedResult? _paired;
  bool _loading = false;
  _BtStatus _status = _BtStatus.idle;
  String? _selectedAddress;
  String? _selectedName;

  /// PRINT-BLUETOOTH-RECOVERY-001: the last test failure's category (drives a
  /// specific message: permission / bluetooth-off / not-paired / connect /
  /// write) + the developer diagnostic detail (small secondary line — never
  /// printed on paper, never sent anywhere).
  pp.PrinterErrorCategory? _failCategory;
  String? _failDetail;

  /// Purpose-suffixed widget keys (customer keeps the legacy names).
  Key _k(String base) => Key(
    widget.purpose == PosPrinterPurpose.customerReceipt
        ? base
        : '$base-kitchen',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final connector = ref.read(bluetoothPrinterConnectorProvider);
    final result = await connector.pairedDevices();
    if (!mounted) return;
    setState(() {
      _paired = result;
      _loading = false;
    });
  }

  Future<void> _save(AppLocalizations l10n) async {
    final address = _selectedAddress;
    if (address == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(posBluetoothPrinterConfigFamily(widget.purpose).notifier)
        .save(PosBluetoothPrinterConfig(address: address, name: _selectedName));
    if (!mounted) return;
    setState(() => _status = _BtStatus.idle);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.posBluetoothSavedSnack)),
    );
  }

  Future<void> _remove(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(posBluetoothPrinterConfigFamily(widget.purpose).notifier)
        .clear();
    if (!mounted) return;
    setState(() {
      _status = _BtStatus.idle;
      _selectedAddress = null;
      _selectedName = null;
    });
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.posPrinterRemovedSnack)),
    );
  }

  Future<void> _testPrint(AppLocalizations l10n) async {
    final address = _selectedAddress;
    if (address == null) return;
    setState(() {
      _status = _BtStatus.testing;
      _failCategory = null;
      _failDetail = null;
    });
    final deviceLabel = ref.read(posDeviceContextProvider)?.displayName;
    // KITCHEN-MODE-001B: the kitchen slot tests with the MONEY-FREE localized
    // kitchen TEST document (shared raster path); the customer slot keeps the
    // classic diagnostic. Result = bytes accepted by the transport only.
    final document = widget.purpose == PosPrinterPurpose.kitchenTicket
        ? await buildPosKitchenTestDocument(
            ref,
            l10n,
            printerName: _selectedName,
            deviceLabel: deviceLabel,
          )
        : null;
    if (!mounted) return;
    final result = await ref
        .read(bluetoothPrinterTesterProvider)
        .testPrint(
          PosBluetoothPrinterConfig(address: address, name: _selectedName),
          deviceLabel: deviceLabel,
          document: document,
        );
    if (!mounted) return;
    setState(() {
      _status = result.ok ? _BtStatus.success : _BtStatus.failure;
      // PRINT-BLUETOOTH-RECOVERY-001: keep the failure KIND + diagnostic so
      // the status row says exactly what failed (not one generic message).
      _failCategory = result.ok ? null : result.category;
      _failDetail = result.ok ? null : result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final saved = ref
        .watch(posBluetoothPrinterConfigFamily(widget.purpose))
        .valueOrNull;
    // The effective selection: an in-session pick, else the saved printer.
    final selectedAddress = _selectedAddress ?? saved?.address;
    final canAct = selectedAddress != null && _status != _BtStatus.testing;

    return Column(
      key: _k('bluetooth-printer-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.posBluetoothPrinterHeading,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        RestoflowNoticeBanner(
          body: l10n.posBluetoothPrinterHelp,
          tone: RestoflowTone.info,
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.posBluetoothPairedLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              key: _k('bluetooth-refresh'),
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh, size: RestoflowIconSizes.sm),
              label: Text(l10n.posBluetoothRefreshAction),
            ),
          ],
        ),
        _DeviceList(
          loading: _loading,
          paired: _paired,
          l10n: l10n,
          selectedAddress: selectedAddress,
          onSelect: (device) => setState(() {
            _selectedAddress = device.address;
            _selectedName = device.name.isEmpty ? null : device.name;
            _status = _BtStatus.idle;
          }),
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: _k('bluetooth-save'),
                onPressed: canAct ? () => _save(l10n) : null,
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.posNetworkPrinterSaveAction),
              ),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                key: _k('bluetooth-test'),
                onPressed: canAct ? () => _testPrint(l10n) : null,
                icon: const Icon(Icons.print_outlined),
                label: Text(l10n.posNetworkPrinterTestAction),
              ),
            ),
          ],
        ),
        if (saved != null) ...[
          const SizedBox(height: RestoflowSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: _k('bluetooth-remove'),
              onPressed: () => _remove(l10n),
              icon: const Icon(
                Icons.delete_outline,
                size: RestoflowIconSizes.sm,
              ),
              label: Text(l10n.posPrinterRemoveAction),
              style: TextButton.styleFrom(
                foregroundColor: RestoflowTone.danger.styleOf(theme).accent,
              ),
            ),
          ),
        ],
        const SizedBox(height: RestoflowSpacing.xs),
        _StatusRow(
          l10n: l10n,
          status: _status,
          saved: saved,
          selectedAddress: selectedAddress,
          failCategory: _failCategory,
          failDetail: _failDetail,
        ),
      ],
    );
  }
}

/// The paired-devices list, or a loading / permission / off / empty message.
class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.loading,
    required this.paired,
    required this.l10n,
    required this.selectedAddress,
    required this.onSelect,
  });

  final bool loading;
  final BluetoothPairedResult? paired;
  final AppLocalizations l10n;
  final String? selectedAddress;
  final void Function(BluetoothDeviceInfo) onSelect;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.md),
        child: RestoflowInlineSpinner(size: 18),
      );
    }
    final result = paired;
    if (result == null) return const SizedBox.shrink();
    if (!result.ok) {
      final message = switch (result.error!) {
        BluetoothPrinterError.permissionDenied =>
          l10n.posBluetoothPermissionRequired,
        BluetoothPrinterError.bluetoothOff => l10n.posBluetoothOff,
        _ => l10n.posBluetoothNoDevices,
      };
      return RestoflowNoticeBanner(
        key: const Key('bluetooth-error'),
        body: message,
        tone: RestoflowTone.warning,
      );
    }
    if (result.devices.isEmpty) {
      return RestoflowNoticeBanner(
        key: const Key('bluetooth-empty'),
        body: l10n.posBluetoothNoDevices,
        tone: RestoflowTone.info,
      );
    }
    return Column(
      children: [
        for (final device in result.devices)
          _DeviceTile(
            key: Key('bluetooth-device-${device.address}'),
            device: device,
            selected: device.address == selectedAddress,
            onTap: () => onSelect(device),
          ),
      ],
    );
  }
}

/// A selectable paired-device row (a radio icon + name + address).
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final BluetoothDeviceInfo device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        device.name.isEmpty ? device.address : device.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        device.address,
        textDirection: TextDirection.ltr,
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.l10n,
    required this.status,
    required this.saved,
    required this.selectedAddress,
    this.failCategory,
    this.failDetail,
  });

  final AppLocalizations l10n;
  final _BtStatus status;
  final PosBluetoothPrinterConfig? saved;
  final String? selectedAddress;

  /// PRINT-BLUETOOTH-RECOVERY-001: the last test failure's category + raw
  /// diagnostic detail — see [_failureLabel].
  final pp.PrinterErrorCategory? failCategory;
  final String? failDetail;

  /// The category-specific failure message — permission / adapter-off /
  /// not-paired / connect / write each read differently (and differently from
  /// the Wi-Fi failure copy); anything else keeps the generic failure copy.
  String get _failureLabel => switch (failCategory) {
    pp.PrinterErrorCategory.permissionDenied =>
      l10n.posBluetoothPermissionRequired,
    pp.PrinterErrorCategory.bluetoothOff => l10n.posBluetoothOff,
    pp.PrinterErrorCategory.notPaired => l10n.posBluetoothNotPaired,
    pp.PrinterErrorCategory.unreachable => l10n.posBluetoothConnectFailed,
    pp.PrinterErrorCategory.writeFailed => l10n.posBluetoothWriteFailed,
    _ => l10n.posNetworkPrinterTestFailure,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, RestoflowTone tone, IconData icon) = switch (status) {
      _BtStatus.testing => (
        l10n.posNetworkPrinterTesting,
        RestoflowTone.info,
        Icons.hourglass_top,
      ),
      _BtStatus.success => (
        l10n.posNetworkPrinterTestSuccess,
        RestoflowTone.success,
        Icons.check_circle_outline,
      ),
      _BtStatus.failure => (
        _failureLabel,
        RestoflowTone.danger,
        Icons.error_outline,
      ),
      _BtStatus.idle =>
        saved != null
            ? (
                l10n.posNetworkPrinterStatusSaved,
                RestoflowTone.success,
                Icons.print_outlined,
              )
            : selectedAddress != null
            ? (
                l10n.posBluetoothSelectHint,
                RestoflowTone.neutral,
                Icons.bluetooth,
              )
            : (
                l10n.posNetworkPrinterStatusNotConfigured,
                RestoflowTone.neutral,
                Icons.info_outline,
              ),
    };
    final style = tone.styleOf(theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: const Key('bluetooth-status'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: RestoflowIconSizes.sm, color: style.accent),
            const SizedBox(width: RestoflowSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: style.accent),
              ),
            ),
          ],
        ),
        // The raw diagnostic (attempt breakdown / byte counts) — technical
        // DATA, small and LTR, shown only on a failure. Never printed on
        // paper, never sent anywhere (a MAC address stays on this device).
        if (status == _BtStatus.failure && failDetail != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: RestoflowSpacing.lg,
              top: RestoflowSpacing.xxs,
            ),
            child: Text(
              failDetail!,
              key: const Key('bluetooth-failure-detail'),
              textDirection: TextDirection.ltr,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
