import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/audit_action_registry.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// PSC-001D — the ACTIVITY LOG presentation of the kitchen cancellation
/// acknowledgement. Both the success and the denial carry a SPECIFIC localized
/// title (never a bare category, never "Other"), classify under Voids, and
/// render only the safe server-projected scalars.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

AuditEvent _ackEvent() => const AuditEvent(
  eventId: 'ae-void-ack',
  action: 'order.void_acknowledged',
  category: 'voids',
  occurredAtLabel: '2026-07-21 12:10',
  actorName: 'Sami K.',
  restaurantName: 'Rest A1',
  branchName: 'Downtown',
  oldValues: {},
  newValues: {
    'order_code': '#02A001',
    'voided_from_status': 'preparing',
    'device_type': 'kds',
    'kitchen_ack_required': true,
    'role': 'kitchen_staff',
  },
);

AuditEvent _deniedEvent() => const AuditEvent(
  eventId: 'ae-void-ack-denied',
  action: 'order.void_ack_denied',
  category: 'voids',
  occurredAtLabel: '2026-07-21 12:11',
  actorName: 'Amira K.',
  restaurantName: 'Rest A1',
  branchName: 'Downtown',
  oldValues: {},
  newValues: {
    'order_code': '#02A001',
    'denied_reason': 'invalid_device_type',
    'device_type': 'pos',
    'role': 'manager',
  },
);

void main() {
  test('the registry contracts both actions to Voids with specific titles', () {
    expect(kAuditActionRegistry['order.void_acknowledged']?.category, 'voids');
    expect(kAuditActionRegistry['order.void_acknowledged']?.hasTitle, isTrue);
    expect(kAuditActionRegistry['order.void_ack_denied']?.category, 'voids');
    expect(kAuditActionRegistry['order.void_ack_denied']?.hasTitle, isTrue);
  });

  test(
    'success + denial render titled under Voids in ar/he/en — never Other',
    () async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await _l(code);
        final presenter = AuditEventPresenter(l10n, 'ILS');

        final ack = presenter.present(_ackEvent());
        expect(ack.categoryLabel, l10n.activityLogCategoryVoids, reason: code);
        expect(
          ack.categoryLabel,
          isNot(l10n.activityLogCategoryOther),
          reason: code,
        );
        expect(ack.title, l10n.activityLogTitleVoidAcknowledged, reason: code);
        expect(ack.title.trim(), isNotEmpty, reason: code);

        final denied = presenter.present(_deniedEvent());
        expect(
          denied.categoryLabel,
          l10n.activityLogCategoryVoids,
          reason: code,
        );
        expect(denied.title, l10n.activityLogTitleVoidAckDenied, reason: code);
      }
    },
  );

  test('the safe scalars render with REAL localized labels', () async {
    for (final code in ['en', 'ar', 'he']) {
      final l10n = await _l(code);
      final view = AuditEventPresenter(l10n, 'ILS').present(_ackEvent());
      expect(view.changes, isNotEmpty, reason: code);
      for (final change in view.changes) {
        // A label equal to its raw payload key means an unmapped field.
        expect(change.label.trim(), isNotEmpty, reason: code);
        expect(
          change.label,
          isNot(
            anyOf('voided_from_status', 'device_type', 'kitchen_ack_required'),
          ),
          reason: '$code: every new field needs a real localized label',
        );
      }
      expect(
        view.changes.any(
          (c) => c.label == l10n.activityLogFieldVoidedFromStatus,
        ),
        isTrue,
        reason: code,
      );
      expect(
        view.changes.any((c) => c.label == l10n.activityLogFieldDeviceType),
        isTrue,
        reason: code,
      );
    }
  });

  test(
    'a HOSTILE payload stays safely projected (no ids, no unknown keys)',
    () async {
      final l10n = await _l('en');
      const hostile = AuditEvent(
        eventId: 'ae-hostile',
        action: 'order.void_acknowledged',
        category: 'voids',
        occurredAtLabel: '2026-07-21 12:12',
        actorName: 'X',
        restaurantName: 'R',
        branchName: 'B',
        oldValues: {},
        newValues: {
          'order_code': '#02A001',
          'order_id': '11111111-2222-3333-4444-555555555555',
          'resolved_membership_id': '66666666-7777-8888-9999-aaaaaaaaaaaa',
          'local_operation_id': 'op-secret',
          'pin': '1234',
          'grand_total_minor': 9999,
        },
      );
      final view = AuditEventPresenter(l10n, 'ILS').present(hostile);
      final rendered = [
        for (final c in view.changes) '${c.label}:${c.oldValue}>${c.newValue}',
      ].join('|');
      expect(rendered, isNot(contains('11111111')));
      expect(rendered, isNot(contains('66666666')));
      expect(rendered, isNot(contains('op-secret')));
      expect(rendered, isNot(contains('1234')));
    },
  );
}
