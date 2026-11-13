/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-DASHBOARD-VERIFICATION, request §5: the
/// accepted 001D card-attempt Activity-log presentation, proven at WIDGET
/// level in en, ar and he for all twelve LIVE `card_attempt.*` actions.
///
/// Fifteen variants cover the twelve actions: `provider_anomaly` raised
/// (attempt_state `unknown`), cleared (`approved`) and generic (`sent`), and
/// `recording_resume_requested` dispatched and refused. Every row travels the
/// REAL read path: a fake transport answers `owner_audit_events` with rows in
/// the server's JSON shape (through a real JSON round trip), and
/// RealAuditLogRepository -> AuditLogController -> AuditEventPresenter ->
/// ActivityEventCard -> ActivityDetailDialog render them as in production.
/// Tests only: no production source is changed.
///
/// card_attempt_activity_log_test.dart (PR #370) keeps the presenter-level
/// unit coverage, mostly in en; this file adds the rendered surfaces. Matrix
/// (every UI row in en, ar and he):
///   A1  the title on the row card and in the dialog;
///   A2  projected fields only: the exact ordered change rows with localized
///       values, no old -> new arrow, no Reason row;
///   A3  hostile exclusion: unprojected keys, nested blobs, old values, a
///       free-text reason and money on any action but `.started` never
///       render (the client allowlist); a canary, the `.started` Amount row
///       and a non-card control prove the scans and the detectors can fire;
///   A4  money on `.started`: the row's ISO currency wins, an absent code
///       uses the page currency, a non-integer amount shows no Amount row;
///   A5  unknown tokens of every closed vocabulary render verbatim;
///   A6  the category pill's tone (card and dialog) and the icon;
///   A7  the Denied pill only on `card_attempt.denied`;
///   A8  TEST-looking tokens in projected keys, which no writer emits: mode
///       `test` reads Test, never Live; an out-of-vocabulary test_* state
///       renders raw; title, tone and icon follow the ACTION, so on a result
///       action the Dashboard cannot tell a TEST row from a LIVE one (the
///       Activity-log TEST exclusion is server-enforced);
///   A8b the owner-read TEST `classification` (`test_<state>`), `recorded`
///       and a result-row mode `test` never render: such a row reads exactly
///       as its LIVE variant;
///   A9  the registry pin (locale-free);
///   A10 an unregistered `card_attempt.mystery`: the category title, no
///       change rows and the generic note.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/activity/activity_log_screen.dart';
import 'package:restoflow_dashboard/src/data/audit_action_registry.dart';
import 'package:restoflow_dashboard/src/data/real_audit_log_repository.dart';
import 'package:restoflow_dashboard/src/format/money_format.dart';
import 'package:restoflow_dashboard/src/state/audit_log_providers.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const List<String> _locales = ['en', 'ar', 'he'];

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

// ===========================================================================
// The server side: rows in the shape app.owner_audit_events returns
// ===========================================================================

const _occurredAt = '2026-10-30 14:05';
const _actor = 'Amira';
const _restaurant = 'Rest One';
const _branch = 'Main';
const _device = 'POS One';

/// The dialog's scope line ("Restaurant · Branch").
const _scope = '$_restaurant · $_branch';

const List<String> _resultKeys = [
  'attempt_state',
  'refusal_code',
  'anomaly_code',
  'release_requested',
];

/// The twelve LIVE actions and the keys `app.audit_safe_detail` projects for
/// each, in projection order (API_CONTRACT §4.33; 001D packet §15.5).
const Map<String, List<String>> _projectedKeys = {
  'card_attempt.started': [
    'attempt_state',
    'mode',
    'amount_minor',
    'currency_code',
  ],
  'card_attempt.approved': _resultKeys,
  'card_attempt.declined': _resultKeys,
  'card_attempt.unknown': _resultKeys,
  'card_attempt.released': _resultKeys,
  'card_attempt.provider_anomaly': _resultKeys,
  'card_attempt.release_requested': ['attempt_state'],
  'card_attempt.release_failed': ['attempt_state'],
  'card_attempt.recording_refused': ['refusal_code'],
  'card_attempt.order_freed': ['attempt_state', 'confirmation_source'],
  'card_attempt.recording_resume_requested': [
    'attempt_state',
    'prior_refusal_code',
    'resume_count',
    'outcome',
    'denied_reason',
  ],
  'card_attempt.denied': ['denied_reason'],
};

/// One `owner_audit_events` row as the server builds it. A card row carries
/// no reason and empty old values (card_audit_write stores neither, and the
/// projection of NULL is `{}`); the hostile tests pass both explicitly.
Map<String, Object?> _serverRow(
  String id,
  String action,
  Map<String, Object?> newValues, {
  Map<String, Object?> oldValues = const {},
  String? reason,
  // app.audit_category maps card_attempt.% to payments.
  String category = 'payments',
}) => {
  'event_id': id,
  'action': action,
  'category': category,
  'occurred_at': _occurredAt,
  'timezone': 'UTC',
  'actor_name': _actor,
  'restaurant_id': 'rest-1',
  'restaurant_name': _restaurant,
  'branch_id': 'branch-1',
  'branch_name': _branch,
  'device_label': _device,
  'reason': reason,
  'old_values': oldValues,
  'new_values': newValues,
};

/// The authenticated transport of the REAL Activity log. It answers the three
/// RPCs the screen issues and sends every answer through a JSON round trip,
/// so the client sees exactly the types a decoded server response carries.
class _AuditTransport implements SyncRpcTransport {
  _AuditTransport(this.rows, {this.pageCurrency = 'ILS'});

  final List<Map<String, Object?>> rows;

  /// The page's `currency_code` (the organization's default currency).
  final String pageCurrency;

  final List<String> calls = <String>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(function);
    final Map<String, Object?> body = switch (function) {
      'owner_audit_events' => {
        'ok': true,
        'entity': 'owner_audit_events',
        'currency_code': pageCurrency,
        'range': params['p_range'],
        'limit': params['p_limit'],
        'events': rows,
        // One page: nothing is held back behind pagination.
        'has_more': false,
        'next_cursor': null,
        'count': rows.length,
      },
      'list_org_structure' => {
        'ok': true,
        'entity': 'org_structure',
        'restaurants': [
          {
            'id': 'rest-1',
            'name': _restaurant,
            'branches': [
              {'id': 'branch-1', 'name': _branch},
            ],
          },
        ],
      },
      'list_staff' => {'ok': true, 'staff': <Object?>[]},
      _ => {'ok': false},
    };
    return jsonDecode(jsonEncode(body));
  }
}

const _membership = MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Org One',
  restaurantId: 'rest-1',
  restaurantName: _restaurant,
  branchId: 'branch-1',
  branchName: _branch,
  role: MembershipRole.orgOwner,
  status: 'active',
);

final _realMode = RuntimeConfig.test(isDemoMode: false);

Widget _app(_AuditTransport transport, String code) => ProviderScope(
  overrides: [
    dashboardMembershipProvider.overrideWithValue(_membership),
    dashboardAuthTransportProvider.overrideWithValue(transport),
    runtimeConfigProvider.overrideWithValue(_realMode),
  ],
  child: MaterialApp(
    locale: Locale(code),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: const Scaffold(body: ActivityLogScreen()),
  ),
);

// ===========================================================================
// What the Dashboard must show
// ===========================================================================

