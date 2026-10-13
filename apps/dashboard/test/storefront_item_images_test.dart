import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_item_images.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_sources.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _org = '11111111-1111-4111-8111-111111111111';
const _rest = '22222222-2222-4222-8222-222222222222';
const _all = Key('storefront-item-images-publish-all');

StorefrontMenuImageOption _item(int n, {String suffix = 'original'}) =>
    StorefrontMenuImageOption(
      itemId: 'item-$n',
      itemName: 'Product $n',
      imageKey: '$_org/$_rest/global/menu_item/item-$n/$suffix.jpg',
    );

StorefrontFunctionReply _success(Map<String, Object?> body) =>
    StorefrontFunctionReply(
      httpStatus: 200,
      json: {
        'ok': true,
        'status': 'published',
        'media': {
          'id': '44444444-4444-4444-8444-444444444444',
          'object_key': '${'a' * 32}/${'b' * 64}.webp',
          'content_hash': 'b' * 64,
          'width': 480,
          'height': 320,
          'bytes': 40000,
          'variant': 'w480',
          'source_bucket': 'menu-images',
          'source_key': body['source_key'],
          'state': 'published',
        },
      },
    );

class _Invoker implements StorefrontFunctionInvoker {
  final bodies = <Map<String, Object?>>[];
  Future<StorefrontFunctionReply> Function(Map<String, Object?>)? reply;

  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    bodies.add(Map.of(body));
    return reply == null ? _success(body) : await reply!(body);
  }
}

class _Harness {
  final invoker = _Invoker();
  StorefrontSourceOptions sources = StorefrontSourceOptions(
    menuImages: [_item(1), _item(2)],
  );
  StorefrontSourceOptions? latest;
  int refreshes = 0;
  int loads = 0;
  int nonce = 1;
  final busy = <bool>[];
  bool enabled = true;

  Future<void> mount(WidgetTester tester, {String locale = 'en'}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StorefrontItemImages(
              publisher: StorefrontMediaPublisher(
                invoker: invoker,
                organizationId: _org,
                restaurantId: _rest,
                retryDelay: Duration.zero,
              ),
              sources: sources,
              reloadSources: () async {
                loads++;
                return latest ?? sources;
              },
              onRefresh: () async {
                refreshes++;
                return true;
              },
              onBusyChanged: busy.add,
              nonce: () => nonce++,
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('storefront-item-images')));
    await tester.pumpAndSettle();
  }

  Future<void> publish(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_all));
    await tester.tap(find.byKey(_all));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'publishes 20 originals without bytes, profile writes or uploads',
    (tester) async {
      final h = _Harness()
        ..sources = StorefrontSourceOptions(
          menuImages: List.generate(20, _item),
        );
      await h.mount(tester);
      await h.publish(tester);
      expect(h.invoker.bodies.length, 20);
      expect(h.invoker.bodies.map((b) => b['request_id']).toSet().length, 20);
      for (final b in h.invoker.bodies) {
        expect(b.keys.toList(), StorefrontMediaPublisher.requestKeys);
        expect(b['slot'], 'item');
        expect(b['variant'], 'w480');
      }
      expect(h.loads, 1);
      expect(h.refreshes, 1);
      expect(h.busy, [true, false]);
      expect(find.textContaining(_org), findsNothing);
    },
  );

  testWidgets('reloads current originals, excludes removed images', (
    tester,
  ) async {
    final h = _Harness()
      ..latest = StorefrontSourceOptions(
        menuImages: [_item(1, suffix: 'replacement')],
      );
    await h.mount(tester);
    await h.publish(tester);
    expect(
      h.invoker.bodies.single['source_key'],
      _item(1, suffix: 'replacement').imageKey,
    );
  });

  testWidgets('failed source read publishes nothing', (tester) async {
    final h = _Harness()
      ..latest = const StorefrontSourceOptions(menuImagesUnavailable: true);
    await h.mount(tester);
    await h.publish(tester);
    expect(h.invoker.bodies, isEmpty);
    expect(
      find.text('The current product images could not be verified. Try again.'),
      findsOneWidget,
    );
    expect(h.busy, [true, false]);
  });

  testWidgets('batch is sequential and disposal stops remaining images', (
    tester,
  ) async {
    final h = _Harness();
    final pending = Completer<StorefrontFunctionReply>();
    h.invoker.reply = (_) => pending.future;
    await h.mount(tester);
    await tester.tap(find.byKey(_all));
    await tester.pump();
    expect(h.invoker.bodies.length, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(_success(h.invoker.bodies.single));
    await tester.pumpAndSettle();
    expect(h.invoker.bodies.length, 1);
    expect(h.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncertain manual retry keeps identity, then reconciles', (
    tester,
  ) async {
    final h = _Harness()
      ..sources = StorefrontSourceOptions(menuImages: [_item(1)]);
    h.invoker.reply = (_) async =>
        const StorefrontFunctionReply.transportFailure();
    await h.mount(tester);
    await h.publish(tester);
    expect(h.invoker.bodies.length, 2);
    final request = h.invoker.bodies.first['request_id'];
    h.invoker.reply = null;
    await h.publish(tester);
    expect(h.invoker.bodies.last['request_id'], request);
    expect(h.refreshes, 2);
    expect(find.text('Public copy published'), findsOneWidget);
  });

  testWidgets(
    'missing source continues other images; permission failure stops batch',
    (tester) async {
      final h = _Harness();
      h.invoker.reply = (b) async => h.invoker.bodies.length == 1
          ? const StorefrontFunctionReply(
              httpStatus: 404,
              json: {'status': 'source_not_found'},
            )
          : _success(b);
      await h.mount(tester);
      await h.publish(tester);
      expect(h.invoker.bodies.length, 2);
      h.invoker.bodies.clear();
      h.invoker.reply = (_) async => const StorefrontFunctionReply(
        httpStatus: 403,
        json: {'status': 'permission_denied'},
      );
      await h.publish(tester);
      expect(h.invoker.bodies.length, 1);
    },
  );

  testWidgets('disabled editor cannot publish', (tester) async {
    final h = _Harness()..enabled = false;
    await h.mount(tester);
    expect(tester.widget<FilledButton>(find.byKey(_all)).onPressed, isNull);
    expect(h.invoker.bodies, isEmpty);
  });

  for (final locale in ['ar', 'he', 'en']) {
    testWidgets('390px $locale workflow keeps localized actions accessible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      await h.mount(tester, locale: locale);
      await h.publish(tester);
      expect(h.invoker.bodies.length, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
