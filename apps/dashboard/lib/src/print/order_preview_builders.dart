/// Builds the reprint-center preview documents from a stored [OrderDetail]
/// (ORDERS-HISTORY-001).
///
///  * [buildOrderReceiptPreview] — a customer receipt built ONLY from stored
///    order/payment values (D-008): it never recomputes a total from live menu
///    prices, never records a payment, never mutates the order/shift/cash.
///  * [buildOrderKitchenTicketPreview] — a MONEY-FREE kitchen ticket: order
///    code, type/table/customer, the aggregated whole-order kitchen count
///    (KITCHEN-COUNT-001), items / modifiers / prep / notes — and NO price,
///    total, tax or payment anywhere.
library;

import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_history_models.dart';
import '../format/money_format.dart';
import 'print_document.dart';

/// The localized order-type label (dine-in / takeaway), or the raw value.
String _orderTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'dine_in' => l10n.posOrderTypeDineIn,
  'takeaway' => l10n.posOrderTypeTakeaway,
  _ => type,
};

/// The localized payment-method label, or the raw value.
String _paymentMethodLabel(AppLocalizations l10n, String method) =>
    switch (method) {
      'cash' => l10n.posPaymentMethodCash,
      'card' => l10n.posPaymentMethodCard,
      'bit' => l10n.posPaymentMethodBit,
      'external' => l10n.posPaymentMethodExternal,
      _ => method,
    };

/// A compact "×N" suffix for a repeated modifier/item (N>1 only).
String _timesSuffix(int quantity) => quantity > 1 ? ' ×$quantity' : '';

/// Builds a customer-receipt [PrintDocument] from [detail]'s STORED values.
/// Money is formatted (never recomputed) with the order's own currency.
PrintDocument buildOrderReceiptPreview(
  AppLocalizations l10n,
  OrderDetail detail,
) {
  String money(int minor) =>
      MoneyFormatter.formatMinor(minor, detail.currencyCode);
  final lines = <PrintLine>[
    PrintLine.title(detail.branchName ?? l10n.dashboardAppTitle),
    PrintLine.center(detail.orderCode),
    if (detail.createdAtLabel != null && detail.createdAtLabel!.isNotEmpty)
      PrintLine.note(detail.createdAtLabel!),
    PrintLine.rule(),
    PrintLine.kv(
      l10n.posOrderTypeLabel,
      _orderTypeLabel(l10n, detail.orderType),
    ),
    if (detail.tableLabel != null && detail.tableLabel!.isNotEmpty)
      PrintLine.kv(l10n.posTableLabel, detail.tableLabel!),
    if (detail.customerName != null && detail.customerName!.isNotEmpty)
      PrintLine.kv(l10n.ordersCustomerLabel, detail.customerName!),
    if (detail.staffName != null && detail.staffName!.isNotEmpty)
      PrintLine.kv(l10n.ordersStaffLabel, detail.staffName!),
    PrintLine.rule(),
  ];

  for (final item in detail.items) {
    lines.add(
      PrintLine.item(
        '${item.quantity} × ${item.name}',
        money(item.lineTotalMinor),
      ),
    );
    for (final mod in item.modifiers) {
      lines.add(
        PrintLine.sub('+ ${mod.optionName}${_timesSuffix(mod.quantity)}'),
      );
    }
    final note = item.notes;
    if (note != null && note.isNotEmpty) {
      lines.add(PrintLine.sub('» $note'));
    }
  }

  lines
    ..add(PrintLine.rule())
    ..add(PrintLine.kv(l10n.ordersSubtotalLabel, money(detail.subtotalMinor)));
  if (detail.discountTotalMinor > 0) {
    lines.add(
      PrintLine.kv(
        l10n.ordersDiscountLabel,
        '-${money(detail.discountTotalMinor)}',
      ),
    );
  }
  if (detail.taxTotalMinor > 0) {
    lines.add(PrintLine.kv(l10n.ordersTaxLabel, money(detail.taxTotalMinor)));
  }
  lines
    ..add(
      PrintLine.kv(
        l10n.posReceiptTotal,
        money(detail.grandTotalMinor),
        emphasised: true,
      ),
    )
    ..add(PrintLine.rule());

  final pay = detail.completedPayment;
  if (pay != null) {
    lines.add(
      PrintLine.kv(
        _paymentMethodLabel(l10n, pay.method),
        money(pay.amountMinor),
      ),
    );
    if (pay.changeMinor > 0) {
      lines.add(PrintLine.kv(l10n.ordersChangeLabel, money(pay.changeMinor)));
    }
    final receipt = pay.receiptNumber ?? detail.receiptNumber;
    if (receipt != null && receipt.isNotEmpty) {
      lines.add(PrintLine.kv(l10n.posReceiptNumberLabel, receipt));
    }
  } else {
    lines.add(PrintLine.center(l10n.dashboardUnpaid));
  }

  lines
    ..add(PrintLine.rule())
    ..add(PrintLine.note(l10n.posReceiptThankYou));

  return PrintDocument(title: l10n.receiptPreviewTitle, lines: lines);
}

/// Builds a MONEY-FREE kitchen-ticket [PrintDocument] from [detail]. Carries the
/// order code, type/table/customer, the aggregated whole-order kitchen count,
/// and items / modifiers / prep / notes — and NO price, total, tax or payment.
PrintDocument buildOrderKitchenTicketPreview(
  AppLocalizations l10n,
  OrderDetail detail,
) {
  final lines = <PrintLine>[
    PrintLine.title(detail.orderCode),
    PrintLine.kv(
      l10n.posOrderTypeLabel,
      _orderTypeLabel(l10n, detail.orderType),
    ),
    if (detail.tableLabel != null && detail.tableLabel!.isNotEmpty)
      PrintLine.kv(l10n.posTableLabel, detail.tableLabel!),
    if (detail.customerName != null && detail.customerName!.isNotEmpty)
      PrintLine.kv(l10n.ordersCustomerLabel, detail.customerName!),
  ];

  // The whole-order kitchen count total (KITCHEN-COUNT-001), money-free.
  final counts = aggregateKitchenCounts(detail);
  if (counts.isNotEmpty) {
    lines.add(PrintLine.rule());
    for (final c in counts) {
      lines.add(
        PrintLine.title(
          l10n.kdsMeatTotalLabel(formatCountQuantity(c.quantity), c.unit),
        ),
      );
    }
  }

  lines.add(PrintLine.rule());
  for (final item in detail.items) {
    lines.add(PrintLine.item('${item.quantity} × ${item.name}', ''));
    for (final mod in item.modifiers) {
      lines.add(
        PrintLine.sub('+ ${mod.optionName}${_timesSuffix(mod.quantity)}'),
      );
    }
    for (final prep in item.prepComponents) {
      final unit = prep.unit;
      final qty = formatCountQuantity(prep.quantity);
      lines.add(
        PrintLine.sub(
          '· ${prep.name} $qty${unit != null && unit.isNotEmpty ? ' $unit' : ''}',
        ),
      );
    }
    final note = item.notes;
    if (note != null && note.isNotEmpty) {
      lines.add(PrintLine.sub('» $note'));
    }
  }

  return PrintDocument(title: l10n.kdsTicketPreviewTitle, lines: lines);
}
