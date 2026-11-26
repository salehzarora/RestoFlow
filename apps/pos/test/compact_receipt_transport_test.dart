@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show kitchenTicketPrintLabelsForLanguageCode;
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/print/native_print_bridges.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/print/receipt_logo_asset.dart';
import 'package:restoflow_pos/src/state/pos_compact_receipt.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

const _address = '66:32:1E:0A:BB:CD';
typedef _Write = ({Uint8List bytes, int chunk, Duration pause, Duration drain});

class _BluetoothApi extends Fake implements BluetoothPrintApi {
  final writes = <_Write>[];
  BluetoothJobResult? outcome;

  @override
  Future<bool> permissionsGranted() async => true;

  @override
  Future<BluetoothJobResult> printBytes({
    required String address,
    required Uint8List bytes,
    required Duration timeout,
    int chunkBytes = kBluetoothChunkBytes,
    Duration chunkDelay = kBluetoothChunkDelay,
    Duration drainDelay = kBluetoothDrainDelay,
  }) async {
    writes.add((
      bytes: bytes,
      chunk: chunkBytes,
      pause: chunkDelay,
      drain: drainDelay,
    ));
    return outcome ??
        BluetoothJobResult(
          code: BluetoothJobCode.ok,
          bytesSent: bytes.length,
          chunks: (bytes.length + chunkBytes - 1) ~/ chunkBytes,
        );
  }
}

class _FailsOnce implements pp.ReceiptRasterizer {
  final delegate = pp.FakeReceiptRasterizer();
  var calls = 0;

  @override
  Future<pp.ReceiptRasterImage> rasterize(pp.ReceiptRasterRequest request) {
    if (++calls == 1) throw StateError('render unavailable');
    return delegate.rasterize(request);
  }
}

ProviderContainer _container(_BluetoothApi api, pp.ReceiptRasterizer renderer) {
  final scope = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      bluetoothPrinterConnectorProvider.overrideWithValue(
        ChannelBluetoothConnector(api: api),
      ),
      nativePrintRasterizerProvider.overrideWithValue(renderer),
    ],
  );
  addTearDown(scope.dispose);
  return scope;
}

Future<void> _enable(ProviderContainer scope, String key) async {
  final pref = posCompactReceiptProvider(key);
  await scope.read(pref.future);
  expect(await scope.read(pref.notifier).setEnabled(true), isTrue);
}

NativeTransportPrintBridge _direct(
  _BluetoothApi api,
  pp.ReceiptRasterizer renderer, {
  bool compact = true,
  pp.MediaProfile media = pp.MediaProfile.continuous80,
}) => NativeTransportPrintBridge(
  transportFactory: () => BluetoothClassicPrintTransport(
    connector: ChannelBluetoothConnector(api: api),
    address: _address,
  ),
  rasterizer: renderer,
  compactReceipt: compact,
  mediaProfile: media,
);

