import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_copy.dart';
import 'storefront_media_publisher.dart';
import 'storefront_media_repository.dart';
import 'storefront_models.dart';
import 'storefront_profile_repository.dart';
import 'storefront_sources.dart';

/// Assigns (or, with a null [mediaId], clears) a storefront slot through the
/// profile CAS writer, then refreshes the authoritative profile + media list.
/// [reReadFirst]: re-read the profile BEFORE writing (the publish function
/// already moved a pointer server-side — `profile_version != null`).
/// [replay]: "Try again" after an UNKNOWN outcome — the write is re-sent as
/// THE SAME request (same idempotency key, same expected version), so a write
/// that did commit is answered from the server ledger instead of being
/// refused as a stale-version conflict.
typedef StorefrontSlotAssigner =
    Future<StorefrontWriteResult> Function(
      StorefrontSlot slot,
      String? mediaId, {
      required bool reReadFirst,
      StorefrontSlotReplay? replay,
    });

/// One slot assignment to re-send verbatim after an unknown outcome.
class StorefrontSlotReplay {
  const StorefrontSlotReplay({
    required this.requestId,
    required this.expectedVersion,
  });

  /// The idempotency key of the ORIGINAL write.
  final String requestId;

  /// The expected version the original write was sent with.
  final int expectedVersion;
}

/// Re-reads the authoritative profile + media list (and, when
/// [reloadSources], the candidate sources).
typedef StorefrontRefresher = Future<void> Function({bool reloadSources});

/// C12 (CRIT-2): a receipt logo the publish function REFUSED for the logo
/// slot — a typed, deterministic `422 refused` of that exact original (recipe
/// `storefront-media-c4`: PNG / JPEG / WebP only, decoded raster at most
/// 8 MiP = 8,388,608 px, each side at most 8192 px, aspect at most 8:1).
/// Receipt-logo keys are unique per upload, so the SAME key is the same
/// refused image; a replaced receipt logo is a new key.
class StorefrontRefusedSource {
  const StorefrontRefusedSource({required this.key, required this.code});

  /// The refused receipt logo's private object key.
  final String key;

  /// The typed refusal code (e.g. `too_many_pixels`, `aspect_ratio`).
  final String code;
}

/// Re-reads the candidate sources NOW (the section shows the fresh list too)
/// and answers them.
typedef StorefrontSourceReloader = Future<StorefrontSourceOptions> Function();

/// The idempotency-key namespace of one logical publish (reused across the
/// function's rungs and its one retry; "Try again" after an unknown outcome
/// reuses it too).
const String kStorefrontPublishRequestPrefix = 'pbl:storefront-publish:';

/// STOREFRONT-PUBLISH-001 — one storefront media slot (logo | hero).
///
/// Shows the CURRENT published derivative (public preview of its
/// `object_key`), a source picker (logo: ONLY the current receipt logo; hero:
/// the receipt logo or a menu item's original), "Publish" (the Edge Function
/// derives + publishes; then the slot is assigned through the profile CAS
/// writer), "Remove from storefront" (clears the pointer; the row stays LIVE),
/// and the slot's media rows with "Use here" / "Retract" for LIVE rows and
/// "Discard" for STAGED rows. Every outcome is typed and honest; an unknown
/// outcome refreshes the server state and offers "Try again" with the SAME
/// request. The Dashboard never encodes or uploads an image itself.
class StorefrontMediaSlot extends StatefulWidget {
  const StorefrontMediaSlot({
    required this.slot,
    required this.profile,
    required this.media,
    required this.sources,
    required this.publisher,
    required this.mediaRepository,
    required this.onAssign,
    required this.onRefresh,
    required this.reloadSources,
    this.onBusyChanged,
    this.publicUrlFor,
    this.enabled = true,
    this.nonce,
    this.refusedReceiptLogo,
    this.onReceiptLogoRefused,
    super.key,
  });

  final StorefrontSlot slot;

  /// C12: the receipt logo the function refused for the LOGO slot (held by
  /// the section). While the current receipt logo is that key, the logo
  /// slot's Publish stays disabled and a note says how to fix it (replace the
  /// receipt logo in Branding). Ignored by the hero slot.
  final StorefrontRefusedSource? refusedReceiptLogo;

