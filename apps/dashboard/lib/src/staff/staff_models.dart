import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The EFFECTIVE cashier capabilities (server-resolved). These toggles apply ONLY
/// to the cashier role; the backend is the authoritative gate — this is
/// display/edit state only.
///
/// TWO POLARITIES, mirroring the server:
///  * STAFF-CASHIER-PERMISSIONS-001 — [applyDiscount], [voidOrder], [closeShift]
///    are DEFAULT-ON and denied only by an explicit override.
///  * FULL-COMP-PERMISSION-001 — [applyFullComp] is DEFAULT-OFF and granted only
///    by an explicit override. Getting this inversion wrong in [fromJson] would
///    render an ungranted cashier as *allowed to give food away*, so it is parsed
///    with the opposite test to the other three.
class StaffCapabilities {
  const StaffCapabilities({
    this.applyDiscount = true,
    this.voidOrder = true,
    this.closeShift = true,
    this.applyFullComp = false,
    this.manageMenuAvailability = true,
    this.manageTableOperations = true,
  });

  /// Applying order/item discounts. Default ON.
  final bool applyDiscount;

  /// Cancelling/voiding an UNPAID order (paid-order void stays server-blocked).
  final bool voidOrder;

  /// Closing the cashier's OWN/current shift.
  final bool closeShift;

  /// FULL-COMP-PERMISSION-001: making an order FREE — a discount that leaves the
  /// order's total at exactly zero. DEFAULT OFF: a cashier holds it only when an
  /// owner/manager grants it explicitly.
  final bool applyFullComp;

  /// PILOT-OPERATIONS-CORRECTIONS-001: changing a menu item's per-branch
  /// availability (Sold out / Paused) from the POS. Default ON.
  final bool manageMenuAvailability;

  /// PILOT-OPERATIONS-CORRECTIONS-001: operational table control from the POS
  /// (manual status, link/unlink). Default ON.
  final bool manageTableOperations;

  /// True when none of the DEFAULT-ON capabilities is disabled (a new cashier's
  /// preset). [applyFullComp] is deliberately NOT part of this: it is default-OFF,
  /// so a fresh cashier having it off is the norm, not a deviation.
  bool get allEnabled =>
      applyDiscount &&
      voidOrder &&
      closeShift &&
      manageMenuAvailability &&
      manageTableOperations;

  /// FULL-COMP-PERMISSION-001: a stored full-comp grant is INERT while ordinary
  /// discounts are denied — the server checks [applyDiscount] first and refuses
  /// there. The UI must say so rather than implying the comp switch still works.
  bool get fullCompEffective => applyFullComp && applyDiscount;

  StaffCapabilities copyWith({
    bool? applyDiscount,
    bool? voidOrder,
    bool? closeShift,
    bool? applyFullComp,
    bool? manageMenuAvailability,
    bool? manageTableOperations,
  }) => StaffCapabilities(
    applyDiscount: applyDiscount ?? this.applyDiscount,
    voidOrder: voidOrder ?? this.voidOrder,
    closeShift: closeShift ?? this.closeShift,
    applyFullComp: applyFullComp ?? this.applyFullComp,
    manageMenuAvailability:
        manageMenuAvailability ?? this.manageMenuAvailability,
    manageTableOperations: manageTableOperations ?? this.manageTableOperations,
  );

  /// Parses the `capabilities` object from `list_staff` (effective booleans).
  ///
  /// The three default-ON keys use `!= false` (a MISSING key means the role
  /// default, ON). [applyFullComp] uses the INVERSE — `== true` — so a missing
  /// key, an old server that does not send the field at all, or any malformed
  /// value all resolve to DENIED. Fail-closed: the client never invents a grant.
  static StaffCapabilities fromJson(
    Map<Object?, Object?> json,
  ) => StaffCapabilities(
    applyDiscount: json['apply_discount'] != false,
    voidOrder: json['void_order'] != false,
    closeShift: json['close_shift'] != false,
    applyFullComp: json['apply_full_comp'] == true,
    // PILOT-OPERATIONS-CORRECTIONS-001: DEFAULT-ON, so a MISSING key (an older
    // server that does not send it) resolves to ON, matching the role default.
    manageMenuAvailability: json['manage_menu_availability'] != false,
    manageTableOperations: json['manage_table_operations'] != false,
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
