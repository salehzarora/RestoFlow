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
  chargeState,
  availability,
  availabilityReason,
  kitchenChannel,
  reasonCode,
  // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: the card_attempt.* closed enums.
  cardState,
  cardMode,
  cardRefusal,
  cardAnomaly,
  cardConfirmation,
  cardResumeOutcome,
  cardDeniedReason,
  yesNo,
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
  // order_served | payment_recorded | order_edited (ORDER-EDIT-001A)
  'completion_trigger': _Kind.completionTrigger,
  // WHY a mutation was denied (MONEY-SETTLEMENT-CONSISTENCY-001). The denial actions have
  // always carried this, but it was never allowlisted — so the Activity Log said THAT a
  // discount was refused and never WHY. A closed enum of safe STATE tokens; never money,
  // never an identifier (T-003 holds).
  'denied_reason': _Kind.deniedReason,
  // WHAT the mutation would have left the order as (FULL-COMP-PERMISSION-001).
  // A closed enum of STATE tokens (currently `not_chargeable`), so both the label
  // and the value are localized — never money, never an identifier (T-003 holds).
  'resulting_charge_state': _Kind.chargeState,
  // RESTAURANT-OPERATIONS-V1-001: branch menu availability (closed enums —
  // both label AND value localized) + the item's display name, and the
  // table-move floor labels (safe display text, already printed on tickets).
  'availability': _Kind.availability,
  'availability_reason': _Kind.availabilityReason,
  'item_name': _Kind.text,
  'table_label': _Kind.text,
  'from_table_label': _Kind.text,
  'to_table_label': _Kind.text,
  // PILOT-OPERATIONS-CORRECTIONS-001 (B4): the operational table payload's safe
  // scalar keys (app.audit_safe_detail): the manual floor-status before/after and the
  // combined linked-group label ("T4 + T5"). Safe display text — never money, never an
  // identifier (T-003 holds).
  'from_status': _Kind.text,
  'to_status': _Kind.text,
  'group_label': _Kind.text,
  // PSC-001D: the kitchen cancellation acknowledgement's safe scalars — the
  // order's pre-void status (closed enum), the acknowledging device class
  // (closed pos|kds enum) and whether acknowledgement was required (boolean).
  // Never money, never identifiers (T-003 holds).
  'voided_from_status': _Kind.text,
  'device_type': _Kind.text,
  'kitchen_ack_required': _Kind.boolean,
  // POS-CASH-DRAWER-MANUAL-OPEN-001: a manual drawer open made while the till
  // was offline, recorded when it reconnected (boolean, never an identifier).
  'recorded_offline': _Kind.boolean,
  // PSC-001C: service rounds — a position in the order and a line count.
  // Never money, never identifiers (T-003 holds).
  'round_number': _Kind.count,
  'added_item_count': _Kind.count,
  // ORDER-EDIT-001A: editing a sent order + the kitchen acknowledgement + the
  // branch order-edit settings. Positions/line counts, two closed enums (both
  // label AND value localized) and two setting booleans — never identifiers
  // (T-003 holds). The edit's money (subtotal / discount / grand total
  // before→after) reuses the existing *_minor keys above.
  'edit_number': _Kind.count,
  'kitchen_channel': _Kind.kitchenChannel, // kds | paper
  'reason_code': _Kind.reasonCode,
  'removed_item_count': _Kind.count,
  'modified_item_count': _Kind.count,
  'up_to_edit_number': _Kind.count,
  'acknowledged_count': _Kind.count,
  'order_edit_enabled': _Kind.boolean,
  'order_edit_finished_food_manager_only': _Kind.boolean,
  // KITCHEN-MODE-001B: printer configuration safe scalars. display_name is
  // tenant display text (the item_name/table_label class); the rest are closed
  // enums/booleans. connection_config (host/port/addresses) is NOT listed and
  // is a nested object server-side — endpoints never render here.
  'display_name': _Kind.text,
  'paper_width': _Kind.text,
  'is_enabled': _Kind.boolean,
  'connection_type': _Kind.text,
};

