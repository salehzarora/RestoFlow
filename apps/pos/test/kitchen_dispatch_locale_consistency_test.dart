@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/testing.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/online_order_print_repository.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart';
import 'package:restoflow_pos/src/spool/online_order_print_hooks.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition_native.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_platform.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_runtime.dart';
import 'package:restoflow_pos/src/state/locale_controller.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

const _savedName = 'Classic برجر / המבורגר';
const _savedModifier = '240g גבינה';
const _savedNote = 'بدون صوص / ללא רוטב';

KitchenDispatchDocument _document(KitchenSpoolDispatchType kind) {
  final items = [
    KitchenDispatchItem(
      qty: 2,
      name: _savedName,
      note: _savedNote,
      prep: [
        KitchenDispatchPrepComponent(name: 'Bread', quantity: 1, unit: 'pc'),
      ],
      modifiers: [
        KitchenDispatchModifier(
          qty: 2,
          name: _savedModifier,
          prep: KitchenDispatchModifierPrep(
            quantity: 2,
            unit: 'meat',
            classifierOptionId: 'cheese-option',
            classifierOptionName: 'Cheese',
            classifierSelected: false,
          ),
        ),
      ],
    ),
    KitchenDispatchItem(
      qty: 1,
      name: 'Wrap لفّة',
      prep: [
        KitchenDispatchPrepComponent(name: 'Wrap', quantity: 3, unit: 'pc'),
      ],
    ),
  ];
  return KitchenDispatchDocument(
    serverPayloadVersion: 1,
    kind: kind,
    orderCode: '#LOCALE01',
    orderType: 'takeaway',
    orderNote: 'Saved order note: $_savedNote',
    createdAt: '2026-10-17T00:00:00Z',
    items: kind == KitchenSpoolDispatchType.orderEdit ? const [] : items,
    roundId: kind == KitchenSpoolDispatchType.serviceRound ? 'round-2' : null,
    roundNumber: kind == KitchenSpoolDispatchType.serviceRound ? 2 : null,
    voidMarker: kind == KitchenSpoolDispatchType.voidNotice,
    reason: kind == KitchenSpoolDispatchType.voidNotice ? _savedNote : null,
    affectedItemCount: kind == KitchenSpoolDispatchType.voidNotice ? 3 : null,
    editNumber: kind == KitchenSpoolDispatchType.orderEdit ? 1 : null,
    reasonCode: kind == KitchenSpoolDispatchType.orderEdit ? 'other' : null,
    staffName: kind == KitchenSpoolDispatchType.orderEdit ? 'Tester' : null,
    editLines: kind == KitchenSpoolDispatchType.orderEdit
        ? [KitchenDispatchEditAdd(now: items)]
        : const [],
    orderNow: kind == KitchenSpoolDispatchType.orderEdit ? items : const [],
  );
}

ProviderContainer _device(String language) => ProviderContainer(
  overrides: [initialLocaleProvider.overrideWithValue(Locale(language))],
);

PosSelectedLocaleKitchenDispatchRenderer _renderer(
  ProviderContainer device,
  pp.ReceiptRasterizer rasterizer, {
  bool Function()? isCurrent,
  void Function()? onRead,
}) => PosSelectedLocaleKitchenDispatchRenderer(
  languageCode: () {
    onRead?.call();
    return device.read(localeControllerProvider).languageCode;
  },
  isCurrent: isCurrent ?? () => true,
  rasterizer: rasterizer,
  restaurantName: 'QA kitchen',
);

/// Manual printing uses the same selected POS AppLocalizations, independently
/// of Android/Flutter's platform locale. Compare the full encoded document and
/// raster requests, including saved content, styles and preparation ordering.
CanonicalKitchenDispatchRenderer _manualRenderer(
  String language,
  pp.ReceiptRasterizer rasterizer,
) {
  final l10n = lookupAppLocalizations(Locale(language));
  return CanonicalKitchenDispatchRenderer(
    labels: kitchenTicketPrintLabelsFromL10n(l10n),
    changeLabels: kitchenChangeSlipLabelsFromL10n(l10n),
    voidRenderer: KitchenTicketRenderer(
      labels: KitchenTicketLabels.forLanguageCode(language),
      rasterizer: rasterizer,
    ),
    rasterizer: rasterizer,
    restaurantName: 'QA kitchen',
  );
}

