import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_money/restoflow_money.dart';

import '../data/demo_menu.dart';
import 'pos_menu_provider.dart';
import 'submitted_order_view.dart';

/// One SELECTED modifier option on a cart line (demo-readiness sprint) — the
/// order-time snapshot (D-008) the payload sends as an `order_item_modifiers`
/// entry: option id + group/option name snapshots + a SIGNED minor-unit price
/// delta. [quantity] (modifier-quantity sprint) is how many units of THIS
/// option the cashier took (extra cheese ×2) — the frozen RF-052 total
/// formula the server recomputes is
/// `line_total = qty × unit + Σ(delta × modifier_qty) − discount`.
class SelectedModifier {
  const SelectedModifier({
    required this.optionId,
    required this.groupName,
    required this.optionName,
    required this.priceDeltaMinor,
    this.quantity = 1,
    this.kitchenMeat,
  });

  final String optionId;
  final String groupName;
  final String optionName;

  /// UNIT price delta (signed integer minor units, D-007).
  final int priceDeltaMinor;

  /// Units of this option (>= 1; quantity-enabled groups may exceed 1).
  final int quantity;

  /// KITCHEN-MEAT-001: the option's per-selection meat contribution (carried
  /// from its [PosModifierOption]), snapshotted into the order so the KDS can
  /// compute the whole-order meat total. Non-money; null when the option has no
  /// configured meat.
  final KitchenMeat? kitchenMeat;

  /// The delta this selection contributes to the line total (unit × units).
  int get totalDeltaMinor => priceDeltaMinor * quantity;

  /// The option name as rendered on cart/receipt/kitchen lines: the bare
  /// snapshot for a single unit, `name ×N` beyond (matches the KDS format).
  String get displayName =>
      quantity > 1 ? '$optionName ×$quantity' : optionName;

  /// MENU-ORDER-001 (Codex #8/#9): durable serialization so a captured draft
  /// survives an app restart (persisted with the recovery record). Money stays
  /// integer minor (D-007); the kitchen count rides through KitchenMeat's json.
  Map<String, Object?> toJson() => <String, Object?>{
    'option_id': optionId,
    'group_name': groupName,
    'option_name': optionName,
    'price_delta_minor': priceDeltaMinor,
    'quantity': quantity,
    if (kitchenMeat != null) 'kitchen_meat': kitchenMeat!.toJson(),
  };

  /// MONEY-MODIFIER-PRICING-INTEGRITY-001 — FAIL-CLOSED decode.
  ///
  /// This used to be "tolerant": `int.tryParse('${v ?? ''}') ?? 0`. That turned
  /// unreadable MONEY into a free option — the modifier name still rendered, so
  /// a 15.00 surcharge silently vanished and the line fell back to its base
  /// price. A cart we cannot read is not a cart we are entitled to re-price.
  ///
  /// The contract, derived from the ACTUAL serialized history rather than
  /// assumed — [toJson] has written BOTH `price_delta_minor` and `quantity`
  /// since it was introduced (ab43893, MENU-ORDER-001), so no record this app
  /// ever wrote can be missing either:
  ///
  ///  * `price_delta_minor` ABSENT      -> corrupt (never "free").
  ///  * `price_delta_minor` present but not an int -> corrupt.
  ///  * `quantity` ABSENT               -> 1. The ONLY legacy allowance, kept
  ///    for records predating explicit modifier quantities. Absence is
  ///    distinguished from an explicit null via [Map.containsKey], so a
  ///    corrupt null can never masquerade as a legacy record.
  ///  * `quantity` present but not an int, or < 1 -> corrupt. A zero quantity
  ///    would zero [totalDeltaMinor], which is the same under-charge by
  ///    another route.
  ///  * `option_id` blank -> corrupt: an unidentifiable option cannot be
  ///    re-priced, re-sent or reasoned about.
  ///
  /// Throwing is what makes this safe: every caller already treats a throw as
  /// "this record is unreadable". A parked cart lands in
  /// `ParkedCartsSnapshot.unreadable`, which is preserved VERBATIM on disk and
  /// re-emitted untouched by the next write, so the record is never destroyed
  /// and the active cart is never replaced by an under-charged one.
  static SelectedModifier fromJson(Map<String, Object?> json) {
    int requireInt(String key) {
      final raw = json[key];
      if (raw is int) return raw;
      throw FormatException(
        'modifier $key is not an integer minor-unit value: '
        '${raw == null ? 'absent/null' : raw.runtimeType}',
      );
    }

    final optionId = (json['option_id'] ?? '').toString();
    if (optionId.isEmpty) {
      throw const FormatException('modifier has no option_id');
    }
    final priceDeltaMinor = requireInt('price_delta_minor');
    final int quantity;
    if (!json.containsKey('quantity')) {
      quantity = 1; // legacy record, written before modifier quantities
    } else {
      quantity = requireInt('quantity');
      if (quantity < 1) {
        throw FormatException('modifier quantity must be >= 1, got $quantity');
      }
    }
    return SelectedModifier(
      optionId: optionId,
      groupName: (json['group_name'] ?? '').toString(),
      optionName: (json['option_name'] ?? '').toString(),
      priceDeltaMinor: priceDeltaMinor,
      quantity: quantity,
      kitchenMeat: KitchenMeat.tryFromJson(json['kitchen_meat']),
    );
  }
}

