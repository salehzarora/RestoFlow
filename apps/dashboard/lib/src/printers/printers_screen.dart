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

/// Whether a REAL print adapter (network dispatch transport) is registered in
/// this build.
///
/// HONESTY GUARD: this web build ships NO print adapter and NO print bridge,
/// so this is a compile-time `false`. It exists to make the
/// `printersStatusReadyNetwork` status STRUCTURALLY unreachable instead of
/// faked: a printer card may only claim "Ready via network adapter" in a
/// build that registers an actual transport and flips this single seam.
/// Never set this to `true` without wiring a real adapter.
const bool hasPrintAdapter = false;

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
          icon: Icons.print_outlined,
          actions: [
            FilledButton.icon(
              onPressed: () => _showPrinterDialog(context),
              icon: const Icon(Icons.add, size: RestoflowIconSizes.sm),
              label: Text(l10n.printersAdd),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
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
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        0,
        RestoflowSpacing.lg,
        RestoflowSpacing.xxl,
      ),
      children: [
        for (final printer in snapshot.printers)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              bottom: RestoflowSpacing.sm,
            ),
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

    // Honest per-printer status. There is deliberately NO "ready" claim in
    // this build: [hasPrintAdapter] is a compile-time false, so the
    // "Ready via network adapter" pill stays unreachable until a real
    // adapter is registered — never faked. Statuses ride the TRUE semantic
    // tones (danger red / warning amber / info blue / success green).
    final String statusLabel;
    final RestoflowTone statusTone;
    final IconData statusIcon;
    if (!printer.isEnabled) {
      statusLabel = l10n.printersStatusDisabled;
      statusTone = RestoflowTone.danger;
      statusIcon = Icons.pause_circle_outline;
    } else if (printer.connectionType != PrinterConnectionType.network) {
      statusLabel = l10n.printersStatusNeedsBridge;
      statusTone = RestoflowTone.warning;
      statusIcon = Icons.extension_off_outlined;
    } else if (hasPrintAdapter) {
      statusLabel = l10n.printersStatusReadyNetwork;
      statusTone = RestoflowTone.success;
      statusIcon = Icons.check_circle_outline;
    } else {
      statusLabel = l10n.printersStatusConfigOnly;
      statusTone = RestoflowTone.info;
      statusIcon = Icons.settings_outlined;
    }
    final warningStyle = RestoflowTone.warning.styleOf(theme);

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
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(RestoflowRadii.md),
                  ),
                  child: Icon(
                    isReceipt
                        ? Icons.receipt_long_outlined
                        : Icons.soup_kitchen_outlined,
                    size: RestoflowIconSizes.lg,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        printer.displayName,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: RestoflowSpacing.xxs),
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
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            // A Wrap, not a Row: long localized (Arabic/Hebrew) pill labels
            // flow to the next line instead of overflowing the card.
            Wrap(
              spacing: RestoflowSpacing.xs,
              runSpacing: RestoflowSpacing.xs,
              children: [
                AdminPill(
                  label: isReceipt
                      ? l10n.printersRoleReceipt
                      : l10n.printersRoleKitchen,
                  color: scheme.primary,
                  icon: isReceipt
                      ? Icons.receipt_long_outlined
                      : Icons.soup_kitchen_outlined,
                ),
                AdminPill.tone(
                  label: printer.isEnabled
                      ? l10n.printersEnabled
                      : l10n.printersDisabled,
                  tone: printer.isEnabled
                      ? RestoflowTone.success
                      : RestoflowTone.danger,
                  icon: printer.isEnabled
                      ? Icons.check_circle_outline
                      : Icons.pause_circle_outline,
                ),
                AdminPill.tone(
                  label: statusLabel,
                  tone: statusTone,
                  icon: statusIcon,
                ),
              ],
            ),
            if (printer.connectionType != PrinterConnectionType.network) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: RestoflowIconSizes.xs,
                    color: warningStyle.accent,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.printersConnConfigOnly,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: warningStyle.accent,
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
                  Icon(
                    Icons.route_outlined,
                    size: RestoflowIconSizes.xs,
                    color: scheme.primary,
                  ),
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
            // Test print stays visible but ALWAYS disabled in this build:
            // there is no print adapter/bridge to dispatch through, and the
            // repo honesty rule forbids a fake success path.
            Row(
              children: [
                TextButton(
                  onPressed: null,
                  child: Text(l10n.printersTestPrint),
                ),
                const SizedBox(width: RestoflowSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.printersTestPrintUnavailable,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Switch(value: printer.isEnabled, onChanged: onToggleEnabled),
                const Spacer(),
                TextButton.icon(
                  onPressed: onRoute,
                  icon: const Icon(
                    Icons.route_outlined,
                    size: RestoflowIconSizes.sm,
                  ),
                  label: Text(l10n.printersRoute),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: RestoflowIconSizes.sm,
                  ),
                  label: Text(l10n.printersEdit),
                ),
                IconButton(
                  tooltip: l10n.printersDelete,
                  style: RestoflowButtonStyles.dangerGhost(context),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
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
  static const int _stepPurpose = 0;
  static const int _stepConnection = 1;
  static const int _stepDetails = 2;

  final _formKey = GlobalKey<FormState>();

  /// Guided-wizard position. Editing an existing printer also starts at the
  /// first step, fully prefilled, so owners can review every choice.
  int _step = _stepPurpose;
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
    final stepTitle = switch (_step) {
      _stepPurpose => l10n.printersWizardStepPurpose,
      _stepConnection => l10n.printersWizardStepConnection,
      _ => l10n.printersWizardStepDetails,
    };
    return AlertDialog(
      title: Text(
        widget.printer == null ? l10n.printersAdd : l10n.printersEdit,
      ),
      content: SizedBox(
        width: RestoflowPanelWidths.dialog,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WizardStepDots(current: _step, total: _stepDetails + 1),
                const SizedBox(height: RestoflowSpacing.md),
                Text(stepTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: RestoflowSpacing.md),
                ...switch (_step) {
                  _stepPurpose => _purposeStep(l10n),
                  _stepConnection => _connectionStep(l10n),
                  _ => _detailsStep(context, l10n),
                },
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
        if (_step > _stepPurpose)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _step -= 1),
            child: Text(l10n.printersBack),
          ),
        if (_step < _stepDetails)
          FilledButton(
            onPressed: () => setState(() => _step += 1),
            child: Text(l10n.printersNext),
          )
        else
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(l10n.printersSave),
          ),
      ],
    );
  }

  /// Step 1 — "What do you want to print?": two big purpose tiles.
  List<Widget> _purposeStep(AppLocalizations l10n) => [
    _ChoiceTile(
      selected: _role == PrinterRole.receipt,
      icon: Icons.receipt_long_outlined,
      title: l10n.printersRoleReceipt,
      hint: l10n.printersPurposeReceiptsHint,
      onTap: () => setState(() => _role = PrinterRole.receipt),
    ),
    const SizedBox(height: RestoflowSpacing.sm),
    _ChoiceTile(
      selected: _role == PrinterRole.kitchen,
      icon: Icons.soup_kitchen_outlined,
      title: l10n.printersRoleKitchen,
      hint: l10n.printersPurposeKitchenHint,
      onTap: () => setState(() => _role = PrinterRole.kitchen),
    ),
  ];

  /// Step 2 — "How is the printer connected?": three connection tiles. The
  /// honest hint shows only under the SELECTED tile: what a network printer
  /// needs, or what Bluetooth/USB can NOT do in this web build (no fake scan).
  List<Widget> _connectionStep(AppLocalizations l10n) {
    Widget tile({
      required PrinterConnectionType type,
      required IconData icon,
      required String title,
      required String hint,
    }) => _ChoiceTile(
      selected: _connection == type,
      icon: icon,
      title: title,
      hint: _connection == type ? hint : null,
      onTap: () => setState(() => _connection = type),
    );
    return [
      tile(
        type: PrinterConnectionType.network,
        icon: Icons.wifi_outlined,
        title: l10n.printersConnNetwork,
        hint: l10n.printersConnNetworkHint,
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      tile(
        type: PrinterConnectionType.bluetooth,
        icon: Icons.bluetooth_outlined,
        title: l10n.printersConnBluetooth,
        hint: l10n.printersConnBluetoothWeb,
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      tile(
        type: PrinterConnectionType.usb,
        icon: Icons.usb_outlined,
        title: l10n.printersConnUsb,
        hint: l10n.printersConnUsbAdapter,
      ),
    ];
  }

  /// Step 3 — "Printer details": name + per-connection fields, kept SIMPLE
  /// for non-technical users. Network asks only for the host up front (port
  /// hides under Advanced, default 9100); Bluetooth/USB ask for nothing and
  /// say honestly what this build can/cannot do — no fake scan, no required
  /// identifiers (they live under Advanced).
  List<Widget> _detailsStep(BuildContext context, AppLocalizations l10n) {
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );
    return [
      TextFormField(
        controller: _name,
        decoration: deco(l10n.printersFieldName),
        validator: (v) => (v ?? '').trim().isEmpty ? l10n.adminErrName : null,
      ),
      const SizedBox(height: RestoflowSpacing.md),
      if (_connection == PrinterConnectionType.network)
        TextFormField(
          controller: _host,
          decoration: deco(l10n.printersFieldHost),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? l10n.printersErrHost : null,
        )
      else if (_connection == PrinterConnectionType.bluetooth)
        RestoflowNoticeBanner(
          tone: RestoflowTone.warning,
          icon: Icons.bluetooth_disabled_outlined,
          body: l10n.printersConnBluetoothWeb,
        )
      else
        RestoflowNoticeBanner(
          tone: RestoflowTone.warning,
          icon: Icons.usb_outlined,
          body: l10n.printersConnUsbAdapter,
        ),
      // Technical extras stay out of the main flow. A collapsed (default)
      // tile never registers its fields with the Form, so an untouched port
      // can never block a save (9100 fallback).
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: RestoflowSpacing.md),
        title: Text(
          l10n.printersAdvanced,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        children: [
          if (_connection == PrinterConnectionType.network)
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
            )
          else if (_connection == PrinterConnectionType.bluetooth)
            TextFormField(
              controller: _bluetoothId,
              decoration: deco(l10n.printersFieldBluetoothId),
            )
          else
            TextFormField(
              controller: _usbPath,
              decoration: deco(l10n.printersFieldUsbPath),
            ),
        ],
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      DropdownButtonFormField<String>(
        initialValue: _paper,
        decoration: deco(l10n.printersFieldPaper),
        items: [
          for (final width in kPaperWidths)
            DropdownMenuItem(value: width, child: Text(width)),
        ],
        onChanged: (v) => setState(() => _paper = v ?? _paper),
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.printersEnabled),
        value: _enabled,
        onChanged: (v) => setState(() => _enabled = v),
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      // ALWAYS honest, for every connection type: saving here configures the
      // printer — this build never prints.
      RestoflowNoticeBanner(
        tone: RestoflowTone.info,
        icon: Icons.info_outline,
        body: l10n.printersDialogSavesConfigOnly,
      ),
    ];
  }
}

/// A quiet, textless step indicator for the guided wizard: one dot per step,
/// the current one stretched and brand-filled. Static (no animation loops).
class _WizardStepDots extends StatelessWidget {
  const _WizardStepDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: RestoflowSpacing.xs),
          Container(
            width: i == current ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= current
                  ? scheme.primary
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(RestoflowRadii.pill),
            ),
          ),
        ],
      ],
    );
  }
}

/// One big selectable wizard choice (purpose / connection type): a bordered
/// card with a radio affordance, highlighted when selected. The optional
/// [hint] renders under the title (the wizard uses it for the always-visible
/// purpose hints and the selected-only honest connection hints).
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
    this.hint,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(RestoflowRadii.lg);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.45)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                ),
                child: Icon(
                  icon,
                  size: RestoflowIconSizes.md,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: RestoflowSpacing.xs,
                      ),
                      child: Text(title, style: theme.textTheme.titleSmall),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: RestoflowSpacing.xs),
                      Text(
                        hint!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
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
