import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/audit_action_registry.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_dashboard/src/format/money_format.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D — the ACTIVITY LOG presentation of the
/// twelve LIVE card-present attempt actions (API_CONTRACT §4.33; the 001D
/// execution packet §15.5–§15.6). Every action has a specific ar/he/en title
/// that describes the PROVIDER's result, renders only the keys the server
/// projects for it, and never reads as success unless the provider approved.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

const List<String> _locales = ['en', 'ar', 'he'];

const List<String> _cardActions = [
  'card_attempt.started',
  'card_attempt.approved',
  'card_attempt.declined',
  'card_attempt.unknown',
  'card_attempt.released',
  'card_attempt.provider_anomaly',
  'card_attempt.release_requested',
  'card_attempt.release_failed',
  'card_attempt.recording_refused',
  'card_attempt.order_freed',
  'card_attempt.recording_resume_requested',
  'card_attempt.denied',
];

/// A representative server-projected payload per action (the exact keys of
/// `app.audit_safe_detail`; short synthetic values only).
const Map<String, Map<String, Object?>> _projected = {
  'card_attempt.started': {
    'attempt_state': 'sent',
    'mode': 'live',
    'amount_minor': 4250,
    'currency_code': 'ILS',
  },
  'card_attempt.approved': {
    'attempt_state': 'approved',
    'release_requested': false,
  },
  'card_attempt.declined': {
    'attempt_state': 'declined',
    'refusal_code': 'release_failed',
    'release_requested': true,
  },
  'card_attempt.unknown': {
    'attempt_state': 'unknown',
    'release_requested': true,
  },
  'card_attempt.released': {
    'attempt_state': 'released',
    'release_requested': true,
  },
  'card_attempt.provider_anomaly': {
    'attempt_state': 'unknown',
    'anomaly_code': 'out_of_contract',
    'release_requested': false,
  },
  'card_attempt.release_requested': {'attempt_state': 'sent'},
  'card_attempt.release_failed': {'attempt_state': 'unknown'},
  'card_attempt.recording_refused': {
    'refusal_code': 'provider_recording_refused',
  },
  'card_attempt.order_freed': {
    'attempt_state': 'released',
    'confirmation_source': 'provider_report',
  },
  'card_attempt.recording_resume_requested': {
    'attempt_state': 'approved',
    'prior_refusal_code': 'permission_denied',
    'resume_count': 1,
    'outcome': 'dispatched',
  },
  'card_attempt.denied': {'denied_reason': 'no_open_shift'},
};

AuditEvent _event(
  String action,
  Map<String, Object?> values, {
  String? reason,
  Map<String, Object?> oldValues = const {},
}) => AuditEvent(
  eventId: 'ae-$action',
  action: action,
  category: 'payments',
  occurredAtLabel: '2026-10-25 12:00',
  actorName: 'Cashier A',
  restaurantName: 'Rest A',
  branchName: 'Main',
  deviceLabel: 'POS 1',
  reason: reason,
  oldValues: oldValues,
  newValues: values,
);

AuditEventView _present(
  AppLocalizations l10n,
  String action,
  Map<String, Object?> values, {
  String currency = 'ILS',
  String? reason,
  Map<String, Object?> oldValues = const {},
}) => AuditEventPresenter(
  l10n,
  currency,
).present(_event(action, values, reason: reason, oldValues: oldValues));

String _rendered(AuditEventView v) => [
  v.title,
  v.reason ?? '',
  for (final c in v.changes) '${c.label}=${c.oldValue}>${c.newValue}',
].join('|');