/// PRINT-STARTUP-REPRINT-001 (Defect 2) — the SINGLE place selected modifiers
/// become kitchen meat contributions, so the automatic ticket, the stored order
/// snapshot and the manual reprint can never drift apart.
///
/// Each option's owner-configured [KitchenMeat] is multiplied by the UNITS of
/// that option (`extra meat ×2` => two patties); the item quantity is applied
/// later by `aggregateOrderKitchenCounts`. Options with no configured meat, or
/// with non-positive units, contribute nothing — so the result is deliberately
/// NOT index-aligned with the modifier display list. Money-free (D-007).
List<KitchenMeat> kitchenMeatSnapshots(Iterable<SelectedModifier> modifiers) =>
    [
      for (final modifier in modifiers)
        if (modifier.kitchenMeat case final meat?)
          if (modifier.quantity > 0)
            KitchenMeat(
              quantity: meat.quantity * modifier.quantity,
              unit: meat.unit,
            ),
    ];

/// Immutable view of a single cart line for the POS UI.
///
/// Money fields are integer minor units (DECISION D-007); [unitPrice] and
/// [lineTotal] expose them as [Money] for type-safe display formatting.
/// [lineTotalMinor] uses the SERVER's formula: `qty × unit + Σmodifiers`.
class CartLineView {
  const CartLineView({
    required this.lineId,
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.currencyCode,
    this.modifiers = const <SelectedModifier>[],
    this.note,
    this.categoryDisplayOrder = 0,
    this.itemDisplayOrder = 0,
  });

  final String lineId;
  final String menuItemId;
  final String name;
  final int quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;
  final String currencyCode;
  final List<SelectedModifier> modifiers;

  /// MENU-ORDER-001: the item's Dashboard print-order ranks (category rank,
  /// item-within-category rank), captured from the menu at add time. Used to
  /// order items into Dashboard-configured order on the POS-direct kitchen
  /// ticket. 0 = unknown (falls back to cart order). Non-money.
  final int categoryDisplayOrder;
  final int itemDisplayOrder;

  /// Optional per-item kitchen note the cashier typed ("بدون بصل") — shown
  /// under the cart line and sent as the payload item's `notes` (non-money).
  final String? note;

  Money get unitPrice => Money(unitPriceMinor, currencyCode);
  Money get lineTotal => Money(lineTotalMinor, currencyCode);
}

/// PSC-001C cart-safety — the immutable OWNER identity of the frozen addition
/// attempt that holds the cart mutation lock. A lock is never a bare boolean:
/// the token binds the lock to ONE exact attempt (its entry generation, parent
/// order and idempotency id), so a stale callback from an earlier attempt can
/// never clear or unlock a cart owned by a later one.
class CartLockOwner {
  const CartLockOwner({
    required this.generation,
    required this.orderId,
    required this.localOperationId,
  });

  final int generation;
  final String orderId;
  final String localOperationId;

  bool matches(CartLockOwner? other) =>
      other != null &&
      other.generation == generation &&
      other.orderId == orderId &&
      other.localOperationId == localOperationId;
}

/// The typed outcome of a normal cart mutation call — a refused mutation is
/// REPORTED, never silently ignored while the UI implies success.
enum CartMutationResult {
  applied,

  /// A frozen addition attempt owns the cart (sending / retryable failure /
  /// applied-awaiting-refresh): its payload is immutable, so the visible cart
  /// must stay exactly what was frozen. The UI shows the existing pending /
  /// refresh-required messaging and disables the controls.
  lockedByAddition,
}

/// Immutable snapshot of the cart for the POS UI (the Riverpod state value).
class CartViewState {
  const CartViewState({
    required this.lines,
    required this.subtotalMinor,
    required this.currencyCode,
    this.submittedOrder,
    this.lockedByAddition = false,
  });

  /// Builds an immutable view from the mutable domain [Cart], optionally
  /// carrying the last locally-submitted order snapshot (RF-101).
  /// [lineModifiers] adds each line's selected modifier snapshots (each delta
  /// counted × its own modifier quantity — RF-052) and [lineNotes] each
  /// line's optional cashier note.
  factory CartViewState.fromCart(
    Cart cart, {
    SubmittedOrderView? submittedOrder,
    Map<String, List<SelectedModifier>> lineModifiers = const {},
    Map<String, String> lineNotes = const {},
    Map<String, (int, int)> lineDisplayOrders = const {},
    bool lockedByAddition = false,
  }) {
    var modifiersTotal = 0;
    final views = cart.lines
        .map((line) {
          final mods = lineModifiers[line.lineId] ?? const <SelectedModifier>[];
          final modSum = mods.fold<int>(0, (sum, m) => sum + m.totalDeltaMinor);
          modifiersTotal += modSum;
          final order = lineDisplayOrders[line.lineId];
          return CartLineView(
            lineId: line.lineId,
            menuItemId: line.menuItemId,
            name: line.itemNameSnapshot,
            quantity: line.quantity,
            unitPriceMinor: line.unitPriceMinor,
            lineTotalMinor: line.lineTotalMinor + modSum,
            currencyCode: line.currencyCodeSnapshot,
            modifiers: mods,
            note: lineNotes[line.lineId],
            categoryDisplayOrder: order?.$1 ?? 0,
            itemDisplayOrder: order?.$2 ?? 0,
          );
        })
        .toList(growable: false);
    return CartViewState(
      lines: views,
      subtotalMinor: cart.subtotalMinor + modifiersTotal,
      currencyCode: cart.currencyCode,
      submittedOrder: submittedOrder,
      lockedByAddition: lockedByAddition,
    );
  }

  final List<CartLineView> lines;
  final int subtotalMinor;
  final String currencyCode;

  /// Snapshot of the last locally-submitted demo order, or null when none is
  /// being confirmed (RF-101). When non-null, the cart UI shows the confirmation.
  final SubmittedOrderView? submittedOrder;

  /// PSC-001C cart-safety: a frozen addition attempt owns the cart — every
  /// visible mutation control must be disabled (the controller refuses the
  /// mutation regardless).
  final bool lockedByAddition;

  bool get hasSubmittedOrder => submittedOrder != null;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// Total number of physical items (sum of line quantities).
  int get itemCount => lines.fold(0, (count, line) => count + line.quantity);

