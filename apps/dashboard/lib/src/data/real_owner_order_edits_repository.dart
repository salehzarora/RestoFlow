/// Real-mode Order edits block (ORDER-EDIT-001G).
///
/// Reads `public.owner_order_edits` (API_CONTRACT §4.47) over the SAME
/// authenticated transport the rest of the real dashboard uses. The RPC is
/// financial-read gated, tenant-scoped, branch-local and integer-minor
/// (D-007); this class only maps it. No figure is recomputed here: each edit's
/// figures are the server's, computed as that edit wrote them (MONEY §13).
///
/// NOT-DEPLOYED-YET vs FAILED, kept distinct (the convention every real owner
/// repository follows): only a PGRST202/404 "could not find the function"
/// degrades to [OwnerOrderEdits.unavailable]. An auth denial (42501), an
/// argument rejection (22023) and `permission_denied` are NEVER softened into
/// "unavailable", and an empty window is EMPTY DATA, never a capability
/// problem.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../analytics/analytics_range.dart';
import '../analytics/analytics_window.dart';
import '../analytics/dashboard_analytics_scope.dart';
import '../analytics/owner_order_edits_query_key.dart';
import 'owner_order_edits.dart';
import 'owner_order_edits_repository.dart';

/// The entity token the reader stamps on every answer.
const String kOwnerOrderEditsEntity = 'owner_order_edits';

/// Reads [OwnerOrderEdits] from `public.owner_order_edits`.
class RealOwnerOrderEditsRepository implements OwnerOrderEditsRepository {
  const RealOwnerOrderEditsRepository({this.scope, this.transport});

  /// The active membership. Null in demo mode or before one is selected.
  final MembershipContext? scope;

  /// The AUTHENTICATED transport. Null => not wired (fail-closed).
  final SyncRpcTransport? transport;

