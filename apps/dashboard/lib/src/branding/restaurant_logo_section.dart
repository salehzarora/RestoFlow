import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminSectionCard;
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show
        PickedMenuImage,
        kSignedUrlValidity,
        menuImagePickerSupported,
        pickMenuImageFile,
        signedUrlCacheFor;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show LogoValidationError;

import 'restaurant_logo_path.dart';
import 'restaurant_logo_repository.dart';
import 'restaurant_logo_storage.dart';

/// PRINT-BRANDING-LOGO-001 (§10/§11) — the Dashboard receipt-branding card:
/// preview the current logo, pick + validate + preview a new one locally, Save
/// (upload-then-pointer with a versioned CAS), Replace, Remove (confirmed), and
/// an enable/disable switch. Every mutation is duplicate-click-guarded, honest
/// about failures, and never rolls back a committed pointer for a best-effort
/// cleanup miss.
class RestaurantLogoSection extends StatefulWidget {
  const RestaurantLogoSection({
    required this.repository,
    required this.storage,
    required this.organizationId,
    required this.restaurantId,
    this.isDemo = false,
    this.idGenerator,
    this.picker,
    this.pickerSupported,
    this.decodeValidator,
    super.key,
  });

  final RestaurantLogoRepository? repository;
  final RestaurantLogoStorage? storage;
  final String organizationId;
  final String restaurantId;
  final bool isDemo;

  final LogoImageIdGenerator? idGenerator;
  final Future<PickedMenuImage?> Function()? picker;
  final bool? pickerSupported;

  /// Validate picked bytes (byte + decoded checks); null == accepted.
  final Future<LogoValidationError?> Function(Uint8List bytes)? decodeValidator;

  @override
  State<RestaurantLogoSection> createState() => _RestaurantLogoSectionState();
}

class _RestaurantLogoSectionState extends State<RestaurantLogoSection> {
  late final LogoImageIdGenerator _ids =
      widget.idGenerator ?? RandomLogoImageIdGenerator();

  RestaurantLogoSettings? _settings;
  Uri? _currentUrl;
  PickedMenuImage? _picked;

  /// Monotonic pick counter. Each [_onPick] captures its value; a NEWER pick
  /// bumps it, so an older pick's (slow) decode result is discarded instead of
  /// overwriting the newer selection — and rapid re-clicks never let a stale
  /// decode win (PRINT-BRANDING-LOGO-001).
  int _pickGeneration = 0;

  /// PRINT-BRANDING-LOGO-001 (§10/§11): the BACKEND management capability, read
  /// ONCE from the read RPC (never the role name). Editable controls appear only
  /// when true; a covering non-manager (branch-only manager / cashier /
  /// accountant) sees a read-only preview. It is NOT overwritten by write results
  /// (which never carry the capability).
  bool _canManage = false;

  bool _loading = false;
  bool _busy = false;
  bool _readFailed = false;

  /// The localized status/error to show under the controls (null == none).
  String? _message;
  bool _messageIsError = false;

  bool get _wired => widget.repository != null && widget.storage != null;
  bool get _pickerSupported =>
      widget.pickerSupported ?? menuImagePickerSupported;

