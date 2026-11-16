import 'package:flutter/material.dart';

import 'storefront_welcome_video_copy.dart';
import 'storefront_welcome_video_models.dart';
import 'storefront_welcome_video_picker.dart';
import 'storefront_welcome_video_publisher.dart';
import 'storefront_welcome_video_upload.dart';

/// Publication is an explicit, separate action. This editor only emits draft
/// mode/selection changes; the parent's existing content CAS action saves them.
class StorefrontWelcomeVideoEditor extends StatefulWidget {
  const StorefrontWelcomeVideoEditor({
    required this.media,
    required this.mode,
    required this.selectedId,
    required this.onChanged,
    required this.onReload,
    required this.enabled,
    required this.canPublish,
    required this.onBusyChanged,
    this.libraryAvailable = true,
    this.publisher,
    this.uploader,
    this.publicUrlFor,
    this.bindingIdentity,
    this.requestIds,
    super.key,
  });
  final List<StorefrontWelcomeVideoMedia> media;
  final String? mode, selectedId;
  final void Function(String field, Object? value) onChanged;
  final Future<void> Function() onReload;
  final bool enabled, canPublish;
  final bool libraryAvailable;
  final ValueChanged<bool> onBusyChanged;
  final StorefrontWelcomeVideoPublisher? publisher;
  final StorefrontWelcomeVideoUpload? uploader;
  final Uri Function(String objectKey)? publicUrlFor;

  /// Membership/authenticated-binding identity, not profile version/draft state.
  final Object? bindingIdentity;
  final String Function()? requestIds;
  @override
  State<StorefrontWelcomeVideoEditor> createState() => _EditorState();
}

class _EditorState extends State<StorefrontWelcomeVideoEditor> {
  bool _busy = false;
  int _generation = 0;
  String? _message;
  StorefrontWelcomeVideoAttempt? _pending;
  StorefrontWelcomeVideoMedia? _lastPublished;
  String c(String key) => welcomeVideoCopy(context, key);
  bool get _editable => widget.enabled && !_busy;

  bool _sameBinding(StorefrontWelcomeVideoEditor old) =>
      old.bindingIdentity == widget.bindingIdentity &&
      identical(
        old.publisher?.bindingIdentity,
        widget.publisher?.bindingIdentity,
      ) &&
      old.publisher?.organizationId == widget.publisher?.organizationId &&
      old.publisher?.restaurantId == widget.publisher?.restaurantId &&
      identical(old.uploader?.storage, widget.uploader?.storage) &&
      old.uploader?.organizationId == widget.uploader?.organizationId &&
      old.uploader?.restaurantId == widget.uploader?.restaurantId;

  @override
  void didUpdateWidget(covariant StorefrontWelcomeVideoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameBinding(oldWidget)) return;
    final abandonedBusy = _busy;
    final notifyPreviousOwner = oldWidget.onBusyChanged;
    final generation = ++_generation;
    _busy = false;
    _pending = null;
    _lastPublished = null;
    _message = 'bindingChanged';
    // An idle editor owns no parent lock. Release only an abandoned operation,
    // through its original owner; a replacement binding owns its own state.
    if (abandonedBusy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && !_busy)
          notifyPreviousOwner(false);
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  bool _current(int generation) => mounted && generation == _generation;
  void _begin() {
    setState(() {
      _busy = true;
      _message = null;
    });
    widget.onBusyChanged(true);
  }

  void _finish(int generation) {
    if (!_current(generation)) return;
    setState(() => _busy = false);
    widget.onBusyChanged(false);
  }

  Future<void> _publish({bool retry = false}) async {
    final publisher = widget.publisher, uploader = widget.uploader;
    if (!_editable ||
        !widget.canPublish ||
        publisher == null ||
        (!retry && (uploader?.supported != true || _pending != null)) ||
        (retry && _pending == null))
      return;
    if (uploader != null &&
        (uploader.organizationId != publisher.organizationId ||
            uploader.restaurantId != publisher.restaurantId))
      return;
    final generation = ++_generation;
    final notify = widget.onBusyChanged;
    _begin();
    try {
      StorefrontWelcomeVideoAttempt attempt;
      if (retry) {
        attempt = _pending!;
      } else {
        final source = await uploader!.pickAndUpload(
          isCurrent: () => _current(generation),
        );
        if (!_current(generation) || source == null) return;
        attempt = publisher.prepare(
          sourceKey: source,
          requestId: (widget.requestIds ?? newWelcomeVideoId)(),
        );
      }
      if (!_current(generation)) return;
      // Store before POST: an unknown outcome may only be retried verbatim.
      _pending = attempt;
      final result = await publisher.publish(attempt);
      if (!_current(generation)) return;
      _pending = result.isUncertain ? attempt : null;
      _message = result.status.name;
      if (result.isPublished) {
        _lastPublished = result.media;
        try {
          await widget.onReload();
        } catch (_) {
          if (_current(generation)) _message = 'publishedReadFailed';
        }
      }
    } on FormatException {
      if (_current(generation)) _message = 'invalidFile';
    } catch (_) {
      if (_current(generation))
        _message = _pending == null ? 'uploadFailed' : 'uncertain';
    } finally {
      if (_current(generation))
        _finish(generation);
      else if (!mounted)
        notify(false);
    }
  }

