import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_section.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_sources.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// STOREFRONT-PUBLISH-001 — the Storefront card at a 360 px phone width (no
/// overflow; fields stack), on a wide desktop (fields pair up like the rest
/// of Settings), and in ar / he (RTL) / en (LTR) with the slug, path and
/// times kept as LTR islands.
const _org = '11111111-1111-4111-8111-111111111111';
const _rest = '22222222-2222-4222-8222-222222222222';
const _branch = '33333333-3333-4333-8333-333333333333';
const _live = '55555555-5555-4555-8555-555555555555';
const _staged = '66666666-6666-4666-8666-666666666666';
const _retracted = '77777777-7777-4777-8777-777777777777';

Map<String, Object?> _profileJson() => {
  'restaurant_id': _rest,
  'storefront_branch_id': _branch,
  'slug': 'a-rather-long-storefront-slug-for-layout-tests',
  'display_name': 'The Long Named Neighbourhood Kitchen and Bakery',
  'tagline': 'Fresh bread, slow coffee and a very long tagline indeed',
  'public_city': 'Haifa',
  'public_address': '12 Harbour Street',
  'public_phone': '+972501234567',
  'primary_color': '#e07b2c',
  'accent_color': '#e07b2c',
  'visual_preset': 'dark',
  'locale_default': 'ar',
  'card_mode': 'list',
  'motion': 'full',
  'pickup_enabled': true,
  'paused_until': '2026-10-01T15:00:00Z',
  'pause_reason': 'Staff training',
  'opening_hours': {
    'weekly': [
      {'dow': 0, 'open': '08:00', 'close': '12:00'},
      {'dow': 0, 'open': '13:00', 'close': '17:00'},
      {'dow': 0, 'open': '18:00', 'close': '02:00'},
      {'dow': 5, 'open': '09:00', 'close': '23:30'},
    ],
    'exceptions': [
      {'date': '2026-12-25', 'closed': true},
      {'date': '2026-12-31', 'open': '10:00', 'close': '01:00'},
    ],
  },
  'logo_media_id': _live,
  'hero_media_id': null,
  'is_published': false,
  'version': 3,
};

Map<String, Object?> _row(String id, String state, List<String> inUse) => {
  'id': id,
  'source_bucket': 'restaurant-logos',
  'source_key': '$_org/$_rest/logo/x.png',
  'variant': 'w480',
  'object_key': 'prefix0/${'a' * 64}.webp',
  'content_hash': 'a' * 64,
  'width': 480,
  'height': 480,
  'bytes': 40000,
  'state': state,
  'published_at': state == 'staged' ? null : '2026-09-24T10:00:00Z',
  'unpublished_at': state == 'retracted' ? '2026-09-24T11:00:00Z' : null,
  'created_at': '2026-09-24T09:00:00Z',
  'in_use': inUse,
};

class _FakeProfileRepo implements StorefrontProfileRepository {
  _FakeProfileRepo({this.exists = true, this.overrides = const {}});

  final bool exists;

  /// Profile fields replaced for a variant (published, other hours...).
  final Map<String, Object?> overrides;

  @override
  Future<StorefrontProfileRead> read() async => StorefrontProfileRead.ok(
    exists: exists,
    version: exists ? 3 : 0,
    profile: exists
        ? StorefrontProfile.fromJson({..._profileJson(), ...overrides})
        : null,
    derived: StorefrontDerived.fromJson({
      'timezone': 'Asia/Jerusalem',
      'currency_code': 'ILS',
      'tax': null,
      'publish_ready': false,
      'publish_blockers': [
        'timezone_missing',
        'currency_not_ils',
        'tax_not_exclusive',
        'no_live_item',
        'hours_missing',
      ],
      'media_prefix': 'prefix0',
    }),
  );

  @override
  Future<StorefrontWriteResult> save({
    required int expectedVersion,
    required Map<String, Object?> patch,
    String? requestId,
  }) async => const StorefrontWriteResult(
    StorefrontWriteStatus.invalid,
    reason: 'publish_precondition',
    blockers: ['hours_missing'],
  );
}

class _FakeMediaRepo implements StorefrontMediaRepository {
  @override
  Future<StorefrontMediaList> list() async => StorefrontMediaList.ok(
    mediaPrefix: 'prefix0',
    media: decodeStorefrontMediaRows([
      _row(_live, 'published', ['logo']),
      _row(_staged, 'staged', []),
      _row(_retracted, 'retracted', []),
    ], 'media'),
  );

  @override
  Future<StorefrontMediaActionResult> retract(
    String mediaId, {
    String? requestId,
  }) => throw StateError('not used');