  @override
  void initState() {
    super.initState();
    if (_wired) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _readFailed = false;
    });
    final settings = await widget.repository!.read();
    if (!mounted) return;
    if (settings == null) {
      setState(() {
        _loading = false;
        _readFailed = true;
      });
      return;
    }
    Uri? url;
    if (settings.hasLogo) {
      try {
        // EGRESS-REMEDIATION-001: reuse one signed URL per logo path across
        // Settings visits (the storage instance is app-lifetime), so
        // revisiting Settings inside the validity window neither re-signs nor
        // re-downloads the unchanged logo. A replaced logo has a new
        // versioned path and resolves fresh immediately.
        url = await signedUrlCacheFor(widget.storage!).resolve(
          settings.path!,
          validity: kSignedUrlValidity,
          sign: () => widget.storage!.createSignedUrl(
            settings.path!,
            expiresIn: kSignedUrlValidity,
          ),
        );
      } catch (_) {
        url = null; // fail-soft: no preview, controls still work
      }
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _canManage = settings.canManage; // backend capability, read once
      _currentUrl = url;
      _loading = false;
    });
  }

  Future<PickedMenuImage?> _pick() =>
      (widget.picker ?? pickMenuImageFile).call();

  Future<LogoValidationError?> _validate(Uint8List bytes) async {
    final custom = widget.decodeValidator;
    if (custom != null) return custom(bytes);
    try {
      await const FlutterLogoDecoder().decode(bytes);
      return null;
    } on LogoDecodeException catch (e) {
      return e.error;
    } catch (_) {
      return LogoValidationError.decodeFailed;
    }
  }

  Future<void> _onPick() async {
    if (_busy) return;
    // Supersede any in-flight pick: a newer selection wins, and a stale (slower)
    // decode that completes later is discarded instead of clobbering it.
    final generation = ++_pickGeneration;
    final l10n = AppLocalizations.of(context);
    final picked = await _pick();
    if (generation != _pickGeneration || !mounted) return; // superseded
    if (picked == null) return;
    if (!isAllowedRestaurantLogoMime(picked.mimeType)) {
      _setMessage(l10n.brandingErrorInvalidType, isError: true);
      return;
    }
    if (!isWithinRestaurantLogoSizeLimit(picked.bytes.length)) {
      _setMessage(l10n.brandingErrorTooLarge, isError: true);
      return;
    }
    final error = await _validate(picked.bytes);
    if (generation != _pickGeneration || !mounted) return; // superseded
    if (error != null) {
      _setMessage(_messageForValidation(error, l10n), isError: true);
      return;
    }
    setState(() {
      _picked = picked;
      _message = null;
    });
  }

  Future<void> _onSave() async {
    if (_busy || _picked == null) return;
    final l10n = AppLocalizations.of(context);
    final picked = _picked!;
    final settings = _settings;
    if (settings == null) return;
    setState(() => _busy = true);

    final objectKey = buildRestaurantLogoObjectKey(
      organizationId: widget.organizationId,
      restaurantId: widget.restaurantId,
      imageId: _ids.newImageId(),
      extension: extensionForLogoMime(picked.mimeType),
    );

    // 1. Upload the new immutable object FIRST.
    try {
      await widget.storage!.upload(
        objectKey: objectKey,
        bytes: picked.bytes,
        mimeType: picked.mimeType,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setMessage(l10n.brandingErrorUploadFailed, isError: true);
      return; // the authoritative old setting is untouched
    }

    // 2. Commit the pointer via CAS (with idempotent-retry + readback
    //    reconciliation inside the repository).
    final result = await widget.repository!.save(
      path: objectKey,
      enabled: true,
      expectedVersion: settings.version,
    );
    if (!mounted) return;
    final previousPath = settings.path;
    final authoritativePath = result.settings?.path;

    switch (result.status) {
      case RestaurantLogoWriteStatus.ok:
        // WE committed: refresh, then best-effort delete the PREVIOUS object.
        await _applyAuthoritative(result.settings);
        var cleanupFailed = false;
        if (previousPath != null && previousPath != objectKey) {
          cleanupFailed = !await _bestEffortRemove(previousPath);
        }
        _finish(
          cleanupFailed ? l10n.brandingCleanupWarning : l10n.brandingSaved,
          isError: false,
        );
        return;
      case RestaurantLogoWriteStatus.uncertain:
        // §7.D: outcome unknown — delete NOTHING (an orphan is safer than
        // deleting an authoritative object); refresh + ask to retry.
        await _applyAuthoritative(result.settings);
        _finish(l10n.brandingErrorUncertain, isError: true);
        return;
      case RestaurantLogoWriteStatus.conflict:
        // Someone else won: delete OUR orphan ONLY if it is not the
        // authoritative path (never delete another user's object).
        if (authoritativePath != objectKey) {
          await _bestEffortRemove(objectKey);
        }
        await _applyAuthoritative(result.settings);
        _finish(l10n.brandingErrorConflict, isError: true);
        return;
      case RestaurantLogoWriteStatus.notCommitted:
      case RestaurantLogoWriteStatus.denied:
      case RestaurantLogoWriteStatus.invalid:
      case RestaurantLogoWriteStatus.unavailable:
      case RestaurantLogoWriteStatus.storageFailure:
        // The write did NOT commit: delete OUR just-uploaded orphan, keep old.
        await _bestEffortRemove(objectKey);
        await _applyAuthoritative(result.settings);
        _finish(_messageForWriteStatus(result.status, l10n), isError: true);
        return;
    }
  }

  Future<void> _onRemove() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final settings = _settings;
    if (settings == null || !settings.hasLogo) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        key: const Key('branding-remove-confirm'),
        title: Text(l10n.brandingRemoveConfirmTitle),
        content: Text(l10n.brandingRemoveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            key: const Key('branding-remove-confirm-action'),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(l10n.brandingRemoveAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final previousPath = settings.path;
    final result = await widget.repository!.save(
      path: null,
      enabled: false,
      expectedVersion: settings.version,
    );
    if (!mounted) return;
    // The OLD object is deleted ONLY when removal is CONFIRMED committed. For
    // notCommitted / conflict / uncertain the logo may still be authoritative,
    // so the old object is KEPT (never deleted on an ambiguous outcome). §8.
    await _applyAuthoritative(result.settings);
    if (result.status == RestaurantLogoWriteStatus.ok) {
      if (previousPath != null) await _bestEffortRemove(previousPath);
      _finish(l10n.brandingRemoved, isError: false);
      return;
    }
    _finish(_messageForWriteStatus(result.status, l10n), isError: true);
  }

  Future<void> _onToggle(bool value) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final settings = _settings;
    if (settings == null || !settings.hasLogo) return;
    setState(() => _busy = true);
    final result = await widget.repository!.save(
      path: settings.path,
      enabled: value,
      expectedVersion: settings.version,
    );
    if (!mounted) return;
    // A toggle mutates no storage object — just reconcile to the authoritative
    // state and report the outcome (uncertain => refresh + retry hint). §8.
    await _applyAuthoritative(result.settings);
    if (result.status == RestaurantLogoWriteStatus.ok) {
      _finish(null, isError: false);
      return;
    }
    _finish(_messageForWriteStatus(result.status, l10n), isError: true);
  }

  /// Clear the busy/pick state and (optionally) set a status message.
  void _finish(String? message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _picked = null;
      _busy = false;
    });
    if (message != null) _setMessage(message, isError: isError);
  }

  String _messageForWriteStatus(
    RestaurantLogoWriteStatus status,
    AppLocalizations l10n,
  ) => switch (status) {
    RestaurantLogoWriteStatus.conflict => l10n.brandingErrorConflict,
    RestaurantLogoWriteStatus.denied => l10n.brandingErrorDenied,
    RestaurantLogoWriteStatus.invalid => l10n.brandingErrorInvalidType,
    RestaurantLogoWriteStatus.uncertain => l10n.brandingErrorUncertain,
    RestaurantLogoWriteStatus.storageFailure => l10n.brandingErrorUploadFailed,
    RestaurantLogoWriteStatus.notCommitted ||
    RestaurantLogoWriteStatus.unavailable => l10n.brandingErrorSaveFailed,
    RestaurantLogoWriteStatus.ok => l10n.brandingSaved,
  };

  Future<void> _applyAuthoritative(RestaurantLogoSettings? settings) async {
    if (settings == null) return;
    Uri? url;
    if (settings.hasLogo) {
      try {
        // A saved logo always lands on a NEW versioned path, so this resolves
        // a fresh URL; an unchanged path reuses the cached one.
        url = await signedUrlCacheFor(widget.storage!).resolve(
          settings.path!,
          validity: kSignedUrlValidity,
          sign: () => widget.storage!.createSignedUrl(
            settings.path!,
            expiresIn: kSignedUrlValidity,
          ),
        );
      } catch (_) {
        url = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _currentUrl = url;
    });
  }

  Future<bool> _bestEffortRemove(String path) async {
    try {
      await widget.storage!.remove(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _setMessage(String message, {required bool isError}) {
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  String _messageForValidation(LogoValidationError e, AppLocalizations l10n) {
    return switch (e) {
      LogoValidationError.emptyFile ||
      LogoValidationError.unsupportedFormat => l10n.brandingErrorInvalidType,
      LogoValidationError.tooLarge => l10n.brandingErrorTooLarge,
      LogoValidationError.decodeFailed => l10n.brandingErrorCorrupt,
      LogoValidationError.dimensionTooLarge ||
      LogoValidationError.tooManyPixels => l10n.brandingErrorDimensions,
      LogoValidationError.tooSmall => l10n.brandingErrorTooSmall,
      LogoValidationError.extremeAspectRatio => l10n.brandingErrorAspect,
      LogoValidationError.transparentImage => l10n.brandingErrorTransparent,
      LogoValidationError.blankImage => l10n.brandingErrorBlank,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AdminSectionCard(
      title: l10n.brandingSectionTitle,
      icon: Icons.image_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.brandingSectionSubtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: RestoflowSpacing.md),
          if (!_wired)
            Text(
              widget.isDemo ? l10n.brandingDemoNote : l10n.brandingUnavailable,
              key: const Key('branding-unavailable'),
              style: theme.textTheme.bodyMedium,
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.all(RestoflowSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_readFailed)
            Text(
              l10n.brandingErrorSaveFailed,
              style: theme.textTheme.bodyMedium,
            )
          else
            ..._editor(l10n, theme),
        ],
      ),
    );
  }

  List<Widget> _editor(AppLocalizations l10n, ThemeData theme) {
    final settings = _settings;
    final picked = _picked;
    return [
      // Preview: the locally-picked image (before save), else the current logo.
      _preview(l10n, theme, picked, settings),
      const SizedBox(height: RestoflowSpacing.md),
      // §10/§11: a covering NON-manager (branch-only manager / cashier /
      // accountant) sees the current logo READ-ONLY — no management controls.
      if (!_canManage)
        Text(
          l10n.brandingReadOnlyNote,
          key: const Key('branding-readonly'),
          style: theme.textTheme.bodySmall,
        ),
      if (_canManage) ...[
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.sm,
          children: [
            FilledButton.tonalIcon(
              key: const Key('branding-pick'),
              onPressed: (_busy || !_pickerSupported) ? null : _onPick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                (settings?.hasLogo ?? false)
                    ? l10n.brandingReplaceAction
                    : l10n.brandingUploadAction,
              ),
            ),
            if (picked != null)
              FilledButton.icon(
                key: const Key('branding-save'),
                onPressed: _busy ? null : _onSave,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(l10n.brandingSaveAction),
              ),
            if ((settings?.hasLogo ?? false) && picked == null)
              TextButton.icon(
                key: const Key('branding-remove'),
                onPressed: _busy ? null : _onRemove,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.brandingRemoveAction),
              ),
          ],
        ),
        if (!_pickerSupported)
          Padding(
            padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
            child: Text(
              l10n.brandingPickerUnsupported,
              style: theme.textTheme.bodySmall,
            ),
          ),
        if ((settings?.hasLogo ?? false) && picked == null)
          SwitchListTile(
            key: const Key('branding-enable'),
            contentPadding: EdgeInsets.zero,
            value: settings!.enabled,
            onChanged: _busy ? null : _onToggle,
            title: Text(l10n.brandingEnableToggle),
          ),
      ],
      if (_canManage)
        Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
          child: Text(
            l10n.brandingFormatsHint,
            style: theme.textTheme.labelSmall,
          ),
        ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.only(top: RestoflowSpacing.sm),
          child: LinearProgressIndicator(),
        ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
          child: Text(
            _message!,
            key: const Key('branding-message'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _messageIsError
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
        ),
    ];
  }

  Widget _preview(
    AppLocalizations l10n,
    ThemeData theme,
    PickedMenuImage? picked,
    RestaurantLogoSettings? settings,
  ) {
    Widget frame(Widget child, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: RestoflowSpacing.xs),
        Container(
          constraints: const BoxConstraints(maxWidth: 200, maxHeight: 120),
          padding: const EdgeInsets.all(RestoflowSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(RestoflowRadii.sm),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: child,
        ),
      ],
    );
    if (picked != null) {
      return frame(
        Image.memory(
          picked.bytes,
          key: const Key('branding-preview-picked'),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        l10n.brandingPreviewLabel,
      );
    }
    final url = _currentUrl;
    if ((settings?.hasLogo ?? false) && url != null) {
      return frame(
        Image.network(
          url.toString(),
          key: const Key('branding-preview-current'),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Text(l10n.brandingNoLogo),
        ),
        l10n.brandingCurrentLabel,
      );
    }
    return Text(l10n.brandingNoLogo, style: theme.textTheme.bodyMedium);
  }
}