/// A server payload and the change rows the dialog must show for it, as
/// (localized label, shown value) pairs in display order.
class _Case {
  const _Case({
    required this.id,
    required this.action,
    required this.values,
    required this.rows,
  });

  final String id;
  final String action;
  final Map<String, Object?> values;
  final List<(String, String)> Function(AppLocalizations l) rows;

  Map<String, Object?> get serverRow => _serverRow(id, action, values);
}

/// A payload plus the title, tone and icon the 001D packet (§15.5) gives it:
/// the fifteen accepted variants (each the projected payload of its action)
/// and the A8 TEST-token cases.
class _Variant extends _Case {
  const _Variant({
    required super.id,
    required super.action,
    required super.values,
    required super.rows,
    required this.title,
    required this.tone,
    required this.icon,
  });

  final String Function(AppLocalizations l) title;
  final RestoflowTone tone;
  final IconData icon;

  bool get isDenied => action == 'card_attempt.denied';
}

/// The four provider-result rows. `refusal_code` there is the release status
/// (packet §15.4a): the server's only token on these rows is release_failed.
List<(String, String)> _resultRows(
  AppLocalizations l,
  String state,
  String anomaly,
  String releaseRequested,
) => [
  (l.activityLogFieldCardState, state),
  (l.activityLogFieldCardReleaseStatus, l.activityLogCardRefusalReleaseFailed),
  (l.activityLogFieldCardAnomaly, anomaly),
  (l.activityLogFieldCardReleaseRequested, releaseRequested),
];

/// The fifteen variants. Each payload carries every key its action projects,
/// written in REVERSE projection order on purpose: the dialog must follow the
/// server projection order, never the order the keys arrive in.
final List<_Variant> _variants = [
  _Variant(
    id: 'ae-card-started',
    action: 'card_attempt.started',
    values: const {
      'currency_code': 'ILS',
      'amount_minor': 4250,
      'mode': 'live',
      'attempt_state': 'sent',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateSent),
      (l.activityLogFieldCardMode, l.activityLogCardModeLive),
      (l.activityLogFieldAmount, MoneyFormatter.formatMinor(4250, 'ILS')),
      (l.activityLogFieldCurrency, 'ILS'),
    ],
    title: (l) => l.activityLogTitleCardAttemptStarted,
    tone: RestoflowTone.info,
    icon: Icons.credit_card_outlined,
  ),
  _Variant(
    id: 'ae-card-approved',
    action: 'card_attempt.approved',
    values: const {
      'release_requested': true,
      'anomaly_code': 'preauthorization',
      'refusal_code': 'release_failed',
      'attempt_state': 'approved',
    },
    rows: (l) => _resultRows(
      l,
      l.activityLogCardStateApproved,
      l.activityLogCardAnomalyPreauthorization,
      l.activityLogYes,
    ),
    title: (l) => l.activityLogTitleCardAttemptApproved,
    tone: RestoflowTone.success,
    icon: Icons.credit_card_outlined,
  ),
  _Variant(
    id: 'ae-card-declined',
    action: 'card_attempt.declined',
    values: const {
      'release_requested': false,
      'anomaly_code': 'currency_mismatch',
      'refusal_code': 'release_failed',
      'attempt_state': 'declined',
    },
    rows: (l) => _resultRows(
      l,
      l.activityLogCardStateDeclined,
      l.activityLogCardAnomalyCurrencyMismatch,
      l.activityLogNo,
    ),
    title: (l) => l.activityLogTitleCardAttemptDeclined,
    tone: RestoflowTone.neutral,
    icon: Icons.credit_card_off_outlined,
  ),
  _Variant(
    id: 'ae-card-unknown',
    action: 'card_attempt.unknown',
    values: const {
      'release_requested': true,
      'anomaly_code': 'out_of_contract',
      'refusal_code': 'release_failed',
      'attempt_state': 'unknown',
    },
    rows: (l) => _resultRows(
      l,
      l.activityLogCardStateUnknown,
      l.activityLogCardAnomalyOutOfContract,
      l.activityLogYes,
    ),
    title: (l) => l.activityLogTitleCardAttemptUnknown,
    tone: RestoflowTone.warning,
    icon: Icons.help_outline,
  ),
  _Variant(
    id: 'ae-card-released',
    action: 'card_attempt.released',
    values: const {
      'release_requested': true,
      'anomaly_code': 'voided',
      'refusal_code': 'release_failed',
      'attempt_state': 'released',
    },
    rows: (l) => _resultRows(
      l,
      l.activityLogCardStateReleased,
      l.activityLogCardAnomalyVoided,
      l.activityLogYes,
    ),
    title: (l) => l.activityLogTitleCardAttemptReleased,
    tone: RestoflowTone.info,
    icon: Icons.credit_card_outlined,
  ),
  // provider_anomaly: the projected attempt_state decides raised / cleared /
  // generic (the server's charge_may_exist is never projected).
  _Variant(
    id: 'ae-card-anomaly-raised',
    action: 'card_attempt.provider_anomaly',
    values: const {
      'release_requested': false,
      'anomaly_code': 'amount_mismatch',
      'refusal_code': 'release_failed',
      'attempt_state': 'unknown',
    },
    rows: (l) => _resultRows(
      l,
      l.activityLogCardStateUnknown,
      l.activityLogCardAnomalyAmountMismatch,
      l.activityLogNo,
    ),
    title: (l) => l.activityLogTitleCardAttemptAnomalyRaised,
    tone: RestoflowTone.danger,
    icon: Icons.report_problem_outlined,
  ),
  _Variant(
    id: 'ae-card-anomaly-cleared',
    action: 'card_attempt.provider_anomaly',
    values: const {
      'release_requested': false,
      'anomaly_code': 'partial_refund',
      'refusal_code': 'release_failed',
      'attempt_state': 'approved',
    },
    rows: (l) => _resultRows(
      l,
      l.activityLogCardStateApproved,
      l.activityLogCardAnomalyPartialRefund,
      l.activityLogNo,
    ),
    title: (l) => l.activityLogTitleCardAttemptAnomalyCleared,
    tone: RestoflowTone.info,
    icon: Icons.credit_card_outlined,
  ),
  _Variant(
    id: 'ae-card-anomaly-generic',
    action: 'card_attempt.provider_anomaly',
    values: const {
      'release_requested': false,
      'anomaly_code': 'refunded',
      'refusal_code': 'release_failed',
      'attempt_state': 'sent',
    },
    rows: (l) => _resultRows(
      l,
      l.activityLogCardStateSent,
      l.activityLogCardAnomalyRefunded,
      l.activityLogNo,
    ),
    title: (l) => l.activityLogTitleCardAttemptAnomaly,
    tone: RestoflowTone.warning,
    icon: Icons.report_problem_outlined,
  ),
  _Variant(
    id: 'ae-card-release-requested',
    action: 'card_attempt.release_requested',
    values: const {'attempt_state': 'sent'},
    rows: (l) => [(l.activityLogFieldCardState, l.activityLogCardStateSent)],
    title: (l) => l.activityLogTitleCardAttemptReleaseRequested,
    tone: RestoflowTone.info,
    icon: Icons.credit_card_outlined,
  ),
  _Variant(
    id: 'ae-card-release-failed',
    action: 'card_attempt.release_failed',
    values: const {'attempt_state': 'unknown'},
    rows: (l) => [(l.activityLogFieldCardState, l.activityLogCardStateUnknown)],
    title: (l) => l.activityLogTitleCardAttemptReleaseFailed,
    tone: RestoflowTone.warning,
    icon: Icons.report_problem_outlined,
  ),
  _Variant(
    id: 'ae-card-recording-refused',
    action: 'card_attempt.recording_refused',
    values: const {'refusal_code': 'provider_recording_refused'},
    rows: (l) => [
      (
        l.activityLogFieldCardRefusal,
        l.activityLogCardRefusalProviderRecordingRefused,
      ),
    ],
    title: (l) => l.activityLogTitleCardAttemptRecordingRefused,
    tone: RestoflowTone.warning,
    icon: Icons.report_problem_outlined,
  ),
  _Variant(
    id: 'ae-card-order-freed',
    action: 'card_attempt.order_freed',
    values: const {
      'confirmation_source': 'provider_back_office',
      'attempt_state': 'released',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateReleased),
      (
        l.activityLogFieldCardConfirmationSource,
        l.activityLogCardConfirmationBackOffice,
      ),
    ],
    title: (l) => l.activityLogTitleCardAttemptOrderFreed,
    tone: RestoflowTone.warning,
    icon: Icons.lock_open_outlined,
  ),
  // The Resume writer stores no denied_reason on a dispatched retry; the
  // count is the raw number of EARLIER retries (0 on the first).
  _Variant(
    id: 'ae-card-resume-dispatched',
    action: 'card_attempt.recording_resume_requested',
    values: const {
      'outcome': 'dispatched',
      'resume_count': 0,
      'prior_refusal_code': 'conflict',
      'attempt_state': 'approved',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateApproved),
      (l.activityLogFieldCardPriorRefusal, l.activityLogCardRefusalConflict),
      (l.activityLogFieldCardResumeCount, '0'),
      (l.activityLogFieldCardResumeOutcome, l.activityLogCardResumeDispatched),
    ],
    title: (l) => l.activityLogTitleCardAttemptResumeRequested,
    tone: RestoflowTone.info,
    icon: Icons.replay_outlined,
  ),
  // A prior refusal of release_failed is the stored release fact, so it reads
  // as the release status (packet §15.4a re-review amendment).
  _Variant(
    id: 'ae-card-resume-refused',
    action: 'card_attempt.recording_resume_requested',
    values: const {
      'denied_reason': 'resume_limit',
      'outcome': 'refused',
      'resume_count': 2,
      'prior_refusal_code': 'release_failed',
      'attempt_state': 'approved',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateApproved),
      (
        l.activityLogFieldCardReleaseStatus,
        l.activityLogCardRefusalReleaseFailed,
      ),
      (l.activityLogFieldCardResumeCount, '2'),
      (l.activityLogFieldCardResumeOutcome, l.activityLogCardResumeRefused),
      (l.activityLogFieldDeniedReason, l.activityLogDeniedResumeLimit),
    ],
    title: (l) => l.activityLogTitleCardAttemptResumeRequested,
    tone: RestoflowTone.warning,
    icon: Icons.replay_outlined,
  ),
  // card_attempt.denied's permission_denied has the card family's own
  // device-or-role label (packet §15.4a).
  _Variant(
    id: 'ae-card-denied',
    action: 'card_attempt.denied',
    values: const {'denied_reason': 'permission_denied'},
    rows: (l) => [
      (l.activityLogFieldDeniedReason, l.activityLogDeniedCardPermission),
    ],
    title: (l) => l.activityLogTitleCardAttemptDenied,
    tone: RestoflowTone.warning,
    icon: Icons.block_outlined,
  ),
];

