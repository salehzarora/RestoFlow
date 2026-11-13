import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/activity/activity_log_screen.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/audit_action_registry.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_dashboard/src/data/currency_breakdown_repository.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart';
import 'package:restoflow_dashboard/src/print/order_preview_builders.dart';
import 'package:restoflow_dashboard/src/print/print_document.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-DASHBOARD-VERIFICATION — request §4: a
/// TEST provider attempt never reaches Dashboard money or the tenant Activity
/// log.
///
/// The accepted 001D contract keeps a TEST card attempt on PRIVATE surfaces
/// only: the ledger (`app.card_provider_attempts`), the private events
/// (`test.card_attempt_denied`, `test.card_recording_refused`) and operator
/// evidence. It writes no payments row, no receipt and no tenant
/// `audit_events` row; it classifies as `test_<state>` and never as
/// `approved_unrecorded`. The Dashboard reads money only through the reporting
/// RPCs. This file proves the client half of that with ONE recording fake
/// server:
///
///   T1/T2 a differential. World A serves LIVE data only; world B serves the
///         same LIVE data plus TEST attempts on every private channel. The
///         Overview (today, last 7 days), Orders history (all / card /
///         unpaid), order O's drawer and receipt preview and the Activity log
///         render identical text from identical mapped models, O stays unpaid,
///         and every RPC called is an allowlisted reporting / audit read —
///         never a private channel.
///   T3    the Activity-log feed is identical in both worlds and the screen
///         shows only the LIVE rows.
///   T4    a static scan of apps/dashboard/lib: no private card channel, TEST
///         classification or provider field is named anywhere; card_attempt
///         lives only in the audit registry and presenter; no test. /
///         operator. / security. action is registered.
///   T5    a LIVE approved-but-unrecorded incident is visible (approved and
///         recording-refused rows, O unpaid) while a TEST attempt for the same
///         O shows nothing (the TEST world renders exactly what a LIVE-only
///         render of the same feed does); a TEST token in a projected state
///         key never borrows a LIVE state label; title and tone follow the
///         action (TEST exclusion is server-enforced).
///   T6    the revoked-device carve-out row (`sync.operation_rejected`,
///         reason `revoked_device`) shows no card title, card field or money.
///
/// TEST attempts exist ONLY on the fake server's private channels: no TEST
/// payment of any kind is simulated. The Overview Daily-summary
/// `dashboardCashCollected` row and the mixed-currency split are the known,
/// separate DASHBOARD-COLLECTED-LABEL-001: nothing here asserts them as
/// correct (the differential only says world B renders what world A does),
/// and the `sales_summary` fallback chain is never served or entered.
const List<String> _locales = ['en', 'ar', 'he'];

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

// ===========================================================================
// The synthetic LIVE dataset. The caller's organization has one restaurant
// and one branch; a second, FOREIGN organization exists on the same server
// and refuses this caller, exactly as the server's authorization would.
// ===========================================================================

const _org = 'org-live';
const _foreignOrg = 'org-foreign';
const _restaurant = 'rest-live';
const _branch = 'branch-main';

/// Order O — served at a table and still UNPAID in the LIVE data. Every TEST
/// attempt of world B names it.
const _ordOpen = 'ord-open';
const _ordCash = 'ord-cash';
const _ordCard = 'ord-card';
const _ordLate = 'ord-late';

const _membership = MembershipContext(
  id: 'membership-owner',
  organizationId: _org,
  organizationName: 'Live Org',
  restaurantId: _restaurant,
  restaurantName: 'Rest One',
  branchId: _branch,
  branchName: 'Main',
  role: MembershipRole.orgOwner,
  status: 'active',
);

/// ONE instance for the file: `RuntimeConfig` has no `==`.
final _realMode = RuntimeConfig.test(isDemoMode: false);

typedef _Item = ({String name, int quantity, int unitMinor});
typedef _Tender = ({String method, int tenderedMinor, int changeMinor});

class _LiveOrder {
  const _LiveOrder({
    required this.id,
    required this.code,
    required this.status,
    required this.type,
    required this.createdAt,
    required this.items,
    this.table,
    this.tender,
  });

  final String id;
  final String code;
  final String status;
  final String type;
  final String createdAt;
  final List<_Item> items;
  final String? table;

  /// The ONE completed payment (always the full total), or null when unpaid.
  final _Tender? tender;

  int get totalMinor =>
      items.fold<int>(0, (sum, i) => sum + i.quantity * i.unitMinor);

  int get itemCount => items.fold<int>(0, (sum, i) => sum + i.quantity);
}

/// Newest first, as `owner_order_history` returns them. Today's money:
/// billed 185.00 = 28.00 + 65.00 + 50.00 + 42.00; collected 120.00 = cash
/// 70.00 + card 50.00; O's 65.00 is billed but unpaid.
const List<_LiveOrder> _liveOrders = [
  _LiveOrder(
    id: _ordLate,
    code: '#LATEWK',
    status: 'completed',
    type: 'dine_in',
    createdAt: '2026-10-31 14:10',
    table: 'T2',
    items: [
      (name: 'Salad', quantity: 1, unitMinor: 2000),
      (name: 'Lemonade', quantity: 1, unitMinor: 800),
    ],
    tender: (method: 'cash', tenderedMinor: 2800, changeMinor: 0),
  ),
  _LiveOrder(
    id: _ordOpen,
    code: '#OPENTB',
    status: 'served',
    type: 'dine_in',
    createdAt: '2026-10-31 13:05',
    table: 'T4',
    items: [
      (name: 'Burger', quantity: 1, unitMinor: 2100),
      (name: 'Salad', quantity: 1, unitMinor: 2000),
      (name: 'Lemonade', quantity: 3, unitMinor: 800),
    ],
  ),
  _LiveOrder(
    id: _ordCard,
    code: '#CARDTK',
    status: 'completed',
    type: 'takeaway',
    createdAt: '2026-10-31 12:00',
    items: [(name: 'Family meal', quantity: 1, unitMinor: 5000)],
    tender: (method: 'card', tenderedMinor: 5000, changeMinor: 0),
  ),
  _LiveOrder(
    id: _ordCash,
    code: '#CASHMR',
    status: 'completed',
    type: 'dine_in',
    createdAt: '2026-10-31 09:15',
    table: 'T1',
    items: [(name: 'Burger', quantity: 2, unitMinor: 2100)],
    tender: (method: 'cash', tenderedMinor: 5000, changeMinor: 800),
  ),
];

const List<String> _allOrderIds = [_ordLate, _ordOpen, _ordCard, _ordCash];

// --- the tenant audit feed (what `owner_audit_events` projects) -------------

const _evtPayLate = 'evt-pay-late';
const _evtOrderOpen = 'evt-order-open';
const _evtPayCard = 'evt-pay-card';
const _evtCardApproved = 'evt-card-approved';
const _evtCardStarted = 'evt-card-started';
const _evtPayCash = 'evt-pay-cash';
const _evtShiftOpen = 'evt-shift-open';
const _evtIncidentStarted = 'evt-incident-started';
const _evtIncidentApproved = 'evt-incident-approved';
const _evtIncidentRefused = 'evt-incident-refused';
const _evtSyncProjected = 'evt-sync-projected';
const _evtSyncWriter = 'evt-sync-writer';

Map<String, Object?> _auditRow(
  String id,
  String action,
  String category,
  String at, {
  Map<String, Object?> newValues = const {},
  String? reason,
}) => {
  'event_id': id,
  'action': action,
  'category': category,
  'occurred_at': at,
  'actor_name': 'Amira',
  'restaurant_name': 'Rest One',
  'branch_name': 'Main',
  'device_label': 'Front till',
  'reason': reason,
  'old_values': null,
  'new_values': newValues,
};

/// The LIVE day, newest first. The LIVE card sale of `#CARDTK` went through
/// the provider (started, approved) and was recorded (payment.recorded).
final List<Map<String, Object?>> _liveFeed = [
  _auditRow(
    _evtPayLate,
    'payment.recorded',
    'payments',
    '2026-10-31 14:12',
    newValues: {'amount_minor': 2800, 'tendered_minor': 2800},
  ),
  _auditRow(
    _evtOrderOpen,
    'order.submitted',
    'orders',
    '2026-10-31 13:05',
    newValues: {'grand_total_minor': 6500, 'order_type': 'dine_in'},
  ),
  _auditRow(
    _evtPayCard,
    'payment.recorded',
    'payments',
    '2026-10-31 12:02',
    newValues: {'amount_minor': 5000, 'tendered_minor': 5000},
  ),
  _auditRow(
    _evtCardApproved,
    'card_attempt.approved',
    'payments',
    '2026-10-31 12:01',
    newValues: {'attempt_state': 'approved', 'release_requested': false},
  ),
  _auditRow(
    _evtCardStarted,
    'card_attempt.started',
    'payments',
    '2026-10-31 12:00',
    newValues: {
      'attempt_state': 'sent',
      'mode': 'live',
      'amount_minor': 5000,
      'currency_code': 'ILS',
    },
  ),
  _auditRow(
    _evtPayCash,
    'payment.recorded',
    'payments',
    '2026-10-31 09:20',
    newValues: {
      'amount_minor': 4200,
      'tendered_minor': 5000,
      'change_minor': 800,
    },
  ),
  _auditRow(
    _evtShiftOpen,
    'shift.opened',
    'shifts',
    '2026-10-31 08:00',
    newValues: {'opening_float_minor': 10000},
  ),
];

/// T5 — a day with NO card activity at all, so a card title can only come
/// from the attempt under test.
final List<Map<String, Object?>> _quietFeed = [
  for (final row in _liveFeed)
    if (const {
      _evtOrderOpen, // order.submitted (O)
      _evtPayCash, // payment.recorded (the morning cash sale)
      _evtShiftOpen, // shift.opened
    }.contains(row['event_id']))
      row,
];