/// The closed vocabularies the presenter localizes, and one action that
/// projects each key.
const Map<String, (String, List<String>)> _vocabularies = {
  'attempt_state': (
    'card_attempt.release_requested',
    ['sent', 'approved', 'declined', 'unknown', 'released'],
  ),
  'mode': ('card_attempt.started', ['live', 'test']),
  'refusal_code': (
    'card_attempt.recording_refused',
    [
      'release_failed',
      'order_not_chargeable',
      'conflict',
      'precondition_failed',
      'revoked_employee',
      'permission_denied',
      'revoked_device',
      'amount_mismatch',
      'payment_in_progress',
      'card_context_lost',
      'provider_recording_refused',
      'nonrecoverable_refusal',
    ],
  ),
  'anomaly_code': (
    'card_attempt.provider_anomaly',
    [
      'amount_mismatch',
      'currency_mismatch',
      'preauthorization',
      'partial_refund',
      'refunded',
      'voided',
      'out_of_contract',
    ],
  ),
  'confirmation_source': (
    'card_attempt.order_freed',
    ['provider_report', 'provider_back_office'],
  ),
  'outcome': (
    'card_attempt.recording_resume_requested',
    ['dispatched', 'refused'],
  ),
  'denied_reason': (
    'card_attempt.denied',
    [
      'permission_denied',
      'ineligible_order_state',
      'max_live_amount_exceeded',
      'no_open_shift',
      'no_active_drawer',
      'no_recording_attempt',
      'attempt_not_freeable',
      'charge_may_exist',
      'confirmation_required',
      'device_not_active',
      'operation_mismatch',
      'resume_limit',
      'resume_stale',
      'not_recoverable',
      'payment_exists',
      'claim_inactive',
      'order_not_chargeable',
      'context_lost',
      'amount_mismatch',
      'refusal_not_recorded',
    ],
  ),
};

/// Each action's exact title. The representative provider_anomaly payload
/// projects `unknown`, so its title is the RAISED one (the other states are
/// pinned by the provider_anomaly test).
final Map<String, String Function(AppLocalizations)> _titleOf = {
  'card_attempt.started': (l) => l.activityLogTitleCardAttemptStarted,
  'card_attempt.approved': (l) => l.activityLogTitleCardAttemptApproved,
  'card_attempt.declined': (l) => l.activityLogTitleCardAttemptDeclined,
  'card_attempt.unknown': (l) => l.activityLogTitleCardAttemptUnknown,
  'card_attempt.released': (l) => l.activityLogTitleCardAttemptReleased,
  'card_attempt.provider_anomaly': (l) =>
      l.activityLogTitleCardAttemptAnomalyRaised,
  'card_attempt.release_requested': (l) =>
      l.activityLogTitleCardAttemptReleaseRequested,
  'card_attempt.release_failed': (l) =>
      l.activityLogTitleCardAttemptReleaseFailed,
  'card_attempt.recording_refused': (l) =>
      l.activityLogTitleCardAttemptRecordingRefused,
  'card_attempt.order_freed': (l) => l.activityLogTitleCardAttemptOrderFreed,
  'card_attempt.recording_resume_requested': (l) =>
      l.activityLogTitleCardAttemptResumeRequested,
  'card_attempt.denied': (l) => l.activityLogTitleCardAttemptDenied,
};

