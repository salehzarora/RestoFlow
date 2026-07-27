import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// PRINT-BRANDING-LOGO-001 §17 — NO-LOGO BYTE-LEVEL BASELINE.
///
/// The branding pass touched exactly one encode-path file (`rtl_raster.dart`);
/// every other file in the ESC/POS pipeline (media profiles, the command
/// builder + adapter, pagination, typography, the shared [FakeReceiptRasterizer])
/// is byte-identical to the review base 8868780962a3a5468d8f5c37535bae807ad36191.
/// This test proves EMPIRICALLY that, for a receipt with NO logo, the encoded
/// ESC/POS output is byte-identical to that baseline on all three media profiles
/// (continuous80 text path, continuous80 raster path, and both fixed labels) —
/// i.e. the branding change is a no-op whenever no logo is present.
///
/// HOW THE GOLDEN WAS CAPTURED (deterministic, no secrets): this exact file was
/// copied verbatim into a detached `git worktree` at the baseline commit and run
/// there. With no golden JSON present it runs in CAPTURE mode and prints each
/// digest; those digests were recorded into
/// `test/fixtures/logo_free_baseline.json` (which also records the baseline SHA).
/// On this branch the JSON is present, so every digest is asserted equal — any
/// byte drift on the no-logo path fails the build. Because the same file computed
/// both sides, the compute logic cannot drift between capture and verify.
///
/// The digest is a self-tested pure-Dart SHA-256 of the FINAL adapter bytes (the
/// exact payload the TCP/Bluetooth transports send — see the payload-identity
/// test below), plus the page STRUCTURE (feed/cut/image/text counts) so a
/// pagination change is caught even in the astronomically unlikely event of a
/// hash collision. No `crypto` dependency is added (printing stays pure-Dart).

/// Resolve a committed fixture regardless of the test CWD (package vs repo root).
File _fixture(String name) {
  for (final base in ['test/fixtures', 'packages/printing/test/fixtures']) {
    final f = File('$base/$name');
    if (f.existsSync()) return f;
  }
  return File('test/fixtures/$name');
}

// ---------------------------------------------------------------------------
// Deterministic fixtures (NO logo). The `en` fixture is pure ASCII, so the
// continuous80 roll stays the crisp TEXT path; the `ar` fixture carries
// Arabic/Hebrew + ₪/×, so continuous80 takes the RASTER path. Both are tall
// enough to force multi-page pagination on the small 50x50 label.
// ---------------------------------------------------------------------------

PrintDocument _enReceipt() => const PrintDocument(<PrintLine>[
  PrintTextLine(
    'THE CORNER BISTRO',
    alignment: PrintAlignment.center,
    emphasis: TextEmphasis.bold,
    style: PrintLineStyle.headingLarge,
  ),
  PrintTextLine(
    'Order #A-1042',
    alignment: PrintAlignment.center,
    style: PrintLineStyle.subheading,
  ),
  PrintTextLine(
    '--------------------------------',
    style: PrintLineStyle.separator,
  ),
  PrintTextLine(
    '1x Falafel Plate            32.00',
    style: PrintLineStyle.item,
  ),
  PrintTextLine('  + Extra tahini             3.00', style: PrintLineStyle.sub),
  PrintTextLine('  no onions', style: PrintLineStyle.note),
  PrintTextLine(
    '2x Mint Lemonade            24.00',
    style: PrintLineStyle.item,
  ),
  PrintTextLine(
    '1x Baklava                  14.00',
    style: PrintLineStyle.item,
  ),
  PrintTextLine(
    '--------------------------------',
    style: PrintLineStyle.separator,
  ),
  PrintTextLine(
    'Subtotal                    73.00',
    style: PrintLineStyle.normal,
  ),
  PrintTextLine(
    'VAT 17%                     12.41',
    style: PrintLineStyle.normal,
  ),
  PrintTextLine(
    'TOTAL                       85.41',
    style: PrintLineStyle.total,
  ),
  PrintTextLine(
    'Cash                       100.00',
    style: PrintLineStyle.normal,
  ),
  PrintTextLine(
    'Change                      14.59',
    style: PrintLineStyle.normal,
  ),
  PrintTextLine(
    'Thank you!',
    alignment: PrintAlignment.center,
    style: PrintLineStyle.centered,
  ),
  PrintFeedLine(3),
  PrintCutLine(),
], localeTag: 'en');

