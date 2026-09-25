import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_dashboard/src/admin/supabase_settings_repository.dart';
import 'package:restoflow_dashboard/src/admin/timezone_catalog.dart';
import 'package:restoflow_dashboard/src/storefront/opening_hours_editor.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_copy.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_section.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_sources.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// STOREFRONT-PUBLISH-001 — the Settings "Storefront" card: read before edit,
/// the confirmed create with a PERMANENT slug, changed-keys-only CAS saves,
/// conflict reloads, the server's blockers and published state (never
/// optimistic), the typed refusals, and no ordering/delivery control.
const _rest = '22222222-2222-4222-8222-222222222222';
const _branchA = '33333333-3333-4333-8333-333333333333';
const _branchB = '44444444-4444-4444-8444-444444444444';
const _retryId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

Map<String, Object?> _profileJson({
  String displayName = 'Cafe Roma',
  bool published = false,
  int version = 1,
  Map<String, Object?> openingHours = const {
    'weekly': <Object?>[],
    'exceptions': <Object?>[],
  },
}) => {
  'restaurant_id': _rest,
  'storefront_branch_id': _branchA,
  'slug': 'cafe-roma',
  'display_name': displayName,
  'tagline': null,
  'public_city': null,
  'public_address': null,
  'public_phone': null,
  'primary_color': '#13322a',
  'accent_color': '#e07b2c',
  'visual_preset': 'dark',
  'locale_default': 'ar',
  'card_mode': 'list',
  'motion': 'full',
  'pickup_enabled': true,
  'paused_until': null,
  'pause_reason': null,
  'opening_hours': openingHours,
  'logo_media_id': null,
  'hero_media_id': null,
  'is_published': published,
  'version': version,
};

StorefrontProfileRead _readOf(
  Map<String, Object?>? profile, {
  List<String> blockers = const [],
  String? timezone = 'Asia/Jerusalem',
}) => StorefrontProfileRead.ok(
  exists: profile != null,
  version: profile == null ? 0 : profile['version']! as int,
  profile: profile == null ? null : StorefrontProfile.fromJson(profile),
  derived: StorefrontDerived.fromJson({
    'timezone': timezone,
    'currency_code': 'ILS',
    'tax': null,
    'publish_ready': blockers.isEmpty,
    'publish_blockers': blockers,
    'media_prefix': 'prefix0',
  }),
);

class _Save {
  const _Save(this.expectedVersion, this.patch, this.requestId);

  final int expectedVersion;
  final Map<String, Object?> patch;
  final String? requestId;
}

/// A tiny in-memory stand-in for the CAS writer: a matching version applies
/// the patch and bumps the version; a stale one conflicts. Scripted
/// [saveOverrides] / [readOverrides] are answered first (without applying).
class _FakeProfileRepo implements StorefrontProfileRepository {
  _FakeProfileRepo({
    Map<String, Object?>? profile,
    this.blockers = const [],
    this.timezone = 'Asia/Jerusalem',
  }) : profile = profile == null ? null : Map.of(profile);

  Map<String, Object?>? profile;
  List<String> blockers;

  /// `derived.timezone` of the SAVED branch.
  String? timezone;
  final List<StorefrontProfileRead> readOverrides = [];
  final List<StorefrontWriteResult> saveOverrides = [];
  final List<_Save> saves = [];
  int reads = 0;

  @override
  Future<StorefrontProfileRead> read() async {
    reads++;
    if (readOverrides.isNotEmpty) return readOverrides.removeAt(0);
    return _readOf(profile, blockers: blockers, timezone: timezone);
  }

  @override
  Future<StorefrontWriteResult> save({
    required int expectedVersion,
    required Map<String, Object?> patch,
    String? requestId,
  }) async {
    saves.add(_Save(expectedVersion, Map.of(patch), requestId));
    final id =
        requestId ??
        'aaaaaaaa-aaaa-4aaa-8aaa-${'${saves.length}'.padLeft(12, '0')}';
    if (saveOverrides.isNotEmpty) return saveOverrides.removeAt(0);
    final current = profile?['version'] as int? ?? 0;
    if (current != expectedVersion) {
      return StorefrontWriteResult(
        StorefrontWriteStatus.conflict,
        requestId: id,
        version: current,
      );
    }
    final next = profile == null
        ? _profileJson(version: 0)
        : Map<String, Object?>.of(profile!);
    patch.forEach((k, v) => next[k] = v);
    next['version'] = current + 1;
    profile = next;
    return StorefrontWriteResult(
      StorefrontWriteStatus.ok,
      requestId: id,
      version: current + 1,
    );
  }
}

class _FakeMediaRepo implements StorefrontMediaRepository {
  int lists = 0;

  @override
  Future<StorefrontMediaList> list() async {
    lists++;
    return const StorefrontMediaList.ok(
      mediaPrefix: 'prefix0',
      media: <StorefrontMediaRow>[],
    );
  }

  @override
  Future<StorefrontMediaActionResult> retract(
    String mediaId, {
    String? requestId,
  }) => throw StateError('not used here');

  @override
  Future<StorefrontMediaActionResult> cancel(
    String mediaId, {
    String? requestId,
  }) => throw StateError('not used here');
}

class _FakeBranches implements StorefrontBranchSource {
  @override
  Future<List<StorefrontBranchOption>?> list() async => const [
    StorefrontBranchOption(
      id: _branchA,
      name: 'Downtown',
      timezone: 'Asia/Jerusalem',
    ),
    StorefrontBranchOption(id: _branchB, name: 'Harbor'),
  ];
}

/// Branch A has its OWN zone; branch B has none, so the server would use the
/// restaurant's zone for it.
class _ZonedBranches implements StorefrontBranchSource {
  @override
  Future<List<StorefrontBranchOption>?> list() async => const [
    StorefrontBranchOption(
      id: _branchA,
      name: 'Downtown',
      timezone: 'Europe/London',
      restaurantTimezone: 'Asia/Jerusalem',
    ),
    StorefrontBranchOption(
      id: _branchB,
      name: 'Harbor',
      restaurantTimezone: 'Asia/Jerusalem',
    ),
  ];
}

class _FakeSources implements StorefrontSourceCatalog {
  @override
  Future<StorefrontSourceOptions> load() async =>
      const StorefrontSourceOptions();
}

Future<AppLocalizations> _l10n([String code = 'en']) =>
    AppLocalizations.delegate.load(Locale(code));

StorefrontEditorSeams _seams(
  StorefrontProfileRepository repo, {
  String identity = 'm-1|org-1|$_rest|manager',
  StorefrontBranchSource? branches,
}) => StorefrontEditorSeams(
  scopeIdentity: identity,
  profileRepository: repo,
  mediaRepository: _FakeMediaRepo(),
  branchSource: branches ?? _FakeBranches(),
  sourceCatalog: _FakeSources(),
);

/// Branch B is SUSPENDED (as `list_org_structure` serves it).
class _SuspendedBranches implements StorefrontBranchSource {
  @override
  Future<List<StorefrontBranchOption>?> list() async => const [
    StorefrontBranchOption(
      id: _branchA,
      name: 'Downtown',
      timezone: 'Asia/Jerusalem',
      status: 'active',
    ),
    StorefrontBranchOption(id: _branchB, name: 'Harbor', status: 'suspended'),
  ];
}

/// A profile read that waits for [gate] (an identity switch while it is in
/// flight must never land in the new editor).
class _GatedRepo extends _FakeProfileRepo {
  _GatedRepo({super.profile});

  final Completer<void> gate = Completer<void>();

  @override
  Future<StorefrontProfileRead> read() async {
    await gate.future;
    return super.read();
  }
}

/// The owner-only editable Settings section (time zone picker etc.) sits
/// ABOVE the Storefront card — in the lazy Settings ListView the card then
/// starts far below the first screen.
class _FakeSettings implements SettingsRepository {
  @override
  Future<SettingsPrefill?> readPrefill() async => null;

  @override
  Future<List<TimezoneOption>> loadTimezones() async => const [
    TimezoneOption(id: 'Asia/Jerusalem', offsetMinutes: 180),
  ];

  @override
  Future<SettingsWrite> saveBranch({
    required String name,
    String? receiptPrefix,
    required String status,
    String? timezone,
  }) => throw StateError('not used here');

