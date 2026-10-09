/// ORDER-EDIT-001E — the BASELINE of a sent-order edit: the authoritative
/// `pos_order_detail` an edit starts from, judged once for eligibility and
/// turned into one [OrderEditSourceLine] per live line.
///
/// PURE: no widgets, no providers, no I/O. The menu is passed in, never read.
///
/// The verdict MIRRORS `app.edit_order` step 5 (and the §6 eligibility list)
/// so the POS refuses up front, with the server's own words, what the server
/// would refuse anyway. It fails CLOSED: anything this build cannot prove is
/// treated as not editable, never guessed into an editable shape — the server
/// stays the authority (D-011) and re-decides every rule under its locks.
///
/// Money is integer minor units (D-007). Nothing here re-prices a sent line:
/// every amount is the order-time snapshot the server stored (D-008).
library;

import 'package:restoflow_domain/restoflow_domain.dart' show KitchenMeat;

import '../state/cart_controller.dart' show SelectedModifier;
import '../state/pos_menu_provider.dart' show PosMenuData, PosModifierGroup;
import 'demo_menu.dart' show DemoMenuItem;
import 'order_detail_repository.dart';
import 'order_edit_read_model.dart';
import 'staff_capabilities.dart';

/// Why an order cannot be edited right now, in `app.edit_order` step-5
/// order — each value is the refusal the server would return.
enum OrderEditIneligibility {
  /// The branch switch `order_edit_enabled` is off — or unknown, which hides
  /// the rollout gate (`feature_disabled`).
  featureDisabled,

  /// Not `dine_in` / `takeaway`, or not `submitted..served`
  /// (`order_not_editable`).
  notEditable,

  /// A live completed payment exists (`order_already_settled`).
  alreadyPaid,

  /// The kitchen channel is unresolvable (`kitchen_mode_changed`).
  kitchenModeChanged,

  /// A live line (or one of its options) carries no server identity, so no
  /// change could ever name it. The detail is not usable for an edit — an
  /// older server, or a malformed answer — and the caller treats it as such.
  unidentifiedLine,
}

/// The `submitted..served` statuses `app.edit_order` accepts (step 5).
const Set<String> kOrderEditableStatuses = <String>{
  'submitted',
  'accepted',
  'preparing',
  'ready',
  'served',
};

/// The unit statuses whose food the kitchen has finished (step 7 / §8.3).
const Set<String> _finishedUnitStatuses = <String>{'ready', 'served'};

/// One option of a sent line, exactly as the server stored it.
class OrderEditSourceModifier {
  const OrderEditSourceModifier({
    required this.optionId,
    required this.optionName,
    required this.priceMinor,
    required this.quantity,
    this.groupName,
    this.meat,
    this.groupId,
  });

  /// `order_item_modifiers.modifier_option_id` — never null here (a line with
  /// an unidentified option makes the whole baseline ineligible).
  final String optionId;
  final String optionName;
  final String? groupName;

  /// The STORED unit price of the option. A kept option is always charged
  /// this, never the live menu price (`edit_order.sql:1296-1305`).
  final int priceMinor;
  final int quantity;

  /// The order-time kitchen-count snapshot (per modifier unit), carried for
  /// the cart only; a kept option is re-answered server-side.
  final KitchenMeat? meat;

  /// The LIVE menu group this option belongs to, found by a UNIQUE option-id
  /// match in the item's groups — so the modifier sheet never falls back to
  /// its group-name heuristic. Null when the option is not (or not uniquely)
  /// on the live menu.
  final String? groupId;

  /// The cart's view of this stored option (its own price, name and kitchen
  /// snapshot — nothing re-read from the menu).
  SelectedModifier toSelectedModifier() => SelectedModifier(
    optionId: optionId,
    groupName: groupName ?? '',
    optionName: optionName,
    priceDeltaMinor: priceMinor,
    quantity: quantity,
    kitchenMeat: meat,
    modifierGroupId: groupId,
  );
}

/// One live line of the order an edit starts from.
class OrderEditSourceLine {
  const OrderEditSourceLine({
    required this.orderItemId,
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineDiscountMinor,
    required this.lineTotalMinor,
    required this.modifiers,
    required this.channel,
    this.notes,
    this.unitStatus,
    this.legacy,
    this.serviceRoundId,
    this.categoryDisplayOrder = 0,
    this.itemDisplayOrder = 0,
    this.missingFromMenu = false,
    this.unavailable = false,
  });

  final String orderItemId;
  final String menuItemId;
  final String name;
  final int quantity;

  /// The stored BARE unit price (`unit_price_minor_snapshot`).
  final int unitPriceMinor;
  final int lineDiscountMinor;

  /// The stored line total — what this line contributes while it is kept.
  final int lineTotalMinor;
  final List<OrderEditSourceModifier> modifiers;
  final String? notes;

  /// The raw D-018 status of the line's work unit (`unit_status`).
  final String? unitStatus;

  /// The server's M1a legacy flag; null is UNKNOWN and counts as legacy.
  final bool? legacy;
  final String? serviceRoundId;
  final int categoryDisplayOrder;
  final int itemDisplayOrder;

