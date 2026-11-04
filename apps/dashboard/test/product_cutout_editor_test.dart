import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_dashboard/src/storefront/product_cutout_editor.dart';
import 'package:restoflow_dashboard/src/storefront/product_cutout_gateway.dart';
import 'package:restoflow_dashboard/src/storefront/product_cutout_processor.dart';

final pixels = Uint8List.fromList([1, 2, 3]);
MenuItem item(String? path) => MenuItem(
  id: 'item',
  organizationId: 'org',
  restaurantId: 'restaurant',
  branchId: null,
  menuCategoryId: 'category',
  name: 'Burger',
  description: null,
  basePriceMinor: 100,
  currencyCode: 'ILS',
  defaultStationId: null,
  displayOrder: 0,
  isActive: true,
  imagePath: path,
);

class Gateway implements ProductCutoutGateway {
  int loads = 0;
  Uint8List sourceBytes = pixels;
  Map<String, Object?> snapshot = {'object_id': 'source-A', 'version': 1};
  int selectionVersion = 0;
  Completer<ProductCutoutPublishResult>? pendingPublish;
  final requests =
      <({String id, Uint8List? candidate, ProductCutoutOriginal original})>[];
  ProductCutoutPublishStatus status = ProductCutoutPublishStatus.published;
  @override
  Future<ProductCutoutOriginal> loadOriginal(MenuItem item) async {
    loads++;
    return ProductCutoutOriginal(
      bytes: sourceBytes,
      mimeType: 'image/png',
      sourceKey: item.imagePath!,
      sourceGeneration: jsonEncode({
        'source_snapshot': snapshot,
        'selection_version': selectionVersion,
      }),
    );
  }

  @override
  Future<ProductCutoutPublishResult> publish({
    required MenuItem item,
    required ProductCutoutOriginal original,
    required String requestId,
    Uint8List? candidateBytes,
    String? candidateMimeType,
  }) async {
    requests.add((
      id: requestId,
      candidate: candidateBytes,
      original: original,
    ));
    return pendingPublish?.future ?? ProductCutoutPublishResult(status);
  }
}

class Processor implements ProductCutoutProcessor {
  bool fail = false, transparent = false;
  Uint8List resultBytes = pixels;
  Completer<ProductCutoutCandidate>? pending;
  int cancels = 0, runs = 0;
  @override
  Future<ProductCutoutCandidate> process(
    Uint8List bytes,
    String mimeType, {
    void Function(String)? onProgress,
  }) async {
    runs++;
    if (fail) throw StateError('bad');
    if (pending != null) return pending!.future;
    return ProductCutoutCandidate(
      bytes: resultBytes,
      mimeType: 'image/png',
      width: 1,
      height: 1,
      alreadyTransparent: transparent,
    );
  }

  @override
  void cancel() {
    cancels++;
  }
}

