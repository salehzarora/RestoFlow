import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-070 AC3: connectivity is configurable; in-memory works and captures bytes,
/// while network/USB/Bluetooth fail clearly (no sockets, no USB/BT libs).
void main() {
  group('transportFor', () {
    test('inMemory returns a working capturing transport', () async {
      final t = transportFor(PrintConnectivity.inMemory);
      expect(t, isA<InMemoryPrintTransport>());
      final r = await t.send(Uint8List.fromList([1, 2, 3]));
      expect(r.ok, isTrue);
      expect((t as InMemoryPrintTransport).lastBytes, [1, 2, 3]);
    });

    test(
      'network/usb/bluetooth throw a clear UnsupportedTransportException',
      () {
        for (final c in [
          PrintConnectivity.network,
          PrintConnectivity.usb,
          PrintConnectivity.bluetooth,
        ]) {
          expect(
            () => transportFor(c),
            throwsA(
              isA<UnsupportedTransportException>().having(
                (e) => e.connectivity,
                'connectivity',
                c,
              ),
            ),
            reason: '${c.name} is deferred (RF-071+) and must fail clearly',
          );
        }
      },
    );
  });

  group('InMemoryPrintTransport', () {
    test('captures each batch and concatenates allBytes', () async {
      final t = InMemoryPrintTransport();
      expect(t.lastBytes, isNull);
      await t.send(Uint8List.fromList([0xAA]));
      await t.send(Uint8List.fromList([0xBB, 0xCC]));
      expect(t.batches.length, 2);
      expect(t.allBytes, [0xAA, 0xBB, 0xCC]);
      await t.dispose();
    });
  });
}
