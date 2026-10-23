import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_content_models.dart';
import 'storefront_content_repository.dart';
import 'storefront_content_unicode.dart' as unicode;
import 'storefront_copy.dart';
import 'storefront_media_publisher.dart';
import 'storefront_models.dart';
import 'storefront_sources.dart';

/// A read acknowledgment from the actual parent editor. A completed Future is
/// not evidence that the profile and its media were both refreshed.
class StorefrontContentRefresh {
  const StorefrontContentRefresh({
    required this.profileRead,
    required this.mediaRead,
    this.version,
    this.branchId,
  });
  const StorefrontContentRefresh.unavailable()
    : profileRead = false,
      mediaRead = false,
      version = null,
      branchId = null;
  final bool profileRead, mediaRead;
  final int? version;
  final String? branchId;
  bool get isReady =>
      profileRead && mediaRead && version != null && branchId != null;
}

/// One complete content draft, owned by the existing membership/restaurant
/// editor identity. The server read controls access; no role test authorizes it.
class StorefrontContentSection extends StatefulWidget {
  const StorefrontContentSection({
    required this.repository,
    required this.catalog,
    required this.profileVersion,
    required this.savedBranchId,
    required this.onRefresh,
    required this.onDraftChanged,
    required this.onBusyChanged,
    this.enabled = true,
    this.publisher,
    this.sources,
    this.reloadSources,
    this.publicUrlFor,
    super.key,
  });
  final StorefrontContentRepository repository;
  final StorefrontContentCatalog? catalog;
  final int profileVersion;
  final String savedBranchId;
  final Future<StorefrontContentRefresh> Function() onRefresh;
  final ValueChanged<bool> onDraftChanged, onBusyChanged;
  final bool enabled;
  final StorefrontMediaPublisher? publisher;
  final StorefrontSourceOptions? sources;
  final Future<StorefrontSourceOptions> Function()? reloadSources;
  final Uri Function(String)? publicUrlFor;
  @override
  State<StorefrontContentSection> createState() => _ContentState();
}

