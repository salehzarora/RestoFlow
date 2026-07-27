import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart' as kitchen;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/native_print_bridges.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show receiptToEscPosDocument;
import 'package:restoflow_pos/src/print/print_document.dart' as app;
import 'package:restoflow_pos/src/print/receipt_logo_asset.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

CashPayment _payment() => CashPayment(
  paymentId: 'pay-1',
  orderNumber: '#ABC',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 1000,
  tenderedMinor: 1000,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.utc(2026, 7, 7, 12),
);

SubmittedOrderView _order() => const SubmittedOrderView(
  orderNumber: '#ABC',
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 1000,
  lines: [
    SubmittedLineView(
      name: 'Item',
      quantity: 1,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
    ),
  ],
);

/// A real, non-blank logo raster for the given profile (a solid-black square).
pp.LogoRaster _raster(pp.MediaProfile profile) {
  final rgba = Uint8List(64 * 32 * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i + 3] = 255; // opaque black
  }
  return const pp.LogoRasterizer().rasterizeForProfile(
    pp.DecodedLogoImage(width: 64, height: 32, rgba: rgba),
    profile,
  );
}

ReceiptLogoAsset _asset(pp.MediaProfile profile, {bool withRaster = true}) =>
    ReceiptLogoAsset(
      sourceBytes: Uint8List.fromList([1, 2, 3, 4]),
      sourceMime: 'image/png',
      raster: withRaster ? _raster(profile) : null,
    );

/// A fake transport returning a scripted result list (last result repeats).
class _FakeTransport implements pp.PrintTransport {
  _FakeTransport(this._results);
  final List<pp.PrintResult> _results;
  final List<Uint8List> sent = <Uint8List>[];
  int _i = 0;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    final r = _results[_i < _results.length ? _i : _results.length - 1];
    _i++;
    return r;
  }

  @override
  Future<void> dispose() async {}
}

/// An adapter that THROWS when the document contains a raster image (a logo),
/// but encodes a text-only document normally — used to exercise the safe
/// PRE-transport encoding fallback (§4A).
class _RasterHostileAdapter implements pp.PrintAdapter {
  const _RasterHostileAdapter();
  static const _real = pp.EscPosPrintAdapter();

  @override
  Uint8List encode(pp.PrintDocument document, pp.PrinterProfile profile) {
    if (document.lines.any((l) => l is pp.PrintRasterImageLine)) {
      throw StateError('raster encoding failed');
    }
    return _real.encode(document, profile);
  }
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('buildReceiptDocument branding', () {
    test('NO branding => byte-identical to the pre-branding receipt', () {
      final plain = buildReceiptDocument(l10n, _order(), _payment());
      // No headerImage line at all; the first line is the brand title.
      expect(
        plain.lines.any((l) => l.kind == app.PrintLineKind.headerImage),
        isFalse,
      );
      expect(plain.lines.first.kind, app.PrintLineKind.title);
    });

    test(
      'WITH branding => a headerImage line is prepended before the title',
      () {
        final asset = _asset(pp.MediaProfile.continuous80);
        final branded = buildReceiptDocument(
          l10n,
          _order(),
          _payment(),
          branding: asset,
        );
        expect(branded.lines.first.kind, app.PrintLineKind.headerImage);
        expect(branded.lines.first.logo, same(asset));
        expect(branded.lines[1].kind, app.PrintLineKind.title);
        // Removing the header image reproduces the exact no-logo line kinds.
        final plain = buildReceiptDocument(l10n, _order(), _payment());
        final strippedKinds = branded.lines
            .where((l) => l.kind != app.PrintLineKind.headerImage)
            .map((l) => l.kind)
            .toList();
        expect(strippedKinds, plain.lines.map((l) => l.kind).toList());
      },
    );
  });

  group('documentToHtml', () {
    test('emits an <img> data URI when a logo is present', () {
      final doc = buildReceiptDocument(
        l10n,
        _order(),
        _payment(),
        branding: _asset(pp.MediaProfile.continuous80),
      );
      final html = app.documentToHtml(doc);
      expect(html.contains('<img'), isTrue);
      expect(html.contains('data:image/png;base64,'), isTrue);
    });

    test('emits NO <img> for a text-only receipt', () {
      final html = app.documentToHtml(
        buildReceiptDocument(l10n, _order(), _payment()),
      );
      expect(html.contains('<img'), isFalse);
    });
  });

