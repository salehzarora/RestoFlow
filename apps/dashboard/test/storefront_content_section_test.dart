import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_section.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_sources.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const restaurant = '22222222-2222-4222-8222-222222222222';
const branch = '33333333-3333-4333-8333-333333333333';
const item = '44444444-4444-4444-8444-444444444444';
const category = '55555555-5555-4555-8555-555555555555';
const request = '66666666-6666-4666-8666-666666666666';

class ContentRepo implements StorefrontContentRepository {
  var version = 3;
  var doc = StorefrontContentDocument.fromJson(
    StorefrontContentDocument.defaults(headline: 'طَعْم رائع'),
  );
  final calls = <StorefrontContentAttempt>[];
  var status = StorefrontContentWriteStatus.ok;
  var readStatus = StorefrontContentReadStatus.ok;
  final warnings = <StorefrontContentWarning>[];
  @override
  Future<StorefrontContentRead> readContent() async => StorefrontContentRead(
    readStatus,
    snapshot: readStatus == StorefrontContentReadStatus.ok
        ? StorefrontContentSnapshot(
            restaurantId: restaurant,
            version: version,
            branchId: branch,
            document: doc,
            warnings: warnings,
          )
        : null,
  );
  @override
  Future<StorefrontContentMediaList?> listContentMedia() async =>
      StorefrontContentMediaList(version: version, rows: []);
  @override
  StorefrontContentAttempt prepareContent({
    required int expectedVersion,
    required String expectedBranchId,
    required StorefrontContentDocument document,
  }) => StorefrontContentAttempt(
    requestId: request,
    expectedVersion: expectedVersion,
    expectedBranchId: expectedBranchId,
    document: document,
  );
  @override
  Future<StorefrontContentWrite> saveContent(
    StorefrontContentAttempt attempt,
  ) async {
    calls.add(attempt);
    if (status == StorefrontContentWriteStatus.ok) {
      doc = attempt.document;
      version++;
    }
    return StorefrontContentWrite(status, attempt: attempt, version: version);
  }
}

class ContentCatalog implements StorefrontContentCatalog {
  final branches = <String>[];
  @override
  Future<StorefrontContentCatalogData?> loadContent(String id) async {
    branches.add(id);
    return const StorefrontContentCatalogData(
      categories: [
        StorefrontContentChoice(id: category, name: 'Stored category'),
      ],
      items: [
        StorefrontContentChoice(
          id: item,
          name: 'Stored item',
          categoryId: category,
          hasImage: true,
        ),
      ],
    );
  }
}

class PublisherInvoker implements StorefrontFunctionInvoker {
  final calls = <Map<String, Object?>>[];
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    calls.add(body);
    return StorefrontFunctionReply.fromHttp(200, {
      'ok': true,
      'status': 'published',
      'media': {
        'id': request,
        'object_key': 'synthetic/w960.webp',
        'content_hash': 'a' * 64,
        'width': 960,
        'height': 640,
        'bytes': 100,
        'variant': 'w960',
        'source_bucket': 'restaurant-logos',
        'source_key': 'synthetic/logo.png',
        'state': 'published',
      },
    });
  }
}

