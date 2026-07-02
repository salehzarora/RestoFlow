import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show
        AdminPageHeader,
        AdminPill,
        AdminResult,
        AdminStateView,
        adminFailureMessage;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'printer_models.dart';
import 'printers_repository.dart';

/// The dashboard Printers surface (RF-150 backend): list, add, edit,
/// enable/disable, route-to-station, and remove printer CONFIGURATION.
///
/// HONESTY: this page manages configuration only. It never claims a print
/// happened — print transport (dispatching bytes to hardware) is not wired in
/// this build, and the page says so (no fake "printed" success anywhere).
class PrintersScreen extends StatefulWidget {
  const PrintersScreen({required this.repository, super.key});

  final PrintersRepository repository;

  @override
  State<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends State<PrintersScreen> {
  late Future<AdminResult<PrintersSnapshot>> _future = widget.repository.load();

  void _reload() {
    // Braces, not an arrow: the setState callback must not RETURN the future.
    setState(() {
      _future = widget.repository.load();
    });
  }

  Future<void> _run(Future<AdminResult<void>> Function() op) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await op();
    if (!mounted) return;
    result.fold(
      (_) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.printersSaved)));
        _reload();
      },
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(adminFailureMessage(l10n, failure))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          title: l10n.printersTitle,
          subtitle: l10n.printersSubtitle,
          actions: [
            FilledButton.icon(
              onPressed: () => _showPrinterDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.printersAdd),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RestoflowSpacing.lg,
            0,
            RestoflowSpacing.lg,
            RestoflowSpacing.sm,
          ),
          child: RestoflowNoticeBanner(
            tone: RestoflowTone.info,
            icon: Icons.print_disabled_outlined,
            title: l10n.printersTransportNoticeTitle,
            body: l10n.printersTransportNotice,
          ),
        ),
        Expanded(
          child: FutureBuilder<AdminResult<PrintersSnapshot>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) return AdminStateView.loading();
              return snap.data!.fold(
                (snapshot) => _list(context, snapshot),
                (failure) => AdminStateView.fromFailure(
                  context,
                  failure,
                  onRetry: _reload,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, PrintersSnapshot snapshot) {
    final l10n = AppLocalizations.of(context);
    if (snapshot.printers.isEmpty) {
      return AdminStateView(
        icon: Icons.print_outlined,
        title: l10n.printersEmptyTitle,
        body: l10n.printersEmptyBody,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RestoflowSpacing.lg,
        0,
        RestoflowSpacing.lg,
        RestoflowSpacing.xxl,
      ),
      children: [
        for (final printer in snapshot.printers)
          Padding(
            padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
            child: _PrinterCard(
              printer: printer,
              snapshot: snapshot,
              onEdit: () => _showPrinterDialog(context, printer: printer),
              onToggleEnabled: (enabled) => _run(
                () => widget.repository.upsertPrinter(
                  id: printer.id,
                  displayName: printer.displayName,
                  connectionType: printer.connectionType,
                  role: printer.role,
                  paperWidth: printer.paperWidth,
                  connectionConfig: printer.connectionConfig,
                  isEnabled: enabled,
                ),
              ),
              onRoute: () => _showRouteDialog(context, printer, snapshot),
              onDelete: () => _confirmDelete(context, printer),
            ),
          ),
      ],
    );
  }

  Future<void> _showPrinterDialog(
    BuildContext context, {
    PrinterDevice? printer,
  }) => showDialog<void>(
    context: context,
    builder: (_) => _PrinterDialog(
      printer: printer,
      onSave:
          ({
            required displayName,
            required connectionType,
            required role,
            required paperWidth,
            required connectionConfig,
            required isEnabled,
          }) => _run(
            () => widget.repository.upsertPrinter(
              id: printer?.id,
              displayName: displayName,
              connectionType: connectionType,
              role: role,
              paperWidth: paperWidth,
              connectionConfig: connectionConfig,
              isEnabled: isEnabled,
            ),
          ),
    ),
  );

  Future<void> _showRouteDialog(
    BuildContext context,
    PrinterDevice printer,
    PrintersSnapshot snapshot,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (snapshot.stations.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.printersNoStations)));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _RouteDialog(
        printer: printer,
        stations: snapshot.stations,
        onSave: (stationId, enabled) => _run(
          () => widget.repository.setRoute(
            stationId: stationId,
            printerDeviceId: printer.id,
            isEnabled: enabled,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PrinterDevice printer,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.printersDelete),
        content: Text(l10n.printersDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.printersDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => widget.repository.deletePrinter(printer.id));
    }
  }
}