  /// Non-authoritative subtotal preview as [Money] (no tax/discounts; the
  /// authoritative total is the server/money engine's job — RF-032/RF-036).
  Money get subtotal => Money(subtotalMinor, currencyCode);
}

/// Riverpod controller holding the in-memory POS draft [Cart] (RF-031) and
/// exposing an immutable [CartViewState].
///
/// The domain [Cart] is mutable with `void` mutators, so after each mutation we
/// re-emit a fresh [CartViewState] for Riverpod to diff. In-memory demo only —
/// no Supabase, no auth, no order submission, no payments, no persistence.
/// PILOT-OPERATIONS-CORRECTIONS-001 — an immutable snapshot of a cart draft,
/// captured at submit time so a rejected (item_unavailable) attempt can be
/// restored for deliberate correction. Carries the rebuildable truth per line.
class CartDraftSnapshot {
  const CartDraftSnapshot({required this.currencyCode, required this.lines});

  final String currencyCode;
  final List<CartDraftLine> lines;

  bool get isEmpty => lines.isEmpty;

  /// MENU-ORDER-001 (Codex #8/#9): durable serialization so a captured draft
  /// (with its Dashboard menu ranks) survives an app restart.
  Map<String, Object?> toJson() => <String, Object?>{
    'currency_code': currencyCode,
    'lines': [for (final l in lines) l.toJson()],
  };

  static CartDraftSnapshot fromJson(Map<String, Object?> json) {
    final rawLines = json['lines'];
    return CartDraftSnapshot(
      currencyCode: (json['currency_code'] ?? 'ILS').toString(),
      lines: <CartDraftLine>[
        if (rawLines is List)
          for (final l in rawLines)
            if (l is Map) CartDraftLine.fromJson(l.cast<String, Object?>()),
      ],
    );
  }
}

class CartDraftLine {
  const CartDraftLine({
    required this.menuItemId,
    required this.name,
    required this.basePriceMinor,
    required this.quantity,
    this.lineId,
    this.modifiers = const <SelectedModifier>[],
    this.note,
    this.categoryDisplayOrder = 0,
    this.itemDisplayOrder = 0,
    this.prepComponents = const <KitchenPrepComponent>[],
  });

  final String menuItemId;
  final String name;
  final int basePriceMinor;
  final int quantity;

  /// MENU-ORDER-001 (Codex #2/#3): the line's STABLE cart line id, persisted so a
  /// restored draft keeps its ORIGINAL line identity (edits/removals target the
  /// right line; no duplicates). Null on a legacy record -> a fresh id is minted.
  final String? lineId;

  final List<SelectedModifier> modifiers;
  final String? note;

  /// MENU-ORDER-001 (Codex): the line's Dashboard print ranks, captured onto the
  /// snapshot so they survive a submit -> reject -> restore round-trip (submit
  /// clears the live _lineDisplayOrders). 0 = unknown (falls back to cart order).
  final int categoryDisplayOrder;
  final int itemDisplayOrder;

  /// PARKED-CARTS-001: the item's PER-UNIT kitchen prep components, captured at
  /// ADD time (the order-time D-008 snapshot). The draft previously dropped
  /// them, so any capture -> restore round-trip silently lost the chef's prep
  /// summary. Empty is a valid, honest value (an item with none configured, or
  /// a record written before this field existed) — it is never re-read from the
  /// live menu at restore time, which would substitute today's configuration
  /// for the one the cashier actually ordered against.
  final List<KitchenPrepComponent> prepComponents;

  /// MENU-ORDER-001 (Codex #8/#9): durable serialization — carries the stable
  /// lineId, ranks, modifiers, and note through a restart so a recovered order
  /// keeps its line identity and still prints in menu order. Money is integer
  /// minor (D-007).
  Map<String, Object?> toJson() => <String, Object?>{
    if (lineId != null) 'line_id': lineId,
    'menu_item_id': menuItemId,
    'name': name,
    'base_price_minor': basePriceMinor,
    'quantity': quantity,
    if (modifiers.isNotEmpty)
      'modifiers': [for (final m in modifiers) m.toJson()],
    if (note != null) 'note': note,
    if (categoryDisplayOrder != 0)
      'category_display_order': categoryDisplayOrder,
    if (itemDisplayOrder != 0) 'item_display_order': itemDisplayOrder,
    // PARKED-CARTS-001: omitted when empty, so a record that carries no prep
    // stays byte-identical to one written before this field existed.
    if (prepComponents.isNotEmpty)
      'prep_components': [for (final p in prepComponents) p.toJson()],
  };

