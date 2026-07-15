import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart'
    show statusLabelFor;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RESTAURANT-OPERATIONS-V1-001 — Dashboard coverage: type-aware served
/// wording, and the Activity Log presentation of the phase's two new action
/// families (titles, localized field labels, localized closed-enum VALUES —
/// never raw wire tokens).
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

AuditEvent _event({
  required String action,
  required String category,
  String? reason,
  Map<String, Object?> oldValues = const {},
  Map<String, Object?> newValues = const {},
}) => AuditEvent(
  eventId: 'e1',
  action: action,
  category: category,
  occurredAtLabel: '2026-07-14 14:00',
  actorName: 'Amira',
  restaurantName: 'Rest 1',
  branchName: 'Downtown',
  reason: reason,
  oldValues: oldValues,
  newValues: newValues,
);

void main() {
  group('A. type-aware served wording', () {
    test('A1 a takeaway served row reads "Picked up"', () async {
      final l10n = await _l('en');
      expect(
        statusLabelFor(l10n, 'served', 'takeaway'),
        l10n.ordersStatusPickedUp,
      );
    });

    test('A2 a dine-in served row still reads "Served"', () async {
      final l10n = await _l('en');
      expect(
        statusLabelFor(l10n, 'served', 'dine_in'),
        l10n.ordersStatusServed,
      );
    });

    test('A3 every other status is untouched by the type', () async {
      final l10n = await _l('en');
      expect(statusLabelFor(l10n, 'ready', 'takeaway'), l10n.ordersStatusReady);
      expect(
        statusLabelFor(l10n, 'completed', 'takeaway'),
        l10n.ordersStatusCompleted,
      );
    });

    test('A4 the picked-up wording is TRANSLATED in ar/he', () async {
      final ar = await _l('ar');
      final he = await _l('he');
      expect(ar.ordersStatusPickedUp, isNot('Picked up'));
      expect(he.ordersStatusPickedUp, isNot('Picked up'));
    });
  });

  group('B. Activity Log — menu availability', () {
    test('B1 availability_changed: title + localized before/after', () async {
      final l10n = await _l('en');
      final v = AuditEventPresenter(l10n, 'ILS').present(
        _event(
          action: 'menu.menu_item.availability_changed',
          category: 'menu',
          reason: 'sold_out',
          oldValues: {'availability': 'available', 'availability_reason': null},
          newValues: {
            'availability': 'unavailable',
            'availability_reason': 'sold_out',
            'item_name': 'Falafel',
          },
        ),
      );
      expect(v.title, l10n.activityLogTitleMenuAvailabilityChanged);
      final rendered = [
        for (final f in v.changes) '${f.label}: ${f.oldValue} -> ${f.newValue}',
      ].join('\n');
      // Values are LOCALIZED closed enums, never the raw wire tokens.
      expect(rendered, contains(l10n.menuAvailabilityAvailable));
      expect(rendered, isNot(contains('sold_out')));
      expect(rendered, contains(l10n.menuAvailabilitySoldOut));
      // The item's display name is shown (it is on the safe allowlist).
      expect(rendered, contains('Falafel'));
    });

    test('B2 availability_denied has its own title', () async {
      final l10n = await _l('en');
      final v = AuditEventPresenter(l10n, 'ILS').present(
        _event(action: 'menu.menu_item.availability_denied', category: 'menu'),
      );
      expect(v.title, l10n.activityLogTitleMenuAvailabilityDenied);
    });
  });

  group('C. Activity Log — table moves', () {
    test('C1 table_moved: title + from/to floor labels', () async {
      final l10n = await _l('en');
      final v = AuditEventPresenter(l10n, 'ILS').present(
        _event(
          action: 'order.table_moved',
          category: 'orders',
          oldValues: {'table_label': 'T1'},
          newValues: {
            'table_label': 'T4',
            'from_table_label': 'T1',
            'to_table_label': 'T4',
            'order_code': '#0D0001',
          },
        ),
      );
      expect(v.title, l10n.activityLogTitleOrderTableMoved);
      final rendered = [
        for (final f in v.changes) '${f.label}: ${f.oldValue} -> ${f.newValue}',
      ].join('\n');
      expect(rendered, contains('T1'));
      expect(rendered, contains('T4'));
      expect(rendered, contains('#0D0001'));
    });

    test('C2 table_move_denied: title + localized denied reason', () async {
      final l10n = await _l('en');
      final v = AuditEventPresenter(l10n, 'ILS').present(
        _event(
          action: 'order.table_move_denied',
          category: 'orders',
          newValues: {
            'attempted_action': 'move_table',
            'denied_reason': 'takeaway_order',
            'order_status': 'preparing',
          },
        ),
      );
      expect(v.title, l10n.activityLogTitleOrderTableMoveDenied);
      final rendered = [
        for (final f in v.changes) '${f.label}: ${f.newValue}',
      ].join('\n');
      // The closed-enum reason is localized, never the raw token.
      expect(rendered, contains(l10n.activityLogDeniedTakeawayOrder));
      expect(rendered, isNot(contains('takeaway_order')));
    });

    test('C3 the other move refusal reasons are localized too', () async {
      final l10n = await _l('en');
      for (final (token, label) in [
        ('order_not_movable', l10n.activityLogDeniedOrderNotMovable),
        ('table_not_available', l10n.activityLogDeniedTableNotAvailable),
        // Stabilization regression: this phase is the FIRST to emit
        // permission_denied as a denied_reason VALUE — it must localize.
        ('permission_denied', l10n.activityLogDeniedPermission),
      ]) {
        final v = AuditEventPresenter(l10n, 'ILS').present(
          _event(
            action: 'order.table_move_denied',
            category: 'orders',
            newValues: {'denied_reason': token},
          ),
        );
        final rendered = [for (final f in v.changes) '${f.newValue}'].join();
        expect(rendered, contains(label));
      }
    });
  });
}
