import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show KitchenTransportOutcomeKind;

/// KITCHEN-MODE-001C2C — the single-attempt kitchen Bluetooth seam: exactly
/// ONE native dispatch, zero automatic resend, byte-count evidence drives
/// the classification (partial/lost results are NEVER retryable).
class _ScriptedApi implements BluetoothPrintApi {
  _ScriptedApi(this._results);

  final List<Future<BluetoothJobResult> Function()> _results;
  int printCalls = 0;
  int? lastChunkSize;
  Duration? lastChunkDelay;

  @override
  Future<bool> permissionsGranted() async => true;

  @override
  Future<bool> requestPermissions() async =>
      throw StateError('the kitchen seam must NEVER prompt for permissions');

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<BluetoothPairedNative> pairedDevices() async =>
      const BluetoothPairedNative.ok([]);

  @override
  Future<BluetoothJobResult> printBytes({
    required String address,
    required Uint8List bytes,
    required Duration timeout,
    int chunkBytes = kBluetoothChunkBytes,
    Duration chunkDelay = kBluetoothChunkDelay,
    Duration drainDelay = kBluetoothDrainDelay,
  }) {
    printCalls++;
    lastChunkSize = chunkBytes;
    lastChunkDelay = chunkDelay;
    return _results.removeAt(0)();
  }
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  Future<(KitchenBluetoothSendAttempt, _ScriptedApi)> attemptFor(
    BluetoothJobResult result,
  ) async {
    final api = _ScriptedApi([() async => result]);
    final connector = ChannelBluetoothConnector(api: api);
    final attempt = await connector.sendOnceForKitchen(
      address: 'DC:0D:30:AA:BB:CC',
      bytes: bytes,
    );
    return (attempt, api);
  }

  group('classification matrix (native evidence drives safety)', () {
    Future<void> expectKind(
      BluetoothJobResult result,
      KitchenTransportOutcomeKind kind,
      String reason,
    ) async {
      final (attempt, api) = await attemptFor(result);
      expect(attempt.nativeResponded, isTrue);
      final outcome = classifyKitchenBluetoothAttempt(attempt);
      expect(outcome.kind, kind, reason: '${result.code.name}: $reason');
      expect(outcome.reasonCode, reason);
      expect(api.printCalls, 1, reason: 'exactly one native call');
    }

    test('permission denied -> unavailable (temporary)', () async {
      await expectKind(
        const BluetoothJobResult(code: BluetoothJobCode.permission),
        KitchenTransportOutcomeKind.unavailable,
        'bluetooth_permission',
      );
    });

    test('bluetooth off -> unavailable (temporary)', () async {
      await expectKind(
        const BluetoothJobResult(code: BluetoothJobCode.bluetoothOff),
        KitchenTransportOutcomeKind.unavailable,
        'bluetooth_off',
      );
    });

    test('not bonded -> unsupported (permanent)', () async {
      await expectKind(
        const BluetoothJobResult(code: BluetoothJobCode.notBonded),
        KitchenTransportOutcomeKind.unsupported,
        'not_bonded',
      );
    });

    test('channel missing -> unsupported (permanent)', () async {
      await expectKind(
        const BluetoothJobResult(code: BluetoothJobCode.unsupported),
        KitchenTransportOutcomeKind.unsupported,
        'channel_missing',
      );
    });

    test('connect failed with ZERO bytes -> definitelyNotSent', () async {
      await expectKind(
        const BluetoothJobResult(code: BluetoothJobCode.connectFailed),
        KitchenTransportOutcomeKind.definitelyNotSent,
        'connect_failed',
      );
    });

    test(
      'native connect timeout with ZERO bytes -> timeoutBeforeWrite',
      () async {
        await expectKind(
          const BluetoothJobResult(code: BluetoothJobCode.timeout),
          KitchenTransportOutcomeKind.timeoutBeforeWrite,
          'native_connect_timeout',
        );
      },
    );

    test('write failed with ZERO bytes -> definitelyNotSent', () async {
      await expectKind(
        const BluetoothJobResult(code: BluetoothJobCode.writeFailed),
        KitchenTransportOutcomeKind.definitelyNotSent,
        'write_failed_zero_bytes',
      );
    });

    test(
      'write failed with PARTIAL bytes -> ambiguous (NEVER resent)',
      () async {
        final (attempt, api) = await attemptFor(
          const BluetoothJobResult(
            code: BluetoothJobCode.writeFailed,
            bytesSent: 128,
            chunks: 1,
            detail: 'write failed after 128/512 bytes',
          ),
        );
        final outcome = classifyKitchenBluetoothAttempt(attempt);
        expect(outcome.kind, KitchenTransportOutcomeKind.ambiguous);
        expect(outcome.reasonCode, 'partial_write');
        expect(outcome.isSafeToRetry, isFalse);
        expect(
          api.printCalls,
          1,
          reason: 'zero automatic full resend after a partial write',
        );
      },
    );

    test('native success (all chunks + drain) -> accepted', () async {
      await expectKind(
        const BluetoothJobResult(
          code: BluetoothJobCode.ok,
          bytesSent: 3,
          chunks: 1,
        ),
        KitchenTransportOutcomeKind.accepted,
        'native_flushed_drained',
      );
    });

    test(
      'unknown native failure -> ambiguous (no catch-all retryable)',
      () async {
        await expectKind(
          const BluetoothJobResult(code: BluetoothJobCode.unknown),
          KitchenTransportOutcomeKind.ambiguous,
          'native_unknown',
        );
      },
    );

    test('native timeout with bytes counted -> ambiguous', () async {
      final (attempt, _) = await attemptFor(
        const BluetoothJobResult(
          code: BluetoothJobCode.timeout,
          bytesSent: 512,
        ),
      );
      final outcome = classifyKitchenBluetoothAttempt(attempt);
      expect(outcome.kind, KitchenTransportOutcomeKind.ambiguous);
      expect(outcome.reasonCode, 'native_timeout_after_write');
    });
  });