  static CartDraftLine fromJson(Map<String, Object?> json) {
    int intOf(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
    final rawMods = json['modifiers'];
    final rawNote = json['note'];
    return CartDraftLine(
      lineId: json['line_id']?.toString(),
      menuItemId: (json['menu_item_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      basePriceMinor: intOf(json['base_price_minor']),
      quantity: json['quantity'] == null ? 1 : intOf(json['quantity']),
      modifiers: <SelectedModifier>[
        if (rawMods is List)
          for (final m in rawMods)
            if (m is Map) SelectedModifier.fromJson(m.cast<String, Object?>()),
      ],
      note: rawNote == null ? null : rawNote.toString(),
      categoryDisplayOrder: intOf(json['category_display_order']),
      itemDisplayOrder: intOf(json['item_display_order']),
      // PARKED-CARTS-001: absent on an older record -> empty. The shared
      // tolerant parser drops blank-name / non-positive rows rather than
      // showing the chef a bogus count.
      prepComponents: parseKitchenPrepComponents(json['prep_components']),
    );
  }
}

class CartController extends Notifier<CartViewState> {
  late Cart _cart;
  int _lineSeq = 0;
  int _orderSeq = 0;
  SubmittedOrderView? _submittedOrder;

  /// PSC-001C cart-safety: the frozen addition attempt currently owning the
  /// cart, or null when the cart is freely editable. While held, EVERY normal
  /// mutation entry point refuses ([CartMutationResult.lockedByAddition]) —
  /// the frozen payload and the visible cart must stay identical, and no
  /// unrelated line may be introduced only to be cleared on reconciliation.
  CartLockOwner? _lockOwner;

  bool get _locked => _lockOwner != null;

  /// Selected modifier snapshots per line id (the domain [Cart] predates
  /// modifiers; the app carries them alongside — D-008 snapshots).
  final Map<String, List<SelectedModifier>> _lineModifiers = {};

  /// Optional cashier note per line id ("بدون بصل") — carried alongside like
  /// the modifiers; sent as the payload item's `notes`.
  final Map<String, String> _lineNotes = {};

  /// MENU-ORDER-001: the item's Dashboard print-order ranks per line id
  /// (categoryDisplayOrder, itemDisplayOrder), captured from the DemoMenuItem at
  /// add time and carried onto CartLineView + SubmittedLineView so every POS
  /// print surface orders items into Dashboard-configured order. Non-money.
  final Map<String, (int, int)> _lineDisplayOrders = {};

  /// PRINT-STARTUP-REPRINT-001 (Defect 2): the item's PER-UNIT kitchen prep
  /// components per line id, captured from the DemoMenuItem at ADD time — the
  /// same order-time snapshot the outbox payload carries (D-008) — and carried
  /// onto SubmittedLineView so a MANUAL kitchen reprint can aggregate the same
  /// whole-order counts as the automatic ticket. Never re-read from the live
  /// menu at reprint time. Non-money.
  final Map<String, List<KitchenPrepComponent>> _linePrep = {};

  /// The ACTIVE menu currency (real backend currency in real mode; the demo
  /// constant otherwise). Read at cart (re)creation so price snapshots and the
  /// cart currency always agree with the menu being sold from (D-007/D-008).
  String _activeCurrency() =>
      ref.read(posMenuProvider).valueOrNull?.currencyCode ?? kDemoCurrencyCode;

  Cart _freshCart() => Cart(
    orderId: 'demo-order',
    organizationId: 'demo-org',
    restaurantId: 'demo-restaurant',
    branchId: 'demo-branch',
    currencyCode: _activeCurrency(),
  );

  @override
  CartViewState build() {
    _cart = _freshCart();
    _submittedOrder = null;
    _lineModifiers.clear();
    _lineNotes.clear();
    _lineDisplayOrders.clear();
    _linePrep.clear();
    _lockOwner = null;
    return CartViewState.fromCart(_cart);
  }

  // -------------------------------------------------------------------------
  // PSC-001C cart-safety — the addition mutation lock (owner-token, never a
  // bare boolean). Acquired atomically with the payload freeze by the
  // AdditionController; released ONLY by the matching owner (explicit cancel
  // of a retryable failure, or the privileged post-reconciliation clear).
  // -------------------------------------------------------------------------

  /// Acquires the mutation lock for [owner]. Fails (false, nothing changes)
  /// when a DIFFERENT attempt already owns the cart; re-acquiring with the
  /// SAME identity is an idempotent success (a retry of the frozen attempt).
  bool lockForAddition(CartLockOwner owner) {
    final current = _lockOwner;
    if (current != null && !owner.matches(current)) return false;
    _lockOwner = owner;
    _emit();
    return true;
  }

  /// Releases the lock with the matching [owner] token, leaving the cart
  /// lines INTACT (an explicit cancel keeps the cashier's work). FAIL CLOSED:
  /// false — with zero state change — when nothing is locked OR the token
  /// does not exactly match; true only proves the caller owned the lock.
  /// Absence of a lock is never treated as privileged authorization.
  bool unlockForAddition(CartLockOwner owner) {
    final current = _lockOwner;
    if (current == null || !owner.matches(current)) return false;
    _lockOwner = null;
    _emit();
    return true;
  }

  /// READ-ONLY exact-owner check: whether [owner] — all three token fields —
  /// currently holds the mutation lock. False when nothing is locked. Mutates
  /// nothing; the reconciliation verifies ownership through this BEFORE
  /// installing any fresh authoritative detail.
  bool ownsAdditionLock(CartLockOwner owner) => owner.matches(_lockOwner);

  /// PRIVILEGED owner-token cleanup: clears the submitted cart state AND
  /// releases the lock in one step — only for the matching [owner], after the
  /// authoritative reconciliation verified the addition. Fails closed (false,
  /// cart and lock untouched) on any mismatch: a stale attempt-A callback can
  /// never clear a cart owned by attempt B.
  bool clearForAddition(CartLockOwner owner) {
    final current = _lockOwner;
    if (current == null || !owner.matches(current)) return false;
    _lockOwner = null;
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    _emit();
    return true;
  }

  /// Adds [item] to the cart. If a PLAIN line (no modifiers) for the same menu
  /// item already exists, its quantity is incremented instead of adding a
  /// duplicate line. Adding an item while a confirmation is showing dismisses
  /// it and starts a fresh order.
  CartMutationResult addItem(DemoMenuItem item) {
    if (_locked) return CartMutationResult.lockedByAddition;
    _submittedOrder = null;
    // An EMPTY cart re-binds to the active menu currency before its first line
    // (the menu can finish loading after the cart was first built).
    if (_cart.lines.isEmpty && _cart.currencyCode != _activeCurrency()) {
      _cart = _freshCart();
    }
    final existing = _lineForMenuItem(item.id);
    if (existing != null &&
        !(_lineModifiers[existing.lineId]?.isNotEmpty ?? false) &&
        !_lineNotes.containsKey(existing.lineId)) {
      _cart.changeQuantity(existing.lineId, existing.quantity + 1);
    } else {
      final lineId = 'line-${_lineSeq++}';
      _cart.addLine(
        CartLine.snapshot(
          lineId: lineId,
          menuItemId: item.id,
          itemNameSnapshot: item.name,
          basePriceMinorSnapshot: item.priceMinor,
          currencyCodeSnapshot: _cart.currencyCode,
        ),
      );
      _lineDisplayOrders[lineId] = (
        item.categoryDisplayOrder,
        item.itemDisplayOrder,
      );
      _linePrep[lineId] = item.prepComponents;
    }
    _emit();
    return CartMutationResult.applied;
  }

  /// Adds a CONFIGURED [item] with its selected [modifiers] and optional
  /// cashier [note] as its OWN line (never merged — each configured item is
  /// priced/kitchen-routed on its own; the RF-052 formula counts each
  /// modifier's delta × its quantity once per line).
  CartMutationResult addItemWithModifiers(
    DemoMenuItem item,
    List<SelectedModifier> modifiers, {
    String? note,
  }) {
    if (_locked) return CartMutationResult.lockedByAddition;
    final trimmedNote = note?.trim();
    final hasNote = trimmedNote != null && trimmedNote.isNotEmpty;
    if (modifiers.isEmpty && !hasNote) return addItem(item);
    _submittedOrder = null;
    if (_cart.lines.isEmpty && _cart.currencyCode != _activeCurrency()) {
      _cart = _freshCart();
    }
    final lineId = 'line-${_lineSeq++}';
    _cart.addLine(
      CartLine.snapshot(
        lineId: lineId,
        menuItemId: item.id,
        itemNameSnapshot: item.name,
        basePriceMinorSnapshot: item.priceMinor,
        currencyCodeSnapshot: _cart.currencyCode,
      ),
    );
    _lineModifiers[lineId] = List.unmodifiable(modifiers);
    if (hasNote) _lineNotes[lineId] = trimmedNote;
    _lineDisplayOrders[lineId] = (
      item.categoryDisplayOrder,
      item.itemDisplayOrder,
    );
    _linePrep[lineId] = item.prepComponents;
    _emit();
    return CartMutationResult.applied;
  }

  /// TABLET-UX-001 (A): replaces the selected [modifiers] and optional [note] on
  /// an EXISTING cart line, in place — never a new/duplicate line. Preserves the
  /// line's position, quantity, base price snapshot, and currency; only its
  /// modifier snapshots + note change, so the line total recomputes through the
  /// same RF-052 formula. No-op when [lineId] is gone. Used by the cart's Edit
  /// action, which reopens the customization sheet prefilled with this line.
  CartMutationResult updateLineModifiers(
    String lineId,
    List<SelectedModifier> modifiers, {
    String? note,
  }) {
    if (_locked) return CartMutationResult.lockedByAddition;
    if (_lineById(lineId) == null) return CartMutationResult.applied;
    if (modifiers.isEmpty) {
      _lineModifiers.remove(lineId);
    } else {
      _lineModifiers[lineId] = List.unmodifiable(modifiers);
    }
    final trimmedNote = note?.trim();
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      _lineNotes[lineId] = trimmedNote;
    } else {
      _lineNotes.remove(lineId);
    }
    _emit();
    return CartMutationResult.applied;
  }

  /// MONEY-MODIFIER-PRICING-INTEGRITY-001 — updates ONLY the cashier note on
  /// [lineId], never its modifier snapshots.
  ///
  /// The cart's Edit action falls back to a note-only sheet when the live menu
  /// cannot supply authoritative modifier groups. Routing that fallback through
  /// [updateLineModifiers] meant confirming it replaced the stored snapshots
  /// with whatever the (empty) sheet could resolve — silently deleting a paid
  /// modifier and re-pricing the line down to base. This entry point cannot do
  /// that: it never touches `_lineModifiers`, so a note edit is money-safe by
  /// CONSTRUCTION rather than by the caller remembering to pass the old list
  /// back in.
  CartMutationResult updateLineNote(String lineId, String? note) {
    if (_locked) return CartMutationResult.lockedByAddition;
    if (_lineById(lineId) == null) return CartMutationResult.applied;
    final trimmedNote = note?.trim();
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      _lineNotes[lineId] = trimmedNote;
    } else {
      _lineNotes.remove(lineId);
    }
    _emit();
    return CartMutationResult.applied;
  }

  /// Increases the quantity of [lineId] by one.
  CartMutationResult increaseQuantity(String lineId) {
    if (_locked) return CartMutationResult.lockedByAddition;
    final line = _lineById(lineId);
    if (line == null) return CartMutationResult.applied;
    _cart.changeQuantity(lineId, line.quantity + 1);
    _emit();
    return CartMutationResult.applied;
  }

  /// Decreases the quantity of [lineId] by one; removes the line at quantity 1.
  CartMutationResult decreaseQuantity(String lineId) {
    if (_locked) return CartMutationResult.lockedByAddition;
    final line = _lineById(lineId);
    if (line == null) return CartMutationResult.applied;
    if (line.quantity <= 1) {
      _cart.removeLine(lineId);
    } else {
      _cart.changeQuantity(lineId, line.quantity - 1);
    }
    _emit();
    return CartMutationResult.applied;
  }

  /// Removes the line [lineId] entirely.
  CartMutationResult removeLine(String lineId) {
    if (_locked) return CartMutationResult.lockedByAddition;
    if (_lineById(lineId) == null) return CartMutationResult.applied;
    _cart.removeLine(lineId);
    _lineModifiers.remove(lineId);
    _lineNotes.remove(lineId);
    _emit();
    return CartMutationResult.applied;
  }

  /// Clears the cart by rebuilding a fresh draft (the domain Cart has no
  /// `clear()`); line ids keep advancing so they stay unique. While a frozen
  /// addition attempt owns the cart this REFUSES — the privileged
  /// [clearForAddition] is the only clear a locked cart accepts.
  CartMutationResult clear() {
    if (_locked) return CartMutationResult.lockedByAddition;
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    // Abandoning the cart ends any in-progress correction: a later unrelated
    // submit must not resolve the previously-restored recovery.
    ref.read(posActiveCorrectionSourceProvider.notifier).clear();
    _emit();
    return CartMutationResult.applied;
  }

  /// PILOT-OPERATIONS-CORRECTIONS-001: capture the current cart as an immutable
  /// draft snapshot BEFORE a submit clears it, so a permanently-rejected submit
  /// (item_unavailable) can be RESTORED for deliberate correction rather than
  /// forcing the cashier to re-key the whole order.
  CartDraftSnapshot captureDraft() => CartDraftSnapshot(
    currencyCode: _cart.currencyCode,
    lines: <CartDraftLine>[
      for (final line in _cart.lines)
        CartDraftLine(
          // MENU-ORDER-001 (Codex #2/#3): carry the STABLE line id so a restored
          // draft keeps its original line identity.
          lineId: line.lineId,
          menuItemId: line.menuItemId,
          name: line.itemNameSnapshot,
          basePriceMinor: line.basePriceMinorSnapshot,
          quantity: line.quantity,
          modifiers: _lineModifiers[line.lineId] ?? const <SelectedModifier>[],
          note: _lineNotes[line.lineId],
          // MENU-ORDER-001 (Codex): carry the line's Dashboard menu ranks onto the
          // draft so a restored (item_unavailable) cart still prints in menu order.
          categoryDisplayOrder: _lineDisplayOrders[line.lineId]?.$1 ?? 0,
          itemDisplayOrder: _lineDisplayOrders[line.lineId]?.$2 ?? 0,
          // PARKED-CARTS-001: carry the ORDER-TIME kitchen prep snapshot too.
          // Without it every draft round-trip dropped the chef's prep summary.
          prepComponents:
              _linePrep[line.lineId] ?? const <KitchenPrepComponent>[],
        ),
    ],
  );

  /// PILOT-OPERATIONS-CORRECTIONS-001: rebuild the cart from a [CartDraftSnapshot]
  /// (products, quantities, modifiers, notes). Idempotent replacement — it always
  /// REPLACES the current cart, so a repeated "Back to cart" cannot duplicate
  /// lines. Line ids keep advancing so they stay unique.
  CartMutationResult restoreDraft(CartDraftSnapshot draft) {
    if (_locked) return CartMutationResult.lockedByAddition;
    _cart = Cart(
      orderId: 'demo-order',
      organizationId: 'demo-org',
      restaurantId: 'demo-restaurant',
      branchId: 'demo-branch',
      currencyCode: draft.currencyCode,
    );
    _lineModifiers.clear();
    _lineNotes.clear();
    _lineDisplayOrders.clear();
    _linePrep.clear();
    for (final l in draft.lines) {
      // MENU-ORDER-001 (Codex #2/#3): reuse the persisted STABLE line id so
      // edits/removals target the original line and a re-restore never
      // duplicates; a legacy record with no id mints a fresh one. Keep _lineSeq
      // AHEAD of any restored `line-N` so a later add can never collide with it.
      final lineId = l.lineId ?? 'line-${_lineSeq++}';
      final seqMatch = RegExp(r'^line-(\d+)$').firstMatch(lineId);
      if (seqMatch != null) {
        final n = int.tryParse(seqMatch.group(1)!) ?? -1;
        if (n >= _lineSeq) _lineSeq = n + 1;
      }
      _cart.addLine(
        CartLine.snapshot(
          lineId: lineId,
          menuItemId: l.menuItemId,
          itemNameSnapshot: l.name,
          basePriceMinorSnapshot: l.basePriceMinor,
          currencyCodeSnapshot: draft.currencyCode,
        ),
      );
      if (l.quantity > 1) _cart.changeQuantity(lineId, l.quantity);
      if (l.modifiers.isNotEmpty) {
        _lineModifiers[lineId] = List.unmodifiable(l.modifiers);
      }
      final note = l.note;
      if (note != null && note.isNotEmpty) _lineNotes[lineId] = note;
      // MENU-ORDER-001 (Codex): restore the Dashboard menu ranks so the corrected
      // resubmit prints in the same menu order the original attempt would have.
      _lineDisplayOrders[lineId] = (l.categoryDisplayOrder, l.itemDisplayOrder);
      // PARKED-CARTS-001: repopulate the ORDER-TIME prep snapshot the draft
      // carries. It is deliberately NOT re-read from the live menu — a restored
      // cart must keep the configuration it was ordered against, and a record
      // written before the field existed honestly restores none.
      if (l.prepComponents.isNotEmpty) {
        _linePrep[lineId] = List.unmodifiable(l.prepComponents);
      }
    }
    _submittedOrder = null;
    _emit();
    return CartMutationResult.applied;
  }

  /// Locally "submits" the current cart (RF-101): materializes an in-memory
  /// [LocalOrder] from the cart, snapshots it into a [SubmittedOrderView] with a
  /// local/provisional demo number, then empties the cart so the confirmation
  /// stands on its own. No backend, RPC, payment, kitchen, printer, or
  /// persistence — purely a visible demo confirmation. No-op on an empty cart.
  CartMutationResult submitOrder({
    OrderType orderType = OrderType.takeaway,
    String? tableLabel,
    String? customerName,
    String? customerPhone,
    String? orderNumber,
    String? outboxEntryId,
    String? localOperationId,
    String? orderId,
    int taxTotalMinor = 0,
    int taxRateBp = 0,
  }) {
    if (_locked) return CartMutationResult.lockedByAddition;
    if (_cart.isEmpty) return CartMutationResult.applied;
    final order = LocalOrder.submitFromCart(_cart, orderType: orderType);
    _orderSeq++;
    // RF-115: the outbox controller is the numbering authority for the real
    // submit flow; fall back to a local number for the RF-101 in-memory path.
    final resolvedNumber =
        orderNumber ?? 'DEMO-${_orderSeq.toString().padLeft(4, '0')}';
    // Line totals mirror the RF-052 server formula (each modifier delta
    // counted × its own quantity, once per line).
    var modifiersTotal = 0;
    var linePosition = 0;
    final lines = <SubmittedLineView>[];
    for (final item in order.items) {
      linePosition++;
      // LocalOrderItem.orderItemId carries the source cart line id.
      final mods =
          _lineModifiers[item.orderItemId] ?? const <SelectedModifier>[];
      final modSum = mods.fold<int>(0, (sum, m) => sum + m.totalDeltaMinor);
      modifiersTotal += modSum;
      // MENU-ORDER-001: carry the item's Dashboard ranks + its 1-based cart
      // position so every POS surface (receipt, kitchen ticket) orders items
      // into the SAME Dashboard-configured sequence the KDS + server reprint use.
      final dispOrder = _lineDisplayOrders[item.orderItemId];
      lines.add(
        SubmittedLineView(
          name: item.itemNameSnapshot,
          quantity: item.quantity,
          lineTotalMinor: item.lineTotalMinorPreview + modSum,
          currencyCode: item.currencyCodeSnapshot,
          // `name ×N` snapshots — quantity rides the display string so the
          // confirmation/receipt/print paths all show it unchanged.
          modifiers: [for (final m in mods) m.displayName],
          note: _lineNotes[item.orderItemId],
          categoryDisplayOrder: dispOrder?.$1 ?? 0,
          itemDisplayOrder: dispOrder?.$2 ?? 0,
          linePosition: linePosition,
          // PRINT-STARTUP-REPRINT-001: the ORDER-TIME kitchen count snapshots,
          // so a manual reprint aggregates the SAME totals the automatic
          // ticket printed. Meat is pre-multiplied by the option's units,
          // exactly as kdsTicketViewFromCartLines does.
          kitchenMeats: kitchenMeatSnapshots(mods),
          prepComponents:
              _linePrep[item.orderItemId] ?? const <KitchenPrepComponent>[],
        ),
      );
    }
    _submittedOrder = SubmittedOrderView(
      orderNumber: resolvedNumber,
      orderType: order.orderType,
      tableLabel: tableLabel,
      customerName: customerName,
      customerPhone: customerPhone,
      outboxEntryId: outboxEntryId,
      localOperationId: localOperationId,
      orderId: orderId,
      currencyCode: order.currencyCode,
      subtotalMinor: order.subtotalMinorPreview + modifiersTotal,
      // RF-117: tax computed at submit from the branch setting (0 when disabled).
      taxTotalMinor: taxTotalMinor,
      taxRateBp: taxRateBp,
      lines: lines,
    );
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    _lineDisplayOrders.clear();
    _linePrep.clear();
    _emit();
    return CartMutationResult.applied;
  }

  /// Finding 1 (PILOT-OPERATIONS-CORRECTIONS-001): build a [SubmittedOrderView] from a
  /// previously-captured [CartDraftSnapshot] WITHOUT mutating the live cart. This is used
  /// only when a submit result lands AFTER a PIN handover on the same till: the ORIGINAL
  /// session's recent-orders row is materialized from ITS captured draft, so the CURRENT
  /// session's cart, setup, and confirmation are never touched. The money arithmetic
  /// mirrors [submitOrder] EXACTLY — integer minor units, base price × line quantity plus
  /// each modifier delta counted once per line (D-007) — so a recovered row shows the same
  /// figures it would have shown in its own session.
  SubmittedOrderView viewFromDraft({
    required CartDraftSnapshot draft,
    OrderType orderType = OrderType.takeaway,
    String? tableLabel,
    String? customerName,
    String? customerPhone,
    String? orderNumber,
    String? outboxEntryId,
    String? localOperationId,
    String? orderId,
    int taxTotalMinor = 0,
    int taxRateBp = 0,
  }) {
    var subtotal = 0;
    var linePosition = 0;
    final lines = <SubmittedLineView>[];
    for (final l in draft.lines) {
      linePosition++;
      final modSum = l.modifiers.fold<int>(
        0,
        (sum, m) => sum + m.totalDeltaMinor,
      );
      final lineTotal = l.basePriceMinor * l.quantity + modSum;
      subtotal += lineTotal;
      lines.add(
        SubmittedLineView(
          name: l.name,
          quantity: l.quantity,
          lineTotalMinor: lineTotal,
          currencyCode: draft.currencyCode,
          modifiers: [for (final m in l.modifiers) m.displayName],
          note: l.note,
          // MENU-ORDER-001 (Codex): the draft now carries the line's Dashboard menu
          // ranks, so a recovered row prints in the SAME menu order it would have in
          // its own session; line_position is the stable in-line tiebreak.
          categoryDisplayOrder: l.categoryDisplayOrder,
          itemDisplayOrder: l.itemDisplayOrder,
          linePosition: linePosition,
          // PRINT-STARTUP-REPRINT-001: the recovered draft carries its own
          // order-time modifier snapshots, so meat survives a restart.
          kitchenMeats: kitchenMeatSnapshots(l.modifiers),
          // PARKED-CARTS-001: the draft now carries its ORDER-TIME prep
          // snapshot as well, so a recovered row's manual kitchen reprint
          // aggregates the real counts instead of silently omitting them. Still
          // never re-read from the current catalog: a record written before the
          // field existed honestly yields none.
          prepComponents: l.prepComponents,
        ),
      );
    }
    return SubmittedOrderView(
      orderNumber: orderNumber ?? 'DEMO-0000',
      orderType: orderType,
      tableLabel: tableLabel,
      customerName: customerName,
      customerPhone: customerPhone,
      outboxEntryId: outboxEntryId,
      localOperationId: localOperationId,
      orderId: orderId,
      currencyCode: draft.currencyCode,
      subtotalMinor: subtotal,
      taxTotalMinor: taxTotalMinor,
      taxRateBp: taxRateBp,
      lines: lines,
    );
  }

  /// Updates the confirmed order's totals after an order-level discount is
  /// applied (RF-117 part C). In real mode the values are the
  /// SERVER-AUTHORITATIVE `discount_total_minor` (+ recomputed grand) from
  /// `apply_discount`; in demo mode they are computed locally with the same
  /// clamp. No-op when no order is being confirmed.
  void applyOrderDiscount({required int discountTotalMinor}) {
    final current = _submittedOrder;
    if (current == null) return;
    _submittedOrder = current.copyWith(discountTotalMinor: discountTotalMinor);
    _emit();
  }

  /// Dismisses the confirmation and returns to an empty cart (RF-101).
  CartMutationResult startNewOrder() {
    if (_locked) return CartMutationResult.lockedByAddition;
    _submittedOrder = null;
    _cart = _freshCart();
    _lineModifiers.clear();
    _lineNotes.clear();
    _lineDisplayOrders.clear();
    _linePrep.clear();
    // A fresh order ends any in-progress correction (see [clear]).
    ref.read(posActiveCorrectionSourceProvider.notifier).clear();
    _emit();
    return CartMutationResult.applied;
  }

  CartLine? _lineById(String lineId) {
    for (final line in _cart.lines) {
      if (line.lineId == lineId) return line;
    }
    return null;
  }

  CartLine? _lineForMenuItem(String menuItemId) {
    for (final line in _cart.lines) {
      if (line.menuItemId == menuItemId) return line;
    }
    return null;
  }

  void _emit() => state = CartViewState.fromCart(
    _cart,
    submittedOrder: _submittedOrder,
    lineModifiers: _lineModifiers,
    lineNotes: _lineNotes,
    lineDisplayOrders: _lineDisplayOrders,
    lockedByAddition: _locked,
  );
}

/// Provider for the in-memory POS cart controller (demo-only).
final cartControllerProvider = NotifierProvider<CartController, CartViewState>(
  CartController.new,
);

/// MENU-ORDER-001 (Codex, correction-ownership): the OWNER-BOUND active correction
/// source — the durable recovery the operator has RESTORED (Back to cart) into the
/// current cart and is now correcting. It is never a bare id: it carries the STABLE
/// ownership of the recovery it points at (the scope + worker), so a corrected submit
/// can revalidate that the CURRENT signed-in worker + POS scope still own it before it
/// links/clears anything. A stale source left by a departed worker (different
/// employeeProfileId) or a re-pair (different scopeKey) is therefore inert — it can
/// never attach to a later, unrelated order.
///
/// The ownership fields mirror `PosRecoveryBinding` (scopeKey + employeeProfileId) but
/// are stored as bare strings here — this file is a low-level leaf, and importing
/// `draft_recovery_controller` (which imports this file) would create a cycle. The
/// ephemeral pinSessionId is deliberately NOT part of ownership (D-006): a new one is
/// minted per login, so the SAME worker across a restart + re-login still owns it.
class ActiveCorrectionSource {
  const ActiveCorrectionSource({
    required this.sourceOutboxEntryId,
    required this.scopeKey,
    required this.employeeProfileId,
  });