/// T5 — the LIVE approved-but-unrecorded incident for O: the provider
/// approved, the recording was refused, and NO payment.recorded follows.
final List<Map<String, Object?>> _incidentFeed = [
  _auditRow(
    _evtIncidentRefused,
    'card_attempt.recording_refused',
    'payments',
    '2026-10-31 13:22',
    newValues: {'refusal_code': 'conflict'},
  ),
  _auditRow(
    _evtIncidentApproved,
    'card_attempt.approved',
    'payments',
    '2026-10-31 13:21',
    newValues: {'attempt_state': 'approved', 'release_requested': false},
  ),
  _auditRow(
    _evtIncidentStarted,
    'card_attempt.started',
    'payments',
    '2026-10-31 13:20',
    newValues: {
      'attempt_state': 'sent',
      'mode': 'live',
      'amount_minor': 6500,
      'currency_code': 'ILS',
    },
  ),
  ..._quietFeed,
];

/// T6 — the revoked-device carve-out. The server writes
/// `{local_operation_id, operation_type, reason}` and projects `{}` for
/// sync.* (no detail); the fake sends BOTH shapes, the writer one carrying a
/// TEST attempt identity, to prove the presentation holds either way.
final List<Map<String, Object?>> _carveOutFeed = [
  _auditRow(
    _evtSyncWriter,
    'sync.operation_rejected',
    'sync',
    '2026-10-31 15:01',
    reason: 'revoked_device',
    newValues: {
      'local_operation_id': 'MARKER-ATTEMPT-ID',
      'operation_type': 'payment.create',
      'reason': 'revoked_device',
    },
  ),
  _auditRow(
    _evtSyncProjected,
    'sync.operation_rejected',
    'sync',
    '2026-10-31 15:00',
    reason: 'revoked_device',
  ),
  ..._liveFeed,
];

// --- the private channels: world B's TEST attempts --------------------------

/// Deliberately MORE than the real ledger would hold: its test-shape CHECK
/// keeps a TEST row's order, provider reference and card fields NULL. The fake
/// names O, with O's exact total on the approved attempt, so that any leak
/// into money would turn O paid. Every classification is `test_<state>` and
/// nothing is recorded (001D: never approved_unrecorded).
const List<Map<String, Object?>> _testAttempts = [
  {
    'attempt_id': 'MARKER-ATTEMPT-ID',
    'mode': 'test',
    'attempt_state': 'approved',
    'classification': 'test_approved',
    'recorded': false,
    'payment_id': null,
    'order_id': _ordOpen,
    'amount_minor': 6500,
    'currency_code': 'ILS',
    'provider_reference': 'MARKER-PROVIDER-REFERENCE',
    'terminal_ref': 'MARKER-TERMINAL-REF',
    'credential_ref': 'MARKER-CREDENTIAL-REF',
    'merchant_key': 'MARKER-MERCHANT-KEY',
    'card_last4': 'MARKER-LAST-FOUR',
  },
  {
    'attempt_id': 'MARKER-ATTEMPT-DECLINED',
    'mode': 'test',
    'attempt_state': 'declined',
    'classification': 'test_declined',
    'recorded': false,
    'payment_id': null,
    'order_id': _ordOpen,
    'amount_minor': 1111,
    'currency_code': 'ILS',
  },
  {
    'attempt_id': 'MARKER-ATTEMPT-UNKNOWN',
    'mode': 'test',
    'attempt_state': 'unknown',
    'classification': 'test_unknown',
    'anomaly_code': 'amount_mismatch',
    'recorded': false,
    'payment_id': null,
    'order_id': _ordOpen,
    'amount_minor': 2222,
    'currency_code': 'ILS',
  },
  {
    'attempt_id': 'MARKER-ATTEMPT-RELEASED',
    'mode': 'test',
    'attempt_state': 'released',
    'classification': 'test_released',
    'recorded': false,
    'payment_id': null,
    'order_id': _ordOpen,
    'amount_minor': 3333,
    'currency_code': 'ILS',
  },
];

/// The two private TEST events, in their CHECK-constrained detail shapes.
const List<Map<String, Object?>> _testPrivateEvents = [
  {
    'action': 'test.card_attempt_denied',
    'mode': 'test',
    'detail': {'rpc': 'MARKER-RPC-NAME', 'denied_reason': 'no_open_shift'},
  },
  {
    'action': 'test.card_recording_refused',
    'mode': 'test',
    'attempt_id': 'MARKER-ATTEMPT-ID',
    'detail': <String, Object?>{},
  },
];

/// Text that may only exist if a TEST attempt leaked: the markers, the TEST
/// classifications and the invented TEST amounts (11.11 / 22.22 / 33.33).
const List<String> _testLeakMarkers = [
  'MARKER-',
  'test_approved',
  'test_declined',
  'test_unknown',
  'test_released',
  '11.11',
  '22.22',
  '33.33',
];

// ===========================================================================
// The fake server.
// ===========================================================================

/// The reporting / audit reads the Dashboard flows may call. The two `list_*`
/// reads are the tenant-structure and staff-name enumerations behind the
/// scope selector and the Activity-log filters — no money, no card channel.
const Set<String> _reportingRpcAllowlist = {
  'owner_report_range',
  'owner_report_currency_breakdown',
  'owner_sales_series',
  'owner_top_items',
  'owner_order_edits',
  'owner_order_history',
  'owner_order_detail',
  'owner_audit_events',
  'list_org_structure',
  'list_staff',
};

/// The 001D private surfaces, by name.
bool _isPrivateChannel(String function) =>
    function == 'owner_card_attempts' ||
    function == 'card_attempt_context' ||
    function.contains('card_attempt') ||
    function.contains('card_provider') ||
    function.contains('payment_terminal');

enum _World { liveOnly, liveWithTest }

/// Answers every RPC the flows call from the LIVE dataset and every private
/// channel from world B's TEST attempts, recording every call. A read scoped
/// to any organization but the caller's is refused (the foreign tenant). Each
/// answer is round-tripped through JSON so the Dashboard sees exactly decoded
/// wire data.
class _FakeServer implements SyncRpcTransport {
  _FakeServer(this.world, {List<Map<String, Object?>>? audit})
    : audit = audit ?? _liveFeed;

  final _World world;
  final List<Map<String, Object?>> audit;

  /// Every function called, in order.
  final List<String> calls = <String>[];

  /// The params of every call, in the same order.
  final List<Map<String, dynamic>> received = <Map<String, dynamic>>[];

  /// The private-channel calls alone. Must stay empty.
  final List<String> privateCalls = <String>[];

  bool get _withTest => world == _World.liveWithTest;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    received.add(Map<String, dynamic>.of(params));
    if (_isPrivateChannel(function)) {
      privateCalls.add(function);
      return _json(_privateAnswer(function));
    }
    final organization = params['p_organization_id'];
    if (organization != null && organization != _org) {
      return _json({'ok': false, 'error': 'permission_denied'});
    }
    final Object? answer = switch (function) {
      'owner_report_range' => _reportRange(params['p_range']),
      'owner_report_currency_breakdown' => _currencyBreakdown(params),
      'owner_sales_series' => _salesSeries(params['p_range']),
      'owner_top_items' => _topItems(params['p_range']),
      'owner_order_edits' => _orderEdits(params['p_range']),
      'owner_order_history' => _history(params),
      'owner_order_detail' => _detail(params['p_order_id']),
      'owner_audit_events' => <String, Object?>{
        'ok': true,
        'currency_code': 'ILS',
        'events': audit,
        'has_more': false,
        'next_cursor': null,
      },
      'list_org_structure' => _orgStructure,
      'list_staff' => _staff,
      _ => null,
    };
    if (answer == null) {
      // Not a missing-function signature, so no repository falls back.
      throw SyncTransportException(
        SyncTransportErrorKind.server,
        code: 'XX000',
        message: 'not served by the 001G fake server: $function',
      );
    }
    return _json(answer);
  }

  Map<String, Object?> _privateAnswer(String function) {
    final attempts = _withTest ? _testAttempts : const <Map<String, Object?>>[];
    return {
      'ok': true,
      'mode': 'test',
      if (function == 'card_attempt_context')
        'attempt': attempts.isEmpty ? null : attempts.first,
      'attempts': attempts,
      'events': _withTest ? _testPrivateEvents : const <Map<String, Object?>>[],
      'terminals': [
        if (_withTest)
          {
            'terminal_ref': 'MARKER-TERMINAL-REF',
            'credential_ref': 'MARKER-CREDENTIAL-REF',
            'binding_mode': 'test',
          },
      ],
    };
  }
}

Object? _json(Object? value) => jsonDecode(jsonEncode(value));

Map<String, Object?> _reportRange(Object? range) =>
    range == 'last7' ? _last7Report() : _todayReport();

Map<String, Object?> _closedShift(
  String id,
  String opened,
  String closed, {
  required int expectedMinor,
  required int countedMinor,
  required int orders,
  required int collectedMinor,
  required int cashSalesMinor,
}) => {
  'shift_id': id,
  'branch_name': 'Main',
  'opened_at': opened,
  'closed_at': closed,
  'opened_by_name': 'Amira',
  'closed_by_name': 'Amira',
  'expected_cash_minor': expectedMinor,
  'counted_cash_minor': countedMinor,
  'cash_variance_minor': countedMinor - expectedMinor,
  'opening_float_minor': 10000,
  'duration_minutes': 270,
  'order_count': orders,
  'collected_minor': collectedMinor,
  'cash_sales_minor': cashSalesMinor,
};

