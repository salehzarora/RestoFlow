import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../print/network_printer_tester.dart';
import '../state/pos_device_context.dart';
import '../state/pos_network_printer_config.dart';

// posNativePrintingAvailableProvider moved to pos_printer_transport.dart
// (ANDROID-003); re-exported so existing importers/tests keep resolving it.
export '../state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;

enum _TestStatus { idle, testing, success, failure }

/// The on-device network-printer setup (ANDROID-002): enter a printer IP + port
/// (9100 default) + optional name, Save it locally, and Test print real ESC/POS
/// bytes straight to the printer — NO print bridge required. Shown only where
/// native printing is available (Android app). Money-free.
class NetworkPrinterSection extends ConsumerStatefulWidget {
  const NetworkPrinterSection({super.key});

  @override
  ConsumerState<NetworkPrinterSection> createState() =>
      _NetworkPrinterSectionState();
}

class _NetworkPrinterSectionState extends ConsumerState<NetworkPrinterSection> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '9100',
  );
  final TextEditingController _nameController = TextEditingController();

  bool _prefilled = false;
  _TestStatus _status = _TestStatus.idle;

  /// Inline validation error (invalid IP/port), or null.
  String? _fieldError;

  /// The last transport diagnostic for a failed test, appended to the message.
  String? _lastHostPort;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  PosNetworkPrinterConfig? _readFields(AppLocalizations l10n) {
    final host = _ipController.text.trim();
    if (!_isValidHost(host)) {
      setState(() => _fieldError = l10n.posNetworkPrinterInvalidIp);
      return null;
    }
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _fieldError = l10n.posNetworkPrinterInvalidPort);
      return null;
    }
    setState(() => _fieldError = null);
    final name = _nameController.text.trim();
    return PosNetworkPrinterConfig(
      host: host,
      port: port,
      name: name.isEmpty ? null : name,
    );
  }

  Future<void> _save(AppLocalizations l10n) async {
    final config = _readFields(l10n);
    if (config == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(posNetworkPrinterConfigProvider.notifier).save(config);
    if (!mounted) return;
    setState(() => _status = _TestStatus.idle);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.posNetworkPrinterSavedSnack)),
    );
  }

  Future<void> _testPrint(AppLocalizations l10n) async {
    final config = _readFields(l10n);
    if (config == null) return;
    // Persist what we are testing so a saved config always matches the test.
    await ref.read(posNetworkPrinterConfigProvider.notifier).save(config);
    if (!mounted) return;
    setState(() {
      _status = _TestStatus.testing;
      _lastHostPort = '${config.host}:${config.port}';
    });
    final deviceLabel = ref.read(posDeviceContextProvider)?.displayName;
    final result = await ref
        .read(networkPrinterTesterProvider)
        .testPrint(config, deviceLabel: deviceLabel);
    if (!mounted) return;
    setState(
      () => _status = result.ok ? _TestStatus.success : _TestStatus.failure,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final savedAsync = ref.watch(posNetworkPrinterConfigProvider);
    final saved = savedAsync.valueOrNull;

    // Prefill the fields once from the saved config (if any).
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
          l10n.posNetworkPrinterHeading,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        RestoflowNoticeBanner(
          body: l10n.posNetworkPrinterHelp,
          tone: RestoflowTone.info,
        ),
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
            labelText: l10n.posNetworkPrinterIpLabel,
            hintText: l10n.posNetworkPrinterIpHint,
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
                  labelText: l10n.posNetworkPrinterPortLabel,
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
                  labelText: l10n.posNetworkPrinterNameLabel,
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
                onPressed: busy ? null : () => _save(l10n),
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.posNetworkPrinterSaveAction),
              ),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                key: const Key('network-printer-test'),
                onPressed: busy ? null : () => _testPrint(l10n),
                icon: const Icon(Icons.print_outlined),
                label: Text(l10n.posNetworkPrinterTestAction),
              ),
            ),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        _StatusRow(
          l10n: l10n,
          status: _status,
          saved: saved,
          hostPort: _lastHostPort,
        ),
      ],
    );
  }
}

/// The honest status line: not configured / saved / testing / succeeded /
/// failed. Never claims a hardware paper-print — success = bytes delivered.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.l10n,
    required this.status,
    required this.saved,
    required this.hostPort,
  });

  final AppLocalizations l10n;
  final _TestStatus status;
  final PosNetworkPrinterConfig? saved;
  final String? hostPort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, RestoflowTone tone, IconData icon) = switch (status) {
      _TestStatus.testing => (
        l10n.posNetworkPrinterTesting,
        RestoflowTone.info,
        Icons.hourglass_top,
      ),
      _TestStatus.success => (
        _withHostPort(l10n.posNetworkPrinterTestSuccess),
        RestoflowTone.success,
        Icons.check_circle_outline,
      ),
      _TestStatus.failure => (
        l10n.posNetworkPrinterTestFailure,
        RestoflowTone.danger,
        Icons.error_outline,
      ),
      _TestStatus.idle =>
        saved != null
            ? (
                _withHostPort(l10n.posNetworkPrinterStatusSaved),
                RestoflowTone.success,
                Icons.print_outlined,
              )
            : (
                l10n.posNetworkPrinterStatusNotConfigured,
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

  /// Appends the tested/saved `host:port` (device data, not translatable) to a
  /// localized status label.
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

/// Accepts a dotted IPv4 (each octet 0-255) or a simple hostname.
bool _isValidHost(String value) {
  final v = value.trim();
  if (v.isEmpty || v.contains(' ')) return false;
  final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
  final m = ipv4.firstMatch(v);
  if (m != null) {
    for (var i = 1; i <= 4; i++) {
      if (int.parse(m.group(i)!) > 255) return false;
    }
    return true;
  }
  // Hostname: letters/digits/dots/hyphens, must contain a letter.
  return RegExp(r'^[A-Za-z0-9.\-]+$').hasMatch(v) &&
      RegExp(r'[A-Za-z]').hasMatch(v);
}
