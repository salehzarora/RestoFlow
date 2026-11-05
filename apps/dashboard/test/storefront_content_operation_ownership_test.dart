import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_copy.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_featured_items.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_section.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_settings_group.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_sources.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'helpers/storefront_content_groups.dart';
import 'helpers/storefront_settings_groups.dart';

// Real StorefrontSection -> real StorefrontContentSection composition. Only
// repositories/function I/O are synthetic; there is no fake parent callback.
const _restaurant = '22222222-2222-4222-8222-222222222222';
const _branch = '33333333-3333-4333-8333-333333333333';
const _item = '44444444-4444-4444-8444-444444444444';
const _mediaId = '55555555-5555-4555-8555-555555555555';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('OFFLINE_OPERATION_OWNERSHIP_TEST');
}

class _Scenario {
  _Scenario({this.name = 'First restaurant'}) {
    profile = _Profile(this);
    content = _Content(this);
  }
  final String identity = 'member|org|restaurant|manager';
  final String name;
  late final _Profile profile;
  late final _Content content;
  final media = _Media();
  final catalog = _Catalog();
  final invoker = _Invoker();
  final sources = _Sources();
  int version = 3;
  StorefrontContentDocument document = StorefrontContentDocument.fromJson(
    StorefrontContentDocument.defaults(headline: 'Original headline'),
  );

  StorefrontEditorSeams get seams => StorefrontEditorSeams(
    scopeIdentity: identity,
    profileRepository: profile,
    mediaRepository: media,
    branchSource: _Branches(),
    sourceCatalog: sources,
    featuredCatalog: _Featured(),
    contentRepository: content,
    contentCatalog: catalog,
    publisher: StorefrontMediaPublisher(
      invoker: invoker,
      organizationId: _restaurant,
      restaurantId: _restaurant,
      retryDelay: Duration.zero,
    ),
  );

  StorefrontProfileRead parentRead() => StorefrontProfileRead.ok(
    exists: true,
    version: version,
    profile: StorefrontProfile.fromJson({
      'restaurant_id': _restaurant,
      'storefront_branch_id': _branch,
      'slug': 'synthetic-ownership',
      'display_name': name,
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
      'logo_media_id': null,
      'hero_media_id': null,
      'is_published': false,
      'version': version,
      'hero_headline': document.json['hero_headline'],
      'hero_subline': null,
      'announcement_text': null,
      'featured_item_ids': <String>[],
    }),
    derived: StorefrontDerived.fromJson({
      'timezone': 'Asia/Jerusalem',
      'currency_code': 'ILS',
      'tax': null,
      'publish_ready': true,
      'publish_blockers': <String>[],
      'media_prefix': 'synthetic',
    }),
  );

  StorefrontContentRead contentRead() => StorefrontContentRead(
    StorefrontContentReadStatus.ok,
    snapshot: StorefrontContentSnapshot(
      restaurantId: _restaurant,
      version: version,
      branchId: _branch,
      document: document,
      warnings: const [],
    ),
  );
}

class _Profile
    implements
        StorefrontProfileRepository,
        StorefrontHomeContentRepository,
        StorefrontFeaturedItemsRepository {
  _Profile(this.scenario);
  final _Scenario scenario;
  final reads = Queue<Future<StorefrontProfileRead>>();
  int readCount = 0, otherWrites = 0;
  @override
  Future<StorefrontProfileRead> read() {
    readCount++;
    return reads.isEmpty
        ? Future.value(scenario.parentRead())
        : reads.removeFirst();
  }

  @override
  Future<StorefrontWriteResult> save({
    required int expectedVersion,
    required Map<String, Object?> patch,
    String? requestId,
  }) async {
    otherWrites++;
    return StorefrontWriteResult(
      StorefrontWriteStatus.unavailable,
      requestId: requestId,
    );
  }

  @override
  Future<StorefrontWriteResult> saveHomeContent({
    required int expectedVersion,
    required Map<String, Object?> content,
    String? requestId,
  }) => save(
    expectedVersion: expectedVersion,
    patch: content,
    requestId: requestId,
  );
  @override
  Future<StorefrontWriteResult> saveFeaturedItems({
    required int expectedVersion,
    required List<String> itemIds,
    String? requestId,
  }) => save(
    expectedVersion: expectedVersion,
    patch: {'featured_item_ids': itemIds},
    requestId: requestId,
  );
}

