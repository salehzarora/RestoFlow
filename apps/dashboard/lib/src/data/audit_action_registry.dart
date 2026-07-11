/// The authoritative CONTRACT registry of known operational audit actions
/// (AUDIT-COVERAGE-002).
///
/// SQL is authoritative for classification (`app.audit_category`) and for the
/// safe payload projection (`app.audit_safe_detail`). This registry is the
/// CLIENT-side presentation/localization contract: for every known server
/// action it declares the category it must map to and whether the presenter
/// gives it a specific localized title. [auditRegistryViolations] turns it into
/// an automated guard so a newly-supported action cannot silently lack a
/// category or localized presentation, and known config actions cannot fall into
/// the generic "Other" bucket.
///
/// It intentionally lists EVERY action in the families this ticket touches
/// (settings.*) plus every specifically-titled action, and a representative per
/// remaining family (the SQL classifier is prefix-based, so a representative
/// proves the family→category contract). A future ticket adding an action MUST
/// add it here (see the audit-coverage checklist in API_CONTRACT.md).
library;

import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'audit_log_models.dart';
import 'audit_log_presentation.dart';

/// The presentation contract for one known audit action.
class AuditActionSpec {
  const AuditActionSpec({
    required this.category,
    this.hasTitle = false,
    this.intentionalOther = false,
  });

  /// The category the server (`app.audit_category`) classifies this action into.
  final String category;

  /// Whether the presenter provides a specific localized title (vs. showing the
  /// category label). Denials typically show the category label + a "Denied"
  /// pill, so they are `hasTitle: false`.
  final bool hasTitle;

  /// True ONLY for actions deliberately left in the generic "other" bucket (a
  /// documented deferral or genuinely-ambiguous legacy action). Exempt from the
  /// "known actions must not be Other" guard. Must stay rare and justified.
  final bool intentionalOther;
}

/// Every known operational audit action -> its presentation contract.
const Map<String, AuditActionSpec> kAuditActionRegistry = {
  // --- orders / voids / discounts -------------------------------------------
  'order.submitted': AuditActionSpec(category: 'orders', hasTitle: true),
  'order.status_updated': AuditActionSpec(category: 'orders', hasTitle: true),
  'order.status_update_denied': AuditActionSpec(category: 'orders'),
  'order.voided': AuditActionSpec(category: 'voids', hasTitle: true),
  'order.void_denied': AuditActionSpec(category: 'voids'),
  'order.discount_applied': AuditActionSpec(
    category: 'discounts',
    hasTitle: true,
  ),
  'order.discount_denied': AuditActionSpec(category: 'discounts'),
  // --- payments -------------------------------------------------------------
  'payment.recorded': AuditActionSpec(category: 'payments', hasTitle: true),
  'payment.denied': AuditActionSpec(category: 'payments'),
  'receipt_number.assigned': AuditActionSpec(category: 'payments'),
  // --- shifts / cash --------------------------------------------------------
  'shift.opened': AuditActionSpec(category: 'shifts', hasTitle: true),
  'shift.open_denied': AuditActionSpec(category: 'shifts'),
  'shift.closed': AuditActionSpec(category: 'shifts', hasTitle: true),
  'shift.close_denied': AuditActionSpec(category: 'shifts'),
  'shift.reconciled': AuditActionSpec(category: 'shifts', hasTitle: true),
  'shift.reconcile_denied': AuditActionSpec(category: 'shifts'),
  'cash_drawer.closed': AuditActionSpec(category: 'shifts'),
  // --- staff ----------------------------------------------------------------
  'staff.created': AuditActionSpec(category: 'staff', hasTitle: true),
  'staff.create_denied': AuditActionSpec(category: 'staff'),
  'staff.pin_set': AuditActionSpec(category: 'staff', hasTitle: true),
  'staff.pin_set_denied': AuditActionSpec(category: 'staff'),
  'staff.capabilities_updated': AuditActionSpec(
    category: 'staff',
    hasTitle: true,
  ),
  'staff.capabilities_denied': AuditActionSpec(category: 'staff'),
  // --- access (membership / employee / pin session) -------------------------
  'membership.granted': AuditActionSpec(category: 'access', hasTitle: true),
  'membership.grant_denied': AuditActionSpec(category: 'access'),
  'membership.role_updated': AuditActionSpec(
    category: 'access',
    hasTitle: true,
  ),
  'membership.role_update_denied': AuditActionSpec(category: 'access'),
  'membership.revoked': AuditActionSpec(category: 'access', hasTitle: true),
  'membership.revoke_denied': AuditActionSpec(category: 'access'),
  'employee.revoked': AuditActionSpec(category: 'access', hasTitle: true),
  'employee.revoke_denied': AuditActionSpec(category: 'access'),
  'pin_session.failed': AuditActionSpec(category: 'access'),
  'pin_session.started': AuditActionSpec(category: 'access'),
  // --- devices --------------------------------------------------------------
  'device.created': AuditActionSpec(category: 'devices', hasTitle: true),
  'device.create_denied': AuditActionSpec(category: 'devices'),
  'device.revoked': AuditActionSpec(category: 'devices', hasTitle: true),
  'device.revoke_denied': AuditActionSpec(category: 'devices'),
  'device.revoked_management': AuditActionSpec(
    category: 'devices',
    hasTitle: true,
  ),
  'device.session_started': AuditActionSpec(
    category: 'devices',
    hasTitle: true,
  ),
  'device.activated': AuditActionSpec(category: 'devices'),
  // --- settings / configuration (this ticket) -------------------------------
  'settings.branch.updated': AuditActionSpec(
    category: 'settings',
    hasTitle: true,
  ),
  'settings.branch.update_denied': AuditActionSpec(category: 'settings'),
  'settings.restaurant.updated': AuditActionSpec(
    category: 'settings',
    hasTitle: true,
  ),
  'settings.restaurant.update_denied': AuditActionSpec(category: 'settings'),
  'settings.organization.updated': AuditActionSpec(
    category: 'settings',
    hasTitle: true,
  ),
  'settings.organization.update_denied': AuditActionSpec(category: 'settings'),
  // --- menu / tables / organization / sync (representatives) ----------------
  'menu.menu_item.updated': AuditActionSpec(category: 'menu'),
  'menu.menu_item.upsert_denied': AuditActionSpec(category: 'menu'),
  'table.created': AuditActionSpec(category: 'tables'),
  'table.delete_denied': AuditActionSpec(category: 'tables'),
  'organization.created': AuditActionSpec(
    category: 'organization',
    hasTitle: true,
  ),
  'sync.operation_conflict': AuditActionSpec(category: 'sync'),
  'sync.operation_rejected': AuditActionSpec(category: 'sync'),
  // --- INTENTIONAL 'other': printer.* config is deferred to a future
  // printer-domain ticket (the printer domain is out of scope here). Documented,
  // exempt from the not-Other guard — NOT a silent fall-through.
  'printer.printer_device.updated': AuditActionSpec(
    category: 'other',
    intentionalOther: true,
  ),
  'printer.printer_route.updated': AuditActionSpec(
    category: 'other',
    intentionalOther: true,
  ),
};

