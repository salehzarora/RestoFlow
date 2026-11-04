import 'dart:async';
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
  final requests = <({String id, Uint8List? candidate})>[];
  ProductCutoutPublishStatus status = ProductCutoutPublishStatus.published;
  @override
  Future<ProductCutoutOriginal> loadOriginal(MenuItem item) async {
    loads++;
    return ProductCutoutOriginal(
      bytes: pixels,
      mimeType: 'image/png',
      sourceKey: item.imagePath!,
      sourceGeneration: 'gen',
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
    requests.add((id: requestId, candidate: candidateBytes));
    return ProductCutoutPublishResult(status);
  }
}

class Processor implements ProductCutoutProcessor {
  bool fail = false, transparent = false;
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
      bytes: pixels,
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
}