  /// Told when the function refuses the receipt logo for the logo slot.
  final ValueChanged<StorefrontRefusedSource>? onReceiptLogoRefused;

  /// The SAVED profile (the slot exists only once the profile does).
  final StorefrontProfile profile;

  /// The server's media list (null while loading).
  final StorefrontMediaList? media;

  /// The candidate sources (null while loading).
  final StorefrontSourceOptions? sources;
  final StorefrontMediaPublisher publisher;
  final StorefrontMediaRepository mediaRepository;
  final StorefrontSlotAssigner onAssign;
  final StorefrontRefresher onRefresh;

  /// Confirms, when Publish is pressed, that a receipt-logo source is still
  /// the CURRENT receipt logo (it may have been replaced meanwhile, e.g. in
  /// the Branding card of the same page).
  final StorefrontSourceReloader reloadSources;

  /// Told when this slot starts / stops a server action (the section locks
  /// its form meanwhile, so a refresh never overwrites in-flight edits).
  final ValueChanged<bool>? onBusyChanged;

  /// The public URL of a derivative (null = no preview).
  final Uri Function(String objectKey)? publicUrlFor;

  /// False while the form has unsaved edits or another action runs.
  final bool enabled;

  /// Request-id nonce seam (default: microseconds).
  final int Function()? nonce;

  @override
  State<StorefrontMediaSlot> createState() => _StorefrontMediaSlotState();
}

class _SourceChoice {
  const _SourceChoice(this.id, this.label, this.source);

  final String id;
  final String label;
  final StorefrontMediaSource source;
}

class _StorefrontMediaSlotState extends State<StorefrontMediaSlot> {
  String? _selectedId;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  /// The blocker codes of a `publish_precondition` refusal (shown under the
  /// message, each saying where to fix it).
  List<String> _blockers = const <String>[];

  /// "Try again" for an UNKNOWN outcome: replays the SAME request.
  Future<void> Function()? _retry;

  String get _slotKey => widget.slot.wire;

  int _nonce() => widget.nonce?.call() ?? DateTime.now().microsecondsSinceEpoch;

  List<_SourceChoice> _choices(AppLocalizations l10n) {
    final sources = widget.sources;
    if (sources == null) return const [];
    final out = <_SourceChoice>[];
    final logo = sources.receiptLogoKey;
    if (logo != null) {
      out.add(
        _SourceChoice(
          'logo|$logo',
          l10n.storefrontSourceReceiptLogo,
          StorefrontMediaSource.receiptLogo(logo),
        ),
      );
    }
    if (widget.slot.allowedBuckets.contains(
      StorefrontSourceBucket.menuImages,
    )) {
      for (final item in sources.menuImages) {
        out.add(
          _SourceChoice(
            'menu|${item.imageKey}',
            l10n.storefrontSourceMenuItem(item.itemName),
            StorefrontMediaSource.menuImage(item.imageKey),
          ),
        );
      }
    }
    return out;
  }

  _SourceChoice? _selected(List<_SourceChoice> choices) {
    if (choices.isEmpty) return null;
    for (final c in choices) {
      if (c.id == _selectedId) return c;
    }
    return choices.first;
  }

  void _setBusy(bool busy) {
    if (!mounted) return;
    setState(() => _busy = busy);
    widget.onBusyChanged?.call(busy);
  }

  /// An action ended after this slot was removed: release the section's form
  /// lock anyway (it is asynchronous here, never during a build).
  void _releaseUnmounted() => widget.onBusyChanged?.call(false);