  @override
  Future<OwnerOrderEdits> loadOrderEdits({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    String? reasonCode,
    int limit = kOrderEditsPageSize,
    String? cursor,
  }) async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const RealRepoNotWiredError(
        'owner-order-edits: no authenticated transport/scope - real read not wired',
      );
    }
    // The scope on the wire is the scope in the KEY; the ORGANIZATION stays the
    // membership's (the authorization anchor), and a key claiming a different
    // one fails closed here rather than becoming a cross-org tuple on the wire.
    final selected = analyticsScope ?? DashboardAnalyticsScope.coveredBy(m);
    if (selected.organizationId != m.organizationId) {
      throw const OwnerOrderEditsException(
        'owner_order_edits: analytics scope organization does not match the membership',
      );
    }

    final window = customWindow ?? AnalyticsWindow.preset(range);
    final Object? raw;
    try {
      raw = await t.invoke('owner_order_edits', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': selected.restaurantId,
        'p_branch_id': selected.branchId,
        // ONE mapper for every owner RPC: a preset sends only p_range, a custom
        // window sends only the two dates.
        ...analyticsWindowParams(window),
        'p_limit': limit,
        if (reasonCode != null) 'p_reason_code': reasonCode,
        if (cursor != null) 'p_cursor': cursor,
      });
    } on SyncTransportException catch (e) {
      if (_isMissingRpc(e)) return OwnerOrderEdits.unavailable(window.wire);
      throw const OwnerOrderEditsException(
        'owner_order_edits transport failure',
      );
    }
    if (raw is! Map || raw['ok'] != true) {
      // A DEPLOYED reader that refused the caller (permission_denied for
      // kitchen staff) is not a missing-RPC case. Fail closed.
      throw const OwnerOrderEditsException('owner_order_edits rejected');
    }
    if (raw['entity'] != kOwnerOrderEditsEntity) {
      throw const OwnerOrderEditsException('owner_order_edits entity mismatch');
    }
    return _fromPayload(raw, window.wire);
  }

  static OwnerOrderEdits _fromPayload(
    Map<Object?, Object?> raw,
    String fallbackWire,
  ) {
    final currency = (raw['currency_code'] ?? '').toString();
    final staffVisible = raw['staff_visible'] == true;

    final codes = <String>[
      for (final c in _list(raw['currency_codes']))
        if (c is String && c.isNotEmpty) c,
    ];

    final byReason = <OrderEditReasonRow>[
      for (final r in _list(raw['by_reason']))
        if (r is Map)
          OrderEditReasonRow(
            reasonCode: _strOrNull(r['reason_code']),
            figures: _figures(r),
          ),
    ];

    // Defence in depth: a caller below manager gets no staff rows even if a
    // server ever sent them (the server already sends `[]`).
    final byStaff = <OrderEditStaffRow>[
      if (staffVisible)
        for (final r in _list(raw['by_staff']))
          if (r is Map)
            OrderEditStaffRow(
              staffName: _strOrNull(r['staff_name']),
              figures: _figures(r),
            ),
    ];

    final edits = <OrderEditReportRow>[];
    for (final e in _list(raw['edits'])) {
      if (e is! Map) continue;
      final id = _strOrNull(e['order_edit_id']);
      final code = _strOrNull(e['order_code']);
      // A row without an identity or a display code is unrenderable; skipping
      // it is honest, inventing one is not.
      if (id == null || code == null) continue;
      edits.add(
        OrderEditReportRow(
          orderEditId: id,
          orderId: (e['order_id'] ?? '').toString(),
          orderCode: code,
          editNumber: _int(e['edit_number']),
          orderStatus: (e['order_status'] ?? '').toString(),
          orderType: (e['order_type'] ?? '').toString(),
          createdAtLabel: (e['created_at'] ?? '').toString(),
          currencyCode: (e['currency_code'] ?? currency).toString(),
          figures: _figures(e),
          branchName: _strOrNull(e['branch_name']),
          staffName: staffVisible ? _strOrNull(e['staff_name']) : null,
          reasonCode: _strOrNull(e['reason_code']),
          kitchenChannel: _strOrNull(e['kitchen_channel']),
          createdAtUtc: _strOrNull(e['created_at_utc']),
          businessDay: _strOrNull(e['business_day']),
          timezone: _strOrNull(e['timezone']),
        ),
      );
    }

    final summaryRaw = raw['summary'];
    return OwnerOrderEdits(
      currencyCode: currency,
      currencyCodes: List.unmodifiable(codes),
      // The server's own echo — it answers `custom` for a custom window.
      rangeWire: (raw['range'] ?? fallbackWire).toString(),
      enabledInScope: raw['order_edit_enabled_in_scope'] == true,
      staffVisible: staffVisible,
      summary: summaryRaw is Map ? _figures(summaryRaw) : OrderEditFigures.zero,
      byReason: List.unmodifiable(byReason),
      byStaff: List.unmodifiable(byStaff),
      edits: List.unmodifiable(edits),
      count: _int(raw['count']),
      matching: _int(raw['matching']),
      hasMore: raw['has_more'] == true,
      nextCursor: _strOrNull(raw['next_cursor']),
    );
  }

  static OrderEditFigures _figures(Map<Object?, Object?> m) => OrderEditFigures(
    editCount: _int(m['edit_count']),
    editedOrderCount: _int(m['edited_order_count']),
    removedMinor: _int(m['removed_minor']),
    replacedOutMinor: _int(m['replaced_out_minor']),
    replacedInMinor: _int(m['replaced_in_minor']),
    addedMinor: _int(m['added_minor']),
    netChangeMinor: _int(m['net_change_minor']),
    grossRetiredMinor: _int(m['gross_retired_minor']),
  );

  static List<Object?> _list(Object? v) => v is List ? v : const <Object?>[];

  static String? _strOrNull(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  /// Integer minor units, defensively. Money never becomes a double (D-007);
  /// a malformed value reads as zero rather than throwing the whole block away.
  static int _int(Object? v) => switch (v) {
    final int i => i,
    final num n => n.toInt(),
    _ => int.tryParse('$v') ?? 0,
  };

  /// Whether [e] means the FUNCTION does not exist yet, as opposed to a
  /// permission / tenant / auth denial. Same rule and same order of checks as
  /// the sibling owner repositories — one definition of "missing".
  static bool _isMissingRpc(SyncTransportException e) {
    if (e.kind == SyncTransportErrorKind.auth) return false;
    final code = (e.code ?? '').toUpperCase();
    if (code == 'PGRST202' || code == '404') return true;
    final message = (e.message ?? '').toLowerCase();
    return message.contains('could not find the function') ||
        (message.contains('function') && message.contains('does not exist'));
  }
}
