import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminSectionCard;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'quick_notes_repository.dart';

/// POS-QUICK-NOTES-124 — the Settings section where an owner or manager defines
/// the phrases the POS offers as one-tap chips.
///
/// Two things are deliberate here:
///
///  * **No optimistic writes.** Every action awaits the server and then RELOADS
///    the authoritative list. A refused save must never leave the owner looking
///    at a row that does not exist, which is exactly how a "saved" preset comes
///    to be missing from the tills.
///  * **One action at a time.** [_busy] blocks a second press while a write is
///    in flight, so a double-tapped Save cannot create two presets — the
///    server's idempotency ledger keys on a per-press request id, so two
///    presses are two genuinely different operations and it would not stop them.
class QuickNotesSection extends StatefulWidget {
  const QuickNotesSection({required this.repository, super.key});

  final QuickNotesRepository repository;

  @override
  State<QuickNotesSection> createState() => _QuickNotesSectionState();
}

class _QuickNotesSectionState extends State<QuickNotesSection> {
  List<QuickNotePreset> _presets = const [];
  QuickNotesLoadStatus _status = QuickNotesLoadStatus.ok;
  bool _loading = true;

  /// A write is in flight. Every control is disabled while it is true.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final snapshot = await widget.repository.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _status = snapshot.status;
      _presets = snapshot.presets;
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _writeMessage(AppLocalizations l10n, QuickNoteWrite outcome) =>
      switch (outcome) {
        QuickNoteWrite.ok => l10n.dashboardQuickNoteSaved,
        QuickNoteWrite.duplicateLabel => l10n.dashboardQuickNoteDuplicate,
        QuickNoteWrite.denied => l10n.dashboardQuickNoteDenied,
        QuickNoteWrite.invalid => l10n.dashboardQuickNoteInvalid(
          kQuickNoteMaxLength,
        ),
        QuickNoteWrite.failed => l10n.dashboardQuickNoteSaveFailed,
      };

  /// Runs one write, reports it honestly, and re-reads the server's truth
  /// whatever happened — including on failure, so a half-applied change can
  /// never linger on screen.
  Future<void> _run(
    AppLocalizations l10n,
    Future<QuickNoteWrite> Function() action, {
    String? failureMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(
      outcome == QuickNoteWrite.ok || failureMessage == null
          ? _writeMessage(l10n, outcome)
          : failureMessage,
    );
    await _reload();
  }

  Future<void> _addOrEdit(
    AppLocalizations l10n, {
    QuickNotePreset? preset,
  }) async {
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => _QuickNoteDialog(initial: preset?.label),
    );
    if (label == null || !mounted) return;
    await _run(
      l10n,
      () => widget.repository.upsert(
        id: preset?.id,
        label: label,
        // An edit keeps whatever the owner had switched it to; a new preset
        // starts enabled.
        isActive: preset?.isActive ?? true,
      ),
    );
  }

  Future<void> _toggle(AppLocalizations l10n, QuickNotePreset preset) => _run(
    l10n,
    () => widget.repository.upsert(
      id: preset.id,
      label: preset.label,
      isActive: !preset.isActive,
    ),
  );

