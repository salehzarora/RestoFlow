import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// AUDIT-LOG-DASHBOARD-001 — the centralized presentation mapper is the privacy
/// boundary. These tests assert it (1) allowlists which payload fields render,
/// (2) NEVER emits a secret-looking key even if the payload contains one,
/// (3) localizes category/action/roles, (4) formats money-minor, (5) handles
/// unknown/denied/former-actor safely.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

AuditEvent _event({
  required String action,
  required String category,
  String? actorName = 'Amira',
  String? reason,
  Map<String, Object?> oldValues = const {},
  Map<String, Object?> newValues = const {},
}) => AuditEvent(
  eventId: 'e1',
  action: action,
  category: category,
  occurredAtLabel: '2026-07-11 14:00',
  actorName: actorName,
  restaurantName: 'Rest 1',
  branchName: 'Downtown',
  reason: reason,
  oldValues: oldValues,
  newValues: newValues,
);

void main() {
  test(
    'D29 known action -> specific localized title + category label',
    () async {
      final l10n = await _en();
      final v = AuditEventPresenter(
        l10n,
        'ILS',
      ).present(_event(action: 'order.voided', category: 'voids'));
      expect(v.title, l10n.activityLogTitleOrderVoided);
      expect(v.categoryLabel, l10n.activityLogCategoryVoids);
      expect(v.isKnownAction, isTrue);
    },
  );

  test(
    'D30 unknown action -> generic (category label), isKnownAction=false',
    () async {
      final l10n = await _en();
      final v = AuditEventPresenter(
        l10n,
        'ILS',
      ).present(_event(action: 'menu.menu_item.updated', category: 'menu'));
      expect(v.title, l10n.activityLogCategoryMenu);
      expect(v.isKnownAction, isFalse);
      // A raw action string is never shown as the title.
      expect(v.title.contains('menu.menu_item'), isFalse);
    },
  );

  test('D31 denied action sets the denied flag', () async {
    final l10n = await _en();
    final v = AuditEventPresenter(l10n, 'ILS').present(
      _event(
        action: 'order.void_denied',
        category: 'voids',
        newValues: {'attempted_action': 'void_order', 'role': 'cashier'},
      ),
    );
    expect(v.isDenied, isTrue);
  });

  test('D32 missing actor -> localized "Unavailable", never blank', () async {
    final l10n = await _en();
    final v = AuditEventPresenter(l10n, 'ILS').present(
      _event(action: 'order.voided', category: 'voids', actorName: null),
    );
    expect(v.actorLabel, l10n.activityLogActorUnknown);
  });

  test(
    'D33 PRIVACY: a secret-looking key is NEVER rendered (belt+suspenders)',
    () async {
      final l10n = await _en();
      // Even if a payload smuggled secrets past the server, the mapper drops them.
      final v = AuditEventPresenter(l10n, 'ILS').present(
        _event(
          action: 'staff.pin_set',
          category: 'staff',
          newValues: {
            'pin_set': true,
            'pin_hash': r'$2b$SUPERSECRET',
            'access_token': 'tok_leak',
            'session_token': 's3cr3t',
          },
        ),
      );
      final rendered = v.changes
          .map((c) => '${c.label}|${c.oldValue}|${c.newValue}')
          .join('~');
      expect(rendered.contains('SUPERSECRET'), isFalse);
      expect(rendered.contains('tok_leak'), isFalse);
      expect(rendered.contains('s3cr3t'), isFalse);
      // pin_set itself is a sensitive-marker ('pin') so it is dropped too.
      expect(
        v.changes.any((c) => c.label == l10n.activityLogFieldPinSet),
        isFalse,
      );
    },
  );

  test('D34 ALLOWLIST: a non-allowlisted safe key is not shown', () async {
    final l10n = await _en();
    final v = AuditEventPresenter(l10n, 'ILS').present(
      _event(
        action: 'order.voided',
        category: 'voids',
        newValues: {'status': 'voided', 'internal_worker_id': 'w-42'},
      ),
    );
    // status is allowlisted; internal_worker_id is not.
    expect(
      v.changes.any((c) => c.label == l10n.activityLogFieldStatus),
      isTrue,
    );
    final joined = v.changes.map((c) => c.newValue).join('~');
    expect(joined.contains('w-42'), isFalse);
  });

  test('D35 money-minor fields format via MoneyFormatter (old->new)', () async {
    final l10n = await _en();
    final v = AuditEventPresenter(l10n, 'ILS').present(
      _event(
        action: 'order.discount_applied',
        category: 'discounts',
        oldValues: {'grand_total_minor': 8400},
        newValues: {
          'discount_type': 'percent',
          'value': '10',
          'discount_total_minor': 840,
          'grand_total_minor': 7560,
        },
      ),
    );
    final total = v.changes.firstWhere(
      (c) => c.label == l10n.activityLogFieldOrderTotal,
    );
    expect(total.oldValue, '₪84.00');
    expect(total.newValue, '₪75.60');
    final disc = v.changes.firstWhere(
      (c) => c.label == l10n.activityLogFieldDiscountTotal,
    );
    expect(disc.newValue, '₪8.40');
  });

  test(
    'D36 capabilities object expands to Enabled/Disabled change rows',
    () async {
      final l10n = await _en();
      final v = AuditEventPresenter(l10n, 'ILS').present(
        _event(
          action: 'staff.capabilities_updated',
          category: 'staff',
          oldValues: {
            'capabilities': {
              'apply_discount': true,
              'void_order': true,
              'close_shift': true,
            },
          },
          newValues: {
            'capabilities': {
              'apply_discount': true,
              'void_order': false,
              'close_shift': true,
            },
          },
        ),
      );
      final voidCap = v.changes.firstWhere(
        (c) => c.label == l10n.activityLogCapVoidOrder,
      );
      expect(voidCap.oldValue, l10n.activityLogEnabled);
      expect(voidCap.newValue, l10n.activityLogDisabled);
    },
  );

  test('D37 role values are localized (not raw enum strings)', () async {
    final l10n = await _en();
    final v = AuditEventPresenter(l10n, 'ILS').present(
      _event(
        action: 'membership.granted',
        category: 'access',
        newValues: {'role': 'cashier'},
      ),
    );
    final role = v.changes.firstWhere(
      (c) => c.label == l10n.activityLogFieldRole,
    );
    expect(role.newValue, l10n.authRoleCashier);
    expect(role.newValue.contains('cashier'), isFalse);
  });

  test('D38 reason + scope + tone are surfaced safely', () async {
    final l10n = await _en();
    final v = AuditEventPresenter(l10n, 'ILS').present(
      _event(
        action: 'order.voided',
        category: 'voids',
        reason: 'Wrong table',
        newValues: {'status': 'voided'},
      ),
    );
    expect(v.reason, 'Wrong table');
    expect(v.scopeLabel, 'Rest 1 · Downtown');
  });

  test('D39 malformed payload (nulls/wrong types) never throws', () async {
    final l10n = await _en();
    // A capabilities value that is not a Map, and a money value as a string.
    final v = AuditEventPresenter(l10n, 'ILS').present(
      _event(
        action: 'staff.capabilities_updated',
        category: 'staff',
        newValues: {
          'capabilities': 'not-an-object',
          'grand_total_minor': 'oops',
        },
      ),
    );
    // Does not crash; the bad money coerces to 0 via the formatter.
    expect(v.title, l10n.activityLogTitleStaffCapabilities);
  });
}
