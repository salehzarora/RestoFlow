import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
// The channel impl lives behind the conditional import (native-only file), so
// this VM test imports it directly to pin the wire protocol.
import 'package:restoflow_native_printing/src/bluetooth_connector_native.dart'
    show MethodChannelBluetoothPrintApi;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// PRINT-BLUETOOTH-RECOVERY-001: the reliability + honest-mapping contract of
/// the in-house channel-backed Bluetooth connector. Plugin-free: a fake
/// [BluetoothPrintApi] observes exactly what the connector asks the native
/// layer to do — no device, no platform channel. Money-free throughout.
class _FakeApi implements BluetoothPrintApi {
  _FakeApi({
    this.granted = true,
    this.requestOutcome = true,
    List<BluetoothJobResult>? jobs,
    this.paired = const BluetoothPairedNative.ok([]),
  }) : jobs = jobs ?? [const BluetoothJobResult(code: BluetoothJobCode.ok)];

  bool granted;
  bool requestOutcome;
  bool enabled = true;
  BluetoothPairedNative paired;

  /// Job results returned in order (the last one repeats).
  final List<BluetoothJobResult> jobs;

  int grantedChecks = 0;
  int requests = 0;
  final List<
    ({
      String address,
      Uint8List bytes,
      Duration timeout,
      int chunkBytes,
      Duration chunkDelay,
      Duration drainDelay,
    })
  >
  printCalls = [];

  /// When set, printBytes never completes (tests the outer never-hang backstop).
  bool hang = false;

  @override
  Future<bool> permissionsGranted() async {
    grantedChecks++;
    return granted;
  }

  @override
  Future<bool> requestPermissions() async {
    requests++;
    if (requestOutcome) granted = true;
    return requestOutcome;
  }

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<BluetoothPairedNative> pairedDevices() async => paired;

  @override
  Future<BluetoothJobResult> printBytes({
    required String address,
    required Uint8List bytes,
    required Duration timeout,
    int chunkBytes = kBluetoothChunkBytes,
    Duration chunkDelay = kBluetoothChunkDelay,
    Duration drainDelay = kBluetoothDrainDelay,
  }) async {
    printCalls.add((
      address: address,
      bytes: bytes,
      timeout: timeout,
      chunkBytes: chunkBytes,
      chunkDelay: chunkDelay,
      drainDelay: drainDelay,
    ));
    if (hang) return Completer<BluetoothJobResult>().future; // never completes
    final index = printCalls.length - 1;
    return jobs[index < jobs.length ? index : jobs.length - 1];
  }
}

ChannelBluetoothConnector _connector(
  _FakeApi api, {
  Duration outerMargin = const Duration(seconds: 30),
}) => ChannelBluetoothConnector(api: api, outerTimeoutMargin: outerMargin);

Uint8List _bytes([int length = 1200]) =>
    Uint8List.fromList(List.generate(length, (i) => i % 251));