  Future<void> _delete(AppLocalizations l10n, QuickNotePreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('quick-note-delete-dialog'),
        title: Text(l10n.dashboardQuickNoteDelete),
        content: Text(l10n.dashboardQuickNoteDeleteBody(preset.label)),
        actions: [
          TextButton(
            key: const Key('quick-note-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            key: const Key('quick-note-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.dashboardQuickNoteDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(l10n, () => widget.repository.delete(preset.id));
  }

  Future<void> _reorder(
    AppLocalizations l10n,
    int oldIndex,
    int newIndex,
  ) async {
    if (_busy) return;
    if (newIndex == oldIndex) return;
    final next = [..._presets];
    next.insert(newIndex, next.removeAt(oldIndex));
    // Shown immediately so the drag does not visibly snap back, but the server
    // is still the authority: _run reloads, and a refusal restores its order.
    setState(() => _presets = next);
    await _run(
      l10n,
      () => widget.repository.reorder([for (final p in next) p.id]),
      failureMessage: l10n.dashboardQuickNoteReorderFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AdminSectionCard(
      key: const Key('quick-notes-section'),
      title: l10n.dashboardQuickNotesTitle,
      icon: Icons.bolt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dashboardQuickNotesDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          if (_loading)
            const Padding(
              key: Key('quick-notes-loading'),
              padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_status != QuickNotesLoadStatus.ok)
            RestoflowNoticeBanner(
              key: const Key('quick-notes-unavailable'),
              tone: RestoflowTone.warning,
              icon: Icons.cloud_off_outlined,
              body: _status == QuickNotesLoadStatus.denied
                  ? l10n.dashboardQuickNoteDenied
                  : l10n.dashboardQuickNoteLoadFailed,
            )
          else if (_presets.isEmpty)
            Padding(
              key: const Key('quick-notes-empty'),
              padding: const EdgeInsets.symmetric(
                vertical: RestoflowSpacing.md,
              ),
              child: Text(
                l10n.dashboardQuickNotesEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ReorderableListView(
              key: const Key('quick-notes-list'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              // onReorderItem, not the deprecated onReorder: it hands us the
              // FINAL index, so there is no off-by-one to re-derive here.
              onReorderItem: (a, b) => _reorder(l10n, a, b),
              children: [
                for (var i = 0; i < _presets.length; i++)
                  _PresetRow(
                    key: ValueKey('quick-note-row-${_presets[i].id}'),
                    index: i,
                    preset: _presets[i],
                    enabled: !_busy,
                    onEdit: () => _addOrEdit(l10n, preset: _presets[i]),
                    onToggle: () => _toggle(l10n, _presets[i]),
                    onDelete: () => _delete(l10n, _presets[i]),
                  ),
              ],
            ),
          if (_presets.length > kQuickNoteSoftMax) ...[
            const SizedBox(height: RestoflowSpacing.sm),
            Text(
              key: const Key('quick-notes-guidance'),
              l10n.dashboardQuickNotesGuidance(kQuickNoteSoftMax),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: RestoflowSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              key: const Key('quick-notes-add'),
              onPressed: _busy || _status != QuickNotesLoadStatus.ok
                  ? null
                  : () => _addOrEdit(l10n),
              icon: const Icon(Icons.add),
              label: Text(l10n.dashboardQuickNoteAdd),
            ),
          ),
        ],
      ),
    );
  }
}

/// One preset row: drag handle, label, disabled badge, and its three actions.
class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.index,
    required this.preset,
    required this.enabled,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    super.key,
  });

  final int index;
  final QuickNotePreset preset;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final off = !preset.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xxs),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              key: Key('quick-note-drag-${preset.id}'),
              padding: const EdgeInsets.all(RestoflowSpacing.sm),
              child: Icon(
                Icons.drag_indicator,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              // Tenant text, rendered verbatim in whatever script it was typed
              // in. Never translated, never case-folded.
              preset.label,
              key: Key('quick-note-label-${preset.id}'),
              style: theme.textTheme.bodyMedium?.copyWith(
                // A switched-off preset is visibly inert, not merely annotated.
                color: off ? theme.colorScheme.onSurfaceVariant : null,
                decoration: off ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (off)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                end: RestoflowSpacing.sm,
              ),
              child: RestoflowStatusPill(
                key: Key('quick-note-disabled-${preset.id}'),
                label: l10n.dashboardQuickNoteDisabled,
                tone: RestoflowTone.neutral,
              ),
            ),
          IconButton(
            key: Key('quick-note-edit-${preset.id}'),
            tooltip: l10n.dashboardQuickNoteEdit,
            onPressed: enabled ? onEdit : null,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: Key('quick-note-toggle-${preset.id}'),
            tooltip: off
                ? l10n.dashboardQuickNoteEnable
                : l10n.dashboardQuickNoteDisable,
            onPressed: enabled ? onToggle : null,
            icon: Icon(
              off ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            ),
          ),
          IconButton(
            key: Key('quick-note-delete-${preset.id}'),
            tooltip: l10n.dashboardQuickNoteDelete,
            onPressed: enabled ? onDelete : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

/// The add/edit form: one field, the same 60-character contract the server
/// enforces, and a Save that stays disabled until there is something to save.
class _QuickNoteDialog extends StatefulWidget {
  const _QuickNoteDialog({this.initial});

  final String? initial;

  @override
  State<_QuickNoteDialog> createState() => _QuickNoteDialogState();
}

class _QuickNoteDialogState extends State<_QuickNoteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trimmed = _controller.text.trim();
    final valid = trimmed.isNotEmpty && trimmed.length <= kQuickNoteMaxLength;
    return AlertDialog(
      key: const Key('quick-note-dialog'),
      title: Text(
        widget.initial == null
            ? l10n.dashboardQuickNoteAdd
            : l10n.dashboardQuickNoteEdit,
      ),
      content: TextField(
        key: const Key('quick-note-dialog-field'),
        controller: _controller,
        autofocus: true,
        maxLength: kQuickNoteMaxLength,
        // Rebuilds so Save reflects the current text; the field is short and
        // the dialog is small, so this costs nothing.
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: l10n.dashboardQuickNoteText,
          hintText: l10n.dashboardQuickNoteHint,
          errorText: _controller.text.isNotEmpty && trimmed.isEmpty
              ? l10n.dashboardQuickNoteInvalid(kQuickNoteMaxLength)
              : null,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('quick-note-dialog-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          key: const Key('quick-note-dialog-save'),
          onPressed: valid ? () => Navigator.of(context).pop(trimmed) : null,
          child: Text(l10n.adminSave),
        ),
      ],
    );
  }
}
