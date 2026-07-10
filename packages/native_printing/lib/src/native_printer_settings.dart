import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'bluetooth_printer.dart';
import 'native_printer_store.dart';
import 'printer_config.dart';
import 'printer_testers.dart';

/// The localized labels the shared native-printer settings UI needs
/// (ANDROID-004). Injected by each app so the package stays l10n-agnostic: the
/// POS builds these from its `pos*` keys, the KDS from its `kdsPrinter*` (and
/// reused generic) keys. No money strings - the UI is money-free.
class NativePrinterStrings {
  const NativePrinterStrings({
    required this.transportHeading,
    required this.transportNetwork,
    required this.transportBluetooth,
    required this.networkHeading,
    required this.networkHelp,
    required this.networkIpLabel,
    required this.networkIpHint,
    required this.networkPortLabel,
    required this.networkNameLabel,
    required this.invalidIp,
    required this.invalidPort,
    required this.saveAction,
    required this.testAction,
    required this.testing,
    required this.testSuccess,
    required this.testFailure,
    required this.statusSaved,
    required this.statusNotConfigured,
    required this.networkSavedSnack,
    required this.bluetoothHeading,
    required this.bluetoothHelp,
    required this.pairedLabel,
    required this.refreshAction,
    required this.permissionRequired,
    required this.bluetoothOff,
    required this.noDevices,
    required this.selectHint,
    required this.removeAction,
    required this.removedSnack,
    required this.bluetoothSavedSnack,
    required this.btConnectFailed,
    required this.btWriteFailed,
    required this.btNotPaired,
  });

  final String transportHeading;
  final String transportNetwork;
  final String transportBluetooth;
  final String networkHeading;
  final String networkHelp;
  final String networkIpLabel;
  final String networkIpHint;
  final String networkPortLabel;
  final String networkNameLabel;
  final String invalidIp;
  final String invalidPort;
  final String saveAction;
  final String testAction;
  final String testing;
  final String testSuccess;
  final String testFailure;
  final String statusSaved;
  final String statusNotConfigured;
  final String networkSavedSnack;
  final String bluetoothHeading;
  final String bluetoothHelp;
  final String pairedLabel;
  final String refreshAction;
  final String permissionRequired;
  final String bluetoothOff;
  final String noDevices;
  final String selectHint;
  final String removeAction;
  final String removedSnack;
  final String bluetoothSavedSnack;

  /// PRINT-BLUETOOTH-RECOVERY-001: category-specific Bluetooth TEST-PRINT
  /// failure messages, so a connect failure, a mid-write failure, and a
  /// not-paired device each read differently (and differently from Wi-Fi).
  final String btConnectFailed;
  final String btWriteFailed;
  final String btNotPaired;
}

/// The on-device printer setup for a native app (ANDROID-003/004): a transport
/// chooser (Wi-Fi / Bluetooth) over the matching setup section. Shown only where
/// native printing is available (Android app) - on web the app keeps the print
/// bridge path and this section is not rendered. [deviceLabel] annotates the
/// test print. Reused by both POS and KDS.
class NativePrinterSettingsSection extends ConsumerWidget {
  const NativePrinterSettingsSection({
    required this.strings,
    this.deviceLabel,
    super.key,
  });

  final NativePrinterStrings strings;
  final String? deviceLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected =
        ref.watch(selectedPrinterTransportProvider).valueOrNull ??
        PrinterTransportKind.network;

    return Column(
      key: const Key('printer-settings-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.transportHeading,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PrinterTransportKind>(
            key: const Key('printer-transport-toggle'),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            segments: [
              ButtonSegment<PrinterTransportKind>(
                value: PrinterTransportKind.network,
                icon: const Icon(Icons.wifi),
                label: Text(strings.transportNetwork),
              ),
              ButtonSegment<PrinterTransportKind>(
                value: PrinterTransportKind.bluetooth,
                icon: const Icon(Icons.bluetooth),
                label: Text(strings.transportBluetooth),
              ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) => ref
                .read(selectedPrinterTransportProvider.notifier)
                .select(selection.first),
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        switch (selected) {
          PrinterTransportKind.network => _NetworkPrinterSection(
            strings: strings,
            deviceLabel: deviceLabel,
          ),
          PrinterTransportKind.bluetooth => _BluetoothPrinterSection(
            strings: strings,
            deviceLabel: deviceLabel,
          ),
        },
      ],
    );
  }
}