List<Map<String, Object?>> _variantRows() => [
  for (final v in _variants) v.serverRow,
];

/// The dialog's fixed detail rows for every row above. There is never a
/// Reason row for the card family.
List<(String, String)> _expectedDetailRows(AppLocalizations l) => [
  (l.activityLogFieldWhen, _occurredAt),
  (l.activityLogFieldActor, _actor),
  (l.activityLogFieldScopeLocation, _scope),
  (l.activityLogFieldDevice, _device),
];

/// Every text of the dialog, in order: the header (title, category pill,
/// Denied pill), the detail rows, then the change rows or the generic note.
List<String> _expectedDialogTexts(
  AppLocalizations l, {
  required String title,
  required List<(String, String)> rows,
  bool denied = false,
  bool known = true,
}) => [
  title,
  l.activityLogCategoryPayments,
  if (denied) l.activityLogDenied,
  for (final (label, value) in _expectedDetailRows(l)) ...[label, value],
  if (rows.isNotEmpty) l.activityLogChangesHeading,
  for (final (label, value) in rows) ...[label, value],
  if (!known) l.activityLogGenericNote,
];

// ---------------------------------------------------------------------------
// A3: hostile payloads
// ---------------------------------------------------------------------------

/// Invented keys the server never projects. Every value is a letters-and-
/// hyphens marker, so one substring scan finds any leak.
const Map<String, Object?> _hostileExtras = {
  'provider_reference': 'MARKER-PROVIDER-REFERENCE',
  'terminal_ref': 'MARKER-TERMINAL-REF',
  'credential_ref': 'MARKER-CREDENTIAL-REF',
  'merchant_id': 'MARKER-MERCHANT-ID',
  'merchant_key': 'MARKER-MERCHANT-KEY',
  'local_operation_id': 'MARKER-LOCAL-OPERATION-ID',
  'attempt_row_id': 'MARKER-ATTEMPT-ROW-ID',
  'device_id': 'MARKER-DEVICE-ID',
  'employee_profile_id': 'MARKER-EMPLOYEE-PROFILE-ID',
  'membership_id': 'MARKER-MEMBERSHIP-ID',
  'approval_number': 'MARKER-APPROVAL-NUMBER',
  'voucher_number': 'MARKER-VOUCHER-NUMBER',
  'card_last4': 'MARKER-LAST-FOUR',
  'card_brand_code': 'MARKER-BRAND-CODE',
  'confirmation_reference': 'MARKER-CONFIRMATION-REFERENCE',
  'order_freed_note': 'MARKER-ORDER-FREED-NOTE',
  'resolution_reference': 'MARKER-RESOLUTION-REFERENCE',
  'requested_by': 'MARKER-REQUESTED-BY',
  'requester_employee_profile_id': 'MARKER-REQUESTER-EMPLOYEE-PROFILE-ID',
  'payload': {
    'provider_reference': 'MARKER-PAYLOAD-PROVIDER-REFERENCE',
    'terminal_ref': 'MARKER-PAYLOAD-TERMINAL-REF',
    'attempt_state': 'MARKER-PAYLOAD-ATTEMPT-STATE',
  },
  'recording_resume_history': [
    {
      'employee_profile_id': 'MARKER-HISTORY-EMPLOYEE-PROFILE-ID',
      'membership_id': 'MARKER-HISTORY-MEMBERSHIP-ID',
      'local_operation_id': 'MARKER-HISTORY-LOCAL-OPERATION-ID',
    },
  ],
};

/// Money under the `.started`-only keys (API_CONTRACT §4.33 "Money keys"),
/// spread into every hostile row but `.started`. It is kept out of
/// [_hostileExtras] so `.started` keeps its own amount (A3's positive
/// control) and the marker guards stay exact. The amount is an int on
/// purpose: a non-integer amount never reaches the money formatter, so it
/// could not prove the exclusion.
const Map<String, Object?> _hostileMoney = {
  'amount_minor': 9999,
  'currency_code': 'USD',
};

