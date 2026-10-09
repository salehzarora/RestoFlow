import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'order_edit_read_model.dart' show PosBranchFeatures;

/// FULL-COMP-PERMISSION-001 — the EFFECTIVE rights of the human behind the current
/// PIN session, as the SERVER resolves them.
///
/// These are EFFECTIVE, not stored, values: a manager/owner holds both rights BY
/// ROLE, while a cashier holds [applyDiscount] by default and [applyFullComp] only
/// via an explicit grant. The POS therefore never has to know the role or reason
/// about role hierarchies — it asks the server what this person may do.
///
/// ADVISORY ONLY. The server re-decides on every mutation inside `app.apply_discount`
/// and remains the sole authority. These exist so the POS can state the rule up
/// front instead of letting a cashier type a discount, wait, and be refused.
class PosStaffCapabilities {
  const PosStaffCapabilities({
    required this.applyDiscount,
    required this.applyFullComp,
    this.manageMenuAvailability = false,
    this.manageTableOperations = false,
    this.openCashDrawer = false,
    this.role,
    this.voidOrder,
    this.branchFeatures,
  });

  /// FAIL-CLOSED default: knowing nothing, we assume nothing is granted.
  static const PosStaffCapabilities none = PosStaffCapabilities(
    applyDiscount: false,
    applyFullComp: false,
    manageMenuAvailability: false,
    manageTableOperations: false,
    openCashDrawer: false,
    role: null,
    voidOrder: false,
    branchFeatures: null,
  );

  /// KITCHEN-PRINT-DUAL-001D: the membership role of the current PIN session, as
  /// resolved by the server (the SAME `pin_session_capabilities` envelope already
  /// returns it — no new permission model). Advisory only; the server re-checks
  /// every order.status push. Null when unknown.
  final String? role;

  /// The roles the server already authorizes to change order kitchen statuses
  /// (`app.update_order_status`): kitchen_staff is a KDS role, so on the POS the
  /// authorized set is cashier / manager / restaurant_owner / org_owner. Used ONLY
  /// to gate a client affordance (the bulk finish button) — never to grant.
  static const Set<String> _kitchenStatusRoles = {
    'cashier',
    'manager',
    'restaurant_owner',
    'org_owner',
  };

  /// Whether this session's role may drive the bulk kitchen-finish action.
  bool get canFinishKitchenOrders =>
      role != null && _kitchenStatusRoles.contains(role);

  /// ORDER-EDIT-001E: the roles `app.edit_order` accepts. `kitchen_staff`
  /// reads `void_order` FALSE, yet the server refuses that role EVERY edit —
  /// additions included — so the POS entry gates on the role, not on the
  /// capability (API_CONTRACT §4.30b). Deliberately a separate set from
  /// [_kitchenStatusRoles]: the two server rules happen to agree today and
  /// must be free to diverge. Gates a client affordance only — never grants.
  static const Set<String> _orderEditRoles = {
    'cashier',
    'manager',
    'restaurant_owner',
    'org_owner',
  };

  /// Whether this session's role may edit a sent order. Unknown role reads
  /// false: the entry is hidden rather than offered to a role the server
  /// refuses outright.
  bool get canEditOrders => role != null && _orderEditRoles.contains(role);

  /// May apply ordinary discounts.
  final bool applyDiscount;

  /// May apply a discount that brings the order total to exactly zero.
  final bool applyFullComp;

  /// PILOT-OPERATIONS-CORRECTIONS-001: may change a menu item's per-branch
  /// availability (Sold out / Paused) from the POS. Server-authoritative.
  final bool manageMenuAvailability;

  /// PILOT-OPERATIONS-CORRECTIONS-001: may run operational table control (manual
  /// status, link/unlink) from the POS. Server-authoritative.
  final bool manageTableOperations;

  /// POS-CASH-DRAWER-MANUAL-OPEN-001: may open the cash drawer manually (a
  /// "no-sale" open). Grant-only for a cashier (default OFF), held by role by a
  /// manager/owner. Server-authoritative — the unlock and every open re-check it.
  final bool openCashDrawer;

  /// ORDER-EDIT-001B / 001E: the effective `void_order` right — the predicate
  /// `app.void_order` and `app.edit_order`'s REMOVAL gate enforce (manager+ by
  /// role, or the deny-only cashier capability). It gates the REMOVING changes
  /// of a sent-order edit (remove, reduce, modify), never the "Edit order"
  /// entry itself: additions and +1 stay possible without it.
  ///
  /// NULLABLE, unlike its siblings: null means the server did not say (an
  /// older server, or a restored offline snapshot), and UNKNOWN IS NOT DENIED
  /// — the removing controls stay usable and the server decides
  /// (API_CONTRACT §4.30b). An explicit non-boolean is malformed and reads
  /// false.
  final bool? voidOrder;

