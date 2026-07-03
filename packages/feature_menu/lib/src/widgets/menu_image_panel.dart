import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/menu_image_path.dart';
import '../data/menu_image_storage.dart';
import '../data/picked_menu_image.dart';
import '../models/menu_item.dart';
import '../models/menu_write_failure.dart';
import '../state/menu_providers.dart';
import 'menu_components.dart';
import 'menu_l10n.dart';

/// A client-side validation / flow problem in the image panel.
enum _PanelIssue { invalidType, tooLarge, uploadFailed }

/// The REAL item-image panel (menu/media sprint — replaces the RF-111 gated
/// shell). Pick a file (zero-dependency web picker) -> validate against the
/// RF-110 bucket rules -> local preview -> on explicit confirm: upload to a
/// fresh `buildMenuImageObjectKey` then persist `image_path` via the item
/// upsert. REPLACE uploads a new image id + persists; REMOVE persists null +
/// best-effort deletes the blob. Existing images preview via a short-lived
/// signed URL (private bucket — D-032; never a public URL).
///
/// HONESTY RULES: nothing claims success before BOTH the storage upload and
/// the RPC persist succeed; storage/persist failures render a visible danger
/// notice; a surface without wired storage shows an explicit "not connected"
/// state; the demo surface labels itself "not uploaded to a server".
class MenuImagePanel extends ConsumerStatefulWidget {
  const MenuImagePanel({required this.item, super.key});

  /// The item being edited — callers must pass the FRESHEST snapshot row so
  /// [MenuItem.imagePath] reflects the latest persisted state.
  final MenuItem item;

  @override
  ConsumerState<MenuImagePanel> createState() => _MenuImagePanelState();
}

class _MenuImagePanelState extends ConsumerState<MenuImagePanel> {
  PickedMenuImage? _picked;
  bool _busy = false;
  _PanelIssue? _issue;
  MenuWriteFailure? _persistFailure;

  // The signed-URL future is cached per object key so rebuilds don't re-sign.
  String? _signedForPath;
  Future<Uri>? _signedUrlFuture;

  Future<Uri> _signedUrl(MenuImageStorage storage, String path) {
    if (_signedForPath != path || _signedUrlFuture == null) {
      _signedForPath = path;
      _signedUrlFuture = storage.createSignedUrl(path);
    }
    return _signedUrlFuture!;
  }

  Future<void> _pick() async {
    final picked = await ref.read(menuImageFilePickerProvider)();
    if (!mounted || picked == null) return;
    setState(() {
      _persistFailure = null;
      if (!isAllowedMenuImageMime(picked.mimeType)) {
        _issue = _PanelIssue.invalidType;
        _picked = null;
      } else if (!isWithinMenuImageSizeLimit(picked.bytes.length)) {
        _issue = _PanelIssue.tooLarge;
        _picked = null;
      } else {
        _issue = null;
        _picked = picked;
      }
    });
  }