/// Old values under PROJECTED key names: only the family rule (new values
/// only, no old -> new) keeps them off the screen.
const Map<String, Object?> _hostileOldValues = {
  'attempt_state': 'MARKER-OLD-ATTEMPT-STATE',
  'mode': 'MARKER-OLD-MODE',
  'refusal_code': 'MARKER-OLD-REFUSAL-CODE',
  'denied_reason': 'MARKER-OLD-DENIED-REASON',
  'provider_reference': 'MARKER-OLD-PROVIDER-REFERENCE',
};

const _hostileReason = 'MARKER-FREE-TEXT-REASON';
const _nestedMapMarker = 'MARKER-NESTED-MAP-STATE';
const _nestedListMarker = 'MARKER-NESTED-LIST-STATE';

/// The positive control of the scan: a scalar in a PROJECTED key renders raw,
/// so the same scan that finds no marker must find this token.
const _canaryState = 'CANARY-RENDERED-STATE';

Iterable<String> _strings(Object? value) sync* {
  if (value is String) {
    yield value;
  } else if (value is Map) {
    for (final v in value.values) {
      yield* _strings(v);
    }
  } else if (value is List) {
    for (final v in value) {
      yield* _strings(v);
    }
  }
}

/// Every hostile value the A3 rows carry.
final Set<String> _markers = {
  ..._strings(_hostileExtras),
  ..._strings(_hostileOldValues),
  _hostileReason,
  _nestedMapMarker,
  _nestedListMarker,
};

/// The fifteen variants with the hostile extras, old values and reason (and
/// the hostile money on every action but `.started`), plus two rows whose
/// PROJECTED key holds a nested map or list, and the canary.
List<Map<String, Object?>> _hostileRows() => [
  for (final v in _variants)
    _serverRow(
      v.id,
      v.action,
      {
        ...v.values,
        ..._hostileExtras,
        if (v.action != 'card_attempt.started') ..._hostileMoney,
      },
      oldValues: _hostileOldValues,
      reason: _hostileReason,
    ),
  _serverRow(
    'ae-card-nested-map',
    'card_attempt.release_requested',
    {
      'attempt_state': {'value': _nestedMapMarker},
      ..._hostileExtras,
      ..._hostileMoney,
    },
    oldValues: _hostileOldValues,
    reason: _hostileReason,
  ),
  _serverRow(
    'ae-card-nested-list',
    'card_attempt.release_failed',
    {
      'attempt_state': [_nestedListMarker],
      ..._hostileExtras,
      ..._hostileMoney,
    },
    oldValues: _hostileOldValues,
    reason: _hostileReason,
  ),
  _serverRow(
    'ae-card-canary',
    'card_attempt.release_requested',
    {'attempt_state': _canaryState, ..._hostileExtras, ..._hostileMoney},
    oldValues: _hostileOldValues,
    reason: _hostileReason,
  ),
];

const _controlReason = 'CONTROL-VOID-REASON';

/// The detector control: a NON-card row (order.voided) with a reason and an
/// old -> new status, both of which that family does show. Seeing them proves
/// the Reason-row and arrow detectors can fire, so their silence on the card
/// rows is real.
Map<String, Object?> _controlRow() => _serverRow(
  'ae-control-voided',
  'order.voided',
  const {'status': 'voided'},
  oldValues: const {'status': 'submitted'},
  reason: _controlReason,
  category: 'voids',
);

// ---------------------------------------------------------------------------
// A5 / A8: tokens outside the localized vocabularies
// ---------------------------------------------------------------------------

/// Invented future tokens of every closed vocabulary: an honest unknown shows
/// raw rather than a confident mislabel.
final List<_Case> _rawTokenCases = [
  _Case(
    id: 'ae-raw-state',
    action: 'card_attempt.release_requested',
    values: const {'attempt_state': 'unforeseen_state'},
    rows: (l) => [(l.activityLogFieldCardState, 'unforeseen_state')],
  ),
  _Case(
    id: 'ae-raw-mode',
    action: 'card_attempt.started',
    values: const {
      'attempt_state': 'sent',
      'mode': 'unforeseen_mode',
      'amount_minor': 1500,
      'currency_code': 'ILS',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateSent),
      (l.activityLogFieldCardMode, 'unforeseen_mode'),
      (l.activityLogFieldAmount, MoneyFormatter.formatMinor(1500, 'ILS')),
      (l.activityLogFieldCurrency, 'ILS'),
    ],
  ),
  _Case(
    id: 'ae-raw-refusal',
    action: 'card_attempt.recording_refused',
    values: const {'refusal_code': 'unforeseen_refusal'},
    rows: (l) => [(l.activityLogFieldCardRefusal, 'unforeseen_refusal')],
  ),
  _Case(
    id: 'ae-raw-release-status',
    action: 'card_attempt.approved',
    values: const {
      'attempt_state': 'approved',
      'refusal_code': 'unforeseen_release',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateApproved),
      (l.activityLogFieldCardReleaseStatus, 'unforeseen_release'),
    ],
  ),
  _Case(
    id: 'ae-raw-anomaly',
    action: 'card_attempt.provider_anomaly',
    values: const {
      'attempt_state': 'unknown',
      'anomaly_code': 'unforeseen_anomaly',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateUnknown),
      (l.activityLogFieldCardAnomaly, 'unforeseen_anomaly'),
    ],
  ),
  _Case(
    id: 'ae-raw-confirmation',
    action: 'card_attempt.order_freed',
    values: const {
      'attempt_state': 'released',
      'confirmation_source': 'unforeseen_source',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateReleased),
      (l.activityLogFieldCardConfirmationSource, 'unforeseen_source'),
    ],
  ),
  _Case(
    id: 'ae-raw-outcome',
    action: 'card_attempt.recording_resume_requested',
    values: const {
      'attempt_state': 'approved',
      'prior_refusal_code': 'unforeseen_prior_refusal',
      'resume_count': 1,
      'outcome': 'unforeseen_outcome',
      'denied_reason': 'unforeseen_resume_reason',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateApproved),
      (l.activityLogFieldCardPriorRefusal, 'unforeseen_prior_refusal'),
      (l.activityLogFieldCardResumeCount, '1'),
      (l.activityLogFieldCardResumeOutcome, 'unforeseen_outcome'),
      (l.activityLogFieldDeniedReason, 'unforeseen_resume_reason'),
    ],
  ),
  _Case(
    id: 'ae-raw-denied',
    action: 'card_attempt.denied',
    values: const {'denied_reason': 'unforeseen_denied_reason'},
    rows: (l) => [(l.activityLogFieldDeniedReason, 'unforeseen_denied_reason')],
  ),
];