Future<void> _expectManualParity(
  PosSelectedLocaleKitchenDispatchRenderer renderer,
  pp.FakeReceiptRasterizer raster,
  String language,
  KitchenSpoolDispatchType kind,
) async {
  final document = _document(kind);
  final before = jsonEncode(document.toJson());
  raster.requests.clear();
  final bytes = await renderer.renderToBytes(document);
  final manualRaster = pp.FakeReceiptRasterizer();
  final manualBytes = await _manualRenderer(
    language,
    manualRaster,
  ).renderToBytes(document);
  expect(bytes, orderedEquals(manualBytes));
  expect(raster.requests, isNotEmpty, reason: 'Unicode must reach rasterizer');
  expect(raster.requests.length, manualRaster.requests.length);
  for (var i = 0; i < raster.requests.length; i++) {
    expect(raster.requests[i].lines, manualRaster.requests[i].lines);
    expect(raster.requests[i].styles, manualRaster.requests[i].styles);
    expect(raster.requests[i].direction, manualRaster.requests[i].direction);
    expect(raster.requests[i].widthDots, manualRaster.requests[i].widthDots);
  }
  final lines = raster.requests.expand((r) => r.lines).toList();
  expect(lines.any((l) => l.contains(_savedName)), isTrue);
  expect(lines.any((l) => l.contains(_savedModifier)), isTrue);
  expect(lines.any((l) => l.contains(_savedNote)), isTrue);
  expect(
    jsonEncode(document.toJson()),
    before,
    reason: 'No snapshot mutations',
  );
  if (kind == KitchenSpoolDispatchType.initialOrder ||
      kind == KitchenSpoolDispatchType.serviceRound) {
    final counts = kdsTicketViewFromKitchenDispatch(document).kitchenCounts;
    expect(counts.map((c) => (c.label, c.quantity)), [
      ('meat', 8),
      ('Bread pc', 2),
      ('Wrap pc', 3),
    ]);
    final firstItem = lines.indexWhere((l) => l.contains(_savedName));
    final l10n = lookupAppLocalizations(Locale(language));
    final totalPrefix = l10n.kdsMeatTotalLabel('2', 'Bread pc');
    expect(
      lines.indexWhere((l) => l.contains(totalPrefix)),
      lessThan(firstItem),
    );
  }
}

class _PausedRasterizer extends pp.FakeReceiptRasterizer {
  final entered = Completer<void>();
  final release = Completer<void>();
  var _paused = false;

  @override
  Future<pp.ReceiptRasterImage> rasterize(
    pp.ReceiptRasterRequest request,
  ) async {
    if (!_paused) {
      _paused = true;
      entered.complete();
      await release.future;
    }
    return super.rasterize(request);
  }
}

class _RealInkRasterizer implements pp.ReceiptRasterizer {
  var calls = 0;

  @override
  Future<pp.ReceiptRasterImage> rasterize(
    pp.ReceiptRasterRequest request,
  ) async {
    final image = await const FlutterReceiptRasterizer().rasterize(request);
    calls++;
    expect(image.widthBytes, request.widthDots ~/ 8);
    expect(image.heightDots, greaterThan(0));
    expect(
      image.data.any((b) => b != 0),
      isTrue,
      reason: 'Real bitmap has ink',
    );
    return image;
  }
}

class _ImportAckTransport implements SyncRpcTransport {
  final calls = <String>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    if (function != 'acknowledge_kitchen_print_dispatch') {
      throw StateError('Unexpected non-ACK operation in offline test');
    }
    return {'ok': true};
  }
}

class _TargetRepository implements OnlineOrderPrintRepository {
  var begins = 0;
  var finishes = 0;
  final _attempts = <String, String>{};
  final _sent = <String>{};

