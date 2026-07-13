/// The SINGLE, centralized presentation mapper for the Activity log
/// (AUDIT-LOG-DASHBOARD-001).
///
/// It converts a raw (already server-secret-scrubbed) [AuditEvent] into a
/// normalized, SAFE [AuditEventView] the UI renders. Two hard privacy rules,
/// both ALLOWLIST-based (never denylist):
///
///   1. Only fields in [_displayableKeys] (plus the two allowlisted nested
///      objects `capabilities` / `permissions`) are ever turned into a visible
///      change row. A key not on the list is silently dropped.
///   2. As belt-and-suspenders over the server redaction, [_looksSensitive]
///      rejects any key whose name resembles a secret — so even a future writer
///      that leaked a secret into a payload could not surface it here.
///
/// There is NO "show raw JSON" path: the raw maps never render directly. Unknown
/// / unmapped actions get a safe generic title + category chip (never hidden,
/// never a raw dump). Money is integer MINOR units formatted via [MoneyFormatter]
/// (D-007); nothing is recomputed.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../format/money_format.dart';
import 'audit_log_models.dart';

/// A single safe before→after field change (either side may be absent).
class AuditChange {
  const AuditChange({
    required this.label,
    required this.newValue,
    this.oldValue,
  });

  final String label;
  final String? oldValue;
  final String newValue;
}

/// The normalized, safe view of one audit event — everything the UI needs, and
/// nothing it must not show.
class AuditEventView {
  const AuditEventView({
    required this.eventId,
    required this.title,
    required this.categoryLabel,
    required this.actorLabel,
    required this.occurredAtLabel,
    required this.tone,
    required this.icon,
    required this.isDenied,
    required this.isKnownAction,
    this.scopeLabel,
    this.deviceLabel,
    this.reason,
    this.changes = const [],
  });

  final String eventId;
  final String title;
  final String categoryLabel;
  final String actorLabel;
  final String occurredAtLabel;
  final RestoflowTone tone;
  final IconData icon;
  final bool isDenied;

  /// False when the action had no specific mapping (shown generically).
  final bool isKnownAction;
  final String? scopeLabel;
  final String? deviceLabel;
  final String? reason;
  final List<AuditChange> changes;
}

/// How an allowlisted field value is formatted.
enum _Kind {
  text,
  role,
  money,
  count,
  boolean,
  paymentStatus,
  completionMode,
  completionTrigger,
  deniedReason,
}

/// The EXPLICIT allowlist of payload keys that may ever be shown, and how to
/// render each. Any key NOT here is never surfaced (privacy allowlist, §10).
const Map<String, _Kind> _displayableKeys = {
  'status': _Kind.text,
  'order_status': _Kind.text,
  'scope': _Kind.text,
  'discount_type': _Kind.text,
  'value': _Kind.text,
  'attempted_action': _Kind.text,
  'order_type': _Kind.text,
  'role': _Kind.role,
  'from_role': _Kind.role,
  'to_role': _Kind.role,
  'target_role': _Kind.role,
  'discount_total_minor': _Kind.money,
  'grand_total_minor': _Kind.money,
  'subtotal_minor': _Kind.money,
  'line_total_minor': _Kind.money,
  'line_discount_minor': _Kind.money,
  'amount_minor': _Kind.money,
  'tendered_minor': _Kind.money,
  'change_minor': _Kind.money,
  'opening_float_minor': _Kind.money,
  'expected_cash_minor': _Kind.money,
  'counted_cash_minor': _Kind.money,
  'cash_variance_minor': _Kind.money,
  'variance_minor': _Kind.money,
  'voided_item_count': _Kind.count,
  'failed_attempt_count': _Kind.count,
  'pin_set': _Kind.boolean,
  'locked': _Kind.boolean,
  // Settings/configuration (AUDIT-COVERAGE-002) — safe scalar fields only; the
  // server already drops internal ids / address / timestamps.
  'timezone': _Kind.text,
  'name': _Kind.text,
  'receipt_prefix': _Kind.text,
  // Order completion (ORDER-COMPLETION-001). `order_code` is the SAFE '#XXXXXX'
  // reference (never the order UUID); `payment_status` is a STATE (paid/unpaid),
  // not a money figure — T-003 still holds.
  'order_code': _Kind.text,
  // paid | unpaid | not_chargeable. A ZERO-TOTAL (comped) order completes with NO
  // payment row, and the server audits `not_chargeable` rather than the false literal
  // "paid" — so the VALUE is a closed enum and is localized, never shown raw.
  'payment_status': _Kind.paymentStatus,
  // Automatic completion (ORDER-AUTO-COMPLETION-001). Both are STATES describing
  // HOW an order closed — not money, not identifiers (T-003 holds). Unlike the
  // plain-text keys above, their VALUES are a closed enum, so both the label and
  // the value are localized (ar/he/en) rather than shown as a raw server token.
  'completion_mode': _Kind.completionMode, //     automatic | manual
  'completion_trigger':
      _Kind.completionTrigger, // order_served | payment_recorded
  // WHY a mutation was denied (MONEY-SETTLEMENT-CONSISTENCY-001). The denial actions have
  // always carried this, but it was never allowlisted — so the Activity Log said THAT a
  // discount was refused and never WHY. A closed enum of safe STATE tokens; never money,
  // never an identifier (T-003 holds).
  'denied_reason': _Kind.deniedReason,
};