/// TEST-looking tokens in PROJECTED keys: mode `test` on `.started`, and the
/// out-of-vocabulary states test_approved and test_unknown. No 001D/001E
/// writer emits these: every tenant `card_attempt.*` write is LIVE-only,
/// attempt_state is the ledger state (sent|approved|declined|unknown|released)
/// and `.started` hard-codes mode live; `test_<state>` exists only as the
/// owner-read `classification`, which app.audit_safe_detail never projects
/// (A8b). These pin only the localized Test mode and the raw-token fallback.
/// Title and tone follow the ACTION, so on a result action the Dashboard
/// cannot tell a TEST row from a LIVE one; Activity-log TEST exclusion is
/// server-enforced (TI-24, TI-61, TI-62).
final List<_Variant> _testTokenCases = [
  _Variant(
    id: 'ae-test-mode',
    action: 'card_attempt.started',
    values: const {
      'attempt_state': 'sent',
      'mode': 'test',
      'amount_minor': 1500,
      'currency_code': 'ILS',
    },
    rows: (l) => [
      (l.activityLogFieldCardState, l.activityLogCardStateSent),
      (l.activityLogFieldCardMode, l.activityLogCardModeTest),
      (l.activityLogFieldAmount, MoneyFormatter.formatMinor(1500, 'ILS')),
      (l.activityLogFieldCurrency, 'ILS'),
    ],
    title: (l) => l.activityLogTitleCardAttemptStarted,
    tone: RestoflowTone.info,
    icon: Icons.credit_card_outlined,
  ),
  // The LIVE approval's title and its success tone: the action decides.
  _Variant(
    id: 'ae-test-approved',
    action: 'card_attempt.approved',
    values: const {
      'attempt_state': 'test_approved',
      'release_requested': false,
    },
    rows: (l) => [
      (l.activityLogFieldCardState, 'test_approved'),
      (l.activityLogFieldCardReleaseRequested, l.activityLogNo),
    ],
    title: (l) => l.activityLogTitleCardAttemptApproved,
    tone: RestoflowTone.success,
    icon: Icons.credit_card_outlined,
  ),
  _Variant(
    id: 'ae-test-unknown',
    action: 'card_attempt.unknown',
    values: const {'attempt_state': 'test_unknown', 'release_requested': false},
    rows: (l) => [
      (l.activityLogFieldCardState, 'test_unknown'),
      (l.activityLogFieldCardReleaseRequested, l.activityLogNo),
    ],
    title: (l) => l.activityLogTitleCardAttemptUnknown,
    tone: RestoflowTone.warning,
    icon: Icons.help_outline,
  ),
];

/// The localized label each TEST case must NOT show.
final Map<String, String Function(AppLocalizations l)> _neverShown = {
  'ae-test-mode': (l) => l.activityLogCardModeLive,
  'ae-test-approved': (l) => l.activityLogCardStateApproved,
  'ae-test-unknown': (l) => l.activityLogCardStateUnknown,
};

// ---------------------------------------------------------------------------
// A8b: the owner-read TEST classification
// ---------------------------------------------------------------------------

/// The five provider-result actions. `mode` is not projected on them, so a
/// TEST mode there must add nothing; on `.started` it is projected and reads
/// Test (A8).
const Set<String> _resultActions = {
  'card_attempt.approved',
  'card_attempt.declined',
  'card_attempt.unknown',
  'card_attempt.released',
  'card_attempt.provider_anomaly',
};

/// The LIVE variants of `.started` and the five result actions
/// (provider_anomaly raised, cleared and generic): eight rows.
final List<_Variant> _classifiedVariants = [
  for (final v in _variants)
    if (v.action == 'card_attempt.started' || _resultActions.contains(v.action))
      v,
];

String _classifiedId(_Variant v) => '${v.id}-cls';

/// [v] plus what only the owner-read TEST ledger derives (001D
/// app.card_attempt_derive): `classification` set to `test_<state>` and
/// `recorded` set to false, and mode `test` on the result actions, where mode
/// is not projected. app.audit_safe_detail never projects any of these, so
/// the row must read exactly like [v].
Map<String, Object?> _classifiedRow(_Variant v) =>
    _serverRow(_classifiedId(v), v.action, {
      ...v.values,
      'classification': 'test_${v.values['attempt_state']}',
      'recorded': false,
      if (_resultActions.contains(v.action)) 'mode': 'test',
    });

/// What a rendered classification would leave on screen (compared in lower
/// case).
const List<String> _classificationTraces = ['test_', 'classification'];

/// The positive control of that scan: a TEST-looking token in a PROJECTED
/// key does render (raw), so the scan that finds no trace on the classified
/// rows can fire.
const _classificationCanary = 'test_classification';

// ===========================================================================
// Harness helpers
// ===========================================================================

/// A tall, wide surface: every row and the whole dialog stay on screen.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the real-mode Activity log over [rows] and checks they arrived
/// through the real repository, one card per row.
Future<void> _pumpLog(
  WidgetTester tester,
  String code,
  List<Map<String, Object?>> rows, {
  String pageCurrency = 'ILS',
}) async {
  final transport = _AuditTransport(rows, pageCurrency: pageCurrency);
  await tester.pumpWidget(_app(transport, code));
  await tester.pumpAndSettle();
  expect(transport.calls, contains('owner_audit_events'), reason: code);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ActivityLogScreen)),
  );
  expect(
    container.read(auditLogRepositoryProvider),
    isA<RealAuditLogRepository>(),
    reason: code,
  );
  for (final row in rows) {
    final id = row['event_id'] as String;
    expect(_card(id), findsOneWidget, reason: '$code $id');
  }
}

Finder _card(String id) => find.byKey(Key('activity-card-$id'));

Finder get _dialog => find.byKey(const Key('activity-detail-dialog'));

Future<void> _open(WidgetTester tester, String id) async {
  final card = _card(id);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
  expect(_dialog, findsOneWidget, reason: id);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('activity-detail-close')));
  await tester.pumpAndSettle();
  expect(_dialog, findsNothing);
}

/// Every [Text] under [scope], in tree order.
List<String> _texts(WidgetTester tester, Finder scope) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: scope, matching: find.byType(Text)),
  ))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

/// Everything the screen renders right now (list and dialog) as plain text:
/// every RichText, onstage or not, so nothing hidden escapes the scan.
String _renderedText(WidgetTester tester) => [
  for (final r in tester.widgetList<RichText>(
    find.byType(RichText, skipOffstage: false),
  ))
    r.text.toPlainText(),
].join('\n');

/// The dialog rows laid out as `label | Text` (When / By / Location / Device,
/// and the Reason row a non-card family can show).
List<(String, String)> _detailRows(WidgetTester tester) =>
    _dialogRows(tester, changeRows: false);

/// The dialog's change rows, laid out as `label | Wrap`. A struck-through old
/// value or the old -> new arrow would appear in the joined value.
List<(String, String)> _changeRows(WidgetTester tester) =>
    _dialogRows(tester, changeRows: true);

List<(String, String)> _dialogRows(
  WidgetTester tester, {
  required bool changeRows,
}) {
  final out = <(String, String)>[];
  for (final row in tester.widgetList<Row>(
    find.descendant(of: _dialog, matching: find.byType(Row)),
  )) {
    if (row.children.length != 3) continue;
    final label = row.children.first;
    final value = row.children.last;
    if (label is! SizedBox || label.child is! Text) continue;
    if (value is! Expanded) continue;
    final labelText = (label.child as Text).data ?? '';
    final child = value.child;
    if (changeRows && child is Wrap) {
      final parts = [
        for (final w in child.children)
          if (w is Text) w.data ?? '' else if (w is Icon) '->' else '?',
      ];
      out.add((labelText, parts.join(' ')));
    } else if (!changeRows && child is Text) {
      out.add((labelText, child.data ?? ''));
    }
  }
  return out;
}

/// The status pills labelled [label] inside [scope].
Finder _pills(Finder scope, String label) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) => w is RestoflowStatusPill && w.label == label,
  ),
);

/// The tone of the category pill (the Payments label) inside [scope].
RestoflowTone _categoryTone(
  WidgetTester tester,
  Finder scope,
  AppLocalizations l,
) => tester
    .widget<RestoflowStatusPill>(_pills(scope, l.activityLogCategoryPayments))
    .tone;