  OnlineOrderPrintResult _result(String request, {bool send = false}) =>
      OnlineOrderPrintResult(
        requestId: request,
        orderId: 'order-$request',
        dispatchId: 'dispatch-$request',
        decisionId: 'decision-$request',
        printerAssignmentId: 'qa-assignment',
        state: _sent.contains(request)
            ? OnlineOrderPrintState.transportAccepted
            : send
            ? OnlineOrderPrintState.sendReserved
            : OnlineOrderPrintState.claimed,
        attemptId: _attempts[request],
        sendAuthorized: send,
        dispatch: PulledKitchenDispatch(
          dispatchId: 'dispatch-$request',
          dispatchType: 'initial_order',
          orderId: 'order-$request',
          payloadVersion: 1,
          moneyFreePayload: _document(
            KitchenSpoolDispatchType.initialOrder,
          ).toJson(),
          createdAt: '2026-10-17T00:00:00Z',
        ),
      );

  @override
  Future<OnlineOrderPrintResult> claim(String requestId) async =>
      _result(requestId);
  @override
  Future<OnlineOrderPrintResult> status(String requestId) async =>
      _result(requestId);
  @override
  Future<OnlineOrderPrintResult> begin(
    String requestId,
    String attemptId,
  ) async {
    begins++;
    if (_attempts.containsKey(requestId)) throw StateError('Duplicate begin');
    _attempts[requestId] = attemptId;
    return _result(requestId, send: true);
  }

  @override
  Future<OnlineOrderPrintResult> finish(
    String requestId,
    String attemptId,
    String clientStatus, {
    String? errorCode,
  }) async {
    expect(_attempts[requestId], attemptId);
    expect(clientStatus, 'transport_accepted');
    finishes++;
    _sent.add(requestId);
    return _result(requestId);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (platform, selected) in [
    ('en', 'ar'),
    ('en', 'he'),
    ('ar', 'en'),
  ]) {
    for (final kind in KitchenSpoolDispatchType.values) {
      test(
        'platform $platform / POS $selected: ${kind.wireName} manual parity',
        () async {
          binding.platformDispatcher.localeTestValue = Locale(platform);
          addTearDown(binding.platformDispatcher.clearLocaleTestValue);
          final device = _device(selected);
          addTearDown(device.dispose);
          final raster = pp.FakeReceiptRasterizer();
          var reads = 0;
          final renderer = _renderer(device, raster, onRead: () => reads++);
          await _expectManualParity(renderer, raster, selected, kind);
          expect(reads, 1, reason: 'One POS-locale snapshot per render');
        },
      );
    }
  }

  test(
    'one retained renderer follows AR → HE → EN for all document kinds',
    () async {
      final device = _device('ar');
      addTearDown(device.dispose);
      final raster = pp.FakeReceiptRasterizer();
      final renderer = _renderer(device, raster);
      for (final language in ['ar', 'he', 'en']) {
        device
            .read(localeControllerProvider.notifier)
            .setLocale(Locale(language));
        for (final kind in KitchenSpoolDispatchType.values) {
          await _expectManualParity(renderer, raster, language, kind);
        }
      }
    },
  );

  for (final kind in KitchenSpoolDispatchType.values) {
    test(
      '${kind.wireName}: in-flight language fixed; next render uses new selection',
      () async {
        final device = _device('ar');
        addTearDown(device.dispose);
        final raster = _PausedRasterizer();
        var reads = 0;
        final renderer = _renderer(device, raster, onRead: () => reads++);
        final pending = renderer.renderToBytes(_document(kind));
        await raster.entered.future;
        device
            .read(localeControllerProvider.notifier)
            .setLocale(const Locale('he'));
        raster.release.complete();
        final bytes = await pending;
        final expectedRaster = pp.FakeReceiptRasterizer();
        expect(
          bytes,
          await _manualRenderer(
            'ar',
            expectedRaster,
          ).renderToBytes(_document(kind)),
        );
        expect(
          raster.requests.single.lines,
          expectedRaster.requests.single.lines,
        );
        expect(reads, 1);
        await _expectManualParity(renderer, raster, 'he', kind);
        expect(reads, 2);
      },
    );
  }