  void _finish(
    String? message, {
    bool isError = false,
    Future<void> Function()? retry,
    List<String> blockers = const <String>[],
  }) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _messageIsError = isError;
      _retry = retry;
      _blockers = blockers;
    });
    widget.onBusyChanged?.call(false);
  }

  Future<bool> _confirm({
    required Key key,
    required String title,
    required String body,
    required String action,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        key: key,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            key: Key('${(key as ValueKey<String>).value}-action'),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  // ---------------------------------------------------------------------------
  // Publish -> assign
  // ---------------------------------------------------------------------------

  Future<void> _onPublish(StorefrontMediaSource source) async {
    if (_busy || !widget.enabled) return;
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      key: Key('storefront-slot-$_slotKey-publish-confirm'),
      title: l10n.storefrontSlotPublishConfirmTitle,
      body: l10n.storefrontSlotPublishConfirmBody,
      action: l10n.storefrontSlotPublishAction,
    );
    if (!ok) return;
    // ONE request id per logical publish (a deliberate press = a new one).
    final requestId = storefrontRequestId(kStorefrontPublishRequestPrefix, [
      widget.publisher.organizationId,
      widget.publisher.restaurantId,
      widget.slot.wire,
      source.bucket.wire,
      source.key,
    ], _nonce());
    await _runPublish(source, requestId);
  }

  Future<void> _runPublish(
    StorefrontMediaSource source,
    String requestId,
  ) async {
    final l10n = AppLocalizations.of(context);
    _setBusy(true);
    setState(() {
      _message = l10n.storefrontSlotPublishing;
      _messageIsError = false;
      _retry = null;
      _blockers = const <String>[];
    });
    if (source.bucket == StorefrontSourceBucket.restaurantLogos) {
      // Publish ONLY the CURRENT receipt logo: the list was loaded earlier,
      // and the logo may have been replaced since (the Branding card on this
      // page, or another device). Re-read it now; on any difference publish
      // nothing — the fresh list is shown for the next press.
      final fresh = await widget.reloadSources();
      if (!mounted) {
        _releaseUnmounted();
        return;
      }
      if (fresh.receiptLogoKey != source.key) {
        final unverified = fresh.receiptLogoUnavailable;
        // Removed: there is nothing to press "Publish image" on again.
        final removed = !unverified && fresh.receiptLogoKey == null;
        _finish(
          unverified
              ? l10n.storefrontSourceLogoUnverified
              : removed
              ? l10n.storefrontSourceLogoRemoved
              : l10n.storefrontSourceLogoChanged,
          isError: true,
          // Unverified: "Try again" re-runs THIS request once the check can
          // be made. Changed: the source is stale; the next press is new.
          retry: unverified ? () => _runPublish(source, requestId) : null,
        );
        return;
      }
    }
    final result = await widget.publisher.publish(
      slot: widget.slot,
      source: source,
      requestId: requestId,
    );
    if (!mounted) {
      _releaseUnmounted();
      return;
    }
    switch (result.status) {
      case StorefrontPublishStatus.published:
        final media = result.media!;
        await _assign(
          media.id,
          reReadFirst: result.profileVersion != null,
          afterPublish: true,
        );
        return;
      case StorefrontPublishStatus.uncertain:
        // Outcome UNKNOWN: show the server's current state, and let "Try
        // again" replay the SAME request (same id, same source).
        await widget.onRefresh();
        _finish(
          l10n.storefrontMediaUncertain,
          isError: true,
          retry: () => _runPublish(source, requestId),
        );
        return;
      case StorefrontPublishStatus.restartRequired:
        // The request cannot continue (the original changed, or its pending
        // copy was discarded meanwhile): the next press starts over with a
        // NEW id. The stage step may have run: show the server's state.
        await widget.onRefresh(reloadSources: true);
        _finish(l10n.storefrontPublishRestart, isError: true);
        return;
      case StorefrontPublishStatus.sourceMissing:
        await widget.onRefresh(reloadSources: true);
        _finish(l10n.storefrontPublishSourceMissing, isError: true);
        return;
      case StorefrontPublishStatus.refused:
        // Refused while deriving, before anything was registered.
        final code = result.refusalCode ?? 'unknown';
        if (widget.slot == StorefrontSlot.logo &&
            source.bucket == StorefrontSourceBucket.restaurantLogos) {
          // C12 (CRIT-2): the logo's ONLY source is the current receipt
          // logo, so "pick another source" would be a dead end. Remember the
          // refused key (Publish stays disabled for it) and let the
          // persistent note name the remedy: replace the receipt logo in
          // Branding — which also changes printed receipts.
          final remember = widget.onReceiptLogoRefused;
          final refused = StorefrontRefusedSource(key: source.key, code: code);
          if (remember != null) {
            remember(refused);
            _finish(null, isError: true);
          } else {
            _finish(
              l10n.storefrontLogoSourceRefused(_refusalMessage(l10n, code)),
              isError: true,
            );
          }
          return;
        }
        _finish(
          '${_refusalMessage(l10n, result.refusalCode)} '
          '${l10n.storefrontRefusalPickAnother}',
          isError: true,
        );
        return;
      // These may arrive AFTER the stage step registered a STAGED row
      // (finalize / upload refusals): show the server's current state so such
      // a row can be seen and discarded — never claim that nothing changed.
      case StorefrontPublishStatus.denied:
        await widget.onRefresh();
        _finish(l10n.storefrontPublishDenied, isError: true);
        return;
      case StorefrontPublishStatus.unauthenticated:
        await widget.onRefresh();
        _finish(l10n.storefrontPublishUnauthenticated, isError: true);
        return;
      case StorefrontPublishStatus.objectConflict:
        await widget.onRefresh();
        _finish(l10n.storefrontPublishObjectConflict, isError: true);
        return;
      case StorefrontPublishStatus.serviceUnavailable:
        await widget.onRefresh();
        _finish(l10n.storefrontPublishServiceUnavailable, isError: true);
        return;
      case StorefrontPublishStatus.invalidRequest:
        _finish(l10n.storefrontPublishInvalidRequest, isError: true);
        return;
    }
  }

  /// Points the slot at [mediaId] (null = remove from the storefront) via the
  /// section's CAS writer; the section re-reads afterwards. [replay] re-sends
  /// an earlier write whose outcome is unknown AS THE SAME REQUEST.
  Future<void> _assign(
    String? mediaId, {
    bool reReadFirst = false,
    bool afterPublish = false,
    StorefrontSlotReplay? replay,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (!_busy) _setBusy(true);
    final write = await widget.onAssign(
      widget.slot,
      mediaId,
      reReadFirst: reReadFirst,
      replay: replay,
    );
    if (!mounted) {
      _releaseUnmounted();
      return;
    }
    final okMessage = mediaId == null
        ? l10n.storefrontSlotRemoved
        : (afterPublish
              ? l10n.storefrontSlotPublished
              : l10n.storefrontSlotAssigned);
    switch (write.status) {
      case StorefrontWriteStatus.ok:
        _finish(okMessage);
      case StorefrontWriteStatus.conflict:
        _finish(
          afterPublish
              ? l10n.storefrontSlotNotPlaced
              : l10n.storefrontErrorConflict,
          isError: true,
        );
      case StorefrontWriteStatus.uncertain:
        // "Try again" re-reads, skips the write when the authoritative
        // profile already points at [mediaId], and otherwise re-sends THE
        // SAME request (same id + expected version): a write that did commit
        // is replayed by the server ledger, never refused as a conflict.
        final id = write.requestId;
        final sentWith = write.expectedVersion;
        final next = id != null && sentWith != null
            ? StorefrontSlotReplay(requestId: id, expectedVersion: sentWith)
            : replay;
        _finish(
          l10n.storefrontErrorUncertain,
          isError: true,
          retry: () => _assign(
            mediaId,
            reReadFirst: true,
            afterPublish: afterPublish,
            replay: next,
          ),
        );
      case StorefrontWriteStatus.denied:
        _finish(l10n.storefrontErrorDenied, isError: true);
      case StorefrontWriteStatus.invalid:
        // A DETERMINISTIC refusal: say why (never "right now", never "use it
        // from the list" — that would be refused the same way). While the
        // storefront is published, the writer re-checks the publish
        // requirements on EVERY save, so a lapsed requirement (e.g. the last
        // menu item deactivated) refuses any image change until it is fixed
        // or the storefront is unpublished.
        final precondition = write.reason == 'publish_precondition';
        final why = precondition
            ? l10n.storefrontSlotPreconditionRefused
            : storefrontReasonMessage(l10n, write.reason);
        _finish(
          afterPublish ? '${l10n.storefrontSlotPublishedNotPlaced} $why' : why,
          isError: true,
          blockers: precondition ? write.blockers : const <String>[],
        );
      case StorefrontWriteStatus.unavailable:
      case StorefrontWriteStatus.notCommitted:
        _finish(
          afterPublish
              ? l10n.storefrontSlotPlaceFailed
              : l10n.storefrontErrorUnavailable,
          isError: true,
        );
    }
  }

  /// Re-reads the sources after a failed source read (keeps any message and
  /// its "Try again": the outcome it refers to is unchanged).
  Future<void> _onReloadSources() async {
    if (_busy || !widget.enabled) return;
    _setBusy(true);
    await widget.onRefresh(reloadSources: true);
    if (!mounted) {
      _releaseUnmounted();
      return;
    }
    _setBusy(false);
  }

  Future<void> _onRemove() async {
    if (_busy || !widget.enabled) return;
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      key: Key('storefront-slot-$_slotKey-remove-confirm'),
      title: l10n.storefrontSlotRemoveConfirmTitle,
      body: l10n.storefrontSlotRemoveConfirmBody,
      action: l10n.storefrontSlotRemoveAction,
    );
    if (!ok) return;
    setState(() => _retry = null);
    await _assign(null);
  }

  Future<void> _onUse(StorefrontMediaRow row) async {
    if (_busy || !widget.enabled) return;
    setState(() => _retry = null);
    await _assign(row.id);
  }

  // ---------------------------------------------------------------------------
  // Retract / discard
  // ---------------------------------------------------------------------------

  Future<void> _onRetract(StorefrontMediaRow row) async {
    if (_busy || !widget.enabled) return;
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      key: Key('storefront-media-retract-confirm-${row.id}'),
      title: l10n.storefrontMediaRetractConfirmTitle,
      body: l10n.storefrontMediaRetractConfirmBody,
      action: l10n.storefrontMediaRetractAction,
    );
    if (!ok) return;
    await _runAction(row.id, retract: true);
  }

  Future<void> _onDiscard(StorefrontMediaRow row) async {
    if (_busy || !widget.enabled) return;
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      key: Key('storefront-media-discard-confirm-${row.id}'),
      title: l10n.storefrontMediaDiscardConfirmTitle,
      body: l10n.storefrontMediaDiscardConfirmBody,
      action: l10n.storefrontMediaDiscardAction,
    );
    if (!ok) return;
    await _runAction(row.id, retract: false);
  }

  Future<void> _runAction(
    String mediaId, {
    required bool retract,
    String? requestId,
  }) async {
    final l10n = AppLocalizations.of(context);
    _setBusy(true);
    setState(() {
      _message = null;
      _retry = null;
      _blockers = const <String>[];
    });
    final repo = widget.mediaRepository;
    final r = retract
        ? await repo.retract(mediaId, requestId: requestId)
        : await repo.cancel(mediaId, requestId: requestId);
    if (!mounted) {
      _releaseUnmounted();
      return;
    }
    switch (r.status) {
      case StorefrontMediaActionStatus.ok:
        await widget.onRefresh();
        _finish(
          retract
              ? l10n.storefrontMediaRetracted
              : l10n.storefrontMediaDiscarded,
        );
      case StorefrontMediaActionStatus.mediaInUse:
        await widget.onRefresh();
        _finish(
          l10n.storefrontMediaInUseError(
            r.slots.map((s) => _slotTitle(l10n, s)).join(' / '),
          ),
          isError: true,
        );
      case StorefrontMediaActionStatus.mediaNotPublished:
        await widget.onRefresh();
        _finish(l10n.storefrontMediaNotPublishedError, isError: true);
      case StorefrontMediaActionStatus.mediaPublished:
        await widget.onRefresh();
        _finish(l10n.storefrontMediaPublishedError, isError: true);
      case StorefrontMediaActionStatus.notFound:
        await widget.onRefresh();
        _finish(l10n.storefrontMediaNotFoundError, isError: true);
      case StorefrontMediaActionStatus.staleRequest:
        // DB-4: a replay of THIS request found the row changed since (e.g.
        // re-published after the retract). Never claim "retracted": show the
        // server's current state instead.
        await widget.onRefresh();
        _finish(l10n.storefrontMediaStaleRequest, isError: true);
      case StorefrontMediaActionStatus.denied:
        _finish(l10n.storefrontMediaDeniedError, isError: true);
      case StorefrontMediaActionStatus.unavailable:
        _finish(l10n.storefrontMediaUnavailableError, isError: true);
      case StorefrontMediaActionStatus.uncertain:
        // Show the server's current state; "Try again" replays the SAME id.
        await widget.onRefresh();
        _finish(
          l10n.storefrontMediaUncertain,
          isError: true,
          retry: () =>
              _runAction(mediaId, retract: retract, requestId: r.requestId),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  static String _slotTitle(AppLocalizations l10n, StorefrontSlot slot) =>
      switch (slot) {
        StorefrontSlot.logo => l10n.storefrontSlotLogoTitle,
        StorefrontSlot.hero => l10n.storefrontSlotHeroTitle,
      };

  /// The rows this slot manages: its own variant, plus any row the slot
  /// points at (a content-addressed publish may return a row of the other
  /// variant when the derivatives are byte-identical).
  List<StorefrontMediaRow> _rows() {
    final list = widget.media;
    if (list == null || !list.isOk) return const [];
    final current = widget.profile.mediaIdFor(widget.slot)?.toLowerCase();
    return [
      for (final row in list.media)
        if (row.variant == widget.slot.variant ||
            row.inUse.contains(widget.slot) ||
            row.id.toLowerCase() == current)
          row,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final active = widget.enabled && !_busy;
    final choices = _choices(l10n);
    final selected = _selected(choices);
    final currentId = widget.profile.mediaIdFor(widget.slot);
    final currentRow = currentId == null ? null : widget.media?.byId(currentId);
    final sources = widget.sources;
    // A failed source read is NOT "no source": never say "upload first" /
    // "none yet" then — say it could not be loaded, and offer a retry.
    final sourcesFailed =
        sources != null &&
        (sources.receiptLogoUnavailable ||
            (widget.slot == StorefrontSlot.hero &&
                sources.menuImagesUnavailable));
    // C12 (CRIT-2): the function refused THIS receipt logo for the logo slot
    // (deterministically): Publish stays disabled for it until the receipt
    // logo is replaced (a new key), and the note says how.
    final refused = widget.slot == StorefrontSlot.logo
        ? widget.refusedReceiptLogo
        : null;
    final refusedHere =
        refused != null &&
        selected != null &&
        selected.source.bucket == StorefrontSourceBucket.restaurantLogos &&
        selected.source.key == refused.key;
    return Container(
      key: Key('storefront-slot-$_slotKey'),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _slotTitle(l10n, widget.slot),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: RestoflowSpacing.xxs),
          Text(
            widget.slot == StorefrontSlot.logo
                ? l10n.storefrontSlotLogoHelp
                : l10n.storefrontSlotHeroHelp,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          // The CURRENT published derivative.
          if (currentId == null)
            Text(
              l10n.storefrontSlotEmpty,
              key: Key('storefront-slot-$_slotKey-empty'),
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            Text(
              l10n.storefrontSlotCurrentLabel,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            _preview(l10n, theme, currentRow),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: Key('storefront-slot-$_slotKey-remove'),
                onPressed: active ? _onRemove : null,
                icon: const Icon(Icons.hide_image_outlined),
                label: Text(l10n.storefrontSlotRemoveAction),
              ),
            ),
          ],
          const SizedBox(height: RestoflowSpacing.sm),
          // The source picker.
          if (sources == null)
            const LinearProgressIndicator()
          else if (choices.isEmpty && !sourcesFailed)
            Text(
              widget.slot == StorefrontSlot.logo
                  ? l10n.storefrontSourceNoReceiptLogo
                  : l10n.storefrontSourceNone,
              key: Key('storefront-slot-$_slotKey-no-source'),
              style: theme.textTheme.bodySmall,
            )
          else if (choices.isNotEmpty)
            // Controlled (not a FormField): a sources reload can never leave
            // a stale selection behind.
            InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.storefrontSlotSourceLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: Key('storefront-slot-$_slotKey-source'),
                  value: selected?.id,
                  isExpanded: true,
                  isDense: true,
                  items: [
                    for (final c in choices)
                      DropdownMenuItem<String>(
                        value: c.id,
                        child: Text(c.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: active
                      ? (id) => setState(() => _selectedId = id)
                      : null,
                ),
              ),
            ),
          if (sourcesFailed)
            Padding(
              padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
              child: Wrap(
                spacing: RestoflowSpacing.sm,
                runSpacing: RestoflowSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.storefrontSourcesUnavailable,
                    key: Key('storefront-slot-$_slotKey-sources-unavailable'),
                    style: theme.textTheme.bodySmall,
                  ),
                  TextButton.icon(
                    key: Key('storefront-slot-$_slotKey-sources-retry'),
                    onPressed: active ? _onReloadSources : null,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.storefrontRetry),
                  ),
                ],
              ),
            ),
          const SizedBox(height: RestoflowSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: Key('storefront-slot-$_slotKey-publish'),
              onPressed: active && selected != null && !refusedHere
                  ? () => _onPublish(selected.source)
                  : null,
              icon: const Icon(Icons.publish_outlined),
              label: Text(l10n.storefrontSlotPublishAction),
            ),
          ),
          if (refusedHere) ...[
            Padding(
              padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
              child: Text(
                l10n.storefrontLogoSourceRefused(
                  _refusalMessage(l10n, refused.code),
                ),
                key: Key('storefront-slot-$_slotKey-refused'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            // After replacing the receipt logo in Branding (same page), re-read
            // it: a new key lifts the block; the same key keeps it.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: Key('storefront-slot-$_slotKey-recheck'),
                onPressed: active ? _onReloadSources : null,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.storefrontLogoRecheckAction),
              ),
            ),
          ],
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
                key: Key('storefront-slot-$_slotKey-message'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _messageIsError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          for (final code in _blockers)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: RestoflowSpacing.md,
                top: RestoflowSpacing.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.block, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      storefrontBlockerLabel(l10n, code),
                      key: Key('storefront-slot-$_slotKey-blocker-$code'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          if (_retry != null && !_busy)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: Key('storefront-slot-$_slotKey-retry'),
                onPressed: widget.enabled ? () => _retry?.call() : null,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.storefrontRetry),
              ),
            ),
          const Divider(height: RestoflowSpacing.xl),
          _mediaList(l10n, theme, active),
        ],
      ),
    );
  }

  Widget _preview(
    AppLocalizations l10n,
    ThemeData theme,
    StorefrontMediaRow? row,
  ) {
    final urlFor = widget.publicUrlFor;
    Widget unavailable() => Text(
      l10n.storefrontSlotPreviewUnavailable,
      key: Key('storefront-slot-$_slotKey-preview-unavailable'),
      style: theme.textTheme.bodySmall,
    );
    if (row == null || urlFor == null) return unavailable();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RestoflowRadii.sm),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          urlFor(row.objectKey).toString(),
          key: Key('storefront-slot-$_slotKey-preview'),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Padding(
            padding: const EdgeInsets.all(RestoflowSpacing.sm),
            child: unavailable(),
          ),
        ),
      ),
    );
  }

  Widget _mediaList(AppLocalizations l10n, ThemeData theme, bool active) {
    final list = widget.media;
    final rows = _rows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.storefrontMediaListTitle, style: theme.textTheme.labelLarge),
        const SizedBox(height: RestoflowSpacing.xs),
        if (list == null)
          const LinearProgressIndicator()
        else if (!list.isOk)
          Text(
            l10n.storefrontMediaListUnavailable,
            key: Key('storefront-slot-$_slotKey-list-unavailable'),
            style: theme.textTheme.bodySmall,
          )
        else if (rows.isEmpty)
          Text(
            l10n.storefrontMediaListEmpty,
            key: Key('storefront-slot-$_slotKey-list-empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final row in rows) _row(l10n, theme, row, active),
      ],
    );
  }

  Widget _row(
    AppLocalizations l10n,
    ThemeData theme,
    StorefrontMediaRow row,
    bool active,
  ) {
    final (stateLabel, tone) = switch (row.state) {
      StorefrontMediaState.staged => (
        l10n.storefrontMediaStateStaged,
        RestoflowTone.warning,
      ),
      StorefrontMediaState.published => (
        l10n.storefrontMediaStateLive,
        RestoflowTone.success,
      ),
      StorefrontMediaState.retracted => (
        l10n.storefrontMediaStateRetracted,
        RestoflowTone.neutral,
      ),
    };
    final style = tone.styleOf(theme);
    final inUse = row.inUse.isNotEmpty;
    final pointedHere =
        widget.profile.mediaIdFor(widget.slot)?.toLowerCase() ==
        row.id.toLowerCase();
    Widget chip(String label, RestoflowToneStyle s) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: s.container,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: s.onContainer),
      ),
    );
    return Padding(
      key: Key('storefront-media-row-${row.id}'),
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Wrap(
        spacing: RestoflowSpacing.sm,
        runSpacing: RestoflowSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip(stateLabel, style),
          if (inUse)
            chip(l10n.storefrontMediaInUse, RestoflowTone.info.styleOf(theme)),
          Text(
            l10n.storefrontMediaDimensions(row.width, row.height),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            row.sourceBucket == StorefrontSourceBucket.restaurantLogos
                ? l10n.storefrontMediaFromReceiptLogo
                : l10n.storefrontMediaFromMenuImage,
            style: theme.textTheme.bodySmall,
          ),
          if (row.isLive && !pointedHere)
            TextButton(
              key: Key('storefront-media-use-${row.id}'),
              onPressed: active ? () => _onUse(row) : null,
              child: Text(l10n.storefrontSlotUseAction),
            ),
          if (row.isLive && !inUse)
            TextButton(
              key: Key('storefront-media-retract-${row.id}'),
              onPressed: active ? () => _onRetract(row) : null,
              child: Text(l10n.storefrontMediaRetractAction),
            ),
          if (row.isLive && inUse)
            Text(
              l10n.storefrontMediaInUseNote,
              key: Key('storefront-media-in-use-note-${row.id}'),
              style: theme.textTheme.bodySmall,
            ),
          if (row.isStaged)
            TextButton(
              key: Key('storefront-media-discard-${row.id}'),
              onPressed: active ? () => _onDiscard(row) : null,
              child: Text(l10n.storefrontMediaDiscardAction),
            ),
        ],
      ),
    );
  }
}