/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D (API §4.33): the card_attempt.* family
/// renders ONLY the keys `app.audit_safe_detail` projects for each action, in
/// this order, from the new values — never the global allowlist above, never
/// old values and never the free-text reason. A hostile or legacy payload can
/// therefore not surface a provider / terminal / credential reference, an
/// approval or voucher number, an internal identifier or money on any action
/// but `.started`. An unregistered card_attempt.* action renders no rows.
const Map<String, List<String>> _cardAttemptKeys = {
  'card_attempt.started': [
    'attempt_state',
    'mode',
    'amount_minor',
    'currency_code',
  ],
  'card_attempt.approved': _cardResultKeys,
  'card_attempt.declined': _cardResultKeys,
  'card_attempt.unknown': _cardResultKeys,
  'card_attempt.released': _cardResultKeys,
  'card_attempt.provider_anomaly': _cardResultKeys,
  'card_attempt.release_requested': ['attempt_state'],
  'card_attempt.release_failed': ['attempt_state'],
  'card_attempt.recording_refused': ['refusal_code'],
  'card_attempt.order_freed': ['attempt_state', 'confirmation_source'],
  'card_attempt.recording_resume_requested': [
    'attempt_state',
    'prior_refusal_code',
    'resume_count',
    'outcome',
    'denied_reason',
  ],
  'card_attempt.denied': ['denied_reason'],
};

/// The four keys of a provider-result row (approved / declined / unknown /
/// released / provider_anomaly).
const List<String> _cardResultKeys = [
  'attempt_state',
  'refusal_code',
  'anomaly_code',
  'release_requested',
];

/// The provider-result actions. On them the server's only `refusal_code` is
/// `release_failed` — a terminal release fact, never a recording refusal —
/// so it is labelled as the release status there.
const Set<String> _cardResultActions = {
  'card_attempt.approved',
  'card_attempt.declined',
  'card_attempt.unknown',
  'card_attempt.released',
  'card_attempt.provider_anomaly',
};

/// How each card_attempt.* key renders. Closed enums are localized; an unknown
/// token of a projected key shows raw — an honest unknown beats a confident
/// mislabel. `currency_code` is shown as its ISO code.
const Map<String, _Kind> _cardFieldKinds = {
  'attempt_state': _Kind.cardState,
  'mode': _Kind.cardMode,
  'amount_minor': _Kind.money,
  'currency_code': _Kind.text,
  'refusal_code': _Kind.cardRefusal,
  'prior_refusal_code': _Kind.cardRefusal,
  'anomaly_code': _Kind.cardAnomaly,
  'release_requested': _Kind.yesNo,
  'confirmation_source': _Kind.cardConfirmation,
  'resume_count': _Kind.count,
  'outcome': _Kind.cardResumeOutcome,
  'denied_reason': _Kind.cardDeniedReason,
};

/// The payload keys the presenter may ever render (the global allowlist plus
/// the card_attempt.* keys), exposed so the audit-coverage guard can assert
/// every one has a localized field label.
List<String> auditDisplayableFieldKeys() =>
    {..._displayableKeys.keys, ..._cardFieldKinds.keys}.toList();

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
  'resulting_charge_state' => l10n.activityLogFieldResultingChargeState,
  'availability' => l10n.activityLogFieldAvailability,
  'availability_reason' => l10n.activityLogFieldAvailabilityReason,
  'item_name' => l10n.activityLogFieldItemName,
  'table_label' => l10n.activityLogFieldTableLabel,
  'from_table_label' => l10n.activityLogFieldFromTable,
  'to_table_label' => l10n.activityLogFieldToTable,
  'from_status' => l10n.activityLogFieldFromStatus,
  'to_status' => l10n.activityLogFieldToStatus,
  'group_label' => l10n.activityLogFieldGroupLabel,
  'voided_from_status' => l10n.activityLogFieldVoidedFromStatus,
  'device_type' => l10n.activityLogFieldDeviceType,
  'kitchen_ack_required' => l10n.activityLogFieldKitchenAckRequired,
  'recorded_offline' => l10n.activityLogFieldRecordedOffline,
  // PSC-001C: service-round safe scalars.
  'round_number' => l10n.activityLogFieldRoundNumber,
  'added_item_count' => l10n.activityLogFieldAddedItemCount,
  // ORDER-EDIT-001A: order-edit / acknowledgement / settings safe scalars.
  'edit_number' => l10n.activityLogFieldEditNumber,
  'kitchen_channel' => l10n.activityLogFieldKitchenChannel,
  'reason_code' => l10n.activityLogFieldReasonCode,
  'removed_item_count' => l10n.activityLogFieldRemovedItemCount,
  'modified_item_count' => l10n.activityLogFieldModifiedItemCount,
  'up_to_edit_number' => l10n.activityLogFieldUpToEditNumber,
  'acknowledged_count' => l10n.activityLogFieldAcknowledgedCount,
  'order_edit_enabled' => l10n.activityLogFieldOrderEditEnabled,
  'order_edit_finished_food_manager_only' =>
    l10n.activityLogFieldOrderEditFinishedFoodManagerOnly,
  // KITCHEN-MODE-001B: printer configuration safe scalars.
  'display_name' => l10n.activityLogFieldName,
  'paper_width' => l10n.activityLogFieldPaperWidth,
  'is_enabled' => l10n.activityLogFieldEnabled,
  'connection_type' => l10n.activityLogFieldConnectionType,
  // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: card_attempt.* safe scalars
  // (amount_minor and denied_reason reuse the labels above).
  'attempt_state' => l10n.activityLogFieldCardState,
  'mode' => l10n.activityLogFieldCardMode,
  'currency_code' => l10n.activityLogFieldCurrency,
  'refusal_code' => l10n.activityLogFieldCardRefusal,
  'prior_refusal_code' => l10n.activityLogFieldCardPriorRefusal,
  'anomaly_code' => l10n.activityLogFieldCardAnomaly,
  'release_requested' => l10n.activityLogFieldCardReleaseRequested,
  'confirmation_source' => l10n.activityLogFieldCardConfirmationSource,
  'resume_count' => l10n.activityLogFieldCardResumeCount,
  'outcome' => l10n.activityLogFieldCardResumeOutcome,
  _ => key,
};