Map<String, Object?> _todayReport() {
  final morning = _closedShift(
    'shift-morning',
    '2026-10-31 08:00',
    '2026-10-31 12:30',
    expectedMinor: 14200,
    countedMinor: 14200,
    orders: 2,
    collectedMinor: 9200,
    cashSalesMinor: 4200,
  );
  return {
    'ok': true,
    'entity': 'owner_report_range',
    'currency_code': 'ILS',
    'range': 'today',
    'range_start': '2026-10-31',
    'range_end': '2026-10-31',
    'current': {
      'order_count': 4,
      'completed_count': 3,
      'open_count': 1,
      'unpaid_count': 1,
      'gross_minor': 18500,
      'discount_minor': 0,
      'net_minor': 18500,
      'void_count': 0,
      'void_total_minor': 0,
      'collected_minor': 12000,
      'cash_minor': 7000,
      'last_cash_payment_minor': 2800,
      'tenders': [
        {'method': 'cash', 'count': 2, 'total_minor': 7000},
        {'method': 'card', 'count': 1, 'total_minor': 5000},
      ],
    },
    'comparison': {
      'order_count': 3,
      'completed_count': 3,
      'gross_minor': 15000,
      'discount_minor': 0,
      'net_minor': 15000,
      'cash_minor': 6000,
    },
    'hourly': [
      {'hour': 9, 'net_minor': 4200},
      {'hour': 12, 'net_minor': 5000},
      {'hour': 13, 'net_minor': 6500},
      {'hour': 14, 'net_minor': 2800},
    ],
    'shift_cash': {
      'closed_shift_count': 1,
      'open_shift_count': 1,
      'expected_cash_minor': 14200,
      'counted_cash_minor': 14200,
      'cash_variance_minor': 0,
      'last_closed_shift': morning,
      'recent_closed_shifts': [morning],
    },
  };
}

Map<String, Object?> _last7Report() {
  final morning = _closedShift(
    'shift-morning',
    '2026-10-31 08:00',
    '2026-10-31 12:30',
    expectedMinor: 14200,
    countedMinor: 14200,
    orders: 2,
    collectedMinor: 9200,
    cashSalesMinor: 4200,
  );
  final evening = _closedShift(
    'shift-evening',
    '2026-10-30 16:00',
    '2026-10-30 20:30',
    expectedMinor: 18000,
    countedMinor: 17500,
    orders: 2,
    collectedMinor: 13000,
    cashSalesMinor: 8000,
  );
  return {
    'ok': true,
    'entity': 'owner_report_range',
    'currency_code': 'ILS',
    'range': 'last7',
    'range_start': '2026-10-25',
    'range_end': '2026-10-31',
    'current': {
      'order_count': 19,
      'completed_count': 17,
      'open_count': 1,
      'unpaid_count': 1,
      'gross_minor': 98500,
      'discount_minor': 1500,
      'net_minor': 97000,
      'void_count': 1,
      'void_total_minor': 2400,
      'collected_minor': 90500,
      'cash_minor': 60500,
      'last_cash_payment_minor': 2800,
      'tenders': [
        {'method': 'cash', 'count': 12, 'total_minor': 60500},
        {'method': 'card', 'count': 6, 'total_minor': 30000},
      ],
    },
    'comparison': {
      'order_count': 16,
      'completed_count': 15,
      'gross_minor': 90000,
      'discount_minor': 1000,
      'net_minor': 89000,
      'cash_minor': 55000,
    },
    'hourly': <Object?>[],
    'shift_cash': {
      'closed_shift_count': 6,
      'open_shift_count': 1,
      'expected_cash_minor': 112000,
      'counted_cash_minor': 111500,
      'cash_variance_minor': -500,
      'last_closed_shift': morning,
      'recent_closed_shifts': [morning, evening],
    },
  };
}

/// One day of the last-7 series: (day, orders, discount, voids, void total,
/// cash, card, billed-but-unpaid).
typedef _Day = (String, int, int, int, int, int, int, int);

const List<_Day> _seriesDays = [
  ('2026-10-25', 3, 0, 0, 0, 8000, 5000, 0),
  ('2026-10-26', 3, 0, 0, 0, 8500, 5000, 0),
  ('2026-10-27', 2, 0, 1, 2400, 12000, 0, 0),
  ('2026-10-28', 3, 1500, 0, 0, 9000, 5000, 0),
  ('2026-10-29', 2, 0, 0, 0, 8000, 5000, 0),
  ('2026-10-30', 2, 0, 0, 0, 8000, 5000, 0),
  ('2026-10-31', 4, 0, 0, 0, 7000, 5000, 6500),
];

Map<String, Object?> _salesSeries(Object? range) => {
  'ok': true,
  'currency_code': 'ILS',
  'range': range ?? 'last7',
  'buckets': [
    for (final (day, orders, discount, voids, voidTotal, cash, card, unpaid)
        in _seriesDays)
      {
        'day': day,
        'order_count': orders,
        'gross_minor': cash + card + unpaid + discount,
        'discount_minor': discount,
        'net_minor': cash + card + unpaid,
        'void_count': voids,
        'void_total_minor': voidTotal,
        'collected_minor': cash + card,
        'cash_minor': cash,
        'by_method': [
          if (cash > 0)
            {
              'method': 'cash',
              'count': orders - (card > 0 ? 1 : 0) - (unpaid > 0 ? 1 : 0),
              'total_minor': cash,
            },
          if (card > 0) {'method': 'card', 'count': 1, 'total_minor': card},
        ],
        'by_order_type': [
          {
            'order_type': 'dine_in',
            'order_count': orders - (card > 0 ? 1 : 0),
            'net_minor': cash + unpaid,
          },
          if (card > 0)
            {'order_type': 'takeaway', 'order_count': 1, 'net_minor': card},
        ],
      },
  ],
};

Map<String, Object?> _currencyBreakdown(Map<String, dynamic> params) {
  final oneDay = params['p_start'] == params['p_end'];
  return {
    'ok': true,
    'by_currency': [
      {
        'currency_code': 'ILS',
        'order_count': oneDay ? 4 : 19,
        'gross_minor': oneDay ? 18500 : 98500,
        'discount_minor': oneDay ? 0 : 1500,
        'net_minor': oneDay ? 18500 : 97000,
        'collected_minor': oneDay ? 12000 : 90500,
        'cash_minor': oneDay ? 7000 : 60500,
      },
    ],
  };
}

Map<String, Object?> _topItems(Object? range) {
  final week = range == 'last7';
  return {
    'ok': true,
    'currency_code': 'ILS',
    'range': range ?? 'today',
    'items': [
      {
        'menu_item_id': 'item-burger',
        'name': 'Burger',
        'quantity': week ? 21 : 3,
        'revenue_minor': week ? 44100 : 6300,
        'order_count': week ? 15 : 2,
      },
      {
        'menu_item_id': 'item-family',
        'name': 'Family meal',
        'quantity': week ? 6 : 1,
        'revenue_minor': week ? 30000 : 5000,
        'order_count': week ? 6 : 1,
      },
      {
        'menu_item_id': 'item-salad',
        'name': 'Salad',
        'quantity': week ? 9 : 2,
        'revenue_minor': week ? 18000 : 4000,
        'order_count': week ? 8 : 2,
      },
    ],
  };
}

Map<String, Object?> _orderEdits(Object? range) => {
  'ok': true,
  'entity': 'owner_order_edits',
  'currency_code': 'ILS',
  'currency_codes': ['ILS'],
  'range': range ?? 'today',
  'order_edit_enabled_in_scope': false,
  'staff_visible': true,
  'summary': {
    'edit_count': 0,
    'edited_order_count': 0,
    'removed_minor': 0,
    'replaced_out_minor': 0,
    'replaced_in_minor': 0,
    'added_minor': 0,
    'net_change_minor': 0,
    'gross_retired_minor': 0,
  },
  'by_reason': <Object?>[],
  'by_staff': <Object?>[],
  'edits': <Object?>[],
  'count': 0,
  'matching': 0,
  'has_more': false,
  'next_cursor': null,
};

/// The server's `p_payment` semantics: a state filter (paid / unpaid) or the
/// method of the order's ONE completed payment.
bool _matchesPayment(_LiveOrder o, Object? payment) => switch (payment) {
  null => true,
  'paid' => o.tender != null,
  'unpaid' => o.tender == null,
  final String method => o.tender?.method == method,
  _ => false,
};

Map<String, Object?> _historyRow(_LiveOrder o) => {
  'order_id': o.id,
  'order_code': o.code,
  'status': o.status,
  'order_type': o.type,
  'created_at': o.createdAt,
  'item_count': o.itemCount,
  'grand_total_minor': o.totalMinor,
  'currency_code': 'ILS',
  'payment_status': o.tender == null ? 'unpaid' : 'paid',
  'payment_method': o.tender?.method,
  'paid_amount_minor': o.tender == null ? null : o.totalMinor,
  'table_label': o.table,
  'customer_name': null,
  'staff_name': 'Amira',
  'receipt_number': null,
  'edit_count': 0,
  'has_active_round': false,
};

Map<String, Object?> _history(Map<String, dynamic> params) {
  final limit = params['p_limit'] is int ? params['p_limit'] as int : 25;
  final rows = [
    for (final o in _liveOrders)
      if (_matchesPayment(o, params['p_payment'])) _historyRow(o),
  ];
  return {
    'ok': true,
    'currency_code': 'ILS',
    'orders': rows.take(limit).toList(),
    'has_more': false,
    'next_cursor': null,
  };
}

Map<String, Object?> _detail(Object? orderId) {
  for (final o in _liveOrders) {
    if (o.id != orderId) continue;
    return {
      'ok': true,
      'currency_code': 'ILS',
      'order': {
        'order_id': o.id,
        'order_code': o.code,
        'status': o.status,
        'order_type': o.type,
        'currency_code': 'ILS',
        'subtotal_minor': o.totalMinor,
        'discount_total_minor': 0,
        'tax_total_minor': 0,
        'grand_total_minor': o.totalMinor,
        'created_at': o.createdAt,
        'table_label': o.table,
        'branch_name': 'Main',
        'staff_name': 'Amira',
        'items': [
          for (final i in o.items)
            {
              'name': i.name,
              'quantity': i.quantity,
              'unit_price_minor': i.unitMinor,
              'line_discount_minor': 0,
              'line_total_minor': i.quantity * i.unitMinor,
              'modifiers': <Object?>[],
              'prep_snapshot': <Object?>[],
            },
        ],
        'payments': [
          if (o.tender case final t?)
            {
              'method': t.method,
              'status': 'completed',
              'amount_minor': o.totalMinor,
              'tendered_minor': t.tenderedMinor,
              'change_minor': t.changeMinor,
              'created_at': o.createdAt,
            },
        ],
        'edit_count': 0,
        'has_active_round': false,
        'active_rounds_ready': false,
        'edits': <Object?>[],
      },
    };
  }
  return {'ok': false, 'error': 'not_found'};
}

