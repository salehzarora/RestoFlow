import 'generated/app_localizations.dart';

/// The closed set of order-edit `reason_code` wire values (ORDER-EDIT-001C).
///
/// Same values and order as the `order_edits.reason_code` CHECK
/// (supabase/migrations/20261008170000_order_edit_001a_schema.sql). A new
/// server code must be added here AND given an `orderEditReason*` label.
const List<String> kOrderEditReasonCodes = <String>[
  'customer_changed_mind',
  'entry_mistake',
  'item_unavailable',
  'kitchen_issue',
  'other',
];

/// The localized label of an order-edit [code], or `null` for an unknown or
/// absent code, so a caller never shows the raw wire value.
///
/// The one mapping shared by the POS reason chips, the KDS change header, the
/// kitchen change slip and the Dashboard. These are the NON-audit
/// `orderEditReason*` keys; the Activity log keeps its own
/// `activityLogEditReason*` values.
String? orderEditReasonLabel(AppLocalizations l10n, String? code) =>
    switch (code) {
      'customer_changed_mind' => l10n.orderEditReasonCustomerChangedMind,
      'entry_mistake' => l10n.orderEditReasonEntryMistake,
      'item_unavailable' => l10n.orderEditReasonItemUnavailable,
      'kitchen_issue' => l10n.orderEditReasonKitchenIssue,
      'other' => l10n.orderEditReasonOther,
      _ => null,
    };