PrintDocument _arReceipt() => const PrintDocument(<PrintLine>[
  PrintTextLine(
    'مطعم الزاوية',
    alignment: PrintAlignment.center,
    emphasis: TextEmphasis.bold,
    style: PrintLineStyle.headingLarge,
  ),
  PrintTextLine(
    'طلب #A-1042',
    alignment: PrintAlignment.center,
    style: PrintLineStyle.subheading,
  ),
  PrintTextLine(
    '--------------------------------',
    style: PrintLineStyle.separator,
  ),
  PrintTextLine('1× فلافل                  ₪32.00', style: PrintLineStyle.item),
  PrintTextLine('  + طحينة إضافية            ₪3.00', style: PrintLineStyle.sub),
  PrintTextLine('  بدون بصل', style: PrintLineStyle.note),
  PrintTextLine('2× ليموناضة نعناع         ₪24.00', style: PrintLineStyle.item),
  PrintTextLine('1× بقلاوة                 ₪14.00', style: PrintLineStyle.item),
  PrintTextLine(
    '--------------------------------',
    style: PrintLineStyle.separator,
  ),
  PrintTextLine(
    'المجموع الفرعي            ₪73.00',
    style: PrintLineStyle.normal,
  ),
  PrintTextLine(
    'ضريبة ١٧٪                 ₪12.41',
    style: PrintLineStyle.normal,
  ),
  PrintTextLine(
    'الإجمالي                  ₪85.41',
    style: PrintLineStyle.total,
  ),
  PrintTextLine(
    'نقداً                    ₪100.00',
    style: PrintLineStyle.normal,
  ),
  PrintTextLine(
    'الباقي                    ₪14.59',
    style: PrintLineStyle.normal,
  ),
  PrintTextLine(
    'شكراً لكم',
    alignment: PrintAlignment.center,
    style: PrintLineStyle.centered,
  ),
  PrintFeedLine(3),
  PrintCutLine(),
], localeTag: 'ar');

// Deterministic page labels so multi-page pagination + the reserved header rows
// are exercised identically on both worktrees (ASCII, no l10n dependency).
String _pageLabel(int page, int total) => 'PAGE $page OF $total';
String _contHeader(int page, int total) => 'CONT $page';

const _adapter = EscPosPrintAdapter();
const _profile = PrinterProfile.escPos80mm;

/// Encode [doc] for [profile] through the FULL bridge pipeline (rasterize for the
/// media profile, then the ESC/POS adapter) and return the final payload bytes —
/// exactly what `transport.send(...)` receives.
Future<Uint8List> _encodeFor(PrintDocument doc, MediaProfile profile) async {
  final laidOut = await rasterizeForMediaProfile(
    doc,
    rasterizer: FakeReceiptRasterizer(),
    profile: profile,
    pageLabel: _pageLabel,
    continuationHeader: _contHeader,
  );
  return _adapter.encode(laidOut, _profile);
}

/// The layed-out document (before adapter encoding) — used to count physical
/// page structure (one image + one feed + one cut per page).
Future<PrintDocument> _layoutFor(PrintDocument doc, MediaProfile profile) =>
    rasterizeForMediaProfile(
      doc,
      rasterizer: FakeReceiptRasterizer(),
      profile: profile,
      pageLabel: _pageLabel,
      continuationHeader: _contHeader,
    );

/// A structural + byte digest of the encoded no-logo output. Only strings/ints,
/// so it round-trips through JSON canonically for a stable equality check.
Future<Map<String, Object>> _digest(
  PrintDocument doc,
  MediaProfile profile,
) async {
  final bytes = await _encodeFor(doc, profile);
  final layout = await _layoutFor(doc, profile);
  var feeds = 0;
  var cuts = 0;
  var images = 0;
  var texts = 0;
  for (final line in layout.lines) {
    switch (line) {
      case PrintFeedLine():
        feeds++;
      case PrintCutLine():
        cuts++;
      case PrintRasterImageLine():
        images++;
      case PrintTextLine():
        texts++;
      case PrintDrawerKickLine():
        break;
    }
  }
  return <String, Object>{
    'sha256': _Sha256.hex(bytes),
    'byteLength': bytes.length,
    'pages': cuts,
    'feeds': feeds,
    'rasterImages': images,
    'textLines': texts,
  };
}

const _fixtures = <String, PrintDocument Function()>{
  'en': _enReceipt,
  'ar': _arReceipt,
};

const _profiles = <String, MediaProfile>{
  'continuous80': MediaProfile.continuous80,
  'label50x50': MediaProfile.label50x50,
  'label80x80': MediaProfile.label80x80,
};