class _Content implements StorefrontContentRepository {
  _Content(this.scenario);
  final _Scenario scenario;
  final reads = Queue<Future<StorefrontContentRead>>();
  final mediaReads = Queue<Future<StorefrontContentMediaList?>>();
  final writes = <StorefrontContentAttempt>[];
  int readCount = 0, mediaReadCount = 0, prepareCount = 0;
  StorefrontContentWriteStatus nextStatus = StorefrontContentWriteStatus.ok;
  Completer<void>? writeGate;
  @override
  Future<StorefrontContentRead> readContent() {
    readCount++;
    return reads.isEmpty
        ? Future.value(scenario.contentRead())
        : reads.removeFirst();
  }

  @override
  Future<StorefrontContentMediaList?> listContentMedia() {
    mediaReadCount++;
    return mediaReads.isEmpty
        ? Future.value(
            StorefrontContentMediaList(
              version: scenario.version,
              rows: const [],
            ),
          )
        : mediaReads.removeFirst();
  }

  @override
  StorefrontContentAttempt prepareContent({
    required int expectedVersion,
    required String expectedBranchId,
    required StorefrontContentDocument document,
  }) {
    prepareCount++;
    return StorefrontContentAttempt(
      requestId:
          '66666666-6666-4666-8666-${prepareCount.toString().padLeft(12, '0')}',
      expectedVersion: expectedVersion,
      expectedBranchId: expectedBranchId,
      document: document,
    );
  }

  @override
  Future<StorefrontContentWrite> saveContent(
    StorefrontContentAttempt attempt,
  ) async {
    writes.add(attempt);
    if (writeGate case final gate?) await gate.future;
    final status = nextStatus;
    if (status == StorefrontContentWriteStatus.ok) {
      scenario.document = attempt.document;
      scenario.version++;
    }
    return StorefrontContentWrite(
      status,
      attempt: attempt,
      version: scenario.version,
    );
  }
}

class _Media implements StorefrontMediaRepository {
  final reads = Queue<Future<StorefrontMediaList>>();
  int readCount = 0;
  @override
  Future<StorefrontMediaList> list() {
    readCount++;
    return reads.isEmpty
        ? Future.value(
            const StorefrontMediaList.ok(mediaPrefix: 'synthetic', media: []),
          )
        : reads.removeFirst();
  }

  @override
  Future<StorefrontMediaActionResult> cancel(String id, {String? requestId}) =>
      throw StateError('UNEXPECTED_CANCEL');
  @override
  Future<StorefrontMediaActionResult> retract(String id, {String? requestId}) =>
      throw StateError('UNEXPECTED_RETRACT');
}

class _Catalog implements StorefrontContentCatalog {
  final reads = Queue<Future<StorefrontContentCatalogData?>>();
  int readCount = 0;
  @override
  Future<StorefrontContentCatalogData?> loadContent(String branchId) {
    readCount++;
    return reads.isEmpty
        ? Future.value(
            const StorefrontContentCatalogData(categories: [], items: []),
          )
        : reads.removeFirst();
  }
}

class _Branches implements StorefrontBranchSource {
  @override
  Future<List<StorefrontBranchOption>?> list() async => const [
    StorefrontBranchOption(id: _branch, name: 'Synthetic branch'),
  ];
}

class _Featured implements StorefrontFeaturedCatalog {
  @override
  Future<List<StorefrontFeaturedOption>?> load(String branchId) async => const [
    StorefrontFeaturedOption(
      id: _item,
      name: 'Synthetic item',
      categoryName: 'Synthetic category',
    ),
  ];
}

class _Sources implements StorefrontSourceCatalog {
  @override
  Future<StorefrontSourceOptions> load() async => const StorefrontSourceOptions(
    receiptLogoKey: 'synthetic/private-logo.png',
  );
}

