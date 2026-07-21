import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/print/native_print_bridges.dart';
import 'package:restoflow_pos/src/print/print_document.dart' as app;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-MODE-001C2C (LOCKED DECISION 3) — the POS RECEIPT bridge now
/// serializes its physical send through the shared per-destination gate, so
/// a future kitchen sender on the SAME physical printer can never interleave
/// bytes with a receipt. Receipt content/encoding/retry semantics are
/// unchanged — the gate wraps ONLY the transport operation.
class _GatedFakeTransport implements pp.PrintTransport {
  _GatedFakeTransport(this.onSend);

  final Future<pp.PrintResult> Function() onSend;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) => onSend();

  @override
  Future<void> dispose() async {}
}

app.PrintDocument _doc(String title) =>
    app.PrintDocument(title: title, lines: const []);

void main() {
  test('two receipt submits to the SAME destination serialize FIFO through '
      'the shared gate', () async {
    final gate = pp.PrinterDestinationSendGate();
    final key = pp.PrinterDestinationSendGate.networkKey('10.0.0.5', 9100);
    final firstEntered = Completer<void>();
    final release = Completer<void>();
    final order = <String>[];

    NativeTransportPrintBridge bridge(String label, Completer<void>? hold) =>
        NativeTransportPrintBridge(
          sendGate: gate,
          destinationKey: key,
          transportFactory: () => _GatedFakeTransport(() async {
            order.add('$label:start');
            if (hold != null) {
              if (!firstEntered.isCompleted) firstEntered.complete();
              await hold.future;
            }
            order.add('$label:end');
            return const pp.PrintResult.success();
          }),
        );

    final first = bridge('first', release).submit(_doc('R1'));
    await firstEntered.future;
    final second = bridge('second', null).submit(_doc('R2'));
    await Future<void>.delayed(Duration.zero);
    expect(order, ['first:start'], reason: 'the second send must wait');
    release.complete();
    expect((await first).outcome, pp.BridgeSubmitOutcome.sentToPrinter);
    expect((await second).outcome, pp.BridgeSubmitOutcome.sentToPrinter);
    expect(order, ['first:start', 'first:end', 'second:start', 'second:end']);
  });

  test('DIFFERENT destinations do not serialize against each other', () async {
    final gate = pp.PrinterDestinationSendGate();
    final release = Completer<void>();
    final entered = Completer<void>();

    final blocked = NativeTransportPrintBridge(
      sendGate: gate,
      destinationKey: pp.PrinterDestinationSendGate.networkKey('a', 9100),
      transportFactory: () => _GatedFakeTransport(() async {
        entered.complete();
        await release.future;
        return const pp.PrintResult.success();
      }),
    ).submit(_doc('A'));
    await entered.future;

    final other = await NativeTransportPrintBridge(
      sendGate: gate,
      destinationKey: pp.PrinterDestinationSendGate.networkKey('b', 9100),
      transportFactory: () =>
          _GatedFakeTransport(() async => const pp.PrintResult.success()),
    ).submit(_doc('B'));
    expect(other.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
    release.complete();
    await blocked;
  });

  test(
    'a failing gated send releases the destination for the next receipt',
    () async {
      final gate = pp.PrinterDestinationSendGate();
      final key = pp.PrinterDestinationSendGate.bluetoothKey(
        'DC:0D:30:AA:BB:CC',
      );

      final failed = await NativeTransportPrintBridge(
        sendGate: gate,
        destinationKey: key,
        transportFactory: () => _GatedFakeTransport(
          () async => const pp.PrintResult.failure(
            pp.PrinterErrorCategory.unreachable,
            'off',
          ),
        ),
      ).submit(_doc('R1'));
      expect(failed.outcome, pp.BridgeSubmitOutcome.failed);

      final next = await NativeTransportPrintBridge(
        sendGate: gate,
        destinationKey: key,
        transportFactory: () =>
            _GatedFakeTransport(() async => const pp.PrintResult.success()),
      ).submit(_doc('R2'));
      expect(next.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
    },
  );

  test('a bridge WITHOUT a gate behaves exactly as before', () async {
    final result = await NativeTransportPrintBridge(
      transportFactory: () =>
          _GatedFakeTransport(() async => const pp.PrintResult.success()),
    ).submit(_doc('R'));
    expect(result.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
  });
}