class _PrinterCard extends StatelessWidget {
  const _PrinterCard({
    required this.printer,
    required this.snapshot,
    required this.onEdit,
    required this.onToggleEnabled,
    required this.onRoute,
    required this.onDelete,
  });

  final PrinterDevice printer;
  final PrintersSnapshot snapshot;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onRoute;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isReceipt = printer.role == PrinterRole.receipt;
    final connectionLabel = switch (printer.connectionType) {
      PrinterConnectionType.network => l10n.printersConnNetwork,
      PrinterConnectionType.bluetooth => l10n.printersConnBluetooth,
      PrinterConnectionType.usb => l10n.printersConnUsb,
    };
    final address = printer.connectionType == PrinterConnectionType.network
        ? [
            printer.host,
            printer.port,
          ].whereType<String>().where((v) => v.isNotEmpty).join(':')
        : '';
    final routedStations = snapshot
        .stationsFor(printer.id)
        .map((s) => s.name)
        .join(', ');

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: Icon(
                    isReceipt
                        ? Icons.receipt_long_outlined
                        : Icons.soup_kitchen_outlined,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        printer.displayName,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          connectionLabel,
                          if (address.isNotEmpty) address,
                          printer.paperWidth,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                AdminPill(
                  label: isReceipt
                      ? l10n.printersRoleReceipt
                      : l10n.printersRoleKitchen,
                  color: isReceipt ? scheme.primary : scheme.tertiary,
                  icon: isReceipt
                      ? Icons.receipt_long_outlined
                      : Icons.soup_kitchen_outlined,
                ),
                const SizedBox(width: RestoflowSpacing.xs),
                AdminPill(
                  label: printer.isEnabled
                      ? l10n.printersEnabled
                      : l10n.printersDisabled,
                  color: printer.isEnabled ? scheme.primary : scheme.error,
                  icon: printer.isEnabled
                      ? Icons.check_circle_outline
                      : Icons.pause_circle_outline,
                ),
              ],
            ),
            if (printer.connectionType != PrinterConnectionType.network) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: scheme.tertiary),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.printersConnConfigOnly,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.tertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (routedStations.isNotEmpty) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Row(
                children: [
                  Icon(Icons.route_outlined, size: 14, color: scheme.primary),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      '${l10n.printersRoutedTo}: $routedStations',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: RestoflowSpacing.sm),
            Row(
              children: [
                Switch(value: printer.isEnabled, onChanged: onToggleEnabled),
                const Spacer(),
                TextButton.icon(
                  onPressed: onRoute,
                  icon: const Icon(Icons.route_outlined, size: 18),
                  label: Text(l10n.printersRoute),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.printersEdit),
                ),
                IconButton(
                  tooltip: l10n.printersDelete,
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit dialog.
// ---------------------------------------------------------------------------
class _PrinterDialog extends StatefulWidget {
  const _PrinterDialog({required this.onSave, this.printer});

  final PrinterDevice? printer;
  final Future<void> Function({
    required String displayName,
    required PrinterConnectionType connectionType,
    required PrinterRole role,
    required String paperWidth,
    required Map<String, Object?> connectionConfig,
    required bool isEnabled,
  })
  onSave;

  @override
  State<_PrinterDialog> createState() => _PrinterDialogState();
}

class _PrinterDialogState extends State<_PrinterDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.printer?.displayName ?? '',
  );
  late final TextEditingController _host = TextEditingController(
    text: widget.printer?.host ?? '',
  );
  late final TextEditingController _port = TextEditingController(
    text: widget.printer?.port ?? '9100',
  );
  late final TextEditingController _bluetoothId = TextEditingController(
    text: widget.printer?.connectionConfig['bluetooth_id']?.toString() ?? '',
  );
  late final TextEditingController _usbPath = TextEditingController(
    text: widget.printer?.connectionConfig['usb_path']?.toString() ?? '',
  );
  late PrinterConnectionType _connection =
      widget.printer?.connectionType ?? PrinterConnectionType.network;
  late PrinterRole _role = widget.printer?.role ?? PrinterRole.receipt;
  late String _paper = widget.printer?.paperWidth ?? kPaperWidths.first;
  late bool _enabled = widget.printer?.isEnabled ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _bluetoothId.dispose();
    _usbPath.dispose();
    super.dispose();
  }

  Map<String, Object?> _config() => switch (_connection) {
    PrinterConnectionType.network => {
      'host': _host.text.trim(),
      'port': int.tryParse(_port.text.trim()) ?? 9100,
    },
    PrinterConnectionType.bluetooth => {
      'bluetooth_id': _bluetoothId.text.trim(),
    },
    PrinterConnectionType.usb => {'usb_path': _usbPath.text.trim()},
  };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    await widget.onSave(
      displayName: _name.text,
      connectionType: _connection,
      role: _role,
      paperWidth: _paper,
      connectionConfig: _config(),
      isEnabled: _enabled,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );
    return AlertDialog(
      title: Text(
        widget.printer == null ? l10n.printersAdd : l10n.printersEdit,
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: deco(l10n.printersFieldName),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l10n.adminErrName : null,
                ),
                const SizedBox(height: RestoflowSpacing.md),
                DropdownButtonFormField<PrinterRole>(
                  initialValue: _role,
                  decoration: deco(l10n.printersFieldRole),
                  items: [
                    DropdownMenuItem(
                      value: PrinterRole.receipt,
                      child: Text(l10n.printersRoleReceipt),
                    ),
                    DropdownMenuItem(
                      value: PrinterRole.kitchen,
                      child: Text(l10n.printersRoleKitchen),
                    ),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
                const SizedBox(height: RestoflowSpacing.md),
                DropdownButtonFormField<PrinterConnectionType>(
                  initialValue: _connection,
                  decoration: deco(l10n.printersFieldConnection),
                  items: [
                    DropdownMenuItem(
                      value: PrinterConnectionType.network,
                      child: Text(l10n.printersConnNetwork),
                    ),
                    DropdownMenuItem(
                      value: PrinterConnectionType.bluetooth,
                      child: Text(l10n.printersConnBluetooth),
                    ),
                    DropdownMenuItem(
                      value: PrinterConnectionType.usb,
                      child: Text(l10n.printersConnUsb),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _connection = v ?? _connection),
                ),
                const SizedBox(height: RestoflowSpacing.md),
                if (_connection == PrinterConnectionType.network) ...[
                  TextFormField(
                    controller: _host,
                    decoration: deco(l10n.printersFieldHost),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? l10n.printersErrHost : null,
                  ),
                  const SizedBox(height: RestoflowSpacing.md),
                  TextFormField(
                    controller: _port,
                    decoration: deco(l10n.printersFieldPort),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final port = int.tryParse((v ?? '').trim());
                      return (port == null || port < 1 || port > 65535)
                          ? l10n.printersErrPort
                          : null;
                    },
                  ),
                ] else if (_connection == PrinterConnectionType.bluetooth)
                  TextFormField(
                    controller: _bluetoothId,
                    decoration: deco(l10n.printersFieldBluetoothId),
                  )
                else
                  TextFormField(
                    controller: _usbPath,
                    decoration: deco(l10n.printersFieldUsbPath),
                  ),
                if (_connection != PrinterConnectionType.network) ...[
                  const SizedBox(height: RestoflowSpacing.md),
                  RestoflowNoticeBanner(
                    tone: RestoflowTone.warning,
                    icon: Icons.info_outline,
                    body: l10n.printersConnConfigOnly,
                  ),
                ],
                const SizedBox(height: RestoflowSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _paper,
                  decoration: deco(l10n.printersFieldPaper),
                  items: [
                    for (final width in kPaperWidths)
                      DropdownMenuItem(value: width, child: Text(width)),
                  ],
                  onChanged: (v) => setState(() => _paper = v ?? _paper),
                ),
                const SizedBox(height: RestoflowSpacing.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.printersEnabled),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.printersSave),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Route-to-station dialog.
// ---------------------------------------------------------------------------
class _RouteDialog extends StatefulWidget {
  const _RouteDialog({
    required this.printer,
    required this.stations,
    required this.onSave,
  });

  final PrinterDevice printer;
  final List<StationInfo> stations;
  final Future<void> Function(String stationId, bool enabled) onSave;

  @override
  State<_RouteDialog> createState() => _RouteDialogState();
}

class _RouteDialogState extends State<_RouteDialog> {
  late String _stationId = widget.stations.first.id;
  bool _enabled = true;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    await widget.onSave(_stationId, _enabled);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.printersRouteTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _stationId,
            decoration: InputDecoration(
              labelText: l10n.printersRouteStation,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final station in widget.stations)
                DropdownMenuItem(value: station.id, child: Text(station.name)),
            ],
            onChanged: (v) => setState(() => _stationId = v ?? _stationId),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.printersRouteActive),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.printersSave),
        ),
      ],
    );
  }
}