  /// The order's kitchen channel (resolved — the baseline is eligible).
  final PosKitchenChannel channel;

  /// The item, or one of its stored options, is not (uniquely) on the live
  /// menu — or the menu is unknown.
  final bool missingFromMenu;

  /// The item is on the live menu but marked unavailable in this branch.
  final bool unavailable;

  /// Unknown counts as legacy: an unknown price history is never editable as
  /// if it were current (`order_detail_repository.dart`).
  bool get isLegacy => legacy != false;
  bool get hasLineDiscount => lineDiscountMinor > 0;

  /// REMOVE ONLY (design §7.1, M3): `app.edit_order` refuses a modify or a
  /// set_quantity on a discounted (`line_has_discount`) or legacy-priced
  /// (`legacy_line_not_editable`) line; removing it is always allowed.
  bool get removeOnly => isLegacy || hasLineDiscount;

  /// KEEP OR REMOVE ONLY (design §7.1, decision D11): the item or an option
  /// left the menu, so the line can only be kept as it is or removed.
  bool get keepOrRemoveOnly => missingFromMenu;

  /// '+' is withheld: the server re-checks sellability on an increase
  /// (`item_unavailable`).
  bool get increaseBlocked => unavailable || missingFromMenu;

  /// The configured unit price under the 002A formula:
  /// `unit + Σ(option price × option quantity)`, with the STORED prices.
  int get configuredUnitMinor {
    var total = unitPriceMinor;
    for (final m in modifiers) {
      total += m.priceMinor * m.quantity;
    }
    return total;
  }

  /// The stage chip (Waiting / In kitchen / Ready / Served / Printed).
  PosLineStage? get stage =>
      posLineStageFor(unitStatus: unitStatus, channel: channel);

  /// The line's work unit has not been acknowledged by the kitchen yet: a
  /// KDS ticket still `submitted` (the "Customer changed mind" preselect).
  bool get isWaitingOnKds =>
      channel == PosKitchenChannel.kds && unitStatus == 'submitted';

  /// The kitchen finished this line's food: a KDS unit `ready` or `served`.
  /// Never true on paper, where every line is "Printed" (§9.2).
  bool get isFinishedOnKds =>
      channel == PosKitchenChannel.kds &&
      _finishedUnitStatuses.contains(unitStatus);

  /// The STORED price of [optionId] on this line, or null when the option is
  /// new to it. Matched by lower-case id, the server's canonical spelling, and
  /// the FIRST match wins, exactly like `edit_order`'s kept-option lookup.
  int? storedPriceOf(String optionId) {
    final id = optionId.toLowerCase();
    for (final m in modifiers) {
      if (m.optionId.toLowerCase() == id) return m.priceMinor;
    }
    return null;
  }

  /// The cart's view of the stored options.
  List<SelectedModifier> toSelectedModifiers() => [
    for (final m in modifiers) m.toSelectedModifier(),
  ];
}

/// Why [OrderEditBaseline.fromDetail] did or did not produce a baseline.
class OrderEditBaselineVerdict {
  const OrderEditBaselineVerdict.eligible(OrderEditBaseline this.baseline)
    : ineligibility = null;

  const OrderEditBaselineVerdict.ineligible(
    OrderEditIneligibility this.ineligibility,
  ) : baseline = null;

  final OrderEditBaseline? baseline;
  final OrderEditIneligibility? ineligibility;

  bool get isEligible => baseline != null;
}

/// The authoritative starting point of one edit.
class OrderEditBaseline {
  const OrderEditBaseline._({
    required this.detail,
    required this.channel,
    required this.lines,
  });

  /// The detail the baseline was built from — its money header is the
  /// "Was" side of the footer and the source of the kept order discount.
  final PosOrderDetail detail;

  /// The resolved kitchen channel (`kds` / `paper`).
  final PosKitchenChannel channel;

  /// Every live line, in the server's print order (the order `pos_order_detail`
  /// emits) — also the canonical order of the planned changes.
  final List<OrderEditSourceLine> lines;

  String get orderId => detail.orderId;
  String get orderCode => detail.orderCode;
  String get currencyCode => detail.currencyCode;

  /// The kept absolute order discount (M6): never clamped, never re-applied.
  int get discountMinor => detail.discountTotalMinor;

  /// The order's stored grand total — the footer's "Was".
  int get grandBeforeMinor => detail.grandTotalMinor;

  /// Σ live line totals. The server RE-ROLLS the subtotal from the live lines
  /// (M5, `edit_order.sql:1618`), so this — not the stored header — is what an
  /// edit's new subtotal is built on.
  int get liveSubtotalMinor {
    var total = 0;
    for (final l in lines) {
      total += l.lineTotalMinor;
    }
    return total;
  }

  /// The line bound to [orderItemId], matched by lower-case id.
  OrderEditSourceLine? lineFor(String orderItemId) {
    final id = orderItemId.toLowerCase();
    for (final l in lines) {
      if (l.orderItemId.toLowerCase() == id) return l;
    }
    return null;
  }