class _ContentState extends State<StorefrontContentSection> {
  StorefrontContentRead? _read;
  StorefrontContentCatalogData? _catalog;
  StorefrontContentMediaList? _media;
  Map<String, dynamic>? _draft;
  StorefrontContentAttempt? _pending;
  StorefrontContentAttempt? _confirmedSave;
  final _headline = TextEditingController(),
      _selection = TextEditingController();
  bool _busy = false, _dirty = false, _stale = false;
  int _generation = 0;
  int _bindingGeneration = 0;
  bool _ownsRefresh = false, _bindingHold = false, _branchHold = false;
  String? _message, _sourceId, _invalidField;
  ({StorefrontMediaSource source, String requestId, String branchId})?
  _pendingPublish;
  ({StorefrontMediaSource source, String requestId, String branchId})?
  _confirmedPublish;
  String c(String key) =>
      storefrontContentCopy(AppLocalizations.of(context), key);
  bool get _editable =>
      widget.enabled &&
      !_busy &&
      !_stale &&
      !_bindingHold &&
      _confirmedSave == null &&
      _confirmedPublish == null &&
      _pending == null &&
      _pendingPublish == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bindingGeneration++;
    _generation++;
    _headline.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StorefrontContentSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.repository, widget.repository) ||
        !identical(old.catalog, widget.catalog) ||
        !identical(old.publisher, widget.publisher) ||
        old.savedBranchId != widget.savedBranchId) {
      _bindingGeneration++;
      _generation++;
      _ownsRefresh = false;
      _busy = false;
      // An in-flight or uncertain request remains owned by its original
      // transport. Never replay it on a replacement authenticated binding.
      _bindingHold =
          _bindingHold ||
          _pending != null ||
          _pendingPublish != null ||
          (old.savedBranchId != widget.savedBranchId &&
              (_confirmedSave != null || _confirmedPublish != null));
      _branchHold =
          _branchHold ||
          (old.savedBranchId != widget.savedBranchId && _bindingHold);
      if (_bindingHold || _confirmedSave != null || _confirmedPublish != null) {
        _stale = true;
        _message = _bindingHold ? 'bindingChanged' : 'savedReadFailed';
        final binding = _bindingGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && binding == _bindingGeneration)
            widget.onBusyChanged(true);
        });
      } else {
        _load();
      }
      return;
    }
    if (old.savedBranchId != widget.savedBranchId ||
        old.profileVersion != widget.profileVersion) {
      // This is our parent's acknowledgment, not a competing write. The
      // explicit refresh owns one child read using its returned version/branch.
      if (_ownsRefresh || _confirmedSave != null || _confirmedPublish != null)
        return;
      final snapshot = _read?.snapshot;
      if (!_stale &&
          snapshot?.branchId == widget.savedBranchId &&
          snapshot?.version == widget.profileVersion &&
          _media?.version == snapshot?.version)
        return;
      if (_dirty || _pending != null || _pendingPublish != null) {
        _stale = true;
        _message = 'conflict';
      } else if (!_busy) {
        _load();
      }
    }
  }

  void _notifyDraft(bool value) {
    if (_dirty == value) return;
    _dirty = value;
    if (mounted) widget.onDraftChanged(value);
  }

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() => _busy = value);
    widget.onBusyChanged(value);
  }

  Future<bool> _load({
    int? version,
    String? branchId,
    bool owned = false,
  }) async {
    if (!mounted) return false;
    final binding = _bindingGeneration;
    final repository = widget.repository;
    final catalog = widget.catalog;
    final expectedVersion = version ?? widget.profileVersion;
    final expectedBranch = branchId ?? widget.savedBranchId;
    bool propsMatch() =>
        owned ||
        (widget.profileVersion == expectedVersion &&
            widget.savedBranchId == expectedBranch);
    final generation = ++_generation;
    setState(() => _busy = true);
    final results = await Future.wait<Object?>(
      <Future<Object?> Function()>[
        () => repository.readContent(),
        () => repository.listContentMedia(),
      ].map(_safeRead),
    );
    if (!_current(binding) || generation != _generation) return false;
    final read = results[0] as StorefrontContentRead?;
    final media = results[1] as StorefrontContentMediaList?;
    final snapshot = read?.snapshot;
    // A failed/denied content read cannot enable this editor. Do not send an
    // unrelated menu/catalog read on that path; positive reads still require
    // all three acknowledgments while the same operation owns the lock.
    StorefrontContentCatalogData? choices;
    if (propsMatch() &&
        read?.isOk == true &&
        snapshot != null &&
        media != null &&
        snapshot.branchId == expectedBranch &&
        snapshot.version == expectedVersion &&
        media.version == snapshot.version) {
      choices =
          await _safeRead(
                () =>
                    catalog?.loadContent(expectedBranch) ??
                    Future<StorefrontContentCatalogData?>.value(),
              )
              as StorefrontContentCatalogData?;
    }
    if (!_current(binding) || generation != _generation) return false;
    final verified =
        propsMatch() &&
        read?.isOk == true &&
        snapshot != null &&
        media != null &&
        choices != null &&
        snapshot.branchId == expectedBranch &&
        snapshot.version == expectedVersion &&
        media.version == snapshot.version;
    setState(() {
      if (!owned) _busy = false;
      if (!owned || verified) {
        _read =
            (!owned && read?.isOk == true && !verified ? null : read) ??
            const StorefrontContentRead(
              StorefrontContentReadStatus.unavailable,
            );
        _media = media;
        _catalog = choices;
      }
      _stale = !verified;
      if (!owned)
        _message = null; // The typed failure view owns its reload message.
      if (verified) {
        _draft = snapshot.document.editableCopy();
        _headline.text = _draft!['hero_headline'] as String? ?? '';
        _selection.text = _headline.text;
        _notifyDraft(false);
      }
    });
    return verified;
  }

  Future<Object?> _safeRead(Future<Object?> Function() action) async {
    try {
      return await action();
    } catch (_) {
      return null;
    }
  }

  bool _current(int binding) => mounted && binding == _bindingGeneration;

  Future<void> _refreshConfirmed(int binding) async {
    final refresh = widget.onRefresh;
    final published = _confirmedPublish != null;
    _ownsRefresh = true;
    StorefrontContentRefresh parent;
    try {
      parent = await refresh();
    } catch (_) {
      parent = const StorefrontContentRefresh.unavailable();
    }
    if (!_current(binding)) return;
    final minimumVersion = _confirmedSave == null
        ? null
        : _confirmedSave!.expectedVersion + 1;
    final expectedBranch =
        _confirmedSave?.expectedBranchId ?? _confirmedPublish?.branchId;
    var verified =
        parent.isReady &&
        (expectedBranch == null || parent.branchId == expectedBranch) &&
        (minimumVersion == null || parent.version! >= minimumVersion);
    if (verified)
      verified = await _load(
        version: parent.version,
        branchId: parent.branchId,
        owned: true,
      );
    if (!_current(binding)) return;
    _ownsRefresh = false;
    setState(() {
      _busy = false;
      _stale = !verified;
      if (verified) {
        _confirmedSave = null;
        _confirmedPublish = null;
        _message = published ? 'published' : 'saved';
      } else {
        _message = published ? 'publishedReadFailed' : 'savedReadFailed';
      }
    });
    widget.onBusyChanged(!verified);
  }

  Future<void> _resumeConfirmedRead() async {
    if (!mounted ||
        _busy ||
        _bindingHold ||
        (_confirmedSave == null && _confirmedPublish == null))
      return;
    final binding = _bindingGeneration;
    _setBusy(true);
    await _refreshConfirmed(binding);
  }

  Future<void> _reload() async {
    if (!mounted ||
        _busy ||
        _pending != null ||
        _pendingPublish != null ||
        _confirmedSave != null ||
        _confirmedPublish != null)
      return;
    final binding = _bindingGeneration;
    if (_dirty && !await _confirm('discard')) return;
    if (!_current(binding) || _busy) return;
    _notifyDraft(false);
    _setBusy(true);
    _ownsRefresh = true;
    StorefrontContentRefresh parent;
    try {
      parent = await widget.onRefresh();
    } catch (_) {
      parent = const StorefrontContentRefresh.unavailable();
    }
    if (!_current(binding)) return;
    var verified = parent.isReady;
    if (verified)
      verified = await _load(
        version: parent.version,
        branchId: parent.branchId,
        owned: true,
      );
    if (!_current(binding)) return;
    _ownsRefresh = false;
    setState(() {
      _busy = false;
      _stale = !verified;
      _message = verified ? null : 'loadFailed';
    });
    widget.onBusyChanged(!verified);
  }

  Object? _get(String path) {
    Object? value = _draft;
    for (final p in path.split('.')) {
      value = value is List ? value[int.parse(p)] : (value as Map)[p];
    }
    return value;
  }

  void _put(String path, Object? value) {
    Object? parent = _draft;
    final keys = path.split('.');
    for (final p in keys.take(keys.length - 1)) {
      parent = parent is List ? parent[int.parse(p)] : (parent as Map)[p];
    }
    if (parent is List) {
      parent[int.parse(keys.last)] = value;
    } else {
      (parent as Map)[keys.last] = value;
    }
  }

  void _change(String path, Object? value) {
    if (!mounted || !_editable) return;
    setState(() {
      _put(path, value);
      _notifyDraft(true);
      _message = null;
      _invalidField = null;
    });
  }

  Widget _text(String path, String label, {int lines = 1}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      key: ValueKey('content-$path-$_generation'),
      initialValue: _get(path) as String? ?? '',
      enabled: _editable,
      decoration: InputDecoration(labelText: c(label)),
      maxLines: lines,
      onChanged: (text) => _change(path, text),
    ),
  );
  Widget _select(
    String path,
    String label,
    List<DropdownMenuItem<String>> choices, {
    bool nullable = true,
    String nullLabel = 'none',
  }) {
    final value = _get(path) as String?;
    final items = <DropdownMenuItem<String>>[
      if (nullable) DropdownMenuItem(value: '', child: Text(c(nullLabel))),
      ...choices,
    ];
    final valid = items.any((item) => item.value == (value ?? ''));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        key: ValueKey('content-select-$path-$_generation'),
        initialValue: valid ? (value ?? '') : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: c(label)),
        items: items,
        onChanged: _editable
            ? (value) => _change(path, value == '' ? null : value)
            : null,
      ),
    );
  }

  List<DropdownMenuItem<String>> _options(
    List<StorefrontContentChoice> choices,
  ) => [
    for (final option in choices)
      DropdownMenuItem(
        value: option.id,
        child: Text(option.name, overflow: TextOverflow.ellipsis),
      ),
  ];
  List<DropdownMenuItem<String>> _enum(List<String> values) => [
    for (final value in values)
      DropdownMenuItem(value: value, child: Text(c(value))),
  ];
  Widget _title(String key) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(c(key), style: Theme.of(context).textTheme.titleSmall),
  );
  Future<bool> _confirm(String title, {String? text}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(c(title)),
          content: text == null ? null : SelectableText(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(c('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(c('confirm')),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _normalizeHeadline() async {
    if (!mounted || !_editable) return;
    final binding = _bindingGeneration;
    final original = _headline.text;
    try {
      final normalized = unicode.normalizeContentText(
        original,
        120,
        legacy: true,
      );
      if (normalized == null) {
        setState(() => _message = 'invalid');
        return;
      }
      if (normalized != original &&
          !await _confirm('normalize', text: normalized))
        return;
      if (!_current(binding) || !_editable || _headline.text != original)
        return;
      setState(() {
        _headline.text = normalized;
        _selection.text = normalized;
        _put('hero_headline', normalized);
        _put('hero.format', null);
        _notifyDraft(true);
      });
    } on FormatException {
      if (_current(binding)) setState(() => _message = 'invalid');
    }
  }

  void _format({required bool highlight}) {
    if (!mounted || !_editable) return;
    final text = _selection.text;
    if (text.isEmpty || text != _headline.text) {
      setState(() => _message = 'invalid');
      return;
    }
    final selection = _selection.selection;
    final range = unicode.utf16SelectionToCodepoints(
      text,
      selection.baseOffset,
      selection.extentOffset,
    );
    if (range == null) {
      setState(() => _message = 'invalid');
      return;
    }
    final old = _get('hero.format') as Map?;
    final start = highlight
        ? range[0]
        : (old?['highlight'] as Map?)?['start'] as int?;
    final end = highlight
        ? range[1]
        : (old?['highlight'] as Map?)?['end'] as int?;
    final b = highlight ? (old?['break_before'] as int?) : range[0];
    if (!unicode.heroFormatValid(text, start, end, b)) {
      setState(() => _message = 'invalid');
      return;
    }
    _change('hero.format', {
      'text': text,
      'highlight': start == null ? null : {'start': start, 'end': end},
      'break_before': b,
    });
  }

  Widget _formatEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title('format'),
      Text(c('formatHelp')),
      TextButton(
        onPressed: _editable ? _normalizeHeadline : null,
        child: Text(c('normalize')),
      ),
      TextField(
        key: const Key('content-headline-selection'),
        controller: _selection,
        readOnly: true,
        enableInteractiveSelection: true,
        maxLines: null,
        decoration: InputDecoration(labelText: c('format')),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            key: const Key('content-highlight'),
            onPressed: _editable ? () => _format(highlight: true) : null,
            child: Text(c('highlight')),
          ),
          TextButton(
            key: const Key('content-break'),
            onPressed: _editable ? () => _format(highlight: false) : null,
            child: Text(c('break')),
          ),
          TextButton(
            onPressed: _editable ? () => _change('hero.format', null) : null,
            child: Text(c('clearFormat')),
          ),
        ],
      ),
      if (_get('hero.format') case final Map format)
        Text(
          '${format['highlight'] ?? ''} ${format['break_before'] ?? ''}',
          key: const Key('content-format-offsets'),
        ),
    ],
  );
  Widget _stringList(String path, String label, int max) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(label),
      for (var i = 0; i < ((_get(path) as List?)?.length ?? 0); i++)
        Row(
          children: [
            Expanded(child: _text('$path.$i', label)),
            IconButton(
              tooltip: c('remove'),
              onPressed: _editable
                  ? () {
                      setState(() {
                        (_get(path) as List).removeAt(i);
                        _generation++;
                        _notifyDraft(true);
                      });
                    }
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
      TextButton.icon(
        onPressed: _editable && ((_get(path) as List?)?.length ?? 0) < max
            ? () {
                setState(() {
                  final list = List<dynamic>.from((_get(path) as List?) ?? []);
                  list.add('');
                  _put(path, list);
                  _generation++;
                  _notifyDraft(true);
                });
              }
            : null,
        icon: const Icon(Icons.add),
        label: Text(c('add')),
      ),
    ],
  );
  Widget _mediaPicker(String path) => _select(path, 'media', [
    for (final row in _media?.rows ?? <StorefrontContentMediaRow>[])
      if (row.media.isLive)
        DropdownMenuItem(
          value: row.media.id,
          child: Text(
            '${row.media.width}×${row.media.height} · ${row.media.id.substring(0, 8)}',
          ),
        ),
  ]);
  Widget _module(String kind) {
    final value = _get(kind) as Map?;
    final promo = kind == 'promo';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(kind),
        SwitchListTile(
          title: Text(c('enabled')),
          value: value != null,
          onChanged: _editable
              ? (enabled) {
                  _change(
                    kind,
                    enabled
                        ? {
                            'kicker': '',
                            'title': '',
                            'body': '',
                            if (promo)
                              'target': {
                                'kind': 'category',
                                'category_id': null,
                              },
                            'editorial_media_id': null,
                            if (!promo) 'facts': <Object?>[],
                          }
                        : null,
                  );
                  _generation++;
                }
              : null,
        ),
        if (value != null) ...[
          if (promo) ...[
            DropdownButtonFormField<String>(
              key: ValueKey('content-promo-kind-$_generation'),
              isExpanded: true,
              initialValue: (value['target'] as Map)['kind'] as String,
              items: _enum(['category', 'item']),
              onChanged: _editable
                  ? (kind) {
                      setState(() {
                        value['target'] = {
                          'kind': kind,
                          kind == 'category' ? 'category_id' : 'item_id': null,
                        };
                        if (kind == 'category') {
                          value['editorial_media_id'] = null;
                        } else {
                          value.remove('editorial_media_id');
                        }
                        _generation++;
                        _notifyDraft(true);
                      });
                    }
                  : null,
            ),
            if ((value['target'] as Map)['kind'] == 'category')
              _select(
                'promo.target.category_id',
                'category',
                _options(
                  (_catalog?.categories ?? [])
                      .where((x) => x.available)
                      .toList(),
                ),
              )
            else ...[
              _select(
                'promo.target.item_id',
                'item',
                _options(
                  (_catalog?.items ?? [])
                      .where((x) => x.available && x.hasSourceImage)
                      .toList(),
                ),
              ),
              Text(c('promoItemCandidates')),
            ],
          ],
          _text('$kind.kicker', 'kicker'),
          _text('$kind.title', 'moduleTitle'),
          _text('$kind.body', 'body', lines: 3),
          if (!promo || (value['target'] as Map)['kind'] == 'category')
            _mediaPicker('$kind.editorial_media_id'),
          if (!promo) _stringList('story.facts', 'facts', 3),
        ],
      ],
    );
  }

  Widget _presentations(bool categories) {
    final path = categories ? 'category_presentation' : 'item_presentation';
    final idKey = categories ? 'category_id' : 'item_id';
    final rows = _get(path) as List;
    final choices = categories ? _catalog?.categories : _catalog?.items;
    final selected = rows.map((r) => (r as Map)[idKey]).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(categories ? 'categoryPresentation' : 'itemPresentation'),
        for (var i = 0; i < rows.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          choices
                                  ?.where(
                                    (choice) =>
                                        choice.id == (rows[i] as Map)[idKey],
                                  )
                                  .firstOrNull
                                  ?.name ??
                              c('relation_unavailable'),
                        ),
                      ),
                      IconButton(
                        tooltip: c('remove'),
                        onPressed: _editable
                            ? () {
                                setState(() {
                                  rows.removeAt(i);
                                  _generation++;
                                  _notifyDraft(true);
                                });
                              }
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  if (categories) ...[
                    _text('$path.$i.heading', 'heading'),
                    _text('$path.$i.blurb', 'blurb'),
                    _mediaPicker('$path.$i.editorial_media_id'),
                  ],
                  _select(
                    '$path.$i.image_fit',
                    'fit',
                    _enum(['fill', 'whole-image']),
                    nullLabel: 'inherit',
                  ),
                  _select(
                    '$path.$i.card_layout',
                    'layout',
                    _enum(['standard', 'cutout']),
                    nullLabel: 'inherit',
                  ),
                ],
              ),
            ),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey('content-add-$path-$_generation'),
          isExpanded: true,
          initialValue: null,
          decoration: InputDecoration(labelText: c('add')),
          items: _options(
            (choices ?? [])
                .where((choice) => !selected.contains(choice.id))
                .toList(),
          ),
          onChanged: _editable && rows.length < (categories ? 100 : 500)
              ? (id) {
                  if (id == null) return;
                  setState(() {
                    rows.add({
                      idKey: id,
                      'image_fit': null,
                      'card_layout': null,
                      if (categories) ...{
                        'heading': null,
                        'blurb': null,
                        'editorial_media_id': null,
                      },
                    });
                    _generation++;
                    _notifyDraft(true);
                  });
                }
              : null,
        ),
      ],
    );
  }

  Map<String, dynamic> _normalizedDraft() {
    final json = jsonDecode(jsonEncode(_draft)) as Map<String, dynamic>;
    void norm(Map map, String key, int max, {bool legacy = false}) {
      map[key] = unicode.normalizeContentText(
        map[key] as String?,
        max,
        legacy: legacy,
      );
    }

    for (final (field, max) in [
      ('hero_headline', 120),
      ('hero_subline', 180),
      ('announcement_text', 240),
    ]) {
      norm(json, field, max, legacy: true);
    }
    final hero = json['hero'] as Map;
    for (final (field, max) in [
      ('eyebrow', 60),
      ('stamp', 80),
      ('footnote', 120),
    ]) {
      norm(hero, field, max);
    }
    final segments = json['announcement_segments'] as List?;
    if (segments != null) {
      json['announcement_segments'] = segments.isEmpty
          ? null
          : [
              for (final s in segments)
                unicode.normalizeContentText(s as String?, 40),
            ];
    }
    for (final kind in ['promo', 'story']) {
      final module = json[kind] as Map?;
      if (module == null) continue;
      for (final (field, max) in [
        ('kicker', 60),
        ('title', 120),
        ('body', 600),
      ]) {
        norm(module, field, max);
      }
      if (kind == 'story') {
        module['facts'] = [
          for (final fact in module['facts'] as List)
            unicode.normalizeContentText(fact as String?, 80),
        ];
      }
    }
    for (final row in json['category_presentation'] as List) {
      norm(row as Map, 'heading', 80);
      norm(row, 'blurb', 120);
    }
    return json;
  }

  Future<void> _save({bool replay = false}) async {
    if (!mounted ||
        _busy ||
        (!replay && !_editable) ||
        _bindingHold ||
        (replay && _pending == null))
      return;
    final binding = _bindingGeneration;
    final repository = widget.repository;
    final snapshot = _read?.snapshot;
    if (snapshot == null) return;
    StorefrontContentAttempt attempt;
    try {
      attempt = replay
          ? _pending!
          : repository.prepareContent(
              expectedVersion: snapshot.version,
              expectedBranchId: snapshot.branchId,
              document: StorefrontContentDocument.fromJson(_normalizedDraft()),
            );
    } on StorefrontDecodeException catch (error) {
      setState(() {
        _message = 'invalid';
        _invalidField = _fieldLabel(error.field);
      });
      return;
    } catch (_) {
      setState(() => _message = 'invalid');
      return;
    }
    // Until a definitive response arrives, retain the exact original attempt.
    _pending = attempt;
    _setBusy(true);
    StorefrontContentWrite result;
    try {
      result = await repository.saveContent(attempt);
    } catch (_) {
      result = StorefrontContentWrite(
        StorefrontContentWriteStatus.uncertain,
        attempt: attempt,
      );
    }
    if (!_current(binding)) return;
    switch (result.status) {
      case StorefrontContentWriteStatus.ok:
        _pending = null;
        _confirmedSave = attempt;
        _notifyDraft(false);
        await _refreshConfirmed(binding);
        return;
      case StorefrontContentWriteStatus.uncertain:
        setState(() {
          _pending = attempt;
          _busy = false;
          _message = 'uncertain';
        });
        widget.onBusyChanged(true);
        return;
      case StorefrontContentWriteStatus.conflict:
      case StorefrontContentWriteStatus.branchConflict:
        setState(() {
          _pending = null;
          _stale = true;
          _message = 'conflict';
        });
      case StorefrontContentWriteStatus.denied:
        setState(() => _message = 'denied');
      case StorefrontContentWriteStatus.notFound:
        setState(() => _message = 'missing');
      case StorefrontContentWriteStatus.invalid:
        setState(() {
          _message = result.reason == 'target_invalid'
              ? 'targetInvalid'
              : 'invalid';
          _invalidField = _fieldLabel(result.field);
        });
      case StorefrontContentWriteStatus.unavailable:
        setState(() => _message = 'unavailable');
    }
    _pending = null;
    _setBusy(false);
  }

  String? _fieldLabel(String? field) => switch (field?.split('.').first) {
    'hero_headline' => 'headline',
    'hero_subline' => 'subline',
    'announcement_text' => 'announcement',
    'announcement_segments' => 'segments',
    'hero' => 'hero',
    'promo' => 'promo',
    'story' => 'story',
    'category_presentation' => 'categoryPresentation',
    'item_presentation' => 'itemPresentation',
    _ => null,
  };

  List<({String id, String label, StorefrontMediaSource source})> _sources(
    StorefrontSourceOptions? sources,
  ) => [
    if (sources?.receiptLogoKey case final String key)
      (
        id: 'logo',
        label: c('editorial'),
        source: StorefrontMediaSource.receiptLogo(key),
      ),
    for (final image in sources?.menuImages ?? <StorefrontMenuImageOption>[])
      (
        id: image.itemId,
        label: image.itemName,
        source: StorefrontMediaSource.menuImage(image.imageKey),
      ),
  ];
  Future<void> _publish({bool replay = false}) async {
    if (!mounted ||
        _busy ||
        (!replay && (!_editable || _dirty)) ||
        _bindingHold ||
        (replay && _pendingPublish == null))
      return;
    final binding = _bindingGeneration;
    final publisher = widget.publisher;
    final reloadSources = widget.reloadSources;
    final branch = widget.savedBranchId;
    if (publisher == null) return;
    final initial = _sources(
      widget.sources,
    ).where((source) => source.id == _sourceId).firstOrNull;
    if (!replay && initial == null) return;
    if (!replay && !await _confirm('publishConfirm')) return;
    if (!_current(binding)) return;
    if (!replay && (!_editable || _dirty)) return;
    _setBusy(true);
    final source = _pendingPublish?.source ?? initial!.source;
    StorefrontSourceOptions? fresh;
    try {
      fresh = await reloadSources?.call();
    } catch (_) {
      fresh = null;
    }
    if (!_current(binding)) return;
    if (!replay &&
        (fresh == null ||
            !_sources(fresh).any(
              (entry) =>
                  entry.source.bucket == source.bucket &&
                  entry.source.key == source.key,
            ))) {
      _setBusy(false);
      setState(() => _message = 'mediaUnavailable');
      return;
    }
    final requestId =
        _pendingPublish?.requestId ??
        storefrontRequestId('pbl:storefront:editorial:', [
          branch,
          source.bucket.wire,
          source.key,
        ], DateTime.now().microsecondsSinceEpoch);
    StorefrontPublishResult result;
    _pendingPublish = (source: source, requestId: requestId, branchId: branch);
    try {
      result = await publisher.publish(
        slot: StorefrontEditorialTarget.editorial,
        source: source,
        requestId: requestId,
      );
    } catch (_) {
      result = StorefrontPublishResult(
        StorefrontPublishStatus.uncertain,
        requestId: requestId,
        slot: StorefrontEditorialTarget.editorial,
      );
    }
    if (!_current(binding)) return;
    if (result.isPublished) {
      // No slot/profile write here. The owner selects a content media reference
      // and saves the whole document through the same global profile CAS.
      _pendingPublish = null;
      _confirmedPublish = (
        source: source,
        requestId: requestId,
        branchId: branch,
      );
      await _refreshConfirmed(binding);
    } else if (result.status == StorefrontPublishStatus.uncertain) {
      setState(() {
        _pendingPublish = (
          source: source,
          requestId: requestId,
          branchId: branch,
        );
        _busy = false;
        _message = 'publishUncertain';
      });
      widget.onBusyChanged(true);
    } else {
      setState(() {
        _pendingPublish = null;
        _message = 'unavailable';
      });
      _setBusy(false);
    }
  }

  Widget _publication() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title('media'),
      Text(c('publishHelp')),
      if (_media == null) Text(c('mediaUnavailable')),
      for (final row in _media?.rows ?? <StorefrontContentMediaRow>[])
        if (row.media.isLive)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.publicUrlFor != null)
                Image.network(
                  widget.publicUrlFor!(row.media.objectKey).toString(),
                  width: 100,
                  height: 70,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              Text(
                '${row.media.id.substring(0, 8)} · ${c('mediaUsage')}: ${[...row.media.inUse.map((slot) => slot.wire), ...row.contentInUse.map((use) => c(use['kind']!))].join(', ')}',
              ),
            ],
          ),
      if (widget.publisher != null) ...[
        DropdownButtonFormField<String>(
          key: ValueKey('content-source-$_generation'),
          isExpanded: true,
          initialValue: _sourceId,
          items: [
            for (final source in _sources(widget.sources))
              DropdownMenuItem(value: source.id, child: Text(source.label)),
          ],
          onChanged: _editable && !_dirty
              ? (id) => setState(() => _sourceId = id)
              : null,
        ),
        TextButton(
          onPressed: _editable && !_dirty && _sourceId != null
              ? () => _publish()
              : null,
          child: Text(c('publish')),
        ),
        if (_pendingPublish != null)
          TextButton(
            onPressed: _busy || _bindingHold
                ? null
                : () => _publish(replay: true),
            child: Text(c('retry')),
          ),
      ],
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (_branchHold)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('title'),
          Text(c('bindingChanged'), key: const Key('content-message')),
        ],
      );
    if (_read == null) return const LinearProgressIndicator();
    final status = _read!.status;
    return Column(
      key: const Key('storefront-content-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        _title('title'),
        Text(c('help')),
        if (_message != null)
          Semantics(
            liveRegion: true,
            child: Text(c(_message!), key: const Key('content-message')),
          ),
        if (_invalidField != null)
          Text(c(_invalidField!), key: const Key('content-invalid-field')),
        if (status != StorefrontContentReadStatus.ok) ...[
          Text(
            c(switch (status) {
              StorefrontContentReadStatus.denied => 'denied',
              StorefrontContentReadStatus.notFound => 'missing',
              _ => 'loadFailed',
            }),
          ),
          TextButton(onPressed: _busy ? null : _load, child: Text(c('reload'))),
        ] else ...[
          for (final warning in _read!.snapshot!.warnings)
            Text('${c(warning.reason)} (${warning.field})'),
          if (!widget.enabled) Text(c('otherEdits')),
          TextField(
            key: const Key('content-hero-headline'),
            controller: _headline,
            enabled: _editable,
            decoration: InputDecoration(labelText: c('headline')),
            onChanged: (value) {
              if (!mounted || !_editable) return;
              _change('hero_headline', value);
              _put('hero.format', null);
              _selection.clear();
            },
          ),
          _text('hero_subline', 'subline', lines: 2),
          _text('announcement_text', 'announcement', lines: 2),
          _title('hero'),
          _select(
            'hero.mode',
            'hero',
            _enum(['editorial', 'item']),
            nullable: false,
          ),
          _select('hero.item_id', 'item', _options(_catalog?.items ?? [])),
          _text('hero.eyebrow', 'eyebrow'),
          _text('hero.stamp', 'stamp'),
          _text('hero.footnote', 'footnote'),
          _formatEditor(),
          _stringList('announcement_segments', 'segments', 6),
          _module('promo'),
          _module('story'),
          _presentations(true),
          _presentations(false),
          _publication(),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const Key('content-save'),
                onPressed: _editable && _dirty ? () => _save() : null,
                child: Text(c('save')),
              ),
              if (_pending != null)
                OutlinedButton(
                  key: const Key('content-retry-save'),
                  onPressed: _busy || _bindingHold
                      ? null
                      : () => _save(replay: true),
                  child: Text(c('retry')),
                ),
              if (_confirmedSave != null || _confirmedPublish != null)
                TextButton(
                  key: const Key('content-resume-read'),
                  onPressed: _busy || _bindingHold
                      ? null
                      : _resumeConfirmedRead,
                  child: Text(c('resumeRead')),
                ),
              TextButton(
                onPressed:
                    _busy ||
                        _pending != null ||
                        _pendingPublish != null ||
                        _confirmedSave != null ||
                        _confirmedPublish != null
                    ? null
                    : _reload,
                child: Text(c('reload')),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