/// The localized copy of a `422 refused` code (unknown codes fall back to a
/// generic line carrying the code).
String _refusalMessage(AppLocalizations l10n, String? code) => switch (code) {
  'unsupported_format' => l10n.storefrontRefusalUnsupportedFormat,
  'empty' => l10n.storefrontRefusalEmpty,
  'input_too_large' => l10n.storefrontRefusalInputTooLarge,
  'too_many_pixels' => l10n.storefrontRefusalTooManyPixels,
  'dimensions_too_large' => l10n.storefrontRefusalDimensionsTooLarge,
  'aspect_ratio' => l10n.storefrontRefusalAspectRatio,
  'animated' => l10n.storefrontRefusalAnimated,
  'truncated' => l10n.storefrontRefusalTruncated,
  'corrupt' => l10n.storefrontRefusalCorrupt,
  'metadata_too_large' => l10n.storefrontRefusalMetadataTooLarge,
  'too_many_scans' => l10n.storefrontRefusalTooManyScans,
  'decode_failed' => l10n.storefrontRefusalDecodeFailed,
  'decode_warning' => l10n.storefrontRefusalDecodeWarning,
  'output_too_large' => l10n.storefrontRefusalOutputTooLarge,
  'self_check_failed' => l10n.storefrontRefusalSelfCheckFailed,
  _ => l10n.storefrontRefusalUnknown(code ?? '-'),
};

/// Exposed for tests: the refusal copy of [code].
@visibleForTesting
String storefrontRefusalMessage(AppLocalizations l10n, String? code) =>
    _refusalMessage(l10n, code);