  /// "Manager needed" (design §7.1, `edit_order` step 7): with the
  /// finished-food switch ON on a KDS branch, a CASHIER may not remove, reduce
  /// or modify a Ready / Served line. Only a known `cashier` role is held back
  /// — the server decides for an unknown one.
  bool needsManagerFor(
    OrderEditSourceLine line,
    PosStaffCapabilities? capabilities,
  ) {
    final switchOn =
        (detail.branchFeatures ?? capabilities?.branchFeatures)
            ?.finishedFoodManagerOnly ??
        false;
    return switchOn && line.isFinishedOnKds && capabilities?.role == 'cashier';
  }

  /// Judges [detail] and, when it is editable, builds the baseline.
  ///
  /// The checks run in `app.edit_order` step-5 order. [menu] is the LIVE menu,
  /// used only for the per-line "keep or remove only" / "+" flags and the
  /// option-to-group attribution; when it is null nothing can be proven to
  /// still exist, so every line is keep-or-remove-only (fail closed).
  static OrderEditBaselineVerdict fromDetail(
    PosOrderDetail detail, {
    PosMenuData? menu,
  }) {
    // The detail's own switch is FRESHER than the session probe; unknown
    // hides the rollout gate (API_CONTRACT §4.30b).
    if (detail.branchFeatures?.orderEditEnabled != true) {
      return const OrderEditBaselineVerdict.ineligible(
        OrderEditIneligibility.featureDisabled,
      );
    }
    if ((detail.orderType != 'dine_in' && detail.orderType != 'takeaway') ||
        !kOrderEditableStatuses.contains(detail.status)) {
      return const OrderEditBaselineVerdict.ineligible(
        OrderEditIneligibility.notEditable,
      );
    }
    if (detail.payment != null) {
      return const OrderEditBaselineVerdict.ineligible(
        OrderEditIneligibility.alreadyPaid,
      );
    }
    final channel = detail.kitchenChannel;
    if (channel == null) {
      return const OrderEditBaselineVerdict.ineligible(
        OrderEditIneligibility.kitchenModeChanged,
      );
    }

    final lines = <OrderEditSourceLine>[];
    for (final item in detail.items) {
      final orderItemId = item.orderItemId;
      final menuItemId = item.menuItemId;
      if (orderItemId == null || menuItemId == null) {
        return const OrderEditBaselineVerdict.ineligible(
          OrderEditIneligibility.unidentifiedLine,
        );
      }
      final groups = menu?.groupsForItem(menuItemId);
      final menuItem = menu == null ? null : _menuItem(menu, menuItemId);
      var missing = menuItem == null;
      final modifiers = <OrderEditSourceModifier>[];
      for (final m in item.modifiers) {
        final optionId = m.modifierOptionId;
        if (optionId == null) {
          // `modifier_option_id` is NOT NULL server-side: a missing id means
          // a detail this build cannot edit against.
          return const OrderEditBaselineVerdict.ineligible(
            OrderEditIneligibility.unidentifiedLine,
          );
        }
        final groupId = groups == null
            ? null
            : _uniqueGroupOf(groups, optionId);
        if (groupId == null) missing = true;
        modifiers.add(
          OrderEditSourceModifier(
            optionId: optionId,
            optionName: m.optionName,
            groupName: m.modifierName,
            priceMinor: m.priceMinor,
            quantity: m.quantity,
            meat: m.meat,
            groupId: groupId,
          ),
        );
      }
      lines.add(
        OrderEditSourceLine(
          orderItemId: orderItemId,
          menuItemId: menuItemId,
          name: item.name,
          quantity: item.quantity,
          unitPriceMinor: item.unitPriceMinor,
          lineDiscountMinor: item.lineDiscountMinor,
          lineTotalMinor: item.lineTotalMinor,
          modifiers: List<OrderEditSourceModifier>.unmodifiable(modifiers),
          notes: item.notes,
          unitStatus: item.unitStatus,
          legacy: item.legacy,
          serviceRoundId: item.serviceRoundId,
          categoryDisplayOrder: item.categoryDisplayOrder,
          itemDisplayOrder: item.itemDisplayOrder,
          channel: channel,
          missingFromMenu: missing,
          unavailable: menuItem?.isUnavailable ?? false,
        ),
      );
    }
    return OrderEditBaselineVerdict.eligible(
      OrderEditBaseline._(
        detail: detail,
        channel: channel,
        lines: List<OrderEditSourceLine>.unmodifiable(lines),
      ),
    );
  }
}

DemoMenuItem? _menuItem(PosMenuData menu, String menuItemId) {
  for (final item in menu.items) {
    if (item.id == menuItemId) return item;
  }
  return null;
}

/// The id of the ONE live group of the item that offers [optionId], or null
/// when none does — or more than one does, which cannot be attributed safely.
String? _uniqueGroupOf(List<PosModifierGroup> groups, String optionId) {
  final id = optionId.toLowerCase();
  String? found;
  for (final group in groups) {
    for (final option in group.options) {
      if (option.id.toLowerCase() != id) continue;
      if (found != null && found != group.id) return null;
      found = group.id;
    }
  }
  return found;
}