  group('receiptToEscPosDocument', () {
    test('maps a headerImage(raster) to exactly one PrintRasterImageLine', () {
      final doc = buildReceiptDocument(
        l10n,
        _order(),
        _payment(),
        branding: _asset(pp.MediaProfile.continuous80),
      );
      final escpos = receiptToEscPosDocument(doc);
      final rasterLines = escpos.lines.whereType<pp.PrintRasterImageLine>();
      expect(rasterLines.length, 1);
    });

    test('omits the raster when the asset has no raster (text-only)', () {
      final doc = buildReceiptDocument(
        l10n,
        _order(),
        _payment(),
        branding: _asset(pp.MediaProfile.continuous80, withRaster: false),
      );
      final escpos = receiptToEscPosDocument(doc);
      expect(escpos.lines.whereType<pp.PrintRasterImageLine>(), isEmpty);
    });

    test('a no-logo receipt has no raster line', () {
      final escpos = receiptToEscPosDocument(
        buildReceiptDocument(l10n, _order(), _payment()),
      );
      expect(escpos.lines.whereType<pp.PrintRasterImageLine>(), isEmpty);
    });
  });

  group('NativeTransportPrintBridge §4 safe transport contract', () {
    NativeTransportPrintBridge bridge(
      _FakeTransport t, {
      pp.PrintAdapter adapter = const pp.EscPosPrintAdapter(),
    }) => NativeTransportPrintBridge(
      transportFactory: () => t,
      adapter: adapter,
      mediaProfile: pp.MediaProfile.continuous80,
    );

    test('a logo job that succeeds sends exactly once', () async {
      final t = _FakeTransport([const pp.PrintResult.success()]);
      final result = await bridge(t).submit(
        buildReceiptDocument(
          l10n,
          _order(),
          _payment(),
          branding: _asset(pp.MediaProfile.continuous80),
        ),
      );
      expect(t.sent.length, 1);
      expect(result.ok, isTrue);
    });

    test('TCP failure BEFORE send begins => ONE send, no resend', () async {
      final t = _FakeTransport([
        const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable),
      ]);
      final result = await bridge(t).submit(
        buildReceiptDocument(
          l10n,
          _order(),
          _payment(),
          branding: _asset(pp.MediaProfile.continuous80),
        ),
      );
      expect(t.sent.length, 1, reason: 'never auto-resend a logo job');
      expect(result.ok, isFalse);
    });

    test(
      'transport failure AFTER send begins => ONE send, no text-only resend',
      () async {
        final t = _FakeTransport([
          const pp.PrintResult.failureAfterSend(
            pp.PrinterErrorCategory.writeFailed,
            bytesSent: 128,
          ),
        ]);
        final result = await bridge(t).submit(
          buildReceiptDocument(
            l10n,
            _order(),
            _payment(),
            branding: _asset(pp.MediaProfile.continuous80),
          ),
        );
        expect(t.sent.length, 1, reason: 'partial print => never auto-resend');
        expect(result.ok, isFalse);
      },
    );

    test('a NO-logo job that fails does NOT retry (1 send)', () async {
      final t = _FakeTransport([
        const pp.PrintResult.failure(pp.PrinterErrorCategory.unknown),
      ]);
      final result = await bridge(
        t,
      ).submit(buildReceiptDocument(l10n, _order(), _payment()));
      expect(t.sent.length, 1);
      expect(result.ok, isFalse);
    });

    test(
      'PRE-transport encoding failure of the logo => text-only ONE send (§4A)',
      () async {
        final t = _FakeTransport([const pp.PrintResult.success()]);
        // The hostile adapter throws on the logo-bearing document; the bridge
        // must re-encode text-only BEFORE sending, then send exactly once.
        final result = await bridge(t, adapter: const _RasterHostileAdapter())
            .submit(
              buildReceiptDocument(
                l10n,
                _order(),
                _payment(),
                branding: _asset(pp.MediaProfile.continuous80),
              ),
            );
        expect(t.sent.length, 1, reason: 'text-only fallback is pre-transport');
        expect(result.ok, isTrue);
      },
    );
  });

  group('kitchen exclusion (§22) — the logo line kind is receipt-only', () {
    test('the POS receipt model HAS a headerImage kind', () {
      expect(
        app.PrintLineKind.values.map((e) => e.name),
        contains('headerImage'),
      );
    });

    test('the kitchen document model has NO image/logo/raster line kind', () {
      final kitchenKinds = kitchen.PrintLineKind.values
          .map((e) => e.name.toLowerCase())
          .toList();
      for (final needle in ['headerimage', 'image', 'logo', 'raster']) {
        expect(
          kitchenKinds.any((k) => k.contains(needle)),
          isFalse,
          reason: 'kitchen must never carry a $needle line kind',
        );
      }
    });
  });
}