  static String _extensionFor(String mimeType) =>
      switch (mimeType.trim().toLowerCase()) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };

  /// Uploads the picked bytes, then persists the pointer. Order matters: the
  /// pointer is only written AFTER the blob exists, and a failed persist
  /// best-effort-removes the fresh blob — no state ever claims a saved image
  /// that isn't fully saved.
  Future<void> _saveImage(MenuImageStorage storage) async {
    final picked = _picked;
    final item = widget.item;
    if (picked == null || _busy) return;
    setState(() {
      _busy = true;
      _issue = null;
      _persistFailure = null;
    });
    final objectKey = buildMenuImageObjectKey(
      organizationId: item.organizationId,
      restaurantId: item.restaurantId,
      branchId: item.branchId,
      menuItemId: item.id,
      imageId: RandomImageIdGenerator().newImageId(),
      extension: _extensionFor(picked.mimeType),
    );
    try {
      await storage.upload(
        objectKey: objectKey,
        bytes: picked.bytes,
        mimeType: picked.mimeType,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _issue =
            _PanelIssue.uploadFailed; // visible danger — never fake success
      });
      return;
    }
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .upsertItem(
          id: item.id,
          menuCategoryId: item.menuCategoryId,
          name: item.name,
          description: item.description,
          basePriceMinor: item.basePriceMinor,
          currencyCode: item.currencyCode,
          displayOrder: item.displayOrder,
          isActive: item.isActive,
          imagePath: objectKey,
          // Full-state upsert: carry the rich attributes through or an image
          // save would silently clear them (same rule as imagePath itself).
          itemType: item.itemType,
          tags: item.tags,
          prepMinutes: item.prepMinutes,
          sku: item.sku,
          kitchenNote: item.kitchenNote,
          attributes: item.attributes,
        );
    if (!mounted) return;
    outcome.fold(
      (_) {
        // Persisted. Replace = the OLD blob is now unreachable — best-effort
        // cleanup (an orphaned blob is harmless if this fails).
        final oldPath = item.imagePath;
        if (oldPath != null && oldPath != objectKey) {
          unawaited(_bestEffortRemove(storage, oldPath));
        }
        setState(() {
          _busy = false;
          _picked = null;
        });
      },
      (failure) {
        // The pointer was NOT saved — clean up the fresh blob (best-effort)
        // and show the real failure.
        unawaited(_bestEffortRemove(storage, objectKey));
        setState(() {
          _busy = false;
          _persistFailure = failure;
        });
      },
    );
  }

  Future<void> _removeImage(MenuImageStorage storage) async {
    final item = widget.item;
    final oldPath = item.imagePath;
    if (oldPath == null || _busy) return;
    setState(() {
      _busy = true;
      _issue = null;
      _persistFailure = null;
    });
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .upsertItem(
          id: item.id,
          menuCategoryId: item.menuCategoryId,
          name: item.name,
          description: item.description,
          basePriceMinor: item.basePriceMinor,
          currencyCode: item.currencyCode,
          displayOrder: item.displayOrder,
          isActive: item.isActive,
          imagePath: null, // null = clear/unset on the server
          // Full-state upsert: removing the image must not clear the rest.
          itemType: item.itemType,
          tags: item.tags,
          prepMinutes: item.prepMinutes,
          sku: item.sku,
          kitchenNote: item.kitchenNote,
          attributes: item.attributes,
        );
    if (!mounted) return;
    outcome.fold(
      (_) {
        unawaited(_bestEffortRemove(storage, oldPath));
        setState(() => _busy = false);
      },
      (failure) => setState(() {
        _busy = false;
        _persistFailure = failure;
      }),
    );
  }

  static Future<void> _bestEffortRemove(
    MenuImageStorage storage,
    String path,
  ) async {
    try {
      await storage.remove(path);
    } catch (_) {
      // Best-effort only: the pointer state is already correct.
    }
  }

  String? _errorText(AppLocalizations l10n) {
    final issue = _issue;
    if (issue != null) {
      return switch (issue) {
        _PanelIssue.invalidType => l10n.menuImageInvalidType,
        _PanelIssue.tooLarge => l10n.menuImageTooLarge,
        _PanelIssue.uploadFailed => l10n.menuImageUploadFailed,
      };
    }
    final failure = _persistFailure;
    if (failure != null) return l10n.menuWriteFailureText(failure);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final config = ref.watch(menuImageStorageProvider);

    if (config == null) {
      // Honest state: no image storage is wired for this surface.
      return MenuSectionCard(
        title: l10n.menuImageHeading,
        icon: Icons.image_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.menuImageDeferredTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              l10n.menuImageDeferredBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final pickerSupported = ref.watch(menuImagePickerSupportedProvider);
    final preview = _preview(context, config.storage);
    final controls = _controls(context, l10n, theme, config, pickerSupported);

    return MenuSectionCard(
      title: l10n.menuImageHeading,
      icon: Icons.image_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                preview,
                const SizedBox(height: RestoflowSpacing.md),
                controls,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              preview,
              const SizedBox(width: RestoflowSpacing.lg),
              Expanded(child: controls),
            ],
          );
        },
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    MenuImageStorageConfig config,
    bool pickerSupported,
  ) {
    final item = widget.item;
    final errorText = _errorText(l10n);
    final actions = <Widget>[];
    if (_picked != null) {
      actions.addAll([
        FilledButton.icon(
          key: const ValueKey('menu-image-save'),
          onPressed: _busy ? null : () => _saveImage(config.storage),
          icon: const Icon(Icons.cloud_upload_outlined, size: 18),
          label: Text(l10n.menuImageSaveAction),
        ),
        TextButton(
          key: const ValueKey('menu-image-cancel'),
          onPressed: _busy
              ? null
              : () => setState(() {
                  _picked = null;
                  _issue = null;
                  _persistFailure = null;
                }),
          child: Text(l10n.menuCancelAction),
        ),
      ]);
    } else {
      if (pickerSupported) {
        actions.add(
          FilledButton.tonalIcon(
            key: const ValueKey('menu-image-pick'),
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(
              item.imagePath == null
                  ? l10n.menuImagePickAction
                  : l10n.menuImageReplaceAction,
            ),
          ),
        );
      }
      if (item.imagePath != null) {
        actions.add(
          TextButton.icon(
            key: const ValueKey('menu-image-remove'),
            onPressed: _busy ? null : () => _removeImage(config.storage),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(l10n.menuImageRemoveAction),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (errorText != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsetsDirectional.all(RestoflowSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(RestoflowRadii.sm),
            ),
            child: Text(
              errorText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(height: RestoflowSpacing.sm),
        ],
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: RestoflowSpacing.sm),
        ],
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.xs,
          children: actions,
        ),
        if (!pickerSupported) ...[
          const SizedBox(height: RestoflowSpacing.sm),
          Text(
            l10n.menuImageUnsupportedPlatform,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (config.isDemo) ...[
          const SizedBox(height: RestoflowSpacing.sm),
          Text(
            l10n.menuImageDemoNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _preview(BuildContext context, MenuImageStorage storage) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final picked = _picked;
    if (picked != null) {
      return _previewFrame(
        theme,
        Image.memory(
          picked.bytes,
          width: 132,
          height: 132,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _placeholderContent(theme, Icons.broken_image_outlined, null),
        ),
      );
    }
    final imagePath = widget.item.imagePath;
    if (imagePath != null) {
      return _previewFrame(
        theme,
        FutureBuilder<Uri>(
          future: _signedUrl(storage, imagePath),
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url != null) {
              return Image.network(
                url.toString(),
                width: 132,
                height: 132,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _placeholderContent(
                      theme,
                      Icons.broken_image_outlined,
                      l10n.menuImageLoadError,
                    ),
              );
            }
            if (snapshot.hasError) {
              return _placeholderContent(
                theme,
                Icons.broken_image_outlined,
                l10n.menuImageLoadError,
              );
            }
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        ),
      );
    }
    return _previewFrame(
      theme,
      _placeholderContent(
        theme,
        Icons.add_photo_alternate_outlined,
        l10n.menuImageEmptyHint,
      ),
    );
  }

  Widget _previewFrame(ThemeData theme, Widget child) {
    return Container(
      width: 132,
      height: 132,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _placeholderContent(ThemeData theme, IconData icon, String? caption) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 34, color: theme.colorScheme.onSurfaceVariant),
        if (caption != null) ...[
          const SizedBox(height: RestoflowSpacing.sm),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: RestoflowSpacing.xs,
            ),
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
