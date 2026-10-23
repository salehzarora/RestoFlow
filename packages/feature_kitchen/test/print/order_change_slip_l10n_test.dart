import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenTicketStatus;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView, KdsTicketMapper, KdsTicketView;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// ORDER-EDIT-001C (D-044) — the change slip in ar / he / en through the ONE
/// shared `AppLocalizations` (OPEN QUESTION Q-015 raster fallback).
///
///  * the ar/he slips carry NO English chrome and never the money-change word
///    (الباقي / עודף) — "CHANGE" is the order-change key;
///  * the raster paragraph direction is RTL for ar/he and LTR for en;
///  * an unsupported language code falls back to English (never a throw on
///    the print path);
///  * the paper never prints the KDS REMAKE / "instead of" words;
///  * the real Flutter rasterizer inks every band of every slip (copied from
///    packages/l10n/test/receipt_rasterizer_flutter_test.dart).

AppLocalizations _l10n(String code) => lookupAppLocalizations(Locale(code));

/// Localized item names, so the slip's dominant script is the slip's own
/// language (a Latin-named menu on an ar/he slip is the Q-015 residual).
const _names = <String, List<String>>{
  'en': ['Burger', 'Fries', 'Cola', 'Lemonade', 'Water', 'tomato', 'Dana'],
  'ar': ['برجر', 'بطاطا', 'كولا', 'ليموناضة', 'ماء', 'طماطم', 'دانا'],
  'he': ['המבורגר', 'צ׳יפס', 'קולה', 'לימונדה', 'מים', 'עגבנייה', 'דנה'],
};

OrderChangeSlipView _slip(String code, {String? reasonText}) {
  final n = _names[code]!;
  final burger = KdsItemView(name: n[0], quantity: 1, modifiers: [n[5]]);
  return OrderChangeSlipView(
    orderCode: '#A1B2C3',
    editNumber: 1,
    orderType: 'dine_in',
    tableLabel: '12',
    customerName: n[6],
    orderNote: n[4],
    editedAt: DateTime(2026, 10, 8, 12, 41),
    reasonCode: 'entry_mistake',
    reasonText: reasonText,
    staffFirstName: n[6],
    changes: [
      OrderChangeModified(
        was: burger,
        now: [KdsItemView(name: n[0], quantity: 1)],
      ),
      OrderChangeRemoved(KdsItemView(name: n[1], quantity: 1, note: n[4])),
      OrderChangeQuantity(
        was: KdsItemView(name: n[2], quantity: 3),
        nowQuantity: 1,
      ),
      OrderChangeQuantity(
        was: KdsItemView(name: n[3], quantity: 1),
        nowQuantity: 3,
      ),
      OrderChangeAdded([KdsItemView(name: n[4], quantity: 1)]),
    ],
    orderNow: [
      KdsItemView(name: n[0], quantity: 1),
      KdsItemView(name: n[2], quantity: 1),
      KdsItemView(name: n[3], quantity: 3),
      KdsItemView(name: n[4], quantity: 1),
    ],
  );
}

PrintDocument _doc(String code, {String? labelCode}) =>
    buildOrderChangeSlipPrintDocument(
      slip: _slip(code),
      labels: kitchenTicketPrintLabelsForLanguageCode(labelCode ?? code),
      changeLabels: kitchenChangeSlipLabelsForLanguageCode(labelCode ?? code),
    );

pp.PrintDocument _escPos(String code) =>
    kitchenTicketToEscPosDocument(_doc(code));

List<String> _texts(PrintDocument doc) => [
  for (final l in doc.lines) l.left ?? '',
];

/// Every English chrome string the slip can print (from the en labels).
List<String> _englishChrome() {
  final en = _l10n('en');
  return [
    en.kitchenChangeSlipTitle,
    en.kitchenEditChangeNumber(1),
    en.kitchenEditRemovedLabel,
    en.kitchenChangeSlipChangeLabel,
    en.kitchenChangeSlipAddLabel,
    en.kitchenChangeSlipOrderNow,
    '${en.kitchenChangeSlipWasLabel}:',
    '${en.kitchenChangeSlipNowLabel}:',
    en.kitchenChangeSlipStaffLabel,
    en.kitchenChangeSlipReasonLabel,
    en.kitchenChangeSlipFooter('#A1B2C3'),
    en.orderEditReasonEntryMistake,
    en.posOrderTypeDineIn,
    en.posTableLabel,
    en.customerNameKitchenLabel,
    en.kdsNoteLabel,
    en.printRestaurantNameFallback,
  ];
}

