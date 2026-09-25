import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_slot.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_section.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_sources.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// STOREFRONT-PUBLISH-001 — the logo / hero media slots, driven through the
/// section so the whole chain runs: the Edge Function publish (identifiers
/// only; one request id across rungs and retries) -> the CAS slot assignment
/// -> the re-read; remove from storefront; retract / discard with
/// confirmation; and the unknown-outcome recovery (refresh + Try again with
/// the SAME request).
const _org = '11111111-1111-4111-8111-111111111111';
const _rest = '22222222-2222-4222-8222-222222222222';
const _branch = '33333333-3333-4333-8333-333333333333';
const _mediaLogo = '55555555-5555-4555-8555-555555555555';
const _mediaHero = '66666666-6666-4666-8666-666666666666';
const _mediaOld = '77777777-7777-4777-8777-777777777777';
const _mediaStaged = '88888888-8888-4888-8888-888888888888';
const _logoKey = '$_org/$_rest/logo/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.png';
const _menuKey =
    '$_org/$_rest/global/menu_item/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/'
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc.jpg';
const _retryId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

Map<String, Object?> _profileJson({
  String? logo,
  String? hero,
  int version = 1,
}) => {
  'restaurant_id': _rest,
  'storefront_branch_id': _branch,
  'slug': 'cafe-roma',
  'display_name': 'Cafe Roma',
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
  'opening_hours': {'weekly': <Object?>[], 'exceptions': <Object?>[]},
  'logo_media_id': logo,
  'hero_media_id': hero,
  'is_published': false,
  'version': version,
};

Map<String, Object?> _row(
  String id, {
  String state = 'published',
  String variant = 'w480',
  String bucket = 'restaurant-logos',
  String key = _logoKey,
}) => {
  'id': id,
  'source_bucket': bucket,
  'source_key': key,
  'variant': variant,
  'object_key': 'prefix0/${id.replaceAll('-', '').padRight(64, '0')}.webp',
  'content_hash': id.replaceAll('-', '').padRight(64, '0'),
  'width': 480,
  'height': 320,
  'bytes': 40000,
  'state': state,
  'published_at': state == 'staged' ? null : '2026-09-24T10:00:00Z',
  'unpublished_at': state == 'retracted' ? '2026-09-24T11:00:00Z' : null,
  'created_at': '2026-09-24T09:00:00Z',
  'in_use': <Object?>[],
};

class _Save {
  const _Save(this.expectedVersion, this.patch, this.requestId);

  final int expectedVersion;
  final Map<String, Object?> patch;
  final String requestId;
}

/// The fake server: one profile + media rows; `in_use` is derived from the
/// profile pointers exactly as the list RPC does.
class _Server implements StorefrontProfileRepository {
  _Server({Map<String, Object?>? profile, List<Map<String, Object?>>? rows})
    : profile = profile ?? _profileJson(),
      rows = rows ?? [];

  Map<String, Object?> profile;
  final List<Map<String, Object?>> rows;
  final List<_Save> saves = [];
  int reads = 0;

  /// The server ledger: a request id that committed replays its result.
  final Map<String, int> ledger = {};

  /// The next N saves COMMIT, but their answer is lost (uncertain).
  int loseSaveAnswers = 0;

  /// After a lost answer, this many following reads fail too.
  int failReadsAfterLoss = 0;
  int _failReads = 0;

  /// The next N reads fail (unavailable).
  set failNextReads(int n) => _failReads = n;

  /// Scripted answers for the next saves (answered first, NOT applied).
  final List<StorefrontWriteResult> saveOverrides = [];

  @override
  Future<StorefrontProfileRead> read() async {
    reads++;
    if (_failReads > 0) {
      _failReads--;
      return const StorefrontProfileRead.unavailable();
    }
    return StorefrontProfileRead.ok(
      exists: true,
      version: profile['version']! as int,
      profile: StorefrontProfile.fromJson(profile),
      derived: StorefrontDerived.fromJson({
        'timezone': 'Asia/Jerusalem',
        'currency_code': 'ILS',
        'tax': null,
        'publish_ready': true,
        'publish_blockers': <String>[],
        'media_prefix': 'prefix0',
      }),
    );
  }

  @override
  Future<StorefrontWriteResult> save({
    required int expectedVersion,
    required Map<String, Object?> patch,
    String? requestId,
  }) async {
    final id =
        requestId ??
        'ffffffff-ffff-4fff-8fff-${'${saves.length}'.padLeft(12, '0')}';
    saves.add(_Save(expectedVersion, Map.of(patch), id));
    if (saveOverrides.isNotEmpty) return saveOverrides.removeAt(0);
    final replayed = ledger[id];
    if (replayed != null) {
      return StorefrontWriteResult(
        StorefrontWriteStatus.ok,
        requestId: id,
        expectedVersion: expectedVersion,
        version: replayed,
        idempotentReplay: true,
      );
    }
    final current = profile['version']! as int;
    if (current != expectedVersion) {
      return StorefrontWriteResult(
        StorefrontWriteStatus.conflict,
        requestId: id,
        expectedVersion: expectedVersion,
        version: current,
      );
    }
    profile = {...profile, ...patch, 'version': current + 1};
    ledger[id] = current + 1;
    if (loseSaveAnswers > 0) {
      loseSaveAnswers--;
      _failReads = failReadsAfterLoss;
      return StorefrontWriteResult(
        StorefrontWriteStatus.uncertain,
        requestId: id,
        expectedVersion: expectedVersion,
      );
    }
    return StorefrontWriteResult(
      StorefrontWriteStatus.ok,
      requestId: id,
      expectedVersion: expectedVersion,
      version: current + 1,
    );
  }

  List<Map<String, Object?>> listed() => [
    for (final r in rows)
      {
        ...r,
        'in_use': [
          if (profile['logo_media_id'] == r['id']) 'logo',
          if (profile['hero_media_id'] == r['id']) 'hero',
        ],
      },
  ];
}

class _Media implements StorefrontMediaRepository {
  _Media(this.server);

  final _Server server;
  int lists = 0;
  final List<(String, String, String?)> actions = [];
  final List<StorefrontMediaActionResult> scripted = [];

  @override
  Future<StorefrontMediaList> list() async {
    lists++;
    return StorefrontMediaList.ok(
      mediaPrefix: 'prefix0',
      media: decodeStorefrontMediaRows(server.listed(), 'media'),
    );
  }

