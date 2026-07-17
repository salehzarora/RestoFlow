import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/audit_action_registry.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// PSC-001C — the ACTIVITY LOG presentation of service rounds: additions and
/// round transitions (success AND denial) carry SPECIFIC localized titles
/// (never a bare category, never "Other"), classify under Orders, and render
/// only the safe server-projected scalars.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

AuditEvent _addedEvent() => const AuditEvent(
  eventId: 'ae-items-added',
  action: 'order.items_added',
  category: 'orders',
  occurredAtLabel: '2026-07-22 13:05',
  actorName: 'Amira K.',
  restaurantName: 'Rest A1',
  branchName: 'Downtown',
  oldValues: {},
  newValues: {
    'order_code': '#02A001',
    'round_number': 2,
    'added_item_count': 3,
    'order_status': 'preparing',
    'role': 'cashier',
  },
);

AuditEvent _roundEvent() => const AuditEvent(
  eventId: 'ae-round-status',
  action: 'order.round_status_updated',
  category: 'orders',
  occurredAtLabel: '2026-07-22 13:12',
  actorName: 'Sami K.',
  restaurantName: 'Rest A1',
  branchName: 'Downtown',
  oldValues: {},
  newValues: {
    'order_code': '#02A001',
    'round_number': 2,
    'from_status': 'preparing',
    'to_status': 'ready',
    'device_type': 'kds',
    'role': 'kitchen_staff',
  },
);

void main() {
  test('the registry contracts all four actions to Orders with titles', () {
    for (final action in [
      'order.items_added',
      'order.items_add_denied',
      'order.round_status_updated',
      'order.round_status_denied',
    ]) {
      expect(kAuditActionRegistry[action]?.category, 'orders', reason: action);
      expect(kAuditActionRegistry[action]?.hasTitle, isTrue, reason: action);
    }
  });

  test(
    'addition + round rows render titled in ar/he/en — never Other',
    () async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await _l(code);
        final presenter = AuditEventPresenter(l10n, 'ILS');

        final added = presenter.present(_addedEvent());
        expect(added.title, l10n.activityLogTitleItemsAdded, reason: code);
        expect(
          added.categoryLabel,
          isNot(l10n.activityLogCategoryOther),
          reason: code,
        );

        final round = presenter.present(_roundEvent());
        expect(
          round.title,
          l10n.activityLogTitleRoundStatusUpdated,
          reason: code,
        );
        expect(
          round.categoryLabel,
          isNot(l10n.activityLogCategoryOther),
          reason: code,
        );
      }
    },
  );

  test('the new safe scalars render with REAL localized labels', () async {
    for (final code in ['en', 'ar', 'he']) {
      final l10n = await _l(code);
      final view = AuditEventPresenter(l10n, 'ILS').present(_addedEvent());
      expect(view.changes, isNotEmpty, reason: code);
      for (final change in view.changes) {
        expect(change.label.trim(), isNotEmpty, reason: code);
        expect(
          change.label,
          isNot(anyOf('round_number', 'added_item_count')),
          reason: '$code: every new field needs a real localized label',
        );
      }
      expect(
        view.changes.any((c) => c.label == l10n.activityLogFieldRoundNumber),
        isTrue,
        reason: code,
      );
      expect(
        view.changes.any((c) => c.label == l10n.activityLogFieldAddedItemCount),
        isTrue,
        reason: code,
      );
    }
  });

  test('a HOSTILE payload stays safely projected (no ids, no money)', () async {
    final l10n = await _l('en');
    const hostile = AuditEvent(
      eventId: 'ae-hostile-round',
      action: 'order.items_added',
      category: 'orders',
      occurredAtLabel: '2026-07-22 13:20',
      actorName: 'X',
      restaurantName: 'R',
      branchName: 'B',
      oldValues: {},
      newValues: {
        'order_code': '#02A001',
        'round_number': 2,
        'order_id': '11111111-2222-3333-4444-555555555555',
        'round_id': '99999999-8888-7777-6666-555555555555',
        'local_operation_id': 'op-secret',
        'pin': '1234',
      },
    );
    final view = AuditEventPresenter(l10n, 'ILS').present(hostile);
    final rendered = [
      for (final c in view.changes) '${c.label}:${c.oldValue}>${c.newValue}',
    ].join('|');
    expect(rendered, isNot(contains('11111111')));
    expect(rendered, isNot(contains('99999999')));
    expect(rendered, isNot(contains('op-secret')));
    expect(rendered, isNot(contains('1234')));
  });
}