class _Invoker implements StorefrontFunctionInvoker {
  final calls = <Map<String, Object?>>[];
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    calls.add(Map.of(body));
    return StorefrontFunctionReply.fromHttp(200, {
      'ok': true,
      'status': 'published',
      'media': {
        'id': _mediaId,
        'object_key': 'synthetic/w960.webp',
        'content_hash': 'a' * 64,
        'width': 960,
        'height': 640,
        'bytes': 100,
        'variant': 'w960',
        'source_bucket': 'restaurant-logos',
        'source_key': 'synthetic/private-logo.png',
        'state': 'published',
      },
    });
  }
}

Widget _application(
  _Scenario scenario, {
  String locale = 'en',
  bool embedded = false,
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  home: Scaffold(
    body: embedded
        ? ListView(
            children: [
              StorefrontSettingsGroup(
                title: 'واجهة المتجر',
                initiallyExpanded: true,
                child: StorefrontSection(seams: scenario.seams, embedded: true),
              ),
            ],
          )
        : SingleChildScrollView(
            child: StorefrontSection(seams: scenario.seams),
          ),
  ),
);
Future<void> _mount(WidgetTester tester, _Scenario scenario) async {
  tester.view.physicalSize = const Size(1400, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_application(scenario));
  await tester.pumpAndSettle();
  await openStorefrontSettingsGroups(tester);
}

Future<void> _tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

Future<void> _edit(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('content-hero-headline')),
    'Confirmed content edit',
  );
  await _tick(tester);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('content-save')));
  await _tick(tester);
}

void _protected(WidgetTester tester) {
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('storefront-display-name')))
        .enabled,
    isFalse,
    reason: 'Parent profile editor stays locked by the content operation',
  );
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('storefront-home-headline')))
        .enabled,
    isFalse,
    reason: 'Legacy Home editor stays locked',
  );
  expect(
    tester
        .widget<CheckboxListTile>(
          find.byKey(const Key('storefront-featured-item-$_item')),
        )
        .onChanged,
    isNull,
    reason: 'Featured editor stays locked',
  );
  expect(
    tester
        .widget<FilledButton>(find.byKey(const Key('content-save')))
        .onPressed,
    isNull,
    reason: 'No second content write',
  );
}

Future<void> _publish(WidgetTester tester) async {
  final source = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        '${w.key}'.contains('content-source-'),
  );
  await tester.tap(source);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Editorial image').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Publish editorial derivative only'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
  await _tick(tester);
}

