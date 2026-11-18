// Local adapter/widget proof only. Real Storage/Edge/CAS persistence is NOT_RUN.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_path.dart';
import 'package:restoflow_dashboard/src/branding/restaurant_logo_storage.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_background_upload.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_slot.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_image_upload.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const org = '11111111-1111-4111-8111-111111111111';
const rest = '22222222-2222-4222-8222-222222222222';
const image = '33333333-3333-4333-8333-333333333333';
const media = '44444444-4444-4444-8444-444444444444';
const assignment = '55555555-5555-4555-8555-555555555555';
const source = '$org/$rest/logo/$image.jpg';

PickedMenuImage picked() => PickedMenuImage(
  bytes: Uint8List.fromList([1, 2, 3]),
  mimeType: 'image/jpeg',
  fileName: 'private-name.jpg',
);

class _Storage implements RestaurantLogoStorage {
  final uploads = <({String key, String mime})>[];
  Completer<void>? pending;
  @override
  Future<void> upload({
    required String objectKey,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploads.add((key: objectKey, mime: mimeType));
    await pending?.future;
  }

  @override
  Future<Uri> createSignedUrl(
    String key, {
    Duration expiresIn = const Duration(minutes: 30),
  }) => throw StateError('must not sign the private original');
  @override
  Future<void> remove(String key) =>
      throw StateError('must not delete private/shared media');
}

class _Invoker implements StorefrontFunctionInvoker {
  final calls = <Map<String, Object?>>[];
  String outcome = 'published';
  Completer<void>? pending;
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) async {
    calls.add(Map.of(body));
    await pending?.future;
    if (outcome == 'uncertain')
      return const StorefrontFunctionReply.transportFailure();
    if (outcome == 'refused')
      return StorefrontFunctionReply.fromHttp(422, {
        'ok': false,
        'status': 'refused',
        'code': 'not_a_decodable_image',
      });
    if (outcome == 'denied')
      return StorefrontFunctionReply.fromHttp(403, {
        'ok': false,
        'status': 'permission_denied',
      });
    return StorefrontFunctionReply.fromHttp(200, {
      'ok': true,
      'status': 'published',
      'profile_version': 41,
      'media': {
        'id': media,
        'object_key': '${'b' * 32}/${'a' * 64}.webp',
        'content_hash': 'a' * 64,
        'width': 960,
        'height': 640,
        'bytes': 1200,
        'variant': 'w960',
        'source_bucket': 'restaurant-logos',
        'source_key': outcome == 'mismatch'
            ? '$org/$rest/logo/another.jpg'
            : body['source_key'],
        'state': 'published',
      },
    });
  }
}