const Map<String, Object?> _orgStructure = {
  'ok': true,
  'entity': 'org_structure',
  'restaurants': [
    {
      'id': _restaurant,
      'name': 'Rest One',
      'branches': [
        {'id': _branch, 'name': 'Main'},
      ],
    },
  ],
};

const Map<String, Object?> _staff = {
  'ok': true,
  'staff': [
    {
      'employee_profile_id': 'ep-amira',
      'display_name': 'Amira',
      'role': 'cashier',
      'employment_status': 'active',
    },
  ],
};

// ===========================================================================
// Harness.
// ===========================================================================

/// A FRESH container per world: the unique key stops Flutter from reusing the
/// previous world's `ProviderScope` (which would only update its overrides).
Widget _app(_FakeServer server, String code, Widget home) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    runtimeConfigProvider.overrideWithValue(_realMode),
    dashboardMembershipProvider.overrideWithValue(_membership),
    dashboardAuthTransportProvider.overrideWithValue(server),
  ],
  child: MaterialApp(
    locale: Locale(code),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: home,
  ),
);

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ProviderContainer _containerOf(WidgetTester tester, Finder finder) =>
    ProviderScope.containerOf(tester.element(finder));

/// Every rendered string (each `RichText`, in tree order) — under [within]
/// when given.
List<String> _texts(WidgetTester tester, [Finder? within]) {
  final finder = within == null
      ? find.byType(RichText)
      : find.descendant(of: within, matching: find.byType(RichText));
  return [
    for (final element in finder.evaluate())
      _readable((element.widget as RichText).text.toPlainText()),
  ];
}

/// An icon renders as one private-use glyph; name it by code point so a
/// failing diff stays legible (icons still take part in the comparison).
String _readable(String text) {
  final runes = text.runes.toList();
  if (runes.length == 1 && runes.single >= 0xE000 && runes.single <= 0xF8FF) {
    return '<icon ${runes.single.toRadixString(16)}>';
  }
  return text;
}

/// What one world rendered and mapped, plus the requests it made.
class _Tour {
  final Map<String, List<String>> texts = <String, List<String>>{};
  final Map<String, String> models = <String, String>{};
  List<String> calls = const <String>[];
  List<String> params = const <String>[];

  void close(_FakeServer server) {
    calls = List<String>.of(server.calls);
    params = [for (final p in server.received) jsonEncode(p)];
  }
}

void _expectSameWorld(_Tour a, _Tour b) {
  expect(b.texts.keys.toList(), a.texts.keys.toList());
  for (final key in a.texts.keys) {
    expect(
      b.texts[key],
      a.texts[key],
      reason: 'rendered text at "$key" differs between world A and world B',
    );
  }
  expect(b.models.keys.toList(), a.models.keys.toList());
  for (final key in a.models.keys) {
    expect(
      b.models[key],
      a.models[key],
      reason: 'mapped model "$key" differs between world A and world B',
    );
  }
  // The same requests, with the same params, in the same order: the TEST
  // attempts did not make the Dashboard ask anything more or different.
  expect(b.calls, a.calls);
  expect(b.params, a.params);
}

void _expectReportingOnly(_FakeServer server) {
  expect(
    server.privateCalls,
    isEmpty,
    reason: 'the Dashboard called a private card channel',
  );
  expect(server.calls.where(_isPrivateChannel), isEmpty);
  expect(
    server.calls.toSet().difference(_reportingRpcAllowlist),
    isEmpty,
    reason: 'an RPC outside the reporting / audit allowlist was called',
  );
  // DASHBOARD-COLLECTED-LABEL-001: the fallback chain is never entered.
  expect(server.calls, isNot(contains('owner_daily_report')));
  expect(server.calls, isNot(contains('sales_summary')));
  // Every read is scoped to the caller's organization, never the foreign one.
  final scoped = [
    for (final p in server.received)
      if (p.containsKey('p_organization_id')) p['p_organization_id'],
  ];
  expect(scoped, isNotEmpty);
  expect(scoped.toSet(), {_org});
}

void _expectNoTestLeak(_Tour tour) {
  for (final entry in tour.texts.entries) {
    for (final text in entry.value) {
      for (final marker in _testLeakMarkers) {
        expect(
          text.contains(marker),
          isFalse,
          reason: '"$marker" rendered at ${entry.key}: $text',
        );
      }
    }
  }
  for (final entry in tour.models.entries) {
    for (final marker in _testLeakMarkers) {
      expect(
        entry.value.contains(marker),
        isFalse,
        reason: '"$marker" mapped into ${entry.key}',
      );
    }
  }
}

// --- model fingerprints (the mapped models carry no ==) ---------------------

String _comparisonPrint(ReportComparison? c) => c == null
    ? 'none'
    : '${c.grossSalesMinor}/${c.netSalesMinor}/${c.orderCount}/'
          '${c.cashSalesMinor}/${c.completedOrderCount}/'
          '${c.discountTotalMinor}';

String _closedShiftPrint(ClosedShiftSummary? s) => s == null
    ? 'none'
    : [
        s.shiftId,
        s.branchName,
        s.closedAtLabel,
        s.openedAtLabel,
        s.closedByName,
        s.openedByName,
        s.expectedCashMinor,
        s.countedCashMinor,
        s.varianceMinor,
        s.openingFloatMinor,
        s.durationMinutes,
        s.orderCount,
        s.collectedMinor,
        s.cashSalesMinor,
      ].join('/');

String _shiftPrint(ShiftCash? s) => s == null
    ? 'none'
    : [
        s.closedShiftCount,
        s.openShiftCount,
        s.expectedCashMinor,
        s.countedCashMinor,
        s.varianceMinor,
        _closedShiftPrint(s.lastClosedShift),
        for (final r in s.recentClosedShifts) _closedShiftPrint(r),
      ].join(' | ');

String _reportPrint(DashboardReport r) => [
  'ccy=${r.currencyCode} date=${r.businessDateLabel}',
  'range=${r.range.wire} supported=${r.rangeSupported} '
      '${r.rangeStartLabel}..${r.rangeEndLabel}',
  'billed=${r.grossSalesMinor}/${r.discountTotalMinor}/${r.netSalesMinor}',
  'collected=${r.collectedMinor} cashSales=${r.cashSalesMinor} '
      'lastCash=${r.lastCashPaymentMinor}',
  'voids=${r.voidCount}/${r.voidTotalMinor}',
  'orders=${r.orderCount}/${r.completedOrderCount}/${r.openOrderCount}/'
      '${r.unpaidOrderCount}',
  'drawer=${r.openingFloatMinor}/${r.expectedCashMinor}/'
      '${r.countedCashMinor}/${r.shiftStatus}',
  'lists=${r.branches.length}/${r.topItems.length}/${r.recentOrders.length}',
  for (final m in r.paymentMethods)
    'tender=${m.method}/${m.count}/${m.totalMinor}/${m.currencyCode}',
  for (final h in r.hourlyNetSales) 'hour=${h.hourLabel}/${h.netSalesMinor}',
  'comparison=${_comparisonPrint(r.comparison)}',
  'shift=${_shiftPrint(r.shiftCash)}',
].join('\n');

String _guardPrint(ReportCurrencyGuard g) =>
    '${g.mode.name}/${g.displayCurrency}/${g.totals.length}';

String _seriesPrint(OwnerSalesSeries s) => [
  'ccy=${s.currencyCode} range=${s.rangeWire} supported=${s.supported}',
  for (final b in s.buckets)
    [
      b.day.label,
      b.orderCount,
      b.grossMinor,
      b.discountMinor,
      b.netMinor,
      b.voidCount,
      b.voidTotalMinor,
      b.collectedMinor,
      b.cashMinor,
      for (final m in b.byMethod) '${m.method}:${m.count}:${m.totalMinor}',
      for (final t in b.byOrderType)
        '${t.orderType}:${t.orderCount}:${t.netMinor}',
    ].join('/'),
].join('\n');

String _historyPrint(OrderHistoryState s) => [
  'loading=${s.loading} error=${s.error} more=${s.hasMore} cursor=${s.cursor}',
  for (final r in s.rows)
    [
      r.orderId,
      r.orderCode,
      r.status,
      r.orderType,
      r.createdAtLabel,
      r.itemCount,
      r.grandTotalMinor,
      r.currencyCode,
      r.settlement.name,
      r.receiptNumber,
      r.customerName,
      r.tableLabel,
      r.staffName,
      r.paymentMethod,
      r.paidAmountMinor,
      r.editCount,
      r.hasActiveRound,
    ].join('/'),
].join('\n');

String _detailPrint(OrderDetail d) => [
  [
    d.orderId,
    d.orderCode,
    d.status,
    d.orderType,
    d.currencyCode,
    d.subtotalMinor,
    d.discountTotalMinor,
    d.taxTotalMinor,
    d.grandTotalMinor,
    d.createdAtLabel,
    d.customerName,
    d.tableLabel,
    d.branchName,
    d.staffName,
    d.receiptNumber,
    d.notes,
    d.editCount,
    d.hasActiveRound,
    d.activeRoundsReady,
    d.edits?.length,
    d.settlement.name,
  ].join('/'),
  for (final i in d.items)
    'item=${i.name}/${i.quantity}/${i.unitPriceMinor}/'
        '${i.lineDiscountMinor}/${i.lineTotalMinor}/${i.notes}/'
        '${i.modifiers.length}/${i.prepComponents.length}',
  for (final p in d.payments)
    'payment=${p.method}/${p.status}/${p.amountMinor}/${p.tenderedMinor}/'
        '${p.changeMinor}/${p.receiptNumber}/${p.createdAtLabel}',
].join('\n');

String _auditPrint(AuditLogState s, AppLocalizations l10n) {
  final presenter = AuditEventPresenter(l10n, s.currencyCode);
  return [
    'loading=${s.loading} error=${s.error} more=${s.hasMore} '
        'ccy=${s.currencyCode}',
    for (final e in s.events)
      [
        e.eventId,
        e.action,
        e.category,
        e.occurredAtLabel,
        e.actorName,
        e.restaurantName,
        e.branchName,
        e.deviceLabel,
        e.reason,
        jsonEncode(e.oldValues),
        jsonEncode(e.newValues),
        _viewPrint(presenter.present(e)),
      ].join('/'),
  ].join('\n');
}

