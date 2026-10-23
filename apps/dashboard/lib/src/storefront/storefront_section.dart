import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminSectionCard;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'opening_hours_editor.dart';
import 'storefront_contrast.dart';
import 'storefront_content_models.dart';
import 'storefront_content_repository.dart';
import 'storefront_content_section.dart';
import 'storefront_copy.dart';
import 'storefront_featured_items.dart';
import 'storefront_item_images.dart';
import 'storefront_media_publisher.dart';
import 'storefront_media_repository.dart';
import 'storefront_media_slot.dart';
import 'storefront_models.dart';
import 'storefront_profile_repository.dart';
import 'storefront_sources.dart';

/// STOREFRONT-PUBLISH-001 — everything the Settings "Storefront" card talks
/// to, built per membership in the dashboard shell (null = not wired: demo
/// mode / no authenticated transport / no concrete restaurant).
class StorefrontEditorSeams {
  const StorefrontEditorSeams({
    required this.scopeIdentity,
    required this.profileRepository,
    required this.mediaRepository,
    required this.branchSource,
    required this.sourceCatalog,
    this.featuredCatalog,
    StorefrontContentRepository? contentRepository,
    StorefrontContentCatalog? contentCatalog,
    this.publisher,
    this.publicUrlFor,
  }) : _contentRepository = contentRepository,
       _contentCatalog = contentCatalog;

  /// WHO this editor works for — the membership, organization, restaurant
  /// (and role) the repositories below were built for. The card's draft,
  /// its pending same-request "Try again" handles and its remembered
  /// refusals belong to THIS identity: a different identity is a different
  /// editor that starts from a fresh read, never showing the previous
  /// tenant's / restaurant's / membership's draft.
  final String scopeIdentity;

  final StorefrontProfileRepository profileRepository;
  final StorefrontMediaRepository mediaRepository;
  final StorefrontBranchSource branchSource;
  final StorefrontSourceCatalog sourceCatalog;
  final StorefrontFeaturedCatalog? featuredCatalog;
  final StorefrontContentRepository? _contentRepository;
  final StorefrontContentCatalog? _contentCatalog;
  StorefrontContentRepository? get contentRepository =>
      _contentRepository ??
      (profileRepository is StorefrontContentRepositoryBinding
          ? (profileRepository as StorefrontContentRepositoryBinding)
                .contentRepository
          : null);
  StorefrontContentCatalog? get contentCatalog =>
      _contentCatalog ??
      (featuredCatalog is StorefrontContentCatalog
          ? featuredCatalog as StorefrontContentCatalog
          : null);

  /// The Edge Function client (null = image publishing is not available
  /// here; the media slots then show an honest note).
  final StorefrontMediaPublisher? publisher;

  /// The public URL of a published derivative (preview only; null = none).
  final Uri Function(String objectKey)? publicUrlFor;
}

/// Picks the pause end as a LOCAL wall-clock date + time (null = dismissed).
typedef StorefrontInstantPicker =
    Future<DateTime?> Function(BuildContext context, DateTime? initial);

