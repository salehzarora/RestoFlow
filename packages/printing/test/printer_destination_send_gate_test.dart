import 'dart:async';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// KITCHEN-MODE-001C2C (LOCKED DECISION 3) — one shared FIFO gate per
/// physical printer destination, spanning receipt AND kitchen senders.
/// Deterministic barriers (Completers) only — no sleeps.
void main() {
  late PrinterDestinationSendGate gate;

  setUp(() => gate = PrinterDestinationSendGate());

  test('two sends to the SAME endpoint serialize FIFO', () async {
    final firstEntered = Completer<void>();
    final release = Completer<void>();
    final order = <String>[];

    final first = gate.withDestination('net|p|9100', () async {
      order.add('first:start');
      firstEntered.complete();
      await release.future;
      order.add('first:end');
      return 1;
    });
    final second = gate.withDestination('net|p|9100', () async {
      order.add('second:start');
      return 2;
    });

    await firstEntered.future;
    // Give the second send every chance to (incorrectly) start.
    await Future<void>.delayed(Duration.zero);
    expect(order, ['first:start'], reason: 'second must wait');
    release.complete();
    expect(await first, 1);
    expect(await second, 2);
    expect(order, ['first:start', 'first:end', 'second:start']);
  });

  test('RECEIPT and KITCHEN sends to the same endpoint share the gate '
      '(both orderings)', () async {
    for (final firstLabel in ['receipt', 'kitchen']) {
      final secondLabel = firstLabel == 'receipt' ? 'kitchen' : 'receipt';
      final entered = Completer<void>();
      final release = Completer<void>();
      final order = <String>[];
      final key = PrinterDestinationSendGate.networkKey('Printer.local', 9100);

      final first = gate.withDestination(key, () async {
        order.add('$firstLabel:start');
        entered.complete();
        await release.future;
        order.add('$firstLabel:end');
      });
      final second = gate.withDestination(key, () async {
        order.add('$secondLabel:start');
      });
      await entered.future;
      await Future<void>.delayed(Duration.zero);
      expect(order, ['$firstLabel:start'], reason: '$secondLabel must wait');
      release.complete();
      await first;
      await second;
      expect(order, [
        '$firstLabel:start',
        '$firstLabel:end',
        '$secondLabel:start',
      ]);
    }
  });

  test('DIFFERENT endpoints proceed concurrently', () async {
    final firstEntered = Completer<void>();
    final release = Completer<void>();

    final blocked = gate.withDestination('net|a|9100', () async {
      firstEntered.complete();
      await release.future;
      return 'a';
    });
    await firstEntered.future;
    // The other destination completes while the first is still held.
    final other = await gate.withDestination('net|b|9100', () async => 'b');
    expect(other, 'b');
    release.complete();
    expect(await blocked, 'a');
  });

  test('a throwing send releases the gate; the next send proceeds and the '
      'error reaches only its own caller', () async {
    final failing = gate.withDestination(
      'bt|aa:bb',
      () async => throw StateError('printer exploded'),
    );
    await expectLater(failing, throwsA(isA<StateError>()));
    // The key is fully released — an immediate send runs to completion.
    expect(await gate.withDestination('bt|aa:bb', () async => 42), 42);
  });

  test('FIFO ordering holds across MANY waiters', () async {
    final order = <int>[];
    final release = Completer<void>();
    final futures = <Future<void>>[
      gate.withDestination('k', () async {
        await release.future;
        order.add(0);
      }),
      for (var i = 1; i <= 4; i++)
        gate.withDestination('k', () async => order.add(i)),
    ];
    release.complete();
    await Future.wait(futures);
    expect(order, [0, 1, 2, 3, 4]);
  });

  test('canonical keys: host case/whitespace and address case collapse; '
      'purpose never enters the key', () {
    expect(
      PrinterDestinationSendGate.networkKey(' Kitchen.LOCAL ', 9100),
      PrinterDestinationSendGate.networkKey('kitchen.local', 9100),
    );
    expect(
      PrinterDestinationSendGate.networkKey('h', 9100),
      isNot(PrinterDestinationSendGate.networkKey('h', 9101)),
    );
    expect(
      PrinterDestinationSendGate.bluetoothKey('DC:0D:30:AA:BB:CC '),
      PrinterDestinationSendGate.bluetoothKey('dc:0d:30:aa:bb:cc'),
    );
    expect(
      PrinterDestinationSendGate.networkKey('x', 1),
      isNot(PrinterDestinationSendGate.bluetoothKey('x')),
      reason: 'transport families never collide',
    );
  });
}
