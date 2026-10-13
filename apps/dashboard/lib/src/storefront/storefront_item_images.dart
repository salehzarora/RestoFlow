import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_media_publisher.dart';
import 'storefront_models.dart';
import 'storefront_sources.dart';

/// Publishes existing originals sequentially, without uploading them again or
/// assigning profile slots. Server stage/finalize enforce current ownership.
class StorefrontItemImages extends StatefulWidget {
  const StorefrontItemImages({
    super.key,
    required this.publisher,
    required this.sources,
    required this.reloadSources,
    required this.onRefresh,
    required this.onBusyChanged,
    required this.nonce,
    required this.enabled,
  });

  final StorefrontMediaPublisher publisher;
  final StorefrontSourceOptions? sources;
  final Future<StorefrontSourceOptions> Function() reloadSources;
  final Future<bool> Function() onRefresh;
  final ValueChanged<bool> onBusyChanged;
  final int Function()? nonce;
  final bool enabled;

  @override
  State<StorefrontItemImages> createState() => _StorefrontItemImagesState();
}

class _StorefrontItemImagesState extends State<StorefrontItemImages> {
  final _results = <String, StorefrontPublishResult>{};
  // An uncertain result retains the SAME logical request for a manual retry.
  final _pending = <String, String>{};
  bool _busy = false;
  bool _sourceUnavailable = false;
  String? _current;

  Future<void> _publish({String? itemId}) async {
    if (_busy || !widget.enabled) return;
    setState(() {
      _busy = true;
      _sourceUnavailable = false;
    });
    widget.onBusyChanged(true);
    try {
      // Never publish the stale source options rendered before the click.
      final sources = await widget.reloadSources();
      if (!mounted) return;
      if (sources.menuImagesUnavailable) {
        setState(() => _sourceUnavailable = true);
        return;
      }
      final currentKeys = sources.menuImages.map((i) => i.imageKey).toSet();
      _results.removeWhere((key, _) => !currentKeys.contains(key));
      _pending.removeWhere((key, _) => !currentKeys.contains(key));
      for (final item in sources.menuImages) {
        if (itemId != null && item.itemId != itemId) continue;
        if (!mounted)
          return; // Scope switch/disposal stops the remaining batch.
        setState(() => _current = item.itemId);
        final requestId = _pending.putIfAbsent(
          item.imageKey,
          () => storefrontRequestId(
            'pbl:storefront-item-publish:',
            [
              widget.publisher.organizationId,
              widget.publisher.restaurantId,
              item.itemId,
              item.imageKey,
            ],
            widget.nonce?.call() ?? DateTime.now().microsecondsSinceEpoch,
          ),
        );
        final result = await widget.publisher.publish(
          slot: StorefrontItemTarget.item,
          source: StorefrontMediaSource.menuImage(item.imageKey),
          requestId: requestId,
        );
        if (!mounted) return;
        setState(() => _results[item.imageKey] = result);
        if (result.status != StorefrontPublishStatus.uncertain) {
          _pending.remove(item.imageKey);
        }
        // Authentication/service failures affect the whole batch. Individual
        // missing/refused images remain visible and do not block other items.
        if (result.status == StorefrontPublishStatus.denied ||
            result.status == StorefrontPublishStatus.unauthenticated ||
            result.status == StorefrontPublishStatus.serviceUnavailable ||
            result.status == StorefrontPublishStatus.invalidRequest ||
            result.status == StorefrontPublishStatus.uncertain) {
          break;
        }
      }
      if (mounted) await widget.onRefresh();
    } catch (_) {
      if (mounted) setState(() => _sourceUnavailable = true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _current = null;
        });
        widget.onBusyChanged(false);
      }
    }
  }

  String _status(AppLocalizations l10n, StorefrontPublishResult result) =>
      switch (result.status) {
        StorefrontPublishStatus.published => l10n.storefrontItemImagePublished,
        StorefrontPublishStatus.uncertain => l10n.storefrontItemImageUnknown,
        StorefrontPublishStatus.sourceMissing =>
          l10n.storefrontPublishSourceMissing,
        StorefrontPublishStatus.unauthenticated =>
          l10n.storefrontPublishUnauthenticated,
        StorefrontPublishStatus.denied => l10n.storefrontItemImageDenied,
        _ => l10n.storefrontItemImageFailed,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sources = widget.sources;
    final items = sources?.menuImages ?? const <StorefrontMenuImageOption>[];
    final unavailable =
        _sourceUnavailable || sources?.menuImagesUnavailable == true;
    final enabled = widget.enabled && !_busy;
    return ExpansionTile(
      key: const Key('storefront-item-images'),
      title: Text(l10n.storefrontItemImagesTitle),
      subtitle: Text(l10n.storefrontItemImagesCount(items.length)),
      childrenPadding: const EdgeInsets.all(12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.storefrontItemImagesHelp),
        if (unavailable) Text(l10n.storefrontItemImagesUnavailable),
        if (sources == null || _busy) const LinearProgressIndicator(),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            key: const Key('storefront-item-images-publish-all'),
            onPressed: enabled && sources != null ? () => _publish() : null,
            icon: const Icon(Icons.publish),
            label: Text(l10n.storefrontItemImagesPublishAll),
          ),
        ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.itemName),
                      if (_results[item.imageKey] case final result?)
                        Text(_status(l10n, result)),
                    ],
                  ),
                ),
                if (_current == item.itemId)
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                TextButton(
                  key: ValueKey('storefront-item-image-${item.itemId}'),
                  onPressed: enabled
                      ? () => _publish(itemId: item.itemId)
                      : null,
                  child: Text(l10n.storefrontItemImagePublish),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