  /// The outbox entry id (map key) of the source recovery being corrected.
  final String sourceOutboxEntryId;

  /// STABLE ownership of the source recovery (org/restaurant/branch/device scope).
  final String? scopeKey;

  /// STABLE authenticated worker id of the source recovery (D-006).
  final String? employeeProfileId;

  /// Whether the given CURRENT scope + worker exactly own this source — the only
  /// context allowed to link/resolve it. A different worker or scope can never.
  bool ownedBy({
    required String? scopeKey,
    required String? employeeProfileId,
  }) =>
      this.scopeKey == scopeKey && this.employeeProfileId == employeeProfileId;

  @override
  bool operator ==(Object other) =>
      other is ActiveCorrectionSource &&
      other.sourceOutboxEntryId == sourceOutboxEntryId &&
      other.scopeKey == scopeKey &&
      other.employeeProfileId == employeeProfileId;

  @override
  int get hashCode =>
      Object.hash(sourceOutboxEntryId, scopeKey, employeeProfileId);

  @override
  String toString() =>
      'ActiveCorrectionSource($sourceOutboxEntryId, scope:$scopeKey, '
      'worker:$employeeProfileId)';
}

/// The current OWNER-BOUND active correction source, or null when the cart is not
/// correcting a restored recovery. Set by [PosRecoveryCoordinator.restore] (only when
/// the current worker+scope own the recovery); consumed by `submitOrderFromCart` to
/// durably LINK the corrected resubmit back to its source recovery BEFORE dispatch (so
/// authoritative acceptance clears exactly that source, never an orphan). Cleared when
/// the cart is cleared / a new order is started / the worker signs out / the accepted
/// source is reconciled — so an UNRELATED later submit never re-links a stale source.
/// In-memory only — re-established on each restore, so a crash simply re-derives it; NO
/// pin/token/secret. Lives here (not draft_recovery_controller) to avoid an import cycle.
class PosActiveCorrectionSource extends Notifier<ActiveCorrectionSource?> {
  @override
  ActiveCorrectionSource? build() => null;

  void set(ActiveCorrectionSource? source) => state = source;

  void clear() => state = null;
}

final posActiveCorrectionSourceProvider =
    NotifierProvider<PosActiveCorrectionSource, ActiveCorrectionSource?>(
      PosActiveCorrectionSource.new,
    );
