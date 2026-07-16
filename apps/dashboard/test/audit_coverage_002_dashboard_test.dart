import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/audit_action_registry.dart';
import 'package:restoflow_dashboard/src/data/audit_log_models.dart';
import 'package:restoflow_dashboard/src/data/audit_log_presentation.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// AUDIT-COVERAGE-002 — settings/timezone changes classify under Settings &
/// configuration (not Other) with safe before/after detail, and the audit
/// registry guard enforces coverage for every known action.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

AuditEvent _event({
  required String action,
  required String category,
  Map<String, Object?> oldValues = const {},
  Map<String, Object?> newValues = const {},
}) => AuditEvent(
  eventId: 'e1',
  action: action,
  category: category,
  occurredAtLabel: '2026-07-11 10:00',
  actorName: 'Amira',
  restaurantName: 'Rest 1',
  branchName: 'Downtown',
  oldValues: oldValues,
  newValues: newValues,
);

void main() {
  // ===== classification =====================================================
  test(
    'C1 branch timezone/settings change is Settings & configuration, not Other',
    () async {
      final en = await _l('en');
      final v = AuditEventPresenter(en, 'ILS').present(
        _event(
          action: 'settings.branch.updated',
          category: 'settings',
          oldValues: {'timezone': 'UTC'},
          newValues: {'timezone': 'Asia/Jerusalem'},
        ),
      );
      expect(v.categoryLabel, en.activityLogCategorySettings);
      expect(v.categoryLabel, isNot(en.activityLogCategoryOther));
      expect(v.title, en.activityLogTitleBranchSettings);
      expect(v.isKnownAction, isTrue);
    },
  );

  test(
    'C2 restaurant + organization settings changes are Settings & configuration',
    () async {
      final en = await _l('en');
      for (final action in [
        'settings.restaurant.updated',
        'settings.organization.updated',
      ]) {
        final v = AuditEventPresenter(
          en,
          'ILS',
        ).present(_event(action: action, category: 'settings'));
        expect(v.categoryLabel, en.activityLogCategorySettings);
        expect(v.isKnownAction, isTrue);
      }
    },
  );

  test(
    'C3 a settings denial is Settings & configuration + Denied (not Other)',
    () async {
      final en = await _l('en');
      final v = AuditEventPresenter(en, 'ILS').present(
        _event(action: 'settings.branch.update_denied', category: 'settings'),
      );
      expect(v.categoryLabel, en.activityLogCategorySettings);
      expect(v.isDenied, isTrue);
    },
  );

  test(
    'C4 an unknown/legacy action still falls back to Other safely',
    () async {
      final en = await _l('en');
      final v = AuditEventPresenter(
        en,
        'ILS',
      ).present(_event(action: 'reservation.created', category: 'other'));
      expect(v.categoryLabel, en.activityLogCategoryOther);
      expect(v.isKnownAction, isFalse);
    },
  );

  test('C5 the settings category is a first-class filter option', () {
    expect(AuditCategory.values.any((c) => c.wire == 'settings'), isTrue);
    expect(AuditCategory.settings.wire, 'settings');
  });

  // ===== event content (safe before/after) ==================================
  test(
    'C6 previous + new timezone are shown with a localized field label',
    () async {
      final en = await _l('en');
      final v = AuditEventPresenter(en, 'ILS').present(
        _event(
          action: 'settings.branch.updated',
          category: 'settings',
          oldValues: {
            'timezone': 'UTC',
            'name': 'Downtown',
            'status': 'active',
          },
          newValues: {
            'timezone': 'Asia/Jerusalem',
            'name': 'Downtown',
            'status': 'active',
          },
        ),
      );
      final tz = v.changes.firstWhere(
        (c) => c.label == en.activityLogFieldTimezone,
      );
      expect(tz.oldValue, 'UTC');
      expect(tz.newValue, 'Asia/Jerusalem');
    },
  );

  test(
    'C7 a settings payload never renders an internal or secret key',
    () async {
      final en = await _l('en');
      final v = AuditEventPresenter(en, 'ILS').present(
        _event(
          action: 'settings.branch.updated',
          category: 'settings',
          newValues: {
            'timezone': 'Asia/Jerusalem',
            'id': 'b-internal',
            'organization_id': 'o-internal',
            'address': '1 King St',
            'api_key': 'leak',
          },
        ),
      );
      final rendered = v.changes
          .map((c) => '${c.label}|${c.newValue}')
          .join('~');
      expect(rendered.contains('b-internal'), isFalse);
      expect(rendered.contains('o-internal'), isFalse);
      expect(
        rendered.contains('1 King St'),
        isFalse,
      ); // address dropped (client allowlist)
      expect(rendered.contains('leak'), isFalse);
      // but the safe timezone IS shown.
      expect(
        v.changes.any((c) => c.label == en.activityLogFieldTimezone),
        isTrue,
      );
    },
  );

  // ===== PILOT-OPERATIONS-CORRECTIONS-001 (B4): operational table actions =====
  test(
    'B4 every new table action is registered under Tables with a title',
    () async {
      final en = await _l('en');
      const successActions = {
        'table.status_set': null,
        'table.tables_linked': null,
        'table.tables_unlinked': null,
      };
      const deniedActions = {
        'table.status_denied',
        'table.link_denied',
        'table.unlink_denied',
      };
      for (final action in [...successActions.keys, ...deniedActions]) {
        // registered under the Tables category...
        expect(
          kAuditActionRegistry[action]?.category,
          'tables',
          reason: '$action not registered under tables',
        );
        final v = AuditEventPresenter(
          en,
          'ILS',
        ).present(_event(action: action, category: 'tables'));
        // ...renders a SPECIFIC title (never the generic category fallback)...
        expect(
          v.isKnownAction,
          isTrue,
          reason: '$action has no specific title',
        );
        expect(v.categoryLabel, en.activityLogCategoryTables);
      }
      // ...and a denial reads as denied.
      final denied = AuditEventPresenter(en, 'ILS').present(
        _event(
          action: 'table.status_denied',
          category: 'tables',
          newValues: {
            'denied_reason': 'permission_denied',
            'to_status': 'reserved',
          },
        ),
      );
      expect(denied.isDenied, isTrue);
    },
  );

  test(
    'B4 the table payload renders from/to status + group label safely',
    () async {
      final en = await _l('en');
      final statusChange = AuditEventPresenter(en, 'ILS').present(
        _event(
          action: 'table.status_set',
          category: 'tables',
          oldValues: {'status': 'available'},
          newValues: {
            'status': 'reserved',
            'from_status': 'available',
            'to_status': 'reserved',
            'table_label': 'T4',
          },
        ),
      );
      expect(
        statusChange.changes.any((c) => c.label == en.activityLogFieldToStatus),
        isTrue,
      );
      final link = AuditEventPresenter(en, 'ILS').present(
        _event(
          action: 'table.tables_linked',
          category: 'tables',
          newValues: {'group_label': 'T4 + T5', 'table_label': 'T4'},
        ),
      );
      final group = link.changes.firstWhere(
        (c) => c.label == en.activityLogFieldGroupLabel,
      );
      expect(group.newValue, 'T4 + T5');
    },
  );

  // ===== the coverage GUARD =================================================
  test('G1 the real audit registry has NO coverage violations', () async {
    final en = await _l('en');
    final ar = await _l('ar');
    final he = await _l('he');
    final violations = auditRegistryViolations(en, ar, he);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
    'G2 the guard FAILS for a known action left in Other (missing category)',
    () async {
      final en = await _l('en');
      final ar = await _l('ar');
      final he = await _l('he');
      final bad = {
        'reservation.created': const AuditActionSpec(category: 'other'),
      };
      final violations = auditRegistryViolations(en, ar, he, registry: bad);
      expect(violations.any((s) => s.contains('reservation.created')), isTrue);
    },
  );

  test(
    'G3 the guard FAILS for a hasTitle action with no presenter title',
    () async {
      final en = await _l('en');
      final ar = await _l('ar');
      final he = await _l('he');
      final bad = {
        'reservation.created': const AuditActionSpec(
          category: 'orders',
          hasTitle: true,
        ),
      };
      final violations = auditRegistryViolations(en, ar, he, registry: bad);
      expect(violations.any((s) => s.contains('hasTitle')), isTrue);
    },
  );

  test(
    'G4 an intentional-Other action (printer) is accepted (documented exception)',
    () async {
      final en = await _l('en');
      final ar = await _l('ar');
      final he = await _l('he');
      final ok = {
        'printer.printer_device.updated': const AuditActionSpec(
          category: 'other',
          intentionalOther: true,
        ),
      };
      expect(auditRegistryViolations(en, ar, he, registry: ok), isEmpty);
    },
  );

  test(
    'G5 every displayable detail field has a localized label (no raw keys)',
    () async {
      final en = await _l('en');
      for (final key in auditDisplayableFieldKeys()) {
        expect(
          auditFieldLabel(en, key),
          isNot(key),
          reason: 'field "$key" has no label',
        );
      }
    },
  );
}