  @override
  Future<StorefrontMediaActionResult> cancel(
    String mediaId, {
    String? requestId,
  }) => throw StateError('not used');
}

class _FakeBranches implements StorefrontBranchSource {
  _FakeBranches({this.suspended = false});

  final bool suspended;

  @override
  Future<List<StorefrontBranchOption>?> list() async => [
    StorefrontBranchOption(
      id: _branch,
      name: 'Downtown branch with a remarkably long display name',
      status: suspended ? 'suspended' : 'active',
    ),
  ];
}

class _FakeSources implements StorefrontSourceCatalog {
  @override
  Future<StorefrontSourceOptions> load() async => const StorefrontSourceOptions(
    receiptLogoKey: '$_org/$_rest/logo/x.png',
    menuImages: [
      StorefrontMenuImageOption(
        itemId: 'i1',
        itemName: 'Shakshuka with an unusually long menu item name',
        imageKey: '$_org/$_rest/global/menu_item/i1/img.jpg',
      ),
    ],
  );
}

class _NeverInvoker implements StorefrontFunctionInvoker {
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async =>
      const StorefrontFunctionReply.transportFailure();
}

/// Refuses every source (the c4 envelope: too many pixels).
class _RefusingInvoker implements StorefrontFunctionInvoker {
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async =>
      const StorefrontFunctionReply(
        httpStatus: 422,
        json: {'ok': false, 'status': 'refused', 'code': 'too_many_pixels'},
      );
}

StorefrontEditorSeams _seams({
  bool exists = true,
  Map<String, Object?> overrides = const {},
  bool suspended = false,
  StorefrontFunctionInvoker? invoker,
}) => StorefrontEditorSeams(
  scopeIdentity: 'm-1|$_org|$_rest|manager',
  profileRepository: _FakeProfileRepo(exists: exists, overrides: overrides),
  mediaRepository: _FakeMediaRepo(),
  branchSource: _FakeBranches(suspended: suspended),
  sourceCatalog: _FakeSources(),
  publisher: StorefrontMediaPublisher(
    invoker: invoker ?? _NeverInvoker(),
    organizationId: _org,
    restaurantId: _rest,
    retryDelay: Duration.zero,
  ),
);