  StorefrontMediaActionResult _act(
    String op,
    String mediaId,
    String? requestId,
    void Function() apply,
  ) {
    actions.add((op, mediaId, requestId));
    if (scripted.isNotEmpty) return scripted.removeAt(0);
    apply();
    return StorefrontMediaActionResult(
      StorefrontMediaActionStatus.ok,
      mediaId: mediaId,
      requestId: requestId ?? 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    );
  }

  @override
  Future<StorefrontMediaActionResult> retract(
    String mediaId, {
    String? requestId,
  }) async => _act('retract', mediaId, requestId, () {
    final i = server.rows.indexWhere((r) => r['id'] == mediaId);
    server.rows[i] = {
      ...server.rows[i],
      'state': 'retracted',
      'unpublished_at': '2026-09-25T10:00:00Z',
    };
  });

  @override
  Future<StorefrontMediaActionResult> cancel(
    String mediaId, {
    String? requestId,
  }) async => _act(
    'cancel',
    mediaId,
    requestId,
    () => server.rows.removeWhere((r) => r['id'] == mediaId),
  );
}

/// Scripted function replies (the last repeats); a 200 registers the row on
/// the fake server, like finalize does.
class _Invoker implements StorefrontFunctionInvoker {
  _Invoker(this.server, this.replies);

  final _Server server;
  final List<StorefrontFunctionReply> replies;
  final List<Map<String, Object?>> bodies = [];

  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    bodies.add(Map.of(body));
    final i = bodies.length - 1;
    final r = replies[i < replies.length ? i : replies.length - 1];
    if (r.httpStatus == 200) {
      final m = r.json!['media']! as Map<String, Object?>;
      if (!server.rows.any((row) => row['id'] == m['id'])) {
        server.rows.insert(
          0,
          _row(
            m['id']! as String,
            variant: m['variant']! as String,
            bucket: m['source_bucket']! as String,
            key: m['source_key']! as String,
          ),
        );
      }
    }
    return r;
  }
}

StorefrontFunctionReply _published(
  String id, {
  String variant = 'w480',
  String bucket = 'restaurant-logos',
  String key = _logoKey,
  int? profileVersion,
}) => StorefrontFunctionReply(
  httpStatus: 200,
  json: {
    'ok': true,
    'status': 'published',
    'recipe': 'storefront-media-c4',
    'rung': 0,
    'idempotent_replay': false,
    'media': {
      'id': id,
      'object_key': 'prefix0/${'a' * 64}.webp',
      'content_hash': 'a' * 64,
      'width': 480,
      'height': 320,
      'bytes': 40000,
      'variant': variant,
      'source_bucket': bucket,
      'source_key': key,
      'state': 'published',
    },
    'already_published': false,
    'republished': false,
    'replaced_media_id': null,
    'profile_version': profileVersion,
    'source_mismatch': false,
  },
);

const _ladder1 = StorefrontFunctionReply(
  httpStatus: 202,
  json: {'ok': false, 'status': 'ladder_next', 'next_rung': 1},
);
const _lost = StorefrontFunctionReply.transportFailure();

/// The candidate sources; every field can change between loads (the receipt
/// logo replaced in the Branding card, a failed read that later recovers).
class _Sources implements StorefrontSourceCatalog {
  _Sources({
    this.logo = _logoKey,
    this.logoUnavailable = false,
    this.menuUnavailable = false,
  });

  String? logo;
  bool logoUnavailable;
  bool menuUnavailable;
  int loads = 0;

  @override
  Future<StorefrontSourceOptions> load() async {
    loads++;
    return StorefrontSourceOptions(
      receiptLogoKey: logoUnavailable ? null : logo,
      receiptLogoUnavailable: logoUnavailable,
      menuImages: menuUnavailable
          ? const <StorefrontMenuImageOption>[]
          : [
              const StorefrontMenuImageOption(
                itemId: 'item-1',
                itemName: 'Margherita',
                imageKey: _menuKey,
              ),
            ],
      menuImagesUnavailable: menuUnavailable,
    );
  }
}

class _Branches implements StorefrontBranchSource {
  @override
  Future<List<StorefrontBranchOption>?> list() async => const [
    StorefrontBranchOption(id: _branch, name: 'Downtown'),
  ];
}

class _Rig {
  _Rig({
    Map<String, Object?>? profile,
    List<Map<String, Object?>>? rows,
    List<StorefrontFunctionReply> replies = const [],
    bool withPublisher = true,
    _Sources? sources,
  }) : server = _Server(profile: profile, rows: rows) {
    media = _Media(server);
    invoker = _Invoker(server, replies.isEmpty ? [_lost] : replies);
    this.sources = sources ?? _Sources();
    seams = StorefrontEditorSeams(
      scopeIdentity: 'm-1|$_org|$_rest|manager',
      profileRepository: server,
      mediaRepository: media,
      branchSource: _Branches(),
      sourceCatalog: this.sources,
      publisher: withPublisher
          ? StorefrontMediaPublisher(
              invoker: invoker,
              organizationId: _org,
              restaurantId: _rest,
              retryDelay: Duration.zero,
            )
          : null,
    );
  }

