import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-070: each ESC/POS command method emits a known, deterministic byte
/// sequence, and user text is written as DATA only (never control bytes).
void main() {
  group('EscPosCommandBuilder commands', () {
    test('init = ESC @', () {
      expect((EscPosCommandBuilder()..init()).bytes(), [0x1B, 0x40]);
    });

    test('selectCodePage = ESC t n', () {
      expect((EscPosCommandBuilder()..selectCodePage(CodePage.cp437)).bytes(), [
        0x1B,
        0x74,
        0x00,
      ]);
      expect((EscPosCommandBuilder()..selectCodePage(CodePage.cp858)).bytes(), [
        0x1B,
        0x74,
        19,
      ]);
    });

    test('align left/center/right = ESC a 0/1/2', () {
      expect((EscPosCommandBuilder()..align(PrintAlignment.left)).bytes(), [
        0x1B,
        0x61,
        0,
      ]);
      expect((EscPosCommandBuilder()..align(PrintAlignment.center)).bytes(), [
        0x1B,
        0x61,
        1,
      ]);
      expect((EscPosCommandBuilder()..align(PrintAlignment.right)).bytes(), [
        0x1B,
        0x61,
        2,
      ]);
    });

    test('bold on/off = ESC E 1/0', () {
      expect((EscPosCommandBuilder()..bold(true)).bytes(), [0x1B, 0x45, 1]);
      expect((EscPosCommandBuilder()..bold(false)).bytes(), [0x1B, 0x45, 0]);
    });

    test('setTextSize = GS ! n (clamped 1..8)', () {
      expect(
        (EscPosCommandBuilder()..setTextSize(width: 2, height: 2)).bytes(),
        [0x1D, 0x21, 0x11],
      );
      expect(
        (EscPosCommandBuilder()..setTextSize(width: 99, height: 0)).bytes(),
        [0x1D, 0x21, 0x70],
      ); // ((8-1)<<4)|(1-1)
    });

    test('lineFeed = LF; feed(n) = ESC d n (clamped 0..255)', () {
      expect((EscPosCommandBuilder()..lineFeed()).bytes(), [0x0A]);
      expect((EscPosCommandBuilder()..feed(3)).bytes(), [0x1B, 0x64, 3]);
      expect((EscPosCommandBuilder()..feed(999)).bytes(), [0x1B, 0x64, 255]);
    });

    test('cut = GS V 1 (partial)', () {
      expect((EscPosCommandBuilder()..cut()).bytes(), [0x1D, 0x56, 0x01]);
    });

    test('drawerKick primitive = ESC p m t1 t2 (command only, no trigger)', () {
      expect((EscPosCommandBuilder()..drawerKick()).bytes(), [
        0x1B,
        0x70,
        0,
        25,
        25,
      ]);
      expect(
        (EscPosCommandBuilder()..drawerKick(pin: 1, onTime: 50, offTime: 50))
            .bytes(),
        [0x1B, 0x70, 1, 50, 50],
      );
    });

    test('rasterImage primitive = GS v 0 header + supplied payload', () {
      final data = Uint8List.fromList([0xFF, 0x00]);
      final bytes =
          (EscPosCommandBuilder()
                ..rasterImage(data: data, widthBytes: 1, heightDots: 2))
              .bytes();
      // GS v 0 m=0, xL=1 xH=0, yL=2 yH=0, then payload FF 00.
      expect(bytes, [
        0x1D,
        0x76,
        0x30,
        0x00,
        0x01,
        0x00,
        0x02,
        0x00,
        0xFF,
        0x00,
      ]);
    });

    test('rasterImage rejects mismatched dimensions', () {
      expect(
        () => EscPosCommandBuilder().rasterImage(
          data: Uint8List(3),
          widthBytes: 1,
          heightDots: 2,
        ),
        throwsArgumentError,
      );
    });
  });

  group('text() writes DATA bytes only (no command injection)', () {
    test('printable ASCII passes through', () {
      expect((EscPosCommandBuilder()..text('Hi 9')).bytes(), [
        0x48,
        0x69,
        0x20,
        0x39,
      ]);
    });

    test(
      'control bytes in user text (ESC, LF) become "?" — never commands',
      () {
        // 'a' + ESC(0x1B) + 'b' + LF(0x0A) + 'c'  ->  a ? b ? c
        final input =
            'a${String.fromCharCode(0x1B)}b${String.fromCharCode(0x0A)}c';
        expect((EscPosCommandBuilder()..text(input)).bytes(), [
          0x61,
          0x3F,
          0x62,
          0x3F,
          0x63,
        ]);
      },
    );

    test('non-ASCII (Arabic/Hebrew) becomes "?" — raster path is RF-073', () {
      // Arabic alef + Hebrew alef -> both replaced (no shaping in RF-070).
      expect((EscPosCommandBuilder()..text('اא')).bytes(), [0x3F, 0x3F]);
    });
  });
}