/// Each closed-vocabulary token's exact label. A denied_reason
/// `permission_denied` uses the card family's own label (the card proof
/// refuses a non-POS device and a role not allowed to take card payments with
/// the same token); a refusal `permission_denied` is the recording's role
/// refusal and keeps the shared label.
final Map<String, Map<String, String Function(AppLocalizations)>> _labelOf = {
  'attempt_state': {
    'sent': (l) => l.activityLogCardStateSent,
    'approved': (l) => l.activityLogCardStateApproved,
    'declined': (l) => l.activityLogCardStateDeclined,
    'unknown': (l) => l.activityLogCardStateUnknown,
    'released': (l) => l.activityLogCardStateReleased,
  },
  'mode': {
    'live': (l) => l.activityLogCardModeLive,
    'test': (l) => l.activityLogCardModeTest,
  },
  'refusal_code': {
    'release_failed': (l) => l.activityLogCardRefusalReleaseFailed,
    'order_not_chargeable': (l) => l.activityLogDeniedOrderNotChargeable,
    'conflict': (l) => l.activityLogCardRefusalConflict,
    'precondition_failed': (l) => l.activityLogCardRefusalPreconditionFailed,
    'revoked_employee': (l) => l.activityLogCardRefusalRevokedEmployee,
    'permission_denied': (l) => l.activityLogDeniedPermission,
    'revoked_device': (l) => l.activityLogCardRefusalRevokedDevice,
    'amount_mismatch': (l) => l.activityLogDeniedAmountMismatch,
    'payment_in_progress': (l) => l.activityLogCardRefusalPaymentInProgress,
    'card_context_lost': (l) => l.activityLogDeniedContextLost,
    'provider_recording_refused': (l) =>
        l.activityLogCardRefusalProviderRecordingRefused,
    'nonrecoverable_refusal': (l) => l.activityLogCardRefusalNonrecoverable,
  },
  'anomaly_code': {
    'amount_mismatch': (l) => l.activityLogCardAnomalyAmountMismatch,
    'currency_mismatch': (l) => l.activityLogCardAnomalyCurrencyMismatch,
    'preauthorization': (l) => l.activityLogCardAnomalyPreauthorization,
    'partial_refund': (l) => l.activityLogCardAnomalyPartialRefund,
    'refunded': (l) => l.activityLogCardAnomalyRefunded,
    'voided': (l) => l.activityLogCardAnomalyVoided,
    'out_of_contract': (l) => l.activityLogCardAnomalyOutOfContract,
  },
  'confirmation_source': {
    'provider_report': (l) => l.activityLogCardConfirmationProviderReport,
    'provider_back_office': (l) => l.activityLogCardConfirmationBackOffice,
  },
  'outcome': {
    'dispatched': (l) => l.activityLogCardResumeDispatched,
    'refused': (l) => l.activityLogCardResumeRefused,
  },
  'denied_reason': {
    'permission_denied': (l) => l.activityLogDeniedCardPermission,
    'ineligible_order_state': (l) => l.activityLogDeniedIneligibleOrderState,
    'max_live_amount_exceeded': (l) => l.activityLogDeniedMaxLiveAmountExceeded,
    'no_open_shift': (l) => l.activityLogDeniedNoOpenShift,
    'no_active_drawer': (l) => l.activityLogDeniedNoActiveDrawer,
    'no_recording_attempt': (l) => l.activityLogDeniedNoRecordingAttempt,
    'attempt_not_freeable': (l) => l.activityLogDeniedAttemptNotFreeable,
    'charge_may_exist': (l) => l.activityLogDeniedChargeMayExist,
    'confirmation_required': (l) => l.activityLogDeniedConfirmationRequired,
    'device_not_active': (l) => l.activityLogDeniedDeviceNotActive,
    'operation_mismatch': (l) => l.activityLogDeniedOperationMismatch,
    'resume_limit': (l) => l.activityLogDeniedResumeLimit,
    'resume_stale': (l) => l.activityLogDeniedResumeStale,
    'not_recoverable': (l) => l.activityLogDeniedNotRecoverable,
    'payment_exists': (l) => l.activityLogDeniedPaymentExists,
    'claim_inactive': (l) => l.activityLogDeniedClaimInactive,
    'order_not_chargeable': (l) => l.activityLogDeniedOrderNotChargeable,
    'context_lost': (l) => l.activityLogDeniedContextLost,
    'amount_mismatch': (l) => l.activityLogDeniedAmountMismatch,
    'refusal_not_recorded': (l) => l.activityLogDeniedRefusalNotRecorded,
  },
};

/// Every card key with a valid value: each action must render exactly the
/// keys `app.audit_safe_detail` projects for it, in that order.
const Map<String, Object?> _allCardKeys = {
  'attempt_state': 'approved',
  'mode': 'live',
  'amount_minor': 4250,
  'currency_code': 'ILS',
  'refusal_code': 'release_failed',
  'prior_refusal_code': 'conflict',
  'anomaly_code': 'voided',
  'release_requested': true,
  'confirmation_source': 'provider_report',
  'resume_count': 2,
  'outcome': 'refused',
  'denied_reason': 'resume_limit',
};

/// The exact ordered field labels of each action (the server's projection).
List<String> _expectedLabels(AppLocalizations l, String action) =>
    switch (action) {
      'card_attempt.started' => [
        l.activityLogFieldCardState,
        l.activityLogFieldCardMode,
        l.activityLogFieldAmount,
        l.activityLogFieldCurrency,
      ],
      'card_attempt.approved' ||
      'card_attempt.declined' ||
      'card_attempt.unknown' ||
      'card_attempt.released' ||
      'card_attempt.provider_anomaly' => [
        l.activityLogFieldCardState,
        l.activityLogFieldCardReleaseStatus,
        l.activityLogFieldCardAnomaly,
        l.activityLogFieldCardReleaseRequested,
      ],
      'card_attempt.release_requested' ||
      'card_attempt.release_failed' => [l.activityLogFieldCardState],
      'card_attempt.recording_refused' => [l.activityLogFieldCardRefusal],
      'card_attempt.order_freed' => [
        l.activityLogFieldCardState,
        l.activityLogFieldCardConfirmationSource,
      ],
      'card_attempt.recording_resume_requested' => [
        l.activityLogFieldCardState,
        l.activityLogFieldCardPriorRefusal,
        l.activityLogFieldCardResumeCount,
        l.activityLogFieldCardResumeOutcome,
        l.activityLogFieldDeniedReason,
      ],
      'card_attempt.denied' => [l.activityLogFieldDeniedReason],
      _ => const <String>[],
    };