/// The payload keys the presenter may ever render, exposed so the audit-coverage
/// guard can assert every one has a localized field label.
List<String> auditDisplayableFieldKeys() => _displayableKeys.keys.toList();

/// The localized label for a safe detail-field key. Public so the audit-coverage
/// guard can assert every displayable key has a real label (an unmapped key
/// returns the raw key, which the guard treats as a violation).
String auditFieldLabel(AppLocalizations l10n, String key) => switch (key) {
  'status' || 'order_status' => l10n.activityLogFieldStatus,
  'scope' => l10n.activityLogFieldScope,
  'discount_type' => l10n.activityLogFieldDiscountType,
  'value' => l10n.activityLogFieldValue,
  'attempted_action' => l10n.activityLogFieldAttemptedAction,
  'order_type' => l10n.activityLogFieldOrderType,
  'role' || 'target_role' => l10n.activityLogFieldRole,
  'from_role' => l10n.activityLogFieldFromRole,
  'to_role' => l10n.activityLogFieldToRole,
  'discount_total_minor' => l10n.activityLogFieldDiscountTotal,
  'grand_total_minor' => l10n.activityLogFieldOrderTotal,
  'subtotal_minor' => l10n.activityLogFieldSubtotal,
  'line_total_minor' => l10n.activityLogFieldLineTotal,
  'line_discount_minor' => l10n.activityLogFieldLineDiscount,
  'amount_minor' => l10n.activityLogFieldAmount,
  'tendered_minor' => l10n.activityLogFieldTendered,
  'change_minor' => l10n.activityLogFieldChange,
  'opening_float_minor' => l10n.activityLogFieldOpeningFloat,
  'expected_cash_minor' => l10n.activityLogFieldExpectedCash,
  'counted_cash_minor' => l10n.activityLogFieldCountedCash,
  'cash_variance_minor' || 'variance_minor' => l10n.activityLogFieldVariance,
  'voided_item_count' => l10n.activityLogFieldItemCount,
  'failed_attempt_count' => l10n.activityLogFieldFailedAttempts,
  'pin_set' => l10n.activityLogFieldPinSet,
  'locked' => l10n.activityLogFieldLocked,
  'timezone' => l10n.activityLogFieldTimezone,
  'name' => l10n.activityLogFieldName,
  'receipt_prefix' => l10n.activityLogFieldReceiptPrefix,
  'order_code' => l10n.activityLogFieldOrderCode,
  'payment_status' => l10n.activityLogFieldPaymentStatus,
  'completion_mode' => l10n.activityLogFieldCompletionMode,
  'completion_trigger' => l10n.activityLogFieldCompletionTrigger,
  'denied_reason' => l10n.activityLogFieldDeniedReason,
  _ => key,
};