Future<void> mount(
  WidgetTester tester,
  ContentRepo repo, {
  String locale = 'en',
  bool enabled = true,
  PublisherInvoker? invoker,
  ContentCatalog? catalog,
  double width = 1024,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  late StateSetter update;
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Padding(
                padding: const EdgeInsets.all(16),
                child: StorefrontContentSection(
                  repository: repo,
                  catalog: catalog ?? ContentCatalog(),
                  profileVersion: repo.version,
                  savedBranchId: branch,
                  enabled: enabled,
                  onRefresh: () async {
                    update(() {});
                  },
                  onDraftChanged: (_) {},
                  onBusyChanged: (_) {},
                  publisher: invoker == null
                      ? null
                      : StorefrontMediaPublisher(
                          invoker: invoker,
                          organizationId: restaurant,
                          restaurantId: restaurant,
                          retryDelay: Duration.zero,
                        ),
                  sources: const StorefrontSourceOptions(
                    receiptLogoKey: 'synthetic/logo.png',
                  ),
                  reloadSources: () async => const StorefrontSourceOptions(
                    receiptLogoKey: 'synthetic/logo.png',
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> edit(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a retained save callback cannot act after scope disposal', (
    tester,
  ) async {
    final repo = ContentRepo();
    await mount(tester, repo);
    await edit(tester, 'content-hero-headline', 'Unsaved old restaurant');
    final save = tester
        .widget<FilledButton>(find.byKey(const Key('content-save')))
        .onPressed!;
    await tester.pumpWidget(const SizedBox.shrink());
    save();
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('duplicate save callback starts exactly one logical request', (
    tester,
  ) async {
    final repo = ContentRepo();
    await mount(tester, repo);
    await edit(tester, 'content-hero-headline', 'One request');
    final save = tester
        .widget<FilledButton>(find.byKey(const Key('content-save')))
        .onPressed!;
    save();
    save();
    await tester.pumpAndSettle();
    expect(repo.calls.length, 1);
    expect(tester.takeException(), isNull);
  });
  for (final locale in ['ar', 'he', 'en']) {
    testWidgets('$locale narrow large-text editor has no layout exception', (
      tester,
    ) async {
      final repo = ContentRepo();
      await mount(tester, repo, locale: locale, width: 390, textScale: 1.6);
      expect(find.byKey(const Key('content-save')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(repo.calls, isEmpty);
    });
    testWidgets(
      '$locale complete real editor renders without overflow or invented content',
      (tester) async {
        final repo = ContentRepo();
        await mount(tester, repo, locale: locale);
        expect(
          find.byKey(const Key('storefront-content-editor')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('content-hero-headline')), findsOneWidget);
        expect(repo.calls, isEmpty);
        expect(tester.takeException(), isNull);
        expect(find.text('طَعْم رائع'), findsNWidgets(2));
      },
    );
  }
  testWidgets(
    'actual selection converts whole Arabic token and edits clear unsaved format',
    (tester) async {
      final repo = ContentRepo();
      await mount(tester, repo);
      final preview = tester.widget<TextField>(
        find.byKey(const Key('content-headline-selection')),
      );
      preview.controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      final action = tester
          .widget<TextButton>(find.byKey(const Key('content-highlight')))
          .onPressed!;
      action();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('content-format-offsets')), findsOneWidget);
      await edit(tester, 'content-hero-headline', 'عنوان جديد');
      expect(find.byKey(const Key('content-format-offsets')), findsNothing);
      expect(repo.calls, isEmpty);
    },
  );
  testWidgets('trim-changing headline preview requires explicit confirmation', (
    tester,
  ) async {
    final repo = ContentRepo();
    await mount(tester, repo);
    await edit(tester, 'content-hero-headline', '  Exact preview  ');
    final normalize = find.widgetWithText(
      TextButton,
      'Confirm exact headline preview',
    );
    tester.widget<TextButton>(normalize).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Exact preview'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('content-hero-headline')))
          .controller!
          .text,
      '  Exact preview  ',
    );
    tester.widget<TextButton>(normalize).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('content-headline-selection')),
          )
          .controller!
          .text,
      'Exact preview',
    );
    expect(repo.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('non-BMP split is rejected and no save is sent', (tester) async {
    final repo = ContentRepo()
      ..doc = StorefrontContentDocument.fromJson(
        StorefrontContentDocument.defaults(headline: '🍔 טָעִים'),
      );
    await mount(tester, repo);
    tester
        .widget<TextField>(find.byKey(const Key('content-headline-selection')))
        .controller!
        .selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 9,
    );
    tester
        .widget<TextButton>(find.byKey(const Key('content-highlight')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(
      find.text('Content is incomplete or invalid. Correct it before saving.'),
      findsOneWidget,
    );
    expect(repo.calls, isEmpty);
  });
  testWidgets(
    'save uses current global version and rereads confirmed content',
    (tester) async {
      final repo = ContentRepo();
      final catalog = ContentCatalog();
      await mount(tester, repo, catalog: catalog);
      await edit(tester, 'content-hero-headline', 'New headline');
      tester
          .widget<FilledButton>(find.byKey(const Key('content-save')))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(repo.calls.length, 1);
      expect(repo.calls.single.expectedVersion, 3);
      expect(repo.calls.single.expectedBranchId, branch);
      expect(repo.calls.single.document.json['hero_headline'], 'New headline');
      expect(find.text('Content saved and reread.'), findsOneWidget);
      expect(catalog.branches.every((id) => id == branch), true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown outcome freezes exact draft and explicit retry reuses original attempt',
    (tester) async {
      final repo = ContentRepo()
        ..status = StorefrontContentWriteStatus.uncertain;
      await mount(tester, repo);
      await edit(tester, 'content-hero-headline', 'Same identity');
      tester
          .widget<FilledButton>(find.byKey(const Key('content-save')))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(repo.calls.length, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('content-hero-headline')))
            .enabled,
        false,
      );
      repo.status = StorefrontContentWriteStatus.ok;
      tester
          .widget<OutlinedButton>(find.byKey(const Key('content-retry-save')))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(repo.calls.length, 2);
      expect(identical(repo.calls.first, repo.calls.last), true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('incomplete enabled promo stays local and cannot submit', (
    tester,
  ) async {
    final repo = ContentRepo();
    await mount(tester, repo);
    tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .first
        .onChanged!(true);
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.byKey(const Key('content-save')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    expect(
      find.text('Content is incomplete or invalid. Correct it before saving.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'disabled or denied composition cannot send through captured callbacks',
    (tester) async {
      final repo = ContentRepo();
      await mount(tester, repo, enabled: false);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('content-save')))
            .onPressed,
        isNull,
      );
      expect(repo.calls, isEmpty);
      repo.readStatus = StorefrontContentReadStatus.denied;
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, repo);
      expect(find.byKey(const Key('content-save')), findsNothing);
      expect(repo.calls, isEmpty);
    },
  );
  testWidgets(
    'editorial publishing uses w960 existing recipe and never assigns Hero or saves content',
    (tester) async {
      final repo = ContentRepo();
      final invoker = PublisherInvoker();
      await mount(tester, repo, invoker: invoker);
      final source = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('content-source-1')),
      );
      source.onChanged!('logo');
      await tester.pumpAndSettle();
      final button = find.widgetWithText(
        TextButton,
        'Publish editorial derivative only',
      );
      tester.widget<TextButton>(button).onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(invoker.calls.length, 1);
      expect(invoker.calls.single['slot'], 'hero');
      expect(invoker.calls.single['variant'], 'w960');
      expect(repo.calls, isEmpty);
      expect((repo.doc.json['hero'] as Map)['mode'], 'editorial');
      expect(tester.takeException(), isNull);
    },
  );
}