  test('two device-local containers choose independently', () async {
    final home = _device('ar');
    final restaurant = _device('he');
    addTearDown(home.dispose);
    addTearDown(restaurant.dispose);
    final homeRaster = pp.FakeReceiptRasterizer();
    final otherRaster = pp.FakeReceiptRasterizer();
    final homeRenderer = _renderer(home, homeRaster);
    final otherRenderer = _renderer(restaurant, otherRaster);
    await _expectManualParity(
      homeRenderer,
      homeRaster,
      'ar',
      KitchenSpoolDispatchType.initialOrder,
    );
    await _expectManualParity(
      otherRenderer,
      otherRaster,
      'he',
      KitchenSpoolDispatchType.initialOrder,
    );
    home.read(localeControllerProvider.notifier).setLocale(const Locale('en'));
    await _expectManualParity(
      homeRenderer,
      homeRaster,
      'en',
      KitchenSpoolDispatchType.initialOrder,
    );
    await _expectManualParity(
      otherRenderer,
      otherRaster,
      'he',
      KitchenSpoolDispatchType.initialOrder,
    );
  });

  test(
    'invalid runtime does not read language or produce printer bytes',
    () async {
      var reads = 0;
      final raster = pp.FakeReceiptRasterizer();
      final renderer = PosSelectedLocaleKitchenDispatchRenderer(
        languageCode: () {
          reads++;
          return 'en';
        },
        isCurrent: () => false,
        rasterizer: raster,
      );
      await expectLater(
        renderer.renderToBytes(
          _document(KitchenSpoolDispatchType.initialOrder),
        ),
        throwsStateError,
      );
      expect(reads, 0);
      expect(raster.requests, isEmpty);
    },
  );

  test(
    'disposed locale provider fails closed instead of English fallback',
    () async {
      final device = _device('ar');
      final raster = pp.FakeReceiptRasterizer();
      final renderer = _renderer(device, raster);
      device.dispose();
      await expectLater(
        renderer.renderToBytes(
          _document(KitchenSpoolDispatchType.initialOrder),
        ),
        throwsStateError,
      );
      expect(raster.requests, isEmpty);
    },
  );

  test('scope invalidation during rasterization discards bytes', () async {
    final device = _device('ar');
    addTearDown(device.dispose);
    final raster = _PausedRasterizer();
    var current = true;
    final renderer = _renderer(device, raster, isCurrent: () => current);
    final pending = renderer.renderToBytes(
      _document(KitchenSpoolDispatchType.initialOrder),
    );
    final failure = expectLater(pending, throwsStateError);
    await raster.entered.future;
    current = false;
    raster.release.complete();
    await failure;
  });

  for (final language in ['ar', 'he']) {
    test(
      'POS $language document reaches real Flutter rasterizer with ink',
      () async {
        final device = _device(language);
        addTearDown(device.dispose);
        final rasterizer = _RealInkRasterizer();
        final renderer = _renderer(device, rasterizer);
        final bytes = await renderer.renderToBytes(
          _document(KitchenSpoolDispatchType.initialOrder),
        );
        expect(bytes, isNotEmpty);
        // GS v 0 is the actual raster-image command, followed by bitmap bytes.
        final rasterCommand = [0x1d, 0x76, 0x30];
        var found = false;
        for (var i = 0; i < bytes.length - 3; i++) {
          if (bytes[i] == rasterCommand[0] &&
              bytes[i + 1] == rasterCommand[1] &&
              bytes[i + 2] == rasterCommand[2]) {
            found = true;
            break;
          }
        }
        expect(
          found,
          isTrue,
          reason: 'Arabic/Hebrew must not use ASCII-only labels',
        );
        expect(rasterizer.calls, 1);
      },
    );
  }

