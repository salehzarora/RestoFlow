import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/audit_action_registry.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_dashboard/src/format/money_format.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDER-EDIT-001A — the ACTIVITY LOG coverage (API_CONTRACT §4.33) of the five
/// new audit actions: editing a sent order, its refusal, the kitchen's
/// acknowledgement of the change, that acknowledgement's refusal, and the
/// branch order-editing settings. Every action is registered with its category
/// and a specific localized title in ar/he/en; every new safe detail key has a
/// real label and its closed-enum values render localized (never raw tokens);
/// ids, revisions and local operation ids never render.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

const _codes = ['en', 'ar', 'he'];

AuditEventView _view(AppLocalizations l10n, AuditEvent e) =>
    AuditEventPresenter(l10n, 'ILS').present(e);

AuditEvent _ev(
  String action, {
  String category = 'orders',
  Map<String, Object?> oldValues = const {},
  Map<String, Object?> newValues = const {},
}) => AuditEvent(
  eventId: 'ev-$action',
  action: action,
  category: category,
  occurredAtLabel: '2026-10-08 12:00',
  actorName: 'Sami K.',
  restaurantName: 'Rest A1',
  branchName: 'Downtown',
  oldValues: oldValues,
  newValues: newValues,
);

/// A realistic `order.edited` projection (the server's app.audit_safe_detail
/// output) — totals before→after plus the edit's safe scalars.
AuditEvent _editedEvent({
  String kitchenChannel = 'kds',
  String? reasonCode = 'entry_mistake',
}) => _ev(
  'order.edited',
  oldValues: const {
    'order_status': 'preparing',
    'subtotal_minor': 5000,
    'discount_total_minor': 0,
    'grand_total_minor': 5000,
  },
  newValues: {
    'order_code': '#02A001',
    'edit_number': 2,
    'order_status': 'preparing',
    'role': 'cashier',
    'device_type': 'pos',
    'reason_code': ?reasonCode,
    'kitchen_channel': kitchenChannel,
    'kitchen_ack_required': true,
    'removed_item_count': 1,
    'modified_item_count': 2,
    'added_item_count': 3,
    'subtotal_minor': 4200,
    'discount_total_minor': 0,
    'grand_total_minor': 4200,
  },
);

AuditChange _row(AuditEventView v, String label) =>
    v.changes.firstWhere((c) => c.label == label);

Iterable<String> _values(AuditEventView v) => [
  for (final c in v.changes) ...[c.newValue, ?c.oldValue],
];

const _newFieldKeys = [
  'edit_number',
  'kitchen_channel',
  'reason_code',
  'removed_item_count',
  'modified_item_count',
  'up_to_edit_number',
  'acknowledged_count',
  'order_edit_enabled',
  'order_edit_finished_food_manager_only',
];