  /// ORDER-EDIT-001B / 001E: the session branch's two edit switches (the
  /// top-level `branch_features`, a SIBLING of `capabilities` in the probe).
  /// Null when unknown — and the rollout gate HIDES "Edit order" when unknown.
  /// Never persisted to the offline snapshot: editing is online-only, and a
  /// restored rollout gate would be stale.
  final PosBranchFeatures? branchFeatures;

  /// Parses the `capabilities` object from `public.pin_session_capabilities`.
  ///
  /// All use `== true`, so a missing field, an old server that does not send the
  /// key, a null, or any malformed value resolves to DENIED. The client never
  /// invents a permission it was not explicitly given.
  ///
  /// ORDER-EDIT-001E — the one exception is [voidOrder]: an ABSENT key is
  /// unknown (null), not denied, per the §4.30b client rule; a present
  /// non-boolean still resolves to denied. [branchFeatures] is the probe's
  /// top-level `branch_features` (a sibling of `capabilities`, so the caller
  /// passes it in), parsed atomically by [PosBranchFeatures.tryParse].
  static PosStaffCapabilities fromJson(
    Map<Object?, Object?> json, {
    Object? role,
    Object? branchFeatures,
  }) => PosStaffCapabilities(
    applyDiscount: json['apply_discount'] == true,
    applyFullComp: json['apply_full_comp'] == true,
    manageMenuAvailability: json['manage_menu_availability'] == true,
    manageTableOperations: json['manage_table_operations'] == true,
    openCashDrawer: json['open_cash_drawer'] == true,
    role: role is String ? role : null,
    voidOrder: json.containsKey('void_order')
        ? json['void_order'] == true
        : null,
    branchFeatures: PosBranchFeatures.tryParse(branchFeatures),
  );
}

/// Reads the effective capabilities of the current PIN session.
abstract class StaffCapabilitiesRepository {
  /// Returns the effective capabilities, or null when they cannot be established
  /// (no session, transport failure, malformed envelope).
  ///
  /// NULL MEANS "UNKNOWN", NOT "DENIED" — and the two must not be conflated. The
  /// POS keeps the discount controls available when capabilities are unknown and
  /// lets the SERVER refuse, because silently hiding a manager's discount button
  /// after a transient network blip would be a worse failure than an honest
  /// server-side rejection. Nothing unsafe can follow: the server gate is
  /// authoritative and a zero-total discount is still refused there.
  Future<PosStaffCapabilities?> fetch();
}

/// DEMO capabilities: the demo cashier can discount but CANNOT comp, so the demo
/// exercises the same refusal path a real un-granted cashier hits.
class DemoStaffCapabilitiesRepository implements StaffCapabilitiesRepository {
  const DemoStaffCapabilitiesRepository();

  @override
  Future<PosStaffCapabilities?> fetch() async => const PosStaffCapabilities(
    applyDiscount: true,
    applyFullComp: false,
    // PILOT-OPERATIONS-CORRECTIONS-001: the demo cashier can manage availability
    // and tables (default-ON in the real deny-only model) so the demo exercises
    // the operational controls.
    manageMenuAvailability: true,
    manageTableOperations: true,
    role: 'cashier',
  );
}

/// REAL capabilities, read from `public.pin_session_capabilities` over the same
/// anon-key + PIN/device-session transport as the sync path (never the `app`
/// schema, never a service-role key).
class RealStaffCapabilitiesRepository implements StaffCapabilitiesRepository {
  const RealStaffCapabilitiesRepository(this._transport, this._session);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;

  @override
  Future<PosStaffCapabilities?> fetch() async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) return null;

    final Object? raw;
    try {
      raw = await transport.invoke(
        'pin_session_capabilities',
        <String, dynamic>{
          'p_pin_session_id': session.pinSessionId,
          'p_device_id': session.deviceId,
        },
      );
    } on SyncTransportException {
      return null; // unknown, not denied — see the seam doc above.
    }
    if (raw is! Map || raw['ok'] != true) return null;
    final caps = raw['capabilities'];
    if (caps is! Map) return null;
    // ORDER-EDIT-001E: `branch_features` is a top-level SIBLING of
    // `capabilities` (§4.30b) — absent on an older server, which hides Edit.
    return PosStaffCapabilities.fromJson(
      caps,
      role: raw['role'],
      branchFeatures: raw['branch_features'],
    );
  }
}