PrintDocument _receipt(String name, {ReceiptLogoAsset? logo}) => PrintDocument(
  title: name,
  lines: [if (logo != null) PrintLine.headerImage(logo), PrintLine.title(name)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'opted-in first and warm receipts each make one complete native write; drawer keeps its own pacing',
    () async {
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.selected.pos.local': 'bluetooth',
        'restoflow.printer.bluetooth.pos.local': jsonEncode({
          'address': _address,
          'name': 'Counter',
        }),
      });
      final key = pp.PrinterDestinationSendGate.bluetoothKey(_address);
      final api = _BluetoothApi();
      final renderer = pp.FakeReceiptRasterizer();
      await _enable(_container(api, renderer), key);
      final cold = _container(api, renderer);
      final first =
          (await cold.read(posActivePrintBridgeReadyProvider.future))!
              as NativeTransportPrintBridge;
      final doc = _receipt('All ASCII');
      expect(
        (await first.submit(doc)).outcome,
        pp.BridgeSubmitOutcome.sentToPrinter,
      );
      expect(
        (await cold.read(posActivePrintBridgeProvider)!.submit(doc)).outcome,
        pp.BridgeSubmitOutcome.sentToPrinter,
      );
      expect(renderer.requests, hasLength(2));
      expect(renderer.requests.first.lines, contains(contains('All ASCII')));
      expect(api.writes, hasLength(2));
      for (final w in api.writes) {
        expect(w.chunk, w.bytes.length);
        expect(w.pause, Duration.zero);
        expect(w.drain, kBluetoothDrainDelay);
      }
      expect(api.writes.first.bytes, api.writes.last.bytes);
      expect((await first.submitDrawerKick())!.ok, isTrue);
      expect(api.writes, hasLength(3));
      final kick = api.writes.last;
      expect(
        kick.bytes,
        const pp.EscPosPrintAdapter().encode(
          const pp.PrintDocument([pp.PrintDrawerKickLine()]),
          pp.PrinterProfile.escPos80mm,
        ),
      );
      expect(kick.chunk, kBluetoothChunkBytes);
      expect(kick.pause, kBluetoothChunkDelay);
      expect(renderer.requests, hasLength(2));
    },
  );

  test(
    'the Orders kitchen reprint sends the entire money-free ticket to its saved printer',
    () async {
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.selected.pos.kitchen_ticket.local': 'bluetooth',
        'restoflow.printer.bluetooth.pos.kitchen_ticket.local': jsonEncode({
          'address': _address,
        }),
      });
      final api = _BluetoothApi();
      final raster = pp.FakeReceiptRasterizer();
      final scope = _container(api, raster);
      final key = pp.PrinterDestinationSendGate.bluetoothKey(_address);
      final reprint = scope.read(posKitchenReprintProvider);
      final order = SubmittedOrderView(
        orderNumber: '#QA-40',
        orderType: OrderType.takeaway,
        currencyCode: 'ILS',
        subtotalMinor: 493600,
        lines: [
          for (var i = 1; i <= 40; i++)
            SubmittedLineView(
              name: 'برجر $i',
              quantity: 1,
              lineTotalMinor: 12340,
              currencyCode: 'ILS',
              modifiers: const ['جبنة'],
              note: 'ללא בצל',
            ),
        ],
      );
      final labels = kitchenTicketPrintLabelsForLanguageCode('ar');
      expect(
        await reprint(container: scope, order: order, labels: labels),
        PosKitchenPrintOutcome.printed,
      );
      final fast = api.writes.single;
      expect(fast.chunk, fast.bytes.length);
      expect(fast.pause, Duration.zero);
      final lines = raster.requests.single.lines;
      expect(lines, contains(contains('برجر 40')));
      expect(lines, contains(contains('ללא בצל')));
      expect(lines, contains(contains('جبنة')));
      expect(
        lines.join(' '),
        isNot(matches(RegExp(r'123[.,]40|4936[.,]00|BIZBOT'))),
      );

      expect(
        await scope
            .read(posCompactReceiptProvider(key).notifier)
            .setEnabled(false),
        isTrue,
      );
      expect(
        await reprint(container: scope, order: order, labels: labels),
        PosKitchenPrintOutcome.printed,
      );
      expect(api.writes, hasLength(2));
      expect(api.writes.last.chunk, kBluetoothChunkBytes);
      expect(api.writes.last.pause, kBluetoothChunkDelay);
      expect(raster.requests.last.lines, lines);
    },
  );

  test(
    'short ack, extra chunks and write failure are reported once after dispatch',
    () async {
      for (final outcome in const [
        BluetoothJobResult(code: BluetoothJobCode.ok, chunks: 1, bytesSent: 10),
        BluetoothJobResult(code: BluetoothJobCode.ok, chunks: 2),
        BluetoothJobResult(code: BluetoothJobCode.writeFailed, bytesSent: 8),
      ]) {
        final api = _BluetoothApi()..outcome = outcome;
        final result = await _direct(
          api,
          pp.FakeReceiptRasterizer(),
        ).submit(_receipt('Item'));
        expect(api.writes, hasLength(1));
        expect(result.isPartialOrUnknownAfterDispatch, isTrue);
        expect(
          result.bytesSent,
          outcome.bytesSent == 0 ? isNull : outcome.bytesSent,
        );
      }
    },
  );

  test(
    'a render failure before dispatch preserves original logo, content, and regular pacing',
    () async {
      final api = _BluetoothApi();
      final renderer = _FailsOnce();
      final doc = _receipt(
        'برجر',
        logo: ReceiptLogoAsset(
          sourceBytes: Uint8List(0),
          sourceMime: 'image/png',
          raster: pp.LogoRaster(
            widthDots: 576,
            widthBytes: 72,
            heightDots: 1,
            data: Uint8List(72)..[36] = 0xa5,
          ),
        ),
      );
      expect((await _direct(api, renderer).submit(doc)).ok, isTrue);
      final actual = api.writes.single;
      final legacy = _BluetoothApi();
      expect(
        (await _direct(
          legacy,
          pp.FakeReceiptRasterizer(),
          compact: false,
        ).submit(doc)).ok,
        isTrue,
      );
      expect(renderer.calls, 2);
      expect(actual.bytes, legacy.writes.single.bytes);
      expect(actual.chunk, kBluetoothChunkBytes);
      expect(actual.pause, kBluetoothChunkDelay);
    },
  );

  test(
    'fixed media ignore a previously enabled continuous-roll mode',
    () async {
      for (final media in [
        pp.MediaProfile.label50x50,
        pp.MediaProfile.label80x80,
      ]) {
        final enabled = _BluetoothApi();
        final legacy = _BluetoothApi();
        final doc = _receipt('מוצר');
        expect(
          (await _direct(
            enabled,
            pp.FakeReceiptRasterizer(),
            media: media,
          ).submit(doc)).ok,
          isTrue,
        );
        expect(
          (await _direct(
            legacy,
            pp.FakeReceiptRasterizer(),
            compact: false,
            media: media,
          ).submit(doc)).ok,
          isTrue,
        );
        expect(enabled.writes.single.bytes, legacy.writes.single.bytes);
        expect(enabled.writes.single.chunk, kBluetoothChunkBytes);
        expect(enabled.writes.single.pause, kBluetoothChunkDelay);
      }
    },
  );

  test(
    'saved network choice sends the same complete packet on one TCP connection',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final host = server.address.address;
      final port = server.port;
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.selected.pos.local': 'network',
        'restoflow.printer.network.pos.local': jsonEncode({
          'host': host,
          'port': port,
        }),
      });
      final key = pp.PrinterDestinationSendGate.networkKey(host, port);
      final api = _BluetoothApi();
      final renderer = pp.FakeReceiptRasterizer();
      await _enable(_container(api, renderer), key);
      final cold = _container(api, renderer);
      final bridge = await cold.read(posActivePrintBridgeReadyProvider.future);
      final doc = _receipt('Item');
      final stream = server.first.then((socket) async {
        try {
          return (await socket.fold(
            BytesBuilder(),
            (buffer, bytes) => buffer..add(bytes),
          )).takeBytes();
        } finally {
          socket.destroy();
        }
      });
      expect(
        (await bridge!.submit(doc)).outcome,
        pp.BridgeSubmitOutcome.sentToPrinter,
      );
      final bytes = await stream;
      final expected = pp.InMemoryPrintTransport();
      await NativeTransportPrintBridge(
        transportFactory: () => expected,
        compactReceipt: true,
        rasterizer: pp.FakeReceiptRasterizer(),
      ).submit(doc);
      expect(bytes, expected.batches.single);
      expect(api.writes, isEmpty);
    },
  );
}