  test(
    'real retained target runtime: language switch never duplicates authorization/send',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rf_locale_target_',
      );
      final device = _device('ar');
      final raster = _PausedRasterizer();
      var current = true;
      final renderer = _renderer(device, raster, isCurrent: () => current);
      final repository = _TargetRepository();
      final transport = _ImportAckTransport();
      final secrets = InMemoryDeviceSessionSecretStore();
      await secrets.write(
        const DeviceSessionCredential(
          deviceId: 'qa-device',
          sessionToken: 'synthetic-device-token',
        ),
      );
      final sends = <Uint8List>[];
      var nextId = 0;
      const context = DeviceContext(
        organizationId: 'qa-org',
        restaurantId: 'qa-restaurant',
        branchId: 'qa-branch',
        deviceId: 'qa-device',
      );
      final runtime = PosKitchenSpoolRuntime(
        platform: const PosKitchenSpoolPlatform(isWeb: false),
        deviceContext: () => context,
        secretStore: secrets,
        modeRepository: null,
        ackRepository: SupabaseKitchenDispatchAckRepository(
          transport: transport,
          secretStore: secrets,
        ),
        fetchMode: () async => KitchenModePrinterOnlyWithRevision(
          revision: 1,
          verifiedAt: DateTime.utc(2026, 10, 17),
        ),
        databaseFactoryBuilder: () => KitchenSpoolDatabaseFactory(
          documentsDirectoryProvider: () async => directory,
        ),
        keyStore: InMemorySecureKeyStore(),
        renderer: renderer,
        webOrderPrintRepository: repository,
        canPrintWebOrder: () => true,
        targetRunAllowed: (_) async => true,
        webOrderDestinationResolver: (_) async => ResolvedKitchenDestination(
          destination: const NetworkKitchenDestination(
            host: '127.0.0.1',
            port: 9100,
          ),
          fingerprint: sha256
              .convert(utf8.encode('network|127.0.0.1|9100'))
              .toString(),
          displayLabel: 'Fake printer transport',
          transportKind: 'network',
          paperWidth: '80mm',
        ),
        localJobIdGenerator: () => 'qa-attempt-${++nextId}',
        networkSend: ({required host, required port, required bytes}) async {
          sends.add(bytes);
          return const pp.KitchenTransportOutcome(
            pp.KitchenTransportOutcomeKind.accepted,
            'fake_transport_only',
          );
        },
        bluetoothSend: ({required address, required bytes}) async =>
            throw StateError('Bluetooth forbidden in offline test'),
        sendGate: pp.PrinterDestinationSendGate(),
      );
      addTearDown(() async {
        await runtime.dispose();
        device.dispose();
        await directory.delete(recursive: true);
      });
      final pending = runtime.onAcceptedWebOrder('qa-one', 'order-qa-one');
      await Future.any<void>([
        raster.entered.future,
        pending.then<void>(
          (outcome) => throw StateError('Rendering not reached: $outcome'),
        ),
      ]);
      device
          .read(localeControllerProvider.notifier)
          .setLocale(const Locale('he'));
      raster.release.complete();
      expect(await pending, WebOrderPrintOutcome.sent);
      final expected = pp.FakeReceiptRasterizer();
      await _manualRenderer(
        'ar',
        expected,
      ).renderToBytes(_document(KitchenSpoolDispatchType.initialOrder));
      expect(raster.requests.single.lines, expected.requests.single.lines);
      expect((repository.begins, repository.finishes, sends.length), (1, 1, 1));
      expect(
        await runtime.onAcceptedWebOrder('qa-one', 'order-qa-one'),
        WebOrderPrintOutcome.sent,
      );
      expect(
        (repository.begins, sends.length),
        (1, 1),
        reason: 'Locale switch cannot authorize a replay',
      );
      expect(
        await runtime.onAcceptedWebOrder('qa-two', 'order-qa-two'),
        WebOrderPrintOutcome.sent,
      );
      expect((repository.begins, repository.finishes, sends.length), (2, 2, 2));
      final expectedHebrew = pp.FakeReceiptRasterizer();
      await _manualRenderer(
        'he',
        expectedHebrew,
      ).renderToBytes(_document(KitchenSpoolDispatchType.initialOrder));
      expect(raster.requests.last.lines, expectedHebrew.requests.single.lines);
      current = false;
      expect(
        await runtime.onAcceptedWebOrder('qa-invalid', 'order-qa-invalid'),
        WebOrderPrintOutcome.failed,
      );
      expect(
        (repository.begins, repository.finishes, sends.length),
        (2, 2, 2),
        reason: 'Invalid renderer cannot reach begin or transport',
      );
      expect(
        transport.calls,
        everyElement('acknowledge_kitchen_print_dispatch'),
      );
    },
  );
}
