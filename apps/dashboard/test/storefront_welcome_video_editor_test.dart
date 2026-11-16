import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_editor.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_file.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_upload.dart';

import 'storefront_welcome_video_publisher_test.dart'
    show VideoInvoker, org, restaurant, request, id, videoMedia, publishedVideo;
import 'storefront_welcome_video_upload_test.dart'
    show VideoStorage, imageId, clientFile;

class _DelayedInvoker extends VideoInvoker {
  _DelayedInvoker() : super([]);
  final answer = Completer<StorefrontFunctionReply>();
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) {
    bodies.add(Map.of(body));
    return answer.future;
  }
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.invoker,
    required this.storage,
    required this.picker,
    this.initialMode,
    this.initialSelection,
    this.available = true,
    super.key,
  });
  final VideoInvoker invoker;
  final VideoStorage storage;
  final Future<PickedWelcomeVideo?> Function() picker;
  final String? initialMode, initialSelection;
  final bool available;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool busy = false;
  String scope = 'A';
  late String? mode = widget.initialMode, selection = widget.initialSelection;
  int reloads = 0;
  final drafts = <(String, Object?)>[];
  final busyEvents = <bool>[];
  List<StorefrontWelcomeVideoMedia> rows = [
    StorefrontWelcomeVideoMedia.fromJson(videoMedia()),
  ];
  void switchBinding() => setState(() => scope = 'B');
  @override
  Widget build(BuildContext context) => StorefrontWelcomeVideoEditor(
    media: rows,
    mode: mode,
    selectedId: selection,
    bindingIdentity: scope,
    libraryAvailable: widget.available,
    enabled: !busy,
    canPublish: !busy,
    // Re-created wrappers keep the same actual invoker/storage binding.
    publisher: StorefrontWelcomeVideoPublisher(
      invoker: widget.invoker,
      organizationId: scope == 'A' ? org : request,
      restaurantId: restaurant,
    ),
    uploader: StorefrontWelcomeVideoUpload(
      storage: widget.storage,
      organizationId: scope == 'A' ? org : request,
      restaurantId: restaurant,
      picker: widget.picker,
      pickerSupported: true,
      ids: () => imageId,
    ),
    publicUrlFor: widget.storage.publicWelcomeVideoUrl,
    requestIds: () => request,
    onChanged: (field, value) {
      expect(
        busy,
        isFalse,
        reason: 'Draft callbacks run only when parent content is editable',
      );
      drafts.add((field, value));
      setState(() {
        if (field == 'welcome_media_type')
          mode = value as String?;
        else
          selection = value as String?;
      });
    },
    onReload: () async {
      reloads++;
      if (mounted) setState(() {});
    },
    onBusyChanged: (value) {
      if (mounted)
        setState(() {
          busy = value;
          busyEvents.add(value);
        });
    },
  );
}