String _viewPrint(AuditEventView v) => [
  v.title,
  v.categoryLabel,
  v.tone.name,
  v.isDenied,
  v.isKnownAction,
  v.reason,
  for (final c in v.changes) '${c.label}=${c.oldValue}>${c.newValue}',
].join('|');

// --- localized vocabularies -------------------------------------------------

/// The fourteen card-family titles (twelve actions, three anomaly variants).
List<String> _cardTitles(AppLocalizations l10n) => [
  l10n.activityLogTitleCardAttemptStarted,
  l10n.activityLogTitleCardAttemptApproved,
  l10n.activityLogTitleCardAttemptDeclined,
  l10n.activityLogTitleCardAttemptUnknown,
  l10n.activityLogTitleCardAttemptReleased,
  l10n.activityLogTitleCardAttemptAnomalyRaised,
  l10n.activityLogTitleCardAttemptAnomalyCleared,
  l10n.activityLogTitleCardAttemptAnomaly,
  l10n.activityLogTitleCardAttemptReleaseRequested,
  l10n.activityLogTitleCardAttemptReleaseFailed,
  l10n.activityLogTitleCardAttemptRecordingRefused,
  l10n.activityLogTitleCardAttemptOrderFreed,
  l10n.activityLogTitleCardAttemptResumeRequested,
  l10n.activityLogTitleCardAttemptDenied,
];

/// The card-family field labels (`amount_minor` shares the global Amount
/// label, checked separately as money).
List<String> _cardFieldLabels(AppLocalizations l10n) => [
  l10n.activityLogFieldCardState,
  l10n.activityLogFieldCardMode,
  l10n.activityLogFieldCurrency,
  l10n.activityLogFieldCardRefusal,
  l10n.activityLogFieldCardReleaseStatus,
  l10n.activityLogFieldCardAnomaly,
  l10n.activityLogFieldCardReleaseRequested,
  l10n.activityLogFieldCardConfirmationSource,
  l10n.activityLogFieldCardPriorRefusal,
  l10n.activityLogFieldCardResumeCount,
  l10n.activityLogFieldCardResumeOutcome,
];

/// The LIVE attempt-state labels a TEST token must never borrow.
List<String> _liveStateLabels(AppLocalizations l10n) => [
  l10n.activityLogCardStateSent,
  l10n.activityLogCardStateApproved,
  l10n.activityLogCardStateDeclined,
  l10n.activityLogCardStateUnknown,
  l10n.activityLogCardStateReleased,
];

/// Card-family VALUE labels that would betray a card presentation.
List<String> _cardValueLabels(AppLocalizations l10n) => [
  ..._liveStateLabels(l10n),
  l10n.activityLogCardModeLive,
  l10n.activityLogCardModeTest,
  l10n.activityLogDeniedCardPermission,
];

final RegExp _moneyPattern = RegExp(r'\d+\.\d\d');

/// No card title, no card field, no money and no TEST identity in [texts].
void _expectNoCardSurface(
  List<String> texts,
  AppLocalizations l10n, {
  required String where,
}) {
  final forbidden = <String>{
    ..._cardTitles(l10n),
    ..._cardFieldLabels(l10n),
    ..._cardValueLabels(l10n),
    l10n.activityLogFieldAmount,
  };
  for (final text in texts) {
    expect(forbidden.contains(text), isFalse, reason: '$where shows "$text"');
    expect(text.contains('₪'), isFalse, reason: '$where shows money: $text');
    expect(
      _moneyPattern.hasMatch(text),
      isFalse,
      reason: '$where shows an amount: $text',
    );
    expect(text.contains('MARKER-'), isFalse, reason: '$where: $text');
  }
}

AuditEvent _event(
  String action, {
  String category = 'payments',
  Map<String, Object?> newValues = const {},
  String? reason,
}) => AuditEvent(
  eventId: 'evt-presenter',
  action: action,
  category: category,
  occurredAtLabel: '2026-10-31 13:21',
  actorName: 'Amira',
  restaurantName: 'Rest One',
  branchName: 'Main',
  deviceLabel: 'Front till',
  reason: reason,
  newValues: newValues,
);

// ===========================================================================
// The flows, run identically in both worlds.
// ===========================================================================

String _kpiValue(WidgetTester tester, String key) =>
    tester.widget<RestoflowMetricCard>(find.byKey(Key(key))).value;

String _keyedText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// Overview, real mode: today, then the last 7 days.
Future<_Tour> _overviewTour(
  WidgetTester tester,
  _FakeServer server,
  String code,
  AppLocalizations l10n,
) async {
  final tour = _Tour();
  await tester.pumpWidget(_app(server, code, const DashboardHomeScreen()));
  await tester.pumpAndSettle();
  final container = _containerOf(tester, find.byType(DashboardHomeScreen));

  // TODAY — LIVE money only: billed 185.00, the card tender is the LIVE 50.00
  // (never O's TEST approval), one unpaid order (O).
  expect(find.byKey(const Key('reports-realmode-banner')), findsOneWidget);
  expect(_kpiValue(tester, 'kpi-gross-sales'), '₪185.00');
  expect(_kpiValue(tester, 'kpi-unpaid'), '1');
  expect(_keyedText(tester, 'payment-amount-card'), '₪50.00');
  expect(_keyedText(tester, 'payment-amount-cash'), '₪70.00');
  expect(find.byKey(const Key('shift-cash-card')), findsOneWidget);
  final recent = find.byKey(const Key('recent-orders-card'));
  expect(
    find.descendant(of: recent, matching: find.text(l10n.dashboardUnpaid)),
    findsOneWidget,
    reason: 'O is the one unpaid recent order',
  );
  tour.texts['overview.today'] = _texts(tester);
  tour.models['overview.today.report'] = _reportPrint(
    container.read(dashboardReportProvider).requireValue,
  );
  tour.models['overview.today.guard'] = _guardPrint(
    container.read(dashboardCurrencyGuardProvider).requireValue,
  );

  // LAST 7 DAYS — the payment mix, the per-method trend and the shift card.
  await tester.tap(find.byKey(const Key('range-chip-last7')));
  await tester.pumpAndSettle();
  expect(_kpiValue(tester, 'kpi-gross-sales'), '₪985.00');
  expect(_keyedText(tester, 'payment-amount-card'), '₪300.00');
  expect(_keyedText(tester, 'payment-amount-cash'), '₪605.00');
  expect(find.byKey(const Key('payment-method-trend-title')), findsOneWidget);
  expect(find.byKey(const Key('payment-method-trend-chart')), findsOneWidget);
  expect(find.byKey(const Key('sales-by-day-card')), findsOneWidget);
  expect(find.byKey(const Key('shift-cash-card')), findsOneWidget);
  expect(
    find.descendant(of: recent, matching: find.text(l10n.dashboardUnpaid)),
    findsOneWidget,
  );
  tour.texts['overview.last7'] = _texts(tester);
  tour.models['overview.last7.report'] = _reportPrint(
    container.read(dashboardReportProvider).requireValue,
  );
  tour.models['overview.last7.guard'] = _guardPrint(
    container.read(dashboardCurrencyGuardProvider).requireValue,
  );
  final seriesKey = container.read(currentOwnerSalesSeriesKeyProvider);
  expect(seriesKey, isNotNull);
  tour.models['overview.last7.series'] = _seriesPrint(
    container.read(ownerSalesSeriesForKeyProvider(seriesKey!)).requireValue,
  );

  await tester.pumpWidget(const SizedBox.shrink());
  tour.close(server);
  return tour;
}

/// O's history card carries exactly one settlement pill, and it says unpaid.
void _expectOpenOrderUnpaid(WidgetTester tester, AppLocalizations l10n) {
  final card = find.byKey(const Key('order-card-$_ordOpen'));
  expect(card, findsOneWidget);
  final settlement = {
    l10n.dashboardPaid,
    l10n.dashboardUnpaid,
    l10n.dashboardNoCharge,
  };
  final pills = tester
      .widgetList<RestoflowStatusPill>(
        find.descendant(of: card, matching: find.byType(RestoflowStatusPill)),
      )
      .where((p) => settlement.contains(p.label))
      .toList();
  expect(pills.map((p) => p.label), [l10n.dashboardUnpaid]);
  expect(pills.single.tone, RestoflowTone.warning);
}

/// Orders history, real mode: all, card and unpaid — set exactly as a
/// drill-down sets them, through the query provider.
Future<_Tour> _ordersTour(
  WidgetTester tester,
  _FakeServer server,
  String code,
  AppLocalizations l10n,
) async {
  final tour = _Tour();
  await tester.pumpWidget(
    _app(server, code, const Scaffold(body: OrderHistoryScreen())),
  );
  await tester.pumpAndSettle();
  final container = _containerOf(tester, find.byType(OrderHistoryScreen));
  for (final (filter, expected) in const [
    (PaymentFilter.all, _allOrderIds),
    (PaymentFilter.card, [_ordCard]),
    (PaymentFilter.unpaid, [_ordOpen]),
  ]) {
    container.read(orderHistoryQueryProvider.notifier).state =
        OrderHistoryQuery(payment: filter);
    await tester.pumpAndSettle();
    final state = container.read(orderHistoryControllerProvider);
    expect(state.error, isNull);
    expect(state.rows.map((r) => r.orderId), expected, reason: filter.name);
    for (final id in _allOrderIds) {
      expect(
        find.byKey(Key('order-card-$id')),
        expected.contains(id) ? findsOneWidget : findsNothing,
        reason: '${filter.name}: $id',
      );
    }
    if (expected.contains(_ordOpen)) _expectOpenOrderUnpaid(tester, l10n);
    tour.texts['history.${filter.name}'] = _texts(tester);
    tour.models['history.${filter.name}'] = _historyPrint(state);
  }
  await tester.pumpWidget(const SizedBox.shrink());
  tour.close(server);
  return tour;
}