/// The event icon: the first [Icon] inside [scope] (card or dialog header).
IconData? _leadingIcon(WidgetTester tester, Finder scope) => tester
    .widgetList<Icon>(find.descendant(of: scope, matching: find.byType(Icon)))
    .first
    .icon;

void _expectNoMarker(WidgetTester tester, String why) {
  final text = _renderedText(tester);
  expect(
    [
      for (final m in _markers)
        if (text.contains(m)) m,
    ],
    isEmpty,
    reason: why,
  );
  // Belt and braces: no marker of any spelling.
  expect(text.contains('MARKER'), isFalse, reason: why);
}

/// No trace of [_hostileMoney] anywhere on screen (not as [formatted], its
/// pinned USD rendering, not in another currency and not raw), and no Amount
/// or Currency row in the open dialog.
void _expectNoHostileMoney(
  WidgetTester tester,
  AppLocalizations l,
  String formatted,
  String why,
) {
  final text = _renderedText(tester);
  for (final trace in [formatted, '99.99', '9999', 'USD']) {
    expect(text, isNot(contains(trace)), reason: '$why $trace');
  }
  for (final label in [l.activityLogFieldAmount, l.activityLogFieldCurrency]) {
    expect(
      find.descendant(of: _dialog, matching: find.text(label)),
      findsNothing,
      reason: '$why $label',
    );
  }
}

