import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';

import '../design/kiosk_theme.dart';
import '../print/kiosk_receipt_auto_print.dart';
import '../widgets/kiosk_chrome.dart';

/// KIOSK-001-103 §8/§9 — the REAL, PIN-protected kiosk printer section.
///
/// CUSTOMER RECEIPT only — the kiosk never configures kitchen printing. The
/// section reuses the shared `restoflow_native_printing` store under the
/// KIOSK namespace (`restoflow.printer.*.kiosk.<deviceId>` — never a POS/KDS
/// key), the shared Wi-Fi/TCP + Bluetooth Classic transports, and the shared
/// testers. On web the whole native surface is honestly unavailable
/// (ordering is unaffected); the media profile stays the project's
/// continuous-80 receipt-roll standard.
class KioskPrinterSection extends ConsumerStatefulWidget {
  const KioskPrinterSection({super.key});

  @override
  ConsumerState<KioskPrinterSection> createState() =>
      _KioskPrinterSectionState();
}

class _KioskPrinterSectionState extends ConsumerState<KioskPrinterSection> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '9100');
  bool _seeded = false;
  String?
  _statusKey; // saved | test-ok | test-failed | invalid-host | invalid-port | bt-unavailable
  bool _busy = false;
  List<BluetoothDeviceInfo>? _paired;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _seedFrom(NetworkPrinterConfig? config) {
    if (_seeded || config == null) return;
    _seeded = true;
    _host.text = config.host;
    _port.text = '${config.port}';
  }

  Future<void> _saveNetwork() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (!isValidPrinterHost(host)) {
      setState(() => _statusKey = 'invalid-host');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _statusKey = 'invalid-port');
      return;
    }
    await ref
        .read(networkPrinterConfigProvider.notifier)
        .save(NetworkPrinterConfig(host: host, port: port, name: 'Kiosk'));
    await ref
        .read(selectedPrinterTransportProvider.notifier)
        .select(PrinterTransportKind.network);
    if (mounted) setState(() => _statusKey = 'saved');
  }

  Future<void> _pickPaired() async {
    setState(() {
      _busy = true;
      _statusKey = null;
    });
    final connector = ref.read(bluetoothPrinterConnectorProvider);
    try {
      final allowed = await connector.ensurePermissions();
      if (!allowed) {
        if (mounted) {
          setState(() {
            _busy = false;
            _statusKey = 'bt-unavailable';
            _paired = null;
          });
        }
        return;
      }
      final result = await connector.pairedDevices();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (result.error != null) {
          _statusKey = 'bt-unavailable';
          _paired = null;
        } else {
          _paired = result.devices;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusKey = 'bt-unavailable';
          _paired = null;
        });
      }
    }
  }

  Future<void> _saveBluetooth(BluetoothDeviceInfo device) async {
    await ref
        .read(bluetoothPrinterConfigProvider.notifier)
        .save(
          BluetoothPrinterConfig(address: device.address, name: device.name),
        );
    await ref
        .read(selectedPrinterTransportProvider.notifier)
        .select(PrinterTransportKind.bluetooth);
    if (mounted) {
      setState(() {
        _statusKey = 'saved';
        _paired = null;
      });
    }
  }

  Future<void> _testPrint() async {
    setState(() {
      _busy = true;
      _statusKey = null;
    });
    final transport =
        ref.read(selectedPrinterTransportProvider).valueOrNull ??
        PrinterTransportKind.network;
    bool ok = false;
    try {
      switch (transport) {
        case PrinterTransportKind.network:
          final config = ref.read(networkPrinterConfigProvider).valueOrNull;
          if (config != null) {
            final result = await ref
                .read(networkPrinterTesterProvider)
                .testPrint(config, deviceLabel: 'Kiosk');
            ok = result.ok;
          }
        case PrinterTransportKind.bluetooth:
          final config = ref.read(bluetoothPrinterConfigProvider).valueOrNull;
          if (config != null) {
            final result = await ref
                .read(bluetoothPrinterTesterProvider)
                .testPrint(config, deviceLabel: 'Kiosk');
            ok = result.ok;
          }
      }
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _statusKey = ok ? 'test-ok' : 'test-failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = ref.watch(nativePrintingAvailableProvider);
    final autoPrint =
        ref.watch(kioskAutoPrintReceiptProvider).valueOrNull ?? false;
    final transport =
        ref.watch(selectedPrinterTransportProvider).valueOrNull ??
        PrinterTransportKind.network;
    final network = ref.watch(networkPrinterConfigProvider).valueOrNull;
    final bluetooth = ref.watch(bluetoothPrinterConfigProvider).valueOrNull;
    _seedFrom(network);

    return Container(
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
            l10n.kioskPrinterSection,
            style: KioskType.body(30, FontWeight.w800),
          ),
          const SizedBox(height: 20),
          if (!available)
            Text(
              l10n.kioskPrinterWebUnavailable,
              key: const Key('kiosk-printer-web-unavailable'),
              style: KioskType.body(
                21,
                FontWeight.w500,
                color: KioskColors.textMuted,
              ),
            )
          else ...[
            // ---- auto-print toggle (default OFF) ------------------------
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.kioskPrinterAutoPrint,
                        style: KioskType.body(23, FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.kioskPrinterAutoPrintHint,
                        style: KioskType.body(
                          18,
                          FontWeight.w500,
                          color: KioskColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const Key('kiosk-printer-autoprint'),
                  value: autoPrint,
                  activeThumbColor: KioskColors.accentTop,
                  onChanged: (v) => ref
                      .read(kioskAutoPrintReceiptProvider.notifier)
                      .setEnabled(v),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // ---- transport ---------------------------------------------
            Wrap(
              spacing: 12,
              children: [
                for (final kind in PrinterTransportKind.values)
                  KioskPressable(
                    onTap: () => ref
                        .read(selectedPrinterTransportProvider.notifier)
                        .select(kind),
                    child: Container(
                      key: Key('kiosk-printer-transport-${kind.name}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: transport == kind
                            ? KioskColors.accentTop
                            : KioskColors.glass(.07),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        kind == PrinterTransportKind.network
                            ? l10n.kioskPrinterTransportWifi
                            : l10n.kioskPrinterTransportBluetooth,
                        style: KioskType.body(
                          20,
                          FontWeight.w700,
                          color: transport == kind
                              ? Colors.white
                              : KioskColors.textSoft,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            if (transport == PrinterTransportKind.network) ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: const Key('kiosk-printer-host'),
                      controller: _host,
                      style: KioskType.body(21, FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: l10n.kioskPrinterHost,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      key: const Key('kiosk-printer-port'),
                      controller: _port,
                      keyboardType: TextInputType.number,
                      style: KioskType.body(21, FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: l10n.kioskPrinterPort,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ] else ...[
              if (bluetooth != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${l10n.kioskPrinterCurrentSaved} '
                    '${bluetooth.name ?? bluetooth.address}',
                    key: const Key('kiosk-printer-bt-current'),
                    style: KioskType.body(
                      20,
                      FontWeight.w600,
                      color: KioskColors.textSoft,
                    ),
                  ),
                ),
              KioskPressable(
                onTap: _busy ? null : _pickPaired,
                child: Container(
                  key: const Key('kiosk-printer-bt-pick'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: KioskColors.glass(.07),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    l10n.kioskPrinterBtPick,
                    style: KioskType.body(20, FontWeight.w700),
                  ),
                ),
              ),
              if (_paired != null) ...[
                const SizedBox(height: 12),
                if (_paired!.isEmpty)
                  Text(
                    l10n.kioskPrinterBtNone,
                    style: KioskType.body(
                      19,
                      FontWeight.w500,
                      color: KioskColors.textMuted,
                    ),
                  )
                else
                  for (final device in _paired!)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: KioskPressable(
                        onTap: () => _saveBluetooth(device),
                        child: Container(
                          key: Key('kiosk-printer-bt-${device.address}'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: KioskColors.glass(.05),
                            border: Border.all(color: KioskColors.glass(.14)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            device.name.isEmpty ? device.address : device.name,
                            style: KioskType.body(20, FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 18),
            ],
            // ---- actions + status --------------------------------------
            Wrap(
              spacing: 14,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (transport == PrinterTransportKind.network)
                  KioskAccentPill(
                    key: const Key('kiosk-printer-save'),
                    onTap: _busy ? null : _saveNetwork,
                    height: 74,
                    horizontalPadding: 36,
                    child: Text(
                      l10n.kioskPrinterSave,
                      style: KioskType.body(
                        21,
                        FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                KioskPressable(
                  onTap: _busy ? null : _testPrint,
                  child: Container(
                    key: const Key('kiosk-printer-test'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: KioskColors.glass(.07),
                      border: Border.all(color: KioskColors.glass(.2)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.kioskPrinterTest,
                      style: KioskType.body(21, FontWeight.w700),
                    ),
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                if (_statusKey != null)
                  Text(
                    switch (_statusKey!) {
                      'saved' => l10n.kioskPrinterSaved,
                      'test-ok' => l10n.kioskPrinterTestOk,
                      'test-failed' => l10n.kioskPrinterTestFailed,
                      'invalid-host' => l10n.kioskPrinterInvalidHost,
                      'invalid-port' => l10n.kioskPrinterInvalidPort,
                      _ => l10n.kioskPrinterBtUnavailable,
                    },
                    key: const Key('kiosk-printer-status'),
                    style: KioskType.body(
                      20,
                      FontWeight.w700,
                      color: switch (_statusKey!) {
                        'saved' || 'test-ok' => const Color(0xFF4ADE80),
                        _ => const Color(0xFFFFB020),
                      },
                    ),
                  ),
              ],
            ),
            if (network == null && bluetooth == null) ...[
              const SizedBox(height: 14),
              Text(
                l10n.kioskPrinterNotConfigured,
                key: const Key('kiosk-printer-not-configured'),
                style: KioskType.body(
                  19,
                  FontWeight.w500,
                  color: KioskColors.textMuted,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
