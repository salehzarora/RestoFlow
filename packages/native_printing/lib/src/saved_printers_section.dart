import 'package:flutter/material.dart';

import 'network_printer_profiles.dart';
import 'printer_config.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — the shared "Saved printers" UI.
///
/// ONE list/add/edit/delete surface used by BOTH the POS printer section and the
/// KDS printer settings, so the two apps cannot drift apart. It owns no state
/// beyond its own dialogs: the profile collection and the active selection come
/// in as data, and every mutation goes back out through the callbacks, which the
/// apps wire to their own device-scoped profile providers.
///
/// It never prints, never connects, and never persists anything itself.

/// The localized strings this section needs. Each app supplies them from its own
/// ARB so nothing user-visible is hardcoded here.
class SavedPrintersStrings {
  const SavedPrintersStrings({
    required this.heading,
    required this.addAction,
    required this.editAction,
    required this.deleteAction,
    required this.activeBadge,
    required this.defaultName,
    required this.nameLabel,
    required this.hostLabel,
    required this.portLabel,
    required this.empty,
    required this.loading,
    required this.loadFailure,
    required this.retryAction,
    required this.deleteConfirmTitle,
    required this.deleteConfirmBody,
    required this.deleteActiveWarning,
    required this.duplicateError,
    required this.nameRequired,
    required this.invalidHost,
    required this.invalidPort,
    required this.saveAction,
    required this.cancelAction,
  });

  final String heading;
  final String addAction;
  final String editAction;
  final String deleteAction;
  final String activeBadge;

  /// The localized name given ONCE to a profile migrated from the previous
  /// single configuration (the store deliberately stores it blank).
  final String defaultName;
  final String nameLabel;
  final String hostLabel;
  final String portLabel;
  final String empty;
  final String loading;
  final String loadFailure;
  final String retryAction;
  final String deleteConfirmTitle;

  /// Names the printer being removed.
  final String Function(String name) deleteConfirmBody;
  final String deleteActiveWarning;
  final String duplicateError;
  final String nameRequired;
  final String invalidHost;
  final String invalidPort;
  final String saveAction;
  final String cancelAction;
}

/// The outcome of an add/edit attempt, so the form can show the right message
/// instead of silently closing.
enum SavedPrinterSaveResult { saved, duplicate, invalid, failed }

class SavedPrintersSection extends StatefulWidget {
  const SavedPrintersSection({
    super.key,
    required this.strings,
    required this.profiles,
    required this.activeId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
    this.loading = false,
    this.failed = false,
    this.onRetry,
    this.defaultPort = 9100,
    this.keySuffix = '',
  });

  final SavedPrintersStrings strings;
  final List<NetworkPrinterProfile> profiles;

  /// Null = this slot is honestly unconfigured.
  final String? activeId;

  /// True only while the FIRST load is in flight — the empty state must never
  /// be shown in its place.
  final bool loading;
  final bool failed;
  final VoidCallback? onRetry;

  final Future<void> Function(String id) onSelect;
  final Future<SavedPrinterSaveResult> Function(
    String name,
    NetworkPrinterConfig config,
  )
  onAdd;
  final Future<SavedPrinterSaveResult> Function(NetworkPrinterProfile profile)
  onEdit;
  final Future<void> Function(String id) onRemove;

  /// The default port pre-filled in the Add form (9100 today) — never the only
  /// port the form accepts.
  final int defaultPort;

  /// Distinguishes two sections in one tree (the POS receipt/kitchen slots).
  final String keySuffix;

  @override
  State<SavedPrintersSection> createState() => _SavedPrintersSectionState();
}

class _SavedPrintersSectionState extends State<SavedPrintersSection> {
  /// Guards against a double submit while a save is in flight.
  bool _busy = false;