enum _TestStatus { idle, testing, success, failure }

/// The on-device network-printer setup (ANDROID-002): enter a printer IP + port
/// (9100 default) + optional name, Save it locally, and Test print real ESC/POS
/// bytes straight to the printer - NO print bridge required. Money-free.
class _NetworkPrinterSection extends ConsumerStatefulWidget {
  const _NetworkPrinterSection({required this.strings, this.deviceLabel});

  final NativePrinterStrings strings;
  final String? deviceLabel;

  @override
  ConsumerState<_NetworkPrinterSection> createState() =>
      _NetworkPrinterSectionState();
}

class _NetworkPrinterSectionState
    extends ConsumerState<_NetworkPrinterSection> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '9100',
  );
  final TextEditingController _nameController = TextEditingController();

  bool _prefilled = false;
  _TestStatus _status = _TestStatus.idle;
  String? _fieldError;
  String? _lastHostPort;

  NativePrinterStrings get _s => widget.strings;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  NetworkPrinterConfig? _readFields() {
    final host = _ipController.text.trim();
    if (!isValidPrinterHost(host)) {
      setState(() => _fieldError = _s.invalidIp);
      return null;
    }
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _fieldError = _s.invalidPort);
      return null;
    }
    setState(() => _fieldError = null);
    final name = _nameController.text.trim();
    return NetworkPrinterConfig(
      host: host,
      port: port,
      name: name.isEmpty ? null : name,
    );
  }

  Future<void> _save() async {
    final config = _readFields();
    if (config == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(networkPrinterConfigProvider.notifier).save(config);
    if (!mounted) return;
    setState(() => _status = _TestStatus.idle);
    messenger.showSnackBar(SnackBar(content: Text(_s.networkSavedSnack)));
  }

  Future<void> _testPrint() async {
    final config = _readFields();
    if (config == null) return;
    // Persist what we are testing so a saved config always matches the test.
    await ref.read(networkPrinterConfigProvider.notifier).save(config);
    if (!mounted) return;
    setState(() {
      _status = _TestStatus.testing;
      _lastHostPort = '${config.host}:${config.port}';
    });
    final result = await ref
        .read(networkPrinterTesterProvider)
        .testPrint(config, deviceLabel: widget.deviceLabel);
    if (!mounted) return;
    setState(
      () => _status = result.ok ? _TestStatus.success : _TestStatus.failure,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savedAsync = ref.watch(networkPrinterConfigProvider);
    final saved = savedAsync.valueOrNull;

    if (!_prefilled && savedAsync.hasValue) {
      _prefilled = true;
      if (saved != null) {
        _ipController.text = saved.host;
        _portController.text = '${saved.port}';
        _nameController.text = saved.name ?? '';
      }
    }

    final busy = _status == _TestStatus.testing;

    return Column(
      key: const Key('network-printer-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _s.networkHeading,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        RestoflowNoticeBanner(body: _s.networkHelp, tone: RestoflowTone.info),
        const SizedBox(height: RestoflowSpacing.sm),
        TextField(
          key: const Key('network-printer-ip-field'),
          controller: _ipController,
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z.\-]')),
          ],
          onChanged: (_) => setState(() => _fieldError = null),
          decoration: InputDecoration(
            labelText: _s.networkIpLabel,
            hintText: _s.networkIpHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: TextField(
                key: const Key('network-printer-port-field'),
                controller: _portController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                onChanged: (_) => setState(() => _fieldError = null),
                decoration: InputDecoration(
                  labelText: _s.networkPortLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Expanded(
              child: TextField(
                key: const Key('network-printer-name-field'),
                controller: _nameController,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: _s.networkNameLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        if (_fieldError != null) ...[
          const SizedBox(height: RestoflowSpacing.sm),
          _InlineError(message: _fieldError!),
        ],
        const SizedBox(height: RestoflowSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('network-printer-save'),
                onPressed: busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_s.saveAction),
              ),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                key: const Key('network-printer-test'),
                onPressed: busy ? null : _testPrint,
                icon: const Icon(Icons.print_outlined),
                label: Text(_s.testAction),
              ),
            ),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        _NetworkStatusRow(
          strings: _s,
          status: _status,
          saved: saved,
          hostPort: _lastHostPort,
        ),
      ],
    );
  }
}

/// The honest network status line: not configured / saved / testing / succeeded
/// / failed. Never claims a hardware paper-print - success = bytes delivered.
class _NetworkStatusRow extends StatelessWidget {
  const _NetworkStatusRow({
    required this.strings,
    required this.status,
    required this.saved,
    required this.hostPort,
  });

  final NativePrinterStrings strings;
  final _TestStatus status;
  final NetworkPrinterConfig? saved;
  final String? hostPort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, RestoflowTone tone, IconData icon) = switch (status) {
      _TestStatus.testing => (
        strings.testing,
        RestoflowTone.info,
        Icons.hourglass_top,
      ),
      _TestStatus.success => (
        _withHostPort(strings.testSuccess),
        RestoflowTone.success,
        Icons.check_circle_outline,
      ),
      _TestStatus.failure => (
        strings.testFailure,
        RestoflowTone.danger,
        Icons.error_outline,
      ),
      _TestStatus.idle =>
        saved != null
            ? (
                _withHostPort(strings.statusSaved),
                RestoflowTone.success,
                Icons.print_outlined,
              )
            : (
                strings.statusNotConfigured,
                RestoflowTone.neutral,
                Icons.info_outline,
              ),
    };
    final style = tone.styleOf(theme);
    return Row(
      key: const Key('network-printer-status'),
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
    );
  }

  String _withHostPort(String base) {
    final hp =
        hostPort ?? (saved == null ? null : '${saved!.host}:${saved!.port}');
    return hp == null ? base : '$base · $hp';
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = RestoflowTone.danger.styleOf(theme).accent;
    return Row(
      key: const Key('network-printer-error'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: RestoflowIconSizes.sm, color: accent),
        const SizedBox(width: RestoflowSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: accent),
          ),
        ),
      ],
    );
  }
}