/// Order O's drawer, then its receipt preview.
Future<_Tour> _drawerTour(
  WidgetTester tester,
  _FakeServer server,
  String code,
  AppLocalizations l10n,
) async {
  final tour = _Tour();
  await tester.pumpWidget(
    _app(server, code, const Scaffold(body: OrderHistoryScreen())),
  );
  await tester.pumpAndSettle();
  final container = _containerOf(tester, find.byType(OrderHistoryScreen));

  await tester.tap(find.byKey(const Key('order-card-$_ordOpen')));
  await tester.pumpAndSettle();
  final sheet = find.byKey(const Key('order-detail-sheet'));
  expect(find.byKey(const Key('order-detail-content')), findsOneWidget);
  // The payment row states the settlement (Unpaid); no tender line exists.
  expect(
    find.descendant(of: sheet, matching: find.text(l10n.dashboardUnpaid)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: sheet, matching: find.text(l10n.posPaymentMethodCard)),
    findsNothing,
  );
  // Served but unpaid, so completion is blocked (D-025).
  expect(
    find.byKey(const Key('order-complete-unpaid-blocked')),
    findsOneWidget,
  );
  tour.texts['drawer'] = _texts(tester, sheet);

  await tester.tap(find.byKey(const Key('order-receipt-preview-button')));
  await tester.pumpAndSettle();
  final preview = find.byKey(const Key('order-receipt-preview'));
  expect(preview, findsOneWidget);
  expect(
    find.descendant(of: preview, matching: find.text(l10n.dashboardUnpaid)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: preview, matching: find.text('₪65.00')),
    findsWidgets,
  );
  for (final label in [
    l10n.posPaymentMethodCard,
    l10n.posReceiptPaid,
    l10n.posReceiptChange,
  ]) {
    expect(
      find.descendant(of: preview, matching: find.text(label)),
      findsNothing,
    );
  }
  tour.texts['receipt'] = _texts(tester, preview);

  // The mapped detail behind both, and the receipt document built from it.
  final detail = await container
      .read(orderHistoryRepositoryProvider)
      .loadDetail(_ordOpen);
  expect(detail.completedPayment, isNull);
  expect(detail.settlement, SettlementState.unpaid);
  tour.models['detail'] = _detailPrint(detail);
  tour.models['receipt'] = documentToHtml(
    buildOrderReceiptPreview(l10n, detail),
  );

  await tester.pumpWidget(const SizedBox.shrink());
  tour.close(server);
  return tour;
}

/// The Activity log: the timeline, then the detail of each row in [open].
Future<_Tour> _activityTour(
  WidgetTester tester,
  _FakeServer server,
  String code,
  AppLocalizations l10n, {
  List<String> open = const [],
}) async {
  final tour = _Tour();
  await tester.pumpWidget(
    _app(server, code, const Scaffold(body: ActivityLogScreen())),
  );
  await tester.pumpAndSettle();
  final container = _containerOf(tester, find.byType(ActivityLogScreen));
  final state = container.read(auditLogControllerProvider);
  expect(state.error, isNull);
  tour.texts['activity'] = _texts(tester);
  tour.models['activity'] = _auditPrint(state, l10n);
  for (final id in open) {
    await tester.tap(find.byKey(Key('activity-card-$id')));
    await tester.pumpAndSettle();
    tour.texts['activity.$id'] = _texts(
      tester,
      find.byKey(const Key('activity-detail-dialog')),
    );
    await tester.tap(find.byKey(const Key('activity-detail-close')));
    await tester.pumpAndSettle();
  }
  await tester.pumpWidget(const SizedBox.shrink());
  tour.close(server);
  return tour;
}

// ===========================================================================
// Static scan helpers (T4).
// ===========================================================================

/// The Dashboard's lib/, whether the runner's cwd is apps/dashboard or the
/// repository root.
Directory _dashboardLib() {
  for (final path in const ['lib', 'apps/dashboard/lib']) {
    if (File('$path/src/data/audit_action_registry.dart').existsSync()) {
      return Directory(path);
    }
  }
  fail('cannot find apps/dashboard/lib (cwd: ${Directory.current.path})');
}

/// lib-relative, forward-slashed path -> content, for every .dart file.
Map<String, String> _dashboardSources() {
  final lib = _dashboardLib();
  final base = lib.path.split(Platform.pathSeparator).join('/');
  final out = <String, String>{};
  for (final entity in lib.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.split(Platform.pathSeparator).join('/');
    out['lib${path.substring(base.length)}'] = entity.readAsStringSync();
  }
  return out;
}

const List<String> _privateTokens = [
  'owner_card_attempts',
  'card_attempt_context',
  'card_provider_attempts',
  'card_provider_private_events',
  'card_payments_pilot',
  'payment_terminals',
  'private_event',
  'test.card_attempt_denied',
  'test.card_recording_refused',
  'operator.card_',
  'security.card_',
  'approved_unrecorded',
  'orphan_approved',
  'test_approved',
  'test_declined',
  'test_unknown',
  'test_released',
  'test_sent',
  'test_closed',
  'credential_ref',
  'terminal_ref',
  'provider_reference',
  'pos-card-charge',
  'set_payment_terminal',
  'local_operation_id',
];