  @override
  Future<SettingsWrite> saveRestaurant({
    required String name,
    required String status,
  }) => throw StateError('not used here');

  @override
  Future<SettingsWrite> saveOperatingCurrency({required String currencyCode}) =>
      throw StateError('not used here');
}

Future<void> _pump(
  WidgetTester tester,
  Widget section, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: Locale(locale),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: section,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, Key dropdown, String label) async {
  await _tap(tester, find.byKey(dropdown));
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, Key key) {
  final w = tester.widget(find.byKey(key));
  if (w is ButtonStyleButton) return w.onPressed != null;
  throw StateError('not a button: $w');
}

/// DASH-V-2: a PUBLISHED card shows [status] (never the clean "Published."
/// and never a "public" claim) AND the availability note right under it.
void _expectPublishedWithNote(
  WidgetTester tester,
  AppLocalizations l10n, {
  required String status,
  required String reason,
}) {
  final statusFinder = find.byKey(const Key('storefront-published-status'));
  final note = find.byKey(const Key('storefront-availability-note'));
  expect(tester.widget<Text>(statusFinder).data, status, reason: reason);
  expect(status, isNot(l10n.storefrontPublishedStatus), reason: reason);
  expect(status.toLowerCase(), isNot(contains('public')), reason: reason);
  expect(find.text(l10n.storefrontPublishedStatus), findsNothing);
  expect(find.text(l10n.storefrontUnpublishedStatus), findsNothing);
  expect(note, findsOneWidget, reason: reason);
  expect(
    tester.widget<Text>(note).data,
    l10n.storefrontPublishedAvailabilityNote,
    reason: reason,
  );
  expect(
    tester.getTopLeft(note).dy,
    greaterThan(tester.getTopLeft(statusFinder).dy),
    reason: '$reason: the note sits under the status',
  );
}

