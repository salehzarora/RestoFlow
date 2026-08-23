import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../data/kiosk_fixtures.dart';
import '../data/kiosk_order_submit.dart';
import '../state/kiosk_flow_controller.dart';

/// KIOSK-001-103 §11 — the PHYSICAL kiosk customer receipt.
///
/// Renders the exact FROZEN accepted order (the same snapshot the on-screen
/// slip shows — item/modifier names from the submit-time frozen displays,
/// integer minor-unit money already totalled by the server-accepted attempt;
/// nothing is recomputed here). Header identity is the AUTHORITATIVE
/// restaurant branding (Dashboard receipt logo raster when enabled, the real
/// restaurant name always) — NEVER the EMBER fixture. The kiosk order is
/// UNPAID by design, so the slip carries the "pay at cashier" stamp and no
/// payment claim. No dailySeq (the shared display code identifies the order).
pp.PrintDocument buildKioskReceiptDocument({
  required AppLocalizations l10n,
  required KioskOrderSnapshot order,
  required String restaurantName,
  required String lang,
  pp.LogoRaster? logoRaster,
  int columns = 48,
}) {
  final rtl = lang != 'en';
  final dir = rtl ? pp.PrintTextDirection.rtl : pp.PrintTextDirection.ltr;
  String money(int minor) => kioskFormatMinor(minor, lang);

  final frozen = {
    for (final d in order.lineDisplays ?? const <KioskFrozenLineDisplay>[])
      d.lineId: d,
  };

  final lines = <pp.PrintLine>[
    if (logoRaster != null) logoRaster.toPrintLine(),
    if (logoRaster != null) const pp.PrintFeedLine(1),
    pp.PrintTextLine(
      restaurantName,
      alignment: pp.PrintAlignment.center,
      emphasis: pp.TextEmphasis.bold,
      direction: dir,
      style: pp.PrintLineStyle.headingLarge,
    ),
    pp.PrintTextLine(
      order.code ?? '#${order.number.toString().padLeft(3, '0')}',
      alignment: pp.PrintAlignment.center,
      emphasis: pp.TextEmphasis.bold,
      direction: dir,
      style: pp.PrintLineStyle.subheading,
    ),
    pp.PrintTextLine(
      order.service == KioskServiceType.dineIn
          ? l10n.kioskDineIn
          : l10n.kioskTakeaway,
      alignment: pp.PrintAlignment.center,
      direction: dir,
      style: pp.PrintLineStyle.centered,
    ),
    if (order.table != null)
      pp.PrintTextLine(
        '${l10n.kioskTableLabel} ${order.table}',
        alignment: pp.PrintAlignment.center,
        direction: dir,
        style: pp.PrintLineStyle.centered,
      ),
    if (order.customerName.isNotEmpty)
      pp.PrintTextLine(
        order.customerName,
        alignment: pp.PrintAlignment.center,
        direction: dir,
        style: pp.PrintLineStyle.centered,
      ),
    pp.PrintTextLine('-' * columns, style: pp.PrintLineStyle.separator),
  ];

  for (final line in order.lines) {
    final display = frozen[line.lineId];
    // REAL accepted orders always carry frozen displays (094); the demo slip
    // has no printer, so an absent display would only occur in tests — the
    // honest fallback is the raw item id, never a live-menu lookup.
    final title = display?.itemName.of(lang) ?? line.itemId;
    lines.add(
      pp.PrintTextLine(
        _twoColumn(
          '${line.quantity}× $title',
          money(line.capturedUnitMinor * line.quantity),
          columns,
        ),
        direction: dir,
        style: pp.PrintLineStyle.item,
      ),
    );
    for (final option in display?.modifierNames ?? const []) {
      lines.add(
        pp.PrintTextLine(
          '  + ${option.of(lang)}',
          direction: dir,
          style: pp.PrintLineStyle.sub,
        ),
      );
    }
    final note = line.note.trim();
    if (note.isNotEmpty) {
      lines.add(
        pp.PrintTextLine(
          '  * $note',
          direction: dir,
          style: pp.PrintLineStyle.note,
        ),
      );
    }
  }

  lines.add(
    pp.PrintTextLine('-' * columns, style: pp.PrintLineStyle.separator),
  );
  if (order.subtotalMinor != null && order.taxMinor != null) {
    lines
      ..add(
        pp.PrintTextLine(
          _twoColumn(l10n.kioskSubtotal, money(order.subtotalMinor!), columns),
          direction: dir,
        ),
      )
      ..add(
        pp.PrintTextLine(
          _twoColumn(
            order.taxInclusive ? l10n.kioskTaxIncludedNote : l10n.kioskTax,
            money(order.taxMinor!),
            columns,
          ),
          direction: dir,
        ),
      );
  }
  lines
    ..add(
      pp.PrintTextLine(
        _twoColumn(l10n.kioskTotal, money(order.totalMinor), columns),
        emphasis: pp.TextEmphasis.bold,
        direction: dir,
        style: pp.PrintLineStyle.total,
      ),
    )
    ..add(pp.PrintTextLine('-' * columns, style: pp.PrintLineStyle.separator))
    ..add(
      pp.PrintTextLine(
        l10n.kioskPayAtCounter,
        alignment: pp.PrintAlignment.center,
        emphasis: pp.TextEmphasis.bold,
        direction: dir,
        style: pp.PrintLineStyle.centered,
      ),
    )
    ..add(
      pp.PrintTextLine(
        l10n.kioskPoweredBy(restaurantName),
        alignment: pp.PrintAlignment.center,
        direction: dir,
        style: pp.PrintLineStyle.centered,
      ),
    )
    ..add(const pp.PrintFeedLine(3))
    ..add(const pp.PrintCutLine());

  return pp.PrintDocument(lines, localeTag: lang);
}

/// Label/value across [columns] monospace cells (the shared receipt idiom);
/// wraps to two lines when the pair genuinely cannot fit.
String _twoColumn(String left, String right, int columns) {
  final pad = columns - left.length - right.length;
  if (pad < 1) return '$left\n$right';
  return '$left${' ' * pad}$right';
}