enum _BtStatus { idle, testing, success, failure }

/// The on-device Bluetooth printer setup (ANDROID-003): list bonded/paired
/// Bluetooth devices, pick one, Save it locally, Test print raw ESC/POS bytes,
/// and Remove it - NO print bridge required. The MVP uses devices already paired
/// in Android Bluetooth settings (no in-app discovery). Money-free.
class _BluetoothPrinterSection extends ConsumerStatefulWidget {
  const _BluetoothPrinterSection({required this.strings, this.deviceLabel});

  final NativePrinterStrings strings;
  final String? deviceLabel;

  @override
  ConsumerState<_BluetoothPrinterSection> createState() =>
      _BluetoothPrinterSectionState();
}

class _BluetoothPrinterSectionState
    extends ConsumerState<_BluetoothPrinterSection> {
  BluetoothPairedResult? _paired;
  bool _loading = false;
  _BtStatus _status = _BtStatus.idle;
  String? _selectedAddress;
  String? _selectedName;

  /// PRINT-BLUETOOTH-RECOVERY-001: what KIND of failure the last test hit
  /// (drives the category-specific message) + the developer diagnostic detail
  /// (adapter/permission/attempt breakdown — shown small, never printed).
  pp.PrinterErrorCategory? _failCategory;
  String? _failDetail;

  NativePrinterStrings get _s => widget.strings;

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

  Future<void> _save() async {
    final address = _selectedAddress;
    if (address == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(bluetoothPrinterConfigProvider.notifier)
        .save(BluetoothPrinterConfig(address: address, name: _selectedName));
    if (!mounted) return;
    setState(() => _status = _BtStatus.idle);
    messenger.showSnackBar(SnackBar(content: Text(_s.bluetoothSavedSnack)));
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(bluetoothPrinterConfigProvider.notifier).clear();
    if (!mounted) return;
    setState(() {
      _status = _BtStatus.idle;
      _selectedAddress = null;
      _selectedName = null;
    });
    messenger.showSnackBar(SnackBar(content: Text(_s.removedSnack)));
  }

  Future<void> _testPrint() async {
    final address = _selectedAddress;
    if (address == null) return;
    setState(() {
      _status = _BtStatus.testing;
      _failCategory = null;
      _failDetail = null;
    });
    final result = await ref
        .read(bluetoothPrinterTesterProvider)
        .testPrint(
          BluetoothPrinterConfig(address: address, name: _selectedName),
          deviceLabel: widget.deviceLabel,
        );
    if (!mounted) return;
    setState(() {
      _status = result.ok ? _BtStatus.success : _BtStatus.failure;
      // PRINT-BLUETOOTH-RECOVERY-001: keep the failure KIND (category-specific
      // message) + the raw diagnostic so the operator sees exactly what failed.
      _failCategory = result.ok ? null : result.category;
      _failDetail = result.ok ? null : result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = ref.watch(bluetoothPrinterConfigProvider).valueOrNull;
    // The effective selection: an in-session pick, else the saved printer.
    final selectedAddress = _selectedAddress ?? saved?.address;
    final canAct = selectedAddress != null && _status != _BtStatus.testing;

    return Column(
      key: const Key('bluetooth-printer-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _s.bluetoothHeading,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        RestoflowNoticeBanner(body: _s.bluetoothHelp, tone: RestoflowTone.info),
        const SizedBox(height: RestoflowSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                _s.pairedLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('bluetooth-refresh'),
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh, size: RestoflowIconSizes.sm),
              label: Text(_s.refreshAction),
            ),
          ],
        ),
        _DeviceList(
          loading: _loading,
          paired: _paired,
          strings: _s,
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
                key: const Key('bluetooth-save'),
                onPressed: canAct ? _save : null,
                icon: const Icon(Icons.save_outlined),
                label: Text(_s.saveAction),
              ),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                key: const Key('bluetooth-test'),
                onPressed: canAct ? _testPrint : null,
                icon: const Icon(Icons.print_outlined),
                label: Text(_s.testAction),
              ),
            ),
          ],
        ),
        if (saved != null) ...[
          const SizedBox(height: RestoflowSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('bluetooth-remove'),
              onPressed: _remove,
              icon: const Icon(
                Icons.delete_outline,
                size: RestoflowIconSizes.sm,
              ),
              label: Text(_s.removeAction),
              style: TextButton.styleFrom(
                foregroundColor: RestoflowTone.danger.styleOf(theme).accent,
              ),
            ),
          ),
        ],
        const SizedBox(height: RestoflowSpacing.xs),
        _BtStatusRow(
          strings: _s,
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
    required this.strings,
    required this.selectedAddress,
    required this.onSelect,
  });

  final bool loading;
  final BluetoothPairedResult? paired;
  final NativePrinterStrings strings;
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
        BluetoothPrinterError.permissionDenied => strings.permissionRequired,
        BluetoothPrinterError.bluetoothOff => strings.bluetoothOff,
        _ => strings.noDevices,
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
        body: strings.noDevices,
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