/// The cashier capability keys (nested under `capabilities`) rendered as
/// Enabled/Disabled booleans. `apply_full_comp` (FULL-COMP-PERMISSION-001) is
/// default-OFF and grant-only, but it renders exactly like the others — the
/// polarity lives in the server resolver and in [StaffCapabilities.fromJson],
/// not here: this list only decides WHAT is shown, not what it means.
const List<String> _capabilityKeys = [
  'apply_discount',
  'void_order',
  'close_shift',
  'apply_full_comp',
  // POS-CASH-DRAWER-MANUAL-OPEN-001: the grant-only manual drawer permission.
  'open_cash_drawer',
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
    // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: the card_attempt.* family shows no
    // free-text reason (its writer stores none) and only its projected keys.
    final card = _isCardAttempt(e);
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
      // The shared model matches `_denied` suffixes only; the card family's
      // refusal is `card_attempt.denied` (a presenter-scoped Denied pill).
      isDenied: e.isDenied || e.action == 'card_attempt.denied',
      isKnownAction: mapped != null,
      scopeLabel: _scopeLabel(e),
      deviceLabel: e.deviceLabel,
      reason: !card && e.reason?.trim().isNotEmpty == true
          ? e.reason!.trim()
          : null,
      changes: card ? _cardChanges(e) : _changes(e),
    );
  }

  static bool _isCardAttempt(AuditEvent e) =>
      e.action.startsWith('card_attempt.');

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
    // PSC-001D: the kitchen's cancellation acknowledgement — success AND
    // denial get specific titles (never a bare category fallback).
    'order.void_acknowledged' => l10n.activityLogTitleVoidAcknowledged,
    'order.void_ack_denied' => l10n.activityLogTitleVoidAckDenied,
    // PSC-001C: service-round additions + their kitchen lifecycle.
    'order.items_added' => l10n.activityLogTitleItemsAdded,
    'order.items_add_denied' => l10n.activityLogTitleItemsAddDenied,
    'order.round_status_updated' => l10n.activityLogTitleRoundStatusUpdated,
    'order.round_status_denied' => l10n.activityLogTitleRoundStatusDenied,
    // ORDER-EDIT-001A: editing a sent order + the kitchen acknowledgement —
    // success AND denial get specific titles (never a bare category fallback).
    'order.edited' => l10n.activityLogTitleOrderEdited,
    'order.edit_denied' => l10n.activityLogTitleOrderEditDenied,
    'order.edit_acknowledged' => l10n.activityLogTitleOrderEditAcknowledged,
    'order.edit_ack_denied' => l10n.activityLogTitleOrderEditAckDenied,
    'order.discount_applied' => l10n.activityLogTitleDiscountApplied,
    // FULL-COMP-PERMISSION-001: a REFUSED discount had no title of its own, so it
    // fell back to the bare category label — the operator saw "Discounts" and had
    // to infer that something had been blocked. A refusal is exactly the row a
    // manager needs to notice, so it now says so.
    'order.discount_denied' => l10n.activityLogTitleDiscountDenied,
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
    // ORDER-EDIT-001A: the branch order-editing settings.
    'settings.branch.order_edit_updated' =>
      l10n.activityLogTitleOrderEditSettingsUpdated,
    'settings.restaurant.updated' => l10n.activityLogTitleRestaurantSettings,
    'settings.organization.updated' =>
      l10n.activityLogTitleOrganizationSettings,
    // RESTAURANT-OPERATIONS-V1-001: branch availability + table moves.
    'menu.menu_item.availability_changed' =>
      l10n.activityLogTitleMenuAvailabilityChanged,
    'menu.menu_item.availability_denied' =>
      l10n.activityLogTitleMenuAvailabilityDenied,
    'order.table_moved' => l10n.activityLogTitleOrderTableMoved,
    'order.table_move_denied' => l10n.activityLogTitleOrderTableMoveDenied,
    // PILOT-OPERATIONS-CORRECTIONS-001 (B4): POS operational table actions.
    'table.status_set' => l10n.activityLogTitleTableStatusChanged,
    'table.status_denied' => l10n.activityLogTitleTableStatusDenied,
    'table.tables_linked' => l10n.activityLogTitleTablesLinked,
    'table.link_denied' => l10n.activityLogTitleTableLinkDenied,
    'table.tables_unlinked' => l10n.activityLogTitleTablesUnlinked,
    'table.unlink_denied' => l10n.activityLogTitleTableUnlinkDenied,
    // POS-CASH-DRAWER-MANUAL-OPEN-001: manual cash-drawer opens.
    'cash_drawer.no_sale_opened' => l10n.activityLogTitleDrawerNoSaleOpened,
    'cash_drawer.no_sale_denied' => l10n.activityLogTitleDrawerNoSaleDenied,
    'cash_drawer.unlock_failed' => l10n.activityLogTitleDrawerUnlockFailed,
    // KITCHEN-MODE-001B: printer configuration (settings category; the former
    // intentional-'other' deferral is resolved).
    'printer.printer_device.created' => l10n.activityLogTitlePrinterCreated,
    'printer.printer_device.updated' => l10n.activityLogTitlePrinterUpdated,
    'printer.printer_device.deleted' => l10n.activityLogTitlePrinterDeleted,
    'printer.printer_route.updated' => l10n.activityLogTitlePrinterRouteUpdated,
    // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D (API §4.33): LIVE card attempts. The
    // titles describe the PROVIDER's result — on finish rows the actor is the
    // attempt's frozen initiating employee, who approved or declined nothing.
    'card_attempt.started' => l10n.activityLogTitleCardAttemptStarted,
    'card_attempt.approved' => l10n.activityLogTitleCardAttemptApproved,
    'card_attempt.declined' => l10n.activityLogTitleCardAttemptDeclined,
    'card_attempt.unknown' => l10n.activityLogTitleCardAttemptUnknown,
    'card_attempt.released' => l10n.activityLogTitleCardAttemptReleased,
    'card_attempt.provider_anomaly' => _cardAnomalyTitle(e),
    'card_attempt.release_requested' =>
      l10n.activityLogTitleCardAttemptReleaseRequested,
    'card_attempt.release_failed' =>
      l10n.activityLogTitleCardAttemptReleaseFailed,
    'card_attempt.recording_refused' =>
      l10n.activityLogTitleCardAttemptRecordingRefused,
    'card_attempt.order_freed' => l10n.activityLogTitleCardAttemptOrderFreed,
    'card_attempt.recording_resume_requested' =>
      l10n.activityLogTitleCardAttemptResumeRequested,
    'card_attempt.denied' => l10n.activityLogTitleCardAttemptDenied,
    _ => null,
  };

  /// The same `card_attempt.provider_anomaly` action is written when an
  /// anomaly is RAISED (the attempt is unknown / released and a charge may
  /// exist) and when an exact provider answer CLEARS it (approved / declined),
  /// so its title follows the projected attempt_state, not one static label.
  String _cardAnomalyTitle(
    AuditEvent e,
  ) => switch (e.newValues['attempt_state']) {
    'unknown' || 'released' => l10n.activityLogTitleCardAttemptAnomalyRaised,
    'approved' || 'declined' => l10n.activityLogTitleCardAttemptAnomalyCleared,
    _ => l10n.activityLogTitleCardAttemptAnomaly,
  };

  /// The tone + icon, driven by category and denial. Denials read as a warning
  /// regardless of category; voids/revocations read as danger.
  (RestoflowTone, IconData) _toneIcon(AuditEvent e) {
    if (_isCardAttempt(e)) return _cardToneIcon(e);
    if (e.isDenied) return (RestoflowTone.warning, Icons.block_outlined);
    // POS-CASH-DRAWER-MANUAL-OPEN-001: a wrong PIN on the drawer unlock counts
    // toward the shared sign-in lockout, so it reads as a warning, not routine.
    if (e.action == 'cash_drawer.unlock_failed') {
      return (RestoflowTone.warning, Icons.lock_outline);
    }
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

  /// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: the card family's tone follows its
  /// operational meaning — only a provider approval reads as success; a
  /// decline, an UNKNOWN result, a possible charge, a refusal or a denial
  /// never does.
  (RestoflowTone, IconData) _cardToneIcon(AuditEvent e) => switch (e.action) {
    'card_attempt.approved' => (
      RestoflowTone.success,
      Icons.credit_card_outlined,
    ),
    'card_attempt.declined' => (
      RestoflowTone.neutral,
      Icons.credit_card_off_outlined,
    ),
    'card_attempt.unknown' => (RestoflowTone.warning, Icons.help_outline),
    'card_attempt.provider_anomaly' => switch (e.newValues['attempt_state']) {
      'unknown' ||
      'released' => (RestoflowTone.danger, Icons.report_problem_outlined),
      'approved' ||
      'declined' => (RestoflowTone.info, Icons.credit_card_outlined),
      _ => (RestoflowTone.warning, Icons.report_problem_outlined),
    },
    'card_attempt.release_failed' || 'card_attempt.recording_refused' => (
      RestoflowTone.warning,
      Icons.report_problem_outlined,
    ),
    'card_attempt.order_freed' => (
      RestoflowTone.warning,
      Icons.lock_open_outlined,
    ),
    'card_attempt.recording_resume_requested' =>
      e.newValues['outcome'] == 'dispatched'
          ? (RestoflowTone.info, Icons.replay_outlined)
          : (RestoflowTone.warning, Icons.replay_outlined),
    'card_attempt.denied' => (RestoflowTone.warning, Icons.block_outlined),
    // started, released and release_requested (and an unregistered action).
    _ => (RestoflowTone.info, Icons.credit_card_outlined),
  };

  /// The safe old→new change rows, built ONLY from allowlisted keys (plus the
  /// two allowlisted nested objects). Never emits a sensitive-looking key.
  List<AuditChange> _changes(AuditEvent e) {
    final out = <AuditChange>[];
    // PSC-001C correction (Finding 6): the four service-round actions are
    // MONEY-FREE by approved contract. Even a HOSTILE / manually inserted
    // payload must never render a money value for them — the exclusion is
    // ACTION-SPECIFIC, so approved money-carrying actions (payments,
    // discounts, shifts, order.submitted, completion) keep their rows.
    final moneyFree =
        e.action.startsWith('order.items_add') ||
        e.action.startsWith('order.round_status') ||
        // KITCHEN-MODE-001B: printer configuration is MONEY-FREE by contract —
        // mirror the server-side hostile-key hardening client-side too.
        e.action.startsWith('printer.');
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
      if (moneyFree && kind == _Kind.money) continue;
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

  /// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: the card_attempt.* change rows — ONLY
  /// this action's projected keys ([_cardAttemptKeys]), from the NEW values,
  /// scalars only. `amount_minor` (projected on `.started` only) and
  /// `resume_count` must be integers (D-007 money is integer minor units); the
  /// amount renders in the row's own ISO currency when well formed, else in
  /// the page currency.
  List<AuditChange> _cardChanges(AuditEvent e) {
    final out = <AuditChange>[];
    for (final key in _cardAttemptKeys[e.action] ?? const <String>[]) {
      final value = e.newValues[key];
      if (value == null || value is Map || value is List) continue;
      final kind = _cardFieldKinds[key]!;
      if ((kind == _Kind.money || kind == _Kind.count) && value is! int) {
        continue;
      }
      final text = kind == _Kind.money
          ? MoneyFormatter.formatMinor(value as int, _cardCurrency(e))
          : _format(kind, value);
      if (text == null) continue;
      out.add(
        AuditChange(
          label: _cardFieldLabel(e.action, key, value),
          newValue: text,
        ),
      );
    }
    return out;
  }

  /// The field label of a card key. `refusal_code` on a provider-result row
  /// ([_cardResultActions]) and a `prior_refusal_code` of `release_failed` are
  /// release facts, never recording refusals, so they read as the release
  /// status.
  String _cardFieldLabel(String action, String key, Object value) =>
      (key == 'refusal_code' && _cardResultActions.contains(action)) ||
          (key == 'prior_refusal_code' && value == 'release_failed')
      ? l10n.activityLogFieldCardReleaseStatus
      : _fieldLabel(key);

  /// The row's own ISO-4217 code when well formed, else the page currency.
  String _cardCurrency(AuditEvent e) {
    final code = e.newValues['currency_code'];
    return code is String && RegExp(r'^[A-Z]{3}$').hasMatch(code)
        ? code
        : currencyCode;
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
      _Kind.chargeState => _chargeStateLabel(value.toString()),
      _Kind.availability => _availabilityLabel(value.toString()),
      _Kind.availabilityReason => _availabilityReasonLabel(value.toString()),
      _Kind.kitchenChannel => _kitchenChannelLabel(value.toString()),
      _Kind.reasonCode => _reasonCodeLabel(value.toString()),
      _Kind.cardState => _cardStateLabel(value.toString()),
      _Kind.cardMode => _cardModeLabel(value.toString()),
      _Kind.cardRefusal => _cardRefusalLabel(value.toString()),
      _Kind.cardAnomaly => _cardAnomalyLabel(value.toString()),
      _Kind.cardConfirmation => _cardConfirmationLabel(value.toString()),
      _Kind.cardResumeOutcome => _cardResumeOutcomeLabel(value.toString()),
      _Kind.cardDeniedReason => _cardDeniedReasonLabel(value.toString()),
      _Kind.yesNo => _yesNo(value),
      _Kind.text => value.toString(),
    };
  }

  /// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: the card attempt's state (closed
  /// enum); an unknown token shows raw.
  String _cardStateLabel(String state) => switch (state) {
    'sent' => l10n.activityLogCardStateSent,
    'approved' => l10n.activityLogCardStateApproved,
    'declined' => l10n.activityLogCardStateDeclined,
    'unknown' => l10n.activityLogCardStateUnknown,
    'released' => l10n.activityLogCardStateReleased,
    _ => state,
  };

  /// LIVE or TEST (only LIVE attempts reach the Activity log).
  String _cardModeLabel(String mode) => switch (mode) {
    'live' => l10n.activityLogCardModeLive,
    'test' => l10n.activityLogCardModeTest,
    _ => mode,
  };

  /// The recording refusal of an approved card payment (closed enum). The
  /// tokens it shares with a denial reason reuse that label; permission_denied
  /// is `app.record_payment`'s role refusal and keeps the shared role label.
  String _cardRefusalLabel(String code) => switch (code) {
    'release_failed' => l10n.activityLogCardRefusalReleaseFailed,
    'order_not_chargeable' => l10n.activityLogDeniedOrderNotChargeable,
    'conflict' => l10n.activityLogCardRefusalConflict,
    'precondition_failed' => l10n.activityLogCardRefusalPreconditionFailed,
    'revoked_employee' => l10n.activityLogCardRefusalRevokedEmployee,
    'permission_denied' => l10n.activityLogDeniedPermission,
    'revoked_device' => l10n.activityLogCardRefusalRevokedDevice,
    'amount_mismatch' => l10n.activityLogDeniedAmountMismatch,
    'payment_in_progress' => l10n.activityLogCardRefusalPaymentInProgress,
    'card_context_lost' => l10n.activityLogDeniedContextLost,
    'provider_recording_refused' =>
      l10n.activityLogCardRefusalProviderRecordingRefused,
    'nonrecoverable_refusal' => l10n.activityLogCardRefusalNonrecoverable,
    _ => code,
  };

  /// The provider anomaly of a card attempt (closed enum).
  String _cardAnomalyLabel(String code) => switch (code) {
    'amount_mismatch' => l10n.activityLogCardAnomalyAmountMismatch,
    'currency_mismatch' => l10n.activityLogCardAnomalyCurrencyMismatch,
    'preauthorization' => l10n.activityLogCardAnomalyPreauthorization,
    'partial_refund' => l10n.activityLogCardAnomalyPartialRefund,
    'refunded' => l10n.activityLogCardAnomalyRefunded,
    'voided' => l10n.activityLogCardAnomalyVoided,
    'out_of_contract' => l10n.activityLogCardAnomalyOutOfContract,
    _ => code,
  };

  /// Where a manager confirmed that no charge stands (closed enum).
  String _cardConfirmationLabel(String source) => switch (source) {
    'provider_report' => l10n.activityLogCardConfirmationProviderReport,
    'provider_back_office' => l10n.activityLogCardConfirmationBackOffice,
    _ => source,
  };

  /// Whether a recording retry was sent or refused (closed enum).
  String _cardResumeOutcomeLabel(String outcome) => switch (outcome) {
    'dispatched' => l10n.activityLogCardResumeDispatched,
    'refused' => l10n.activityLogCardResumeRefused,
    _ => outcome,
  };

  /// A card denial reason: on `card_attempt.denied`, `permission_denied`
  /// covers both a non-POS device and a role not allowed to take card
  /// payments (the card proof answers one token for both), so it has the card
  /// family's own label; every other token keeps the shared denial label.
  String _cardDeniedReasonLabel(String reason) => reason == 'permission_denied'
      ? l10n.activityLogDeniedCardPermission
      : _deniedReasonLabel(reason);

  /// A yes / no flag (release_requested); anything but a boolean shows raw.
  String _yesNo(Object value) => switch (value) {
    true || 'true' => l10n.activityLogYes,
    false || 'false' => l10n.activityLogNo,
    _ => value.toString(),
  };

  /// ORDER-EDIT-001A: HOW the kitchen learned of an order edit — a closed
  /// enum; an unknown token shows raw rather than guessed.
  String _kitchenChannelLabel(String channel) => switch (channel) {
    'kds' => l10n.activityLogKitchenChannelKds,
    'paper' => l10n.activityLogKitchenChannelPaper,
    _ => channel,
  };

  /// ORDER-EDIT-001A: the structured reason picked for an order edit (closed
  /// enum). An unknown token falls back to the raw token — an honest unknown
  /// beats a confident mislabel.
  String _reasonCodeLabel(String code) => switch (code) {
    'customer_changed_mind' => l10n.activityLogEditReasonCustomerChangedMind,
    'entry_mistake' => l10n.activityLogEditReasonEntryMistake,
    'item_unavailable' => l10n.activityLogEditReasonItemUnavailable,
    'kitchen_issue' => l10n.activityLogEditReasonKitchenIssue,
    'other' => l10n.activityLogEditReasonOther,
    _ => code,
  };

  /// Branch menu availability — a closed enum; an unknown token shows raw.
  String _availabilityLabel(String value) => switch (value) {
    'available' => l10n.menuAvailabilityAvailable,
    'unavailable' => l10n.menuAvailabilityUnavailable,
    _ => value,
  };

  /// The structured availability reason (sold_out | paused).
  String _availabilityReasonLabel(String value) => switch (value) {
    'sold_out' => l10n.menuAvailabilitySoldOut,
    'paused' => l10n.menuAvailabilityPaused,
    _ => value,
  };

  /// WHY a mutation was refused. An unknown token is shown raw rather than guessed —
  /// an honest unknown beats a confident mislabel.
  ///
  /// `full_comp_requires_manager` is the token the server emitted BEFORE
  /// FULL-COMP-PERMISSION-001, when the right was role-only. The audit trail is
  /// APPEND-ONLY, so those historical rows still exist and must keep rendering
  /// correctly — the old mapping stays, and the new token is added beside it.
  String _deniedReasonLabel(String reason) => switch (reason) {
    'order_has_completed_payment' => l10n.activityLogDeniedOrderHasPayment,
    'full_comp_requires_manager' =>
      l10n.activityLogDeniedFullCompRequiresManager,
    'full_comp_permission_required' =>
      l10n.activityLogDeniedFullCompPermissionRequired,
    'discount_exceeds_order_total' =>
      l10n.activityLogDeniedDiscountExceedsOrderTotal,
    'order_not_voidable' => l10n.activityLogDeniedOrderNotVoidable,
    // RESTAURANT-OPERATIONS-V1-001: table-move / availability refusals.
    // 'permission_denied' first appears as a denied_reason VALUE in this
    // phase's two denial audits — without a case it rendered raw in all
    // three locales (stabilization fix).
    'permission_denied' => l10n.activityLogDeniedPermission,
    'takeaway_order' => l10n.activityLogDeniedTakeawayOrder,
    'order_not_movable' => l10n.activityLogDeniedOrderNotMovable,
    'table_not_available' => l10n.activityLogDeniedTableNotAvailable,
    // ORDER-EDIT-001A: editing a sent order / acknowledging the change.
    // permission_denied, full_comp_permission_required and
    // discount_exceeds_order_total reuse the labels above.
    'removal_not_permitted' => l10n.activityLogDeniedRemovalNotPermitted,
    'finished_food_needs_manager' =>
      l10n.activityLogDeniedFinishedFoodNeedsManager,
    'reason_required' => l10n.activityLogDeniedReasonRequired,
    'feature_disabled' => l10n.activityLogDeniedFeatureDisabled,
    'order_not_editable' => l10n.activityLogDeniedOrderNotEditable,
    'order_already_settled' => l10n.activityLogDeniedOrderAlreadySettled,
    'kitchen_mode_changed' => l10n.activityLogDeniedKitchenModeChanged,
    'line_changed' => l10n.activityLogDeniedLineChanged,
    'line_has_discount' => l10n.activityLogDeniedLineHasDiscount,
    'legacy_line_not_editable' => l10n.activityLogDeniedLegacyLineNotEditable,
    'edit_would_empty_order' => l10n.activityLogDeniedEditWouldEmptyOrder,
    'tax_mode_unsupported' => l10n.activityLogDeniedTaxModeUnsupported,
    'totals_mismatch' => l10n.activityLogDeniedTotalsMismatch,
    'invalid_edit_number' => l10n.activityLogDeniedInvalidEditNumber,
    'order_voided' => l10n.activityLogDeniedOrderVoided,
    'item_unavailable' => l10n.activityLogDeniedItemUnavailable,
    'modifier_option_not_in_scope' =>
      l10n.activityLogDeniedModifierOptionNotInScope,
    'modifier_prep_snapshot_stale' =>
      l10n.activityLogDeniedModifierPrepSnapshotStale,
    // Also emitted by the PSC-001D void-acknowledgement refusal (the action
    // came from a device type that may not perform it); it rendered raw.
    'invalid_device_type' => l10n.activityLogDeniedInvalidDeviceType,
    // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: card_attempt.denied and refused
    // recording retries (the card family's denied_reason labels
    // permission_denied with its own key, _cardDeniedReasonLabel).
    'ineligible_order_state' => l10n.activityLogDeniedIneligibleOrderState,
    'max_live_amount_exceeded' => l10n.activityLogDeniedMaxLiveAmountExceeded,
    'no_open_shift' => l10n.activityLogDeniedNoOpenShift,
    'no_active_drawer' => l10n.activityLogDeniedNoActiveDrawer,
    'no_recording_attempt' => l10n.activityLogDeniedNoRecordingAttempt,
    'attempt_not_freeable' => l10n.activityLogDeniedAttemptNotFreeable,
    'charge_may_exist' => l10n.activityLogDeniedChargeMayExist,
    'confirmation_required' => l10n.activityLogDeniedConfirmationRequired,
    'device_not_active' => l10n.activityLogDeniedDeviceNotActive,
    'operation_mismatch' => l10n.activityLogDeniedOperationMismatch,
    'resume_limit' => l10n.activityLogDeniedResumeLimit,
    'resume_stale' => l10n.activityLogDeniedResumeStale,
    'not_recoverable' => l10n.activityLogDeniedNotRecoverable,
    'payment_exists' => l10n.activityLogDeniedPaymentExists,
    'claim_inactive' => l10n.activityLogDeniedClaimInactive,
    'order_not_chargeable' => l10n.activityLogDeniedOrderNotChargeable,
    'context_lost' => l10n.activityLogDeniedContextLost,
    'amount_mismatch' => l10n.activityLogDeniedAmountMismatch,
    'refusal_not_recorded' => l10n.activityLogDeniedRefusalNotRecorded,
    _ => reason,
  };

  /// WHAT the mutation would have left the order as. `not_chargeable` means the
  /// order would owe nothing at all — i.e. it would be FREE.
  String _chargeStateLabel(String state) => switch (state) {
    'not_chargeable' => l10n.dashboardNoCharge,
    _ => state,
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
    // ORDER-EDIT-001A: the edit left the order served + paid, so it closed.
    'order_edited' => l10n.activityLogCompletionTriggerOrderEdited,
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
    // KITCHEN-MODE-001B: printer configuration shares the `role` payload key —
    // localize its closed vocabulary too (no collision with membership roles).
    'receipt' => l10n.printersRoleReceipt,
    'kitchen' => l10n.printersRoleKitchen,
    'both' => l10n.printersRoleBoth,
    _ => role,
  };

  String _fieldLabel(String key) => auditFieldLabel(l10n, key);

  String _capabilityLabel(String cap) => switch (cap) {
    'apply_discount' => l10n.activityLogCapApplyDiscount,
    'void_order' => l10n.activityLogCapVoidOrder,
    'close_shift' => l10n.activityLogCapCloseShift,
    'apply_full_comp' => l10n.activityLogCapApplyFullComp,
    'open_cash_drawer' => l10n.activityLogCapOpenCashDrawer,
    _ => cap,
  };

  static int _int(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
}