void main() {
  setUp(() {
    HttpOverrides.global = _NoNetwork();
  });
  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets(
    'embedded Settings exposes the confirmed save as a live status',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      try {
        final scenario = _Scenario();
        await tester.pumpWidget(
          _application(scenario, locale: 'ar', embedded: true),
        );
        await tester.pumpAndSettle();
        await setContentGroup(tester, 'editorial');
        await tester.ensureVisible(
          find.byKey(const Key('content-hero-headline')),
        );
        await _edit(tester);
        final reads = scenario.content.readCount;
        final mediaReads = scenario.content.mediaReadCount;
        await tester.ensureVisible(find.byKey(const Key('content-save')));
        await tester.pumpAndSettle();
        await _save(tester);
        await tester.pumpAndSettle();
        expect(scenario.content.writes, hasLength(1));
        expect(scenario.version, 4);
        expect(
          scenario.document.json['hero_headline'],
          'Confirmed content edit',
        );
        expect(scenario.content.readCount, greaterThan(reads));
        expect(scenario.content.mediaReadCount, greaterThan(mediaReads));

        final message = find.byKey(const Key('content-message'));
        await tester.ensureVisible(message);
        await tester.pumpAndSettle();
        final saved = find.bySemanticsLabel('حُفظ المحتوى وأُعيدت قراءته.');
        expect(saved, findsOneWidget);
        expect(tester.getSemantics(saved).flagsCollection.isLiveRegion, isTrue);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  for (final layout in [
    (size: const Size(1440, 1000), locale: 'en'),
    (size: const Size(390, 844), locale: 'ar'),
  ]) {
    testWidgets(
      'dirty notices preserve primary field geometry at ${layout.size.width} ${layout.locale}',
      (tester) async {
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        try {
          final scenario = _Scenario();
          await tester.pumpWidget(
            _application(scenario, locale: layout.locale),
          );
          await tester.pumpAndSettle();
          await openStorefrontSettingsGroups(tester);
          final l10n = await AppLocalizations.delegate.load(
            Locale(layout.locale),
          );
          final noticeTexts = [
            l10n.storefrontFeaturedItemsSeparateEdits,
            storefrontContentCopy(l10n, 'otherEdits'),
          ];
          final field = find.byKey(const Key('storefront-primary-color'));
          final editable = find.descendant(
            of: field,
            matching: find.byType(EditableText),
          );
          Future<void> tap(Finder target) async {
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          await tap(find.byKey(const Key('storefront-primary-color-advanced')));
          await tap(field);
          final originalState = tester.state<EditableTextState>(editable);
          final controller = originalState.widget.controller;
          final focus = originalState.widget.focusNode;
          final original = controller.text;
          final scroll = Scrollable.of(tester.element(field)).position;
          Rect documentRect() =>
              tester.getRect(field).translate(0, scroll.pixels);
          final initialDocumentRect = documentRect();
          expect(focus.hasFocus, isTrue);

          // The first dirty transition comes from the actual visual picker.
          // Advanced remains open under the modal, with the same input state.
          await tap(find.byKey(const Key('storefront-primary-color-picker')));
          final square = find.byKey(const Key('storefront-color-sv-field'));
          await tester.ensureVisible(square);
          final squareRect = tester.getRect(square);
          await tester.tapAt(
            Offset(
              squareRect.left + squareRect.width * .8,
              squareRect.top + squareRect.height * .2,
            ),
          );
          await tester.pumpAndSettle();
          await tap(find.byKey(const Key('storefront-color-apply')));
          expect(
            documentRect(),
            initialDocumentRect,
            reason: 'Both dirty notices reserve space before the first Apply',
          );
          expect(
            tester.state<EditableTextState>(editable),
            same(originalState),
          );
          expect(originalState.widget.controller, same(controller));
          expect(originalState.widget.focusNode, same(focus));
          expect(controller.text, isNot(original));
          final changed = controller.text;
          // One ordinary readback click, with no refocus loop or value injection.
          await tap(field);
          expect(focus.hasFocus, isTrue);
          final focusedRect = tester.getRect(field);
          for (final text in noticeTexts) {
            final notice = find.text(text);
            expect(notice, findsOneWidget);
            expect(
              tester
                  .element(notice)
                  .findAncestorWidgetOfExactType<Visibility>()!
                  .visible,
              isTrue,
            );
          }

          // Restore through the already-focused platform input connection.
          // enterText would refocus and could hide a rebuild-related focus loss.
          tester.testTextInput.enterText(original);
          await tester.pumpAndSettle();
          expect(tester.getRect(field), focusedRect);
          expect(documentRect(), initialDocumentRect);
          expect(
            tester.state<EditableTextState>(editable),
            same(originalState),
          );
          expect(focus.hasFocus, isTrue);
          expect(controller.text, original);

          Future<void> checkNotices({required bool visible}) async {
            for (final text in noticeTexts) {
              final notice = find.text(text);
              expect(
                notice,
                findsOneWidget,
                reason:
                    'Notice size is retained even when its content is hidden',
              );
              final visibility = tester
                  .element(notice)
                  .findAncestorWidgetOfExactType<Visibility>()!;
              expect(visibility.visible, visible);
              // Retaining layout must not expose invisible notices to assistive
              // technology, hit testing or focus traversal.
              expect(visibility.maintainSemantics, isFalse);
              expect(visibility.maintainInteractivity, isFalse);
              expect(visibility.maintainFocusability, isFalse);
              await tester.ensureVisible(notice);
              await tester.pumpAndSettle();
              expect(
                notice.hitTestable(),
                visible ? findsOneWidget : findsNothing,
              );
              expect(
                find.semantics.byLabel(RegExp(RegExp.escape(text))),
                visible ? findsWidgets : findsNothing,
              );
            }
          }

          await checkNotices(visible: false);
          expect(focus.hasFocus, isTrue);
          tester.testTextInput.enterText(changed);
          await tester.pumpAndSettle();
          expect(documentRect(), initialDocumentRect);
          await checkNotices(visible: true);
          await tap(find.byKey(const Key('storefront-discard')));
          expect(
            documentRect(),
            initialDocumentRect,
            reason:
                'Discard hides both notices without moving the appearance grid',
          );
          expect(
            tester.state<EditableTextState>(editable),
            same(originalState),
          );
          expect(originalState.widget.controller, same(controller));
          expect(originalState.widget.focusNode, same(focus));
          expect(controller.text, original);
          await checkNotices(visible: false);
          await tap(field);
          expect(focus.hasFocus, isTrue);
          expect(scenario.profile.otherWrites, 0);
          expect(scenario.content.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final replay in [false, true]) {
    testWidgets(
      'parent composition owns save and every delayed refresh, replay=$replay',
      (tester) async {
        final s = _Scenario();
        await _mount(tester, s);
        await _edit(tester);
        if (replay) {
          s.content.nextStatus = StorefrontContentWriteStatus.uncertain;
          await _save(tester);
          s.content.nextStatus = StorefrontContentWriteStatus.ok;
        }
        final parent = Completer<StorefrontProfileRead>(),
            media = Completer<StorefrontMediaList>();
        final content = Completer<StorefrontContentRead>(),
            choices = Completer<StorefrontContentMediaList?>(),
            catalog = Completer<StorefrontContentCatalogData?>();
        s.profile.reads.add(parent.future);
        s.media.reads.add(media.future);
        s.content.reads.add(content.future);
        s.content.mediaReads.add(choices.future);
        s.catalog.reads.add(catalog.future);
        if (replay) {
          await tester.tap(find.byKey(const Key('content-retry-save')));
          await _tick(tester);
        } else {
          await _save(tester);
        }
        _protected(tester);
        parent.complete(s.parentRead());
        await _tick(tester);
        _protected(tester);
        media.complete(
          const StorefrontMediaList.ok(mediaPrefix: 'synthetic', media: []),
        );
        await _tick(tester);
        _protected(tester);
        content.complete(s.contentRead());
        await _tick(tester);
        _protected(tester);
        choices.complete(
          StorefrontContentMediaList(version: s.version, rows: const []),
        );
        await _tick(tester);
        _protected(tester);
        catalog.complete(
          const StorefrontContentCatalogData(categories: [], items: []),
        );
        await tester.pumpAndSettle();
        expect(s.content.prepareCount, 1);
        expect(s.content.writes.length, replay ? 2 : 1);
        if (replay)
          expect(identical(s.content.writes[0], s.content.writes[1]), isTrue);
        expect(
          s.content.readCount,
          2,
          reason:
              'Exactly one post-write child read, not didUpdate plus explicit load',
        );
        expect(s.content.mediaReadCount, 2);
        expect(s.catalog.readCount, 2);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const Key('storefront-display-name')),
              )
              .enabled,
          isTrue,
        );
        expect(s.profile.otherWrites, 0);
        expect(s.invoker.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final failed in [
    'parent',
    'parent-media',
    'content',
    'content-media',
    'catalog',
  ]) {
    testWidgets(
      'confirmed save + $failed read failure permits only read-only resume',
      (tester) async {
        final s = _Scenario();
        await _mount(tester, s);
        await _edit(tester);
        switch (failed) {
          case 'parent':
            s.profile.reads.add(
              Future.value(const StorefrontProfileRead.unavailable()),
            );
          case 'parent-media':
            s.media.reads.add(
              Future.value(const StorefrontMediaList.unavailable()),
            );
          case 'content':
            s.content.reads.add(
              Future.value(
                const StorefrontContentRead(
                  StorefrontContentReadStatus.unavailable,
                ),
              ),
            );
          case 'content-media':
            s.content.mediaReads.add(Future.value(null));
          case 'catalog':
            s.catalog.reads.add(Future.value(null));
        }
        await _save(tester);
        await tester.pumpAndSettle();
        _protected(tester);
        expect(find.byKey(const Key('content-retry-save')), findsNothing);
        final resume = find.byKey(const Key('content-resume-read'));
        expect(resume, findsOneWidget);
        expect(tester.widget<TextButton>(resume).onPressed, isNotNull);
        final original = s.content.writes.single;
        await tester.tap(resume);
        await tester.pumpAndSettle();
        expect(s.content.prepareCount, 1);
        expect(s.content.writes.length, 1);
        expect(identical(s.content.writes.single, original), isTrue);
        expect(s.invoker.calls, isEmpty);
        expect(s.profile.otherWrites, 0);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const Key('storefront-display-name')),
              )
              .enabled,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'editorial publish owns parent and child refresh without content or Hero save',
    (tester) async {
      final s = _Scenario();
      await _mount(tester, s);
      final parent = Completer<StorefrontProfileRead>(),
          media = Completer<StorefrontMediaList>(),
          content = Completer<StorefrontContentRead>();
      s.profile.reads.add(parent.future);
      s.media.reads.add(media.future);
      s.content.reads.add(content.future);
      await _publish(tester);
      expect(s.invoker.calls.length, 1);
      _protected(tester);
      parent.complete(s.parentRead());
      await _tick(tester);
      _protected(tester);
      media.complete(
        const StorefrontMediaList.ok(mediaPrefix: 'synthetic', media: []),
      );
      await _tick(tester);
      _protected(tester);
      content.complete(s.contentRead());
      await tester.pumpAndSettle();
      // Publish-only editorial reuses the unchanged hero recipe wire; a
      // profile/Hero assignment would be a separate (forbidden here) write.
      expect(s.invoker.calls.single['slot'], 'hero');
      expect(s.invoker.calls.single['variant'], 'w960');
      expect(s.content.writes, isEmpty);
      expect(s.content.prepareCount, 0);
      expect(s.profile.otherWrites, 0);
      expect(s.content.readCount, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed publish + failed parent read resumes without another publish',
    (tester) async {
      final s = _Scenario();
      await _mount(tester, s);
      s.profile.reads.add(
        Future.value(const StorefrontProfileRead.unavailable()),
      );
      await _publish(tester);
      await tester.pumpAndSettle();
      _protected(tester);
      final original = Map<String, Object?>.of(s.invoker.calls.single);
      await tester.tap(find.byKey(const Key('content-resume-read')));
      await tester.pumpAndSettle();
      expect(s.invoker.calls, [original]);
      expect(s.content.writes, isEmpty);
      expect(s.profile.otherWrites, 0);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-display-name')))
            .enabled,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late confirmed save after disposal cannot refresh or touch disposed controllers',
    (tester) async {
      final s = _Scenario();
      await _mount(tester, s);
      await _edit(tester);
      final gate = Completer<void>();
      s.content.writeGate = gate;
      await _save(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.pumpAndSettle();
      expect(s.content.writes.length, 1);
      expect(s.profile.readCount, 1);
      expect(s.content.readCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same-scope repository replacement rejects late old parent completion',
    (tester) async {
      final first = _Scenario();
      await _mount(tester, first);
      await _edit(tester);
      final old = Completer<StorefrontProfileRead>();
      first.profile.reads.add(old.future);
      await _save(tester);
      final second = _Scenario(name: 'Second restaurant');
      await tester.pumpWidget(_application(second));
      await _tick(tester);
      old.complete(first.parentRead());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('storefront-display-name')))
            .controller!
            .text,
        'Second restaurant',
      );
      expect(second.profile.readCount, 1);
      expect(second.content.writes, isEmpty);
      expect(first.content.readCount, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