Future<GlobalKey<_HarnessState>> mount(
  WidgetTester tester,
  VideoInvoker invoker,
  VideoStorage storage, {
  Future<PickedWelcomeVideo?> Function()? picker,
  String? mode,
  String? selected,
  bool available = true,
}) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _Harness(
              key: key,
              invoker: invoker,
              storage: storage,
              picker: picker ?? () async => clientFile(),
              initialMode: mode,
              initialSelection: selected,
              available: available,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

Future<void> press(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'late publisher response from an old membership never changes the new editor',
    (tester) async {
      final invoker = _DelayedInvoker(), storage = VideoStorage();
      final key = await mount(tester, invoker, storage);
      await tester.tap(find.byKey(const Key('welcome-video-upload')));
      await tester.pump();
      expect(invoker.bodies, hasLength(1));
      key.currentState!.switchBinding();
      await tester.pumpAndSettle();
      invoker.answer.complete(
        StorefrontFunctionReply.fromHttp(200, publishedVideo()),
      );
      await tester.pumpAndSettle();
      expect(invoker.bodies, hasLength(1));
      expect(key.currentState!.reloads, 0);
      expect(key.currentState!.drafts, isEmpty);
      expect(key.currentState!.selection, isNull);
      expect(key.currentState!.busy, isFalse);
      expect(find.byKey(const Key('welcome-video-retry')), findsNothing);
      expect(
        find.text('نُشر الفيديو. اختره واحفظ المحتوى لاستخدامه.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'actual upload/publish action never selects or enables video; own busy does not abort it',
    (tester) async {
      final invoker = VideoInvoker([
            StorefrontFunctionReply.fromHttp(200, publishedVideo()),
          ]),
          storage = VideoStorage()..wait = Completer<void>();
      final key = await mount(tester, invoker, storage);
      await tester.tap(find.byKey(const Key('welcome-video-upload')));
      await tester.pump();
      expect(key.currentState!.busy, isTrue);
      expect(storage.writes, hasLength(1));
      expect(invoker.bodies, isEmpty);
      storage.wait!.complete();
      await tester.pumpAndSettle();
      expect(invoker.bodies, hasLength(1));
      expect(key.currentState!.busy, isFalse);
      expect(key.currentState!.busyEvents, [true, false]);
      expect(key.currentState!.reloads, 1);
      expect(key.currentState!.drafts, isEmpty);
      expect(key.currentState!.mode, isNull);
      expect(key.currentState!.selection, isNull);
      expect(
        find.text('نُشر الفيديو. اختره واحفظ المحتوى لاستخدامه.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('welcome-video-public-preview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown original response requires explicit same-identity retry, with no second upload',
    (tester) async {
      final invoker = VideoInvoker([
            const StorefrontFunctionReply.transportFailure(),
            StorefrontFunctionReply.fromHttp(200, publishedVideo()),
          ]),
          storage = VideoStorage();
      final key = await mount(tester, invoker, storage);
      await press(tester, 'welcome-video-upload');
      expect(invoker.bodies, hasLength(1));
      expect(find.byKey(const Key('welcome-video-retry')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(invoker.bodies, hasLength(1));
      await press(tester, 'welcome-video-retry');
      expect(invoker.bodies, hasLength(2));
      expect(invoker.bodies.first, invoker.bodies.last);
      expect(storage.writes, hasLength(1));
      expect(key.currentState!.drafts, isEmpty);
      expect(key.currentState!.reloads, 1);
    },
  );

  testWidgets(
    'membership change while picking retires old upload and request',
    (tester) async {
      final picked = Completer<PickedWelcomeVideo?>(),
          invoker = VideoInvoker([
            StorefrontFunctionReply.fromHttp(200, publishedVideo()),
          ]),
          storage = VideoStorage();
      final key = await mount(
        tester,
        invoker,
        storage,
        picker: () => picked.future,
      );
      await tester.tap(find.byKey(const Key('welcome-video-upload')));
      await tester.pump();
      key.currentState!.switchBinding();
      await tester.pumpAndSettle();
      picked.complete(clientFile());
      await tester.pumpAndSettle();
      expect(storage.writes, isEmpty);
      expect(invoker.bodies, isEmpty);
      expect(key.currentState!.busy, isFalse);
      expect(key.currentState!.drafts, isEmpty);
      expect(find.byKey(const Key('welcome-video-retry')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled native file selection leaves mode/media untouched', (
    tester,
  ) async {
    final invoker = VideoInvoker([
          StorefrontFunctionReply.fromHttp(200, publishedVideo()),
        ]),
        storage = VideoStorage();
    final key = await mount(
      tester,
      invoker,
      storage,
      picker: () async => null,
      mode: 'video',
      selected: id,
    );
    await press(tester, 'welcome-video-upload');
    expect(key.currentState!.busy, isFalse);
    expect(key.currentState!.mode, 'video');
    expect(key.currentState!.selection, id);
    expect(storage.writes, isEmpty);
    expect(invoker.bodies, isEmpty);
    expect(key.currentState!.drafts, isEmpty);
  });

  testWidgets(
    'mode and clear are drafts only; clearing selection preserves video mode fallback',
    (tester) async {
      final invoker = VideoInvoker([
            StorefrontFunctionReply.fromHttp(200, publishedVideo()),
          ]),
          storage = VideoStorage();
      final key = await mount(
        tester,
        invoker,
        storage,
        mode: 'video',
        selected: id,
      );
      await tester.tap(
        find.byKey(
          const ValueKey(
            'welcome-video-selection-44444444-4444-4444-8444-444444444444',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('بدون فيديو — استخدام الصورة البديلة').last);
      await tester.pumpAndSettle();
      expect(key.currentState!.selection, isNull);
      expect(key.currentState!.mode, 'video');
      expect(key.currentState!.drafts, [('welcome_video_media_id', null)]);
      await tester.tap(find.byKey(const ValueKey('welcome-video-mode-video')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('صورة').last);
      await tester.pumpAndSettle();
      expect(key.currentState!.mode, 'image');
      expect(invoker.bodies, isEmpty);
      expect(storage.writes, isEmpty);
      expect(key.currentState!.reloads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable library is not silently accepted as an empty read', (
    tester,
  ) async {
    final invoker = VideoInvoker([
          StorefrontFunctionReply.fromHttp(200, publishedVideo()),
        ]),
        storage = VideoStorage();
    final key = await mount(
      tester,
      invoker,
      storage,
      available: false,
      selected: request,
    );
    tester.view.physicalSize = const Size(390, 1300);
    await tester.pumpAndSettle();
    expect(find.text('تعذرت قراءة مكتبة الفيديو.'), findsOneWidget);
    expect(find.text('الفيديو المحفوظ غير متاح'), findsOneWidget);
    expect(key.currentState!.selection, request);
    expect(key.currentState!.drafts, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
