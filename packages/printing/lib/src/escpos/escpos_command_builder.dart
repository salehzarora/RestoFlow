import 'dart:typed_data';

import '../print_document.dart';
import '../printer_profile.dart';

/// A low-level, deterministic ESC/POS byte builder (RF-070).
///
/// Each method appends a single, well-known command sequence. CONTROL bytes are
/// emitted ONLY by these methods — [text] writes user input strictly as data
/// bytes (printable ASCII; every control byte and non-ASCII code unit is mapped
/// to '?'), so user text can never inject an ESC/POS command. Output is
/// deterministic (golden-testable). No transport, no job identity, no state
/// beyond the accumulating buffer.
class EscPosCommandBuilder {
  final BytesBuilder _b = BytesBuilder(copy: false);

  // Control bytes.
  static const int _esc = 0x1B; // ESC
  static const int _gs = 0x1D; // GS
  static const int _lf = 0x0A; // LF
  static const int _replacement = 0x3F; // '?'

  /// The bytes accumulated so far.
  Uint8List bytes() => _b.toBytes();

  /// ESC @ — initialize/reset the printer to defaults.
  EscPosCommandBuilder init() {
    _b.add([_esc, 0x40]);
    return this;
  }

  /// ESC t n — select the character code page table.
  EscPosCommandBuilder selectCodePage(CodePage codePage) {
    _b.add([_esc, 0x74, _clampByte(codePage.escPosTableId)]);
    return this;
  }

  /// ESC a n — alignment (0 left, 1 center, 2 right).
  EscPosCommandBuilder align(PrintAlignment alignment) {
    final n = switch (alignment) {
      PrintAlignment.left => 0,
      PrintAlignment.center => 1,
      PrintAlignment.right => 2,
    };
    _b.add([_esc, 0x61, n]);
    return this;
  }

  /// ESC E n — emphasis/bold on (1) or off (0).
  EscPosCommandBuilder bold(bool on) {
    _b.add([_esc, 0x45, on ? 1 : 0]);
    return this;
  }

  /// GS ! n — character size (width/height multipliers 1..8). Simple + safe.
  EscPosCommandBuilder setTextSize({int width = 1, int height = 1}) {
    final w = _clampMultiplier(width);
    final h = _clampMultiplier(height);
    final n = ((w - 1) << 4) | (h - 1);
    _b.add([_gs, 0x21, n]);
    return this;
  }

  /// Write user [value] as DATA bytes only. Printable ASCII (0x20..0x7E) passes
  /// through; every control byte (incl. ESC/GS/LF) and non-ASCII code unit
  /// becomes '?'. Real Arabic/Hebrew goes through the raster path (RF-073).
  EscPosCommandBuilder text(String value) {
    final out = Uint8List(value.length);
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      out[i] = (c >= 0x20 && c <= 0x7E) ? c : _replacement;
    }
    _b.add(out);
    return this;
  }

  /// LF — one line feed.
  EscPosCommandBuilder lineFeed() {
    _b.addByte(_lf);
    return this;
  }

  /// ESC d n — feed n lines (0..255).
  EscPosCommandBuilder feed(int lines) {
    _b.add([_esc, 0x64, _clampByte(lines)]);
    return this;
  }

  /// GS V m — partial cut (m = 1).
  EscPosCommandBuilder cut() {
    _b.add([_gs, 0x56, 0x01]);
    return this;
  }

  /// ESC p m t1 t2 — drawer kick pulse (command primitive only; RF-074 owns the
  /// trigger). [pin] 0/1; [onTime]/[offTime] in 2ms units (0..255).
  EscPosCommandBuilder drawerKick({
    int pin = 0,
    int onTime = 25,
    int offTime = 25,
  }) {
    _b.add([
      _esc,
      0x70,
      pin == 1 ? 1 : 0,
      _clampByte(onTime),
      _clampByte(offTime),
    ]);
    return this;
  }

  /// GS v 0 — print an ALREADY-PREPARED monochrome raster bitmap (RF-070 A2).
  /// [data] is row-major MSB-first, [widthBytes] bytes/row, [heightDots] rows.
  /// RF-070 only ENCODES the supplied payload; it does not generate bitmaps.
  EscPosCommandBuilder rasterImage({
    required Uint8List data,
    required int widthBytes,
    required int heightDots,
  }) {
    if (widthBytes <= 0 || heightDots <= 0) {
      throw ArgumentError('raster dimensions must be positive');
    }
    if (data.length != widthBytes * heightDots) {
      throw ArgumentError(
        'raster data length must equal widthBytes * heightDots',
      );
    }
    final xL = widthBytes & 0xFF;
    final xH = (widthBytes >> 8) & 0xFF;
    final yL = heightDots & 0xFF;
    final yH = (heightDots >> 8) & 0xFF;
    _b.add([_gs, 0x76, 0x30, 0x00, xL, xH, yL, yH]);
    _b.add(data);
    return this;
  }

  static int _clampByte(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
  static int _clampMultiplier(int v) => v < 1 ? 1 : (v > 8 ? 8 : v);
}