/// The three cashier capability keys (nested under `capabilities`) rendered as
/// Enabled/Disabled booleans.
const List<String> _capabilityKeys = [
  'apply_discount',
  'void_order',
  'close_shift',
];

/// Substrings that mark a key as secret-bearing — a final client guard on top of
/// the server-side [app.audit_redact_values]. A matching key is never rendered.
const List<String> _sensitiveMarkers = [
  'pin',
  'password',
  'passcode',
  'secret',
  'token',
  'credential',
  'authorization',
  'api_key',
  'apikey',
  'private_key',
  'service_role',
  'enrollment',
  'otp',
  'session',
  'hash',
];

bool _looksSensitive(String key) {
  final k = key.toLowerCase();
  for (final marker in _sensitiveMarkers) {
    if (k.contains(marker)) return true;
  }
  return false;
}

/// The localized label for a server-derived category. Public so the
/// audit-coverage guard (AUDIT-COVERAGE-002) can assert every registered
/// category has a localized label; an unrecognized category falls back to
/// "Other" (safe, for genuinely unknown/legacy actions only).
String auditCategoryLabel(AppLocalizations l10n, String category) =>
    switch (category) {
      'orders' => l10n.activityLogCategoryOrders,
      'voids' => l10n.activityLogCategoryVoids,
      'discounts' => l10n.activityLogCategoryDiscounts,
      'payments' => l10n.activityLogCategoryPayments,
      'shifts' => l10n.activityLogCategoryShifts,
      'staff' => l10n.activityLogCategoryStaff,
      'access' => l10n.activityLogCategoryAccess,
      'devices' => l10n.activityLogCategoryDevices,
      'settings' => l10n.activityLogCategorySettings,
      'menu' => l10n.activityLogCategoryMenu,
      'tables' => l10n.activityLogCategoryTables,
      'organization' => l10n.activityLogCategoryOrganization,
      'sync' => l10n.activityLogCategorySync,
      _ => l10n.activityLogCategoryOther,
    };

/// The categories that have an explicit localized label (i.e. NOT the generic
/// "other" bucket). The coverage guard asserts every known action maps to one
/// of these.
const List<String> kAuditLabeledCategories = [
  'orders',
  'voids',
  'discounts',
  'payments',
  'shifts',
  'staff',
  'access',
  'devices',
  'settings',
  'menu',
  'tables',
  'organization',
  'sync',
];

/// Converts audit events into safe view models. Stateless; pure.
class AuditEventPresenter {
  const AuditEventPresenter(this.l10n, this.currencyCode);

  final AppLocalizations l10n;
  final String currencyCode;

  AuditEventView present(AuditEvent e) {
    final (tone, icon) = _toneIcon(e);
    final mapped = _title(e);
    return AuditEventView(
      eventId: e.eventId,
      title: mapped ?? _categoryLabel(e.category),
      categoryLabel: _categoryLabel(e.category),
      actorLabel: e.actorName?.trim().isNotEmpty == true
          ? e.actorName!.trim()
          : l10n.activityLogActorUnknown,
      occurredAtLabel: e.occurredAtLabel,
      tone: tone,
      icon: icon,
      isDenied: e.isDenied,
      isKnownAction: mapped != null,
      scopeLabel: _scopeLabel(e),
      deviceLabel: e.deviceLabel,
      reason: e.reason?.trim().isNotEmpty == true ? e.reason!.trim() : null,
      changes: _changes(e),
    );
  }

