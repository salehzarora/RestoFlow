import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/audit_action_registry.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDER-COMPLETION-001 — the ACTIVITY LOG presentation of a completion.
///
/// A successful served -> completed emits the existing canonical
/// `order.status_updated` action (no new key was minted). This pins how the
/// Dashboard RENDERS it: under Orders (never "Other"), with the safe order code,
/// the previous and new status, and the safe payment state — all with localized
/// ar/he/en labels — and with NO identifier, private field or raw payload.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

/// EXACTLY what the server's `app.audit_safe_detail` allowlist projects for a
/// completion (pgTAP pins this: status / order_code / payment_status / role are
/// kept; order_id, revision, resolved_membership_id and local_operation_id are
/// DROPPED server-side and never reach the client).
AuditEvent _completionEvent() => const AuditEvent(
  eventId: 'ae-complete',
  action: 'order.status_updated',
  category: 'orders',
  occurredAtLabel: '2026-07-13 14:05',
  actorName: 'Amira K.',
  restaurantName: 'Rest A1',
  branchName: 'Downtown',
  oldValues: {'status': 'served'},
  newValues: {
    'status': 'completed',
    'order_code': '#02A001',
    'payment_status': 'paid',
    'role': 'manager',
  },
);

void main() {
  test(
    'L1 a completion is categorized ORDERS and never falls into Other',
    () async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await _l(code);
        final view = AuditEventPresenter(
          l10n,
          'ILS',
        ).present(_completionEvent());

        expect(
          view.categoryLabel,
          l10n.activityLogCategoryOrders,
          reason: code,
        );
        expect(
          view.categoryLabel,
          isNot(l10n.activityLogCategoryOther),
          reason: '$code: a completion must NEVER render as "Other"',
        );
        // The action is a KNOWN one with a specific localized title (not a generic
        // fallback), so the event reads as a real order-status change.
        expect(view.isKnownAction, isTrue, reason: code);
        expect(
          view.title,
          l10n.activityLogTitleOrderStatusUpdated,
          reason: code,
        );
        expect(view.title.trim(), isNotEmpty, reason: code);
        expect(view.isDenied, isFalse, reason: code);
      }
    },
  );

  test(
    'L2 it communicates served -> completed, the safe code and the payment',
    () async {
      final l10n = await _l('en');
      final view = AuditEventPresenter(l10n, 'ILS').present(_completionEvent());

      // Previous status -> new status. This IS the "served -> completed" story.
      final status = view.changes.firstWhere(
        (c) => c.label == l10n.activityLogFieldStatus,
      );
      expect(status.oldValue, 'served');
      expect(status.newValue, 'completed');

      // The SAFE human reference (never the order UUID).
      final code = view.changes.firstWhere(
        (c) => c.label == l10n.activityLogFieldOrderCode,
      );
      expect(code.newValue, '#02A001');

      // The payment state at completion (a STATE, not a money figure).
      final payment = view.changes.firstWhere(
        (c) => c.label == l10n.activityLogFieldPaymentStatus,
      );
      expect(payment.newValue, 'paid');

      // The authority actually used.
      expect(
        view.changes.any((c) => c.label == l10n.activityLogFieldRole),
        isTrue,
      );
    },
  );

  test(
    'L3 every displayed field has a REAL localized label in ar/he/en',
    () async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await _l(code);
        final view = AuditEventPresenter(
          l10n,
          'ILS',
        ).present(_completionEvent());

        expect(view.changes, isNotEmpty, reason: code);
        for (final change in view.changes) {
          expect(change.label.trim(), isNotEmpty, reason: code);
          // A label that is still the raw payload key means it was never localized.
          for (final rawKey in const [
            'status',
            'order_code',
            'payment_status',
            'role',
          ]) {
            expect(
              change.label,
              isNot(rawKey),
              reason: '$code: "$rawKey" is rendering as a raw key, not a label',
            );
          }
        }
        // The three new-in-this-ticket labels really are translated per locale.
        expect(l10n.activityLogFieldOrderCode.trim(), isNotEmpty, reason: code);
        expect(
          l10n.activityLogFieldPaymentStatus.trim(),
          isNotEmpty,
          reason: code,
        );
      }
    },
  );

  test(
    'L4 NO identifier, private field, raw payload or secret is ever rendered',
    () async {
      final l10n = await _l('en');
      // Even if a payload somehow carried them, the CLIENT allowlist drops them too
      // (the server already strips them — this is the second, independent layer).
      final hostile = AuditEvent(
        eventId: 'ae-x',
        action: 'order.status_updated',
        category: 'orders',
        occurredAtLabel: '2026-07-13 14:05',
        oldValues: const {'status': 'served'},
        newValues: const {
          'status': 'completed',
          'order_code': '#02A001',
          'payment_status': 'paid',
          'order_id': '00000000-0000-0000-0000-00000002a001',
          'revision': 2,
          'resolved_membership_id': '00000000-0000-0000-0000-0000000a0002',
          'employee_profile_id': '00000000-0000-0000-0000-0000000e0f01',
          'local_operation_id': 'op-123',
          'device_id': '00000000-0000-0000-0000-00000000d001',
          'customer_name': 'Layla',
          'phone': '+972500000000',
          'email': 'guest@example.test',
          'address': '1 King St',
          'notes': 'PRIVATE-NOTE',
          'token': 'sekrit',
          'api_key': 'leak',
        },
      );

      final view = AuditEventPresenter(l10n, 'ILS').present(hostile);
      final rendered = view.changes
          .map((c) => '${c.label}|${c.oldValue}|${c.newValue}')
          .join('~');

      for (final forbidden in const [
        '00000000-0000-0000-0000-00000002a001', // order UUID
        '00000000-0000-0000-0000-0000000a0002', // membership id
        '00000000-0000-0000-0000-0000000e0f01', // employee profile id
        '00000000-0000-0000-0000-00000000d001', // device id
        'op-123', // operation id
        'Layla', // customer name
        '+972500000000', // phone
        'guest@example.test', // email
        '1 King St', // address
        'PRIVATE-NOTE', // notes
        'sekrit', // token
        'leak', // secret
      ]) {
        expect(
          rendered.contains(forbidden),
          isFalse,
          reason: '"$forbidden" must never reach the Activity Log',
        );
      }

      // The safe fields ARE still shown.
      expect(rendered.contains('completed'), isTrue);
      expect(rendered.contains('#02A001'), isTrue);
      expect(rendered.contains('paid'), isTrue);
    },
  );

  test('L5 the denial action is also Orders (never Other)', () async {
    final l10n = await _l('en');
    final view = AuditEventPresenter(l10n, 'ILS').present(
      const AuditEvent(
        eventId: 'ae-denied',
        action: 'order.status_update_denied',
        category: 'orders',
        occurredAtLabel: '2026-07-13 14:04',
        newValues: {
          'attempted_action': 'owner_complete_order',
          'order_code': '#02A001',
          'role': 'kitchen_staff',
        },
      ),
    );
    expect(view.categoryLabel, l10n.activityLogCategoryOrders);
    expect(view.categoryLabel, isNot(l10n.activityLogCategoryOther));
    expect(view.isDenied, isTrue);
  });

  test(
    'L6 the audit-coverage registry guard stays clean (no new action key)',
    () async {
      final en = await _l('en');
      final ar = await _l('ar');
      final he = await _l('he');

      // No `order.completed` key was minted — the canonical transition action is
      // reused, so it inherits the whole existing coverage contract.
      expect(kAuditActionRegistry.containsKey('order.completed'), isFalse);
      expect(kAuditActionRegistry['order.status_updated']?.category, 'orders');
      expect(kAuditActionRegistry['order.status_updated']?.hasTitle, isTrue);
      expect(
        kAuditActionRegistry['order.status_update_denied']?.category,
        'orders',
      );

      final violations = auditRegistryViolations(en, ar, he);
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
}
