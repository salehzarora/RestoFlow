import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_native_printer.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// PRINT-RTL-001: the KDS native kitchen-ticket bridge renders Arabic/Hebrew
/// tickets (incl. an ar/he customer name + item names) as an ESC/POS RASTER
/// image so they print correctly instead of "?????". The kitchen ticket stays
/// MONEY-FREE (T-003) — so the rasterized image carries no money either.

class _RecordingTransport implements pp.PrintTransport {
  Uint8List? sent;
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent = bytes;
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

bool _containsSeq(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

Future<AppLocalizations> _ar() =>
    AppLocalizations.delegate.load(const Locale('ar'));

KdsTicketView _arabicTicket() => KdsTicketView(
  kitchenTicketId: 'o1:grill',
  stationId: 'grill',
  status: KitchenTicketStatus.inPreparation,
  orderId: 'o1',
  orderNumber: '#ABC123',
  orderType: 'dine_in',
  tableLabel: 'T2',
  customerName: 'محمد',
  items: [
    const KdsItemView(
      name: 'برجر كلاسيك',
      quantity: 2,
      modifiers: ['جبنة إضافية'],
      note: 'بدون بصل',
    ),
  ],
);

void main() {
  test('Arabic kitchen ticket over the native bridge -> ESC/POS RASTER bytes '
      '(GS v 0), delivered', () async {
    final l10n = await _ar();
    final transport = _RecordingTransport();
    final bridge = NativeKdsPrintBridge(
      NativeEscPosSender(transportFactory: () => transport),
      rasterizer: pp.FakeReceiptRasterizer(),
    );
    final result = await bridge.submit(
      buildKdsTicketDocument(l10n, _arabicTicket()),
    );
    expect(result.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
    expect(_containsSeq(transport.sent!, [0x1D, 0x76, 0x30]), isTrue);
  });

  test('the ar customer name + item names reach the rasterizer, and the raster '
      'is MONEY-FREE (T-003)', () async {
    final l10n = await _ar();
    final fake = pp.FakeReceiptRasterizer();
    await NativeKdsPrintBridge(
      NativeEscPosSender(transportFactory: () => _RecordingTransport()),
      rasterizer: fake,
    ).submit(buildKdsTicketDocument(l10n, _arabicTicket()));
    final rasterized = fake.requests.single.lines.join('\n');
    expect(rasterized.contains('محمد'), isTrue); // ar customer name
    expect(rasterized.contains('برجر كلاسيك'), isTrue); // ar item name
    // Money-free: the kitchen ticket never carries money, so neither does the image.
    expect(rasterized.contains('₪'), isFalse);
    expect(rasterized.toLowerCase().contains('minor'), isFalse);
  });

  test('no rasterizer -> ESC/POS TEXT fallback (no raster command)', () async {
    final l10n = await _ar();
    final transport = _RecordingTransport();
    await NativeKdsPrintBridge(
      NativeEscPosSender(transportFactory: () => transport),
    ).submit(buildKdsTicketDocument(l10n, _arabicTicket()));
    expect(_containsSeq(transport.sent!, [0x1D, 0x76, 0x30]), isFalse);
  });
}