class _BtStatusRow extends StatelessWidget {
  const _BtStatusRow({
    required this.strings,
    required this.status,
    required this.saved,
    required this.selectedAddress,
    this.failCategory,
    this.failDetail,
  });

  final NativePrinterStrings strings;
  final _BtStatus status;
  final BluetoothPrinterConfig? saved;
  final String? selectedAddress;

  /// PRINT-BLUETOOTH-RECOVERY-001: the last test failure's category (drives
  /// the specific message) and diagnostic detail (small secondary line).
  final pp.PrinterErrorCategory? failCategory;
  final String? failDetail;

  /// The category-specific failure message — permission / adapter-off /
  /// not-paired / connect / write each read differently; anything else keeps
  /// the generic failure copy.
  String get _failureLabel => switch (failCategory) {
    pp.PrinterErrorCategory.permissionDenied => strings.permissionRequired,
    pp.PrinterErrorCategory.bluetoothOff => strings.bluetoothOff,
    pp.PrinterErrorCategory.notPaired => strings.btNotPaired,
    pp.PrinterErrorCategory.unreachable => strings.btConnectFailed,
    pp.PrinterErrorCategory.writeFailed => strings.btWriteFailed,
    _ => strings.testFailure,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, RestoflowTone tone, IconData icon) = switch (status) {
      _BtStatus.testing => (
        strings.testing,
        RestoflowTone.info,
        Icons.hourglass_top,
      ),
      _BtStatus.success => (
        strings.testSuccess,
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
            ? (strings.statusSaved, RestoflowTone.success, Icons.print_outlined)
            : selectedAddress != null
            ? (strings.selectHint, RestoflowTone.neutral, Icons.bluetooth)
            : (
                strings.statusNotConfigured,
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
        // DATA, deliberately small and LTR; shown only on a failure, never
        // printed on paper, never sent anywhere.
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
