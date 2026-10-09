/// ORDER-EDIT-001G — the "Order edits" report seam (`owner_order_edits`).
///
/// A SIBLING of the top-items and sales-series seams, not an extension of the
/// report: it answers its own question ("what changed on sent orders in this
/// window") from its own RPC, and a failure here must leave the KPIs beside it
/// intact.
library;

import '../analytics/analytics_range.dart';
import '../analytics/analytics_window.dart';
import '../analytics/dashboard_analytics_scope.dart';
import '../analytics/owner_order_edits_query_key.dart';
import 'demo_report.dart' show kDemoCurrencyCode;
import 'owner_order_edits.dart';

/// Loads the Order edits block for a window within a scope.
abstract class OwnerOrderEditsRepository {
  /// Loads one page of [range] (or [customWindow]) within [analyticsScope].
  ///
  /// [reasonCode] narrows only the edit list (one of the five reason codes or
  /// `none`); [cursor] is the previous page's `next_cursor`.
  Future<OwnerOrderEdits> loadOrderEdits({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    String? reasonCode,
    int limit = kOrderEditsPageSize,
    String? cursor,
  });
}

/// A failure loading the Order edits block.
///
/// Its own type so the Overview can show healthy KPIs beside a failed block.
class OwnerOrderEditsException implements Exception {
  const OwnerOrderEditsException(this.message);

  final String message;

  @override
  String toString() => 'OwnerOrderEditsException: $message';
}

/// The demo Order edits block: the MONEY_AND_TAX_SPEC §9.2 worked example.
///
/// One edit on one demo order — the burger changed (4000 out, 4000 in), the
/// fries removed (1500) and a lemonade added (900) — so the demo shows every
/// figure the block has and the identity the contract promises:
/// net = 4000 + 900 − 1500 − 4000 = −600, gross removed = 5500. Integer minor
/// units throughout (D-007). The demo has no date dimension, so every window
/// answers the same single edit, echoing its own wire token.
class DemoOwnerOrderEditsRepository implements OwnerOrderEditsRepository {
  const DemoOwnerOrderEditsRepository({this.failureMessage});

  /// When non-null, [loadOrderEdits] throws (drives the error state in tests).
  final String? failureMessage;

  static const OrderEditFigures _workedExample = OrderEditFigures(
    editCount: 1,
    editedOrderCount: 1,
    removedMinor: 1500,
    replacedOutMinor: 4000,
    replacedInMinor: 4000,
    addedMinor: 900,
    netChangeMinor: -600,
    grossRetiredMinor: 5500,
  );

  @override
  Future<OwnerOrderEdits> loadOrderEdits({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    String? reasonCode,
    int limit = kOrderEditsPageSize,
    String? cursor,
  }) async {
    final message = failureMessage;
    if (message != null) throw OwnerOrderEditsException(message);

    final window = customWindow ?? AnalyticsWindow.preset(range);
    const edit = OrderEditReportRow(
      orderEditId: 'demo-edit-1002-1',
      orderId: 'demo-ord-1002',
      orderCode: '#1002BB',
      editNumber: 1,
      orderStatus: 'preparing',
      orderType: 'dine_in',
      createdAtLabel: '12:55',
      currencyCode: kDemoCurrencyCode,
      figures: _workedExample,
      branchName: 'Downtown',
      staffName: 'Amira',
      reasonCode: 'customer_changed_mind',
      kitchenChannel: 'kds',
    );
    final filtered = reasonCode == null || reasonCode == edit.reasonCode
        ? const <OrderEditReportRow>[edit]
        : const <OrderEditReportRow>[];
    // One page holds everything, so a continuation is always empty.
    final page = cursor == null ? filtered : const <OrderEditReportRow>[];
    return OwnerOrderEdits(
      currencyCode: kDemoCurrencyCode,
      currencyCodes: const <String>[kDemoCurrencyCode],
      rangeWire: window.wire,
      enabledInScope: true,
      staffVisible: true,
      summary: _workedExample,
      byReason: const <OrderEditReasonRow>[
        OrderEditReasonRow(
          reasonCode: 'customer_changed_mind',
          figures: _workedExample,
        ),
      ],
      byStaff: const <OrderEditStaffRow>[
        OrderEditStaffRow(staffName: 'Amira', figures: _workedExample),
      ],
      edits: List.unmodifiable(page.take(limit)),
      count: page.length < limit ? page.length : limit,
      matching: filtered.length,
    );
  }
}