  Future<void> _reload() async {
    if (!_editable) return;
    final generation = ++_generation, notify = widget.onBusyChanged;
    _begin();
    try {
      await widget.onReload();
    } catch (_) {
      if (_current(generation)) _message = 'readFailed';
    } finally {
      if (_current(generation))
        _finish(generation);
      else if (!mounted)
        notify(false);
    }
  }

  Uri? _publicUrl(StorefrontWelcomeVideoMedia media) {
    if (!media.published ||
        media.publicPath == null ||
        widget.publicUrlFor == null)
      return null;
    try {
      final uri = widget.publicUrlFor!(media.objectKey);
      if ((uri.scheme != 'https' &&
              !(uri.scheme == 'http' &&
                  const ['127.0.0.1', 'localhost'].contains(uri.host))) ||
          uri.path != media.publicPath ||
          uri.hasQuery ||
          uri.hasFragment)
        return null;
      return uri;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.media.where((v) => v.published).toList(growable: false);
    final selected = rows.where((v) => v.id == widget.selectedId).firstOrNull;
    final preview = _lastPublished ?? selected;
    final url = preview == null ? null : _publicUrl(preview);
    final mode = widget.mode ?? 'legacy';
    return Column(
      key: const Key('welcome-video-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c('title'), style: Theme.of(context).textTheme.titleSmall),
        Text(c('help')),
        Text(c('publicCopyHelp'), style: Theme.of(context).textTheme.bodySmall),
        if (!widget.libraryAvailable) Text(c('readFailed')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('welcome-video-mode-$mode'),
          initialValue: mode,
          isExpanded: true,
          decoration: InputDecoration(labelText: c('mode')),
          items: [
            for (final value in ['legacy', 'image', 'video'])
              DropdownMenuItem(
                value: value,
                child: Text(
                  c(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _editable
              ? (value) => widget.onChanged(
                  'welcome_media_type',
                  value == 'legacy' ? null : value,
                )
              : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(
            'welcome-video-selection-${widget.selectedId ?? 'none'}',
          ),
          initialValue: widget.selectedId ?? 'none',
          isExpanded: true,
          decoration: InputDecoration(labelText: c('choose')),
          items: [
            DropdownMenuItem(
              value: 'none',
              child: Text(
                c('none'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final row in rows)
              DropdownMenuItem(
                value: row.id,
                child: Text(
                  '${row.width}×${row.height} · ${(row.durationMs / 1000).toStringAsFixed(1)} s · ${row.id.substring(0, 8)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (widget.selectedId != null && selected == null)
              DropdownMenuItem(
                value: widget.selectedId,
                enabled: false,
                child: Text(
                  c('unavailableSelection'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _editable
              ? (value) => widget.onChanged(
                  'welcome_video_media_id',
                  value == 'none' ? null : value,
                )
              : null,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('welcome-video-upload'),
              onPressed:
                  _editable &&
                      widget.canPublish &&
                      widget.uploader?.supported == true &&
                      widget.publisher != null &&
                      _pending == null
                  ? () => _publish()
                  : null,
              icon: const Icon(Icons.video_file_outlined),
              label: Text(c('upload')),
            ),
            TextButton(
              key: const Key('welcome-video-reload'),
              onPressed: _editable ? _reload : null,
              child: Text(c('reload')),
            ),
            if (_pending != null)
              TextButton(
                key: const Key('welcome-video-retry'),
                onPressed:
                    _editable && widget.canPublish && widget.publisher != null
                    ? () => _publish(retry: true)
                    : null,
                child: Text(c('retry')),
              ),
          ],
        ),
        if (widget.uploader?.supported != true) Text(c('pickerUnavailable')),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Semantics(
            liveRegion: true,
            child: Text(c(_message!), key: const Key('welcome-video-message')),
          ),
        if (url != null) ...[
          const SizedBox(height: 8),
          Text(c('previewHelp')),
          TextButton.icon(
            key: const Key('welcome-video-public-preview'),
            onPressed: welcomeVideoLinkSupported
                ? () => openPublishedWelcomeVideo(url)
                : null,
            icon: const Icon(Icons.open_in_new),
            label: Text(c('previewLink')),
          ),
          SelectableText(url.toString(), textDirection: TextDirection.ltr),
        ],
      ],
    );
  }
}