void main() {
  // dart:ui Picture.toImage needs an initialized binding (no widget tree).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('localized chrome', () {
    test('the en slip prints the exact English chrome', () {
      final texts = _texts(_doc('en'));
      expect(texts, contains('*** ORDER CHANGED · Change 1 ***'));
      expect(texts, containsAllInOrder(['REMOVED', 'CHANGE', 'ADD']));
      expect(texts, contains('ORDER NOW'));
      expect(texts, contains('Staff: Dana'));
      expect(texts, contains('» Reason: Order entry mistake'));
      expect(texts, contains('Replaces earlier tickets for #A1B2C3'));
      expect(texts.where((t) => t.startsWith('Was: ')), isNotEmpty);
      expect(texts.where((t) => t.startsWith('Now: ')), isNotEmpty);
    });

    for (final code in ['ar', 'he']) {
      test('the $code slip carries its own chrome and NO English chrome', () {
        final l10n = _l10n(code);
        final blob = _texts(_doc(code)).join('\n');
        for (final english in _englishChrome()) {
          expect(blob, isNot(contains(english)), reason: '"$english" leaked');
        }
        expect(
          blob,
          contains(
            '*** ${l10n.kitchenChangeSlipTitle} · '
            '${l10n.kitchenEditChangeNumber(1)} ***',
          ),
        );
        for (final heading in [
          l10n.kitchenEditRemovedLabel,
          l10n.kitchenChangeSlipChangeLabel,
          l10n.kitchenChangeSlipAddLabel,
          l10n.kitchenChangeSlipOrderNow,
          l10n.kitchenChangeSlipFooter('#A1B2C3'),
          '${l10n.kitchenChangeSlipStaffLabel}: ${_names[code]![6]}',
          '» ${l10n.kitchenChangeSlipReasonLabel}: '
              '${l10n.orderEditReasonEntryMistake}',
        ]) {
          expect(blob, contains(heading));
        }
        // No Latin letter at all, apart from the order code's own.
        expect(
          blob.replaceAll('#A1B2C3', '').contains(RegExp('[A-Za-z]')),
          isFalse,
        );
      });

      test('the $code slip never prints the money-change word', () {
        final blob = _texts(_doc(code)).join('\n');
        expect(blob, isNot(contains('الباقي')));
        expect(blob, isNot(contains('עודף')));
        expect(blob, isNot(contains(_l10n(code).posReceiptChange)));
      });
    }

    test('no slip, in any language, prints REMAKE or "instead of"', () {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = _l10n(code);
        final blob = _texts(_doc(code)).join('\n');
        expect(blob, isNot(contains(l10n.kdsEditRemake)), reason: code);
        for (final name in _names[code]!) {
          expect(
            blob,
            isNot(contains(l10n.kdsEditInsteadOf(name))),
            reason: code,
          );
        }
      }
    });

    test('an unsupported language code falls back to English', () {
      final fallback = _doc('en', labelCode: 'xx');
      final english = _doc('en');
      expect(_texts(fallback), _texts(english));
      expect(fallback.title, english.title);
    });

    test('the reason labels are the SAME shared mapping as '
        'orderEditReasonLabel, in every language', () {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = _l10n(code);
        final labels = kitchenChangeSlipLabelsFromL10n(l10n);
        for (final reason in kOrderEditReasonCodes) {
          expect(
            labels.reasonCodeLabel(reason),
            orderEditReasonLabel(l10n, reason),
            reason: '$code/$reason',
          );
        }
        expect(labels.reasonCodeLabel('not_a_code'), isNull);
      }
    });
  });

  group('O-6: the shared ticket labels name an edit-opened round', () {
    KdsTicketView editRound() => KdsTicketView(
      kitchenTicketId: 'kt-r2',
      stationId: KdsTicketMapper.unassignedStation,
      items: const [KdsItemView(name: 'Burger', quantity: 1)],
      status: KitchenTicketStatus.newTicket,
      orderNumber: '#A1B2C3',
      orderType: 'takeaway',
      roundId: 'r-2',
      roundNumber: 2,
      openedByEditNumber: 1,
    );

    for (final code in ['en', 'ar', 'he']) {
      test('$code: "Change N · Round M" through kitchenEditChangeNumber', () {
        final l10n = _l10n(code);
        final texts = _texts(
          buildKdsTicketPrintDocument(
            ticket: editRound(),
            labels: kitchenTicketPrintLabelsForLanguageCode(code),
          ),
        );
        expect(
          texts,
          contains(
            '${l10n.kitchenEditChangeNumber(1)} · ${l10n.kdsRoundLabel(2)}',
          ),
        );
        expect(texts.where((t) => t.contains(l10n.kdsAdditionLabel)), isEmpty);
      });
    }
  });

  group('raster direction and ink (Q-015)', () {
    test('the ar/he slips raster RTL, the en slip LTR', () {
      String dir(String code) => pp.baseDirectionForLines([
        for (final l in _escPos(code).lines.whereType<pp.PrintTextLine>())
          l.text,
      ]).name;
      expect(dir('ar'), pp.ReceiptTextDirection.rtl.name);
      expect(dir('he'), pp.ReceiptTextDirection.rtl.name);
      expect(dir('en'), pp.ReceiptTextDirection.ltr.name);
    });

    const rasterizer = FlutterReceiptRasterizer();

    void expectEveryBandInked(ReceiptRasterRender r) {
      for (final band in r.bands) {
        if (!band.expectsInk) continue;
        expect(
          r.inkInBand(band),
          greaterThan(0),
          reason:
              'line ${band.index} (${band.style.name}) '
              '"${band.text.trim()}" rendered NO ink in rows '
              '${band.startRow}..${band.endRow}',
        );
      }
    }

    void expectBandsTile(ReceiptRasterRender r) {
      expect(r.bands.first.startRow, 0);
      expect(r.bands.last.endRow, r.image.heightDots);
      for (var i = 1; i < r.bands.length; i++) {
        expect(r.bands[i].startRow, r.bands[i - 1].endRow);
      }
      for (final band in r.bands) {
        expect(band.endRow, greaterThan(band.startRow));
      }
    }

    for (final code in ['ar', 'he', 'en']) {
      test('$code: every band of the slip carries ink and the bands tile the '
          'bitmap', () async {
        final lines = _escPos(code).lines.whereType<pp.PrintTextLine>();
        final texts = [for (final l in lines) l.text];
        final render = await rasterizer.rasterizeDetailed(
          pp.ReceiptRasterRequest(
            lines: texts,
            styles: [for (final l in lines) l.style],
            widthDots: 576,
            direction: pp.baseDirectionForLines(texts),
            localeTag: code,
          ),
        );
        expect(render.bands, hasLength(texts.length));
        expectBandsTile(render);
        expectEveryBandInked(render);
      });

      test('$code: roll bands reconstruct the real slip bitmap with no '
          'command separators', () async {
        final source = _escPos(code);
        final textLines = source.lines.whereType<pp.PrintTextLine>().toList();
        final texts = [for (final line in textLines) line.text, ''];
        final image = await rasterizer.rasterize(
          pp.ReceiptRasterRequest(
            lines: texts,
            styles: [
              for (final line in textLines) line.style,
              pp.PrintLineStyle.normal,
            ],
            widthDots: 576,
            direction: pp.baseDirectionForLines(texts),
            localeTag: source.localeTag ?? '',
          ),
        );
        final out = await pp.rasterizeForMediaProfile(
          source,
          rasterizer: rasterizer,
          profile: pp.MediaProfile.continuous80,
        );
        final bands = out.lines.whereType<pp.PrintRasterImageLine>().toList();
        expect(bands.length, greaterThan(1));
        expect(bands.length, (image.heightDots + 255) ~/ 256);
        expect(bands.every((band) => band.widthBytes == 72), isTrue);
        expect(
          bands.take(bands.length - 1).map((band) => band.heightDots),
          everyElement(256),
        );
        expect(bands.last.heightDots, inInclusiveRange(1, 256));
        expect(
          bands.fold<int>(0, (sum, band) => sum + band.heightDots),
          image.heightDots,
        );
        expect(bands.expand((band) => band.data), orderedEquals(image.data));
        expect(out.lines.length, bands.length + 2);
        expect(out.lines[bands.length], isA<pp.PrintFeedLine>());
        expect(out.lines.last, isA<pp.PrintCutLine>());
        expect(out.lines.whereType<pp.PrintTextLine>(), isEmpty);

        final bytes = const pp.EscPosPrintAdapter().encode(
          out,
          pp.PrinterProfile.escPos80mm,
        );
        expect(bytes.take(5), [0x1b, 0x40, 0x1b, 0x74, 0]);
        final pixels = <int>[];
        var offset = 5;
        for (final band in bands) {
          expect(bytes.sublist(offset, offset + 8), [
            0x1d,
            0x76,
            0x30,
            0,
            72,
            0,
            band.heightDots & 0xff,
            band.heightDots >> 8,
          ]);
          final end = offset + 8 + band.widthBytes * band.heightDots;
          pixels.addAll(bytes.sublist(offset + 8, end));
          offset = end;
        }
        expect(pixels, orderedEquals(image.data));
        expect(bytes.sublist(offset), [0x1b, 0x64, 3, 0x1d, 0x56, 1]);
      });
    }
  });
}