  Key _k(String base) => Key('$base${widget.keySuffix}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.strings;
    return Column(
      key: _k('saved-printers-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(s.heading, style: theme.textTheme.titleSmall)),
            TextButton.icon(
              key: _k('saved-printers-add'),
              onPressed: _busy ? null : () => _openForm(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(s.addAction),
            ),
          ],
        ),
        if (widget.failed)
          Padding(
            key: _k('saved-printers-error'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.loadFailure,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                if (widget.onRetry != null)
                  TextButton(
                    key: _k('saved-printers-retry'),
                    onPressed: widget.onRetry,
                    child: Text(s.retryAction),
                  ),
              ],
            ),
          )
        else if (widget.loading)
          // A compact loading row — NEVER the empty state, which would read as
          // "you have no saved printers" while they are still being read.
          Padding(
            key: _k('saved-printers-loading'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            // Deliberately NOT an indeterminate spinner: a perpetual animation
            // never lets a settings sheet settle (every enclosing widget test
            // would hang), and a one-line notice reads just as honestly.
            child: Row(
              children: [
                Icon(
                  Icons.hourglass_empty,
                  size: 14,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Text(s.loading, style: theme.textTheme.bodySmall),
              ],
            ),
          )
        else if (widget.profiles.isEmpty)
          Padding(
            key: _k('saved-printers-empty'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(s.empty, style: theme.textTheme.bodySmall),
          )
        else
          for (final p in widget.profiles) _row(context, p),
      ],
    );
  }

  Widget _row(BuildContext context, NetworkPrinterProfile p) {
    final theme = Theme.of(context);
    final s = widget.strings;
    final isActive = p.id == widget.activeId;
    return InkWell(
      key: Key('saved-printer-row-${p.id}${widget.keySuffix}'),
      onTap: _busy ? null : () => widget.onSelect(p.id),
      child: Padding(
        // A comfortable tap target for a settings row.
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // The active mark is an ICON + a text badge, never colour alone.
            Icon(
              isActive ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Text(
                          s.activeBadge,
                          key: Key(
                            'saved-printer-active-${p.id}${widget.keySuffix}',
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${p.config.host}:${p.config.port}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('saved-printer-edit-${p.id}${widget.keySuffix}'),
              tooltip: s.editAction,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: _busy ? null : () => _openForm(context, existing: p),
            ),
            IconButton(
              key: Key('saved-printer-delete-${p.id}${widget.keySuffix}'),
              tooltip: s.deleteAction,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: _busy ? null : () => _confirmDelete(context, p),
            ),
          ],
        ),
      ),
    );
  }

  /// The add/edit form. Cancelling changes nothing; an invalid or duplicate
  /// entry keeps the form open with a localized message and never mutates the
  /// stored collection.
  ///
  /// The form is its OWN widget so Flutter owns the text controllers' lifecycle
  /// — disposing them when the dialog future completes would tear them down
  /// while the exit animation is still rebuilding the fields.
  Future<void> _openForm(
    BuildContext context, {
    NetworkPrinterProfile? existing,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => _ProfileFormDialog(
      strings: widget.strings,
      existing: existing,
      defaultPort: widget.defaultPort,
      keySuffix: widget.keySuffix,
      onAdd: widget.onAdd,
      onEdit: widget.onEdit,
    ),
  );

  /// Explicit confirmation, naming the printer. Deleting the ACTIVE profile
  /// additionally warns that the slot will have no printer.
  Future<void> _confirmDelete(
    BuildContext context,
    NetworkPrinterProfile p,
  ) async {
    final s = widget.strings;
    final isActive = p.id == widget.activeId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.deleteConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.deleteConfirmBody(p.name)),
            if (isActive) ...[
              const SizedBox(height: 8),
              Text(
                s.deleteActiveWarning,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: _k('saved-printer-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancelAction),
          ),
          FilledButton(
            key: _k('saved-printer-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.onRemove(p.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The add/edit form body. Owns its controllers, so they live exactly as long
/// as the dialog's element does.
class _ProfileFormDialog extends StatefulWidget {
  const _ProfileFormDialog({
    required this.strings,
    required this.existing,
    required this.defaultPort,
    required this.keySuffix,
    required this.onAdd,
    required this.onEdit,
  });

  final SavedPrintersStrings strings;
  final NetworkPrinterProfile? existing;
  final int defaultPort;
  final String keySuffix;
  final Future<SavedPrinterSaveResult> Function(
    String name,
    NetworkPrinterConfig config,
  )
  onAdd;
  final Future<SavedPrinterSaveResult> Function(NetworkPrinterProfile profile)
  onEdit;

  @override
  State<_ProfileFormDialog> createState() => _ProfileFormDialogState();
}

class _ProfileFormDialogState extends State<_ProfileFormDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _host = TextEditingController(
    text: widget.existing?.config.host ?? '',
  );
  late final TextEditingController _port = TextEditingController(
    text: '${widget.existing?.config.port ?? widget.defaultPort}',
  );

  String? _error;
  bool _saving = false;

  Key _k(String base) => Key('$base${widget.keySuffix}');

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = widget.strings;
    final name = _name.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (name.isEmpty) {
      setState(() => _error = s.nameRequired);
      return;
    }
    if (host.isEmpty) {
      setState(() => _error = s.invalidHost);
      return;
    }
    if (port == null || port <= 0 || port > 65535) {
      setState(() => _error = s.invalidPort);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final existing = widget.existing;
    final config = NetworkPrinterConfig(
      host: host,
      port: port,
      name: name,
      mediaProfileId:
          existing?.config.mediaProfileId ??
          const NetworkPrinterConfig(host: 'x').mediaProfileId,
    );
    final result = existing == null
        ? await widget.onAdd(name, config)
        : await widget.onEdit(existing.copyWith(name: name, config: config));
    if (!mounted) return;
    if (result == SavedPrinterSaveResult.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = switch (result) {
        SavedPrinterSaveResult.duplicate => s.duplicateError,
        SavedPrinterSaveResult.invalid => s.invalidHost,
        _ => s.loadFailure,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? s.addAction : s.editAction),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: _k('saved-printer-name-field'),
              controller: _name,
              decoration: InputDecoration(labelText: s.nameLabel),
              textInputAction: TextInputAction.next,
            ),
            TextField(
              key: _k('saved-printer-host-field'),
              controller: _host,
              decoration: InputDecoration(labelText: s.hostLabel),
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.next,
            ),
            TextField(
              key: _k('saved-printer-port-field'),
              controller: _port,
              decoration: InputDecoration(labelText: s.portLabel),
              keyboardType: TextInputType.number,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  key: _k('saved-printer-form-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: _k('saved-printer-cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(s.cancelAction),
        ),
        FilledButton(
          key: _k('saved-printer-save'),
          onPressed: _saving ? null : _submit,
          child: Text(s.saveAction),
        ),
      ],
    );
  }
}