void main() {
  // The hasher must be provably correct before it can certify byte-identity.
  test('SHA-256 helper matches the NIST test vectors', () {
    expect(
      _Sha256.hex(Uint8List(0)),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      _Sha256.hex(Uint8List.fromList(utf8.encode('abc'))),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      _Sha256.hex(
        Uint8List.fromList(
          utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          ),
        ),
      ),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
  });

  final goldenFile = _fixture('logo_free_baseline.json');
  final Map<String, dynamic>? golden = goldenFile.existsSync()
      ? (jsonDecode(goldenFile.readAsStringSync()) as Map<String, dynamic>)
      : null;

  group('§17 no-logo encoded bytes are byte-identical to baseline', () {
    for (final fx in _fixtures.entries) {
      for (final pf in _profiles.entries) {
        final key = '${fx.key}_${pf.key}';
        test('$key digest matches baseline', () async {
          final digest = await _digest(fx.value(), pf.value);
          if (golden == null || golden[key] == null) {
            // CAPTURE mode (baseline worktree): no golden yet — record it.
            // ignore: avoid_print
            print('CAPTURE $key ${jsonEncode(digest)}');
            markTestSkipped('capture mode — no golden baseline present');
            return;
          }
          expect(
            jsonEncode(digest),
            jsonEncode(golden[key]),
            reason:
                'no-logo $key drifted from baseline '
                '${golden['_baseline_commit']}',
          );
        });
      }
    }
  });

  group('§17 the transport payload IS the encoded ESC/POS bytes', () {
    test('the in-memory transport receives exactly the adapter bytes', () async {
      // The bridge does `transport.send(adapter.encode(doc))`; neither the TCP
      // sender (`socket.add(bytes)`) nor the Bluetooth connector transforms the
      // payload before chunking. So the "TCP payload" and the "Bluetooth logical
      // payload before transport chunking" are literally these bytes.
      final bytes = await _encodeFor(_enReceipt(), MediaProfile.continuous80);
      final transport = InMemoryPrintTransport();
      final result = await transport.send(bytes);
      expect(result.ok, isTrue);
      expect(transport.lastBytes, isNotNull);
      expect(transport.lastBytes, orderedEquals(bytes));
    });
  });
}

/// A minimal, allocation-light, self-contained SHA-256 (FIPS 180-4). Present so
/// the byte-identity claim needs no third-party `crypto` dependency (printing is
/// pure-Dart). Verified against the NIST vectors in the test above.
class _Sha256 {
  static const List<int> _k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  static const int _mask = 0xFFFFFFFF;

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & _mask;

  static String hex(Uint8List message) {
    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final bitLen = message.length * 8;
    // Pre-processing: append 0x80, pad with zeros to 56 mod 64, then 64-bit len.
    final padLen = ((56 - (message.length + 1) % 64) % 64);
    final total = message.length + 1 + padLen + 8;
    final data = Uint8List(total)..setRange(0, message.length, message);
    data[message.length] = 0x80;
    // 64-bit big-endian length (message length in bits fits in 53 bits here).
    for (var i = 0; i < 8; i++) {
      data[total - 1 - i] = (bitLen >> (8 * i)) & 0xFF;
    }

    final w = List<int>.filled(64, 0);
    for (var chunk = 0; chunk < total; chunk += 64) {
      for (var i = 0; i < 16; i++) {
        final j = chunk + i * 4;
        w[i] =
            (data[j] << 24) |
            (data[j + 1] << 16) |
            (data[j + 2] << 8) |
            data[j + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 =
            _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & _mask;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ (~e & _mask & g);
        final t1 = (h + s1 + ch + _k[i] + w[i]) & _mask;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (s0 + maj) & _mask;
        h = g;
        g = f;
        f = e;
        e = (d + t1) & _mask;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & _mask;
      }

      h0 = (h0 + a) & _mask;
      h1 = (h1 + b) & _mask;
      h2 = (h2 + c) & _mask;
      h3 = (h3 + d) & _mask;
      h4 = (h4 + e) & _mask;
      h5 = (h5 + f) & _mask;
      h6 = (h6 + g) & _mask;
      h7 = (h7 + h) & _mask;
    }

    final out = StringBuffer();
    for (final h in <int>[h0, h1, h2, h3, h4, h5, h6, h7]) {
      out.write(h.toRadixString(16).padLeft(8, '0'));
    }
    return out.toString();
  }
}