Future<void> mount(
  WidgetTester tester,
  Gateway gateway,
  Processor processor, {
  String? path = 'original',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProductCutoutEditor(
            key: const ValueKey('editor'),
            item: item(path),
            gateway: gateway,
            processor: processor,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  for (final change in ['snapshot and bytes', 'snapshot only', 'bytes only']) {
    testWidgets('same-key overwrite ($change) invalidates the old candidate', (
      tester,
    ) async {
      final gateway = Gateway(), processor = Processor();
      await mount(tester, gateway, processor);
      await tap(tester, 'product-cutout-prepare');
      await tester.tap(find.text('Remove background').last);
      await tester.pumpAndSettle();
      if (change != 'bytes only')
        gateway.snapshot = {'object_id': 'source-B', 'version': 2};
      if (change != 'snapshot only')
        gateway.sourceBytes = Uint8List.fromList([4, 5, 6]);
      gateway.selectionVersion = 1;
      await tap(tester, 'product-cutout-publish');
      expect(gateway.requests.single.candidate, pixels);
      expect(
        find.text('The original changed. Prepare a new preview.'),
        findsOneWidget,
      );
      final selection = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      expect(selection.selected, {false});
      expect(selection.segments.last.enabled, isFalse);
      await tap(tester, 'product-cutout-publish');
      expect(gateway.requests.last.candidate, isNull);
      expect(gateway.requests.last.original.bytes, gateway.sourceBytes);
      await tap(tester, 'product-cutout-prepare');
      expect(processor.runs, 2);
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {false},
      );
    });
  }
  testWidgets(
    'selection-only refresh retains candidate with the fresh selection proof',
    (tester) async {
      final gateway = Gateway(), processor = Processor();
      await mount(tester, gateway, processor);
      await tap(tester, 'product-cutout-prepare');
      await tester.tap(find.text('Remove background').last);
      await tester.pumpAndSettle();
      gateway.selectionVersion = 1;
      // Map order is not source identity either.
      gateway.snapshot = {'version': 1, 'object_id': 'source-A'};
      await tap(tester, 'product-cutout-publish');
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true},
      );
      await tap(tester, 'product-cutout-publish');
      expect(gateway.requests.last.candidate, pixels);
      expect(
        jsonDecode(
          gateway.requests.last.original.sourceGeneration,
        )['selection_version'],
        1,
      );
      expect(processor.runs, 1);
    },
  );
  testWidgets('delayed publication cannot replace the state of a new source', (
    tester,
  ) async {
    final gateway = Gateway(), processor = Processor();
    await mount(tester, gateway, processor);
    await tap(tester, 'product-cutout-prepare');
    final pending = Completer<ProductCutoutPublishResult>();
    gateway.pendingPublish = pending;
    await tester.ensureVisible(find.byKey(const Key('product-cutout-publish')));
    await tester.tap(find.byKey(const Key('product-cutout-publish')));
    await tester.pump(); // The publication is intentionally still in flight.
    gateway.sourceBytes = Uint8List.fromList([4, 5, 6]);
    gateway.snapshot = {'object_id': 'source-B', 'version': 2};
    processor.resultBytes = Uint8List.fromList([7, 8, 9]);
    await mount(tester, gateway, processor, path: 'new-original');
    expect(processor.runs, 2);
    final loadsBeforeOldCompletion = gateway.loads;
    gateway.pendingPublish = null;
    pending.complete(
      const ProductCutoutPublishResult(ProductCutoutPublishStatus.published),
    );
    await tester.pumpAndSettle();
    expect(gateway.loads, loadsBeforeOldCompletion);
    expect(find.text('Selection published.'), findsNothing);
    await tester.tap(find.text('Remove background').last);
    await tester.pumpAndSettle();
    await tap(tester, 'product-cutout-publish');
    expect(gateway.requests.last.original.sourceKey, 'new-original');
    expect(gateway.requests.last.original.bytes, gateway.sourceBytes);
    expect(gateway.requests.last.candidate, processor.resultBytes);
  });
  testWidgets(
    'existing products prepare locally and require explicit publication choice',
    (tester) async {
      final gateway = Gateway(), processor = Processor();
      await mount(tester, gateway, processor);
      expect(gateway.loads, 0);
      await tap(tester, 'product-cutout-prepare');
      expect(processor.runs, 1);
      expect(gateway.requests, isEmpty);
      await tester.tap(find.text('Remove background').last);
      await tester.pumpAndSettle();
      await tap(tester, 'product-cutout-publish');
      expect(gateway.requests.single.candidate, isNotNull);
      expect(find.text('Selection published.'), findsOneWidget);
    },
  );
  testWidgets('failed processing keeps Original available and retries', (
    tester,
  ) async {
    final gateway = Gateway(), processor = Processor()..fail = true;
    await mount(tester, gateway, processor);
    await tap(tester, 'product-cutout-prepare');
    expect(find.textContaining('Your original is safe'), findsOneWidget);
    expect(gateway.requests, isEmpty);
    await tap(tester, 'product-cutout-publish');
    expect(gateway.requests.single.candidate, isNull);
    processor.fail = false;
    await tap(tester, 'product-cutout-prepare');
    expect(processor.runs, 2);
  });
  testWidgets('existing alpha publishes Original without a candidate upload', (
    tester,
  ) async {
    final gateway = Gateway(), processor = Processor()..transparent = true;
    await mount(tester, gateway, processor);
    await tap(tester, 'product-cutout-prepare');
    expect(find.textContaining('no segmentation was run'), findsOneWidget);
    final selection = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(selection.selected, {false});
    expect(selection.segments.last.enabled, isFalse);
    await tap(tester, 'product-cutout-publish');
    expect(gateway.requests.single.candidate, isNull);
  });
  testWidgets('uncertain publication retries identical request and selection', (
    tester,
  ) async {
    final gateway = Gateway()..status = ProductCutoutPublishStatus.uncertain,
        processor = Processor();
    await mount(tester, gateway, processor);
    await tap(tester, 'product-cutout-prepare');
    await tap(tester, 'product-cutout-publish');
    await tap(tester, 'product-cutout-publish');
    expect(gateway.requests[0].id, gateway.requests[1].id);
    expect(
      gateway.requests.every((request) => request.candidate == null),
      isTrue,
    );
  });
  testWidgets(
    'successful original upload change automatically prepares but never publishes',
    (tester) async {
      final gateway = Gateway(), processor = Processor();
      await mount(tester, gateway, processor, path: null);
      await mount(tester, gateway, processor, path: 'new-original');
      expect(gateway.loads, 1);
      expect(processor.runs, 1);
      expect(gateway.requests, isEmpty);
    },
  );
  testWidgets('cancel discards late candidate and retains original bytes', (
    tester,
  ) async {
    final gateway = Gateway(),
        processor = Processor()..pending = Completer<ProductCutoutCandidate>();
    await mount(tester, gateway, processor);
    await tester.tap(find.byKey(const Key('product-cutout-prepare')));
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('product-cutout-cancel')));
    await tester.tap(find.byKey(const Key('product-cutout-cancel')));
    await tester.pumpAndSettle();
    expect(processor.cancels, 1);
    expect(gateway.requests, isEmpty);
    processor.pending!.complete(
      ProductCutoutCandidate(
        bytes: pixels,
        mimeType: 'image/png',
        width: 1,
        height: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Remove background'), findsOneWidget);
    await tap(tester, 'product-cutout-publish');
    expect(gateway.requests.single.candidate, isNull);
  });
  testWidgets(
    'retry readiness requires a candidate, not the prior Original publish button',
    (tester) async {
      final gateway = Gateway(), processor = Processor()..fail = true;
      await mount(tester, gateway, processor);
      await tap(tester, 'product-cutout-prepare');
      final publish = find.byKey(const Key('product-cutout-publish'));
      bool canPublish() =>
          tester.widget<FilledButton>(publish).onPressed != null;
      bool canRemove() => tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .segments
          .singleWhere((segment) => segment.value)
          .enabled;
      // A failed fetch deliberately leaves Original publishable, without a mask.
      expect(canPublish(), isTrue);
      expect(canRemove(), isFalse);
      processor.fail = false;
      processor.pending = Completer<ProductCutoutCandidate>();
      await tester.ensureVisible(
        find.byKey(const Key('product-cutout-prepare')),
      );
      await tester.tap(find.byKey(const Key('product-cutout-prepare')));
      // Pointer dispatch alone is not a rendered loading/completion barrier.
      // This is the stale enabled state that the old E2E predicate accepted.
      expect(canPublish(), isTrue);
      expect(canRemove(), isFalse);
      await tester.pump();
      await tester.pump();
      expect(canPublish(), isFalse);
      expect(canRemove(), isFalse);
      expect(gateway.requests, isEmpty);
      processor.pending!.complete(
        ProductCutoutCandidate(
          bytes: pixels,
          mimeType: 'image/png',
          width: 1,
          height: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(canRemove(), isTrue);
      expect(canPublish(), isTrue);
      expect(gateway.requests, isEmpty);
    },
  );
}
