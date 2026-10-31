import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminSectionCard;

import 'seo_consent_copy.dart';
import 'seo_consent_repository.dart';
import 'seo_consent_operations.dart';

class SeoConsentSection extends ConsumerStatefulWidget {
  const SeoConsentSection({
    required this.repository,
    required this.canManage,
    this.restaurantName,
    this.mutationId,
    required this.scopeIdentity,
    required this.operationScope,
    super.key,
  });

  final SeoConsentRepository repository;
  final String scopeIdentity;
  final SeoConsentOperationScope operationScope;

  /// Owner-only advisory gate; the server capability and setter enforce scope.
  final bool canManage;
  final String? restaurantName;
  final String Function()? mutationId;

  @override
  ConsumerState<SeoConsentSection> createState() => _SeoConsentSectionState();
}

class _SeoConsentSectionState extends ConsumerState<SeoConsentSection> {
  late final _operations = ref.read(seoConsentOperationsProvider);
  SeoConsentState? _confirmed;
  bool? _draft;
  SeoConsentMutation? _pending;
  SeoConsentOutcome? _notice;
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
  void didUpdateWidget(SeoConsentSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.canManage != widget.canManage ||
        oldWidget.scopeIdentity != widget.scopeIdentity ||
        oldWidget.operationScope.key != widget.operationScope.key) {
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
    final scope = widget.operationScope;
    final repository = widget.repository;
    setState(() => _loading = true);
    try {
      await _operations.restore(scope);
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loading = false;
        _notice = SeoConsentOutcome.unavailable;
        _confirmed = null;
        _draft = null;
      });
      return;
    }
    final result = await repository.read();
    if (!mounted || epoch != _epoch) return;
    setState(() {
      _loading = false;
      _pending = _operations.pending(scope);
      _uncertain = _pending != null;
      _notRecorded = false;
      _saved = false;
      _notice = result.outcome == SeoConsentOutcome.ok ? null : result.outcome;
      _confirmed = result.outcome == SeoConsentOutcome.ok ? result.state : null;
      _draft = _pending?.consentEnabled ?? _confirmed?.consentEnabled;
    });
  }

  bool get _dirty => _draft != null && _draft != _confirmed?.consentEnabled;
  bool get _frozen => _loading || _busy || _uncertain || _notice != null;

  void _edit(bool consentEnabled) => setState(() {
    _draft = consentEnabled;
    _saved = false;
  });

  Future<void> _save({bool resend = false}) async {
    final baseline = _confirmed;
    final draft = _draft;
    if (_busy ||
        _loading ||
        !widget.canManage ||
        baseline?.canManage != true ||
        baseline == null ||
        draft == null)
      return;
    if (resend ? !_notRecorded : (_frozen || !_dirty)) return;
    final intent = resend
        ? _pending!
        : SeoConsentMutation(
            id: (widget.mutationId ?? newSeoConsentMutationId)(),
            expectedRevision: baseline.revision,
            consentEnabled: draft,
          );
    final epoch = _epoch;
    final scope = widget.operationScope;
    final repository = widget.repository;
    setState(() {
      _busy = true;
      _pending = intent;
      _saved = false;
      _notRecorded = false;
    });
    final result = await _operations.save(scope, repository, intent);
    if (!mounted || epoch != _epoch) return;
    if (result.outcome == SeoConsentOutcome.ok && result.state != null) {
      // The receipt confirms the write, but may predate another owner's edit.
      // Always read current state before enabling a new intent.
      final current = await repository.read();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _busy = false;
        _pending = _operations.pending(scope);
        _uncertain = _pending != null;
        _saved = !_uncertain;
        _notice = current.outcome == SeoConsentOutcome.ok
            ? null
            : current.outcome;
        _confirmed = current.outcome == SeoConsentOutcome.ok
            ? current.state
            : null;
        _draft = _pending?.consentEnabled ?? _confirmed?.consentEnabled;
      });
      return;
    }
    setState(() {
      _busy = false;
      _pending = _operations.pending(scope) ?? intent;
      _draft = _pending!.consentEnabled;
      _uncertain = true;
      _notice = result.outcome == SeoConsentOutcome.unavailable
          ? null
          : result.outcome;
    });
  }

  Future<void> _checkSave() async {
    final intent = _pending;
    if (_busy || !_uncertain || intent == null) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    final result = await _operations.reconcile(
      widget.operationScope,
      widget.repository,
      intent,
    );
    if (!mounted || epoch != _epoch) return;
    setState(() {
      _busy = false;
      final next = _operations.pending(widget.operationScope);
      if ((result.mutationState == SeoConsentMutationState.committed ||
              result.mutationState == SeoConsentMutationState.refused) &&
          next != null) {
        _pending = next;
        _draft = next.consentEnabled;
        _confirmed = result.current;
        _uncertain = true;
        _notRecorded = false;
        _notice = null;
        _saved = false;
        return;
      }
      if (result.outcome == SeoConsentOutcome.ok && result.current != null) {
        if (result.mutationState == SeoConsentMutationState.committed) {
          _confirmed = result.current;
          _draft = result.current!.consentEnabled;
          _pending = null;
          _uncertain = false;
          _notRecorded = false;
          _notice = null;
          _saved = true;
        } else if (result.mutationState ==
            SeoConsentMutationState.notRecorded) {
          // Even when current settings changed, retain the original CAS and UUID.
          // A deliberate same-intent resend cannot overwrite the newer revision.
          _notRecorded = true;
        }
      } else if (result.mutationState == SeoConsentMutationState.refused) {
        _notice = result.outcome;
        _pending = null;
        _uncertain = false;
        _notRecorded = false;
      } else if (result.outcome != SeoConsentOutcome.unavailable) {
        _notice = result.outcome;
        _notRecorded = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = SeoConsentCopy.of(context);
    return AdminSectionCard(
      key: const Key('seo-consent-settings-section'),
      title: copy.title,
      icon: Icons.travel_explore_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.restaurantName case final name? when name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: RestoflowSpacing.xs),
              child: Text(name, style: Theme.of(context).textTheme.titleSmall),
            ),
          Text(copy.scope),
          const SizedBox(height: RestoflowSpacing.sm),
          RestoflowNoticeBanner(
            key: const Key('seo-consent-not-operational'),
            tone: RestoflowTone.info,
            body: copy.notOperational,
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Text(copy.help),
          const SizedBox(height: RestoflowSpacing.sm),
          Text(copy.withdrawal),
          const SizedBox(height: RestoflowSpacing.sm),
          Text(copy.independent),
          const SizedBox(height: RestoflowSpacing.md),
          if (_loading)
            Center(
              child: CircularProgressIndicator(
                key: const Key('seo-consent-settings-loading'),
                semanticsLabel: copy.loading,
              ),
            )
          else
            ..._content(copy),
        ],
      ),
    );
  }

  List<Widget> _content(SeoConsentCopy copy) {
    final draft = _draft;
    final editable =
        widget.canManage && _confirmed?.canManage == true && !_frozen;
    final refusal = switch (_notice) {
      SeoConsentOutcome.denied => copy.denied,
      SeoConsentOutcome.notFound => copy.notFound,
      SeoConsentOutcome.revisionConflict => copy.conflict,
      SeoConsentOutcome.requestConflict => copy.requestConflict,
      SeoConsentOutcome.invalidRequest => copy.invalid,
      _ => null,
    };
    final message = _uncertain
        ? (refusal != null
              ? '$refusal\n${copy.uncertain}'
              : (_notRecorded ? copy.notRecorded : copy.uncertain))
        : switch (_notice) {
            SeoConsentOutcome.denied => copy.denied,
            SeoConsentOutcome.notFound => copy.notFound,
            SeoConsentOutcome.revisionConflict => copy.conflict,
            SeoConsentOutcome.requestConflict => copy.requestConflict,
            SeoConsentOutcome.invalidRequest => copy.invalid,
            SeoConsentOutcome.unavailable =>
              _saved ? copy.savedReadUnavailable : copy.unavailable,
            _ => _saved ? copy.saved : null,
          };
    return [
      if (draft != null)
        SwitchListTile(
          key: const Key('seo-consent-toggle'),
          contentPadding: EdgeInsets.zero,
          title: Text(copy.label),
          value: draft,
          onChanged: editable ? _edit : null,
        ),
      if (_dirty && !_uncertain)
        Text(copy.dirty, key: const Key('seo-consent-unsaved')),
      if ((!widget.canManage || _confirmed?.canManage == false) &&
          _notice != SeoConsentOutcome.denied)
        Text(copy.denied),
      if (message != null) ...[
        const SizedBox(height: RestoflowSpacing.sm),
        Semantics(
          liveRegion: true,
          child: RestoflowNoticeBanner(
            key: const Key('seo-consent-settings-notice'),
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
              key: const Key('seo-consent-save'),
              onPressed: editable && _dirty ? () => _save() : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? copy.saving : copy.save),
            ),
          if (_uncertain)
            OutlinedButton(
              key: const Key('seo-consent-check-save'),
              onPressed: _busy ? null : _checkSave,
              child: Text(copy.checkSave),
            ),
          if (_notRecorded)
            FilledButton(
              key: const Key('seo-consent-resend'),
              onPressed: _busy ? null : () => _save(resend: true),
              child: Text(copy.retrySame),
            ),
          // A not-recorded snapshot is not cancellation: a delayed original
          // request may still commit. Retain its UUID until a final receipt.
          if (!_uncertain)
            TextButton(
              key: const Key('seo-consent-reload'),
              onPressed: _busy ? null : _load,
              child: Text(
                _dirty || _notice != null || _notRecorded
                    ? copy.reload
                    : copy.refresh,
              ),
            ),
        ],
      ),
    ];
  }
}