/// Collects RenderFlex overflows reported through [FlutterError.onError]
/// (they do NOT reach `tester.takeException()` in this harness). The handler
/// is restored BEFORE returning, so the caller's expectations run clean.
Future<List<String>> _overflowsDuring(Future<void> Function() body) async {
  final out = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      out.add(text.split('\n').first.trim());
    } else {
      previous?.call(details);
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return out;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required Size size,
  String locale = 'en',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: Locale(locale),
      home: Scaffold(
        // The Settings page wraps its cards in a ListView with lg padding.
        body: ListView(padding: const EdgeInsets.all(16), children: [child]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls the whole list, painting every part of the card.
Future<void> _scrollThrough(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the overflow capture is not vacuous (a real overflow is seen)', (
    tester,
  ) async {
    final overflows = await _overflowsDuring(() async {
      await _pump(
        tester,
        const SizedBox(
          width: 100,
          child: Row(children: [SizedBox(width: 400, height: 10)]),
        ),
        size: const Size(360, 800),
      );
    });
    expect(overflows, isNotEmpty);
  });

  for (final locale in ['en', 'ar', 'he']) {
    testWidgets('360x800 [$locale]: the full editor has no overflow', (
      tester,
    ) async {
      final overflows = await _overflowsDuring(() async {
        await _pump(
          tester,
          StorefrontSection(seams: _seams()),
          size: const Size(360, 800),
          locale: locale,
        );
        // Show a banner with blockers too (a refused save).
        await tester.enterText(
          find.byKey(const Key('storefront-tagline')),
          'x',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('storefront-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('storefront-save')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('storefront-banner')), findsOneWidget);
        await _scrollThrough(tester);
      });
      expect(overflows, isEmpty);
    });

    testWidgets('360x800 [$locale]: the C9-C12 notes (published + '
        'availability, a suspended branch, overlap / spill warnings, a '
        'refused receipt logo) have no overflow', (tester) async {
      final overflows = await _overflowsDuring(() async {
        await _pump(
          tester,
          StorefrontSection(
            seams: _seams(
              overrides: {
                'is_published': true,
                'opening_hours': {
                  'weekly': [
                    {'dow': 1, 'open': '09:00', 'close': '17:00'},
                    {'dow': 1, 'open': '09:00', 'close': '17:00'},
                    {'dow': 2, 'open': '09:00', 'close': '12:00'},
                    {'dow': 2, 'open': '11:00', 'close': '23:00'},
                    {'dow': 6, 'open': '20:00', 'close': '03:00'},
                    {'dow': 0, 'open': '01:00', 'close': '11:00'},
                  ],
                  'exceptions': <Object?>[],
                },
              },
              suspended: true,
              invoker: _RefusingInvoker(),
            ),
          ),
          size: const Size(360, 800),
          locale: locale,
        );
        final publish = find.byKey(const Key('storefront-slot-logo-publish'));
        await tester.ensureVisible(publish);
        await tester.pumpAndSettle();
        await tester.tap(publish);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('storefront-slot-logo-publish-confirm-action')),
        );
        await tester.pumpAndSettle();
        for (final key in [
          'storefront-availability-note',
          'storefront-branch-suspended',
          'storefront-hours-duplicate-1',
          'storefront-hours-overlap-2',
          'storefront-hours-spill-6',
          'storefront-slot-logo-refused',
          'storefront-slot-logo-recheck',
        ]) {
          expect(
            find.byKey(Key(key), skipOffstage: false),
            findsOneWidget,
            reason: key,
          );
        }
        await _scrollThrough(tester);
      });
      expect(overflows, isEmpty);
    });

    testWidgets('360x800 [$locale]: the create form has no overflow', (
      tester,
    ) async {
      final overflows = await _overflowsDuring(() async {
        await _pump(
          tester,
          StorefrontSection(
            seams: _seams(exists: false),
            defaultDisplayName: 'The Long Named Neighbourhood Kitchen',
          ),
          size: const Size(360, 800),
          locale: locale,
        );
        await _scrollThrough(tester);
      });
      expect(overflows, isEmpty);
    });
  }

  testWidgets('360 px: fields stack; 1400 px: they pair up', (tester) async {
    await _pump(
      tester,
      StorefrontSection(seams: _seams()),
      size: const Size(360, 3000),
    );
    const name = Key('storefront-display-name');
    const tagline = Key('storefront-tagline');
    expect(
      tester.getTopLeft(find.byKey(tagline)).dy,
      greaterThan(tester.getTopLeft(find.byKey(name)).dy),
    );

    final wide = await _overflowsDuring(() async {
      await _pump(
        tester,
        StorefrontSection(key: UniqueKey(), seams: _seams()),
        size: const Size(1400, 3000),
      );
    });
    expect(wide, isEmpty);
    // Rows pair up: (branch, name), (tagline, city), (address, phone).
    const city = Key('storefront-city');
    expect(
      tester.getTopLeft(find.byKey(city)).dy,
      tester.getTopLeft(find.byKey(tagline)).dy,
    );
    expect(
      tester.getTopLeft(find.byKey(city)).dx,
      isNot(tester.getTopLeft(find.byKey(tagline)).dx),
    );
  });

  for (final (locale, direction) in [
    ('en', TextDirection.ltr),
    ('ar', TextDirection.rtl),
    ('he', TextDirection.rtl),
  ]) {
    testWidgets('[$locale] renders localized with $direction and LTR islands', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(Locale(locale));
      await _pump(
        tester,
        StorefrontSection(seams: _seams()),
        size: const Size(1200, 4000),
        locale: locale,
      );
      final section = find.byKey(const Key('storefront-section'));
      expect(Directionality.of(tester.element(section)), direction);
      expect(find.text(l10n.storefrontSectionTitle), findsOneWidget);
      expect(find.text(l10n.storefrontLocaleHelp), findsOneWidget);
      expect(find.text(l10n.storefrontPauseHelp), findsOneWidget);
      expect(find.text(l10n.storefrontBlockerNoLiveItem), findsOneWidget);
      // Slug, path and times are LTR islands in every locale.
      for (final key in ['storefront-slug-readonly', 'storefront-path']) {
        expect(
          tester.widget<Text>(find.byKey(Key(key))).textDirection,
          TextDirection.ltr,
          reason: key,
        );
      }
      expect(
        tester.widget<Text>(find.text('18:00').first).textDirection,
        TextDirection.ltr,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-phone')))
            .textDirection,
        TextDirection.ltr,
      );
      if (locale != 'en') {
        // Real translations, not English copies.
        final en = await AppLocalizations.delegate.load(const Locale('en'));
        expect(l10n.storefrontSectionTitle, isNot(en.storefrontSectionTitle));
        expect(l10n.storefrontPauseHelp, isNot(en.storefrontPauseHelp));
      }
    });
  }
}