  final _Server server;
  late final _Media media;
  late final _Invoker invoker;
  late final _Sources sources;
  late final StorefrontEditorSeams seams;
}

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester, _Rig rig, {int nonce = 7}) async {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          // A fresh State per pump (loops pump several rigs in one test).
          child: StorefrontSection(
            key: UniqueKey(),
            seams: rig.seams,
            nonce: () => nonce,
          ),
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

Future<void> _confirm(WidgetTester tester, String dialogKey) async {
  expect(find.byKey(Key(dialogKey)), findsOneWidget);
  await tester.tap(find.byKey(Key('$dialogKey-action')));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed != null;

String _message(WidgetTester tester, String slot) =>
    tester.widget<Text>(find.byKey(Key('storefront-slot-$slot-message'))).data!;

void main() {
  testWidgets('publish -> assign via CAS -> re-read (logo, rung ladder)', (
    tester,
  ) async {
    final l10n = await _l10n();
    final rig = _Rig(replies: [_ladder1, _published(_mediaLogo)]);
    await _pump(tester, rig);
    expect(find.byKey(const Key('storefront-slot-logo-empty')), findsOneWidget);
    final readsBefore = rig.server.reads;

    await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
    await _confirm(tester, 'storefront-slot-logo-publish-confirm');

    // The function saw identifiers ONLY, one request id across the rungs.
    expect(rig.invoker.bodies, hasLength(2));
    expect([for (final b in rig.invoker.bodies) b['rung']], [0, 1]);
    final first = rig.invoker.bodies.first;
    expect(first.keys.toSet(), StorefrontMediaPublisher.requestKeys.toSet());
    expect(first['slot'], 'logo');
    expect(first['variant'], 'w480');
    expect(first['source_bucket'], 'restaurant-logos');
    expect(first['source_key'], _logoKey);
    expect(isCanonicalUuid(first['request_id']! as String), isTrue);
    expect(rig.invoker.bodies[1]['request_id'], first['request_id']);

    // Then the slot is assigned through the profile CAS writer, re-read.
    expect(rig.server.saves.single.patch, {'logo_media_id': _mediaLogo});
    expect(rig.server.saves.single.expectedVersion, 1);
    expect(rig.server.reads, greaterThan(readsBefore));
    expect(_message(tester, 'logo'), l10n.storefrontSlotPublished);
    expect(
      find.byKey(const Key('storefront-slot-logo-remove')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('storefront-media-in-use-note-$_mediaLogo')),
      findsOneWidget,
    );
  });

  testWidgets('profile_version != null: re-read first; an already-moved '
      'pointer is not written again', (tester) async {
    final l10n = await _l10n();
    final rig = _Rig(
      rows: [_row(_mediaOld)],
      profile: _profileJson(logo: _mediaOld),
      replies: [_published(_mediaLogo, profileVersion: 2)],
    );
    await _pump(tester, rig);
    // Server-side re-point (finalize moved the pointer, version 2).
    rig.invoker.bodies.clear();
    final readsBefore = rig.server.reads;
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
    rig.server.profile = _profileJson(logo: _mediaLogo, version: 2);
    await _confirm(tester, 'storefront-slot-logo-publish-confirm');
    expect(rig.server.saves, isEmpty);
    expect(rig.server.reads, greaterThan(readsBefore));
    expect(_message(tester, 'logo'), l10n.storefrontSlotPublished);
  });

  testWidgets('hero from a menu item original: w960, menu-images', (
    tester,
  ) async {
    final rig = _Rig(
      replies: [
        _published(
          _mediaHero,
          variant: 'w960',
          bucket: 'menu-images',
          key: _menuKey,
        ),
      ],
    );
    await _pump(tester, rig);
    await _tap(tester, find.byKey(const Key('storefront-slot-hero-source')));
    await tester.tap(find.text('Menu item: Margherita').last);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('storefront-slot-hero-publish')));
    await _confirm(tester, 'storefront-slot-hero-publish-confirm');
    final body = rig.invoker.bodies.single;
    expect(body['slot'], 'hero');
    expect(body['variant'], 'w960');
    expect(body['source_bucket'], 'menu-images');
    expect(body['source_key'], _menuKey);
    expect(rig.server.saves.single.patch, {'hero_media_id': _mediaHero});
  });

  testWidgets('the logo slot offers ONLY the receipt logo', (tester) async {
    final l10n = await _l10n();
    final rig = _Rig(sources: _Sources(logo: null));
    await _pump(tester, rig);
    expect(
      find.byKey(const Key('storefront-slot-logo-no-source')),
      findsOneWidget,
    );
    expect(find.text(l10n.storefrontSourceNoReceiptLogo), findsOneWidget);
    expect(
      _enabled(tester, const Key('storefront-slot-logo-publish')),
      isFalse,
    );
    // The hero still has the menu original.
    expect(_enabled(tester, const Key('storefront-slot-hero-publish')), isTrue);
  });

  testWidgets('hero: a typed 422 refusal shows its own copy, "pick another '
      'source", and changes nothing', (tester) async {
    final l10n = await _l10n();
    final rig = _Rig(
      replies: const [
        StorefrontFunctionReply(
          httpStatus: 422,
          json: {'ok': false, 'status': 'refused', 'code': 'animated'},
        ),
      ],
    );
    await _pump(tester, rig);
    await _tap(tester, find.byKey(const Key('storefront-slot-hero-publish')));
    await _confirm(tester, 'storefront-slot-hero-publish-confirm');
    expect(rig.invoker.bodies, hasLength(1), reason: 'never retried');
    expect(_message(tester, 'hero'), contains(l10n.storefrontRefusalAnimated));
    expect(
      _message(tester, 'hero'),
      contains(l10n.storefrontRefusalPickAnother),
    );
    expect(rig.server.saves, isEmpty);
    expect(find.byKey(const Key('storefront-slot-hero-retry')), findsNothing);
    // The hero has other sources: it is never blocked by a refusal.
    expect(find.byKey(const Key('storefront-slot-hero-refused')), findsNothing);
    expect(_enabled(tester, const Key('storefront-slot-hero-publish')), isTrue);
  });

  group('C12 / CRIT-2: a refused receipt logo for the LOGO slot', () {
    for (final code in [
      'too_many_pixels',
      'dimensions_too_large',
      'aspect_ratio',
      'unsupported_format',
    ]) {
      testWidgets('$code: names the remedy (replace the receipt logo in '
          'Branding, which also changes printed receipts) and disables '
          'Publish for that logo', (tester) async {
        final l10n = await _l10n();
        final rig = _Rig(
          replies: [
            StorefrontFunctionReply(
              httpStatus: 422,
              json: {'ok': false, 'status': 'refused', 'code': code},
            ),
          ],
        );
        await _pump(tester, rig);
        await _tap(
          tester,
          find.byKey(const Key('storefront-slot-logo-publish')),
        );
        await _confirm(tester, 'storefront-slot-logo-publish-confirm');
        expect(rig.invoker.bodies, hasLength(1), reason: 'never retried');
        expect(rig.server.saves, isEmpty);
        final note = tester
            .widget<Text>(find.byKey(const Key('storefront-slot-logo-refused')))
            .data!;
        expect(
          note,
          l10n.storefrontLogoSourceRefused(
            storefrontRefusalMessage(l10n, code),
          ),
        );
        expect(note, contains(l10n.brandingSectionTitle));
        expect(note, contains('receipts'));
        expect(note, contains('8,388,608'));
        // Never the dead-end "pick another source" for the logo slot.
        expect(note, isNot(contains(l10n.storefrontRefusalPickAnother)));
        expect(
          find.byKey(const Key('storefront-slot-logo-message')),
          findsNothing,
        );
        expect(
          _enabled(tester, const Key('storefront-slot-logo-publish')),
          isFalse,
        );
        // The hero is not blocked by the logo slot's refusal.
        expect(
          _enabled(tester, const Key('storefront-slot-hero-publish')),
          isTrue,
        );
      });
    }

    testWidgets('stays disabled for the SAME receipt logo (a re-check keeps '
        'it); a replaced receipt logo lifts the block', (tester) async {
      final l10n = await _l10n();
      const newKey =
          '$_org/$_rest/logo/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee.png';
      final rig = _Rig(
        replies: [
          const StorefrontFunctionReply(
            httpStatus: 422,
            json: {'ok': false, 'status': 'refused', 'code': 'too_many_pixels'},
          ),
          _published(_mediaLogo, key: newKey),
        ],
      );
      await _pump(tester, rig);
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(
        _enabled(tester, const Key('storefront-slot-logo-publish')),
        isFalse,
      );
      // Re-checking while the receipt logo is unchanged keeps the block.
      final loads = rig.sources.loads;
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-recheck')));
      expect(rig.sources.loads, loads + 1);
      expect(
        find.byKey(const Key('storefront-slot-logo-refused')),
        findsOneWidget,
      );
      expect(
        _enabled(tester, const Key('storefront-slot-logo-publish')),
        isFalse,
      );
      expect(rig.invoker.bodies, hasLength(1));

      // The manager replaced the receipt logo in Branding: a new key.
      rig.sources.logo = newKey;
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-recheck')));
      expect(
        find.byKey(const Key('storefront-slot-logo-refused')),
        findsNothing,
      );
      expect(
        _enabled(tester, const Key('storefront-slot-logo-publish')),
        isTrue,
      );
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(rig.invoker.bodies.last['source_key'], newKey);
      expect(rig.server.saves.single.patch, {'logo_media_id': _mediaLogo});
      expect(_message(tester, 'logo'), l10n.storefrontSlotPublished);
    });

    testWidgets('the block survives a reload of the card', (tester) async {
      final rig = _Rig(
        replies: const [
          StorefrontFunctionReply(
            httpStatus: 422,
            json: {'ok': false, 'status': 'refused', 'code': 'aspect_ratio'},
          ),
        ],
      );
      await _pump(tester, rig);
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      // A form save whose re-read fails locks the card; Reload re-reads the
      // whole card (the slots are rebuilt from scratch).
      await tester.enterText(find.byKey(const Key('storefront-tagline')), 'x');
      await tester.pumpAndSettle();
      rig.server.failNextReads = 1;
      await _tap(tester, find.byKey(const Key('storefront-save')));
      expect(find.byKey(const Key('storefront-stale')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('storefront-reload')));
      expect(find.byKey(const Key('storefront-stale')), findsNothing);
      expect(
        find.byKey(const Key('storefront-slot-logo-refused')),
        findsOneWidget,
      );
      expect(
        _enabled(tester, const Key('storefront-slot-logo-publish')),
        isFalse,
      );
    });
  });

  testWidgets('every refusal code has its own copy; unknown falls back', (
    tester,
  ) async {
    final l10n = await _l10n();
    final copies = {
      for (final c in kStorefrontRefusalCodes)
        storefrontRefusalMessage(l10n, c),
    };
    expect(copies, hasLength(kStorefrontRefusalCodes.length));
    expect(storefrontRefusalMessage(l10n, 'x_new'), contains('x_new'));
  });

  testWidgets('403 / 401 / 404 / 409 map to their honest messages', (
    tester,
  ) async {
    final l10n = await _l10n();
    final cases = <StorefrontFunctionReply, String>{
      const StorefrontFunctionReply(
        httpStatus: 403,
        json: {'ok': false, 'status': 'permission_denied'},
      ): l10n.storefrontPublishDenied,
      const StorefrontFunctionReply(
        httpStatus: 401,
        json: {'ok': false, 'status': 'unauthenticated'},
      ): l10n.storefrontPublishUnauthenticated,
      const StorefrontFunctionReply(
        httpStatus: 404,
        json: {'ok': false, 'status': 'source_not_found'},
      ): l10n.storefrontPublishSourceMissing,
      const StorefrontFunctionReply(
        httpStatus: 409,
        json: {'ok': false, 'status': 'restart_required'},
      ): l10n.storefrontPublishRestart,
      const StorefrontFunctionReply(
        httpStatus: 409,
        json: {'ok': false, 'status': 'object_conflict'},
      ): l10n.storefrontPublishObjectConflict,
    };
    for (final entry in cases.entries) {
      final rig = _Rig(replies: [entry.key]);
      await _pump(tester, rig);
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(_message(tester, 'logo'), entry.value);
      expect(rig.server.saves, isEmpty);
    }
  });

  testWidgets('source_not_found reloads the sources', (tester) async {
    final rig = _Rig(
      replies: const [
        StorefrontFunctionReply(
          httpStatus: 404,
          json: {'ok': false, 'status': 'source_not_found'},
        ),
      ],
    );
    await _pump(tester, rig);
    final loads = rig.sources.loads;
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
    await _confirm(tester, 'storefront-slot-logo-publish-confirm');
    expect(rig.sources.loads, greaterThan(loads));
  });

  testWidgets('unknown outcome: refresh, then Try again reuses the SAME id', (
    tester,
  ) async {
    final l10n = await _l10n();
    final rig = _Rig(replies: [_lost, _lost, _published(_mediaLogo)]);
    await _pump(tester, rig);
    final reads = rig.server.reads;
    final lists = rig.media.lists;
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
    await _confirm(tester, 'storefront-slot-logo-publish-confirm');
    // One retry inside the publisher, then uncertain -> refreshed state.
    expect(rig.invoker.bodies, hasLength(2));
    expect(_message(tester, 'logo'), l10n.storefrontMediaUncertain);
    expect(rig.server.reads, greaterThan(reads));
    expect(rig.media.lists, greaterThan(lists));
    expect(rig.server.saves, isEmpty);

    await _tap(tester, find.byKey(const Key('storefront-slot-logo-retry')));
    expect(rig.invoker.bodies, hasLength(3));
    expect(
      rig.invoker.bodies[2]['request_id'],
      rig.invoker.bodies[0]['request_id'],
    );
    expect(rig.invoker.bodies[2]['rung'], 0);
    expect(rig.server.saves.single.patch, {'logo_media_id': _mediaLogo});
    expect(_message(tester, 'logo'), l10n.storefrontSlotPublished);
  });

  testWidgets('an uncertain slot assignment: Try again replays the SAME '
      'request (id + expected version), never a false conflict', (
    tester,
  ) async {
    final l10n = await _l10n();
    final rig = _Rig(replies: [_published(_mediaLogo)]);
    await _pump(tester, rig);
    // The CAS write COMMITS, but its answer is lost, and the reads that
    // follow (the refresh, then the retry's re-read) fail too: the card
    // keeps the old version and the old (empty) pointer.
    rig.server
      ..loseSaveAnswers = 1
      ..failReadsAfterLoss = 2;
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
    await _confirm(tester, 'storefront-slot-logo-publish-confirm');
    expect(rig.server.saves.single.expectedVersion, 1);
    expect(rig.server.profile['version'], 2, reason: 'it did commit');
    expect(_message(tester, 'logo'), l10n.storefrontErrorUncertain);
    expect(find.byKey(const Key('storefront-slot-logo-empty')), findsOneWidget);

    await _tap(tester, find.byKey(const Key('storefront-slot-logo-retry')));
    expect(rig.server.saves, hasLength(2));
    expect(rig.server.saves[1].requestId, rig.server.saves[0].requestId);
    expect(rig.server.saves[1].expectedVersion, 1);
    expect(rig.server.saves[1].patch, {'logo_media_id': _mediaLogo});
    expect(rig.server.profile['version'], 2, reason: 'never applied twice');
    expect(_message(tester, 'logo'), l10n.storefrontSlotPublished);
    expect(
      find.byKey(const Key('storefront-slot-logo-remove')),
      findsOneWidget,
    );
  });

  testWidgets('an uncertain slot assignment whose retry re-read already '
      'shows it placed: no second write', (tester) async {
    final l10n = await _l10n();
    final rig = _Rig(replies: [_published(_mediaLogo)]);
    await _pump(tester, rig);
    rig.server
      ..loseSaveAnswers = 1
      ..failReadsAfterLoss = 1;
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
    await _confirm(tester, 'storefront-slot-logo-publish-confirm');
    expect(_message(tester, 'logo'), l10n.storefrontErrorUncertain);
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-retry')));
    expect(rig.server.saves, hasLength(1));
    expect(_message(tester, 'logo'), l10n.storefrontSlotPublished);
  });

  testWidgets('answers that may follow the stage step refresh the server '
      'state: a STAGED row left behind shows up and can be discarded', (
    tester,
  ) async {
    final l10n = await _l10n();
    final cases = <StorefrontFunctionReply, String>{
      const StorefrontFunctionReply(
        httpStatus: 403,
        json: {'ok': false, 'status': 'permission_denied'},
      ): l10n.storefrontPublishDenied,
      const StorefrontFunctionReply(
        httpStatus: 401,
        json: {'ok': false, 'status': 'unauthenticated'},
      ): l10n.storefrontPublishUnauthenticated,
      const StorefrontFunctionReply(
        httpStatus: 409,
        json: {'ok': false, 'status': 'object_conflict'},
      ): l10n.storefrontPublishObjectConflict,
      const StorefrontFunctionReply(
        httpStatus: 409,
        json: {'ok': false, 'status': 'restart_required'},
      ): l10n.storefrontPublishRestart,
      // The platform gateway while the function is not deployed.
      const StorefrontFunctionReply(
        httpStatus: 404,
        json: {
          'code': 'NOT_FOUND',
          'message': 'Requested function was not found',
        },
      ): l10n.storefrontPublishServiceUnavailable,
    };
    for (final entry in cases.entries) {
      final rig = _Rig(replies: [entry.key]);
      await _pump(tester, rig);
      final reads = rig.server.reads;
      final lists = rig.media.lists;
      // The function registered a STAGED row before it stopped.
      rig.server.rows.add(_row(_mediaStaged, state: 'staged'));
      expect(
        find.byKey(const Key('storefront-media-discard-$_mediaStaged')),
        findsNothing,
      );
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(_message(tester, 'logo'), entry.value);
      expect(rig.server.reads, greaterThan(reads));
      expect(rig.media.lists, greaterThan(lists));
      expect(
        find.byKey(const Key('storefront-media-discard-$_mediaStaged')),
        findsOneWidget,
      );
      expect(rig.server.saves, isEmpty);
      expect(rig.invoker.bodies, hasLength(1));
    }
  });

  testWidgets('a stage validation code is a fault: its own copy, never '
      '"pick another source"', (tester) async {
    final l10n = await _l10n();
    final rig = _Rig(
      replies: const [
        StorefrontFunctionReply(
          httpStatus: 422,
          json: {
            'ok': false,
            'status': 'refused',
            'code': 'variant_not_allowed',
          },
        ),
      ],
    );
    await _pump(tester, rig);
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
    await _confirm(tester, 'storefront-slot-logo-publish-confirm');
    expect(_message(tester, 'logo'), l10n.storefrontPublishInvalidRequest);
    expect(
      _message(tester, 'logo'),
      isNot(contains(l10n.storefrontRefusalPickAnother)),
    );
    expect(rig.invoker.bodies, hasLength(1));
    expect(rig.server.saves, isEmpty);
  });

  testWidgets('remove from storefront: confirm, then clear the pointer', (
    tester,
  ) async {
    final l10n = await _l10n();
    final rig = _Rig(
      rows: [_row(_mediaLogo)],
      profile: _profileJson(logo: _mediaLogo),
    );
    await _pump(tester, rig);
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-remove')));
    expect(find.text(l10n.storefrontSlotRemoveConfirmBody), findsOneWidget);
    await _confirm(tester, 'storefront-slot-logo-remove-confirm');
    expect(rig.server.saves.single.patch, {'logo_media_id': null});
    expect(_message(tester, 'logo'), l10n.storefrontSlotRemoved);
    // The row stays LIVE and can now be retracted.
    expect(
      find.byKey(const Key('storefront-media-retract-$_mediaLogo')),
      findsOneWidget,
    );
  });

  testWidgets('Use here points the slot at an existing live copy', (
    tester,
  ) async {
    final rig = _Rig(rows: [_row(_mediaHero, variant: 'w960')]);
    await _pump(tester, rig);
    await _tap(
      tester,
      find.byKey(const Key('storefront-media-use-$_mediaHero')),
    );
    expect(rig.server.saves.single.patch, {'hero_media_id': _mediaHero});
  });

  testWidgets('retract: confirmation, the object is kept, the list refreshes', (
    tester,
  ) async {
    final l10n = await _l10n();
    final rig = _Rig(rows: [_row(_mediaOld)]);
    await _pump(tester, rig);
    await _tap(
      tester,
      find.byKey(const Key('storefront-media-retract-$_mediaOld')),
    );
    expect(find.text(l10n.storefrontMediaRetractConfirmBody), findsOneWidget);
    await _confirm(tester, 'storefront-media-retract-confirm-$_mediaOld');
    expect(rig.media.actions.single.$1, 'retract');
    expect(rig.media.actions.single.$2, _mediaOld);
    expect(_message(tester, 'logo'), l10n.storefrontMediaRetracted);
    expect(find.text(l10n.storefrontMediaStateRetracted), findsOneWidget);
    expect(
      find.byKey(const Key('storefront-media-retract-$_mediaOld')),
      findsNothing,
    );
  });

  testWidgets('an in-use row has no Retract; a raced media_in_use is '
      'explained', (tester) async {
    final l10n = await _l10n();
    final rig = _Rig(
      rows: [_row(_mediaLogo), _row(_mediaOld)],
      profile: _profileJson(logo: _mediaLogo),
    );
    await _pump(tester, rig);
    expect(
      find.byKey(const Key('storefront-media-retract-$_mediaLogo')),
      findsNothing,
    );
    expect(
      find.byKey(Key('storefront-media-in-use-note-$_mediaLogo')),
      findsOneWidget,
    );
    rig.media.scripted.add(
      const StorefrontMediaActionResult(
        StorefrontMediaActionStatus.mediaInUse,
        mediaId: _mediaOld,
        requestId: _retryId,
        slots: [StorefrontSlot.hero],
      ),
    );
    await _tap(
      tester,
      find.byKey(const Key('storefront-media-retract-$_mediaOld')),
    );
    await _confirm(tester, 'storefront-media-retract-confirm-$_mediaOld');
    expect(
      _message(tester, 'logo'),
      l10n.storefrontMediaInUseError(l10n.storefrontSlotHeroTitle),
    );
  });

  testWidgets('discard a STAGED row: confirmation, then cancel', (
    tester,
  ) async {
    final l10n = await _l10n();
    final rig = _Rig(rows: [_row(_mediaStaged, state: 'staged')]);
    await _pump(tester, rig);
    expect(
      find.byKey(const Key('storefront-media-retract-$_mediaStaged')),
      findsNothing,
    );
    await _tap(
      tester,
      find.byKey(const Key('storefront-media-discard-$_mediaStaged')),
    );
    await _confirm(tester, 'storefront-media-discard-confirm-$_mediaStaged');
    expect(rig.media.actions.single.$1, 'cancel');
    expect(_message(tester, 'logo'), l10n.storefrontMediaDiscarded);
    expect(
      find.byKey(const Key('storefront-media-row-$_mediaStaged')),
      findsNothing,
    );
  });

  testWidgets('an unknown retract outcome refreshes; Try again reuses the '
      'SAME request id', (tester) async {
    final l10n = await _l10n();
    final rig = _Rig(rows: [_row(_mediaOld)]);
    await _pump(tester, rig);
    rig.media.scripted.add(
      const StorefrontMediaActionResult(
        StorefrontMediaActionStatus.uncertain,
        mediaId: _mediaOld,
        requestId: _retryId,
      ),
    );
    final lists = rig.media.lists;
    await _tap(
      tester,
      find.byKey(const Key('storefront-media-retract-$_mediaOld')),
    );
    await _confirm(tester, 'storefront-media-retract-confirm-$_mediaOld');
    expect(_message(tester, 'logo'), l10n.storefrontMediaUncertain);
    expect(rig.media.lists, greaterThan(lists));
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-retry')));
    expect(rig.media.actions, hasLength(2));
    expect(rig.media.actions[1].$3, _retryId);
    expect(_message(tester, 'logo'), l10n.storefrontMediaRetracted);
  });

  testWidgets('DB-4: a retract REPLAY answered stale_request (the copy was '
      're-published since) re-reads the list and never claims "retracted"', (
    tester,
  ) async {
    final l10n = await _l10n();
    final rig = _Rig(rows: [_row(_mediaOld)]);
    await _pump(tester, rig);
    rig.media.scripted.addAll(const [
      StorefrontMediaActionResult(
        StorefrontMediaActionStatus.uncertain,
        mediaId: _mediaOld,
        requestId: _retryId,
      ),
      StorefrontMediaActionResult(
        StorefrontMediaActionStatus.staleRequest,
        mediaId: _mediaOld,
        requestId: _retryId,
      ),
    ]);
    await _tap(
      tester,
      find.byKey(const Key('storefront-media-retract-$_mediaOld')),
    );
    await _confirm(tester, 'storefront-media-retract-confirm-$_mediaOld');
    expect(_message(tester, 'logo'), l10n.storefrontMediaUncertain);
    final lists = rig.media.lists;
    await _tap(tester, find.byKey(const Key('storefront-slot-logo-retry')));
    expect(rig.media.actions, hasLength(2));
    expect(rig.media.actions[1].$3, _retryId, reason: 'the SAME request');
    expect(_message(tester, 'logo'), l10n.storefrontMediaStaleRequest);
    expect(find.text(l10n.storefrontMediaRetracted), findsNothing);
    expect(rig.media.lists, greaterThan(lists), reason: 'authority re-read');
    // The server's state is shown: the copy is LIVE, Retract is offered.
    expect(find.text(l10n.storefrontMediaStateRetracted), findsNothing);
    expect(
      find.byKey(const Key('storefront-media-retract-$_mediaOld')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('storefront-slot-logo-retry')), findsNothing);
  });

  testWidgets('media actions are locked while the form has unsaved edits', (
    tester,
  ) async {
    final rig = _Rig(rows: [_row(_mediaOld)]);
    await _pump(tester, rig);
    expect(_enabled(tester, const Key('storefront-slot-logo-publish')), isTrue);
    await tester.enterText(find.byKey(const Key('storefront-tagline')), 'x');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('storefront-media-save-first')),
      findsOneWidget,
    );
    expect(
      _enabled(tester, const Key('storefront-slot-logo-publish')),
      isFalse,
    );
    final retract = tester.widget<TextButton>(
      find.byKey(const Key('storefront-media-retract-$_mediaOld')),
    );
    expect(retract.onPressed, isNull);
  });

  testWidgets('no publisher wired: an honest note instead of the slots', (
    tester,
  ) async {
    final l10n = await _l10n();
    final rig = _Rig(withPublisher: false);
    await _pump(tester, rig);
    expect(find.text(l10n.storefrontMediaUnavailable), findsOneWidget);
    expect(find.byKey(const Key('storefront-slot-logo')), findsNothing);
    expect(rig.sources.loads, 0, reason: 'no source reads without a publisher');
  });

  group('a refused slot write is explained, never "right now"', () {
    testWidgets('publish_precondition on Remove: the reason and the blocker '
        'codes, no transient copy, no Try again', (tester) async {
      final l10n = await _l10n();
      final rig = _Rig(
        rows: [_row(_mediaHero, variant: 'w960')],
        profile: _profileJson(hero: _mediaHero),
      );
      await _pump(tester, rig);
      rig.server.saveOverrides.add(
        const StorefrontWriteResult(
          StorefrontWriteStatus.invalid,
          reason: 'publish_precondition',
          blockers: ['no_live_item', 'tax_not_exclusive'],
        ),
      );
      await _tap(tester, find.byKey(const Key('storefront-slot-hero-remove')));
      await _confirm(tester, 'storefront-slot-hero-remove-confirm');
      expect(rig.server.saves.single.patch, {'hero_media_id': null});
      expect(_message(tester, 'hero'), l10n.storefrontSlotPreconditionRefused);
      expect(
        _message(tester, 'hero'),
        isNot(contains(l10n.storefrontErrorUnavailable)),
      );
      for (final (code, label) in [
        ('no_live_item', l10n.storefrontBlockerNoLiveItem),
        ('tax_not_exclusive', l10n.storefrontBlockerTaxNotExclusive),
      ]) {
        expect(
          tester
              .widget<Text>(
                find.byKey(Key('storefront-slot-hero-blocker-$code')),
              )
              .data,
          label,
        );
      }
      expect(find.byKey(const Key('storefront-slot-hero-retry')), findsNothing);
      // The pointer is untouched (the server refused the write).
      expect(
        find.byKey(const Key('storefront-slot-hero-remove')),
        findsOneWidget,
      );
    });

    testWidgets('publish_precondition right after a publish: published but '
        'not placed, with the reason — never "use it from the list"', (
      tester,
    ) async {
      final l10n = await _l10n();
      final rig = _Rig(replies: [_published(_mediaLogo)]);
      await _pump(tester, rig);
      rig.server.saveOverrides.add(
        const StorefrontWriteResult(
          StorefrontWriteStatus.invalid,
          reason: 'publish_precondition',
          blockers: ['currency_not_ils'],
        ),
      );
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(rig.server.saves.single.patch, {'logo_media_id': _mediaLogo});
      final message = _message(tester, 'logo');
      expect(message, startsWith(l10n.storefrontSlotPublishedNotPlaced));
      expect(message, contains(l10n.storefrontSlotPreconditionRefused));
      expect(message, isNot(contains(l10n.storefrontSlotPlaceFailed)));
      expect(message, isNot(contains(l10n.storefrontErrorUnavailable)));
      expect(
        find.byKey(const Key('storefront-slot-logo-blocker-currency_not_ils')),
        findsOneWidget,
      );
      // The published copy is LIVE in the list (usable once fixed).
      expect(
        find.byKey(const Key('storefront-media-use-$_mediaLogo')),
        findsOneWidget,
      );
    });

    testWidgets('hero_media_id_invalid on Use here: its own reason copy', (
      tester,
    ) async {
      final l10n = await _l10n();
      final rig = _Rig(rows: [_row(_mediaHero, variant: 'w960')]);
      await _pump(tester, rig);
      rig.server.saveOverrides.add(
        const StorefrontWriteResult(
          StorefrontWriteStatus.invalid,
          reason: 'hero_media_id_invalid',
        ),
      );
      await _tap(
        tester,
        find.byKey(const Key('storefront-media-use-$_mediaHero')),
      );
      expect(_message(tester, 'hero'), l10n.storefrontReasonHeroMediaIdInvalid);
      expect(
        find.byKey(
          const Key('storefront-slot-hero-blocker-hero_media_id_invalid'),
        ),
        findsNothing,
      );
    });

    testWidgets('logo_media_id_invalid right after a publish: published but '
        'not placed, and why', (tester) async {
      final l10n = await _l10n();
      final rig = _Rig(replies: [_published(_mediaLogo)]);
      await _pump(tester, rig);
      rig.server.saveOverrides.add(
        const StorefrontWriteResult(
          StorefrontWriteStatus.invalid,
          reason: 'logo_media_id_invalid',
        ),
      );
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(
        _message(tester, 'logo'),
        '${l10n.storefrontSlotPublishedNotPlaced} '
        '${l10n.storefrontReasonLogoMediaIdInvalid}',
      );
    });

    testWidgets('a transient failure keeps the transient copy', (tester) async {
      final l10n = await _l10n();
      final rig = _Rig(rows: [_row(_mediaHero, variant: 'w960')]);
      await _pump(tester, rig);
      rig.server.saveOverrides.add(
        const StorefrontWriteResult(StorefrontWriteStatus.unavailable),
      );
      await _tap(
        tester,
        find.byKey(const Key('storefront-media-use-$_mediaHero')),
      );
      expect(_message(tester, 'hero'), l10n.storefrontErrorUnavailable);
    });
  });

  group('the logo source is the CURRENT receipt logo at the press', () {
    testWidgets('replaced since the page loaded: nothing is published, the '
        'sources reload, and the next press publishes the new logo', (
      tester,
    ) async {
      final l10n = await _l10n();
      const newKey =
          '$_org/$_rest/logo/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee.png';
      final rig = _Rig(replies: [_published(_mediaLogo, key: newKey)]);
      await _pump(tester, rig);
      final loads = rig.sources.loads;
      // The Branding card replaced the receipt logo meanwhile.
      rig.sources.logo = newKey;
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(rig.invoker.bodies, isEmpty, reason: 'the OLD logo never goes');
      expect(rig.server.saves, isEmpty);
      expect(rig.sources.loads, greaterThan(loads));
      expect(_message(tester, 'logo'), l10n.storefrontSourceLogoChanged);
      expect(find.byKey(const Key('storefront-slot-logo-retry')), findsNothing);

      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(rig.invoker.bodies.single['source_key'], newKey);
      expect(rig.server.saves.single.patch, {'logo_media_id': _mediaLogo});
      expect(_message(tester, 'logo'), l10n.storefrontSlotPublished);
    });

    testWidgets('the receipt logo was removed: nothing is published', (
      tester,
    ) async {
      final l10n = await _l10n();
      final rig = _Rig(replies: [_published(_mediaLogo)]);
      await _pump(tester, rig);
      rig.sources.logo = null;
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(rig.invoker.bodies, isEmpty);
      // Not "press Publish image again": there is no logo left to publish.
      expect(_message(tester, 'logo'), l10n.storefrontSourceLogoRemoved);
      expect(
        find.byKey(const Key('storefront-slot-logo-no-source')),
        findsOneWidget,
      );
    });

    testWidgets('the check cannot be made: nothing is published', (
      tester,
    ) async {
      final l10n = await _l10n();
      final rig = _Rig(replies: [_published(_mediaLogo)]);
      await _pump(tester, rig);
      rig.sources.logoUnavailable = true;
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-publish')));
      await _confirm(tester, 'storefront-slot-logo-publish-confirm');
      expect(rig.invoker.bodies, isEmpty);
      expect(_message(tester, 'logo'), l10n.storefrontSourceLogoUnverified);
      // Once the check can be made, Try again sends THIS request.
      rig.sources.logoUnavailable = false;
      await _tap(tester, find.byKey(const Key('storefront-slot-logo-retry')));
      expect(rig.invoker.bodies.single['source_key'], _logoKey);
      expect(rig.server.saves.single.patch, {'logo_media_id': _mediaLogo});
      expect(_message(tester, 'logo'), l10n.storefrontSlotPublished);
    });

    testWidgets('a menu-image source needs no receipt-logo check', (
      tester,
    ) async {
      final rig = _Rig(
        replies: [
          _published(
            _mediaHero,
            variant: 'w960',
            bucket: 'menu-images',
            key: _menuKey,
          ),
        ],
      );
      await _pump(tester, rig);
      final loads = rig.sources.loads;
      await _tap(tester, find.byKey(const Key('storefront-slot-hero-source')));
      await tester.tap(find.text('Menu item: Margherita').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('storefront-slot-hero-publish')));
      await _confirm(tester, 'storefront-slot-hero-publish-confirm');
      expect(rig.sources.loads, loads);
      expect(rig.invoker.bodies.single['source_key'], _menuKey);
    });
  });

  group('a failed source read is not "no source"', () {
    testWidgets('logo: only the unavailable note and a retry that reloads', (
      tester,
    ) async {
      final l10n = await _l10n();
      final rig = _Rig(sources: _Sources(logoUnavailable: true));
      await _pump(tester, rig);
      expect(find.text(l10n.storefrontSourceNoReceiptLogo), findsNothing);
      expect(
        find.byKey(const Key('storefront-slot-logo-no-source')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('storefront-slot-logo-sources-unavailable')),
        findsOneWidget,
      );
      expect(
        _enabled(tester, const Key('storefront-slot-logo-publish')),
        isFalse,
      );
      // The hero still lists the menu original, and says the logo read
      // failed.
      expect(
        find.byKey(const Key('storefront-slot-hero-source')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('storefront-slot-hero-sources-unavailable')),
        findsOneWidget,
      );

      final loads = rig.sources.loads;
      final reads = rig.server.reads;
      rig.sources.logoUnavailable = false;
      await _tap(
        tester,
        find.byKey(const Key('storefront-slot-logo-sources-retry')),
      );
      expect(rig.sources.loads, loads + 1);
      expect(rig.server.reads, greaterThan(reads));
      expect(
        find.byKey(const Key('storefront-slot-logo-sources-unavailable')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('storefront-slot-logo-source')),
        findsOneWidget,
      );
      expect(
        _enabled(tester, const Key('storefront-slot-logo-publish')),
        isTrue,
      );
    });

    testWidgets('hero: both reads failed — never "none yet"', (tester) async {
      final l10n = await _l10n();
      final rig = _Rig(
        sources: _Sources(logoUnavailable: true, menuUnavailable: true),
      );
      await _pump(tester, rig);
      expect(find.text(l10n.storefrontSourceNone), findsNothing);
      expect(
        find.byKey(const Key('storefront-slot-hero-no-source')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('storefront-slot-hero-sources-retry')),
        findsOneWidget,
      );
    });

    testWidgets('a read that succeeded with nothing in it still says so', (
      tester,
    ) async {
      final l10n = await _l10n();
      final rig = _Rig(sources: _Sources(logo: null));
      await _pump(tester, rig);
      expect(find.text(l10n.storefrontSourceNoReceiptLogo), findsOneWidget);
      expect(
        find.byKey(const Key('storefront-slot-logo-sources-retry')),
        findsNothing,
      );
    });
  });

  testWidgets('the preview uses the injected public URL of the object key', (
    tester,
  ) async {
    final rig = _Rig(
      rows: [_row(_mediaLogo)],
      profile: _profileJson(logo: _mediaLogo),
    );
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final asked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StorefrontSection(
              seams: StorefrontEditorSeams(
                scopeIdentity: rig.seams.scopeIdentity,
                profileRepository: rig.seams.profileRepository,
                mediaRepository: rig.seams.mediaRepository,
                branchSource: rig.seams.branchSource,
                sourceCatalog: rig.seams.sourceCatalog,
                publisher: rig.seams.publisher,
                publicUrlFor: (key) {
                  asked.add(key);
                  return Uri.parse('https://cdn.test/storefront-media/$key');
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
      find.byKey(const Key('storefront-slot-logo-preview')),
    );
    final provider = image.image as NetworkImage;
    expect(provider.url, startsWith('https://cdn.test/storefront-media/'));
    expect(asked, contains(rig.server.rows.single['object_key']));
  });
}