  group('compact kitchen packet', () {
    for (final sample in [
      (
        const BluetoothJobResult(
          code: BluetoothJobCode.ok,
          bytesSent: 3,
          chunks: 1,
        ),
        KitchenTransportOutcomeKind.accepted,
      ),
      (
        const BluetoothJobResult(
          code: BluetoothJobCode.ok,
          bytesSent: 2,
          chunks: 1,
        ),
        KitchenTransportOutcomeKind.ambiguous,
      ),
      (
        const BluetoothJobResult(
          code: BluetoothJobCode.ok,
          bytesSent: 3,
          chunks: 2,
        ),
        KitchenTransportOutcomeKind.ambiguous,
      ),
      (
        const BluetoothJobResult(code: BluetoothJobCode.writeFailed),
        KitchenTransportOutcomeKind.ambiguous,
      ),
      (
        const BluetoothJobResult(code: BluetoothJobCode.connectFailed),
        KitchenTransportOutcomeKind.definitelyNotSent,
      ),
    ]) {
      final (result, expected) = sample;
      test(
        '${result.code.name} (${result.chunks} writes, ${result.bytesSent} bytes) returns ${expected.name}',
        () async {
          final api = _ScriptedApi([() async => result]);
          final attempt = await ChannelBluetoothConnector(api: api)
              .sendOnceForKitchen(
                address: 'DC:0D:30:AA:BB:CC',
                bytes: bytes,
                wholeJob: true,
              );
          expect(api.printCalls, 1);
          expect(api.lastChunkSize, bytes.length);
          expect(api.lastChunkDelay, Duration.zero);
          final outcome = classifyKitchenBluetoothAttempt(attempt);
          expect(outcome.kind, expected);
          if (expected == KitchenTransportOutcomeKind.ambiguous) {
            expect(outcome.isSafeToRetry, isFalse);
          }
        },
      );
    }
  });

  group('lost platform result', () {
    test('outer backstop timeout after dispatch -> timeoutAfterPossibleWrite, '
        'exactly one call, never resent', () async {
      final api = _ScriptedApi([() => Completer<BluetoothJobResult>().future]);
      final connector = ChannelBluetoothConnector(
        api: api,
        outerTimeoutMargin: const Duration(milliseconds: 40),
      );
      final attempt = await connector.sendOnceForKitchen(
        address: 'DC:0D:30:AA:BB:CC',
        bytes: bytes,
        timeout: const Duration(milliseconds: 10),
      );
      expect(attempt.nativeResponded, isFalse);
      final outcome = classifyKitchenBluetoothAttempt(attempt);
      expect(
        outcome.kind,
        KitchenTransportOutcomeKind.timeoutAfterPossibleWrite,
      );
      expect(outcome.reasonCode, 'channel_result_lost');
      expect(outcome.isSafeToRetry, isFalse);
      expect(api.printCalls, 1);
    });

    test(
      'a THROWING channel call after dispatch is ambiguous, never resent',
      () async {
        final api = _ScriptedApi([() => throw StateError('channel died')]);
        final connector = ChannelBluetoothConnector(api: api);
        final attempt = await connector.sendOnceForKitchen(
          address: 'DC:0D:30:AA:BB:CC',
          bytes: bytes,
        );
        expect(attempt.nativeResponded, isFalse);
        expect(
          classifyKitchenBluetoothAttempt(attempt).kind,
          KitchenTransportOutcomeKind.timeoutAfterPossibleWrite,
        );
        expect(api.printCalls, 1);
      },
    );
  });

  group('privacy', () {
    test('classified outcomes never carry the address, payload, or raw '
        'exception text', () async {
      final (attempt, _) = await attemptFor(
        const BluetoothJobResult(
          code: BluetoothJobCode.writeFailed,
          bytesSent: 64,
          detail: 'DC:0D:30:AA:BB:CC exploded mid-write',
        ),
      );
      final rendered = classifyKitchenBluetoothAttempt(attempt).toString();
      expect(rendered, isNot(contains('DC:0D:30')));
      expect(rendered, isNot(contains('exploded')));
    });
  });
}