void main() {
  group('permissions', () {
    test('granted -> no request dialog, job runs', () async {
      final api = _FakeApi(granted: true);
      final result = await _connector(api).send(address: 'AA', bytes: _bytes());
      expect(result.ok, isTrue);
      expect(api.requests, 0);
      expect(api.printCalls, hasLength(1));
    });

    test('not granted -> ONE request; granted after it -> job runs', () async {
      final api = _FakeApi(granted: false, requestOutcome: true);
      final result = await _connector(api).send(address: 'AA', bytes: _bytes());
      expect(result.ok, isTrue);
      expect(api.requests, 1);
    });

    test('denied -> permissionDenied, NO job, NO retry', () async {
      final api = _FakeApi(granted: false, requestOutcome: false);
      final result = await _connector(api).send(address: 'AA', bytes: _bytes());
      expect(result.ok, isFalse);
      expect(result.category, pp.PrinterErrorCategory.permissionDenied);
      expect(api.printCalls, isEmpty);
    });
  });

  group('retry-once policy', () {
    test(
      'connect failure retries EXACTLY once, then maps to unreachable',
      () async {
        final api = _FakeApi(
          jobs: const [
            BluetoothJobResult(
              code: BluetoothJobCode.connectFailed,
              detail: 'x',
            ),
            BluetoothJobResult(
              code: BluetoothJobCode.connectFailed,
              detail: 'y',
            ),
          ],
        );
        final result = await _connector(
          api,
        ).send(address: 'AA', bytes: _bytes());
        expect(api.printCalls, hasLength(2));
        expect(result.ok, isFalse);
        expect(result.category, pp.PrinterErrorCategory.unreachable);
        expect(result.message, 'y');
      },
    );

    test('first fails, retry succeeds -> success', () async {
      final api = _FakeApi(
        jobs: const [
          BluetoothJobResult(code: BluetoothJobCode.writeFailed),
          BluetoothJobResult(code: BluetoothJobCode.ok),
        ],
      );
      final result = await _connector(api).send(address: 'AA', bytes: _bytes());
      expect(api.printCalls, hasLength(2));
      expect(result.ok, isTrue);
    });

    test('bluetoothOff / notBonded fail FAST — no pointless retry', () async {
      for (final (code, category) in [
        (BluetoothJobCode.bluetoothOff, pp.PrinterErrorCategory.bluetoothOff),
        (BluetoothJobCode.notBonded, pp.PrinterErrorCategory.notPaired),
      ]) {
        final api = _FakeApi(jobs: [BluetoothJobResult(code: code)]);
        final result = await _connector(
          api,
        ).send(address: 'AA', bytes: _bytes());
        expect(api.printCalls, hasLength(1), reason: '$code');
        expect(result.category, category, reason: '$code');
      }
    });
  });

  group('honest category mapping', () {
    test('every native code maps to its distinct category', () async {
      const cases = {
        BluetoothJobCode.permission: pp.PrinterErrorCategory.permissionDenied,
        BluetoothJobCode.bluetoothOff: pp.PrinterErrorCategory.bluetoothOff,
        BluetoothJobCode.notBonded: pp.PrinterErrorCategory.notPaired,
        BluetoothJobCode.connectFailed: pp.PrinterErrorCategory.unreachable,
        BluetoothJobCode.timeout: pp.PrinterErrorCategory.unreachable,
        BluetoothJobCode.writeFailed: pp.PrinterErrorCategory.writeFailed,
        BluetoothJobCode.unsupported: pp.PrinterErrorCategory.unsupported,
        BluetoothJobCode.unknown: pp.PrinterErrorCategory.unknown,
      };
      for (final entry in cases.entries) {
        final api = _FakeApi(
          jobs: [BluetoothJobResult(code: entry.key, detail: 'd')],
        );
        final result = await _connector(
          api,
        ).send(address: 'AA', bytes: _bytes());
        expect(result.ok, isFalse, reason: '${entry.key}');
        expect(result.category, entry.value, reason: '${entry.key}');
      }
    });
  });

  group('wire fidelity', () {
    test(
      'bytes reach the native job UNMODIFIED with the tuned chunk/drain '
      'parameters (the old plugin injected a rogue newline per chunk)',
      () async {
        final api = _FakeApi();
        final payload = _bytes(3000);
        await _connector(api).send(
          address: '66:02:BD:06:18:7B',
          bytes: payload,
          timeout: const Duration(seconds: 10),
        );
        final call = api.printCalls.single;
        expect(call.address, '66:02:BD:06:18:7B');
        expect(call.bytes, same(payload)); // EXACT bytes — no copy, no framing
        expect(call.timeout, const Duration(seconds: 10));
        expect(call.chunkBytes, kBluetoothChunkBytes);
        expect(call.chunkDelay, kBluetoothChunkDelay);
        expect(call.drainDelay, kBluetoothDrainDelay);
      },
    );

    test('the default transport timeout is the Bluetooth budget (10s), not '
        'the 5s Wi-Fi budget', () async {
      final api = _FakeApi();
      final transport = BluetoothClassicPrintTransport(
        connector: _connector(api),
        address: 'AA',
      );
      await transport.send(_bytes());
      expect(api.printCalls.single.timeout, kBluetoothPrintTimeout);
      expect(kBluetoothPrintTimeout, const Duration(seconds: 10));
    });
  });

  group('never hangs', () {
    test('a native job that never answers is bounded by the outer backstop '
        'and maps to unreachable', () async {
      final api = _FakeApi()..hang = true;
      final result = await _connector(api, outerMargin: Duration.zero).send(
        address: 'AA',
        bytes: _bytes(),
        timeout: const Duration(milliseconds: 50),
      );
      expect(result.ok, isFalse);
      expect(result.category, pp.PrinterErrorCategory.unreachable);
      expect(result.message, contains('no response'));
    });
  });

  group('paired devices', () {
    test('permission denied -> typed permissionDenied error', () async {
      final api = _FakeApi(granted: false, requestOutcome: false);
      final result = await _connector(api).pairedDevices();
      expect(result.ok, isFalse);
      expect(result.error, BluetoothPrinterError.permissionDenied);
    });

    test('native bluetoothOff -> typed bluetoothOff error', () async {
      final api = _FakeApi(
        paired: const BluetoothPairedNative.failed(
          BluetoothJobCode.bluetoothOff,
        ),
      );
      final result = await _connector(api).pairedDevices();
      expect(result.error, BluetoothPrinterError.bluetoothOff);
    });

    test('devices whose class says IMAGING (printer) sort first; nothing is '
        'hidden (a keyboard stays listed, after the printers)', () async {
      final api = _FakeApi(
        paired: const BluetoothPairedNative.ok([
          BluetoothDeviceInfo(
            address: '11',
            name: 'A1916 Keyboard',
            majorClass: 0x0500, // peripheral
          ),
          BluetoothDeviceInfo(
            address: '22',
            name: 'Printer001',
            majorClass: kBluetoothImagingMajorClass,
          ),
          BluetoothDeviceInfo(address: '33', name: 'NFXSL'), // unknown class
          BluetoothDeviceInfo(
            address: '44',
            name: 'HMS 51 04',
            majorClass: kBluetoothImagingMajorClass,
          ),
        ]),
      );
      final result = await _connector(api).pairedDevices();
      expect(result.ok, isTrue);
      expect(result.devices.map((d) => d.name).toList(), [
        'HMS 51 04', // imaging first (by name)
        'Printer001',
        'A1916 Keyboard', // everything else after (by name) — never hidden
        'NFXSL',
      ]);
    });
  });

  group('MethodChannelBluetoothPrintApi (wire protocol)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('restoflow.native_printing/bluetooth');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'printBytes sends the exact argument map and decodes the result',
      () async {
        late MethodCall seen;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              seen = call;
              return <String, Object>{
                'ok': false,
                'code': 'writeFailed',
                'detail': 'write failed after 512/1200 bytes',
                'bytesSent': 512,
                'chunks': 1,
              };
            });
        const api = MethodChannelBluetoothPrintApi();
        final result = await api.printBytes(
          address: '66:02:BD:06:18:7B',
          bytes: _bytes(),
          timeout: const Duration(seconds: 10),
        );
        expect(seen.method, 'printBytes');
        final args = seen.arguments as Map<Object?, Object?>;
        expect(args['address'], '66:02:BD:06:18:7B');
        expect(args['bytes'], isA<Uint8List>());
        expect(args['bytes'] as Uint8List, _bytes());
        expect(args['timeoutMs'], 10000);
        expect(args['chunkBytes'], kBluetoothChunkBytes);
        expect(args['chunkDelayMs'], kBluetoothChunkDelay.inMilliseconds);
        expect(args['drainMs'], kBluetoothDrainDelay.inMilliseconds);
        expect(result.code, BluetoothJobCode.writeFailed);
        expect(result.detail, contains('512/1200'));
        expect(result.bytesSent, 512);
        expect(result.chunks, 1);
      },
    );

    test('a host app WITHOUT the channel fails honestly as unsupported '
        '(never a fake success, never a hang)', () async {
      // No mock handler registered -> MissingPluginException.
      const api = MethodChannelBluetoothPrintApi();
      final job = await api.printBytes(
        address: 'AA',
        bytes: _bytes(),
        timeout: const Duration(seconds: 1),
      );
      expect(job.code, BluetoothJobCode.unsupported);
      expect(job.detail, contains('not registered'));
      final paired = await api.pairedDevices();
      expect(paired.ok, isFalse);
      expect(paired.code, BluetoothJobCode.unsupported);
      expect(await api.permissionsGranted(), isFalse);
      expect(await api.isEnabled(), isFalse);
    });

    test('pairedDevices decodes devices incl. the majorClass hint '
        '(-1 wire value -> null)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'pairedDevices');
            return <String, Object>{
              'ok': true,
              'code': 'ok',
              'devices': [
                {'name': 'Printer1', 'address': 'AA:BB', 'majorClass': 1536},
                {'name': '', 'address': 'CC:DD', 'majorClass': -1},
              ],
            };
          });
      const api = MethodChannelBluetoothPrintApi();
      final result = await api.pairedDevices();
      expect(result.ok, isTrue);
      expect(result.devices, hasLength(2));
      expect(result.devices.first.name, 'Printer1');
      expect(result.devices.first.majorClass, 1536);
      expect(result.devices.first.looksLikePrinter, isTrue);
      expect(result.devices.last.majorClass, isNull);
      expect(result.devices.last.looksLikePrinter, isFalse);
    });

    test(
      'typed failure codes come through (permission / bluetoothOff)',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              return <String, Object>{
                'ok': false,
                'code': 'permission',
                'devices': const <Object>[],
              };
            });
        const api = MethodChannelBluetoothPrintApi();
        final result = await api.pairedDevices();
        expect(result.ok, isFalse);
        expect(result.code, BluetoothJobCode.permission);
      },
    );
  });
}