/// The default [StorefrontInstantPicker]: date picker, then a 24 h time
/// picker, in this device's time zone.
Future<DateTime?> showStorefrontInstantPicker(
  BuildContext context,
  DateTime? initial,
) async {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month, now.day);
  final last = DateTime(now.year + 2, 12, 31);
  var seed = (initial ?? now.add(const Duration(hours: 1))).toLocal();
  if (seed.isBefore(first)) seed = first;
  if (seed.isAfter(last)) seed = last;
  final date = await showDatePicker(
    context: context,
    initialDate: seed,
    firstDate: first,
    lastDate: last,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(seed),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// The writer's phone CHECK (E.164 `+` 7-15 digits, or the Israeli local
/// `0XX-XXX-XXXX` shape with optional `-`/space separators).
final RegExp _phoneShape = RegExp(
  r'^(\+[1-9][0-9]{6,14}|0[0-9]{1,2}[- ]?[0-9]{3}[- ]?[0-9]{4})$',
);

/// The writer's colour CHECK.
final RegExp _colorShape = RegExp(r'^#[0-9A-Fa-f]{6}$');

String _two(int n) => n.toString().padLeft(2, '0');

/// `+HH:MM` / `-HH:MM` for a UTC offset.
String _offsetText(Duration offset) {
  final abs = offset.abs();
  final sign = offset.isNegative ? '-' : '+';
  return '$sign${_two(abs.inHours)}:${_two(abs.inMinutes % 60)}';
}

/// The one `paused_until` wire form: the instant at THIS device's offset,
/// spelled out (e.g. `2026-10-01T18:00:00+03:00`).
String _wireInstant(DateTime instant) {
  try {
    return formatStorefrontInstant(
      instant,
      offset: instant.toLocal().timeZoneOffset,
    );
  } on ArgumentError {
    return formatStorefrontInstant(instant);
  }
}

String? _blankToNull(String text) {
  final t = text.trim();
  return t.isEmpty ? null : t;
}

bool _sameId(String? a, String? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.toLowerCase() == b.toLowerCase();
}

bool _sameInstant(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.isAtSameMomentAs(b);
}

/// A save to replay with the SAME request after an unknown outcome.
class _PendingSave {
  const _PendingSave({
    required this.patch,
    required this.expectedVersion,
    required this.requestId,
    required this.draftPatch,
    required this.okMessage,
  });

  final Map<String, Object?> patch;
  final int expectedVersion;
  final String? requestId;

  /// The form's diff when the save was sent: "Try again" is offered only while
  /// the form still shows exactly these edits.
  final Map<String, Object?> draftPatch;
  final String okMessage;
}

class _Banner {
  const _Banner(
    this.message,
    this.tone, {
    this.blockers = const <String>[],
    this.offerUnpublishSave = false,
    this.retry,
  });

  final String message;
  final RestoflowTone tone;
  final List<String> blockers;
  final bool offerUnpublishSave;
  final _PendingSave? retry;
}

/// STOREFRONT-PUBLISH-001 — the Settings "Storefront" card.
///
/// READ BEFORE EDIT: nothing is editable until the manager read answers ok;
/// `denied` shows an honest note and NO fields (the SERVER verdict decides —
/// D7 — never the client role); a failed read offers a retry. With no
/// profile yet the card is a create form (branch + permanent slug + display
/// name, confirmed); afterwards the slug is read-only and every field is
/// edited as a DRAFT whose Save sends ONLY the changed keys with the current
/// version (compare-and-set), then re-reads. A conflict reloads the
/// authoritative profile (never a silent merge). Publishing is an explicit,
/// confirmed action gated on the SERVER's blockers and on a saved form; the
/// published state shown is only ever the server's. There is deliberately NO
/// ordering / delivery control anywhere (browse-only release).
///
/// LIFECYCLE (DASH-1): the card is a lazy child of the Settings ListView, so
/// its editor keeps itself alive ([AutomaticKeepAliveClientMixin]) — scrolling
/// it out of view and back never discards the unsaved draft, an unknown-
/// outcome "Try again" or a remembered refusal, and never re-reads. The
/// editor is keyed by [StorefrontEditorSeams.scopeIdentity]: another
/// membership / organization / restaurant gets a NEW editor (the old one and
/// anything it still had in flight are dropped) that starts from a fresh read.
class StorefrontSection extends StatelessWidget {
  const StorefrontSection({
    required this.seams,
    this.isDemo = false,
    this.defaultDisplayName,
    this.pickPauseUntil,
    this.pickTime,
    this.pickDate,
    this.nonce,
    super.key,
  });

  final StorefrontEditorSeams? seams;
  final bool isDemo;

  /// Prefills the create form's display name (the restaurant name).
  final String? defaultDisplayName;

  /// Test seams for the pickers (default: the Material pickers).
  final StorefrontInstantPicker? pickPauseUntil;
  final StorefrontTimePicker? pickTime;
  final StorefrontDatePicker? pickDate;

  /// Request-id nonce seam for the media slots.
  final int Function()? nonce;

  @override
  Widget build(BuildContext context) => _StorefrontEditor(
    // A different identity = a different editor (fresh State, fresh read).
    key: ValueKey<String>('storefront-editor|${seams?.scopeIdentity ?? '-'}'),
    seams: seams,
    isDemo: isDemo,
    defaultDisplayName: defaultDisplayName,
    pickPauseUntil: pickPauseUntil,
    pickTime: pickTime,
    pickDate: pickDate,
    nonce: nonce,
  );
}

class _StorefrontEditor extends StatefulWidget {
  const _StorefrontEditor({
    required this.seams,
    required this.isDemo,
    required this.defaultDisplayName,
    required this.pickPauseUntil,
    required this.pickTime,
    required this.pickDate,
    required this.nonce,
    super.key,
  });

  final StorefrontEditorSeams? seams;
  final bool isDemo;
  final String? defaultDisplayName;
  final StorefrontInstantPicker? pickPauseUntil;
  final StorefrontTimePicker? pickTime;
  final StorefrontDatePicker? pickDate;
  final int Function()? nonce;

  @override
  State<_StorefrontEditor> createState() => _StorefrontEditorState();
}

class _StorefrontEditorState extends State<_StorefrontEditor>
    with AutomaticKeepAliveClientMixin<_StorefrontEditor> {
  /// DASH-1: the Settings ListView builds its children lazily and disposes
  /// the ones scrolled far out of view. The draft, the pending same-request
  /// "Try again" and the media slots' in-flight handles live in this State,
  /// so it is kept alive for as long as the Settings view itself lives.
  @override
  bool get wantKeepAlive => true;

  StorefrontProfileRead? _read;
  bool _loading = false;

  List<StorefrontBranchOption>? _branches;
  bool _branchesLoading = false;
  StorefrontMediaList? _media;
  StorefrontSourceOptions? _sources;

  // The draft.
  final _slug = TextEditingController();
  final _displayName = TextEditingController();
  final _tagline = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _primary = TextEditingController();
  final _accent = TextEditingController();
  final _pauseReason = TextEditingController();
  final _heroHeadline = TextEditingController();
  final _heroSubline = TextEditingController();
  final _announcement = TextEditingController();
  late final List<TextEditingController> _controllers = [
    _slug,
    _displayName,
    _tagline,
    _city,
    _address,
    _phone,
    _primary,
    _accent,
    _pauseReason,
    _heroHeadline,
    _heroSubline,
    _announcement,
  ];
  String? _branchId;
  StorefrontVisualPreset _preset = StorefrontVisualPreset.dark;
  StorefrontLocale _locale = StorefrontLocale.ar;
  StorefrontCardMode _cardMode = StorefrontCardMode.list;
  StorefrontMotion _motion = StorefrontMotion.full;
  bool _pickup = true;
  DateTime? _pausedUntil;
  OpeningHours _hours = OpeningHours.empty;

  bool _saving = false;
  bool _mediaBusy = false;
  _Banner? _banner;

  /// The last pause end picked was at or before now (refused, not applied).
  bool _pausePickRefused = false;

  /// A write committed (or lost to someone else), but the re-read that
  /// should have followed failed: what is shown is older than the server.
  /// Editing stays locked until a reload succeeds — a further save would go
  /// out with a stale version and read as someone else's conflict.
  bool _stale = false;
  _PendingSave? _homePending;
  _PendingSave? _featuredPending;
  Set<String> _featuredIds = {};
  List<StorefrontFeaturedOption>? _featuredOptions;
  bool _featuredLoading = false;
  int _featuredGeneration = 0;

  /// C12 (CRIT-2): the receipt logo the publish function REFUSED for the
  /// logo slot (a deterministic source refusal). The logo slot's only source
  /// is the current receipt logo, so its Publish stays disabled for exactly
  /// that receipt-logo key until the receipt logo is replaced in Branding (a
  /// new upload is a new key). Held here, not in the slot, so reloading the
  /// card does not forget it; a new identity (a new editor) starts without.
  StorefrontRefusedSource? _refusedReceiptLogo;

  bool get _wired => widget.seams != null;
  StorefrontProfile? get _profile => _read?.profile;
  bool get _busy =>
      _saving ||
      _contentDirty ||
      _contentBusy ||
      _legacyBindingHold ||
      _mediaBusy ||
      _stale ||
      _homePending != null ||
      _featuredPending != null;

  bool _contentDirty = false;
  bool _contentBusy = false;
  bool _legacyBindingHold = false;
  ({StorefrontProfileRepository repository, _PendingSave attempt})?
  _legacyOperation;
  int _bindingGeneration = 0;

  bool _currentBinding(int generation) =>
      mounted && generation == _bindingGeneration;

  @override
  void didUpdateWidget(covariant _StorefrontEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.seams, current = widget.seams;
    if (!identical(old?.profileRepository, current?.profileRepository) ||
        !identical(old?.mediaRepository, current?.mediaRepository) ||
        !identical(old?.contentRepository, current?.contentRepository) ||
        !identical(old?.contentCatalog, current?.contentCatalog) ||
        !identical(old?.publisher, current?.publisher)) {
      final keepDraft =
          _patch().isNotEmpty ||
          _homeDirty ||
          _featuredDirty ||
          _banner?.retry != null ||
          _homePending != null ||
          _featuredPending != null;
      if (_saving ||
          _legacyOperation != null ||
          (!identical(old?.profileRepository, current?.profileRepository) &&
              (_banner?.retry != null ||
                  _homePending != null ||
                  _featuredPending != null))) {
        _legacyBindingHold = true;
      }
      _bindingGeneration++;
      _featuredGeneration++;
      // Keep the current child mounted so its original uncertain/confirmed
      // request receipt survives. The replacement parent read is read-only.
      _stale = true;
      if (_wired) _load(preserveVisible: true, preserveDraft: keepDraft);
    }
  }

  bool get _featuredSupported =>
      (_profile?.supportsFeaturedItems ?? false) &&
      widget.seams?.profileRepository is StorefrontFeaturedItemsRepository &&
      widget.seams?.featuredCatalog != null;

  Map<String, Object?> _featuredContent() => {
    'featured_item_ids': List<String>.unmodifiable(
      _featuredIds.toList()..sort(),
    ),
  };

  bool get _featuredDirty {
    final profile = _profile;
    if (profile == null || !_featuredSupported) return false;
    return _featuredIds.length != profile.featuredItemIds.length ||
        !profile.featuredItemIds.every(_featuredIds.contains);
  }

  bool get _featuredValid =>
      !_featuredLoading &&
      _featuredOptions != null &&
      StorefrontProfile.isValidFeaturedItemIds(_featuredIds.toList()) &&
      _featuredIds.every(
        (id) => _featuredOptions!.any((option) => option.id == id),
      );

  bool get _homeSupported =>
      (_profile?.supportsHomeContent ?? false) &&
      widget.seams?.profileRepository is StorefrontHomeContentRepository;

  Map<String, Object?> _homeContent() => {
    'hero_headline': _heroHeadline.text,
    'hero_subline': _heroSubline.text,
    'announcement_text': _announcement.text,
  };

  bool get _homeDirty {
    final p = _profile;
    if (p == null || !_homeSupported) return false;
    final saved = p.toHomeContentFields();
    return _homeContent().entries.any(
      (e) => _blankToNull(e.value! as String) != saved[e.key],
    );
  }

  bool get _homeValid => _homeContent().entries.every(
    (e) => StorefrontProfile.isValidHomeContentValue(e.key, e.value),
  );

  @override
  void initState() {
    super.initState();
    for (final c in _controllers) {
      c.addListener(_onTextChanged);
    }
    if (_wired) _load();
  }

  @override
  void dispose() {
    _bindingGeneration++;
    _featuredGeneration++;
    for (final c in _controllers) {
      c.removeListener(_onTextChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _load({
    bool preserveVisible = false,
    bool preserveDraft = false,
  }) async {
    final generation = _bindingGeneration;
    final seams = widget.seams!;
    final priorProfile = _profile;
    setState(() {
      _loading = !preserveVisible;
      if (!preserveDraft) _banner = null;
      _stale = preserveVisible;
    });
    final read = await _safeRead(seams);
    if (!_currentBinding(generation)) return;
    setState(() {
      _loading = false;
      _read = read;
      _stale =
          _legacyBindingHold ||
          !read.isOk ||
          (preserveDraft &&
              (priorProfile?.version != read.profile?.version ||
                  priorProfile?.storefrontBranchId !=
                      read.profile?.storefrontBranchId));
      if (!preserveDraft) _resetDraft();
    });
    if (!read.isOk) return;
    unawaited(_loadBranches());
    if (read.exists) {
      unawaited(_loadMedia());
      unawaited(_loadSources());
      unawaited(_loadFeatured());
    }
  }

  Future<void> _loadBranches() async {
    final generation = _bindingGeneration;
    final source = widget.seams!.branchSource;
    setState(() => _branchesLoading = true);
    List<StorefrontBranchOption>? branches;
    try {
      branches = await source.list();
    } catch (_) {
      branches = null; // fail-soft: the picker says so
    }
    if (!_currentBinding(generation)) return;
    setState(() {
      _branches = branches;
      _branchesLoading = false;
    });
  }

  Future<void> _loadMedia() async {
    final generation = _bindingGeneration;
    final media = await _safeList(widget.seams!);
    if (!_currentBinding(generation)) return;
    setState(() => _media = media);
  }

  Future<void> _loadSources() async {
    final generation = _bindingGeneration;
    final seams = widget.seams!;
    if (seams.publisher == null) return;
    final sources = await _safeSources(seams);
    if (!_currentBinding(generation)) return;
    setState(() => _sources = sources);
  }

  Future<void> _loadFeatured() async {
    final binding = _bindingGeneration;
    final generation = ++_featuredGeneration;
    final profile = _profile;
    final catalog = widget.seams?.featuredCatalog;
    if (!_featuredSupported || profile == null || catalog == null) return;
    setState(() {
      _featuredLoading = true;
      _featuredOptions = null;
    });
    List<StorefrontFeaturedOption>? options;
    try {
      options = await catalog.load(profile.storefrontBranchId);
    } catch (_) {
      options = null;
    }
    if (!_currentBinding(binding) ||
        generation != _featuredGeneration ||
        _profile?.version != profile.version ||
        _profile?.storefrontBranchId != profile.storefrontBranchId)
      return;
    setState(() {
      _featuredLoading = false;
      _featuredOptions = options;
    });
  }

  /// Re-reads the authoritative profile AND media list (and the sources when
  /// asked). A failed profile read keeps the last good state on screen and
  /// answers false (a successful one clears [_stale]).
  Future<bool> _refreshAll({
    bool resetDraft = true,
    bool reloadSources = false,
  }) async {
    final result = await _refreshAllState(
      resetDraft: resetDraft,
      reloadSources: reloadSources,
    );
    return result.profileRead && result.mediaRead;
  }

  Future<StorefrontContentRefresh> _refreshAllState({
    bool resetDraft = true,
    bool reloadSources = false,
  }) async {
    final generation = _bindingGeneration;
    final seams = widget.seams!;
    final hadProfile = _read?.exists ?? false;
    final results = await Future.wait<Object?>([
      _safeRead(seams),
      _safeList(seams),
      if (reloadSources && seams.publisher != null) _safeSources(seams),
    ]);
    if (!_currentBinding(generation))
      return const StorefrontContentRefresh.unavailable();
    final read = results[0]! as StorefrontProfileRead;
    final media = results[1]! as StorefrontMediaList;
    setState(() {
      if (read.isOk) {
        _read = read;
        _stale = _legacyBindingHold;
        if (resetDraft) _resetDraft();
      }
      _media = media;
      if (results.length > 2) {
        _sources = results[2]! as StorefrontSourceOptions;
      }
    });
    if (read.isOk && read.exists && !hadProfile && _sources == null) {
      unawaited(_loadSources());
    }
    if (read.isOk && read.exists) unawaited(_loadFeatured());
    return StorefrontContentRefresh(
      profileRead: read.isOk,
      mediaRead: media.isOk,
      version: read.profile?.version,
      branchId: read.profile?.storefrontBranchId,
    );
  }

  /// The seams return typed results and never throw; these guards keep a
  /// misbehaving seam from leaving the card spinning (a throw = unavailable).
  Future<StorefrontProfileRead> _safeRead([
    StorefrontEditorSeams? binding,
  ]) async {
    final repository = (binding ?? widget.seams!).profileRepository;
    try {
      return await repository.read();
    } catch (_) {
      return const StorefrontProfileRead.unavailable();
    }
  }

  Future<StorefrontMediaList> _safeList([
    StorefrontEditorSeams? binding,
  ]) async {
    final repository = (binding ?? widget.seams!).mediaRepository;
    try {
      return await repository.list();
    } catch (_) {
      return const StorefrontMediaList.unavailable();
    }
  }

  /// Re-reads the candidate sources NOW and shows them (the media slots use
  /// it to confirm a receipt-logo source is still the CURRENT receipt logo
  /// when Publish is pressed).
  Future<StorefrontSourceOptions> _reloadSources() async {
    final generation = _bindingGeneration;
    final sources = await _safeSources(widget.seams!);
    if (_currentBinding(generation)) setState(() => _sources = sources);
    return sources;
  }

  Future<StorefrontSourceOptions> _safeSources([
    StorefrontEditorSeams? binding,
  ]) async {
    final source = (binding ?? widget.seams!).sourceCatalog;
    try {
      return await source.load();
    } catch (_) {
      return const StorefrontSourceOptions(
        receiptLogoUnavailable: true,
        menuImagesUnavailable: true,
      );
    }
  }

  /// Puts the SAVED profile (or the create defaults) into the draft.
  void _resetDraft() {
    final p = _profile;
    _slug.text = p?.slug ?? '';
    final fallbackName = (widget.defaultDisplayName ?? '').trim();
    _displayName.text =
        p?.displayName ??
        (fallbackName.runes.length > 60
            ? String.fromCharCodes(fallbackName.runes.take(60))
            : fallbackName);
    _tagline.text = p?.tagline ?? '';
    _city.text = p?.publicCity ?? '';
    _address.text = p?.publicAddress ?? '';
    _phone.text = p?.publicPhone ?? '';
    _primary.text = p?.primaryColor ?? kStorefrontNeutralPrimary;
    _accent.text = p?.accentColor ?? '#e07b2c';
    _pauseReason.text = p?.pauseReason ?? '';
    _heroHeadline.text = p?.heroHeadline ?? '';
    _heroSubline.text = p?.heroSubline ?? '';
    _announcement.text = p?.announcementText ?? '';
    if (_featuredPending == null) _featuredIds = {...?p?.featuredItemIds};
    _branchId = p?.storefrontBranchId;
    _preset = p?.visualPreset ?? StorefrontVisualPreset.dark;
    _locale = p?.localeDefault ?? StorefrontLocale.ar;
    _cardMode = p?.cardMode ?? StorefrontCardMode.list;
    _motion = p?.motion ?? StorefrontMotion.full;
    _pickup = p?.pickupEnabled ?? true;
    _pausedUntil = p?.pausedUntil;
    _pausePickRefused = false;
    _hours = p?.openingHours ?? OpeningHours.empty;
  }

  // ---------------------------------------------------------------------------
  // Draft -> patch (ONLY changed keys) + client-side mirrors of the writer
  // ---------------------------------------------------------------------------

  Map<String, Object?> _patch() {
    final p = _profile;
    final out = <String, Object?>{};
    final name = _displayName.text.trim();
    if (p == null) {
      final slug = _slug.text.trim();
      if (slug.isNotEmpty) out['slug'] = slug;
      if (_branchId != null) out['storefront_branch_id'] = _branchId;
      if (name.isNotEmpty) out['display_name'] = name;
      return out;
    }
    if (_branchId != null && !_sameId(_branchId, p.storefrontBranchId)) {
      out['storefront_branch_id'] = _branchId;
    }
    if (name != p.displayName) out['display_name'] = name;
    void text(String key, TextEditingController c, String? current) {
      final v = _blankToNull(c.text);
      if (v != current) out[key] = v;
    }

    text('tagline', _tagline, p.tagline);
    text('public_city', _city, p.publicCity);
    text('public_address', _address, p.publicAddress);
    text('public_phone', _phone, p.publicPhone);
    void color(String key, TextEditingController c, String current) {
      final v = c.text.trim().toLowerCase();
      if (v != current.toLowerCase()) out[key] = v;
    }

    color('primary_color', _primary, p.primaryColor);
    color('accent_color', _accent, p.accentColor);
    if (_preset != p.visualPreset) out['visual_preset'] = _preset.name;
    if (_locale != p.localeDefault) out['locale_default'] = _locale.name;
    if (_cardMode != p.cardMode) out['card_mode'] = _cardMode.name;
    if (_motion != p.motion) out['motion'] = _motion.name;
    if (_pickup != p.pickupEnabled) out['pickup_enabled'] = _pickup;
    if (!_sameInstant(_pausedUntil, p.pausedUntil)) {
      out['paused_until'] = _pausedUntil == null
          ? null
          : _wireInstant(_pausedUntil!);
    }
    text('pause_reason', _pauseReason, p.pauseReason);
    if (_hours != p.openingHours) out['opening_hours'] = _hours.toJson();
    return out;
  }

  /// Unsaved edits against the SAVED profile (never while [_stale]: the
  /// saved profile on screen is then older than the server).
  bool get _dirty => !_stale && _profile != null && _patch().isNotEmpty;

  int _len(TextEditingController c) => c.text.trim().runes.length;

  String? _slugError(AppLocalizations l10n) {
    if (_profile != null) return null;
    final s = _slug.text.trim();
    if (s.isEmpty) return null;
    return isValidStorefrontSlug(s) ? null : l10n.storefrontSlugInvalid;
  }

  String? _nameError(AppLocalizations l10n) {
    final n = _len(_displayName);
    // Creating with an empty name keeps the server default (the restaurant's
    // name); an existing profile needs 1..60.
    final bad = _profile == null ? n > 60 : (n < 1 || n > 60);
    return bad ? l10n.storefrontDisplayNameInvalid : null;
  }

  String? _maxError(AppLocalizations l10n, TextEditingController c, int max) =>
      _len(c) > max ? l10n.storefrontTooLong(max) : null;

  String? _phoneError(AppLocalizations l10n) {
    final t = _phone.text.trim();
    if (t.isEmpty) return null;
    return _phoneShape.hasMatch(t) ? null : l10n.storefrontPhoneInvalid;
  }

  String? _colorError(AppLocalizations l10n, TextEditingController c) =>
      _colorShape.hasMatch(c.text.trim()) ? null : l10n.storefrontColorInvalid;

  /// An UNSAVED pause end that is no longer in the future (e.g. picked, then
  /// left unsaved until it passed): saving it would not pause anything.
  bool get _pauseDraftPast {
    final draft = _pausedUntil;
    final p = _profile;
    if (draft == null || p == null || _sameInstant(draft, p.pausedUntil)) {
      return false;
    }
    return !draft.isAfter(DateTime.now());
  }

  bool _hasErrors(AppLocalizations l10n) {
    if (_profile == null) {
      return _slugError(l10n) != null || _nameError(l10n) != null;
    }
    return [
          _nameError(l10n),
          _maxError(l10n, _tagline, 90),
          _maxError(l10n, _city, 60),
          _maxError(l10n, _address, 80),
          _phoneError(l10n),
          _colorError(l10n, _primary),
          _colorError(l10n, _accent),
          _maxError(l10n, _pauseReason, 120),
        ].any((e) => e != null) ||
        _pauseDraftPast ||
        !_hours.isValid ||
        // Q-038: touching windows are refused here (the server accepts them).
        _hours.hasTouchingWindows;
  }

  bool _canCreate(AppLocalizations l10n) =>
      !_busy &&
      _branchId != null &&
      isValidStorefrontSlug(_slug.text.trim()) &&
      !_hasErrors(l10n);

  bool _canSave(AppLocalizations l10n) =>
      !_busy && _dirty && !_homeDirty && !_featuredDirty && !_hasErrors(l10n);

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<bool> _confirm({
    required Key key,
    required String title,
    required String body,
    required String action,
    String? path,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        key: key,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            if (path != null) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              // The path is an LTR island in ar/he; plain text, not a link.
              Text(
                path,
                textDirection: TextDirection.ltr,
                style: Theme.of(dctx).textTheme.titleSmall,
              ),
            ],
          ],
        ),
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

  Future<void> _onSave() async {
    final l10n = AppLocalizations.of(context);
    final read = _read;
    if (read == null || !read.isOk || _busy || _homeDirty || _featuredDirty)
      return;
    // The button may predate a check that changes with time (a pause end
    // that has passed since it was picked): re-check at the press.
    if (_hasErrors(l10n)) {
      setState(() {});
      return;
    }
    final patch = _patch();
    if (patch.isEmpty) return;
    if (!read.exists) {
      // The FIRST save fixes the slug for good: say so, and ask.
      final ok = await _confirm(
        key: const Key('storefront-create-confirm'),
        title: l10n.storefrontCreateConfirmTitle,
        body: l10n.storefrontCreateConfirmBody,
        action: l10n.storefrontCreateConfirmAction,
        path: '/s/${patch['slug']}',
      );
      if (!ok) return;
    }
    await _runSave(
      patch,
      expectedVersion: read.version,
      draftPatch: patch,
      okMessage: l10n.storefrontSaved,
    );
  }

  Future<void> _onSaveHome({_PendingSave? replay}) async {
    if (!mounted) return;
    final generation = _bindingGeneration;
    final p = _profile;
    final repository = widget.seams?.profileRepository;
    if (p == null ||
        repository is! StorefrontHomeContentRepository ||
        !_homeSupported ||
        _featuredDirty ||
        _featuredPending != null ||
        _saving ||
        _legacyBindingHold ||
        _contentBusy ||
        _contentDirty ||
        _mediaBusy ||
        _stale)
      return;
    if (replay == null &&
        (_homePending != null || _dirty || !_homeDirty || !_homeValid))
      return;
    if (replay != null && !identical(replay, _homePending)) return;
    final homeRepository = repository as StorefrontHomeContentRepository;
    final l10n = AppLocalizations.of(context);
    final patch =
        replay?.patch ?? Map<String, Object?>.unmodifiable(_homeContent());
    final version = replay?.expectedVersion ?? p.version;
    final requestId =
        replay?.requestId ??
        storefrontRequestId(
          'pbl:storefront:home:',
          [widget.seams!.scopeIdentity, version.toString(), jsonEncode(patch)],
          widget.nonce?.call() ?? DateTime.now().microsecondsSinceEpoch,
        );
    _legacyOperation = (
      repository: repository!,
      attempt:
          replay ??
          _PendingSave(
            patch: patch,
            expectedVersion: version,
            requestId: requestId,
            draftPatch: patch,
            okMessage: l10n.storefrontHomeContentSaved,
          ),
    );
    setState(() {
      _saving = true;
      _banner = null;
    });
    StorefrontWriteResult result;
    try {
      result = await homeRepository.saveHomeContent(
        expectedVersion: version,
        content: patch,
        requestId: requestId,
      );
    } catch (_) {
      // A seam that throws after sending cannot prove a rollback. Keep the
      // existing retry identity if one exists; never mint an automatic POST.
      result = StorefrontWriteResult(
        StorefrontWriteStatus.uncertain,
        requestId: requestId,
        expectedVersion: version,
      );
    }
    if (!_currentBinding(generation)) return;
    if (replay != null &&
        result.status != StorefrontWriteStatus.ok &&
        result.status != StorefrontWriteStatus.conflict) {
      // Losing authorization during an explicit retry says nothing about
      // the original unknown write. Keep its exact identity and draft.
      result = StorefrontWriteResult(
        StorefrontWriteStatus.uncertain,
        requestId: requestId,
        expectedVersion: version,
        readback: result.readback,
      );
    }
    var stale = false;
    late final _Banner banner;
    switch (result.status) {
      case StorefrontWriteStatus.ok:
        _homePending = null;
        stale = !await _refreshAll();
        banner = _Banner(
          l10n.storefrontHomeContentSaved,
          RestoflowTone.success,
        );
      case StorefrontWriteStatus.conflict:
        _homePending = null;
        stale = !await _refreshAll();
        banner = _Banner(
          stale
              ? l10n.storefrontErrorConflictNotReloaded
              : l10n.storefrontErrorConflict,
          RestoflowTone.warning,
        );
      case StorefrontWriteStatus.uncertain:
        _homePending = _PendingSave(
          patch: patch,
          expectedVersion: version,
          requestId: requestId,
          draftPatch: patch,
          okMessage: l10n.storefrontHomeContentSaved,
        );
        banner = _Banner(
          l10n.storefrontHomeContentUncertain,
          RestoflowTone.warning,
        );
      case StorefrontWriteStatus.denied:
        _homePending = null;
        banner = _Banner(l10n.storefrontErrorDenied, RestoflowTone.danger);
      case StorefrontWriteStatus.invalid:
        _homePending = null;
        if (result.reason == 'not_found') stale = !await _refreshAll();
        banner = _Banner(
          result.reason == 'not_found'
              ? l10n.storefrontHomeContentProfileMissing
              : l10n.storefrontHomeContentInvalid,
          RestoflowTone.danger,
        );
      case StorefrontWriteStatus.unavailable:
        _homePending = null;
        banner = _Banner(l10n.storefrontErrorUnavailable, RestoflowTone.danger);
      case StorefrontWriteStatus.notCommitted:
        _homePending = null;
        banner = _Banner(
          l10n.storefrontErrorNotCommitted,
          RestoflowTone.danger,
        );
    }
    if (!_currentBinding(generation)) return;
    _legacyOperation = null;
    setState(() {
      _saving = false;
      _banner = banner;
      if (stale) _stale = true;
    });
  }

  Future<void> _onSaveFeatured({_PendingSave? replay}) async {
    if (!mounted) return;
    final generation = _bindingGeneration;
    final p = _profile;
    final repository = widget.seams?.profileRepository;
    if (p == null ||
        repository is! StorefrontFeaturedItemsRepository ||
        !_featuredSupported ||
        _homeDirty ||
        _homePending != null ||
        _saving ||
        _legacyBindingHold ||
        _contentBusy ||
        _contentDirty ||
        _mediaBusy ||
        _stale)
      return;
    if (replay == null &&
        (_featuredPending != null ||
            _dirty ||
            !_featuredDirty ||
            !_featuredValid))
      return;
    if (replay != null && !identical(replay, _featuredPending)) return;
    final featuredRepository = repository as StorefrontFeaturedItemsRepository;
    final l10n = AppLocalizations.of(context);
    final patch =
        replay?.patch ?? Map<String, Object?>.unmodifiable(_featuredContent());
    final version = replay?.expectedVersion ?? p.version;
    final requestId =
        replay?.requestId ??
        storefrontRequestId(
          'pbl:storefront:featured:',
          [widget.seams!.scopeIdentity, version.toString(), jsonEncode(patch)],
          widget.nonce?.call() ?? DateTime.now().microsecondsSinceEpoch,
        );
    _legacyOperation = (
      repository: repository!,
      attempt:
          replay ??
          _PendingSave(
            patch: patch,
            expectedVersion: version,
            requestId: requestId,
            draftPatch: patch,
            okMessage: l10n.storefrontFeaturedItemsSaved,
          ),
    );
    setState(() {
      _saving = true;
      _banner = null;
    });
    StorefrontWriteResult result;
    try {
      result = await featuredRepository.saveFeaturedItems(
        expectedVersion: version,
        itemIds: (patch['featured_item_ids']! as List).cast<String>(),
        requestId: requestId,
      );
    } catch (_) {
      // A seam that throws after sending cannot prove a rollback. Keep the
      // existing retry identity if one exists; never mint an automatic POST.
      result = StorefrontWriteResult(
        StorefrontWriteStatus.uncertain,
        requestId: requestId,
        expectedVersion: version,
      );
    }
    if (!_currentBinding(generation)) return;
    if (replay != null &&
        result.status != StorefrontWriteStatus.ok &&
        result.status != StorefrontWriteStatus.conflict) {
      // Losing authorization during an explicit retry says nothing about
      // the original unknown write. Keep its exact identity and draft.
      result = StorefrontWriteResult(
        StorefrontWriteStatus.uncertain,
        requestId: requestId,
        expectedVersion: version,
        readback: result.readback,
      );
    }
    var stale = false;
    late final _Banner banner;
    switch (result.status) {
      case StorefrontWriteStatus.ok:
        _featuredPending = null;
        stale = !await _refreshAll();
        banner = _Banner(
          l10n.storefrontFeaturedItemsSaved,
          RestoflowTone.success,
        );
      case StorefrontWriteStatus.conflict:
        _featuredPending = null;
        stale = !await _refreshAll();
        banner = _Banner(
          stale
              ? l10n.storefrontErrorConflictNotReloaded
              : l10n.storefrontErrorConflict,
          RestoflowTone.warning,
        );
      case StorefrontWriteStatus.uncertain:
        _featuredPending = _PendingSave(
          patch: patch,
          expectedVersion: version,
          requestId: requestId,
          draftPatch: patch,
          okMessage: l10n.storefrontFeaturedItemsSaved,
        );
        banner = _Banner(
          l10n.storefrontFeaturedItemsUncertain,
          RestoflowTone.warning,
        );
      case StorefrontWriteStatus.denied:
        _featuredPending = null;
        banner = _Banner(l10n.storefrontErrorDenied, RestoflowTone.danger);
      case StorefrontWriteStatus.invalid:
        _featuredPending = null;
        if (result.reason == 'not_found') stale = !await _refreshAll();
        banner = _Banner(
          result.reason == 'not_found'
              ? l10n.storefrontFeaturedItemsProfileMissing
              : l10n.storefrontFeaturedItemsInvalid,
          RestoflowTone.danger,
        );
      case StorefrontWriteStatus.unavailable:
        _featuredPending = null;
        banner = _Banner(l10n.storefrontErrorUnavailable, RestoflowTone.danger);
      case StorefrontWriteStatus.notCommitted:
        _featuredPending = null;
        banner = _Banner(
          l10n.storefrontErrorNotCommitted,
          RestoflowTone.danger,
        );
    }
    if (!_currentBinding(generation)) return;
    _legacyOperation = null;
    setState(() {
      _saving = false;
      _banner = banner;
      if (stale) _stale = true;
    });
  }

  Future<void> _onPublishToggle(bool publish) async {
    final l10n = AppLocalizations.of(context);
    final p = _profile;
    if (p == null || _busy) return;
    final ok = publish
        ? await _confirm(
            key: const Key('storefront-publish-confirm'),
            title: l10n.storefrontPublishConfirmTitle,
            body: l10n.storefrontPublishConfirmBody,
            action: l10n.storefrontPublishAction,
            path: '/s/${p.slug}',
          )
        : await _confirm(
            key: const Key('storefront-unpublish-confirm'),
            title: l10n.storefrontUnpublishConfirmTitle,
            body: l10n.storefrontUnpublishConfirmBody,
            action: l10n.storefrontUnpublishAction,
          );
    if (!ok) return;
    await _runSave(
      {'is_published': publish},
      expectedVersion: p.version,
      draftPatch: const <String, Object?>{},
      okMessage: publish
          ? l10n.storefrontPublishDone
          : l10n.storefrontUnpublishDone,
    );
  }

  /// The `publish_precondition` offer: save the SAME edits together with
  /// `is_published: false` (one CAS write).
  Future<void> _onUnpublishAndSave() async {
    final l10n = AppLocalizations.of(context);
    final p = _profile;
    if (p == null || _busy) return;
    final ok = await _confirm(
      key: const Key('storefront-unpublish-save-confirm'),
      title: l10n.storefrontUnpublishConfirmTitle,
      body: l10n.storefrontUnpublishConfirmBody,
      action: l10n.storefrontUnpublishAndSaveAction,
    );
    if (!ok) return;
    final draft = _patch();
    await _runSave(
      {...draft, 'is_published': false},
      expectedVersion: p.version,
      draftPatch: draft,
      okMessage: l10n.storefrontUnpublishDone,
    );
  }

  Future<void> _retrySave(_PendingSave pending) => _runSave(
    pending.patch,
    expectedVersion: pending.expectedVersion,
    draftPatch: pending.draftPatch,
    okMessage: pending.okMessage,
    requestId: pending.requestId,
  );

  Future<void> _runSave(
    Map<String, Object?> patch, {
    required int expectedVersion,
    required Map<String, Object?> draftPatch,
    required String okMessage,
    String? requestId,
  }) async {
    if (!mounted || _busy) return;
    final generation = _bindingGeneration;
    final repository = widget.seams!.profileRepository;
    final l10n = AppLocalizations.of(context);
    _legacyOperation = (
      repository: repository,
      attempt: _PendingSave(
        patch: Map<String, Object?>.unmodifiable(patch),
        expectedVersion: expectedVersion,
        requestId: requestId,
        draftPatch: Map<String, Object?>.unmodifiable(draftPatch),
        okMessage: okMessage,
      ),
    );
    setState(() {
      _saving = true;
      _banner = null;
    });
    final result = await repository.save(
      expectedVersion: expectedVersion,
      patch: patch,
      requestId: requestId,
    );
    if (!_currentBinding(generation)) return;
    _Banner banner;
    var stale = false;
    switch (result.status) {
      case StorefrontWriteStatus.ok:
        // The success envelope has no profile: re-read the authority. If
        // that read fails, lock editing until a reload (never a second save
        // from the old version).
        stale = !await _refreshAll();
        banner = _Banner(okMessage, RestoflowTone.success);
      case StorefrontWriteStatus.conflict:
        // Someone else won: show THEIR state; never merge silently.
        stale = !await _refreshAll();
        banner = _Banner(
          stale
              ? l10n.storefrontErrorConflictNotReloaded
              : l10n.storefrontErrorConflict,
          RestoflowTone.warning,
        );
      case StorefrontWriteStatus.denied:
        banner = _Banner(l10n.storefrontErrorDenied, RestoflowTone.danger);
      case StorefrontWriteStatus.invalid:
        final precondition = result.reason == 'publish_precondition';
        if (precondition && patch['is_published'] == true) {
          // The blockers changed since the last read: show the current ones.
          await _refreshAll(resetDraft: false);
        }
        banner = _Banner(
          storefrontReasonMessage(l10n, result.reason),
          RestoflowTone.danger,
          blockers: result.blockers,
          offerUnpublishSave:
              precondition &&
              (_profile?.isPublished ?? false) &&
              patch['is_published'] != false &&
              draftPatch.isNotEmpty,
        );
      case StorefrontWriteStatus.unavailable:
        banner = _Banner(l10n.storefrontErrorUnavailable, RestoflowTone.danger);
      case StorefrontWriteStatus.notCommitted:
        banner = _Banner(
          l10n.storefrontErrorNotCommitted,
          RestoflowTone.danger,
        );
      case StorefrontWriteStatus.uncertain:
        // Unknown outcome: keep the draft; "Try again" replays the SAME
        // request (a committed write is replayed by the server ledger).
        banner = _Banner(
          l10n.storefrontErrorUncertain,
          RestoflowTone.warning,
          retry: _PendingSave(
            patch: patch,
            expectedVersion: expectedVersion,
            requestId: result.requestId,
            draftPatch: draftPatch,
            okMessage: okMessage,
          ),
        );
    }
    if (!_currentBinding(generation)) return;
    _legacyOperation = null;
    setState(() {
      _saving = false;
      _banner = banner;
      if (stale) _stale = true;
    });
  }

  /// The media slots' CAS assignment (null [mediaId] clears the slot).
  /// [replay] re-sends an earlier write with an unknown outcome as THE SAME
  /// request (its id + expected version) unless the authoritative profile
  /// already shows it.
  Future<StorefrontWriteResult> _assignSlot(
    StorefrontSlot slot,
    String? mediaId, {
    required bool reReadFirst,
    StorefrontSlotReplay? replay,
  }) async {
    if (!mounted)
      return const StorefrontWriteResult(StorefrontWriteStatus.unavailable);
    final seams = widget.seams!;
    final generation = _bindingGeneration;
    if (_contentBusy || _contentDirty || _legacyBindingHold)
      return const StorefrontWriteResult(StorefrontWriteStatus.unavailable);
    if (reReadFirst) {
      final fresh = await _safeRead(seams);
      if (!_currentBinding(generation) || _contentBusy || _contentDirty)
        return const StorefrontWriteResult(StorefrontWriteStatus.unavailable);
      if (fresh.isOk) {
        setState(() {
          _read = fresh;
          _stale = false;
          _resetDraft();
        });
      }
    }
    final p = _profile;
    if (p == null) {
      return const StorefrontWriteResult(StorefrontWriteStatus.unavailable);
    }
    if (_sameId(p.mediaIdFor(slot), mediaId)) {
      // Already the authoritative state (e.g. a same-source re-point, or a
      // retry after an unknown outcome that had in fact committed).
      await _refreshAll();
      return StorefrontWriteResult(
        StorefrontWriteStatus.ok,
        version: p.version,
      );
    }
    final result = await seams.profileRepository.save(
      expectedVersion: replay?.expectedVersion ?? p.version,
      patch: {slot.profileKey: mediaId},
      requestId: replay?.requestId,
    );
    if (!_currentBinding(generation)) return result;
    final fresh = await _refreshAll();
    if (!fresh &&
        mounted &&
        (result.status == StorefrontWriteStatus.ok ||
            result.status == StorefrontWriteStatus.conflict)) {
      // The profile moved on but could not be re-read: lock until a reload.
      setState(() => _stale = true);
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AdminSectionCard(
      key: const Key('storefront-section'),
      title: l10n.storefrontSectionTitle,
      icon: Icons.storefront_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.storefrontSectionSubtitle,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: RestoflowSpacing.md),
          ..._body(l10n, theme),
        ],
      ),
    );
  }

  List<Widget> _body(AppLocalizations l10n, ThemeData theme) {
    if (!_wired) {
      return [
        Text(
          widget.isDemo
              ? l10n.storefrontDemoNote
              : l10n.storefrontUnavailableNote,
          key: const Key('storefront-unavailable'),
          style: theme.textTheme.bodyMedium,
        ),
      ];
    }
    final read = _read;
    if (_loading || read == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(RestoflowSpacing.md),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    switch (read.status) {
      case StorefrontReadStatus.denied:
        return [
          Text(
            l10n.storefrontDeniedNote,
            key: const Key('storefront-denied'),
            style: theme.textTheme.bodyMedium,
          ),
        ];
      case StorefrontReadStatus.unavailable:
      case StorefrontReadStatus.malformed:
        return [
          Text(
            l10n.storefrontLoadFailed,
            key: const Key('storefront-load-failed'),
            style: theme.textTheme.bodyMedium,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('storefront-retry'),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.storefrontRetry),
            ),
          ),
        ];
      case StorefrontReadStatus.ok:
        break;
    }
    final profile = read.profile;
    return profile == null
        ? _createForm(l10n, theme)
        : _editor(l10n, theme, profile, read.derived!);
  }

  /// Fields that stack on narrow widths and pair up on wide ones.
  Widget _grid(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      final max = constraints.maxWidth;
      final width = max >= 560
          ? ((max - RestoflowSpacing.md) / 2).floorToDouble()
          : max;
      return Wrap(
        spacing: RestoflowSpacing.md,
        runSpacing: RestoflowSpacing.md,
        children: [for (final c in children) SizedBox(width: width, child: c)],
      );
    },
  );

  InputDecoration _decoration(
    String label, {
    String? error,
    String? helper,
    Widget? prefix,
  }) => InputDecoration(
    labelText: label,
    errorText: error,
    helperText: helper,
    helperMaxLines: 4,
    errorMaxLines: 4,
    prefixIcon: prefix,
    border: const OutlineInputBorder(),
    isDense: true,
  );

  Widget _textField({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? error,
    String? helper,
    bool ltr = false,
    Widget? prefix,
  }) => TextField(
    key: key,
    controller: controller,
    enabled: !_busy,
    textDirection: ltr ? TextDirection.ltr : null,
    decoration: _decoration(
      label,
      error: error,
      helper: helper,
      prefix: prefix,
    ),
  );

  /// A CONTROLLED dropdown (a FormField would keep a stale value when the
  /// draft is reset from the server).
  Widget _dropdown<T>({
    required Key key,
    required String label,
    required T? value,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
    String? helper,
  }) => InputDecorator(
    decoration: _decoration(label, helper: helper),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        key: key,
        value: value,
        isExpanded: true,
        isDense: true,
        items: [
          for (final (v, text) in items)
            DropdownMenuItem<T>(
              value: v,
              child: Text(text, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _busy
            ? null
            : (v) {
                if (v != null) setState(() => onChanged(v));
              },
      ),
    ),
  );

  Widget _branchPicker(AppLocalizations l10n, ThemeData theme) {
    final branches = _branches;
    if (branches == null) {
      if (_branchesLoading) return const LinearProgressIndicator();
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: RestoflowSpacing.sm,
        children: [
          Text(
            l10n.storefrontBranchesUnavailable,
            key: const Key('storefront-branches-unavailable'),
            style: theme.textTheme.bodySmall,
          ),
          TextButton(
            key: const Key('storefront-branches-retry'),
            onPressed: _busy ? null : _loadBranches,
            child: Text(l10n.storefrontRetry),
          ),
        ],
      );
    }
    final current = _branchId;
    final listed =
        current != null && branches.any((b) => _sameId(b.id, current));
    final picker = _dropdown<String>(
      key: const Key('storefront-branch'),
      label: l10n.storefrontBranchLabel,
      helper: l10n.storefrontBranchHelp,
      value: current,
      items: [
        // Q-035 / DASH-3: the read carries each branch's status; the public
        // read serves nothing for a suspended branch, so say so here.
        for (final b in branches)
          (
            b.id,
            b.isSuspended
                ? l10n.storefrontBranchSuspendedOption(b.name)
                : b.name,
          ),
        if (current != null && !listed)
          (current, l10n.storefrontBranchUnlisted),
      ],
      onChanged: (id) => _branchId = id,
    );
    final chosenSuspended = branches.any(
      (b) => b.isSuspended && _sameId(b.id, current),
    );
    if (!chosenSuspended) return picker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        picker,
        Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
          child: Text(
            l10n.storefrontBranchSuspendedNote,
            key: const Key('storefront-branch-suspended'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: RestoflowTone.warning.styleOf(theme).accent,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _createForm(AppLocalizations l10n, ThemeData theme) => [
    Text(l10n.storefrontCreateIntro, style: theme.textTheme.bodyMedium),
    const SizedBox(height: RestoflowSpacing.md),
    _grid([
      _branchPicker(l10n, theme),
      _textField(
        key: const Key('storefront-slug'),
        controller: _slug,
        label: l10n.storefrontSlugLabel,
        helper: l10n.storefrontSlugHelp,
        error: _slugError(l10n),
        ltr: true,
      ),
      _textField(
        key: const Key('storefront-display-name'),
        controller: _displayName,
        label: l10n.storefrontDisplayNameLabel,
        error: _nameError(l10n),
      ),
    ]),
    const SizedBox(height: RestoflowSpacing.md),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton.icon(
        key: const Key('storefront-save'),
        onPressed: _canCreate(l10n) ? _onSave : null,
        icon: const Icon(Icons.add_business_outlined),
        label: Text(l10n.storefrontCreateAction),
      ),
    ),
    if (_saving)
      const Padding(
        padding: EdgeInsets.only(top: RestoflowSpacing.sm),
        child: LinearProgressIndicator(),
      ),
    if (_banner != null) ..._bannerView(l10n, theme),
    if (_stale) ..._staleView(l10n, theme),
    const Divider(height: RestoflowSpacing.xl),
    Text(l10n.storefrontMediaTitle, style: theme.textTheme.titleSmall),
    const SizedBox(height: RestoflowSpacing.xs),
    Text(
      l10n.storefrontMediaNeedsProfile,
      key: const Key('storefront-media-needs-profile'),
      style: theme.textTheme.bodySmall,
    ),
  ];

  String? _hoursTimezone(StorefrontProfile profile, StorefrontDerived derived) {
    final draft = _branchId;
    if (draft == null || _sameId(draft, profile.storefrontBranchId)) {
      return derived.timezone;
    }
    for (final b in _branches ?? const <StorefrontBranchOption>[]) {
      // The server's rule for the draft branch: its own zone, else the
      // restaurant's (never the SAVED branch's zone).
      if (_sameId(b.id, draft)) return b.effectiveTimezone;
    }
    // Unreachable: a draft branch always comes from the listed branches.
    return derived.timezone;
  }

  List<Widget> _editor(
    AppLocalizations l10n,
    ThemeData theme,
    StorefrontProfile profile,
    StorefrontDerived derived,
  ) {
    final dirty = _dirty;
    final contentBinding = _bindingGeneration;
    final path = '/s/${profile.slug}';
    final pausedUntil = _pausedUntil;
    final zone = (pausedUntil ?? DateTime.now()).toLocal().timeZoneOffset;
    // A pause end that has passed pauses nothing: never label it "Paused
    // until" (the public read pauses only while `paused_until > now()`).
    final pauseEnded =
        pausedUntil != null && !pausedUntil.isAfter(DateTime.now());
    final primaryHex = _primary.text.trim();
    final primaryVerdict = _colorShape.hasMatch(primaryHex)
        ? inspectStorefrontPrimary(primaryHex)
        : null;
    return [
      // Identity: the slug is fixed after creation; the path is TEXT (no
      // public origin yet — D8), never a link.
      Text(l10n.storefrontSlugLabel, style: theme.textTheme.labelMedium),
      Text(
        profile.slug,
        key: const Key('storefront-slug-readonly'),
        textDirection: TextDirection.ltr,
        style: theme.textTheme.bodyLarge,
      ),
      Text(
        l10n.storefrontSlugPermanentNote,
        key: const Key('storefront-slug-permanent-note'),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      Text(l10n.storefrontPathLabel, style: theme.textTheme.labelMedium),
      Text(
        path,
        key: const Key('storefront-path'),
        textDirection: TextDirection.ltr,
        style: theme.textTheme.bodyLarge,
      ),
      Text(l10n.storefrontPathNote, style: theme.textTheme.bodySmall),
      const SizedBox(height: RestoflowSpacing.md),
      _grid([
        _branchPicker(l10n, theme),
        _textField(
          key: const Key('storefront-display-name'),
          controller: _displayName,
          label: l10n.storefrontDisplayNameLabel,
          error: _nameError(l10n),
        ),
        _textField(
          key: const Key('storefront-tagline'),
          controller: _tagline,
          label: l10n.storefrontTaglineLabel,
          error: _maxError(l10n, _tagline, 90),
        ),
        _textField(
          key: const Key('storefront-city'),
          controller: _city,
          label: l10n.storefrontCityLabel,
          error: _maxError(l10n, _city, 60),
        ),
        _textField(
          key: const Key('storefront-address'),
          controller: _address,
          label: l10n.storefrontAddressLabel,
          error: _maxError(l10n, _address, 80),
        ),
        _textField(
          key: const Key('storefront-phone'),
          controller: _phone,
          label: l10n.storefrontPhoneLabel,
          helper: l10n.storefrontPhoneHelp,
          error: _phoneError(l10n),
          ltr: true,
        ),
      ]),
      ..._homeContentEditor(l10n, theme, profile),
      if (widget.seams?.contentRepository
          case final StorefrontContentRepository repository)
        StorefrontContentSection(
          key: ValueKey('storefront-content|${widget.seams!.scopeIdentity}'),
          repository: repository,
          catalog: widget.seams!.contentCatalog,
          profileVersion: profile.version,
          savedBranchId: profile.storefrontBranchId,
          enabled:
              !_saving &&
              !_mediaBusy &&
              !_stale &&
              !_dirty &&
              !_homeDirty &&
              !_featuredDirty &&
              _homePending == null &&
              _featuredPending == null,
          publisher: widget.seams!.publisher,
          sources: _sources,
          reloadSources: _reloadSources,
          publicUrlFor: widget.seams!.publicUrlFor,
          onRefresh: () async => _currentBinding(contentBinding)
              ? _refreshAllState()
              : const StorefrontContentRefresh.unavailable(),
          onDraftChanged: (dirty) {
            if (_currentBinding(contentBinding))
              setState(() => _contentDirty = dirty);
          },
          onBusyChanged: (busy) {
            if (_currentBinding(contentBinding))
              setState(() => _contentBusy = busy);
          },
        ),
      ..._featuredEditor(l10n, theme, profile),
      const Divider(height: RestoflowSpacing.xl),
      Text(l10n.storefrontLookTitle, style: theme.textTheme.titleSmall),
      const SizedBox(height: RestoflowSpacing.sm),
      _grid([
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _textField(
              key: const Key('storefront-primary-color'),
              controller: _primary,
              label: l10n.storefrontPrimaryColorLabel,
              helper: l10n.storefrontColorHelp,
              error: _colorError(l10n, _primary),
              ltr: true,
              prefix: _swatch(_primary.text),
            ),
            if (primaryVerdict != null && !primaryVerdict.supported)
              Padding(
                padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
                child: Text(
                  l10n.storefrontPrimaryContrastWarning,
                  key: const Key('storefront-primary-contrast-warning'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: RestoflowTone.warning.styleOf(theme).accent,
                  ),
                ),
              ),
          ],
        ),
        _textField(
          key: const Key('storefront-accent-color'),
          controller: _accent,
          label: l10n.storefrontAccentColorLabel,
          helper: l10n.storefrontColorHelp,
          error: _colorError(l10n, _accent),
          ltr: true,
          prefix: _swatch(_accent.text),
        ),
        _dropdown<StorefrontVisualPreset>(
          key: const Key('storefront-visual-preset'),
          label: l10n.storefrontVisualPresetLabel,
          value: _preset,
          items: [
            (StorefrontVisualPreset.dark, l10n.storefrontVisualPresetDark),
            (StorefrontVisualPreset.light, l10n.storefrontVisualPresetLight),
          ],
          onChanged: (v) => _preset = v,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dropdown<StorefrontLocale>(
              key: const Key('storefront-locale'),
              label: l10n.storefrontLocaleLabel,
              value: _locale,
              items: [
                (StorefrontLocale.ar, l10n.storefrontLocaleAr),
                (StorefrontLocale.he, l10n.storefrontLocaleHe),
                (StorefrontLocale.en, l10n.storefrontLocaleEn),
              ],
              onChanged: (v) => _locale = v,
            ),
            Padding(
              padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
              child: Text(
                l10n.storefrontLocaleHelp,
                key: const Key('storefront-locale-help'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        _dropdown<StorefrontCardMode>(
          key: const Key('storefront-card-mode'),
          label: l10n.storefrontCardModeLabel,
          value: _cardMode,
          items: [
            (StorefrontCardMode.list, l10n.storefrontCardModeList),
            (StorefrontCardMode.grid, l10n.storefrontCardModeGrid),
          ],
          onChanged: (v) => _cardMode = v,
        ),
        _dropdown<StorefrontMotion>(
          key: const Key('storefront-motion'),
          label: l10n.storefrontMotionLabel,
          value: _motion,
          items: [
            (StorefrontMotion.calm, l10n.storefrontMotionCalm),
            (StorefrontMotion.full, l10n.storefrontMotionFull),
            (StorefrontMotion.lively, l10n.storefrontMotionLively),
          ],
          onChanged: (v) => _motion = v,
        ),
      ]),
      const SizedBox(height: RestoflowSpacing.sm),
      SwitchListTile(
        key: const Key('storefront-pickup'),
        contentPadding: EdgeInsets.zero,
        value: _pickup,
        onChanged: _busy ? null : (v) => setState(() => _pickup = v),
        title: Text(l10n.storefrontPickupLabel),
        subtitle: Text(
          l10n.storefrontPickupHelp,
          key: const Key('storefront-pickup-help'),
        ),
      ),
      const Divider(height: RestoflowSpacing.xl),
      Text(l10n.storefrontPauseTitle, style: theme.textTheme.titleSmall),
      const SizedBox(height: RestoflowSpacing.xs),
      Wrap(
        spacing: RestoflowSpacing.sm,
        runSpacing: RestoflowSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            pauseEnded
                ? l10n.storefrontPauseEndedLabel
                : l10n.storefrontPausedUntilLabel,
            key: const Key('storefront-paused-until-label'),
            style: theme.textTheme.labelMedium,
          ),
          Text(
            pausedUntil == null
                ? l10n.storefrontNotPaused
                : _formatLocal(pausedUntil),
            key: const Key('storefront-paused-until-value'),
            textDirection: pausedUntil == null ? null : TextDirection.ltr,
            style: theme.textTheme.bodyMedium,
          ),
          OutlinedButton.icon(
            key: const Key('storefront-pause-set'),
            onPressed: _busy ? null : _onPickPause,
            icon: const Icon(Icons.pause_circle_outline),
            label: Text(l10n.storefrontPauseSetAction),
          ),
          if (pausedUntil != null)
            TextButton(
              key: const Key('storefront-pause-clear'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _pausedUntil = null;
                      _pausePickRefused = false;
                    }),
              child: Text(l10n.storefrontPauseClearAction),
            ),
        ],
      ),
      if (_pausePickRefused || _pauseDraftPast)
        Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
          child: Text(
            l10n.storefrontPausePast,
            key: const Key('storefront-pause-past'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      Text(
        l10n.storefrontPauseDeviceZone(_offsetText(zone)),
        key: const Key('storefront-pause-zone'),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      _textField(
        key: const Key('storefront-pause-reason'),
        controller: _pauseReason,
        label: l10n.storefrontPauseReasonLabel,
        error: _maxError(l10n, _pauseReason, 120),
      ),
      Padding(
        padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
        child: Text(
          l10n.storefrontPauseHelp,
          key: const Key('storefront-pause-help'),
          style: theme.textTheme.bodySmall,
        ),
      ),
      const Divider(height: RestoflowSpacing.xl),
      Text(l10n.storefrontHoursTitle, style: theme.textTheme.titleSmall),
      const SizedBox(height: RestoflowSpacing.xs),
      if (profile.openingHours.hasUnreadableEntries) ...[
        // C10 (OQ-1): the AUTHORITATIVE saved hours hold entries this editor
        // cannot read. An explicit error; the stored value is kept verbatim
        // (the editor below is locked, so no other edit can silently replace
        // it with the readable subset or with defaults) and Publish is
        // disabled, until the manager explicitly repairs AND saves.
        Text(
          l10n.storefrontHoursUnreadable,
          key: const Key('storefront-hours-unreadable'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        if (_hours.hasUnreadableEntries)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('storefront-hours-repair'),
              // The same entries, unflagged: the draft is now dirty, the
              // editor unlocks, and the next save writes exactly what is
              // shown.
              onPressed: _busy
                  ? null
                  : () => setState(
                      () => _hours = OpeningHours(
                        weekly: _hours.weekly,
                        exceptions: _hours.exceptions,
                      ),
                    ),
              child: Text(l10n.storefrontHoursRepairAction),
            ),
          )
        else
          Text(
            l10n.storefrontHoursRepairPending,
            key: const Key('storefront-hours-repair-pending'),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: RestoflowSpacing.xs),
      ],
      OpeningHoursEditor(
        key: const Key('storefront-hours'),
        value: _hours,
        timezone: _hoursTimezone(profile, derived),
        // Locked while the draft still IS the unreadable stored value: only
        // the explicit repair above may replace it.
        enabled: !_busy && !_hours.hasUnreadableEntries,
        pickTime: widget.pickTime,
        pickDate: widget.pickDate,
        onChanged: (h) => setState(() => _hours = h),
      ),
      if (!_hours.isValid)
        Text(
          l10n.storefrontHoursInvalid,
          key: const Key('storefront-hours-invalid'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      const Divider(height: RestoflowSpacing.xl),
      // Save row.
      Wrap(
        spacing: RestoflowSpacing.sm,
        runSpacing: RestoflowSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            key: const Key('storefront-save'),
            onPressed: _canSave(l10n) ? _onSave : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.storefrontSaveAction),
          ),
          if (dirty)
            TextButton(
              key: const Key('storefront-discard'),
              onPressed: _busy ? null : _onDiscard,
              child: Text(l10n.storefrontDiscardAction),
            ),
          if (dirty)
            Text(
              l10n.storefrontUnsavedNote,
              key: const Key('storefront-unsaved'),
              style: theme.textTheme.bodySmall,
            ),
          if (dirty && _hasErrors(l10n))
            Text(
              l10n.storefrontFixFields,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
      if (_saving)
        const Padding(
          padding: EdgeInsets.only(top: RestoflowSpacing.sm),
          child: LinearProgressIndicator(),
        ),
      if (_banner != null) ..._bannerView(l10n, theme),
      if (_stale) ..._staleView(l10n, theme),
      const Divider(height: RestoflowSpacing.xl),
      ..._publishArea(
        l10n,
        theme,
        profile,
        derived,
        dirty || _homeDirty || _featuredDirty,
      ),
      const Divider(height: RestoflowSpacing.xl),
      ..._mediaArea(
        l10n,
        theme,
        profile,
        dirty || _homeDirty || _featuredDirty,
      ),
    ];
  }

  List<Widget> _featuredEditor(
    AppLocalizations l10n,
    ThemeData theme,
    StorefrontProfile profile,
  ) {
    final pending = _featuredPending;
    final options = _featuredOptions;
    final unavailableIds = options == null
        ? <String>{}
        : _featuredIds.difference(options.map((option) => option.id).toSet());
    final editable = !_busy && !_dirty && !_homeDirty && !_featuredLoading;
    return [
      const Divider(height: RestoflowSpacing.xl),
      Text(
        l10n.storefrontFeaturedItemsTitle,
        style: theme.textTheme.titleSmall,
      ),
      const SizedBox(height: RestoflowSpacing.xs),
      if (!_featuredSupported)
        Text(
          l10n.storefrontFeaturedItemsUnavailable,
          key: const Key('storefront-featured-unsupported'),
        )
      else ...[
        Text(
          l10n.storefrontFeaturedItemsHelp,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.storefrontFeaturedItemsCount(
            _featuredIds.length,
            StorefrontProfile.maxFeaturedItems,
          ),
          key: const Key('storefront-featured-count'),
        ),
        if (_featuredLoading)
          const LinearProgressIndicator(key: Key('storefront-featured-loading'))
        else if (options == null) ...[
          Text(
            l10n.storefrontFeaturedItemsCatalogUnavailable,
            key: const Key('storefront-featured-catalog-unavailable'),
          ),
          TextButton(
            onPressed: _busy ? null : _loadFeatured,
            child: Text(l10n.storefrontReloadAction),
          ),
        ] else ...[
          if (options.isEmpty) Text(l10n.storefrontFeaturedItemsEmpty),
          for (final option in options)
            CheckboxListTile(
              key: Key('storefront-featured-item-${option.id}'),
              title: Text(option.name),
              subtitle: Text(option.categoryName),
              value: _featuredIds.contains(option.id),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              onChanged:
                  editable &&
                      (_featuredIds.contains(option.id) ||
                          _featuredIds.length <
                              StorefrontProfile.maxFeaturedItems)
                  ? (selected) => setState(() {
                      if (selected == true) {
                        _featuredIds.add(option.id);
                      } else {
                        _featuredIds.remove(option.id);
                      }
                    })
                  : null,
            ),
          if (unavailableIds.isNotEmpty) ...[
            Text(
              l10n.storefrontFeaturedItemsStaleSelection,
              key: const Key('storefront-featured-stale-selection'),
            ),
            TextButton(
              key: const Key('storefront-featured-remove-unavailable'),
              onPressed: editable
                  ? () => setState(() => _featuredIds.removeAll(unavailableIds))
                  : null,
              child: Text(l10n.storefrontFeaturedItemsRemoveUnavailable),
            ),
          ],
        ],
        const SizedBox(height: RestoflowSpacing.sm),
        Wrap(
          spacing: RestoflowSpacing.sm,
          children: [
            FilledButton.icon(
              key: const Key('storefront-featured-save'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: editable && _featuredDirty && _featuredValid
                  ? () => _onSaveFeatured()
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.storefrontFeaturedItemsSaveAction),
            ),
            if (_featuredDirty)
              TextButton(
                key: const Key('storefront-featured-discard'),
                onPressed: _busy
                    ? null
                    : () => setState(
                        () => _featuredIds = {...profile.featuredItemIds},
                      ),
                child: Text(l10n.storefrontDiscardAction),
              ),
            if (pending?.requestId != null)
              TextButton.icon(
                key: const Key('storefront-featured-retry'),
                onPressed:
                    _saving ||
                        _contentBusy ||
                        _contentDirty ||
                        _mediaBusy ||
                        _stale ||
                        _homePending != null
                    ? null
                    : () => _onSaveFeatured(replay: pending),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.storefrontRetry),
              ),
          ],
        ),
        if (_dirty || _homeDirty)
          Text(
            l10n.storefrontFeaturedItemsSeparateEdits,
            key: const Key('storefront-featured-separate-edits'),
          ),
      ],
    ];
  }

  List<Widget> _homeContentEditor(
    AppLocalizations l10n,
    ThemeData theme,
    StorefrontProfile profile,
  ) {
    final pending = _homePending;
    final headline =
        _blankToNull(_heroHeadline.text) ??
        profile.tagline ??
        profile.displayName;
    final subline = _blankToNull(_heroSubline.text);
    final announcement = _blankToNull(_announcement.text);
    return [
      const Divider(height: RestoflowSpacing.xl),
      Text(l10n.storefrontHomeContentTitle, style: theme.textTheme.titleSmall),
      const SizedBox(height: RestoflowSpacing.xs),
      if (!_homeSupported)
        Text(
          l10n.storefrontHomeContentUnavailable,
          key: const Key('storefront-home-unsupported'),
        )
      else ...[
        Text(l10n.storefrontHomeContentHelp, style: theme.textTheme.bodySmall),
        const SizedBox(height: RestoflowSpacing.sm),
        _grid([
          _textField(
            key: const Key('storefront-home-headline'),
            controller: _heroHeadline,
            label: l10n.storefrontHeroHeadlineLabel,
            error:
                StorefrontProfile.isValidHomeContentValue(
                  'hero_headline',
                  _heroHeadline.text,
                )
                ? null
                : l10n.storefrontHomeContentInvalid,
          ),
          _textField(
            key: const Key('storefront-home-subline'),
            controller: _heroSubline,
            label: l10n.storefrontHeroSublineLabel,
            error:
                StorefrontProfile.isValidHomeContentValue(
                  'hero_subline',
                  _heroSubline.text,
                )
                ? null
                : l10n.storefrontHomeContentInvalid,
          ),
          _textField(
            key: const Key('storefront-home-announcement'),
            controller: _announcement,
            label: l10n.storefrontAnnouncementLabel,
            error:
                StorefrontProfile.isValidHomeContentValue(
                  'announcement_text',
                  _announcement.text,
                )
                ? null
                : l10n.storefrontHomeContentInvalid,
          ),
        ]),
        const SizedBox(height: RestoflowSpacing.sm),
        Wrap(
          spacing: RestoflowSpacing.sm,
          children: [
            FilledButton.icon(
              key: const Key('storefront-home-save'),
              onPressed:
                  !_busy &&
                      !_dirty &&
                      !_featuredDirty &&
                      _homeDirty &&
                      _homeValid
                  ? () => _onSaveHome()
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.storefrontHomeContentSaveAction),
            ),
            if (_homeDirty)
              TextButton(
                key: const Key('storefront-home-discard'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _heroHeadline.text = profile.heroHeadline ?? '';
                        _heroSubline.text = profile.heroSubline ?? '';
                        _announcement.text = profile.announcementText ?? '';
                      }),
                child: Text(l10n.storefrontDiscardAction),
              ),
            if (pending?.requestId != null)
              TextButton.icon(
                key: const Key('storefront-home-retry'),
                onPressed:
                    _saving ||
                        _contentBusy ||
                        _contentDirty ||
                        _mediaBusy ||
                        _stale
                    ? null
                    : () => _onSaveHome(replay: pending),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.storefrontRetry),
              ),
          ],
        ),
        if (_dirty && _homeDirty)
          Text(
            l10n.storefrontHomeContentSeparateEdits,
            key: const Key('storefront-home-separate-edits'),
          ),
        const SizedBox(height: RestoflowSpacing.sm),
        Text(
          l10n.storefrontHomeContentPreviewTitle,
          style: theme.textTheme.labelMedium,
        ),
        // Plain Text only: merchant copy is never interpreted as markup or a
        // link. Empty optional rows remain absent, including in this preview.
        Card(
          key: const Key('storefront-home-preview'),
          child: Padding(
            padding: const EdgeInsets.all(RestoflowSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  key: const Key('storefront-home-preview-headline'),
                ),
                if (subline != null)
                  Text(
                    subline,
                    key: const Key('storefront-home-preview-subline'),
                  ),
                if (announcement != null)
                  Text(
                    announcement,
                    key: const Key('storefront-home-preview-announcement'),
                  ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  Widget? _swatch(String text) {
    final hex = text.trim();
    if (!_colorShape.hasMatch(hex)) return null;
    final value = int.parse(hex.substring(1), radix: 16);
    return Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.sm),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Color(0xFF000000 | value),
          borderRadius: BorderRadius.circular(RestoflowRadii.sm),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }

  String _formatLocal(DateTime instant) {
    final l = instant.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-${_two(l.month)}-'
        '${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}';
  }

  Future<void> _onPickPause() async {
    final pick = widget.pickPauseUntil ?? showStorefrontInstantPicker;
    final picked = await pick(context, _pausedUntil);
    if (picked == null || !mounted) return;
    // A pause end at or before now would pause nothing (the public read
    // pauses only while `paused_until > now()`): refuse it, and say so.
    if (!picked.isAfter(DateTime.now())) {
      setState(() => _pausePickRefused = true);
      return;
    }
    setState(() {
      _pausedUntil = picked.toUtc();
      _pausePickRefused = false;
    });
  }

  /// Discard. After an UNKNOWN save outcome the cached profile may be older
  /// than the server (the lost write may have committed), so the authority is
  /// re-read instead; if that read fails nothing is discarded and the
  /// same-request "Try again" stays, because the outcome is still unknown.
  Future<void> _onDiscard() async {
    final pending = _banner?.retry;
    if (pending == null) {
      setState(() {
        _resetDraft();
        _banner = null;
      });
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final fresh = await _refreshAll();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _banner = fresh
          ? _Banner(l10n.storefrontDiscardReloaded, RestoflowTone.info)
          : _Banner(
              l10n.storefrontDiscardNotReloaded,
              RestoflowTone.warning,
              retry: pending,
            );
    });
  }

  /// After a write whose re-read failed: say that what is shown may be out of
  /// date, and offer a reload (editing stays locked until it succeeds).
  List<Widget> _staleView(AppLocalizations l10n, ThemeData theme) => [
    const SizedBox(height: RestoflowSpacing.sm),
    RestoflowNoticeBanner(
      key: const Key('storefront-stale'),
      tone: RestoflowTone.warning,
      body: _legacyBindingHold
          ? storefrontContentCopy(l10n, 'bindingChanged')
          : l10n.storefrontStaleNote,
    ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const Key('storefront-reload'),
        onPressed: _saving || _contentBusy || _legacyBindingHold || _mediaBusy
            ? null
            : _load,
        icon: const Icon(Icons.refresh),
        label: Text(l10n.storefrontReloadAction),
      ),
    ),
  ];

  List<Widget> _bannerView(AppLocalizations l10n, ThemeData theme) {
    final b = _banner!;
    final retry = b.retry;
    final retryEligible =
        retry != null && jsonEncode(_patch()) == jsonEncode(retry.draftPatch);
    return [
      const SizedBox(height: RestoflowSpacing.sm),
      RestoflowNoticeBanner(
        key: const Key('storefront-banner'),
        tone: b.tone,
        body: b.message,
      ),
      for (final code in b.blockers)
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
                  key: Key('storefront-banner-blocker-$code'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      if (retryEligible || b.offerUnpublishSave)
        Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
          child: Wrap(
            spacing: RestoflowSpacing.sm,
            runSpacing: RestoflowSpacing.xs,
            children: [
              if (retryEligible)
                TextButton.icon(
                  key: const Key('storefront-save-retry'),
                  onPressed: _busy ? null : () => _retrySave(retry),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.storefrontRetry),
                ),
              if (b.offerUnpublishSave)
                FilledButton.tonal(
                  key: const Key('storefront-unpublish-save'),
                  onPressed: _busy ? null : _onUnpublishAndSave,
                  child: Text(l10n.storefrontUnpublishAndSaveAction),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _publishArea(
    AppLocalizations l10n,
    ThemeData theme,
    StorefrontProfile profile,
    StorefrontDerived derived,
    bool dirty,
  ) {
    final published = profile.isPublished;
    // C10 (OQ-1): the database check accepts saved hours this editor cannot
    // read, so the SERVER's blockers cannot see them: the card adds its own
    // blocker — Publish stays disabled and "all requirements met" is never
    // claimed until the hours are repaired and saved.
    final hoursUnreadable = profile.openingHours.hasUnreadableEntries;
    // Q-038: SAVED hours with touching windows (written before this check, or
    // through the RPC directly) would announce a wrong closing time; the
    // server's blockers cannot see them, so the card adds its own.
    final hoursTouching =
        !hoursUnreadable && profile.openingHours.hasTouchingWindows;
    final blockers = [
      ...derived.publishBlockers,
      if (hoursUnreadable) kStorefrontClientBlockerHoursUnreadable,
      if (hoursTouching) kStorefrontClientBlockerHoursTouching,
    ];
    final canPublish = !published && blockers.isEmpty && !dirty && !_busy;
    // C11 (OQ-3 / Q-035 / DASH-3 / DASH-5): the status is the SERVER's
    // published flag AND what its public read does with the saved profile's
    // blockers. It never says "public": published is a setting, and the
    // availability note says what it does not guarantee (a suspended
    // organization / restaurant / branch, other reasons, and exposure of the
    // public address are decided elsewhere).
    final page = storefrontPublishedPageOf(derived.publishBlockers);
    final (status, tone, icon) = !published
        ? (
            l10n.storefrontUnpublishedStatus,
            RestoflowTone.neutral,
            Icons.public_off,
          )
        : switch ((hoursUnreadable || hoursTouching) &&
                  page == StorefrontPublishedPage.online
              // Served, but with hours it cannot state correctly.
              ? StorefrontPublishedPage.incomplete
              : page) {
            StorefrontPublishedPage.online => (
              l10n.storefrontPublishedStatus,
              RestoflowTone.success,
              Icons.check_circle_outline,
            ),
            StorefrontPublishedPage.incomplete => (
              l10n.storefrontPublishedIncompleteStatus,
              RestoflowTone.warning,
              Icons.error_outline,
            ),
            StorefrontPublishedPage.offline => (
              l10n.storefrontPublishedOfflineStatus,
              RestoflowTone.warning,
              Icons.public_off,
            ),
            StorefrontPublishedPage.unknown => (
              l10n.storefrontPublishedUncheckedStatus,
              RestoflowTone.warning,
              Icons.warning_amber_outlined,
            ),
          };
    final statusStyle = tone.styleOf(theme);
    return [
      Text(
        l10n.storefrontStatusLabel,
        key: const Key('storefront-status-label'),
        style: theme.textTheme.labelMedium,
      ),
      const SizedBox(height: RestoflowSpacing.xs),
      Row(
        children: [
          Icon(icon, size: 20, color: statusStyle.accent),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              status,
              key: const Key('storefront-published-status'),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
      if (published)
        Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
          child: Text(
            l10n.storefrontPublishedAvailabilityNote,
            key: const Key('storefront-availability-note'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: RestoflowSpacing.sm),
      if (blockers.isEmpty)
        Text(
          published
              ? l10n.storefrontPublishedChecksMet
              : l10n.storefrontReadyToPublish,
          key: const Key('storefront-ready'),
          style: theme.textTheme.bodyMedium,
        )
      else ...[
        Text(
          published
              ? l10n.storefrontBlockersTitlePublished
              : l10n.storefrontBlockersTitle,
          key: const Key('storefront-blockers-title'),
          style: theme.textTheme.labelLarge,
        ),
        for (final code in blockers)
          Padding(
            padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: RestoflowTone.warning.styleOf(theme).accent,
                ),
                const SizedBox(width: RestoflowSpacing.xs),
                Expanded(
                  child: Text(
                    storefrontBlockerLabel(l10n, code),
                    key: Key('storefront-blocker-$code'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
      Padding(
        padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
        child: Text(
          l10n.storefrontBlockersSavedNote,
          key: const Key('storefront-blockers-saved-note'),
          style: theme.textTheme.bodySmall,
        ),
      ),
      const SizedBox(height: RestoflowSpacing.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: published
            ? OutlinedButton.icon(
                key: const Key('storefront-unpublish'),
                onPressed: !dirty && !_busy
                    ? () => _onPublishToggle(false)
                    : null,
                icon: const Icon(Icons.public_off),
                label: Text(l10n.storefrontUnpublishAction),
              )
            : FilledButton.icon(
                key: const Key('storefront-publish'),
                onPressed: canPublish ? () => _onPublishToggle(true) : null,
                icon: const Icon(Icons.public),
                label: Text(l10n.storefrontPublishAction),
              ),
      ),
      if (!published && dirty)
        Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
          child: Text(
            l10n.storefrontPublishNeedsSave,
            key: const Key('storefront-publish-needs-save'),
            style: theme.textTheme.bodySmall,
          ),
        )
      else if (!published && blockers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
          child: Text(
            l10n.storefrontPublishNeedsBlockers,
            key: const Key('storefront-publish-needs-blockers'),
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }

  List<Widget> _mediaArea(
    AppLocalizations l10n,
    ThemeData theme,
    StorefrontProfile profile,
    bool dirty,
  ) {
    final seams = widget.seams!;
    final publisher = seams.publisher;
    return [
      Text(l10n.storefrontMediaTitle, style: theme.textTheme.titleSmall),
      const SizedBox(height: RestoflowSpacing.xs),
      if (publisher == null)
        Text(
          widget.isDemo
              ? l10n.storefrontDemoNote
              : l10n.storefrontMediaUnavailable,
          key: const Key('storefront-media-unavailable'),
          style: theme.textTheme.bodySmall,
        )
      else ...[
        if (dirty)
          Padding(
            padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
            child: Text(
              l10n.storefrontMediaSaveFirst,
              key: const Key('storefront-media-save-first'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        StorefrontItemImages(
          publisher: publisher,
          sources: _sources,
          reloadSources: _reloadSources,
          onRefresh: () => _refreshAll(reloadSources: true),
          onBusyChanged: (busy) {
            if (mounted) setState(() => _mediaBusy = busy);
          },
          nonce: widget.nonce,
          enabled:
              !dirty &&
              !_saving &&
              !_contentBusy &&
              !_contentDirty &&
              !_mediaBusy &&
              !_stale,
        ),
        for (final slot in StorefrontSlot.values) ...[
          StorefrontMediaSlot(
            key: ValueKey('storefront-slot-widget-${slot.wire}'),
            slot: slot,
            profile: profile,
            media: _media,
            sources: _sources,
            publisher: publisher,
            mediaRepository: seams.mediaRepository,
            publicUrlFor: seams.publicUrlFor,
            enabled:
                !dirty &&
                !_saving &&
                !_contentBusy &&
                !_contentDirty &&
                !_mediaBusy &&
                !_stale,
            nonce: widget.nonce,
            refusedReceiptLogo: _refusedReceiptLogo,
            onReceiptLogoRefused: (refused) {
              if (mounted) setState(() => _refusedReceiptLogo = refused);
            },
            onAssign: _assignSlot,
            reloadSources: _reloadSources,
            onRefresh: ({bool reloadSources = false}) =>
                _refreshAll(reloadSources: reloadSources),
            onBusyChanged: (busy) {
              if (mounted) setState(() => _mediaBusy = busy);
            },
          ),
          const SizedBox(height: RestoflowSpacing.sm),
        ],
      ],
    ];
  }
}