void main() {
  group('read before edit', () {
    testWidgets('unwired: an honest note, no fields', (tester) async {
      final l10n = await _l10n();
      await _pump(tester, const StorefrontSection(seams: null));
      expect(find.text(l10n.storefrontUnavailableNote), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await _pump(tester, const StorefrontSection(seams: null, isDemo: true));
      expect(find.text(l10n.storefrontDemoNote), findsOneWidget);
    });

    testWidgets('denied: the honest note and NO fields', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson())
        ..readOverrides.add(const StorefrontProfileRead.denied());
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(find.byKey(const Key('storefront-denied')), findsOneWidget);
      expect(find.text(l10n.storefrontDeniedNote), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('storefront-save')), findsNothing);
      expect(find.byKey(const Key('storefront-publish')), findsNothing);
      expect(repo.saves, isEmpty);
    });

    testWidgets('unavailable / malformed: retry, then the editor', (
      tester,
    ) async {
      final repo = _FakeProfileRepo(profile: _profileJson())
        ..readOverrides.addAll(const [
          StorefrontProfileRead.unavailable(code: '42501'),
          StorefrontProfileRead.malformed(
            StorefrontDecodeException('profile.slug'),
          ),
        ]);
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(find.byKey(const Key('storefront-load-failed')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await _tap(tester, find.byKey(const Key('storefront-retry')));
      expect(find.byKey(const Key('storefront-load-failed')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('storefront-retry')));
      expect(find.byKey(const Key('storefront-slug-readonly')), findsOneWidget);
      expect(repo.reads, 3);
    });
  });

  group('create', () {
    testWidgets('requires branch + slug; the first save confirms permanence', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo();
      await _pump(
        tester,
        StorefrontSection(seams: _seams(repo), defaultDisplayName: 'Cafe Roma'),
      );
      expect(find.text(l10n.storefrontCreateIntro), findsOneWidget);
      expect(
        find.byKey(const Key('storefront-media-needs-profile')),
        findsOneWidget,
      );
      const save = Key('storefront-save');
      expect(_enabled(tester, save), isFalse);

      await tester.enterText(
        find.byKey(const Key('storefront-slug')),
        'cafe-roma',
      );
      await tester.pumpAndSettle();
      expect(_enabled(tester, save), isFalse, reason: 'no branch yet');

      await _choose(tester, const Key('storefront-branch'), 'Harbor');
      expect(_enabled(tester, save), isTrue);

      // Client-side grammar: shape, reserved words.
      for (final bad in ['Cafe Roma', 'ab', 'api', 'cafe--roma']) {
        await tester.enterText(find.byKey(const Key('storefront-slug')), bad);
        await tester.pumpAndSettle();
        expect(_enabled(tester, save), isFalse, reason: bad);
        expect(find.text(l10n.storefrontSlugInvalid), findsOneWidget);
      }
      await tester.enterText(
        find.byKey(const Key('storefront-slug')),
        'cafe-roma',
      );
      await tester.pumpAndSettle();

      // Cancel the permanence dialog: nothing is sent.
      await _tap(tester, find.byKey(save));
      expect(
        find.byKey(const Key('storefront-create-confirm')),
        findsOneWidget,
      );
      expect(find.text(l10n.storefrontCreateConfirmBody), findsOneWidget);
      expect(find.text('/s/cafe-roma'), findsOneWidget);
      await tester.tap(find.text(l10n.adminCancel));
      await tester.pumpAndSettle();
      expect(repo.saves, isEmpty);

      await _tap(tester, find.byKey(save));
      await tester.tap(
        find.byKey(const Key('storefront-create-confirm-action')),
      );
      await tester.pumpAndSettle();
      expect(repo.saves, hasLength(1));
      expect(repo.saves.single.expectedVersion, 0);
      expect(repo.saves.single.patch, {
        'slug': 'cafe-roma',
        'storefront_branch_id': _branchB,
        'display_name': 'Cafe Roma',
      });
      // Re-read after the save: the slug is now read-only text.
      expect(find.byKey(const Key('storefront-slug')), findsNothing);
      expect(find.byKey(const Key('storefront-slug-readonly')), findsOneWidget);
      expect(find.text(l10n.storefrontSaved), findsOneWidget);
    });
  });

  group('create (unknown outcome)', () {
    testWidgets('an uncertain create offers Try again with the SAME request', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo()
        ..saveOverrides.add(
          const StorefrontWriteResult(
            StorefrontWriteStatus.uncertain,
            requestId: _retryId,
          ),
        );
      await _pump(
        tester,
        StorefrontSection(seams: _seams(repo), defaultDisplayName: 'Cafe Roma'),
      );
      await tester.enterText(
        find.byKey(const Key('storefront-slug')),
        'cafe-roma',
      );
      await tester.pumpAndSettle();
      await _choose(tester, const Key('storefront-branch'), 'Downtown');
      await _tap(tester, find.byKey(const Key('storefront-save')));
      await tester.tap(
        find.byKey(const Key('storefront-create-confirm-action')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.storefrontErrorUncertain), findsOneWidget);
      await _tap(tester, find.byKey(const Key('storefront-save-retry')));
      expect(repo.saves, hasLength(2));
      expect(repo.saves[1].requestId, _retryId);
      expect(repo.saves[1].expectedVersion, 0);
      expect(repo.saves[1].patch, repo.saves[0].patch);
      expect(find.byKey(const Key('storefront-slug-readonly')), findsOneWidget);
    });
  });

  group('after creation', () {
    testWidgets('the slug is read-only and the path is plain LTR text', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      final slug = tester.widget<Text>(
        find.byKey(const Key('storefront-slug-readonly')),
      );
      expect(slug.data, 'cafe-roma');
      expect(find.text(l10n.storefrontSlugPermanentNote), findsOneWidget);
      final path = find.byKey(const Key('storefront-path'));
      expect(tester.widget<Text>(path).data, '/s/cafe-roma');
      expect(tester.widget<Text>(path).textDirection, TextDirection.ltr);
      // NOT a link: nothing tappable wraps it.
      expect(
        find.ancestor(of: path, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.ancestor(of: path, matching: find.byType(GestureDetector)),
        findsNothing,
      );
      expect(find.byKey(const Key('storefront-slug')), findsNothing);
    });

    testWidgets('help texts: default language, pickup and pause (truthful)', (
      tester,
    ) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(_FakeProfileRepo(profile: _profileJson())),
        ),
      );
      expect(find.text(l10n.storefrontLocaleHelp), findsOneWidget);
      expect(find.text(l10n.storefrontPickupHelp), findsOneWidget);
      expect(find.text(l10n.storefrontPauseHelp), findsOneWidget);
      expect(find.byKey(const Key('storefront-pause-zone')), findsOneWidget);
      expect(find.text(l10n.storefrontBlockersSavedNote), findsOneWidget);
    });

    testWidgets('no ordering / delivery control anywhere', (tester) async {
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(_FakeProfileRepo(profile: _profileJson())),
        ),
      );
      final keyed = find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> &&
            (k.value.contains('ordering') || k.value.contains('delivery'));
      });
      expect(keyed, findsNothing);
      // The ONLY switch is pickup (browse-only release).
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byKey(const Key('storefront-pickup')), findsOneWidget);
    });

    testWidgets('Save sends ONLY the changed keys with the current version', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson(version: 4));
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(_enabled(tester, const Key('storefront-save')), isFalse);

      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        '  Fresh pasta  ',
      );
      await _choose(
        tester,
        const Key('storefront-motion'),
        l10n.storefrontMotionLively,
      );
      await tester.enterText(
        find.byKey(const Key('storefront-primary-color')),
        '#1A2B3C',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('storefront-unsaved')), findsOneWidget);

      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.single.expectedVersion, 4);
      expect(repo.saves.single.patch, {
        'tagline': 'Fresh pasta',
        'primary_color': '#1a2b3c',
        'motion': 'lively',
      });
      expect(find.text(l10n.storefrontSaved), findsOneWidget);
      // Re-read: the saved values are the new baseline (nothing dirty).
      expect(find.byKey(const Key('storefront-unsaved')), findsNothing);
      expect(repo.reads, greaterThanOrEqualTo(2));
    });

    testWidgets('DASH-6: a display-name-only save sends exactly that key — '
        'never the (immutable) slug', (tester) async {
      final repo = _FakeProfileRepo(profile: _profileJson(version: 3));
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await tester.enterText(
        find.byKey(const Key('storefront-display-name')),
        '  Roma Two  ',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      final save = repo.saves.single;
      expect(save.expectedVersion, 3);
      expect(save.patch, {'display_name': 'Roma Two'});
      expect(save.patch.containsKey('slug'), isFalse);
      expect(repo.profile!['slug'], 'cafe-roma');
    });

    testWidgets('a blank optional field is sent as null', (tester) async {
      final repo = _FakeProfileRepo(
        profile: {..._profileJson(), 'public_city': 'Haifa'},
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await tester.enterText(find.byKey(const Key('storefront-city')), '   ');
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.single.patch, {'public_city': null});
    });

    testWidgets('client-side mirrors block Save (phone, colour, length)', (
      tester,
    ) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(_FakeProfileRepo(profile: _profileJson())),
        ),
      );
      const save = Key('storefront-save');
      await tester.enterText(find.byKey(const Key('storefront-phone')), '12');
      await tester.pumpAndSettle();
      expect(find.text(l10n.storefrontPhoneInvalid), findsOneWidget);
      expect(_enabled(tester, save), isFalse);
      for (final ok in ['+972501234567', '050-123-4567', '03 123 4567']) {
        await tester.enterText(find.byKey(const Key('storefront-phone')), ok);
        await tester.pumpAndSettle();
        expect(_enabled(tester, save), isTrue, reason: ok);
      }
      await tester.enterText(
        find.byKey(const Key('storefront-accent-color')),
        'orange',
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.storefrontColorInvalid), findsOneWidget);
      expect(_enabled(tester, save), isFalse);
      await tester.enterText(
        find.byKey(const Key('storefront-accent-color')),
        '#e07b2c',
      );
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'x' * 91,
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.storefrontTooLong(90)), findsOneWidget);
      expect(_enabled(tester, save), isFalse);
    });

    testWidgets('the primary colour shows the truthful contrast warning', (
      tester,
    ) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(_FakeProfileRepo(profile: _profileJson())),
        ),
      );
      const warning = Key('storefront-primary-contrast-warning');
      expect(find.byKey(warning), findsNothing, reason: '#13322a supported');
      for (final hex in ['#e07b2c', '#ffffff']) {
        await tester.enterText(
          find.byKey(const Key('storefront-primary-color')),
          hex,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(warning), findsOneWidget, reason: hex);
        expect(
          find.text(l10n.storefrontPrimaryContrastWarning),
          findsOneWidget,
        );
      }
    });

    testWidgets('pause: set (RFC 3339 with offset on the wire) and clear', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      // Always in the future (a past pause end is refused when picked).
      final local = DateTime(DateTime.now().year + 1, 10, 1, 18, 0);
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(repo),
          pickPauseUntil: (context, initial) async => local,
        ),
      );
      await _tap(tester, find.byKey(const Key('storefront-pause-set')));
      expect(find.text('${local.year}-10-01 18:00'), findsOneWidget);
      expect(find.text(l10n.storefrontPausedUntilLabel), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('storefront-pause-reason')),
        'Staff training',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      final patch = repo.saves.single.patch;
      final wire = patch['paused_until']! as String;
      expect(isStorefrontInstantText(wire), isTrue, reason: wire);
      expect(wire, isNot(endsWith('Z')));
      expect(DateTime.parse(wire).isAtSameMomentAs(local), isTrue);
      expect(patch['pause_reason'], 'Staff training');

      await _tap(tester, find.byKey(const Key('storefront-pause-clear')));
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.last.patch, {'paused_until': null});
    });

    testWidgets('a pause end at or before now is refused when picked', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(repo),
          pickPauseUntil: (context, initial) async =>
              DateTime.now().subtract(const Duration(hours: 4)),
        ),
      );
      await _tap(tester, find.byKey(const Key('storefront-pause-set')));
      expect(find.byKey(const Key('storefront-pause-past')), findsOneWidget);
      expect(find.text(l10n.storefrontPausePast), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('storefront-paused-until-value')),
            )
            .data,
        l10n.storefrontNotPaused,
      );
      expect(find.byKey(const Key('storefront-unsaved')), findsNothing);
      expect(_enabled(tester, const Key('storefront-save')), isFalse);
      expect(repo.saves, isEmpty);
    });

    testWidgets('a saved pause end in the past reads "Pause ended at", never '
        '"Paused until"', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(
        profile: {..._profileJson(), 'paused_until': '2020-01-01T10:00:00Z'},
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('storefront-paused-until-label')),
            )
            .data,
        l10n.storefrontPauseEndedLabel,
      );
      expect(find.text(l10n.storefrontPausedUntilLabel), findsNothing);
      // It is the SAVED value, not an edit: no error, nothing to save.
      expect(find.byKey(const Key('storefront-pause-past')), findsNothing);
      expect(find.byKey(const Key('storefront-unsaved')), findsNothing);
      // It can still be cleared.
      await _tap(tester, find.byKey(const Key('storefront-pause-clear')));
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.single.patch, {'paused_until': null});
    });

    testWidgets('an unsaved pause end that passes before Save is refused at '
        'Save', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(repo),
          pickPauseUntil: (context, initial) async =>
              DateTime.now().add(const Duration(milliseconds: 300)),
        ),
      );
      await _tap(tester, find.byKey(const Key('storefront-pause-set')));
      expect(find.text(l10n.storefrontPausedUntilLabel), findsOneWidget);
      expect(_enabled(tester, const Key('storefront-save')), isTrue);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      // The button was built before the time passed: the press re-checks.
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves, isEmpty);
      expect(find.byKey(const Key('storefront-pause-past')), findsOneWidget);
      expect(find.text(l10n.storefrontPauseEndedLabel), findsOneWidget);
      expect(_enabled(tester, const Key('storefront-save')), isFalse);
    });

    testWidgets('opening hours edits are sent in the validator grammar', (
      tester,
    ) async {
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await _tap(tester, find.byKey(const Key('storefront-hours-add-0')));
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.single.patch, {
        'opening_hours': {
          'weekly': [
            {'dow': 0, 'open': '09:00', 'close': '17:00'},
          ],
          'exceptions': <Object?>[],
        },
      });
    });

    testWidgets('invalid hours block Save until fixed', (tester) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(_FakeProfileRepo(profile: _profileJson())),
          pickTime: (context, initial) async => '09:00',
        ),
      );
      await _tap(tester, find.byKey(const Key('storefront-hours-add-3')));
      await _tap(tester, find.byKey(const Key('storefront-hours-close-3-0')));
      expect(find.text(l10n.storefrontHoursInvalid), findsOneWidget);
      expect(_enabled(tester, const Key('storefront-save')), isFalse);
    });
  });

  group('hours edge cases', () {
    testWidgets('a draft branch without its own zone shows the RESTAURANT '
        'zone (the server rule), never the saved branch\'s zone', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(
        profile: _profileJson(),
        timezone: 'Europe/London',
      );
      await _pump(
        tester,
        StorefrontSection(seams: _seams(repo, branches: _ZonedBranches())),
      );
      expect(
        find.text(l10n.storefrontHoursTimezone('Europe/London')),
        findsOneWidget,
      );
      await _choose(tester, const Key('storefront-branch'), 'Harbor');
      expect(
        find.text(l10n.storefrontHoursTimezone('Asia/Jerusalem')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.storefrontHoursTimezone('Europe/London')),
        findsNothing,
      );
    });

    testWidgets('stored hours with incomplete entries (accepted by the '
        'database check) load flagged, and can be replaced', (tester) async {
      final repo = _FakeProfileRepo(
        profile: _profileJson(
          openingHours: {
            'weekly': [
              {'dow': 1, 'open': '09:00'},
              {'dow': 2, 'open': '10:00', 'close': '14:00'},
            ],
          },
        ),
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      // The card loads (it used to fail the whole read, for good).
      expect(find.byKey(const Key('storefront-load-failed')), findsNothing);
      expect(
        find.byKey(const Key('storefront-hours-unreadable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('storefront-unsaved')), findsNothing);
      await _tap(tester, find.byKey(const Key('storefront-hours-repair')));
      expect(find.byKey(const Key('storefront-unsaved')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.single.patch, {
        'opening_hours': {
          'weekly': [
            {'dow': 2, 'open': '10:00', 'close': '14:00'},
          ],
          'exceptions': <Object?>[],
        },
      });
      // The clean re-read clears the note.
      expect(
        find.byKey(const Key('storefront-hours-unreadable')),
        findsNothing,
      );
    });

    testWidgets('C10 / OQ-1: unreadable AUTHORITATIVE hours ({"weekly":[{}]}) '
        'show an explicit error and disable Publish; the stored value is '
        'never replaced by empty/default hours until an explicit repair is '
        'saved', (tester) async {
      final l10n = await _l10n();
      const unreadable = {
        'weekly': [<String, Object?>{}],
      };
      final repo = _FakeProfileRepo(
        profile: _profileJson(openingHours: unreadable),
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      // An explicit ERROR (error colour), not a soft note.
      final error = find.byKey(const Key('storefront-hours-unreadable'));
      expect(error, findsOneWidget);
      expect(tester.widget<Text>(error).data, l10n.storefrontHoursUnreadable);
      expect(
        tester.widget<Text>(error).style?.color,
        Theme.of(tester.element(error)).colorScheme.error,
      );
      // The server's blockers are empty (the database check accepts the
      // value), but Publish is disabled and nothing claims "ready".
      expect(_enabled(tester, const Key('storefront-publish')), isFalse);
      expect(find.byKey(const Key('storefront-ready')), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('storefront-blocker-hours_unreadable')),
            )
            .data,
        l10n.storefrontBlockerHoursUnreadable,
      );
      // No hours edit can silently replace it: the editor is locked.
      for (final k in ['storefront-hours-add-1', 'storefront-hours-add-6']) {
        expect(
          tester.widget<TextButton>(find.byKey(Key(k))).onPressed,
          isNull,
          reason: k,
        );
      }
      // Another field's save leaves the stored hours exactly as they are.
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Fresh',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.single.patch, {'tagline': 'Fresh'});
      expect(repo.profile!['opening_hours'], unreadable);
      expect(error, findsOneWidget);
      expect(_enabled(tester, const Key('storefront-publish')), isFalse);

      // The explicit repair: the editor unlocks, the draft is dirty.
      await _tap(tester, find.byKey(const Key('storefront-hours-repair')));
      expect(
        find.byKey(const Key('storefront-hours-repair-pending')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('storefront-unsaved')), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('storefront-hours-add-1')))
            .onPressed,
        isNotNull,
      );
      await _tap(tester, find.byKey(const Key('storefront-hours-add-1')));
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.last.patch, {
        'opening_hours': {
          'weekly': [
            {'dow': 1, 'open': '09:00', 'close': '17:00'},
          ],
          'exceptions': <Object?>[],
        },
      });
      expect(error, findsNothing);
      expect(find.byKey(const Key('storefront-ready')), findsOneWidget);
      expect(_enabled(tester, const Key('storefront-publish')), isTrue);
    });

    testWidgets('Q-038: touching periods in the DRAFT disable Save; merging '
        'them into one continuous period re-enables it', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Fresh',
      );
      await tester.pumpAndSettle();
      expect(_enabled(tester, const Key('storefront-save')), isTrue);
      // Build 09:00-12:00 + 12:00-23:00 through the section's own seam.
      final editor = tester.widget<OpeningHoursEditor>(
        find.byKey(const Key('storefront-hours')),
      );
      editor.onChanged(
        const OpeningHours(
          weekly: [
            WeeklyWindow(dow: 1, open: '09:00', close: '12:00'),
            WeeklyWindow(dow: 1, open: '12:00', close: '23:00'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('storefront-hours-touching-1')))
            .data,
        l10n.storefrontHoursTouchingError,
      );
      expect(_enabled(tester, const Key('storefront-save')), isFalse);
      expect(repo.saves, isEmpty);
      // 12:01 is a separate period: allowed.
      editor.onChanged(
        const OpeningHours(
          weekly: [
            WeeklyWindow(dow: 1, open: '09:00', close: '12:00'),
            WeeklyWindow(dow: 1, open: '12:01', close: '23:00'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('storefront-hours-touching-1')),
        findsNothing,
      );
      expect(_enabled(tester, const Key('storefront-save')), isTrue);
      // The merged period: allowed, and saved exactly as entered.
      editor.onChanged(
        const OpeningHours(
          weekly: [WeeklyWindow(dow: 1, open: '09:00', close: '23:00')],
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect((repo.saves.single.patch['opening_hours']! as Map)['weekly'], [
        {'dow': 1, 'open': '09:00', 'close': '23:00'},
      ]);
    });

    testWidgets('Q-038: SAVED touching periods (accepted by the database) '
        'disable Publish with the card\'s own blocker and are never '
        'merged silently', (tester) async {
      final l10n = await _l10n();
      const touching = {
        'weekly': [
          {'dow': 1, 'open': '09:00', 'close': '12:00'},
          {'dow': 1, 'open': '12:00', 'close': '23:00'},
        ],
        'exceptions': <Object?>[],
      };
      final repo = _FakeProfileRepo(
        profile: _profileJson(openingHours: touching),
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      // The server's blockers are empty, yet Publish is disabled.
      expect(_enabled(tester, const Key('storefront-publish')), isFalse);
      expect(find.byKey(const Key('storefront-ready')), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('storefront-blocker-hours_touching')),
            )
            .data,
        l10n.storefrontBlockerHoursTouching,
      );
      expect(
        find.byKey(const Key('storefront-hours-touching-1')),
        findsOneWidget,
      );
      // Another field's save cannot go through while the error stands, and
      // nothing rewrote the stored value.
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Fresh',
      );
      await tester.pumpAndSettle();
      expect(_enabled(tester, const Key('storefront-save')), isFalse);
      expect(repo.saves, isEmpty);
      expect(repo.profile!['opening_hours'], touching);
      // Merge into one continuous period, save: Publish is enabled.
      tester
          .widget<OpeningHoursEditor>(find.byKey(const Key('storefront-hours')))
          .onChanged(
            const OpeningHours(
              weekly: [WeeklyWindow(dow: 1, open: '09:00', close: '23:00')],
            ),
          );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(
        find.byKey(const Key('storefront-blocker-hours_touching')),
        findsNothing,
      );
      expect(_enabled(tester, const Key('storefront-publish')), isTrue);
    });

    testWidgets('Q-038: a PUBLISHED storefront with saved touching periods is '
        'never shown as fully published', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(
        profile: _profileJson(
          published: true,
          openingHours: const {
            'weekly': [
              {'dow': 1, 'open': '09:00', 'close': '12:00'},
              {'dow': 1, 'open': '12:00', 'close': '23:00'},
            ],
            'exceptions': <Object?>[],
          },
        ),
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(find.text(l10n.storefrontPublishedStatus), findsNothing);
      expect(
        find.text(l10n.storefrontPublishedIncompleteStatus),
        findsOneWidget,
      );
    });

    testWidgets('C10: a PUBLISHED storefront with unreadable hours is never '
        '"all requirements met"', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(
        profile: _profileJson(
          published: true,
          openingHours: const {
            'weekly': [
              {'dow': 1, 'open': '09:00'},
            ],
          },
        ),
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('storefront-published-status')))
            .data,
        l10n.storefrontPublishedIncompleteStatus,
      );
      expect(find.text(l10n.storefrontPublishedChecksMet), findsNothing);
      expect(
        find.byKey(const Key('storefront-blocker-hours_unreadable')),
        findsOneWidget,
      );
      // The way out stays: Unpublish.
      expect(_enabled(tester, const Key('storefront-unpublish')), isTrue);
    });

    testWidgets('C9 / DASH-2: overlapping hours get an ADVISORY warning; '
        'Save is not blocked and sends them as they are', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(repo),
          pickTime: (context, initial) async => '16:00',
        ),
      );
      // Two windows on Monday: the seed never duplicates (09-17, 18-22).
      await _tap(tester, find.byKey(const Key('storefront-hours-add-1')));
      await _tap(tester, find.byKey(const Key('storefront-hours-add-1')));
      expect(find.byKey(const Key('storefront-hours-overlap-1')), findsNothing);
      // Move the second window's open to 16:00: it now overlaps 09-17.
      await _tap(tester, find.byKey(const Key('storefront-hours-open-1-1')));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('storefront-hours-overlap-1')))
            .data,
        l10n.storefrontHoursOverlapWarning,
      );
      expect(find.byKey(const Key('storefront-hours-invalid')), findsNothing);
      expect(_enabled(tester, const Key('storefront-save')), isTrue);
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.single.patch, {
        'opening_hours': {
          'weekly': [
            {'dow': 1, 'open': '09:00', 'close': '17:00'},
            {'dow': 1, 'open': '16:00', 'close': '22:00'},
          ],
          'exceptions': <Object?>[],
        },
      });
      // The saved (server-accepted) shape keeps its warning after the
      // re-read.
      expect(
        find.byKey(const Key('storefront-hours-overlap-1')),
        findsOneWidget,
      );
    });
  });

  group('DASH-1: the card\'s lifecycle', () {
    const owner = MembershipContext(
      id: 'm-1',
      organizationId: 'org-1',
      organizationName: 'Olive Group',
      restaurantId: _rest,
      restaurantName: 'Olive North',
      branchId: 'branch-1',
      branchName: 'Main hall',
      role: MembershipRole.orgOwner,
      status: 'active',
    );

    testWidgets('scrolled out of the lazy Settings list and back: the draft '
        'and the same-request Try again are kept, with no extra read', (
      tester,
    ) async {
      final l10n = await _l10n();
      tester.view.physicalSize = const Size(1200, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeProfileRepo(profile: _profileJson())
        ..saveOverrides.add(
          const StorefrontWriteResult(
            StorefrontWriteStatus.uncertain,
            requestId: _retryId,
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: RealSettingsView(
              membership: owner,
              currencyCode: 'ILS',
              settingsRepository: _FakeSettings(),
              storefrontSeams: _seams(repo),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      // The card starts below the first screen (not even built yet).
      expect(
        find.byKey(const Key('storefront-section'), skipOffstage: false),
        findsNothing,
      );
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(repo.reads, 1);

      // A draft — a typed field AND picker-driven opening hours — then a
      // save whose outcome is unknown.
      final tagline = find.byKey(
        const Key('storefront-tagline'),
        skipOffstage: false,
      );
      await tester.ensureVisible(tagline);
      await tester.pumpAndSettle();
      await tester.enterText(tagline, 'Fresh pasta');
      await tester.pumpAndSettle();
      await _tap(
        tester,
        find.byKey(const Key('storefront-hours-add-1'), skipOffstage: false),
      );
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(find.text(l10n.storefrontErrorUncertain), findsOneWidget);
      expect(find.byKey(const Key('storefront-save-retry')), findsOneWidget);
      // No text field keeps focus (a focused field would keep its list child
      // alive by itself and hide the bug): this is the hours-editing case.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      final reads = repo.reads;
      final there = position.pixels;

      // Up to the time zone setting the hours editor points to: the card
      // leaves the list's build window entirely.
      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('storefront-section')), findsNothing);
      expect(find.text(l10n.adminSettingsTitle), findsOneWidget);

      // ...and back.
      position.jumpTo(there);
      await tester.pumpAndSettle();
      expect(repo.reads, reads, reason: 'no extra read');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('storefront-tagline'), skipOffstage: false),
            )
            .controller!
            .text,
        'Fresh pasta',
      );
      expect(
        find.byKey(const Key('storefront-unsaved'), skipOffstage: false),
        findsOneWidget,
      );
      final retry = find.byKey(
        const Key('storefront-save-retry'),
        skipOffstage: false,
      );
      expect(retry, findsOneWidget);
      expect(
        find.byKey(const Key('storefront-hours-open-1-0'), skipOffstage: false),
        findsOneWidget,
        reason: 'the picker-driven hours draft is kept',
      );
      // The kept handle still replays THE SAME request.
      await _tap(tester, retry);
      expect(repo.saves, hasLength(2));
      expect(repo.saves[1].requestId, _retryId);
      expect(repo.saves[1].patch, repo.saves[0].patch);
      expect(repo.saves[1].patch, {
        'tagline': 'Fresh pasta',
        'opening_hours': {
          'weekly': [
            {'dow': 1, 'open': '09:00', 'close': '17:00'},
          ],
          'exceptions': <Object?>[],
        },
      });
    });

    testWidgets('another membership / restaurant identity drops the draft and '
        'the pending Try again, and starts from a fresh read', (tester) async {
      final l10n = await _l10n();
      final repoA =
          _FakeProfileRepo(profile: _profileJson(displayName: 'Tenant A'))
            ..saveOverrides.add(
              const StorefrontWriteResult(
                StorefrontWriteStatus.uncertain,
                requestId: _retryId,
              ),
            );
      final repoB = _FakeProfileRepo(
        profile: _profileJson(displayName: 'Tenant B'),
      );
      await _pump(
        tester,
        StorefrontSection(seams: _seams(repoA, identity: 'm-a|org-a|rest-a')),
      );
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Draft of A',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(find.byKey(const Key('storefront-save-retry')), findsOneWidget);

      // The same identity (a rebuilt seams object) keeps the draft...
      await _pump(
        tester,
        StorefrontSection(seams: _seams(repoA, identity: 'm-a|org-a|rest-a')),
      );
      expect(find.byKey(const Key('storefront-unsaved')), findsOneWidget);

      // ...another identity never shows it.
      await _pump(
        tester,
        StorefrontSection(seams: _seams(repoB, identity: 'm-b|org-b|rest-b')),
      );
      expect(repoB.reads, 1, reason: 'a fresh read of the new identity');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-display-name')))
            .controller!
            .text,
        'Tenant B',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-tagline')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byKey(const Key('storefront-unsaved')), findsNothing);
      expect(find.byKey(const Key('storefront-save-retry')), findsNothing);
      expect(find.text(l10n.storefrontErrorUncertain), findsNothing);
      expect(repoB.saves, isEmpty);
    });

    testWidgets('a read of the previous identity still in flight never lands '
        'in the new one', (tester) async {
      final gated = _GatedRepo(profile: _profileJson(displayName: 'Tenant A'));
      final repoB = _FakeProfileRepo(
        profile: _profileJson(displayName: 'Tenant B'),
      );
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      Widget app(StorefrontEditorSeams seams) => MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(child: StorefrontSection(seams: seams)),
        ),
      );
      await tester.pumpWidget(app(_seams(gated, identity: 'a')));
      await tester.pump();
      await tester.pumpWidget(app(_seams(repoB, identity: 'b')));
      await tester.pumpAndSettle();
      gated.gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-display-name')))
            .controller!
            .text,
        'Tenant B',
      );
      expect(find.text('Tenant A'), findsNothing);
    });
  });

  group('outcomes', () {
    testWidgets('version_conflict reloads the authority (no silent merge)', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      // Someone else saves first.
      repo.profile = _profileJson(displayName: 'Roma Downtown', version: 2);
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Mine',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.single.expectedVersion, 1);
      expect(find.text(l10n.storefrontErrorConflict), findsOneWidget);
      // The draft now shows THEIR state; our unsaved edit was not applied.
      final name = tester.widget<TextField>(
        find.byKey(const Key('storefront-display-name')),
      );
      expect(name.controller!.text, 'Roma Downtown');
      final tagline = tester.widget<TextField>(
        find.byKey(const Key('storefront-tagline')),
      );
      expect(tagline.controller!.text, isEmpty);
      // The next save uses the reloaded version.
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Mine again',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.last.expectedVersion, 2);
    });

    testWidgets('a save whose re-read fails locks editing until a reload '
        '(never a second save from the old version)', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Fresh',
      );
      await tester.pumpAndSettle();
      repo.readOverrides.add(const StorefrontProfileRead.unavailable());
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.single.expectedVersion, 1);
      expect(repo.profile!['version'], 2, reason: 'the write committed');
      expect(find.text(l10n.storefrontSaved), findsOneWidget);
      expect(find.byKey(const Key('storefront-stale')), findsOneWidget);
      expect(find.text(l10n.storefrontStaleNote), findsOneWidget);
      // No false "unsaved changes"; Save, Publish and the fields are locked.
      expect(find.byKey(const Key('storefront-unsaved')), findsNothing);
      expect(_enabled(tester, const Key('storefront-save')), isFalse);
      expect(_enabled(tester, const Key('storefront-publish')), isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-tagline')))
            .enabled,
        isFalse,
      );
      // Reload shows the authority and unlocks editing.
      await _tap(tester, find.byKey(const Key('storefront-reload')));
      expect(find.byKey(const Key('storefront-stale')), findsNothing);
      final tagline = tester.widget<TextField>(
        find.byKey(const Key('storefront-tagline')),
      );
      expect(tagline.controller!.text, 'Fresh');
      expect(tagline.enabled, isTrue);
      expect(_enabled(tester, const Key('storefront-publish')), isTrue);
      expect(repo.saves, hasLength(1));
    });

    testWidgets('publish whose re-read fails: locked, never a second press '
        'that reads as someone else\'s conflict', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      repo.readOverrides.add(const StorefrontProfileRead.unavailable());
      await _tap(tester, find.byKey(const Key('storefront-publish')));
      await tester.tap(
        find.byKey(const Key('storefront-publish-confirm-action')),
      );
      await tester.pumpAndSettle();
      expect(repo.saves.single.patch, {'is_published': true});
      expect(find.byKey(const Key('storefront-stale')), findsOneWidget);
      expect(_enabled(tester, const Key('storefront-publish')), isFalse);
      await _tap(tester, find.byKey(const Key('storefront-reload')));
      expect(find.text(l10n.storefrontPublishedStatus), findsOneWidget);
      expect(repo.saves, hasLength(1));
    });

    testWidgets('a conflict whose re-read fails says so, and locks too', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      repo.profile = _profileJson(displayName: 'Roma Downtown', version: 2);
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Mine',
      );
      await tester.pumpAndSettle();
      repo.readOverrides.add(const StorefrontProfileRead.unavailable());
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(
        find.text(l10n.storefrontErrorConflictNotReloaded),
        findsOneWidget,
      );
      expect(find.text(l10n.storefrontErrorConflict), findsNothing);
      expect(find.byKey(const Key('storefront-stale')), findsOneWidget);
      expect(_enabled(tester, const Key('storefront-save')), isFalse);
      await _tap(tester, find.byKey(const Key('storefront-reload')));
      final name = tester.widget<TextField>(
        find.byKey(const Key('storefront-display-name')),
      );
      expect(name.controller!.text, 'Roma Downtown');
      expect(find.byKey(const Key('storefront-stale')), findsNothing);
    });

    testWidgets('uncertain: Try again replays the SAME request', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson())
        ..saveOverrides.add(
          const StorefrontWriteResult(
            StorefrontWriteStatus.uncertain,
            requestId: _retryId,
          ),
        );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Fresh',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(find.text(l10n.storefrontErrorUncertain), findsOneWidget);
      // The draft is kept (nothing is known).
      expect(find.byKey(const Key('storefront-unsaved')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('storefront-save-retry')));
      expect(repo.saves, hasLength(2));
      expect(repo.saves[1].requestId, _retryId);
      expect(repo.saves[1].expectedVersion, repo.saves[0].expectedVersion);
      expect(repo.saves[1].patch, repo.saves[0].patch);
      expect(find.text(l10n.storefrontSaved), findsOneWidget);
    });

    testWidgets('uncertain: Try again disappears once the draft changes', (
      tester,
    ) async {
      final repo = _FakeProfileRepo(profile: _profileJson())
        ..saveOverrides.add(
          const StorefrontWriteResult(
            StorefrontWriteStatus.uncertain,
            requestId: _retryId,
          ),
        );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await tester.enterText(find.byKey(const Key('storefront-tagline')), 'A');
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(find.byKey(const Key('storefront-save-retry')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('storefront-tagline')), 'B');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('storefront-save-retry')), findsNothing);
    });

    testWidgets('Discard after an unknown outcome re-reads the authority, '
        'never the cached pre-save profile', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson())
        ..saveOverrides.add(
          const StorefrontWriteResult(
            StorefrontWriteStatus.uncertain,
            requestId: _retryId,
          ),
        );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Fresh',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(find.text(l10n.storefrontErrorUncertain), findsOneWidget);
      // The lost write DID commit.
      repo.profile = {..._profileJson(version: 2), 'tagline': 'Fresh'};
      final reads = repo.reads;
      await _tap(tester, find.byKey(const Key('storefront-discard')));
      expect(repo.reads, reads + 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-tagline')))
            .controller!
            .text,
        'Fresh',
      );
      expect(find.text(l10n.storefrontDiscardReloaded), findsOneWidget);
      expect(find.text(l10n.storefrontErrorUncertain), findsNothing);
      expect(find.byKey(const Key('storefront-save-retry')), findsNothing);
      expect(find.byKey(const Key('storefront-unsaved')), findsNothing);
      // The next save goes out from the AUTHORITATIVE version: no conflict
      // blamed on "someone else" for the manager's own write.
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Fresher',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(repo.saves.last.expectedVersion, 2);
      expect(find.text(l10n.storefrontSaved), findsOneWidget);
      expect(find.text(l10n.storefrontErrorConflict), findsNothing);
    });

    testWidgets('Discard after an unknown outcome whose re-read fails: '
        'nothing is discarded and the same-request Try again stays', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson())
        ..saveOverrides.add(
          const StorefrontWriteResult(
            StorefrontWriteStatus.uncertain,
            requestId: _retryId,
          ),
        );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await tester.enterText(
        find.byKey(const Key('storefront-tagline')),
        'Fresh',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-save')));
      repo.readOverrides.add(const StorefrontProfileRead.unavailable());
      await _tap(tester, find.byKey(const Key('storefront-discard')));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-tagline')))
            .controller!
            .text,
        'Fresh',
      );
      expect(find.text(l10n.storefrontDiscardNotReloaded), findsOneWidget);
      expect(find.byKey(const Key('storefront-unsaved')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('storefront-save-retry')));
      expect(repo.saves, hasLength(2));
      expect(repo.saves[1].requestId, _retryId);
      expect(repo.saves[1].expectedVersion, repo.saves[0].expectedVersion);
      expect(repo.saves[1].patch, repo.saves[0].patch);
      expect(find.text(l10n.storefrontSaved), findsOneWidget);
    });

    testWidgets('each typed failure has its own honest message', (
      tester,
    ) async {
      final l10n = await _l10n();
      final cases = <StorefrontWriteResult, String>{
        const StorefrontWriteResult(StorefrontWriteStatus.denied):
            l10n.storefrontErrorDenied,
        const StorefrontWriteResult(StorefrontWriteStatus.unavailable):
            l10n.storefrontErrorUnavailable,
        const StorefrontWriteResult(StorefrontWriteStatus.notCommitted):
            l10n.storefrontErrorNotCommitted,
        const StorefrontWriteResult(
          StorefrontWriteStatus.invalid,
          reason: 'slug_taken',
        ): l10n.storefrontReasonSlugTaken,
        const StorefrontWriteResult(
          StorefrontWriteStatus.invalid,
          reason: 'opening_hours_invalid',
        ): l10n.storefrontReasonOpeningHoursInvalid,
      };
      for (final entry in cases.entries) {
        final repo = _FakeProfileRepo(profile: _profileJson())
          ..saveOverrides.add(entry.key);
        await _pump(
          tester,
          StorefrontSection(key: UniqueKey(), seams: _seams(repo)),
        );
        await tester.enterText(
          find.byKey(const Key('storefront-tagline')),
          'x',
        );
        await tester.pumpAndSettle();
        await _tap(tester, find.byKey(const Key('storefront-save')));
        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
        // Nothing is known to have changed: the draft is kept.
        expect(find.byKey(const Key('storefront-unsaved')), findsOneWidget);
      }
    });

    testWidgets(
      'publish_precondition lists the codes and offers unpublish-and-save',
      (tester) async {
        final l10n = await _l10n();
        final repo = _FakeProfileRepo(profile: _profileJson(published: true))
          ..saveOverrides.add(
            const StorefrontWriteResult(
              StorefrontWriteStatus.invalid,
              reason: 'publish_precondition',
              blockers: ['hours_missing', 'timezone_missing'],
            ),
          );
        await _pump(tester, StorefrontSection(seams: _seams(repo)));
        await tester.enterText(
          find.byKey(const Key('storefront-tagline')),
          'New',
        );
        await tester.pumpAndSettle();
        await _tap(tester, find.byKey(const Key('storefront-save')));
        expect(
          find.text(l10n.storefrontReasonPublishPrecondition),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('storefront-banner-blocker-hours_missing')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('storefront-banner-blocker-timezone_missing')),
          findsOneWidget,
        );
        expect(find.text(l10n.storefrontBlockerHoursMissing), findsOneWidget);

        await _tap(tester, find.byKey(const Key('storefront-unpublish-save')));
        expect(
          find.byKey(const Key('storefront-unpublish-save-confirm')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('storefront-unpublish-save-confirm-action')),
        );
        await tester.pumpAndSettle();
        expect(repo.saves.last.patch, {
          'tagline': 'New',
          'is_published': false,
        });
        expect(find.text(l10n.storefrontUnpublishedStatus), findsOneWidget);
      },
    );
  });

  group('publishing', () {
    testWidgets('blockers are listed and Publish is disabled', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(
        profile: _profileJson(),
        blockers: const ['timezone_missing', 'no_live_item', 'future_code'],
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(find.text(l10n.storefrontBlockerTimezoneMissing), findsOneWidget);
      expect(find.text(l10n.storefrontBlockerNoLiveItem), findsOneWidget);
      expect(
        find.text(l10n.storefrontBlockerUnknown('future_code')),
        findsOneWidget,
      );
      expect(_enabled(tester, const Key('storefront-publish')), isFalse);
      expect(
        find.byKey(const Key('storefront-publish-needs-blockers')),
        findsOneWidget,
      );
    });

    testWidgets('published, but the public read answers not_found: never '
        'called "public"', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(
        profile: _profileJson(published: true),
        blockers: const ['currency_not_ils'],
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('storefront-published-status')))
            .data,
        l10n.storefrontPublishedOfflineStatus,
      );
      expect(find.text(l10n.storefrontPublishedStatus), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('storefront-blockers-title')))
            .data,
        l10n.storefrontBlockersTitlePublished,
      );
      expect(find.text(l10n.storefrontBlockersTitle), findsNothing);
      expect(find.text(l10n.storefrontBlockerCurrencyNotIls), findsOneWidget);
      // The way out stays: Unpublish.
      expect(_enabled(tester, const Key('storefront-unpublish')), isTrue);
    });

    testWidgets('published: each blocker changes the status honestly', (
      tester,
    ) async {
      final l10n = await _l10n();
      final cases = <List<String>, String>{
        const ['branch_missing']: l10n.storefrontPublishedOfflineStatus,
        const ['timezone_missing']: l10n.storefrontPublishedOfflineStatus,
        const ['tax_not_exclusive', 'no_live_item']:
            l10n.storefrontPublishedOfflineStatus,
        const ['no_live_item']: l10n.storefrontPublishedIncompleteStatus,
        const ['hours_missing']: l10n.storefrontPublishedIncompleteStatus,
        const ['future_code']: l10n.storefrontPublishedUncheckedStatus,
        const <String>[]: l10n.storefrontPublishedStatus,
      };
      for (final entry in cases.entries) {
        final repo = _FakeProfileRepo(
          profile: _profileJson(published: true),
          blockers: entry.key,
        );
        await _pump(
          tester,
          StorefrontSection(key: UniqueKey(), seams: _seams(repo)),
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('storefront-published-status')),
              )
              .data,
          entry.value,
          reason: '${entry.key}',
        );
        if (entry.key.isEmpty) {
          // Already published: never "Ready to publish".
          expect(
            tester.widget<Text>(find.byKey(const Key('storefront-ready'))).data,
            l10n.storefrontPublishedChecksMet,
          );
          expect(find.text(l10n.storefrontReadyToPublish), findsNothing);
        }
      }
    });

    testWidgets('C11 / OQ-3 / DASH-5: "Published" never claims "public"; the '
        'availability note says what publishing does not guarantee', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson(published: true));
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('storefront-status-label')))
            .data,
        l10n.storefrontStatusLabel,
      );
      final status = tester
          .widget<Text>(find.byKey(const Key('storefront-published-status')))
          .data!;
      expect(status, l10n.storefrontPublishedStatus);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('storefront-availability-note')))
            .data,
        l10n.storefrontPublishedAvailabilityNote,
      );
      // The copy itself: no "public" claim for a published status, and the
      // publish confirmation no longer promises visibility right away.
      for (final code in ['en', 'ar', 'he']) {
        final t = await _l10n(code);
        expect(
          t.storefrontPublishedStatus,
          isNot(t.storefrontUnpublishedStatus),
        );
      }
      for (final s in [
        l10n.storefrontPublishedStatus,
        l10n.storefrontPublishedIncompleteStatus,
      ]) {
        expect(s.toLowerCase(), isNot(contains('public')), reason: s);
        expect(s.toLowerCase(), isNot(contains('online')), reason: s);
      }
      for (final s in [
        l10n.storefrontPublishedAvailabilityNote,
        l10n.storefrontBranchSuspendedNote,
      ]) {
        expect(s, contains('suspended'), reason: s);
      }
      expect(l10n.storefrontPublishConfirmBody, startsWith('Once'));
    });

    testWidgets('C11: not published = no availability note', (tester) async {
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(_FakeProfileRepo(profile: _profileJson())),
        ),
      );
      expect(
        find.byKey(const Key('storefront-availability-note')),
        findsNothing,
      );
      expect(find.byKey(const Key('storefront-status-label')), findsOneWidget);
    });

    // DASH-V-2: the note belongs to EVERY published state. The C11 test above
    // pins it for the clean "Published." status only, so a note shown only
    // while nothing needs fixing would still pass there (only the 360 px
    // layout run would notice). The blocker states are exactly where the
    // manager most needs to read that "published" is not "available".
    testWidgets('DASH-V-2: published but OFFLINE (a blocker hides the page) '
        'still shows the availability note, under a status that is not '
        '"Published." and never says "public"', (tester) async {
      final l10n = await _l10n();
      for (final blockers in const [
        ['currency_not_ils'],
        ['branch_missing'],
        // A hiding blocker wins over a page-online one.
        ['tax_not_exclusive', 'no_live_item'],
      ]) {
        final repo = _FakeProfileRepo(
          profile: _profileJson(published: true),
          blockers: blockers,
        );
        await _pump(
          tester,
          StorefrontSection(key: UniqueKey(), seams: _seams(repo)),
        );
        _expectPublishedWithNote(
          tester,
          l10n,
          status: l10n.storefrontPublishedOfflineStatus,
          reason: '$blockers',
        );
        // The way out stays: Unpublish.
        expect(_enabled(tester, const Key('storefront-unpublish')), isTrue);
      }
    });

    testWidgets('DASH-V-2: published but INCOMPLETE (server blockers, or '
        'saved hours this editor cannot read) still shows the availability '
        'note, under a status that is not "Published." and never says '
        '"public"', (tester) async {
      final l10n = await _l10n();
      final cases = <String, _FakeProfileRepo>{
        'no_live_item': _FakeProfileRepo(
          profile: _profileJson(published: true),
          blockers: const ['no_live_item'],
        ),
        'hours_missing': _FakeProfileRepo(
          profile: _profileJson(published: true),
          blockers: const ['hours_missing'],
        ),
        'no_live_item + hours_missing': _FakeProfileRepo(
          profile: _profileJson(published: true),
          blockers: const ['no_live_item', 'hours_missing'],
        ),
        // No SERVER blocker at all: the card's own hours_unreadable makes it
        // incomplete.
        'unreadable hours': _FakeProfileRepo(
          profile: _profileJson(
            published: true,
            openingHours: const {
              'weekly': [
                {'dow': 1, 'open': '09:00'},
              ],
            },
          ),
        ),
      };
      for (final entry in cases.entries) {
        await _pump(
          tester,
          StorefrontSection(key: UniqueKey(), seams: _seams(entry.value)),
        );
        _expectPublishedWithNote(
          tester,
          l10n,
          status: l10n.storefrontPublishedIncompleteStatus,
          reason: entry.key,
        );
        expect(find.text(l10n.storefrontPublishedChecksMet), findsNothing);
        expect(_enabled(tester, const Key('storefront-unpublish')), isTrue);
      }
    });

    testWidgets('C11 / DASH-3: a suspended branch is marked in the picker, and '
        'choosing it says the storefront is then unavailable', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson(published: true));
      await _pump(
        tester,
        StorefrontSection(seams: _seams(repo, branches: _SuspendedBranches())),
      );
      // The saved branch (A) is active: no note.
      expect(
        find.byKey(const Key('storefront-branch-suspended')),
        findsNothing,
      );
      await _tap(tester, find.byKey(const Key('storefront-branch')));
      expect(
        find.text(l10n.storefrontBranchSuspendedOption('Harbor')),
        findsWidgets,
      );
      expect(find.text('Downtown'), findsWidgets);
      await tester.tap(
        find.text(l10n.storefrontBranchSuspendedOption('Harbor')).last,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('storefront-branch-suspended')))
            .data,
        l10n.storefrontBranchSuspendedNote,
      );
      // A saved suspended branch shows it on load too.
      final saved = _FakeProfileRepo(
        profile: {..._profileJson(), 'storefront_branch_id': _branchB},
      );
      await _pump(
        tester,
        StorefrontSection(
          key: UniqueKey(),
          seams: _seams(saved, branches: _SuspendedBranches()),
        ),
      );
      expect(
        find.byKey(const Key('storefront-branch-suspended')),
        findsOneWidget,
      );
    });

    testWidgets('unpublished: the heading still reads "before you can '
        'publish"', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(
        profile: _profileJson(),
        blockers: const ['currency_not_ils'],
      );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(find.text(l10n.storefrontUnpublishedStatus), findsOneWidget);
      expect(find.text(l10n.storefrontBlockersTitle), findsOneWidget);
      expect(find.text(l10n.storefrontBlockersTitlePublished), findsNothing);
    });

    testWidgets('Publish is disabled while there are unsaved edits', (
      tester,
    ) async {
      await _pump(
        tester,
        StorefrontSection(
          seams: _seams(_FakeProfileRepo(profile: _profileJson())),
        ),
      );
      expect(_enabled(tester, const Key('storefront-publish')), isTrue);
      await tester.enterText(find.byKey(const Key('storefront-tagline')), 'x');
      await tester.pumpAndSettle();
      expect(_enabled(tester, const Key('storefront-publish')), isFalse);
      expect(
        find.byKey(const Key('storefront-publish-needs-save')),
        findsOneWidget,
      );
    });

    testWidgets('publish: confirmation, then ONLY the server state is shown', (
      tester,
    ) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson());
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(find.text(l10n.storefrontUnpublishedStatus), findsOneWidget);

      await _tap(tester, find.byKey(const Key('storefront-publish')));
      expect(
        find.byKey(const Key('storefront-publish-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.adminCancel));
      await tester.pumpAndSettle();
      expect(repo.saves, isEmpty);

      await _tap(tester, find.byKey(const Key('storefront-publish')));
      await tester.tap(
        find.byKey(const Key('storefront-publish-confirm-action')),
      );
      await tester.pumpAndSettle();
      expect(repo.saves.single.patch, {'is_published': true});
      expect(repo.saves.single.expectedVersion, 1);
      expect(find.text(l10n.storefrontPublishedStatus), findsOneWidget);
      expect(find.byKey(const Key('storefront-unpublish')), findsOneWidget);
    });

    testWidgets('an ok answer is NOT shown as published until the re-read '
        'says so', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson())
        ..saveOverrides.add(
          const StorefrontWriteResult(StorefrontWriteStatus.ok, version: 2),
        );
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      await _tap(tester, find.byKey(const Key('storefront-publish')));
      await tester.tap(
        find.byKey(const Key('storefront-publish-confirm-action')),
      );
      await tester.pumpAndSettle();
      // The (overridden) write did not change the fake server: the re-read
      // still says unpublished, and that is what is shown.
      expect(find.text(l10n.storefrontUnpublishedStatus), findsOneWidget);
      expect(find.text(l10n.storefrontPublishedStatus), findsNothing);
    });

    testWidgets('unpublish: confirmation; the profile is kept', (tester) async {
      final l10n = await _l10n();
      final repo = _FakeProfileRepo(profile: _profileJson(published: true));
      await _pump(tester, StorefrontSection(seams: _seams(repo)));
      expect(find.text(l10n.storefrontPublishedStatus), findsOneWidget);
      await _tap(tester, find.byKey(const Key('storefront-unpublish')));
      expect(
        find.byKey(const Key('storefront-unpublish-confirm')),
        findsOneWidget,
      );
      expect(find.text(l10n.storefrontUnpublishConfirmBody), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('storefront-unpublish-confirm-action')),
      );
      await tester.pumpAndSettle();
      expect(repo.saves.single.patch, {'is_published': false});
      expect(find.text(l10n.storefrontUnpublishedStatus), findsOneWidget);
      expect(find.byKey(const Key('storefront-slug-readonly')), findsOneWidget);
    });
  });

  group('copy registries', () {
    test(
      'every writer reason and blocker has its own localized copy',
      () async {
        for (final code in ['en', 'ar', 'he']) {
          final l10n = await _l10n(code);
          final reasons = {
            for (final r in kStorefrontInvalidReasons)
              storefrontReasonMessage(l10n, r),
          };
          expect(reasons, hasLength(kStorefrontInvalidReasons.length));
          expect(
            reasons.contains(storefrontReasonMessage(l10n, 'x_unknown')),
            isFalse,
          );
          final blockers = {
            for (final b in kStorefrontPublishBlockers)
              storefrontBlockerLabel(l10n, b),
          };
          expect(blockers, hasLength(kStorefrontPublishBlockers.length));
          expect(
            storefrontBlockerLabel(l10n, 'x_unknown'),
            contains('x_unknown'),
          );
        }
      },
    );
  });

  group('Settings placement', () {
    testWidgets('RealSettingsView shows the card right after branding', (
      tester,
    ) async {
      final l10n = await _l10n();
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const membership = MembershipContext(
        id: 'm-1',
        organizationId: 'org-1',
        organizationName: 'Olive Group',
        restaurantId: 'rest-1',
        restaurantName: 'Olive North',
        branchId: 'branch-1',
        branchName: 'Main hall',
        role: MembershipRole.manager,
        status: 'active',
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: RealSettingsView(membership: membership)),
        ),
      );
      await tester.pumpAndSettle();
      final branding = find.text(l10n.brandingSectionTitle);
      final storefront = find.byKey(const Key('storefront-section'));
      expect(storefront, findsOneWidget);
      expect(find.text(l10n.storefrontUnavailableNote), findsOneWidget);
      expect(
        tester.getTopLeft(storefront).dy,
        greaterThan(tester.getTopLeft(branding).dy),
      );
    });
  });
}