  /// The localized scope line ("Restaurant · Branch"), or whichever is present.
  String? _scopeLabel(AuditEvent e) {
    final parts = <String>[
      if (e.restaurantName?.trim().isNotEmpty == true) e.restaurantName!.trim(),
      if (e.branchName?.trim().isNotEmpty == true) e.branchName!.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// The localized category label (delegates to the public helper so the
  /// audit-coverage guard can verify every category has a label).
  String _categoryLabel(String category) => auditCategoryLabel(l10n, category);

  /// A specific localized title for the known operational actions; null when the
  /// action is unmapped (the caller falls back to the category label).
  String? _title(AuditEvent e) => switch (e.action) {
    'order.voided' => l10n.activityLogTitleOrderVoided,
    'order.discount_applied' => l10n.activityLogTitleDiscountApplied,
    'order.submitted' => l10n.activityLogTitleOrderSubmitted,
    'order.status_updated' => l10n.activityLogTitleOrderStatusUpdated,
    'staff.created' => l10n.activityLogTitleStaffCreated,
    'staff.capabilities_updated' => l10n.activityLogTitleStaffCapabilities,
    'staff.pin_set' => l10n.activityLogTitleStaffPinSet,
    'membership.granted' => l10n.activityLogTitleMembershipGranted,
    'membership.revoked' => l10n.activityLogTitleMembershipRevoked,
    'membership.role_updated' => l10n.activityLogTitleRoleUpdated,
    'shift.opened' => l10n.activityLogTitleShiftOpened,
    'shift.closed' => l10n.activityLogTitleShiftClosed,
    'shift.reconciled' => l10n.activityLogTitleShiftReconciled,
    'device.created' => l10n.activityLogTitleDeviceAdded,
    'device.revoked' ||
    'device.revoked_management' => l10n.activityLogTitleDeviceRevoked,
    'device.session_started' => l10n.activityLogTitleDeviceSignedIn,
    'employee.revoked' => l10n.activityLogTitleEmployeeRevoked,
    'payment.recorded' => l10n.activityLogTitlePaymentRecorded,
    'organization.created' => l10n.activityLogTitleOrganizationCreated,
    'settings.branch.updated' => l10n.activityLogTitleBranchSettings,
    'settings.restaurant.updated' => l10n.activityLogTitleRestaurantSettings,
    'settings.organization.updated' =>
      l10n.activityLogTitleOrganizationSettings,
    _ => null,
  };

  /// The tone + icon, driven by category and denial. Denials read as a warning
  /// regardless of category; voids/revocations read as danger.
  (RestoflowTone, IconData) _toneIcon(AuditEvent e) {
    if (e.isDenied) return (RestoflowTone.warning, Icons.block_outlined);
    return switch (e.category) {
      'voids' => (RestoflowTone.danger, Icons.remove_circle_outline),
      'discounts' => (RestoflowTone.info, Icons.percent_outlined),
      'payments' => (RestoflowTone.success, Icons.payments_outlined),
      'shifts' => (RestoflowTone.info, Icons.point_of_sale_outlined),
      'staff' => (RestoflowTone.info, Icons.badge_outlined),
      'access' => (RestoflowTone.warning, Icons.key_outlined),
      'devices' => (RestoflowTone.info, Icons.devices_outlined),
      'settings' => (RestoflowTone.info, Icons.tune_outlined),
      'menu' => (RestoflowTone.neutral, Icons.restaurant_menu_outlined),
      'tables' => (RestoflowTone.neutral, Icons.table_restaurant_outlined),
      'organization' => (RestoflowTone.neutral, Icons.apartment_outlined),
      'orders' => (RestoflowTone.neutral, Icons.receipt_long_outlined),
      _ => (RestoflowTone.neutral, Icons.history_outlined),
    };
  }

  /// The safe old→new change rows, built ONLY from allowlisted keys (plus the
  /// two allowlisted nested objects). Never emits a sensitive-looking key.
  List<AuditChange> _changes(AuditEvent e) {
    final out = <AuditChange>[];
    // The union of keys present in either side, in a stable order (new first).
    final keys = <String>{...e.newValues.keys, ...e.oldValues.keys};
    for (final key in keys) {
      if (_looksSensitive(key)) continue;
      // Allowlisted nested capability/permission objects.
      if (key == 'capabilities') {
        out.addAll(_capabilities(e));
        continue;
      }
      final kind = _displayableKeys[key];
      if (kind == null) continue;
      final oldV = _format(kind, e.oldValues[key]);
      final newV = _format(kind, e.newValues[key]);
      if (newV == null && oldV == null) continue;
      out.add(
        AuditChange(
          label: _fieldLabel(key),
          oldValue: oldV,
          newValue: newV ?? oldV!,
        ),
      );
    }
    return out;
  }

  /// The three cashier capabilities as Enabled/Disabled rows (old→new).
  List<AuditChange> _capabilities(AuditEvent e) {
    final newCaps = e.newValues['capabilities'];
    final oldCaps = e.oldValues['capabilities'];
    if (newCaps is! Map && oldCaps is! Map) return const [];
    final out = <AuditChange>[];
    for (final cap in _capabilityKeys) {
      final n = (newCaps is Map) ? newCaps[cap] : null;
      final o = (oldCaps is Map) ? oldCaps[cap] : null;
      if (n == null && o == null) continue;
      out.add(
        AuditChange(
          label: _capabilityLabel(cap),
          oldValue: o == null ? null : _bool(o),
          newValue: _bool(n ?? o),
        ),
      );
    }
    return out;
  }

  String? _format(_Kind kind, Object? value) {
    if (value == null) return null;
    return switch (kind) {
      _Kind.money => MoneyFormatter.formatMinor(_int(value), currencyCode),
      _Kind.count => _int(value).toString(),
      _Kind.boolean => _bool(value),
      _Kind.role => _roleLabel(value.toString()),
      _Kind.paymentStatus => _paymentStatusLabel(value.toString()),
      _Kind.completionMode => _completionModeLabel(value.toString()),
      _Kind.completionTrigger => _completionTriggerLabel(value.toString()),
      _Kind.deniedReason => _deniedReasonLabel(value.toString()),
      _Kind.text => value.toString(),
    };
  }

  /// WHY a mutation was refused. An unknown token is shown raw rather than guessed —
  /// an honest unknown beats a confident mislabel.
  String _deniedReasonLabel(String reason) => switch (reason) {
    'order_has_completed_payment' => l10n.activityLogDeniedOrderHasPayment,
    'full_comp_requires_manager' =>
      l10n.activityLogDeniedFullCompRequiresManager,
    _ => reason,
  };

  /// Whether the order owed anything, and whether it was settled. `not_chargeable`
  /// is a ZERO-TOTAL (comped) order: it closed without a payment because there was
  /// nothing to pay — reporting that as "Paid" would be a lie.
  String _paymentStatusLabel(String status) => switch (status) {
    'paid' => l10n.dashboardPaid,
    'unpaid' => l10n.dashboardUnpaid,
    'not_chargeable' => l10n.activityLogPaymentNotChargeable,
    _ => status,
  };

  /// HOW the order closed. An unknown value falls back to the raw token rather
  /// than guessing — an honest unknown beats a confident mislabel.
  String _completionModeLabel(String mode) => switch (mode) {
    'automatic' => l10n.activityLogCompletionModeAutomatic,
    'manual' => l10n.activityLogCompletionModeManual,
    _ => mode,
  };

  /// WHICH event closed it (automatic completions only).
  String _completionTriggerLabel(String trigger) => switch (trigger) {
    'order_served' => l10n.activityLogCompletionTriggerOrderServed,
    'payment_recorded' => l10n.activityLogCompletionTriggerPaymentRecorded,
    _ => trigger,
  };

  String _bool(Object? value) {
    final v = value is bool ? value : value.toString() == 'true';
    return v ? l10n.activityLogEnabled : l10n.activityLogDisabled;
  }

  String _roleLabel(String role) => switch (role) {
    'org_owner' => l10n.authRoleOwner,
    'restaurant_owner' => l10n.authRoleRestaurantOwner,
    'manager' => l10n.authRoleManager,
    'cashier' => l10n.authRoleCashier,
    'kitchen_staff' => l10n.authRoleKitchenStaff,
    'accountant' => l10n.authRoleAccountant,
    _ => role,
  };

  String _fieldLabel(String key) => auditFieldLabel(l10n, key);

  String _capabilityLabel(String cap) => switch (cap) {
    'apply_discount' => l10n.activityLogCapApplyDiscount,
    'void_order' => l10n.activityLogCapVoidOrder,
    'close_shift' => l10n.activityLogCapCloseShift,
    _ => cap,
  };

  static int _int(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
}
