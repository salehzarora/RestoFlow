import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// STAFF-CASHIER-PERMISSIONS-001: the three default-ON cashier capabilities, as
/// EFFECTIVE booleans (server-resolved: on unless an explicit deny override
/// exists). These toggles apply ONLY to the cashier role; the backend is the
/// authoritative gate — this is display/edit state only. Defaults are all ON to
/// match a freshly-created cashier.
class StaffCapabilities {
  const StaffCapabilities({
    this.applyDiscount = true,
    this.voidOrder = true,
    this.closeShift = true,
  });

  /// Applying order/item discounts.
  final bool applyDiscount;

  /// Cancelling/voiding an UNPAID order (paid-order void stays server-blocked).
  final bool voidOrder;

  /// Closing the cashier's OWN/current shift.
  final bool closeShift;

  /// True when nothing is disabled (a new cashier's default preset).
  bool get allEnabled => applyDiscount && voidOrder && closeShift;

  StaffCapabilities copyWith({
    bool? applyDiscount,
    bool? voidOrder,
    bool? closeShift,
  }) => StaffCapabilities(
    applyDiscount: applyDiscount ?? this.applyDiscount,
    voidOrder: voidOrder ?? this.voidOrder,
    closeShift: closeShift ?? this.closeShift,
  );

  /// Parses the `capabilities` object from `list_staff` (effective booleans).
  /// A missing key defaults to ON (the role default), matching the server rule.
  static StaffCapabilities fromJson(Map<Object?, Object?> json) =>
      StaffCapabilities(
        applyDiscount: json['apply_discount'] != false,
        voidOrder: json['void_order'] != false,
        closeShift: json['close_shift'] != false,
      );
}

/// A staff member (an `employee_profiles` row + its authoritative membership
/// role). Pure Dart. NEVER carries PIN material — only the boolean fact that a
/// PIN credential is set (`has_pin`); the backend stores a bcrypt hash and the
/// raw PIN exists nowhere.
class StaffMember {
  const StaffMember({
    required this.employeeProfileId,
    required this.displayName,
    required this.role,
    required this.hasPin,
    required this.employmentStatus,
    this.employeeNumber,
    this.capabilities,
  });

  final String employeeProfileId;
  final String displayName;
  final MembershipRole role;

  /// True when a PIN credential reference is set (boolean only — never the ref).
  final bool hasPin;

  /// `active` / `suspended` / `terminated`.
  final String employmentStatus;
  final String? employeeNumber;

  /// STAFF-CASHIER-PERMISSIONS-001: the effective cashier capabilities. Only
  /// meaningful for [MembershipRole.cashier]; null / ignored for other roles.
  final StaffCapabilities? capabilities;

  bool get isActive => employmentStatus == 'active';

  /// True for a cashier — the only role whose capabilities are editable here.
  bool get isCashier => role == MembershipRole.cashier;
}

/// The staff roles a dashboard owner/manager can provision from this surface —
/// PIN-operated tenant roles only. Owner roles are granted via Users/RF-112
/// (`grant_membership`), never here; `platform_admin` is not a tenant role
/// (D-026).
const List<MembershipRole> kProvisionableStaffRoles = [
  MembershipRole.cashier,
  MembershipRole.kitchenStaff,
  MembershipRole.manager,
];