/// Runs the audit-coverage guard against [registry] (default the real one) and
/// returns a list of human-readable violations (empty = healthy). Verifies:
///   * every known action maps to a labeled (non-"other") category, unless it is
///     an explicit `intentionalOther`;
///   * every `hasTitle` action actually renders a specific title;
///   * every labeled category has ar/he/en labels;
///   * every displayable detail-field key has a localized label (not the raw key).
List<String> auditRegistryViolations(
  AppLocalizations en,
  AppLocalizations ar,
  AppLocalizations he, {
  Map<String, AuditActionSpec> registry = kAuditActionRegistry,
}) {
  final out = <String>[];
  final otherLabel = auditCategoryLabel(en, '__unknown__');
  final presenter = AuditEventPresenter(en, 'ILS');

  registry.forEach((action, spec) {
    if (!spec.intentionalOther) {
      if (spec.category == 'other') {
        out.add(
          'action "$action" is classified as "other" (known actions must not be Other)',
        );
      } else if (!kAuditLabeledCategories.contains(spec.category)) {
        out.add(
          'action "$action" declares unknown category "${spec.category}"',
        );
      } else if (auditCategoryLabel(en, spec.category) == otherLabel) {
        out.add(
          'category "${spec.category}" (for "$action") has no localized label',
        );
      }
    }
    if (spec.hasTitle) {
      final view = presenter.present(
        AuditEvent(
          eventId: 'guard',
          action: action,
          category: spec.category,
          occurredAtLabel: '',
        ),
      );
      if (!view.isKnownAction) {
        out.add(
          'action "$action" is marked hasTitle but the presenter has no specific title',
        );
      }
    }
  });

  // Every labeled category has ar/he/en labels.
  for (final category in kAuditLabeledCategories) {
    for (final (name, l10n) in [('ar', ar), ('he', he), ('en', en)]) {
      if (auditCategoryLabel(l10n, category).trim().isEmpty) {
        out.add('category "$category" has an empty $name label');
      }
    }
  }

  // Every displayable detail-field key has a real (non-raw) label in all locales.
  for (final key in auditDisplayableFieldKeys()) {
    for (final (name, l10n) in [('ar', ar), ('he', he), ('en', en)]) {
      if (auditFieldLabel(l10n, key) == key) {
        out.add(
          'detail field "$key" has no $name label (falls back to the raw key)',
        );
      }
    }
  }

  return out;
}