void main() {
  // =========================================================================
  // T1/T2 — the differential: world A (LIVE) vs world B (LIVE + TEST).
  // =========================================================================
  group('T1/T2 differential: LIVE-only world A vs world B with TEST attempts '
      'on the private channels', () {
    test('T1/T2 fixture: world B differs from world A only on the private '
        'channels', () async {
      final a = _FakeServer(_World.liveOnly);
      final b = _FakeServer(_World.liveWithTest);
      // Every reporting answer is byte-identical: TEST writes no LIVE fact.
      for (final (function, params) in <(String, Map<String, dynamic>)>[
        ('owner_report_range', {'p_range': 'today'}),
        ('owner_report_range', {'p_range': 'last7'}),
        (
          'owner_report_currency_breakdown',
          {'p_start': '2026-10-31', 'p_end': '2026-10-31'},
        ),
        ('owner_sales_series', {'p_range': 'last7'}),
        ('owner_top_items', {'p_range': 'today'}),
        ('owner_order_edits', {'p_range': 'today'}),
        ('owner_order_history', {'p_payment': null}),
        ('owner_order_history', {'p_payment': 'card'}),
        ('owner_order_history', {'p_payment': 'unpaid'}),
        ('owner_order_detail', {'p_order_id': _ordOpen}),
        ('owner_audit_events', <String, dynamic>{}),
        ('list_org_structure', <String, dynamic>{}),
        ('list_staff', <String, dynamic>{}),
      ]) {
        final scoped = <String, dynamic>{'p_organization_id': _org, ...params};
        final inA = await a.invoke(function, scoped);
        final inB = await b.invoke(function, scoped);
        expect((inA! as Map)['ok'], isTrue, reason: function);
        expect(jsonEncode(inB), jsonEncode(inA), reason: function);
      }
      // The second organization exists and refuses this caller everywhere.
      for (final server in [a, b]) {
        for (final function in _reportingRpcAllowlist) {
          expect(
            await server.invoke(function, {'p_organization_id': _foreignOrg}),
            {'ok': false, 'error': 'permission_denied'},
            reason: function,
          );
        }
      }
      // ...while every private channel holds TEST attempts in world B only.
      for (final function in const [
        'owner_card_attempts',
        'card_attempt_context',
        'card_provider_private_events',
        'payment_terminals',
      ]) {
        final inA = jsonEncode(await a.invoke(function, {'p_mode': 'test'}));
        final inB = jsonEncode(await b.invoke(function, {'p_mode': 'test'}));
        expect(inA.contains('MARKER-'), isFalse, reason: function);
        expect(inB.contains('MARKER-'), isTrue, reason: function);
      }
      final page =
          await b.invoke('owner_card_attempts', {'p_mode': 'test'}) as Map;
      final attempts = page['attempts'] as List;
      expect(attempts, hasLength(4));
      for (final row in attempts.cast<Map>()) {
        expect(row['mode'], 'test');
        expect(row['classification'], 'test_${row['attempt_state']}');
        expect(row['classification'], isNot('approved_unrecorded'));
        expect(row['recorded'], isFalse);
        expect(row['order_id'], _ordOpen);
      }
      // The allowlist itself names no private channel.
      expect(_reportingRpcAllowlist.where(_isPrivateChannel), isEmpty);
    });

    for (final code in _locales) {
      testWidgets('T1/T2 [$code] Overview today and last 7 days: identical '
          'text and report / guard / series models, reporting RPCs only', (
        tester,
      ) async {
        _surface(tester, const Size(1400, 4400));
        final l10n = await _l10n(code);
        final serverA = _FakeServer(_World.liveOnly);
        final serverB = _FakeServer(_World.liveWithTest);
        final a = await _overviewTour(tester, serverA, code, l10n);
        final b = await _overviewTour(tester, serverB, code, l10n);

        _expectSameWorld(a, b);
        _expectNoTestLeak(b);
        for (final server in [serverA, serverB]) {
          _expectReportingOnly(server);
          expect(
            server.calls,
            containsAll(<String>[
              'owner_report_range',
              'owner_report_currency_breakdown',
              'owner_sales_series',
            ]),
          );
        }
      });

      testWidgets('T1/T2 [$code] Orders history all / card / unpaid: '
          'identical rows and text, O unpaid in both worlds, reporting RPCs '
          'only', (tester) async {
        _surface(tester, const Size(1400, 2600));
        final l10n = await _l10n(code);
        final serverA = _FakeServer(_World.liveOnly);
        final serverB = _FakeServer(_World.liveWithTest);
        final a = await _ordersTour(tester, serverA, code, l10n);
        final b = await _ordersTour(tester, serverB, code, l10n);

        _expectSameWorld(a, b);
        _expectNoTestLeak(b);
        for (final server in [serverA, serverB]) {
          _expectReportingOnly(server);
          expect(server.calls, contains('owner_order_history'));
          final payments = [
            for (var i = 0; i < server.calls.length; i++)
              if (server.calls[i] == 'owner_order_history')
                server.received[i]['p_payment'],
          ];
          expect(payments, containsAll(<String?>[null, 'card', 'unpaid']));
        }
      });

      testWidgets('T1/T2 [$code] order O drawer and receipt preview: '
          'identical text and detail / receipt models, O unpaid in both '
          'worlds', (tester) async {
        _surface(tester, const Size(1400, 2600));
        final l10n = await _l10n(code);
        final serverA = _FakeServer(_World.liveOnly);
        final serverB = _FakeServer(_World.liveWithTest);
        final a = await _drawerTour(tester, serverA, code, l10n);
        final b = await _drawerTour(tester, serverB, code, l10n);

        _expectSameWorld(a, b);
        _expectNoTestLeak(b);
        for (final server in [serverA, serverB]) {
          _expectReportingOnly(server);
          expect(server.calls, contains('owner_order_detail'));
        }
      });

      testWidgets('T1/T2 [$code] Activity log: identical timeline, row '
          'details and event models, audit RPCs only', (tester) async {
        _surface(tester, const Size(1400, 2600));
        final l10n = await _l10n(code);
        final serverA = _FakeServer(_World.liveOnly);
        final serverB = _FakeServer(_World.liveWithTest);
        const open = [_evtCardStarted, _evtCardApproved, _evtPayCard];
        final a = await _activityTour(tester, serverA, code, l10n, open: open);
        final b = await _activityTour(tester, serverB, code, l10n, open: open);

        _expectSameWorld(a, b);
        _expectNoTestLeak(b);
        for (final server in [serverA, serverB]) {
          _expectReportingOnly(server);
          expect(server.calls, contains('owner_audit_events'));
        }
      });
    }
  });

  // =========================================================================
  // T3 — the Activity log carries no tenant row for TEST.
  // =========================================================================
  group('T3 Activity log: no tenant row for TEST', () {
    for (final code in _locales) {
      testWidgets('T3 [$code] world B audit feed equals world A and the '
          'screen shows only the LIVE rows', (tester) async {
        _surface(tester, const Size(1400, 2600));
        final l10n = await _l10n(code);
        final liveIds = [
          for (final row in _liveFeed) row['event_id']! as String,
        ];
        final feeds = <String>[];
        for (final world in _World.values) {
          final server = _FakeServer(world);
          await tester.pumpWidget(
            _app(server, code, const Scaffold(body: ActivityLogScreen())),
          );
          await tester.pumpAndSettle();
          final container = _containerOf(
            tester,
            find.byType(ActivityLogScreen),
          );
          final state = container.read(auditLogControllerProvider);
          expect(state.error, isNull);
          // The feed is the LIVE feed, in order, and nothing else.
          expect(state.events.map((e) => e.eventId), liveIds);
          for (final e in state.events) {
            expect(
              e.action.startsWith('test.') ||
                  e.action.startsWith('operator.') ||
                  e.action.startsWith('security.'),
              isFalse,
              reason: e.action,
            );
          }
          feeds.add(
            [
              for (final e in state.events)
                '${e.eventId}/${e.action}/${e.category}/${e.reason}/'
                    '${jsonEncode(e.oldValues)}/${jsonEncode(e.newValues)}',
            ].join('\n'),
          );
          // The screen shows exactly those rows.
          expect(find.byType(ActivityEventCard), findsNWidgets(liveIds.length));
          for (final id in liveIds) {
            expect(find.byKey(Key('activity-card-$id')), findsOneWidget);
          }
          // The one card attempt with a mode is the LIVE one.
          await tester.tap(
            find.byKey(const Key('activity-card-$_evtCardStarted')),
          );
          await tester.pumpAndSettle();
          final dialog = find.byKey(const Key('activity-detail-dialog'));
          expect(
            find.descendant(
              of: dialog,
              matching: find.text(l10n.activityLogCardModeLive),
            ),
            findsOneWidget,
          );
          expect(find.text(l10n.activityLogCardModeTest), findsNothing);
          await tester.tap(find.byKey(const Key('activity-detail-close')));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          _expectReportingOnly(server);
        }
        expect(feeds[1], feeds[0]);
      });
    }
  });

  // =========================================================================
  // T4 — static: the Dashboard source never names a private card surface.
  // =========================================================================
  group('T4 static scan of apps/dashboard/lib', () {
    test('T4 no Dashboard source names a private card channel, a TEST '
        'classification or a provider field', () {
      final sources = _dashboardSources();
      // Non-vacuous: the whole library was read.
      expect(sources.length, greaterThan(100));
      expect(
        sources.keys,
        contains('lib/src/data/audit_log_presentation.dart'),
      );
      for (final token in _privateTokens) {
        final offenders = [
          for (final entry in sources.entries)
            if (entry.value.contains(token)) entry.key,
        ];
        expect(offenders, isEmpty, reason: '"$token" appears in $offenders');
      }
    });

    test('T4 card_attempt appears only in the audit registry and the audit '
        'presenter', () {
      final sources = _dashboardSources();
      final holders = [
        for (final entry in sources.entries)
          if (entry.value.contains('card_attempt')) entry.key,
      ]..sort();
      expect(holders, [
        'lib/src/data/audit_action_registry.dart',
        'lib/src/data/audit_log_presentation.dart',
      ]);
    });

    test('T4 kAuditActionRegistry registers no test., operator. or '
        'security. action', () {
      final private = [
        for (final action in kAuditActionRegistry.keys)
          if (action.startsWith('test.') ||
              action.startsWith('operator.') ||
              action.startsWith('security.'))
            action,
      ];
      expect(private, isEmpty);
      // The LIVE card family is still there, so the scan is not vacuous.
      expect(
        kAuditActionRegistry.keys.where((a) => a.startsWith('card_attempt.')),
        hasLength(12),
      );
    });
  });

  // =========================================================================
  // T5 — a TEST attempt can never look like a LIVE approved-unrecorded case.
  // =========================================================================
  group('T5 never a LIVE approved_unrecorded incident from TEST', () {
    for (final code in _locales) {
      testWidgets('T5 [$code] LIVE incident shows the approved (success) and '
          'recording-refused (warning) rows with O unpaid; a TEST attempt for '
          'O shows neither and O stays unpaid', (tester) async {
        _surface(tester, const Size(1400, 2600));
        final l10n = await _l10n(code);

        Future<void> expectOpenOrderUnpaid(_FakeServer server) async {
          await tester.pumpWidget(
            _app(server, code, const Scaffold(body: OrderHistoryScreen())),
          );
          await tester.pumpAndSettle();
          _expectOpenOrderUnpaid(tester, l10n);
          final container = _containerOf(
            tester,
            find.byType(OrderHistoryScreen),
          );
          container.read(orderHistoryQueryProvider.notifier).state =
              const OrderHistoryQuery(payment: PaymentFilter.unpaid);
          await tester.pumpAndSettle();
          expect(
            container
                .read(orderHistoryControllerProvider)
                .rows
                .map((r) => r.orderId),
            [_ordOpen],
          );
          _expectOpenOrderUnpaid(tester, l10n);
          await tester.pumpWidget(const SizedBox.shrink());
        }

        RestoflowStatusPill categoryPill(Finder card) =>
            tester.widget<RestoflowStatusPill>(
              find.descendant(
                of: card,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is RestoflowStatusPill &&
                      w.label == l10n.activityLogCategoryPayments,
                ),
              ),
            );

        // LIVE incident world: approved by the provider, recording refused,
        // and no payment.recorded for O.
        final live = _FakeServer(_World.liveOnly, audit: _incidentFeed);
        await tester.pumpWidget(
          _app(live, code, const Scaffold(body: ActivityLogScreen())),
        );
        await tester.pumpAndSettle();
        final approved = find.byKey(
          const Key('activity-card-$_evtIncidentApproved'),
        );
        expect(
          find.descendant(
            of: approved,
            matching: find.text(l10n.activityLogTitleCardAttemptApproved),
          ),
          findsOneWidget,
        );
        expect(categoryPill(approved).tone, RestoflowTone.success);
        final refused = find.byKey(
          const Key('activity-card-$_evtIncidentRefused'),
        );
        expect(
          find.descendant(
            of: refused,
            matching: find.text(
              l10n.activityLogTitleCardAttemptRecordingRefused,
            ),
          ),
          findsOneWidget,
        );
        expect(categoryPill(refused).tone, RestoflowTone.warning);
        // The only recorded payment of the day is the morning cash sale.
        expect(find.text(l10n.activityLogTitlePaymentRecorded), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await expectOpenOrderUnpaid(live);

        // A LIVE-only render of the SAME quiet feed (the T1/T2 tour). Its
        // three LIVE rows carry money (65.00 / 42.00 / 100.00), so the TEST
        // world is compared with this render, not with "no money anywhere".
        final quietLiveServer = _FakeServer(_World.liveOnly, audit: _quietFeed);
        final quietLive = await _activityTour(
          tester,
          quietLiveServer,
          code,
          l10n,
        );

        // TEST world: the same O, a TEST approval and a private TEST
        // recording refusal — and no tenant row at all.
        final testWorld = _FakeServer(_World.liveWithTest, audit: _quietFeed);
        await tester.pumpWidget(
          _app(testWorld, code, const Scaffold(body: ActivityLogScreen())),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.activityLogTitleCardAttemptApproved),
          findsNothing,
        );
        expect(
          find.text(l10n.activityLogTitleCardAttemptRecordingRefused),
          findsNothing,
        );
        final testTexts = _texts(tester);
        expect(
          testTexts,
          quietLive.texts['activity'],
          reason:
              'the TEST world renders other than LIVE-only for the same feed',
        );
        // Non-vacuous: the scan below reads the three LIVE row titles.
        expect(
          testTexts,
          containsAll(<String>[
            l10n.activityLogTitleOrderSubmitted,
            l10n.activityLogTitlePaymentRecorded,
            l10n.activityLogTitleShiftOpened,
          ]),
        );
        // The quiet feed has no card row, so a card title, a TEST marker or
        // a TEST amount (11.11 / 22.22 / 33.33) can only come from TEST.
        for (final text in testTexts) {
          expect(
            _cardTitles(l10n),
            isNot(contains(text)),
            reason: 'TEST world shows "$text"',
          );
          for (final marker in _testLeakMarkers) {
            expect(
              text.contains(marker),
              isFalse,
              reason: 'TEST world shows "$marker": $text',
            );
          }
        }
        expect(
          find.byType(ActivityEventCard),
          findsNWidgets(_quietFeed.length),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await expectOpenOrderUnpaid(testWorld);

        _expectReportingOnly(live);
        _expectReportingOnly(quietLiveServer);
        _expectReportingOnly(testWorld);
      });

      test('T5 [$code] presenter: TEST classification tokens in '
          'attempt_state render raw, never a LIVE state label and never the '
          'raised-anomaly danger', () async {
        final l10n = await _l10n(code);
        final presenter = AuditEventPresenter(l10n, 'ILS');
        const stateful = [
          'card_attempt.started',
          'card_attempt.approved',
          'card_attempt.declined',
          'card_attempt.unknown',
          'card_attempt.released',
          'card_attempt.provider_anomaly',
          'card_attempt.release_requested',
          'card_attempt.release_failed',
          'card_attempt.order_freed',
          'card_attempt.recording_resume_requested',
        ];
        for (final token in const ['test_approved', 'test_unknown']) {
          for (final action in stateful) {
            final view = presenter.present(
              _event(action, newValues: {'attempt_state': token}),
            );
            final row = view.changes.singleWhere(
              (c) => c.label == l10n.activityLogFieldCardState,
            );
            expect(row.newValue, token, reason: '$action / $token');
            expect(_liveStateLabels(l10n), isNot(contains(row.newValue)));
            expect(view.tone, isNot(RestoflowTone.danger), reason: action);
            expect(
              view.title,
              isNot(l10n.activityLogTitleCardAttemptAnomalyRaised),
            );
          }
          // Title and tone follow the ACTION, never the token: an approved
          // row with a TEST token still reads as the provider approval, in
          // success tone. The client cannot detect TEST on a result action (a
          // TEST-derived row would be byte-identical to a LIVE one), so
          // Activity-log TEST exclusion is server-enforced (TI-24 / TI-61 /
          // TI-62).
          final approved = presenter.present(
            _event(
              'card_attempt.approved',
              newValues: {'attempt_state': token},
            ),
          );
          expect(
            approved.title,
            l10n.activityLogTitleCardAttemptApproved,
            reason: token,
          );
          expect(approved.tone, RestoflowTone.success, reason: token);
          // The anomaly row with a TEST token is the generic, warning-toned
          // anomaly — neither the raised (danger) nor the cleared variant.
          final anomaly = presenter.present(
            _event(
              'card_attempt.provider_anomaly',
              newValues: {
                'attempt_state': token,
                'anomaly_code': 'amount_mismatch',
              },
            ),
          );
          expect(anomaly.title, l10n.activityLogTitleCardAttemptAnomaly);
          expect(anomaly.tone, RestoflowTone.warning);
        }
        // Contrast: the LIVE token does raise, so the check above can fail.
        final raised = presenter.present(
          _event(
            'card_attempt.provider_anomaly',
            newValues: {'attempt_state': 'unknown'},
          ),
        );
        expect(raised.title, l10n.activityLogTitleCardAttemptAnomalyRaised);
        expect(raised.tone, RestoflowTone.danger);
      });

      test('T5 [$code] presenter: a card_attempt.started row in mode test '
          'shows the localized Test label, never Live', () async {
        final l10n = await _l10n(code);
        final presenter = AuditEventPresenter(l10n, 'ILS');
        expect(
          l10n.activityLogCardModeTest,
          isNot(l10n.activityLogCardModeLive),
        );
        String modeOf(String mode) => presenter
            .present(
              _event(
                'card_attempt.started',
                newValues: {
                  'attempt_state': 'sent',
                  'mode': mode,
                  'amount_minor': 4321,
                  'currency_code': 'ILS',
                },
              ),
            )
            .changes
            .singleWhere((c) => c.label == l10n.activityLogFieldCardMode)
            .newValue;
        expect(modeOf('test'), l10n.activityLogCardModeTest);
        expect(modeOf('test'), isNot(l10n.activityLogCardModeLive));
        // Contrast: a LIVE row reads Live.
        expect(modeOf('live'), l10n.activityLogCardModeLive);
      });

      test('T5 [$code] presenter: the private-event-shaped actions are '
          'unregistered and show no card title, card field or money', () async {
        final l10n = await _l10n(code);
        final presenter = AuditEventPresenter(l10n, 'ILS');
        // TEST attempt facts a private event could be confused with. None is
        // on the global allowlist; amount_minor is deliberately absent — it
        // IS a global money key (payment.recorded), and what keeps TEST money
        // away is the server: the private-event detail CHECK and
        // audit_safe_detail answering {} for test.*.
        const testFacts = <String, Object?>{
          'attempt_state': 'test_approved',
          'classification': 'test_approved',
          'mode': 'test',
          'currency_code': 'ILS',
          'provider_reference': 'MARKER-PROVIDER-REFERENCE',
          'terminal_ref': 'MARKER-TERMINAL-REF',
          'credential_ref': 'MARKER-CREDENTIAL-REF',
          'card_last4': 'MARKER-LAST-FOUR',
        };
        const shapes = <String, List<Map<String, Object?>>>{
          'test.card_attempt_denied': [
            {},
            {'rpc': 'MARKER-RPC-NAME', 'denied_reason': 'permission_denied'},
            {
              'rpc': 'MARKER-RPC-NAME',
              'denied_reason': 'permission_denied',
              ...testFacts,
            },
          ],
          'test.card_recording_refused': [
            {},
            {...testFacts},
          ],
        };
        final titles = _cardTitles(l10n);
        final fields = _cardFieldLabels(l10n);
        final values = _cardValueLabels(l10n);
        for (final MapEntry(key: action, value: payloads) in shapes.entries) {
          expect(kAuditActionRegistry.containsKey(action), isFalse);
          for (final category in const ['other', 'payments']) {
            for (final newValues in payloads) {
              final view = presenter.present(
                _event(action, category: category, newValues: newValues),
              );
              final where = '$action/$category/${newValues.keys}';
              expect(view.isKnownAction, isFalse, reason: where);
              expect(titles, isNot(contains(view.title)), reason: where);
              expect(view.title, auditCategoryLabel(l10n, category));
              for (final c in view.changes) {
                expect(fields, isNot(contains(c.label)), reason: where);
                expect(c.label, isNot(l10n.activityLogFieldAmount));
                expect(values, isNot(contains(c.newValue)), reason: where);
                expect(c.newValue.contains('₪'), isFalse, reason: where);
                expect(_moneyPattern.hasMatch(c.newValue), isFalse);
                expect(c.newValue.contains('MARKER-'), isFalse);
                expect(c.newValue.startsWith('test_'), isFalse);
              }
            }
          }
        }
      });
    }
  });

  // =========================================================================
  // T6 — the revoked-device carve-out is evidence, never an attempt fact.
  // =========================================================================
  group('T6 revoked-device carve-out', () {
    for (final code in _locales) {
      testWidgets('T6 [$code] a sync.operation_rejected (revoked_device) row '
          'renders with no card title, no card field and no money', (
        tester,
      ) async {
        _surface(tester, const Size(1400, 2800));
        final l10n = await _l10n(code);
        final server = _FakeServer(_World.liveWithTest, audit: _carveOutFeed);
        await tester.pumpWidget(
          _app(server, code, const Scaffold(body: ActivityLogScreen())),
        );
        await tester.pumpAndSettle();
        // The LIVE card rows still read as card rows: the absence below is
        // specific to the carve-out row.
        expect(
          find.descendant(
            of: find.byKey(const Key('activity-card-$_evtCardApproved')),
            matching: find.text(l10n.activityLogTitleCardAttemptApproved),
          ),
          findsOneWidget,
        );
        for (final id in const [_evtSyncWriter, _evtSyncProjected]) {
          final card = find.byKey(Key('activity-card-$id'));
          expect(card, findsOneWidget);
          expect(
            find.descendant(
              of: card,
              matching: find.text(l10n.activityLogCategorySync),
            ),
            findsWidgets,
          );
          _expectNoCardSurface(_texts(tester, card), l10n, where: 'row $id');
          await tester.tap(card);
          await tester.pumpAndSettle();
          final dialog = find.byKey(const Key('activity-detail-dialog'));
          expect(dialog, findsOneWidget);
          _expectNoCardSurface(
            _texts(tester, dialog),
            l10n,
            where: 'detail $id',
          );
          // No change row of any kind.
          expect(
            find.descendant(
              of: dialog,
              matching: find.text(l10n.activityLogChangesHeading),
            ),
            findsNothing,
          );
          await tester.tap(find.byKey(const Key('activity-detail-close')));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        _expectReportingOnly(server);
      });

      test('T6 [$code] presenter: both the projected and the writer payload '
          'surface no card field, no money and no TEST identity', () async {
        final l10n = await _l10n(code);
        final presenter = AuditEventPresenter(l10n, 'ILS');
        for (final newValues in const <Map<String, Object?>>[
          {},
          {
            'local_operation_id': 'MARKER-ATTEMPT-ID',
            'operation_type': 'payment.create',
            'reason': 'revoked_device',
          },
        ]) {
          final view = presenter.present(
            _event(
              'sync.operation_rejected',
              category: 'sync',
              reason: 'revoked_device',
              newValues: newValues,
            ),
          );
          expect(view.title, l10n.activityLogCategorySync);
          expect(_cardTitles(l10n), isNot(contains(view.title)));
          expect(view.isKnownAction, isFalse);
          // No change row at all: no card field and no money.
          expect(
            [for (final c in view.changes) '${c.label}=${c.newValue}'],
            isEmpty,
            reason: '${newValues.keys}',
          );
          expect(view.tone, isNot(RestoflowTone.success));
          _expectNoCardSurface(
            [view.title, view.categoryLabel, ?view.reason],
            l10n,
            where: 'presenter ${newValues.keys}',
          );
        }
      });
    }
  });
}