void main() {
  test('R1 the registry contracts all five actions with category + title', () {
    const expected = {
      'order.edited': 'orders',
      'order.edit_denied': 'orders',
      'order.edit_acknowledged': 'orders',
      'order.edit_ack_denied': 'orders',
      'settings.branch.order_edit_updated': 'settings',
    };
    expected.forEach((action, category) {
      final spec = kAuditActionRegistry[action];
      expect(spec, isNotNull, reason: action);
      expect(spec!.category, category, reason: action);
      expect(spec.hasTitle, isTrue, reason: action);
      expect(spec.intentionalOther, isFalse, reason: action);
    });
  });

  for (final code in _codes) {
    test('T1 each action has its own title in $code, never Other', () async {
      final l10n = await _l(code);
      final cases = <(String, String, String, String, bool)>[
        (
          'order.edited',
          'orders',
          l10n.activityLogTitleOrderEdited,
          l10n.activityLogCategoryOrders,
          false,
        ),
        (
          'order.edit_denied',
          'orders',
          l10n.activityLogTitleOrderEditDenied,
          l10n.activityLogCategoryOrders,
          true,
        ),
        (
          'order.edit_acknowledged',
          'orders',
          l10n.activityLogTitleOrderEditAcknowledged,
          l10n.activityLogCategoryOrders,
          false,
        ),
        (
          'order.edit_ack_denied',
          'orders',
          l10n.activityLogTitleOrderEditAckDenied,
          l10n.activityLogCategoryOrders,
          true,
        ),
        (
          'settings.branch.order_edit_updated',
          'settings',
          l10n.activityLogTitleOrderEditSettingsUpdated,
          l10n.activityLogCategorySettings,
          false,
        ),
      ];
      final titles = <String>{};
      for (final (action, category, title, categoryLabel, denied) in cases) {
        final v = _view(l10n, _ev(action, category: category));
        expect(v.title, title, reason: '$code $action');
        expect(v.title.trim(), isNotEmpty, reason: '$code $action');
        expect(v.isKnownAction, isTrue, reason: '$code $action');
        expect(v.categoryLabel, categoryLabel, reason: '$code $action');
        expect(
          v.categoryLabel,
          isNot(l10n.activityLogCategoryOther),
          reason: '$code $action',
        );
        expect(v.isDenied, denied, reason: '$code $action');
        titles.add(v.title);
      }
      expect(titles, hasLength(5), reason: '$code: five DISTINCT titles');
    });

    test('T2 an edit renders localized labels + values in $code', () async {
      final l10n = await _l(code);
      final v = _view(l10n, _editedEvent());

      expect(_row(v, l10n.activityLogFieldEditNumber).newValue, '2');
      expect(
        _row(v, l10n.activityLogFieldKitchenChannel).newValue,
        l10n.activityLogKitchenChannelKds,
      );
      expect(
        _row(v, l10n.activityLogFieldReasonCode).newValue,
        l10n.activityLogEditReasonEntryMistake,
      );
      expect(_row(v, l10n.activityLogFieldRemovedItemCount).newValue, '1');
      expect(_row(v, l10n.activityLogFieldModifiedItemCount).newValue, '2');
      expect(_row(v, l10n.activityLogFieldAddedItemCount).newValue, '3');
      expect(
        _row(v, l10n.activityLogFieldKitchenAckRequired).newValue,
        l10n.activityLogEnabled,
      );

      // The edit legitimately carries money: totals before→after (NOT in the
      // client money-free strip), formatted from integer minor units.
      final total = _row(v, l10n.activityLogFieldOrderTotal);
      expect(total.oldValue, MoneyFormatter.formatMinor(5000, 'ILS'));
      expect(total.newValue, MoneyFormatter.formatMinor(4200, 'ILS'));
      final subtotal = _row(v, l10n.activityLogFieldSubtotal);
      expect(subtotal.oldValue, isNot(subtotal.newValue));

      // Never the raw server tokens, never a raw key as a label.
      final values = _values(v);
      for (final raw in ['kds', 'entry_mistake']) {
        expect(values, isNot(contains(raw)), reason: '$code $raw');
      }
      for (final c in v.changes) {
        expect(c.label, isNot(isIn(_newFieldKeys)), reason: '$code ${c.label}');
      }
    });

    test(
      'T3 every kitchen channel + edit reason is localized in $code',
      () async {
        final l10n = await _l(code);
        final paper = _view(l10n, _editedEvent(kitchenChannel: 'paper'));
        expect(
          _row(paper, l10n.activityLogFieldKitchenChannel).newValue,
          l10n.activityLogKitchenChannelPaper,
        );

        final reasons = {
          'customer_changed_mind':
              l10n.activityLogEditReasonCustomerChangedMind,
          'entry_mistake': l10n.activityLogEditReasonEntryMistake,
          'item_unavailable': l10n.activityLogEditReasonItemUnavailable,
          'kitchen_issue': l10n.activityLogEditReasonKitchenIssue,
          'other': l10n.activityLogEditReasonOther,
        };
        expect(reasons.values.toSet(), hasLength(5), reason: code);
        reasons.forEach((token, label) {
          final v = _view(l10n, _editedEvent(reasonCode: token));
          final row = _row(v, l10n.activityLogFieldReasonCode);
          expect(row.newValue, label, reason: '$code $token');
          expect(row.newValue, isNot(token), reason: '$code $token');
        });

        // An edit without a reason (adding only) simply has no reason row.
        final noReason = _view(l10n, _editedEvent(reasonCode: null));
        expect(
          noReason.changes.any(
            (c) => c.label == l10n.activityLogFieldReasonCode,
          ),
          isFalse,
          reason: code,
        );
      },
    );

    test('T4 a refused edit says WHY, localized, in $code', () async {
      final l10n = await _l(code);
      final reasons = {
        'removal_not_permitted': l10n.activityLogDeniedRemovalNotPermitted,
        'finished_food_needs_manager':
            l10n.activityLogDeniedFinishedFoodNeedsManager,
        'reason_required': l10n.activityLogDeniedReasonRequired,
        'feature_disabled': l10n.activityLogDeniedFeatureDisabled,
        'order_not_editable': l10n.activityLogDeniedOrderNotEditable,
        'order_already_settled': l10n.activityLogDeniedOrderAlreadySettled,
        'kitchen_mode_changed': l10n.activityLogDeniedKitchenModeChanged,
        'line_changed': l10n.activityLogDeniedLineChanged,
        'line_has_discount': l10n.activityLogDeniedLineHasDiscount,
        'legacy_line_not_editable': l10n.activityLogDeniedLegacyLineNotEditable,
        'edit_would_empty_order': l10n.activityLogDeniedEditWouldEmptyOrder,
        'tax_mode_unsupported': l10n.activityLogDeniedTaxModeUnsupported,
        'totals_mismatch': l10n.activityLogDeniedTotalsMismatch,
        'item_unavailable': l10n.activityLogDeniedItemUnavailable,
        'modifier_option_not_in_scope':
            l10n.activityLogDeniedModifierOptionNotInScope,
        'modifier_prep_snapshot_stale':
            l10n.activityLogDeniedModifierPrepSnapshotStale,
        'invalid_device_type': l10n.activityLogDeniedInvalidDeviceType,
        // Existing tokens the edit path reuses — the existing labels.
        'permission_denied': l10n.activityLogDeniedPermission,
        'full_comp_permission_required':
            l10n.activityLogDeniedFullCompPermissionRequired,
        'discount_exceeds_order_total':
            l10n.activityLogDeniedDiscountExceedsOrderTotal,
      };
      reasons.forEach((token, label) {
        final v = _view(
          l10n,
          _ev(
            'order.edit_denied',
            newValues: {
              'attempted_action': 'edit_order',
              'order_code': '#02A001',
              'role': 'cashier',
              'device_type': 'pos',
              'order_status': 'preparing',
              'denied_reason': token,
            },
          ),
        );
        expect(v.isDenied, isTrue, reason: '$code $token');
        expect(v.title, l10n.activityLogTitleOrderEditDenied);
        final row = _row(v, l10n.activityLogFieldDeniedReason);
        expect(row.newValue, label, reason: '$code $token');
        expect(row.newValue, isNot(token), reason: '$code $token');
      });
    });

    test('T5 the kitchen acknowledgement + its refusal in $code', () async {
      final l10n = await _l(code);
      final ack = _view(
        l10n,
        _ev(
          'order.edit_acknowledged',
          newValues: const {
            'order_code': '#02A001',
            'up_to_edit_number': 3,
            'acknowledged_count': 2,
            'role': 'kitchen_staff',
            'device_type': 'kds',
          },
        ),
      );
      expect(ack.isDenied, isFalse, reason: code);
      expect(_row(ack, l10n.activityLogFieldUpToEditNumber).newValue, '3');
      expect(_row(ack, l10n.activityLogFieldAcknowledgedCount).newValue, '2');

      for (final (token, label) in [
        ('invalid_edit_number', l10n.activityLogDeniedInvalidEditNumber),
        ('order_voided', l10n.activityLogDeniedOrderVoided),
        ('permission_denied', l10n.activityLogDeniedPermission),
        ('invalid_device_type', l10n.activityLogDeniedInvalidDeviceType),
      ]) {
        final denied = _view(
          l10n,
          _ev(
            'order.edit_ack_denied',
            newValues: {
              'attempted_action': 'kitchen_ack_order_edit',
              'order_code': '#02A001',
              'role': 'kitchen_staff',
              'device_type': 'kds',
              'order_status': 'preparing',
              'denied_reason': token,
            },
          ),
        );
        expect(denied.isDenied, isTrue, reason: '$code $token');
        expect(denied.title, l10n.activityLogTitleOrderEditAckDenied);
        expect(
          _row(denied, l10n.activityLogFieldDeniedReason).newValue,
          label,
          reason: '$code $token',
        );
      }
    });

    test('T6 the order-edit settings are labelled before→after rows in '
        '$code', () async {
      final l10n = await _l(code);
      final v = _view(
        l10n,
        _ev(
          'settings.branch.order_edit_updated',
          category: 'settings',
          oldValues: const {
            'order_edit_enabled': false,
            'order_edit_finished_food_manager_only': true,
          },
          newValues: const {
            'order_edit_enabled': true,
            'order_edit_finished_food_manager_only': false,
          },
        ),
      );
      final enabled = _row(v, l10n.activityLogFieldOrderEditEnabled);
      expect(enabled.oldValue, l10n.activityLogDisabled);
      expect(enabled.newValue, l10n.activityLogEnabled);
      final managerOnly = _row(
        v,
        l10n.activityLogFieldOrderEditFinishedFoodManagerOnly,
      );
      expect(managerOnly.oldValue, l10n.activityLogEnabled);
      expect(managerOnly.newValue, l10n.activityLogDisabled);
      expect(_values(v), isNot(contains('true')));
      expect(_values(v), isNot(contains('false')));
    });

    test(
      'T7 an automatic completion caused by an edit says so in $code',
      () async {
        final l10n = await _l(code);
        final v = _view(
          l10n,
          _ev(
            'order.status_updated',
            newValues: const {
              'order_code': '#02A001',
              'order_status': 'completed',
              'completion_mode': 'automatic',
              'completion_trigger': 'order_edited',
            },
          ),
        );
        final row = _row(v, l10n.activityLogFieldCompletionTrigger);
        expect(row.newValue, l10n.activityLogCompletionTriggerOrderEdited);
        expect(row.newValue, isNot('order_edited'));
      },
    );

    test('T8 every new detail key has a real label in $code', () async {
      final l10n = await _l(code);
      final displayable = auditDisplayableFieldKeys();
      for (final key in _newFieldKeys) {
        expect(displayable, contains(key), reason: key);
        final label = auditFieldLabel(l10n, key);
        expect(label, isNot(key), reason: '$code $key');
        expect(label.trim(), isNotEmpty, reason: '$code $key');
      }
    });
  }

  test('T9 ids, revisions and local operation ids never render', () async {
    for (final code in _codes) {
      final l10n = await _l(code);
      final v = _view(
        l10n,
        _ev(
          'order.edited',
          oldValues: const {
            'grand_total_minor': 5000,
            'revision': 7,
            'order_revision': 7,
          },
          newValues: const {
            'order_code': '#02A001',
            'edit_number': 1,
            'order_id': '11111111-2222-3333-4444-555555555555',
            'order_edit_id': '66666666-7777-8888-9999-aaaaaaaaaaaa',
            'order_item_id': '77777777-8888-9999-aaaa-bbbbbbbbbbbb',
            'device_id': '88888888-9999-aaaa-bbbb-cccccccccccc',
            'revision': 8,
            'order_revision': 8,
            'local_operation_id': 'op-secret-123',
            'removed_item_ids': ['99999999-0000-1111-2222-333333333333'],
            'lines': [
              {'order_item_id': 'nested-uuid', 'quantity': 2},
            ],
            'grand_total_minor': 4200,
          },
        ),
      );
      final rendered = [
        for (final c in v.changes) '${c.label}:${c.oldValue}>${c.newValue}',
      ].join('|');
      for (final leak in [
        '11111111',
        '66666666',
        '77777777',
        '88888888',
        '99999999',
        'nested-uuid',
        'op-secret-123',
        'revision',
        'local_operation_id',
      ]) {
        expect(rendered, isNot(contains(leak)), reason: '$code $leak');
      }
      // Only the safe scalars survive: order code, edit number, total.
      expect(v.changes, hasLength(3), reason: '$code: $rendered');
    }
  });

  test('T10 an unknown enum token shows raw — an honest unknown', () async {
    final l10n = await _l('en');
    final v = _view(
      l10n,
      _editedEvent(kitchenChannel: 'carrier_pigeon', reasonCode: 'mystery'),
    );
    expect(
      _row(v, l10n.activityLogFieldKitchenChannel).newValue,
      'carrier_pigeon',
    );
    expect(_row(v, l10n.activityLogFieldReasonCode).newValue, 'mystery');
  });

  test('G the real audit registry has NO coverage violations', () async {
    final en = await _l('en');
    final ar = await _l('ar');
    final he = await _l('he');
    final violations = auditRegistryViolations(en, ar, he);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