void main() {
  test('the registry contracts exactly the twelve LIVE card actions', () {
    final card = kAuditActionRegistry.keys
        .where((a) => a.startsWith('card_attempt.'))
        .toSet();
    expect(card, _cardActions.toSet());
    for (final action in _cardActions) {
      expect(
        kAuditActionRegistry[action]!.category,
        'payments',
        reason: action,
      );
      expect(kAuditActionRegistry[action]!.hasTitle, isTrue, reason: action);
      expect(
        kAuditActionRegistry[action]!.intentionalOther,
        isFalse,
        reason: action,
      );
    }
    // The private operator.* / test.* / security.* events never reach the
    // Activity log and must not be registered.
    for (final action in kAuditActionRegistry.keys) {
      expect(
        action.startsWith('operator.') ||
            action.startsWith('test.') ||
            action.startsWith('security.'),
        isFalse,
        reason: action,
      );
    }
  });

  test('every action has a specific, distinct title in ar/he/en', () async {
    for (final code in _locales) {
      final l10n = await _l(code);
      final titles = <String>{};
      for (final action in _cardActions) {
        final view = _present(l10n, action, _projected[action]!);
        expect(view.isKnownAction, isTrue, reason: '$code $action');
        expect(view.title.trim(), isNotEmpty, reason: '$code $action');
        expect(
          view.title,
          isNot(l10n.activityLogCategoryPayments),
          reason: '$code $action: a title, not the category fallback',
        );
        expect(
          view.categoryLabel,
          l10n.activityLogCategoryPayments,
          reason: '$code $action',
        );
        titles.add(view.title);
      }
      expect(titles, hasLength(_cardActions.length), reason: code);
      // The three provider_anomaly variants are distinct from each other and
      // from every other card title.
      final anomaly = {
        l10n.activityLogTitleCardAttemptAnomalyRaised,
        l10n.activityLogTitleCardAttemptAnomalyCleared,
        l10n.activityLogTitleCardAttemptAnomaly,
      };
      expect(anomaly, hasLength(3), reason: code);
      expect(
        titles.where((t) => anomaly.contains(t)),
        hasLength(1),
        reason: code,
      );
    }
  });

  test('each action shows its exact title in ar/he/en', () async {
    for (final code in _locales) {
      final l10n = await _l(code);
      for (final action in _cardActions) {
        expect(
          _present(l10n, action, _projected[action]!).title,
          _titleOf[action]!(l10n),
          reason: '$code $action',
        );
      }
    }
  });

  test(
    'each action renders exactly its projected keys, in the server order',
    () async {
      for (final code in _locales) {
        final l10n = await _l(code);
        for (final action in _cardActions) {
          final view = _present(l10n, action, _allCardKeys);
          expect(
            view.changes.map((c) => c.label).toList(),
            _expectedLabels(l10n, action),
            reason: '$code $action',
          );
        }
        // On a provider-result row refusal_code is the release status, never a
        // recording refusal; card_attempt.recording_refused keeps that label.
        final unknown = _present(l10n, 'card_attempt.unknown', {
          'refusal_code': 'release_failed',
        });
        expect(
          unknown.changes.single.label,
          l10n.activityLogFieldCardReleaseStatus,
        );
        expect(
          unknown.changes.single.label,
          isNot(l10n.activityLogFieldCardRefusal),
        );
        // resume_count is the raw server count of EARLIER retries (0 on the
        // first retry), never shifted into an ordinal.
        final first = _present(
          l10n,
          'card_attempt.recording_resume_requested',
          {'resume_count': 0},
        );
        expect(
          first.changes.single.label,
          l10n.activityLogFieldCardResumeCount,
        );
        expect(first.changes.single.newValue, '0');
        // A prior refusal of release_failed is the stored release fact, so it
        // reads as the release status; a recording refusal keeps its label.
        final priorRelease = _present(
          l10n,
          'card_attempt.recording_resume_requested',
          {'prior_refusal_code': 'release_failed'},
        );
        expect(
          priorRelease.changes.single.label,
          l10n.activityLogFieldCardReleaseStatus,
        );
        final priorRecording = _present(
          l10n,
          'card_attempt.recording_resume_requested',
          {'prior_refusal_code': 'conflict'},
        );
        expect(
          priorRecording.changes.single.label,
          l10n.activityLogFieldCardPriorRefusal,
        );
      }
    },
  );

  test(
    'provider_anomaly titles and tones follow the projected state',
    () async {
      for (final code in _locales) {
        final l10n = await _l(code);
        AuditEventView anomaly(Object? state) =>
            _present(l10n, 'card_attempt.provider_anomaly', {
              if (state != null) 'attempt_state': state,
              'anomaly_code': 'amount_mismatch',
            });
        for (final raised in ['unknown', 'released']) {
          final v = anomaly(raised);
          expect(v.title, l10n.activityLogTitleCardAttemptAnomalyRaised);
          expect(v.tone, RestoflowTone.danger, reason: '$code $raised');
        }
        for (final cleared in ['approved', 'declined']) {
          final v = anomaly(cleared);
          expect(v.title, l10n.activityLogTitleCardAttemptAnomalyCleared);
          expect(v.tone, RestoflowTone.info, reason: '$code $cleared');
        }
        for (final other in [null, 'sent', 'mystery']) {
          final v = anomaly(other);
          expect(v.title, l10n.activityLogTitleCardAttemptAnomaly);
          expect(v.tone, RestoflowTone.warning, reason: '$code $other');
        }
      }
    },
  );

  test('only a provider approval reads as success', () async {
    final l10n = await _l('en');
    RestoflowTone tone(String action, [Map<String, Object?>? values]) =>
        _present(l10n, action, values ?? _projected[action]!).tone;
    expect(tone('card_attempt.approved'), RestoflowTone.success);
    expect(tone('card_attempt.declined'), RestoflowTone.neutral);
    expect(tone('card_attempt.unknown'), RestoflowTone.warning);
    expect(tone('card_attempt.release_failed'), RestoflowTone.warning);
    expect(tone('card_attempt.recording_refused'), RestoflowTone.warning);
    expect(tone('card_attempt.order_freed'), RestoflowTone.warning);
    expect(tone('card_attempt.denied'), RestoflowTone.warning);
    expect(tone('card_attempt.started'), RestoflowTone.info);
    expect(tone('card_attempt.released'), RestoflowTone.info);
    expect(tone('card_attempt.release_requested'), RestoflowTone.info);
    expect(
      tone('card_attempt.recording_resume_requested', {
        'outcome': 'dispatched',
      }),
      RestoflowTone.info,
    );
    expect(
      tone('card_attempt.recording_resume_requested', {
        'outcome': 'refused',
        'denied_reason': 'resume_limit',
      }),
      RestoflowTone.warning,
    );
    for (final action in _cardActions) {
      if (action == 'card_attempt.approved') continue;
      expect(tone(action), isNot(RestoflowTone.success), reason: action);
    }
  });

  test('the Denied pill is set for card_attempt.denied only', () async {
    final l10n = await _l('en');
    for (final action in _cardActions) {
      final view = _present(l10n, action, _projected[action]!);
      expect(view.isDenied, action == 'card_attempt.denied', reason: action);
    }
  });

  test(
    'projected fields render with real localized labels and values',
    () async {
      for (final code in _locales) {
        final l10n = await _l(code);
        for (final action in _cardActions) {
          final payload = _projected[action]!;
          final view = _present(l10n, action, payload);
          expect(
            view.changes,
            hasLength(payload.length),
            reason: '$code $action',
          );
          for (final change in view.changes) {
            expect(
              payload.keys,
              isNot(contains(change.label)),
              reason: '$code $action: ${change.label} is a raw key',
            );
            expect(change.label.trim(), isNotEmpty, reason: '$code $action');
            expect(change.oldValue, isNull, reason: '$code $action');
          }
        }
      }
    },
  );

  test(
    'every closed-vocabulary token is localized in ar/he/en (never raw)',
    () async {
      for (final code in _locales) {
        final l10n = await _l(code);
        final label = <String, String>{
          'attempt_state': l10n.activityLogFieldCardState,
          'mode': l10n.activityLogFieldCardMode,
          'refusal_code': l10n.activityLogFieldCardRefusal,
          'anomaly_code': l10n.activityLogFieldCardAnomaly,
          'confirmation_source': l10n.activityLogFieldCardConfirmationSource,
          'outcome': l10n.activityLogFieldCardResumeOutcome,
          'denied_reason': l10n.activityLogFieldDeniedReason,
        };
        _vocabularies.forEach((key, entry) {
          final (action, tokens) = entry;
          expect(_labelOf[key]!.keys.toSet(), tokens.toSet(), reason: key);
          final shown = <String>[];
          for (final token in tokens) {
            final view = _present(l10n, action, {key: token});
            final row = view.changes.singleWhere(
              (c) => c.label == label[key],
              orElse: () => throw StateError('$code $action: no $key row'),
            );
            expect(row.newValue, isNot(token), reason: '$code $key=$token');
            expect(
              row.newValue,
              _labelOf[key]![token]!(l10n),
              reason: '$code $key=$token',
            );
            expect(
              row.newValue.trim(),
              isNotEmpty,
              reason: '$code $key=$token',
            );
            shown.add(row.newValue);
          }
          // Distinct tokens never share one label within a vocabulary.
          expect(shown.toSet(), hasLength(shown.length), reason: '$code $key');
        });
        // prior_refusal_code shares the refusal vocabulary and its labels.
        _labelOf['refusal_code']!.forEach((token, labelOf) {
          final prior = _present(
            l10n,
            'card_attempt.recording_resume_requested',
            {'prior_refusal_code': token},
          );
          expect(
            prior.changes.single.newValue,
            labelOf(l10n),
            reason: '$code prior $token',
          );
          expect(
            prior.changes.single.newValue.trim(),
            isNotEmpty,
            reason: '$code prior $token',
          );
        });
      }
    },
  );

  test(
    'money renders only on .started, in the row currency, as integer minor units',
    () async {
      final l10n = await _l('en');
      String? amount(AuditEventView v) => v.changes
          .where((c) => c.label == l10n.activityLogFieldAmount)
          .map((c) => c.newValue)
          .firstOrNull;
      // The row's own ISO currency wins over the page currency.
      final usd = _present(l10n, 'card_attempt.started', {
        'attempt_state': 'sent',
        'amount_minor': 4250,
        'currency_code': 'USD',
      }, currency: 'ILS');
      expect(amount(usd), MoneyFormatter.formatMinor(4250, 'USD'));
      expect(amount(usd), isNot(MoneyFormatter.formatMinor(4250, 'ILS')));
      // A malformed row currency falls back to the page currency.
      final page = _present(l10n, 'card_attempt.started', {
        'amount_minor': 4250,
        'currency_code': 'usd',
      }, currency: 'ILS');
      expect(amount(page), MoneyFormatter.formatMinor(4250, 'ILS'));
      // A non-integer amount never renders (D-007: integer minor units only).
      for (final bad in <Object>['4250', 42.5]) {
        final v = _present(l10n, 'card_attempt.started', {
          'amount_minor': bad,
          'currency_code': 'ILS',
        });
        expect(amount(v), isNull, reason: '$bad');
      }
      // Money is projected on .started only: any other card action drops it.
      for (final action in _cardActions) {
        if (action == 'card_attempt.started') continue;
        final v = _present(l10n, action, {
          ..._projected[action]!,
          'amount_minor': 9999,
          'currency_code': 'ILS',
        });
        expect(amount(v), isNull, reason: action);
        expect(_rendered(v), isNot(contains('99.99')), reason: action);
      }
    },
  );

  test(
    'a hostile payload never surfaces unprojected keys, old values or the reason',
    () async {
      final l10n = await _l('en');
      const hostile = <String, Object?>{
        'attempt_state': 'approved',
        'provider_reference': 'PREF-HOSTILE',
        'approval_number': 'APPROVAL-HOSTILE',
        'voucher_number': 'VOUCHER-HOSTILE',
        'terminal_ref': 'term-hostile',
        'credential_ref': 'cred-hostile',
        'local_operation_id': 'op-hostile',
        'order_id': 'order-hostile',
        'confirmation_reference': 'CONF-HOSTILE',
        'order_freed_note': 'note-hostile',
        'resolution_reference': 'RES-HOSTILE',
        'card_last4': '4321',
        'card_brand_code': 'BRAND-HOSTILE',
        // Keys other families render must not render for a card action.
        'status': 'status-hostile',
        'name': 'name-hostile',
        'value': 'value-hostile',
        'reason': 'reason-hostile',
      };
      for (final action in _cardActions) {
        final view = _present(
          l10n,
          action,
          hostile,
          reason: 'free text reason-hostile',
          oldValues: const {'attempt_state': 'sent', 'mode': 'old-hostile'},
        );
        final text = _rendered(view);
        for (final needle in [
          'HOSTILE',
          'hostile',
          '4321',
          'free text',
          'op-',
          'cred-',
          'term-',
        ]) {
          expect(text, isNot(contains(needle)), reason: '$action: $needle');
        }
        expect(view.reason, isNull, reason: action);
        for (final change in view.changes) {
          expect(change.oldValue, isNull, reason: action);
        }
      }
    },
  );

  test(
    'an unknown projected token shows raw; an unregistered card action renders no rows',
    () async {
      final l10n = await _l('en');
      final unknown = _present(l10n, 'card_attempt.release_requested', {
        'attempt_state': 'mystery_state',
      });
      expect(unknown.changes.single.newValue, 'mystery_state');
      final unregistered = _present(l10n, 'card_attempt.mystery', {
        'attempt_state': 'approved',
        'mode': 'live',
      });
      expect(unregistered.changes, isEmpty);
      expect(unregistered.isKnownAction, isFalse);
      expect(unregistered.title, l10n.activityLogCategoryPayments);
    },
  );

  test(
    'release_requested is a yes / no value; anything else shows raw',
    () async {
      final l10n = await _l('en');
      String flag(Object value) => _present(l10n, 'card_attempt.approved', {
        'release_requested': value,
      }).changes.single.newValue;
      expect(flag(true), l10n.activityLogYes);
      expect(flag(false), l10n.activityLogNo);
      expect(flag('true'), l10n.activityLogYes);
      expect(flag('maybe'), 'maybe');
      expect(flag(true), isNot(l10n.activityLogEnabled));
    },
  );

  test('other actions keep their existing presentation', () async {
    final l10n = await _l('en');
    // The card keys are scoped to the card family: another action carrying
    // them renders none of them, and its money keeps the page currency.
    final recorded = _present(l10n, 'payment.recorded', {
      'amount_minor': 1500,
      'mode': 'live',
      'attempt_state': 'approved',
      'outcome': 'dispatched',
      'currency_code': 'USD',
    }, currency: 'ILS');
    expect(recorded.title, l10n.activityLogTitlePaymentRecorded);
    expect(recorded.tone, RestoflowTone.success);
    expect(recorded.changes, hasLength(1));
    expect(
      recorded.changes.single.newValue,
      MoneyFormatter.formatMinor(1500, 'ILS'),
    );
    // The card family's Denied pill is presenter-scoped: the existing
    // `payment.denied` keeps its pre-existing presentation (no pill, payments
    // tone — a known gap owned outside 001D), unchanged by this ticket.
    final denied = _present(l10n, 'payment.denied', {
      'denied_reason': 'permission_denied',
    });
    expect(denied.isDenied, isFalse);
    expect(denied.tone, RestoflowTone.success);
    expect(denied.title, l10n.activityLogCategoryPayments);
    // ... and its permission_denied keeps the shared role label; only the
    // card family uses its own device-or-role label.
    expect(denied.changes.single.newValue, l10n.activityLogDeniedPermission);
    expect(
      _present(l10n, 'card_attempt.denied', {
        'denied_reason': 'permission_denied',
      }).changes.single.newValue,
      l10n.activityLogDeniedCardPermission,
    );
    // A non-card action still shows its operational reason.
    final voided = _present(
      l10n,
      'order.voided',
      const {},
      reason: 'Customer left',
    );
    expect(voided.reason, 'Customer left');
  });

  test('the audit-coverage guard stays green with the card family', () async {
    final en = await _l('en');
    final ar = await _l('ar');
    final he = await _l('he');
    expect(auditRegistryViolations(en, ar, he), isEmpty);
    for (final key in [
      'attempt_state',
      'mode',
      'currency_code',
      'refusal_code',
      'prior_refusal_code',
      'anomaly_code',
      'release_requested',
      'confirmation_source',
      'resume_count',
      'outcome',
    ]) {
      expect(auditDisplayableFieldKeys(), contains(key));
      for (final l10n in [en, ar, he]) {
        expect(auditFieldLabel(l10n, key), isNot(key), reason: key);
      }
    }
  });
}
