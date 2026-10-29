import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminSectionCard;

import 'online_order_settings_copy.dart';
import 'online_order_settings_repository.dart';

class OnlineOrderSettingsSection extends StatefulWidget {
  const OnlineOrderSettingsSection({
    required this.repository,
    required this.canManage,
    this.branchName,
    this.mutationId,
    super.key,
  });

  final OnlineOrderSettingsRepository repository;

  /// Advisory membership gate; the versioned reader and setter enforce scope.
  final bool canManage;
  final String? branchName;
  final String Function()? mutationId;

  @override
  State<OnlineOrderSettingsSection> createState() =>
      _OnlineOrderSettingsSectionState();
}

class _OnlineOrderSettingsSectionState
    extends State<OnlineOrderSettingsSection> {
  OnlineOrderSettings? _confirmed;
  OnlineOrderValues? _draft;
  OnlineOrderMutation? _pending;
  OnlineOrderOutcome? _notice;
  bool _loading = true;
  bool _busy = false;
  bool _uncertain = false;
  bool _notRecorded = false;
  bool _saved = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OnlineOrderSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.canManage != widget.canManage) {
      _epoch++;
      _confirmed = null;
      _draft = null;
      _pending = null;
      _notice = null;
      _uncertain = false;
      _notRecorded = false;
      _saved = false;
      _busy = false;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final epoch = _epoch;
    setState(() => _loading = true);
    final result = await widget.repository.read();
    if (!mounted || epoch != _epoch) return;
    setState(() {
      _loading = false;
      _pending = null;
      _uncertain = false;
      _notRecorded = false;
      _saved = false;
      _notice = result.outcome == OnlineOrderOutcome.ok ? null : result.outcome;
      _confirmed = result.outcome == OnlineOrderOutcome.ok
          ? result.settings
          : null;
      _draft = _confirmed?.values;
    });
  }

  bool get _dirty => _draft != null && _draft != _confirmed?.values;
  bool get _frozen => _loading || _busy || _uncertain || _notice != null;

  void _edit(OnlineOrderValues values) => setState(() {
    _draft = values;
    _saved = false;
  });

  Future<void> _save({bool resend = false}) async {
    final baseline = _confirmed;
    final draft = _draft;
    if (_busy ||
        _loading ||
        !widget.canManage ||
        baseline == null ||
        draft == null)
      return;
    if (resend ? !_notRecorded : (_frozen || !_dirty)) return;
    final intent = resend
        ? _pending!
        : OnlineOrderMutation(
            id: (widget.mutationId ?? newOnlineOrderMutationId)(),
            expectedRevision: baseline.revision,
            values: draft,
          );
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _pending = intent;
      _saved = false;
      _notRecorded = false;
    });
    final result = await widget.repository.save(intent);
    if (!mounted || epoch != _epoch) return;
    if (result.outcome == OnlineOrderOutcome.ok && result.settings != null) {
      // The receipt confirms the write, but may predate another manager's edit.
      // Always read current state before enabling a new intent.
      final current = await widget.repository.read();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _busy = false;
        _pending = null;
        _uncertain = false;
        _saved = true;
        _notice = current.outcome == OnlineOrderOutcome.ok
            ? null
            : current.outcome;
        _confirmed = current.outcome == OnlineOrderOutcome.ok
            ? current.settings
            : null;
        _draft = _confirmed?.values;
      });
      return;
    }
    setState(() {
      _busy = false;
      _uncertain = result.outcome == OnlineOrderOutcome.unavailable;
      _notice = _uncertain ? null : result.outcome;
      if (!_uncertain) _pending = null;
    });
  }

  Future<void> _checkSave() async {
    final intent = _pending;
    if (_busy || !_uncertain || intent == null) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    final result = await widget.repository.reconcile(intent);
    if (!mounted || epoch != _epoch) return;
    setState(() {
      _busy = false;
      if (result.outcome == OnlineOrderOutcome.ok && result.current != null) {
        if (result.state == OnlineOrderMutationState.committed) {
          _confirmed = result.current;
          _draft = result.current!.values;
          _pending = null;
          _uncertain = false;
          _notRecorded = false;
          _notice = null;
          _saved = true;
        } else if (result.state == OnlineOrderMutationState.notRecorded) {
          // Even when current settings changed, retain the original CAS and UUID.
          // A deliberate same-intent resend cannot overwrite the newer revision.
          _notRecorded = true;
        }
      } else if (result.state == OnlineOrderMutationState.refused) {
        _notice = result.outcome;
        _pending = null;
        _uncertain = false;
        _notRecorded = false;
      } else if (result.outcome != OnlineOrderOutcome.unavailable) {
        _notice = result.outcome;
        _notRecorded = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = OnlineOrderSettingsCopy.of(context);
    return AdminSectionCard(
      key: const Key('online-order-settings-section'),
      title: copy.title,
      icon: Icons.shopping_bag_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.branchName case final name? when name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: RestoflowSpacing.xs),
              child: Text(name, style: Theme.of(context).textTheme.titleSmall),
            ),
          Text(copy.scope),
          const SizedBox(height: RestoflowSpacing.md),
          if (_loading)
            Center(
              child: CircularProgressIndicator(
                key: const Key('online-order-settings-loading'),
                semanticsLabel: copy.loading,
              ),
            )
          else
            ..._content(copy),
        ],
      ),
    );
  }

  List<Widget> _content(OnlineOrderSettingsCopy copy) {
    final draft = _draft;
    final editable = widget.canManage && !_frozen;
    final message = _uncertain
        ? (_notice == OnlineOrderOutcome.denied ||
                  _notice == OnlineOrderOutcome.notFound
              ? '${_notice == OnlineOrderOutcome.denied ? copy.denied : copy.notFound}\n${copy.uncertain}'
              : (_notRecorded ? copy.notRecorded : copy.uncertain))
        : switch (_notice) {
            OnlineOrderOutcome.denied => copy.denied,
            OnlineOrderOutcome.notFound => copy.notFound,
            OnlineOrderOutcome.revisionConflict => copy.conflict,
            OnlineOrderOutcome.requestConflict => copy.requestConflict,
            OnlineOrderOutcome.invalidRequest => copy.invalid,
            OnlineOrderOutcome.unavailable =>
              _saved ? copy.savedReadUnavailable : copy.unavailable,
            _ => _saved ? copy.saved : null,
          };
    return [
      if (draft != null) ...[
        SwitchListTile(
          key: const Key('online-order-ordering-toggle'),
          contentPadding: EdgeInsets.zero,
          title: Text(copy.ordering),
          subtitle: Text(copy.orderingHelp),
          value: draft.ordering,
          onChanged: editable
              ? (v) => _edit(draft.copyWith(ordering: v))
              : null,
        ),
        SwitchListTile(
          key: const Key('online-order-alerts-toggle'),
          contentPadding: EdgeInsets.zero,
          title: Text(copy.alerts),
          subtitle: Text(copy.alertsHelp),
          value: draft.alerts,
          onChanged: editable ? (v) => _edit(draft.copyWith(alerts: v)) : null,
        ),
        SwitchListTile(
          key: const Key('online-order-printing-toggle'),
          contentPadding: EdgeInsets.zero,
          title: Text(copy.printing),
          subtitle: Text(copy.printingHelp),
          value: draft.printing,
          onChanged: editable
              ? (v) => _edit(draft.copyWith(printing: v))
              : null,
        ),
      ],
      if (_dirty && !_uncertain)
        Text(copy.dirty, key: const Key('online-order-unsaved')),
      if (!widget.canManage) Text(copy.denied),
      if (message != null) ...[
        const SizedBox(height: RestoflowSpacing.sm),
        Semantics(
          liveRegion: true,
          child: RestoflowNoticeBanner(
            key: const Key('online-order-settings-notice'),
            body: message,
            tone: _saved && _notice == null
                ? RestoflowTone.success
                : RestoflowTone.warning,
          ),
        ),
      ],
      const SizedBox(height: RestoflowSpacing.sm),
      Wrap(
        spacing: RestoflowSpacing.sm,
        runSpacing: RestoflowSpacing.sm,
        children: [
          if (!_uncertain)
            FilledButton.icon(
              key: const Key('online-order-save'),
              onPressed: editable && _dirty ? () => _save() : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? copy.saving : copy.save),
            ),
          if (_uncertain)
            OutlinedButton(
              key: const Key('online-order-check-save'),
              onPressed: _busy ? null : _checkSave,
              child: Text(copy.checkSave),
            ),
          if (_notRecorded)
            FilledButton(
              key: const Key('online-order-resend'),
              onPressed: _busy ? null : () => _save(resend: true),
              child: Text(copy.retrySame),
            ),
          // A not-recorded snapshot is not cancellation: a delayed original
          // request may still commit. Retain its UUID until a final receipt.
          if (!_uncertain)
            TextButton(
              key: const Key('online-order-reload'),
              onPressed: _busy ? null : _load,
              child: Text(
                _dirty || _notice != null || _notRecorded
                    ? copy.reload
                    : copy.read,
              ),
            ),
        ],
      ),
    ];
  }
}