void main() {
  group('A1 title', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] every variant shows its own title on the row card and in the '
        'dialog',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          await _pumpLog(tester, code, _variantRows());
          for (final v in _variants) {
            final why = '$code ${v.id}';
            final title = v.title(l);
            // A specific title, never the category fallback.
            expect(title, isNot(l.activityLogCategoryPayments), reason: why);
            expect(
              find.descendant(of: _card(v.id), matching: find.text(title)),
              findsOneWidget,
              reason: why,
            );
            expect(_texts(tester, _card(v.id)).first, title, reason: why);

            await _open(tester, v.id);
            expect(
              Directionality.of(tester.element(_dialog)),
              code == 'en' ? TextDirection.ltr : TextDirection.rtl,
              reason: why,
            );
            expect(
              find.descendant(of: _dialog, matching: find.text(title)),
              findsOneWidget,
              reason: why,
            );
            expect(_texts(tester, _dialog).first, title, reason: why);
            await _close(tester);
          }
          // Raised, cleared and generic are three different anomaly titles.
          expect(
            {
              for (final v in _variants)
                if (v.action == 'card_attempt.provider_anomaly') v.title(l),
            },
            hasLength(3),
            reason: code,
          );
        },
      );
    }
  });

  group('A2 projected fields only', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] the dialog shows exactly the projected rows, in order, with '
        'localized values; no old -> new arrow and no Reason row',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          await _pumpLog(tester, code, _variantRows());
          for (final v in _variants) {
            final why = '$code ${v.id}';
            // Fixture guard: the payload is the action's projection only.
            expect(
              _projectedKeys[v.action],
              containsAll(v.values.keys),
              reason: why,
            );
            final rows = v.rows(l);
            expect(rows, hasLength(v.values.length), reason: why);

            await _open(tester, v.id);
            expect(_changeRows(tester), rows, reason: why);
            expect(_detailRows(tester), _expectedDetailRows(l), reason: why);
            expect(
              find.descendant(
                of: _dialog,
                matching: find.byIcon(Icons.arrow_forward),
              ),
              findsNothing,
              reason: why,
            );
            // Nothing else anywhere in the dialog.
            expect(
              _texts(tester, _dialog),
              _expectedDialogTexts(
                l,
                title: v.title(l),
                rows: rows,
                denied: v.isDenied,
              ),
              reason: why,
            );
            await _close(tester);
          }
        },
      );
    }
  });

  group('A3 hostile exclusion', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] unprojected keys, nested blobs, old values and a free-text '
        'reason never render on the list or in any dialog',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          // Fixture guard: every hostile value is a marker, so the scans
          // below can only pass when nothing leaks.
          expect(_markers, hasLength(33));
          expect(_markers.every((m) => m.startsWith('MARKER-')), isTrue);
          // Pinned, so the money scans below can never pass vacuously.
          final hostileUsd = MoneyFormatter.formatMinor(9999, 'USD');
          expect(hostileUsd, r'$99.99');

          await _pumpLog(tester, code, [..._hostileRows(), _controlRow()]);
          _expectNoMarker(tester, '$code list');
          // Positive control: the list scan does read the cards.
          expect(
            _renderedText(tester),
            contains(_variants.first.title(l)),
            reason: '$code list',
          );
          for (final v in _variants) {
            final why = '$code ${v.id}';
            await _open(tester, v.id);
            _expectNoMarker(tester, why);
            // The extras add nothing: still exactly the projected rows ...
            expect(_changeRows(tester), v.rows(l), reason: why);
            // ... and neither the reason (a Reason row) nor an old value (an
            // old -> new arrow) shows.
            expect(_detailRows(tester), _expectedDetailRows(l), reason: why);
            expect(
              find.descendant(
                of: _dialog,
                matching: find.byIcon(Icons.arrow_forward),
              ),
              findsNothing,
              reason: why,
            );
            // Money renders on `.started` only: its own Amount and Currency
            // rows are the positive control that the label finders fire, and
            // the hostile 9999 USD leaves no trace on any other action.
            if (v.action == 'card_attempt.started') {
              for (final label in [
                l.activityLogFieldAmount,
                l.activityLogFieldCurrency,
              ]) {
                expect(
                  find.descendant(of: _dialog, matching: find.text(label)),
                  findsOneWidget,
                  reason: '$why $label',
                );
              }
            } else {
              _expectNoHostileMoney(tester, l, hostileUsd, why);
            }
            await _close(tester);
          }
          // A nested map or list under a PROJECTED key renders no row either.
          for (final id in const [
            'ae-card-nested-map',
            'ae-card-nested-list',
          ]) {
            final why = '$code $id';
            await _open(tester, id);
            _expectNoMarker(tester, why);
            _expectNoHostileMoney(tester, l, hostileUsd, why);
            expect(_changeRows(tester), isEmpty, reason: why);
            expect(
              find.descendant(
                of: _dialog,
                matching: find.text(l.activityLogChangesHeading),
              ),
              findsNothing,
              reason: why,
            );
            await _close(tester);
          }
          // Positive control: the dialog scan does read rendered values. The
          // canary (a raw token in a projected key) is found by it, beside
          // the same hostile extras, and still no marker is.
          await _open(tester, 'ae-card-canary');
          expect(
            _renderedText(tester),
            contains(_canaryState),
            reason: '$code canary',
          );
          _expectNoMarker(tester, '$code canary');
          _expectNoHostileMoney(tester, l, hostileUsd, '$code canary');
          expect(_changeRows(tester), [
            (l.activityLogFieldCardState, _canaryState),
          ], reason: '$code canary');
          await _close(tester);

          // Detector control: where a family DOES show a reason and an old
          // value, the same helpers see the Reason row and the arrow.
          await _open(tester, 'ae-control-voided');
          expect(_detailRows(tester), [
            ..._expectedDetailRows(l),
            (l.activityLogFieldReason, _controlReason),
          ], reason: '$code control');
          expect(_changeRows(tester), [
            (l.activityLogFieldStatus, 'submitted -> voided'),
          ], reason: '$code control');
          expect(
            find.descendant(
              of: _dialog,
              matching: find.byIcon(Icons.arrow_forward),
            ),
            findsOneWidget,
            reason: '$code control',
          );
          await _close(tester);
        },
      );
    }
  });

  group('A4 money', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] .started shows the row ISO currency, falls back to the page '
        'currency, and never shows a non-integer amount',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          final usd = MoneyFormatter.formatMinor(4250, 'USD');
          final ils = MoneyFormatter.formatMinor(4250, 'ILS');
          final eur = MoneyFormatter.formatMinor(4250, 'EUR');
          // Pinned, so the comparisons below can never pass vacuously.
          expect(usd, r'$42.50');
          expect(ils, '₪42.50');
          expect(eur, '€42.50');
          final head = [
            (l.activityLogFieldCardState, l.activityLogCardStateSent),
            (l.activityLogFieldCardMode, l.activityLogCardModeLive),
          ];
          const usdRow = {
            'attempt_state': 'sent',
            'mode': 'live',
            'amount_minor': 4250,
            'currency_code': 'USD',
          };
          const noCodeRow = {
            'attempt_state': 'sent',
            'mode': 'live',
            'amount_minor': 4250,
          };

          // Page currency ILS.
          await _pumpLog(tester, code, [
            _serverRow('ae-money-usd', 'card_attempt.started', usdRow),
            _serverRow('ae-money-page', 'card_attempt.started', noCodeRow),
            _serverRow('ae-money-text', 'card_attempt.started', const {
              'attempt_state': 'sent',
              'mode': 'live',
              'amount_minor': '4250',
              'currency_code': 'ILS',
            }),
            _serverRow('ae-money-fraction', 'card_attempt.started', const {
              'attempt_state': 'sent',
              'mode': 'live',
              'amount_minor': 42.5,
              'currency_code': 'ILS',
            }),
          ]);
          await _open(tester, 'ae-money-usd');
          expect(_changeRows(tester), [
            ...head,
            (l.activityLogFieldAmount, usd),
            (l.activityLogFieldCurrency, 'USD'),
          ], reason: '$code row USD under page ILS');
          await _close(tester);

          await _open(tester, 'ae-money-page');
          expect(_changeRows(tester), [
            ...head,
            (l.activityLogFieldAmount, ils),
          ], reason: '$code no currency_code -> page ILS');
          await _close(tester);

          // D-007: only an integer minor amount renders.
          for (final id in const ['ae-money-text', 'ae-money-fraction']) {
            await _open(tester, id);
            expect(_changeRows(tester), [
              ...head,
              (l.activityLogFieldCurrency, 'ILS'),
            ], reason: '$code $id');
            expect(
              _texts(
                tester,
                _dialog,
              ).where((t) => t.contains('4250') || t.contains('42.5')),
              isEmpty,
              reason: '$code $id',
            );
            await _close(tester);
          }

          // A fresh page in EUR: the absent code follows THIS page, while a
          // row's own code still wins.
          await tester.pumpWidget(const SizedBox.shrink());
          await _pumpLog(tester, code, [
            _serverRow('ae-money-usd', 'card_attempt.started', usdRow),
            _serverRow('ae-money-page', 'card_attempt.started', noCodeRow),
          ], pageCurrency: 'EUR');
          await _open(tester, 'ae-money-page');
          expect(_changeRows(tester), [
            ...head,
            (l.activityLogFieldAmount, eur),
          ], reason: '$code no currency_code -> page EUR');
          await _close(tester);
          await _open(tester, 'ae-money-usd');
          expect(_changeRows(tester), [
            ...head,
            (l.activityLogFieldAmount, usd),
            (l.activityLogFieldCurrency, 'USD'),
          ], reason: '$code row USD under page EUR');
          await _close(tester);
        },
      );
    }
  });

  group('A5 raw-token fallback', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] unknown attempt_state, mode, refusal_code, anomaly_code, '
        'confirmation_source, outcome and denied_reason tokens render verbatim',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          await _pumpLog(tester, code, [
            for (final c in _rawTokenCases) c.serverRow,
          ]);
          for (final c in _rawTokenCases) {
            await _open(tester, c.id);
            expect(_changeRows(tester), c.rows(l), reason: '$code ${c.id}');
            await _close(tester);
          }
        },
      );
    }
  });

  group('A6 tone and icon', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] the category pill tone on the card and in the dialog, and '
        'the icon, follow the variant; approved is the only success',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          await _pumpLog(tester, code, _variantRows());
          final success = <String>[];
          for (final v in _variants) {
            final why = '$code ${v.id}';
            final cardTone = _categoryTone(tester, _card(v.id), l);
            expect(cardTone, v.tone, reason: '$why card pill');
            expect(
              _leadingIcon(tester, _card(v.id)),
              v.icon,
              reason: '$why card icon',
            );
            if (cardTone == RestoflowTone.success) success.add(v.id);

            await _open(tester, v.id);
            expect(
              _categoryTone(tester, _dialog, l),
              v.tone,
              reason: '$why dialog pill',
            );
            expect(
              _leadingIcon(tester, _dialog),
              v.icon,
              reason: '$why dialog icon',
            );
            await _close(tester);
          }
          // A provider approval is the ONLY success in the family.
          expect(success, ['ae-card-approved'], reason: code);
        },
      );
    }
  });

  group('A7 Denied pill', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] only card_attempt.denied carries the Denied pill, on the card '
        'and in the dialog; the refused Resume does not',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          await _pumpLog(tester, code, _variantRows());
          // Exactly one Denied pill on the whole list.
          expect(
            _pills(find.byType(ActivityLogScreen), l.activityLogDenied),
            findsOneWidget,
            reason: code,
          );
          for (final v in _variants) {
            final why = '$code ${v.id}';
            // The refused Resume carries outcome refused and a denied_reason,
            // yet the pill is action-scoped: it must stay absent there too.
            final expected = v.isDenied ? findsOneWidget : findsNothing;
            final onCard = _pills(_card(v.id), l.activityLogDenied);
            expect(onCard, expected, reason: '$why card');
            await _open(tester, v.id);
            final inDialog = _pills(_dialog, l.activityLogDenied);
            expect(inDialog, expected, reason: '$why dialog');
            if (v.isDenied) {
              for (final pill in [
                tester.widget<RestoflowStatusPill>(onCard),
                tester.widget<RestoflowStatusPill>(inDialog),
              ]) {
                expect(pill.tone, RestoflowTone.warning, reason: why);
                expect(pill.icon, Icons.block_outlined, reason: why);
              }
            }
            await _close(tester);
          }
        },
      );
    }
  });

  group('A8 TEST tokens', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] mode test reads the localized Test label, never Live; '
        'test_approved and test_unknown render raw in the state row; title '
        'and tone follow the action',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          expect(
            l.activityLogCardModeTest,
            isNot(l.activityLogCardModeLive),
            reason: code,
          );
          await _pumpLog(tester, code, [
            for (final c in _testTokenCases) c.serverRow,
          ]);
          for (final c in _testTokenCases) {
            final why = '$code ${c.id}';
            final title = c.title(l);
            // The row card: the ACTION's title, tone and icon.
            expect(_texts(tester, _card(c.id)).first, title, reason: why);
            expect(
              _categoryTone(tester, _card(c.id), l),
              c.tone,
              reason: '$why card pill',
            );
            expect(
              _leadingIcon(tester, _card(c.id)),
              c.icon,
              reason: '$why card icon',
            );

            await _open(tester, c.id);
            expect(_changeRows(tester), c.rows(l), reason: why);
            expect(
              find.descendant(
                of: _dialog,
                matching: find.text(_neverShown[c.id]!(l)),
              ),
              findsNothing,
              reason: why,
            );
            // The dialog: the same title, tone and icon.
            expect(_texts(tester, _dialog).first, title, reason: why);
            expect(
              _categoryTone(tester, _dialog, l),
              c.tone,
              reason: '$why dialog pill',
            );
            expect(
              _leadingIcon(tester, _dialog),
              c.icon,
              reason: '$why dialog icon',
            );
            await _close(tester);
          }
          // That look is exactly the LIVE variant's of the same action (A1,
          // A6): only the change rows (a raw test_* state, or the Test mode on
          // `.started`) can tell the two apart.
          for (final c in _testTokenCases) {
            final live = _variants.firstWhere((v) => v.action == c.action);
            final why = '$code ${c.id} vs ${live.id}';
            expect(c.title(l), live.title(l), reason: why);
            expect(c.tone, live.tone, reason: why);
            expect(c.icon, live.icon, reason: why);
          }
        },
      );
    }
  });

  group('A8b classification never renders', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] the owner-read classification and recorded keys, and mode '
        'test on a result action, never render: rows, title, tone and icon '
        'equal the LIVE variant',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          // Fixture guard: `.started` and the five result actions (three
          // provider_anomaly variants), each with a ledger attempt_state. No
          // action projects the TEST keys, and only `.started` projects mode.
          expect(_classifiedVariants, hasLength(8), reason: code);
          expect(
            {for (final v in _classifiedVariants) v.action},
            {'card_attempt.started', ..._resultActions},
            reason: code,
          );
          for (final action in _resultActions) {
            expect(_projectedKeys[action], _resultKeys, reason: action);
          }
          for (final v in _classifiedVariants) {
            final keys = _projectedKeys[v.action]!;
            expect(
              v.values['attempt_state'],
              isIn(const [
                'sent',
                'approved',
                'declined',
                'unknown',
                'released',
              ]),
              reason: v.id,
            );
            expect(keys, isNot(contains('classification')), reason: v.id);
            expect(keys, isNot(contains('recorded')), reason: v.id);
            expect(
              keys.contains('mode'),
              v.action == 'card_attempt.started',
              reason: v.id,
            );
          }

          // Each LIVE variant beside its classified copy, on one page.
          await _pumpLog(tester, code, [
            for (final v in _classifiedVariants) ...[
              v.serverRow,
              _classifiedRow(v),
            ],
          ]);
          for (final v in _classifiedVariants) {
            final id = _classifiedId(v);
            final why = '$code $id';
            final title = v.title(l);
            // The row card: the LIVE title, tone and icon, and the very
            // texts of the LIVE row's card.
            expect(_texts(tester, _card(id)).first, title, reason: why);
            expect(
              _categoryTone(tester, _card(id), l),
              v.tone,
              reason: '$why card pill',
            );
            expect(
              _leadingIcon(tester, _card(id)),
              v.icon,
              reason: '$why card icon',
            );
            expect(
              _texts(tester, _card(id)),
              _texts(tester, _card(v.id)),
              reason: '$why card texts',
            );

            await _open(tester, v.id);
            final liveDialog = _texts(tester, _dialog);
            await _close(tester);

            await _open(tester, id);
            expect(_changeRows(tester), v.rows(l), reason: why);
            expect(_texts(tester, _dialog).first, title, reason: why);
            expect(
              _categoryTone(tester, _dialog, l),
              v.tone,
              reason: '$why dialog pill',
            );
            expect(
              _leadingIcon(tester, _dialog),
              v.icon,
              reason: '$why dialog icon',
            );
            // Nothing else: the dialog reads exactly as the LIVE row's.
            expect(
              _texts(tester, _dialog),
              liveDialog,
              reason: '$why dialog texts',
            );
            final text = _renderedText(tester).toLowerCase();
            for (final trace in _classificationTraces) {
              expect(text, isNot(contains(trace)), reason: '$why $trace');
            }
            await _close(tester);
          }

          // Positive control, on a fresh page: a TEST-looking token in a
          // PROJECTED key renders raw, and the same scan finds every trace.
          await tester.pumpWidget(const SizedBox.shrink());
          await _pumpLog(tester, code, [
            _serverRow(
              'ae-cls-canary',
              'card_attempt.release_requested',
              const {'attempt_state': _classificationCanary},
            ),
          ]);
          await _open(tester, 'ae-cls-canary');
          expect(_changeRows(tester), [
            (l.activityLogFieldCardState, _classificationCanary),
          ], reason: '$code canary');
          final canaryText = _renderedText(tester).toLowerCase();
          for (final trace in _classificationTraces) {
            expect(canaryText, contains(trace), reason: '$code canary $trace');
          }
          await _close(tester);
        },
      );
    }
  });

  group('A9 registry pin (locale-free)', () {
    test('the card_attempt.* registry keys are exactly the twelve LIVE '
        'actions, each payments with a title; no test., operator. or '
        'security. key', () {
      final card = kAuditActionRegistry.keys
          .where((a) => a.startsWith('card_attempt.'))
          .toSet();
      expect(card, hasLength(12));
      expect(card, _projectedKeys.keys.toSet());
      for (final action in card) {
        final spec = kAuditActionRegistry[action]!;
        expect(spec.category, 'payments', reason: action);
        expect(spec.hasTitle, isTrue, reason: action);
        expect(spec.intentionalOther, isFalse, reason: action);
      }
      for (final action in kAuditActionRegistry.keys) {
        for (final prefix in const ['test.', 'operator.', 'security.']) {
          expect(action.startsWith(prefix), isFalse, reason: action);
        }
      }
      // The widget variants above exercise every one of the twelve.
      expect({for (final v in _variants) v.action}, card);
    });
  });

  group('A10 unregistered card_attempt.mystery', () {
    for (final code in _locales) {
      testWidgets(
        '[$code] the title is the category label, no change rows, and the '
        'dialog shows the generic note',
        (tester) async {
          _tall(tester);
          final l = await _l10n(code);
          expect(
            kAuditActionRegistry.containsKey('card_attempt.mystery'),
            isFalse,
          );
          // Projected-looking keys on purpose: an unregistered action still
          // renders none of them.
          await _pumpLog(tester, code, [
            _serverRow('ae-card-mystery', 'card_attempt.mystery', const {
              'attempt_state': 'approved',
              'mode': 'live',
              'amount_minor': 4250,
              'currency_code': 'ILS',
            }),
          ]);
          expect(
            _texts(tester, _card('ae-card-mystery')).first,
            l.activityLogCategoryPayments,
            reason: code,
          );

          await _open(tester, 'ae-card-mystery');
          expect(_changeRows(tester), isEmpty, reason: code);
          expect(
            find.descendant(
              of: _dialog,
              matching: find.text(l.activityLogChangesHeading),
            ),
            findsNothing,
            reason: code,
          );
          expect(
            find.descendant(
              of: _dialog,
              matching: find.text(l.activityLogGenericNote),
            ),
            findsOneWidget,
            reason: code,
          );
          expect(
            _texts(tester, _dialog),
            _expectedDialogTexts(
              l,
              title: l.activityLogCategoryPayments,
              rows: const [],
              known: false,
            ),
            reason: code,
          );
          await _close(tester);
        },
      );
    }
  });
}