class _Rig {
  _Rig({this.disableOnOwnBusy = false, this.locale = 'en'}) {
    upload = newUpload();
    publisher = newPublisher(invoker);
  }
  final String locale;
  final bool disableOnOwnBusy;
  final storage = _Storage(), invoker = _Invoker();
  late StorefrontBackgroundUpload upload;
  late StorefrontMediaPublisher publisher;
  late StateSetter update;
  Object binding = 'member-a:branch-a';
  bool enabled = true, parentBusy = false, show = true;
  int picks = 0, refreshes = 0;
  Completer<PickedMenuImage?>? picker;
  final busyCalls = <({Object binding, bool value})>[];
  final assignCalls =
      <
        ({
          Object binding,
          StorefrontSlot slot,
          String? id,
          bool readFirst,
          StorefrontSlotReplay? replay,
        })
      >[];
  final assignmentResults = <StorefrontWriteResult>[];
  final contentDraft = {'headline': 'Unchanged welcome draft'};
  int assignCallbackCalls = 0;
  StorefrontBackgroundUpload newUpload() => StorefrontBackgroundUpload(
    storage: storage,
    organizationId: org,
    restaurantId: rest,
    ids: const FixedLogoImageIdGenerator(image),
    pickerSupported: true,
    picker: () async {
      picks++;
      return picker == null ? picked() : picker!.future;
    },
  );
  StorefrontMediaPublisher newPublisher(
    _Invoker value, {
    String restaurant = rest,
  }) => StorefrontMediaPublisher(
    invoker: value,
    organizationId: org,
    restaurantId: restaurant,
    retryDelay: Duration.zero,
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                final identity = binding,
                    capturedUpload = upload,
                    capturedPublisher = publisher;
                bool current() =>
                    context.mounted &&
                    binding == identity &&
                    identical(upload, capturedUpload) &&
                    identical(publisher, capturedPublisher);
                return show
                    ? StorefrontWelcomeImageUpload(
                        upload: capturedUpload,
                        publisher: capturedPublisher,
                        bindingIdentity: identity,
                        enabled: enabled && !(disableOnOwnBusy && parentBusy),
                        nonce: () => 17,
                        onAssign:
                            (slot, id, {required reReadFirst, replay}) async {
                              assignCallbackCalls++;
                              if (!current())
                                return const StorefrontWriteResult(
                                  StorefrontWriteStatus.unavailable,
                                );
                              assignCalls.add((
                                binding: identity,
                                slot: slot,
                                id: id,
                                readFirst: reReadFirst,
                                replay: replay,
                              ));
                              return assignmentResults.isEmpty
                                  ? const StorefrontWriteResult(
                                      StorefrontWriteStatus.ok,
                                    )
                                  : assignmentResults.removeAt(0);
                            },
                        onRefresh: ({bool reloadSources = false}) async {
                          if (current()) refreshes++;
                        },
                        onBusyChanged: (value) {
                          busyCalls.add((binding: identity, value: value));
                          if (current()) setState(() => parentBusy = value);
                        },
                      )
                    : const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> begin(WidgetTester tester, {bool confirm = true}) async {
  await tester.tap(find.byKey(const Key('welcome-image-upload-pick')));
  await tester.pumpAndSettle();
  if (confirm) {
    await tester.tap(
      find.byKey(const Key('welcome-image-upload-confirm-action')),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'confirmation precedes picking; cancel makes no upload/publish/profile operation',
    (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await begin(tester, confirm: false);
      expect(rig.picks, 0);
      await tester.tap(
        find.byKey(const Key('welcome-image-upload-confirm-cancel')),
      );
      await tester.pumpAndSettle();
      expect(rig.storage.uploads, isEmpty);
      expect(rig.invoker.calls, isEmpty);
      expect(rig.assignCalls, isEmpty);
      expect(rig.busyCalls.map((e) => e.value), [true, false]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'independent private source publishes editorial w960 then assigns only Hero with fresh CAS read',
    (tester) async {
      final rig = _Rig(disableOnOwnBusy: true);
      await rig.pump(tester);
      await begin(tester);
      expect(rig.storage.uploads.single.key, source);
      expect(rig.invoker.calls.single['source_key'], source);
      expect(rig.invoker.calls.single['source_bucket'], 'restaurant-logos');
      expect(rig.invoker.calls.single['slot'], 'hero');
      expect(rig.invoker.calls.single['variant'], 'w960');
      expect(rig.assignCalls.single.slot, StorefrontSlot.hero);
      expect(rig.assignCalls.single.id, media);
      expect(rig.assignCalls.single.readFirst, isTrue);
      expect(rig.assignCalls.single.replay, isNull);
      expect(rig.contentDraft, {'headline': 'Unchanged welcome draft'});
      expect(rig.busyCalls.map((e) => e.value), [true, false]);
      expect(rig.parentBusy, isFalse);
      expect(
        find.text(
          'Welcome image applied. Welcome text is still saved separately.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('cancelling the file picker releases busy without publication', (
    tester,
  ) async {
    final rig = _Rig()..picker = Completer<PickedMenuImage?>();
    await rig.pump(tester);
    await begin(tester);
    rig.picker!.complete(null);
    await tester.pumpAndSettle();
    expect(rig.storage.uploads, isEmpty);
    expect(rig.assignCalls, isEmpty);
    expect(rig.parentBusy, isFalse);
  });
  testWidgets(
    'unknown publication retries the SAME request/source without picking or uploading again',
    (tester) async {
      final rig = _Rig();
      rig.invoker.outcome = 'uncertain';
      await rig.pump(tester);
      await begin(tester);
      expect(
        rig.invoker.calls,
        hasLength(2),
        reason: 'existing publisher bounded retry is unchanged',
      );
      final first = rig.invoker.calls.first;
      expect(rig.assignCalls, isEmpty);
      expect(rig.refreshes, 1);
      expect(rig.storage.uploads, hasLength(1));
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('welcome-image-upload-pick')),
            )
            .onPressed,
        isNull,
      );
      rig.invoker.outcome = 'published';
      await tester.tap(find.byKey(const Key('welcome-image-upload-retry')));
      await tester.pumpAndSettle();
      expect(rig.invoker.calls.last, first);
      expect(rig.storage.uploads, hasLength(1));
      expect(rig.picks, 1);
      expect(rig.assignCalls, hasLength(1));
    },
  );
  testWidgets(
    'unknown assignment retries ONLY assignment with original expected version/request id',
    (tester) async {
      final rig = _Rig();
      rig.assignmentResults.add(
        const StorefrontWriteResult(
          StorefrontWriteStatus.uncertain,
          requestId: assignment,
          expectedVersion: 7,
        ),
      );
      await rig.pump(tester);
      await begin(tester);
      expect(rig.assignCalls, hasLength(1));
      await tester.tap(find.byKey(const Key('welcome-image-upload-retry')));
      await tester.pumpAndSettle();
      expect(rig.assignCalls, hasLength(2));
      expect(rig.assignCalls.last.replay!.requestId, assignment);
      expect(rig.assignCalls.last.replay!.expectedVersion, 7);
      expect(rig.assignCalls.last.id, media);
      expect(rig.assignCalls.every((e) => e.readFirst), isTrue);
      expect(rig.invoker.calls, hasLength(1));
      expect(rig.storage.uploads, hasLength(1));
    },
  );
  testWidgets(
    'unknown assignment without identity never fabricates a replay or success',
    (tester) async {
      final rig = _Rig();
      rig.assignmentResults.add(
        const StorefrontWriteResult(StorefrontWriteStatus.uncertain),
      );
      await rig.pump(tester);
      await begin(tester);
      expect(find.byKey(const Key('welcome-image-upload-retry')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('welcome-image-upload-pick')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text(
          'Welcome image applied. Welcome text is still saved separately.',
        ),
        findsNothing,
      );
      expect(rig.assignCalls, hasLength(1));
    },
  );
  testWidgets(
    'typed refusal and assignment conflict are not presented as applied',
    (tester) async {
      final refused = _Rig();
      refused.invoker.outcome = 'refused';
      await refused.pump(tester);
      await begin(tester);
      expect(refused.assignCalls, isEmpty);
      expect(find.textContaining('publisher refused'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final conflict = _Rig();
      conflict.assignmentResults.add(
        const StorefrontWriteResult(StorefrontWriteStatus.conflict),
      );
      await conflict.pump(tester);
      await begin(tester);
      expect(find.textContaining('was not applied'), findsOneWidget);
      expect(
        find.text(
          'Welcome image applied. Welcome text is still saved separately.',
        ),
        findsNothing,
      );
    },
  );
  testWidgets(
    'a historical dedup response for a different source cannot assign the welcome image',
    (tester) async {
      final rig = _Rig();
      rig.invoker.outcome = 'mismatch';
      await rig.pump(tester);
      await begin(tester);
      expect(rig.assignCalls, isEmpty);
      expect(rig.refreshes, 1);
      expect(
        find.byKey(const Key('welcome-image-upload-retry')),
        findsOneWidget,
      );
      expect(find.text(source), findsNothing);
    },
  );
  testWidgets(
    'upload and publisher restaurant mismatch disables picking before any work',
    (tester) async {
      final rig = _Rig();
      rig.publisher = rig.newPublisher(rig.invoker, restaurant: media);
      await rig.pump(tester);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('welcome-image-upload-pick')),
            )
            .onPressed,
        isNull,
      );
      expect(rig.picks, 0);
      expect(rig.invoker.calls, isEmpty);
    },
  );
  testWidgets(
    'a member/branch switch while the file picker is open performs no old upload',
    (tester) async {
      final rig = _Rig()..picker = Completer<PickedMenuImage?>();
      await rig.pump(tester);
      await begin(tester);
      rig.update(() {
        rig.binding = 'member-b:branch-b';
        rig.parentBusy = false;
      });
      await tester.pumpAndSettle();
      rig.picker!.complete(picked());
      await tester.pumpAndSettle();
      expect(rig.storage.uploads, isEmpty);
      expect(rig.invoker.calls, isEmpty);
      expect(rig.assignCallbackCalls, 0);
      expect(
        rig.busyCalls.where((e) => e.binding == 'member-b:branch-b'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching authenticated transports during publication cannot assign via old/new callbacks',
    (tester) async {
      final rig = _Rig();
      rig.invoker.pending = Completer<void>();
      await rig.pump(tester);
      await begin(tester);
      final oldInvoker = rig.invoker;
      rig.update(() {
        rig.publisher = rig.newPublisher(_Invoker());
        rig.parentBusy = false;
      });
      await tester.pumpAndSettle();
      oldInvoker.pending!.complete();
      await tester.pumpAndSettle();
      expect(rig.assignCallbackCalls, 0);
      expect(find.byKey(const Key('welcome-image-upload-retry')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new binding clears the pending assignment replay before it can be reused',
    (tester) async {
      final rig = _Rig();
      rig.assignmentResults.add(
        const StorefrontWriteResult(
          StorefrontWriteStatus.uncertain,
          requestId: assignment,
          expectedVersion: 7,
        ),
      );
      await rig.pump(tester);
      await begin(tester);
      rig.update(() {
        rig.binding = 'replacement-member';
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcome-image-upload-retry')), findsNothing);
      expect(rig.assignCalls, hasLength(1));
    },
  );
  testWidgets(
    'replacing upload transport during its private write cannot continue with the old source',
    (tester) async {
      final rig = _Rig();
      rig.storage.pending = Completer<void>();
      await rig.pump(tester);
      await begin(tester);
      final replacementStorage = _Storage();
      rig.update(() {
        rig.upload = StorefrontBackgroundUpload(
          storage: replacementStorage,
          organizationId: org,
          restaurantId: rest,
          ids: const FixedLogoImageIdGenerator(image),
          pickerSupported: true,
          picker: () async => picked(),
        );
        rig.parentBusy = false;
      });
      await tester.pumpAndSettle();
      rig.storage.pending!.complete();
      await tester.pumpAndSettle();
      expect(rig.storage.uploads, hasLength(1));
      expect(replacementStorage.uploads, isEmpty);
      expect(rig.invoker.calls, isEmpty);
      expect(rig.assignCallbackCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changing member while publication is in flight never applies its late answer',
    (tester) async {
      final rig = _Rig();
      rig.invoker.pending = Completer<void>();
      await rig.pump(tester);
      await begin(tester);
      rig.update(() {
        rig.binding = 'different-member';
        rig.parentBusy = false;
      });
      await tester.pumpAndSettle();
      rig.invoker.pending!.complete();
      await tester.pumpAndSettle();
      expect(rig.invoker.calls, hasLength(1));
      expect(rig.assignCallbackCalls, 0);
      expect(find.byKey(const Key('welcome-image-upload-retry')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancel after publication starts never follows the late answer with an assignment',
    (tester) async {
      final rig = _Rig();
      rig.invoker.pending = Completer<void>();
      await rig.pump(tester);
      await begin(tester);
      await tester.tap(find.byKey(const Key('welcome-image-upload-cancel')));
      await tester.pumpAndSettle();
      rig.invoker.pending!.complete();
      await tester.pumpAndSettle();
      expect(rig.invoker.calls, hasLength(1));
      expect(rig.assignCallbackCalls, 0);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('may already have started'), findsOneWidget);
    },
  );
  testWidgets(
    'cancel continuation during a private upload leaves no subsequent publish or assignment',
    (tester) async {
      final rig = _Rig();
      rig.storage.pending = Completer<void>();
      await rig.pump(tester);
      await begin(tester);
      await tester.tap(find.byKey(const Key('welcome-image-upload-cancel')));
      await tester.pumpAndSettle();
      rig.storage.pending!.complete();
      await tester.pumpAndSettle();
      expect(rig.storage.uploads, hasLength(1));
      expect(rig.invoker.calls, isEmpty);
      expect(rig.assignCallbackCalls, 0);
      expect(find.textContaining('may already have started'), findsOneWidget);
    },
  );
  testWidgets(
    'dispose releases only captured old busy callback without setState during disposal or late assignment',
    (tester) async {
      final rig = _Rig();
      rig.storage.pending = Completer<void>();
      await rig.pump(tester);
      await begin(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      rig.storage.pending!.complete();
      await tester.pumpAndSettle();
      expect(rig.busyCalls.map((e) => e.value), [true, false]);
      expect(rig.assignCallbackCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changing binding during confirmation closes only that dialog and starts no picker',
    (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await begin(tester, confirm: false);
      rig.update(() {
        rig.binding = 'replacement-member';
        rig.parentBusy = false;
      });
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('welcome-image-upload-confirm')),
        findsNothing,
      );
      expect(rig.picks, 0);
      expect(rig.assignCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final (language, label) in [
    ('ar', 'رفع صورة ترحيب'),
    ('he', 'העלאת תמונת פתיחה'),
    ('en', 'Upload welcome image'),
  ]) {
    testWidgets(
      'own localized upload labels support $language without modifying shared copy',
      (tester) async {
        final rig = _Rig(locale: language);
        await rig.pump(tester);
        expect(find.text(label), findsOneWidget);
      },
    );
  }
}
