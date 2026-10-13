import 'package:restoflow_pos/src/data/online_order_inbox.dart';

const requestId = '10000000-0000-4000-8000-000000000001';
const canonicalId = '20000000-0000-4000-8000-000000000001';
const decisionId = '30000000-0000-4000-8000-000000000001';
const deviceId = '40000000-0000-4000-8000-000000000001';
const pinId = '50000000-0000-4000-8000-000000000001';
final inboxNow = DateTime.utc(2026, 10, 14, 12);

Map<String, dynamic> requestJson({String status = 'pending'}) => {
  'request_id': requestId,
  'status': status,
  'customer': {'name': 'زبون לדוגמה', 'phone': '+972501234567'},
  'notes': 'بدون بصل / בלי בצל',
  'created_at': inboxNow.subtract(const Duration(minutes: 3)).toIso8601String(),
  'expires_at': inboxNow.add(const Duration(minutes: 20)).toIso8601String(),
  'totals': {
    'currency_code': 'ILS',
    'subtotal_minor': 2800,
    'tax_total_minor': 140,
    'grand_total_minor': 2940,
  },
  'items': [
    {
      'menu_item_id': '60000000-0000-4000-8000-000000000001',
      'item_name_snapshot': 'وجبة / ארוחה',
      'quantity': 2,
      'unit_price_minor_snapshot': 1000,
      'line_total_minor': 2800,
      'modifiers': [
        {
          'modifier_option_id': '70000000-0000-4000-8000-000000000001',
          'modifier_id': '80000000-0000-4000-8000-000000000001',
          'option_name_snapshot': 'جبنة / גבינה',
          'quantity': 2,
          'price_minor_snapshot': 200,
        },
      ],
    },
  ],
  'canonical_order_id': status == 'accepted' ? canonicalId : null,
};

OnlineOrderRequest inboxRequest({String status = 'pending'}) =>
    OnlineOrderRequest.fromJson(requestJson(status: status));

OnlineInboxPage inboxPage({List<OnlineOrderRequest>? requests}) =>
    OnlineInboxPage(
      serverTime: inboxNow,
      requests: requests ?? [inboxRequest()],
    );

Map<String, dynamic> inboxPageJson() => {
  'ok': true,
  'server_time': inboxNow.toIso8601String(),
  'requests': [requestJson()],
  'has_more': false,
  'next_cursor': null,
};

Map<String, dynamic> decisionJson({String status = 'accepted'}) => {
  'ok': true,
  'request_id': requestId,
  'status': status,
  'canonical_order_id': status == 'accepted' ? canonicalId : null,
  'decision_id': decisionId,
  'replayed': false,
};

class FakeInboxRepository implements OnlineOrderInboxRepository {
  Future<OnlineInboxPage> Function(String?, OnlineInboxCursor?)? onFetch;
  Future<OnlineInboxDecisionResult> Function(OnlineInboxIntentCall)? onDecide;
  final fetches = <String?>[];
  final decisions = <OnlineInboxIntentCall>[];
  @override
  Future<OnlineInboxPage> fetch({
    String? requestId,
    OnlineInboxCursor? cursor,
  }) {
    fetches.add(requestId);
    return onFetch?.call(requestId, cursor) ?? Future.value(inboxPage());
  }

  @override
  Future<OnlineInboxDecisionResult> decide({
    required String requestId,
    required String decisionId,
    required OnlineOrderDecision decision,
    String? reason,
  }) {
    final call = OnlineInboxIntentCall(requestId, decisionId, decision, reason);
    decisions.add(call);
    return onDecide?.call(call) ??
        Future.value(
          OnlineInboxDecisionResult.fromJson(
            decisionJson(
              status: decision == OnlineOrderDecision.accept
                  ? 'accepted'
                  : 'rejected',
            ),
          ),
        );
  }
}

class OnlineInboxIntentCall {
  const OnlineInboxIntentCall(
    this.requestId,
    this.decisionId,
    this.decision,
    this.reason,
  );
  final String requestId;
  final String decisionId;
  final OnlineOrderDecision decision;
  final String? reason;
}
