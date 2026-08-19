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
/// option the cashier took (extra cheese ×2). The total formula the server
/// recomputes is the CORRECTED per-unit one (MONEY-PRICING-FORMULA-002A):
/// `line_total = qty × (unit + Σ(delta × modifier_qty)) − discount`.
/// The surcharge belongs to the per-unit price, so it is charged once per ITEM
/// UNIT — the old `qty × unit + Σ` under-charged every extra unit.
class SelectedModifier {
  const SelectedModifier({
    required this.optionId,
    required this.groupName,
    required this.optionName,
    required this.priceDeltaMinor,
    this.quantity = 1,
    this.kitchenMeat,
    this.modifierGroupId,
  });

  final String optionId;

  /// MONEY-EDIT-INTEGRITY-002C (Codex Blocker 4) — the STABLE id of the
  /// modifier group this option was selected from (`PosModifierGroup.id`, i.e.
  /// the server `modifiers.id` the POS menu payload serves).
  ///
  /// LOCAL EDIT-SAFETY METADATA ONLY. It never reaches the order wire, the
  /// `order_item_modifiers` schema, an RPC argument, a receipt, a kitchen
  /// ticket or a KDS payload: those are built from a SEPARATE
  /// `OrderSubmissionModifier` whose `toJson` writes its own fixed key set, so
  /// the wire shape and the server's content fingerprint are untouched.
  ///
  /// Null on a LEGACY record written before this field existed. That absence is
  /// tolerated — rejecting proven-valid history would be a worse defect than
  /// the one this fixes — and resolved fail-closed at edit time instead (see
  /// the modifier sheet). A group id is only ever WRITTEN after a healthy,
  /// intentional edit where the current group→option relationship was proven.
  final String? modifierGroupId;

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
    // MONEY-EDIT-INTEGRITY-002C: emitted ONLY when known, so a record that
    // carries no proven group id stays byte-identical to one written before
    // this field existed — the same additive shape `kitchen_meat` uses. This
    // is LOCAL persistence (cart draft / parked cart / draft recovery); the
    // order wire is built from `OrderSubmissionModifier`, not from here.
    if (modifierGroupId != null) 'modifier_group_id': modifierGroupId,
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

    // MONEY-LOCAL-ATOMICITY-003A — an IDENTITY is exact or it is corrupt.
    //
    // This used to be `(json['option_id'] ?? '').toString()`, so an int, a
    // bool, a double, a list or a map all became plausible option ids and only
    // emptiness was caught. An unidentifiable option cannot be re-priced,
    // re-sent or reasoned about — and a fabricated one is worse, because it
    // looks resolvable.
    //
    // Stored UNTRIMMED, deliberately. Every consumer compares ids byte-exactly
    // (the sheet's group match, the domain's line lookup, the side-map keys), so
    // trimming here would silently re-point a stored selection at a live group
    // and re-price it — exactly the class of defect 002C closed.
    final rawOptionId = json['option_id'];
    if (rawOptionId is! String || rawOptionId.trim().isEmpty) {
      throw FormatException(
        'modifier option_id is not a non-blank string: '
        '${rawOptionId == null ? 'absent/null' : rawOptionId.runtimeType}',
      );
    }
    final optionId = rawOptionId;

    /// A DISPLAY snapshot: type-strict, but blank is legitimate history — the
    /// menu parse can produce an empty option name, so requiring non-blank here
    /// would quarantine a real cashier's parked cart.
    String requireDisplayName(String key) {
      final raw = json[key];
      if (raw is String) return raw;
      throw FormatException(
        'modifier $key is not a string: '
        '${raw == null ? 'absent/null' : raw.runtimeType}',
      );
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
    // MONEY-EDIT-INTEGRITY-002C — strict, under the SAME 002B corruption
    // contract as the money above. ABSENT is the one legacy allowance (a record
    // written before the field existed); a value that is PRESENT must be an
    // exact non-blank String. Absence is distinguished from an explicit null
    // via containsKey, so a corrupt null can never masquerade as legacy — that
    // is precisely the coercion that would hand a moved option a free pass.
    final String? modifierGroupId;
    if (!json.containsKey('modifier_group_id')) {
      modifierGroupId = null;
    } else {
      final raw = json['modifier_group_id'];
      if (raw is! String || raw.trim().isEmpty) {
        throw FormatException(
          'modifier modifier_group_id is not a non-blank string: '
          '${raw == null ? 'null' : raw.runtimeType}',
        );
      }
      modifierGroupId = raw;
    }
    return SelectedModifier(
      optionId: optionId,
      modifierGroupId: modifierGroupId,
      groupName: requireDisplayName('group_name'),
      optionName: requireDisplayName('option_name'),
      priceDeltaMinor: priceDeltaMinor,
      quantity: quantity,
      kitchenMeat: KitchenMeat.tryFromJson(json['kitchen_meat']),
    );
  }
}

/// MONEY-PRICING-FORMULA-002A — THE ONE client pricing formula.
///
/// A cart line is N identical FULLY CONFIGURED items, so a modifier surcharge is
/// part of the per-unit price and is charged once per ITEM UNIT:
///
///   configuredUnitAmountMinor = basePriceMinor + Σ(priceDeltaMinor × modifierQty)
///   lineTotalMinor            = configuredUnitAmountMinor × itemQuantity
///
/// This is the authoritative contract in `docs/MONEY_AND_TAX_SPEC.md` §9:157,
/// whose worked example §9.1:179 reads "Line A per-unit = 4500 + 700 = 5200;
/// × 2 = 10400". §9:155 requires the server RPC and every offline client to
/// follow it IDENTICALLY.
///
/// It replaces four independently-maintained copies of `base × itemQty + Σ`,
/// which added the surcharge once per LINE and so under-charged every extra
/// unit — while the kitchen already multiplied meat and prep by item quantity
/// (`aggregateOrderKitchenCounts`), cooking N upgraded meals for one upgrade's
/// money. The two rules agree at quantity 1, which is why it survived.
///
/// Integer minor units only (D-007). Keep this the ONLY implementation: the
/// payload still transmits the BARE unit price and the UNIT modifier delta, and
/// the server recombines them with the same rule.
int configuredUnitAmountMinor(
  int basePriceMinor,
  Iterable<SelectedModifier> modifiers,
) {
  var total = basePriceMinor;
  for (final m in modifiers) {
    total += m.totalDeltaMinor;
  }
  return total;
}

/// [configuredUnitAmountMinor] × [quantity] — a line's total BEFORE any line
/// discount, which the existing discount/tax ordering then consumes unchanged.
int configuredLineTotalMinor({
  required int basePriceMinor,
  required Iterable<SelectedModifier> modifiers,
  required int quantity,
}) => configuredUnitAmountMinor(basePriceMinor, modifiers) * quantity;

/// PRINT-STARTUP-REPRINT-001 (Defect 2) — the SINGLE place selected modifiers
/// become kitchen meat contributions, so the automatic ticket, the stored order
/// snapshot and the manual reprint can never drift apart.
///
/// Each option's owner-configured [KitchenMeat] is multiplied by the UNITS of
/// that option (`extra meat ×2` => two patties); the item quantity is applied
/// later by `aggregateOrderKitchenCounts`. Options with no configured meat, or
/// with non-positive units, contribute nothing — so the result is deliberately
/// NOT index-aligned with the modifier display list. Money-free (D-007).
/// 018 (Codex HIGH #1) — the AUTHORITATIVE lookup into a submitted operation's
/// prep snapshot.
///
/// `map?[id] ?? legacy` conflated two different situations:
///
///  * `map == null` — no authoritative snapshot was supplied at all (the legacy
///    in-memory/demo path), so falling back to the add-to-cart capture is right;
///  * `map != null` but carrying no entry for the item — the authoritative
///    answer IS "this item has no preparation resources". An owner who removed
///    every resource between add-to-cart and submit produces exactly this, and
///    the old expression silently resurrected the deleted add-time prep.
///
/// Returning `null` ONLY for the first case keeps the two distinguishable at the
/// call site: a non-null map always answers, with an empty list when it has no
/// entry, and the legacy fallback is unreachable.
List<KitchenPrepComponent>? submittedPrepForItem(
  Map<String, List<KitchenPrepComponent>>? submittedPrepByItemId,
  String menuItemId,
) {
  if (submittedPrepByItemId == null) return null;
  return submittedPrepByItemId[menuItemId] ?? const <KitchenPrepComponent>[];
}

/// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 — the POS adapter over the shared
/// [classifyPrepComponents]: the item's configured prep [components] resolved
/// against the option ids actually selected on THIS line.
///
/// Presence-based by construction — a `Set` of ids — so `Cheese ×2` classifies
/// the resource exactly once and never doubles the owner-configured resource
/// quantity. Called at every site where a line's prep snapshot is built (order
/// wire, addition wire, direct kitchen print, parked draft, submitted view), so
/// all five agree; `kitchen_prep_modifier_split_test.dart` pins that parity.
List<KitchenPrepComponent> classifiedPrepForLine(
  List<KitchenPrepComponent> components,
  Iterable<SelectedModifier> modifiers,
) => classifyPrepComponents(components, <String>{
  for (final m in modifiers)
    if (m.quantity > 0) m.optionId,
});

List<KitchenMeat> kitchenMeatSnapshots(Iterable<SelectedModifier> modifiers) {
  // KITCHEN-MODIFIER-PREP-CLASSIFIER-019: the option ids actually selected on
  // THIS line — the order-time answer for every classifier configured on a
  // contributing option. PRESENCE-based, so a classifier taken twice (or with a
  // quantity above one) still classifies once and never multiplies the
  // contribution.
  final selectedOptionIds = <String>{
    for (final m in modifiers)
      if (m.quantity > 0) m.optionId,
  };
  return [
    for (final modifier in modifiers)
      if (modifier.kitchenMeat case final meat?)
        if (modifier.quantity > 0)
          // The option's own units still scale ITS contribution (extra patty ×2
          // = two patties); the classifier is applied on top, unscaled.
          _resolvedMeat(meat.scaledBy(modifier.quantity), selectedOptionIds),
  ];
}

/// Applies the ORDER-TIME classification answer to one already-scaled
/// contribution. A contribution with no configured classifier is returned
/// unchanged — the historical unsplit behaviour, byte-identical on the wire.
///
/// The link itself was already proven against the item's own options at the
/// menu boundary ([resolveTrustedMeatClassifier]); this only answers
/// with-or-without.
KitchenMeat _resolvedMeat(KitchenMeat meat, Set<String> selectedOptionIds) =>
    resolveOrderTimeMeatSnapshot(meat, selectedOptionIds) ?? meat;

/// 020 (Codex BLOCKER #1 / HIGH #2) — THE ONE authoritative wire snapshot
/// resolver, shared by the initial submit and the Add-items operation.
///
/// The wire previously carried `m.kitchenMeat` verbatim: MENU CONFIGURATION
/// (quantity, unit, classifier id/name) with **no order-time answer**, so
/// `classifier_selected` was absent from every submitted snapshot and both the
/// server and the KDS saw an unresolved contribution. The direct print looked
/// right only because it resolved locally.
///
/// The answer is PRESENCE-based over [selectedOptionIds] — the complete,
/// immutable set of option ids selected on THAT order line — so a classifier
/// taken once or four times gives the same result.
///
/// QUANTITY IS PER MODIFIER UNIT and is deliberately NOT scaled here: the wire
/// carries the option's per-unit contribution alongside its own
/// `quantity` field, and the KDS/aggregation applies the modifier units and the
/// order-item quantity exactly once downstream. Scaling here would double-count.
///
/// Returns null when [meat] is null (the option contributes nothing), so the
/// caller emits no snapshot at all — byte-identical to a pre-feature payload.
KitchenMeat? resolveOrderTimeMeatSnapshot(
  KitchenMeat? meat,
  Set<String> selectedOptionIds,
) {
  if (meat == null) return null;
  // A half-configured link cannot be labelled on a ticket; the contribution
  // keeps its ordinary unsplit line. The link's VALIDITY (same item, not self)
  // was already proven at the menu boundary — this only answers with/without.
  if (meat.classifierOptionId.isEmpty || meat.classifierOptionName.isEmpty) {
    return meat;
  }
  return meat.withClassifierSelected(
    selectedOptionIds.contains(meat.classifierOptionId),
  );
}

/// The complete, immutable set of option ids selected on ONE order line — the
/// authoritative input to [resolveOrderTimeMeatSnapshot]. A zero-unit selection
/// contributes no presence.
Set<String> selectedOptionIdsOf(Iterable<SelectedModifier> modifiers) =>
    <String>{
      for (final m in modifiers)
        if (m.quantity > 0) m.optionId,
    };

/// Immutable view of a single cart line for the POS UI.
///
/// Money fields are integer minor units (DECISION D-007); [unitPrice] and
/// [lineTotal] expose them as [Money] for type-safe display formatting.
/// [lineTotalMinor] uses the SERVER's formula, corrected in
/// MONEY-PRICING-FORMULA-002A: `qty × (unit + Σmodifiers)`.
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
/// MONEY-CODEX-FINAL-CLOSURE-005 (F1) — THE STARTUP HYDRATION GATE.
///
/// The durable Add-items journal is read from disk, so there is a window
/// between "the app is on screen" and "we know which orders carry an unresolved
/// amendment". Before 005 the cart was fully editable in that window: the
/// cashier could type lines no journal covered, and the attempt restored a
/// moment later would take ownership of — and, on reconciliation, destroy —
/// them. The same window let Add-items be entered for the very order that
/// already had a pending operation, which is how a second identity gets minted.
///
/// The affected order ids are not knowable until the read finishes, so the gate
/// is deliberately GLOBAL and deliberately brief. It is closed SYNCHRONOUSLY by
/// `AdditionController.build()` — before its first `await` — and opened once
/// hydration has either restored every actionable record or FAILED, in which
/// case it stays closed: an unreadable journal is not an empty one.
///
/// A PLAIN OBJECT, not provider state, for one specific reason: Riverpod forbids
/// a provider from modifying another provider during initialization, and the
/// gate must be observable from inside `AdditionController.build()`. Mutating a
/// shared object is not a provider write, so the ordering constraint disappears
/// and the guarantee — no editable window, ever — is kept.
///
/// Kept separate from [CartLockOwner] because it is not an ownership claim: no
/// attempt holds the cart yet. It only folds into `_locked`, so every normal
/// mutation entry point refuses through the ONE existing path while
/// `lockForAddition` / `unlockForAddition` / `ownsAdditionLock` /
/// `clearForAddition` keep reading the owner token alone — the restore must
/// still be able to take real ownership while the gate is shut.
class PosAdditionHydrationGate {
  bool _closed = false;

  /// Whether cart mutation is currently barred pending journal hydration.
  bool get isClosed => _closed;

  void close() => _closed = true;

  void open() => _closed = false;
}

/// One gate per container. Scoped like every other POS seam, so two containers
/// in a test (a simulated process restart) never share a gate.
final posAdditionHydrationGateProvider = Provider<PosAdditionHydrationGate>(
  (_) => PosAdditionHydrationGate(),
);

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

  /// MONEY-LOCAL-ATOMICITY-003A — the incoming draft could not be turned into a
  /// valid cart (a duplicate line id, a currency mismatch, an impossible
  /// quantity), so NOTHING was applied.
  ///
  /// This is a distinct outcome from [lockedByAddition]: the cart was free to
  /// change, and the change was refused on its own merits. The previous cart,
  /// its money and every side map are exactly as they were, and no state was
  /// emitted. Callers keep their source record (the parked entry, the durable
  /// recovery) so the cashier can try again or read it on a later build.
  invalidDraft,
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
          // MONEY-PRICING-FORMULA-002A: the modifier surcharge belongs to the
          // per-unit price, so it is multiplied by the item quantity like the
          // base is. `line.unitPriceMinor` is the BARE unit price here (the POS
          // carries modifier snapshots out-of-band in `lineModifiers`, never on
          // the domain CartLine), and it stays bare on the wire.
          final lineTotal = configuredLineTotalMinor(
            basePriceMinor: line.unitPriceMinor,
            modifiers: mods,
            quantity: line.quantity,
          );
          modifiersTotal += lineTotal - line.lineTotalMinor;
          final order = lineDisplayOrders[line.lineId];
          return CartLineView(
            lineId: line.lineId,
            menuItemId: line.menuItemId,
            name: line.itemNameSnapshot,
            quantity: line.quantity,
            unitPriceMinor: line.unitPriceMinor,
            lineTotalMinor: lineTotal,
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

  /// MONEY-LOCAL-DECODE-INTEGRITY-002B (Codex Blocker 2) — decode EXACTLY, or
  /// not at all.
  ///
  /// This previously reinterpreted a non-List `lines` as an empty cart and
  /// SKIPPED any element that was not a Map, so a truncated or partially
  /// corrupt record restored as a smaller — but entirely plausible — cart that
  /// the cashier would then charge. A draft we cannot read in full is a draft
  /// we are not entitled to re-price, so the whole snapshot is refused and the
  /// caller quarantines the raw record instead of silently reducing it.
  static CartDraftSnapshot fromJson(Map<String, Object?> json) {
    final rawLines = json['lines'];
    if (rawLines is! List) {
      throw FormatException(
        'cart draft lines must be a list, got '
        '${rawLines == null ? 'absent/null' : rawLines.runtimeType}',
      );
    }
    final lines = <CartDraftLine>[];
    // MONEY-LOCAL-ATOMICITY-003A: line ids must be UNIQUE within a draft. The
    // domain refuses a duplicate by throwing, so a record carrying one can
    // never become a cart — catching it here means the existing quarantine
    // seams receive it exactly like any other corruption, instead of the
    // restore path discovering it half-way through. No first-wins, no
    // last-wins, no silent regeneration: a cart we cannot rebuild faithfully
    // is not one we may rebuild approximately.
    final seenLineIds = <String>{};
    for (var i = 0; i < rawLines.length; i++) {
      final l = rawLines[i];
      if (l is! Map) {
        throw FormatException(
          'cart draft line $i is not an object: '
          '${l == null ? 'absent/null' : l.runtimeType}',
        );
      }
      final line = CartDraftLine.fromJson(l.cast<String, Object?>());
      final id = line.lineId;
      if (id != null && !seenLineIds.add(id)) {
        throw FormatException('cart draft has duplicate line_id "$id"');
      }
      lines.add(line);
    }
    // OPS-043 Phase 2 — CORRECTED CLAIM. This is not backward compatibility:
    // the WRITE of 'currency_code' landed in the same commit that created the
    // durable draft store (ab438933), so no persisted draft has ever lacked the
    // key. The default is retained only because a decode that threw here would
    // discard a cashier's recovered cart over a field the UI re-derives on the
    // next menu load. It is a last-resort floor, not a historical meaning — a
    // present-but-unreadable value is still corruption and still throws.
    final rawCurrency = json['currency_code'];
    final String currencyCode;
    if (rawCurrency == null) {
      currencyCode = 'ILS';
    } else if (rawCurrency is String && rawCurrency.trim().isNotEmpty) {
      currencyCode = rawCurrency;
    } else {
      throw FormatException(
        'cart draft currency_code is not a non-blank string: '
        '${rawCurrency.runtimeType}',
      );
    }
    return CartDraftSnapshot(currencyCode: currencyCode, lines: lines);
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

  /// MONEY-LOCAL-DECODE-INTEGRITY-002B (Codex Blocker 2) — strict, atomic.
  ///
  /// Every field this line is priced or identified by is read EXACTLY. The old
  /// decoder coerced through `int.tryParse('${v}') ?? 0`, so a corrupt
  /// `base_price_minor` became a free item, a corrupt `quantity` became 0, and
  /// a `modifiers` value that was not a list became "no modifiers" — each of
  /// them an UNDER-CHARGE that looked like a normal cart.
  ///
  /// The tolerated absences are evidence-based, not invented: [toJson] has,
  /// since the commit that introduced it (MENU-ORDER-001), ALWAYS written
  /// `menu_item_id`, `name`, `base_price_minor` and `quantity`, and
  /// conditionally omitted `line_id`, `modifiers`, `note`, the display orders
  /// and `prep_components`. So exactly those omissions are legitimate history;
  /// anything else missing is corruption.
  static CartDraftLine fromJson(Map<String, Object?> json) {
    int requireInt(String key) {
      final raw = json[key];
      if (raw is int) return raw;
      throw FormatException(
        'cart draft line $key is not an integer: '
        '${raw == null ? 'absent/null' : raw.runtimeType}',
      );
    }

    /// A rank omitted when 0 is legitimate; a present one must be exact.
    int optionalRank(String key) {
      if (!json.containsKey(key) || json[key] == null) return 0;
      final v = requireInt(key);
      if (v < 0) throw FormatException('cart draft line $key must be >= 0');
      return v;
    }

    String requireId(String key) {
      final raw = json[key];
      if (raw is String && raw.trim().isNotEmpty) return raw;
      throw FormatException(
        'cart draft line $key is not a non-blank string: '
        '${raw == null ? 'absent/null' : raw.runtimeType}',
      );
    }

    final basePriceMinor = requireInt('base_price_minor');
    if (basePriceMinor < 0) {
      throw FormatException(
        'cart draft line base_price_minor must be >= 0, got $basePriceMinor',
      );
    }
    final quantity = requireInt('quantity');
    if (quantity < 1) {
      throw FormatException(
        'cart draft line quantity must be >= 1, got $quantity',
      );
    }

    // An ABSENT `modifiers` key is a plain line. A present one that is not a
    // list is corruption: treating it as empty deletes paid surcharges.
    final modifiers = <SelectedModifier>[];
    if (json.containsKey('modifiers')) {
      final rawMods = json['modifiers'];
      if (rawMods is! List) {
        throw FormatException(
          'cart draft line modifiers must be a list, got '
          '${rawMods == null ? 'absent/null' : rawMods.runtimeType}',
        );
      }
      for (var i = 0; i < rawMods.length; i++) {
        final m = rawMods[i];
        if (m is! Map) {
          throw FormatException(
            'cart draft line modifier $i is not an object: '
            '${m == null ? 'absent/null' : m.runtimeType}',
          );
        }
        modifiers.add(SelectedModifier.fromJson(m.cast<String, Object?>()));
      }
    }

    final rawName = json['name'];
    if (rawName is! String) {
      throw FormatException(
        'cart draft line name is not a string: '
        '${rawName == null ? 'absent/null' : rawName.runtimeType}',
      );
    }
    final rawNote = json['note'];
    if (rawNote != null && rawNote is! String) {
      throw FormatException(
        'cart draft line note is not a string: ${rawNote.runtimeType}',
      );
    }
    // PARKED-CARTS-001: absent on an older record -> empty. Present but not a
    // list is corruption, for the same reason as `modifiers`.
    if (json.containsKey('prep_components') &&
        json['prep_components'] is! List) {
      throw FormatException(
        'cart draft line prep_components must be a list, got '
        '${json['prep_components']!.runtimeType}',
      );
    }

    return CartDraftLine(
      // Absent line_id is legitimate (a fresh id is minted); a present one
      // must be an exact non-blank string, never a coerced number.
      lineId: json.containsKey('line_id') ? requireId('line_id') : null,
      menuItemId: requireId('menu_item_id'),
      name: rawName,
      basePriceMinor: basePriceMinor,
      quantity: quantity,
      modifiers: modifiers,
      note: rawNote as String?,
      categoryDisplayOrder: optionalRank('category_display_order'),
      itemDisplayOrder: optionalRank('item_display_order'),
      // The shared tolerant element parser drops blank-name / non-positive
      // rows rather than showing the chef a bogus count.
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

  /// MONEY-CODEX-FINAL-CLOSURE-005 (F1): the shared startup gate, read on EVERY
  /// mutation. See [PosAdditionHydrationGate].
  PosAdditionHydrationGate get _gate =>
      ref.read(posAdditionHydrationGateProvider);

  bool get _locked => _lockOwner != null || _gate.isClosed;

  /// Recomputes the published view after the startup gate opened. Called by the
  /// Addition controller from an ASYNC continuation — never during a build, which
  /// Riverpod forbids for cross-provider writes.
  void refreshAdditionLockView() => _emit();

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
    // F1: the gate may ALREADY be closed — `AdditionController.build()` closes
    // it synchronously and this controller is built lazily, often afterwards. The
    // published view must agree with `_locked` from its very first frame.
    return CartViewState.fromCart(_cart, lockedByAddition: _locked);
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
  CartMutationResult addItem(DemoMenuItem item, {int quantity = 1}) {
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
      // POS-MODIFIER-SHEET-QUANTITY-003: merge by the requested N, not by one.
      // The default of 1 keeps every existing caller byte-identical.
      _cart.changeQuantity(existing.lineId, existing.quantity + quantity);
    } else {
      final lineId = 'line-${_lineSeq++}';
      _cart.addLine(
        CartLine.snapshot(
          lineId: lineId,
          menuItemId: item.id,
          itemNameSnapshot: item.name,
          basePriceMinorSnapshot: item.priceMinor,
          currencyCodeSnapshot: _cart.currencyCode,
          // Validation is the DOMAIN's (CartLine rejects a non-positive
          // quantity); no second, divergent rule is invented here, and no
          // arbitrary maximum is introduced because the cart has none.
          quantity: quantity,
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
  /// priced/kitchen-routed on its own).
  ///
  /// Priced by [configuredLineTotalMinor]: `qty × (unit + Σ(delta × modQty))`
  /// (MONEY-PRICING-FORMULA-002A). This used to say the delta is counted "once
  /// per line", which was the pre-002A rule the fix replaced — it under-charged
  /// every unit after the first.
  CartMutationResult addItemWithModifiers(
    DemoMenuItem item,
    List<SelectedModifier> modifiers, {
    String? note,
    int quantity = 1,
  }) {
    if (_locked) return CartMutationResult.lockedByAddition;
    final trimmedNote = note?.trim();
    final hasNote = trimmedNote != null && trimmedNote.isNotEmpty;
    if (modifiers.isEmpty && !hasNote) {
      return addItem(item, quantity: quantity);
    }
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
        // ONE configured line carrying N units — never N lines, and never N
        // add-calls. The modifier snapshots below stay PER UNIT; the kitchen
        // and the money engine both multiply by this quantity downstream.
        quantity: quantity,
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
    int? quantity,
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
    // POS-MODIFIER-SHEET-QUANTITY-003: the quantity moves inside this SAME
    // bounded mutation — the line is never removed and re-added, so its id,
    // its position and its frozen snapshots all survive, and the cart emits
    // once below. Null leaves the quantity exactly as it was.
    if (quantity != null) {
      _cart.changeQuantity(lineId, quantity);
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
          // 016: with its classification resolved against this line's selected
          // options, so a restored draft prints the same split it was parked with.
          prepComponents: classifiedPrepForLine(
            _linePrep[line.lineId] ?? const <KitchenPrepComponent>[],
            _lineModifiers[line.lineId] ?? const <SelectedModifier>[],
          ),
        ),
    ],
  );

  /// PILOT-OPERATIONS-CORRECTIONS-001: rebuild the cart from a [CartDraftSnapshot]
  /// (products, quantities, modifiers, notes). Idempotent replacement — it always
  /// REPLACES the current cart, so a repeated "Back to cart" cannot duplicate
  /// lines. Line ids keep advancing so they stay unique.
  /// MONEY-LOCAL-ATOMICITY-003A — BUILD, VALIDATE, THEN SWAP ONCE.
  ///
  /// This used to replace the live `Cart` and clear all four side maps BEFORE
  /// validating a single incoming line, then add lines one at a time. Because
  /// the domain refuses a duplicate line id by THROWING
  /// (`Cart.addLine` -> `DuplicateLineException`), a draft whose third of five
  /// lines repeated an id destroyed the cashier's active cart, left a shorter
  /// and cheaper one behind, and threw into the UI on the way out.
  ///
  /// Everything below is assembled into LOCAL structures. Nothing owned by this
  /// controller is touched until the whole replacement exists and is valid, and
  /// then it is swapped in as one committed step with exactly one emit. On any
  /// failure the previous cart, its money, every side map, the line sequence and
  /// the submitted-order confirmation are untouched and NOTHING is emitted —
  /// the caller gets [CartMutationResult.invalidDraft] and keeps its source
  /// record.
  CartMutationResult restoreDraft(CartDraftSnapshot draft) {
    if (_locked) return CartMutationResult.lockedByAddition;

    // ---- build into TEMPORARIES; the live state is not touched yet ---------
    final nextCart = Cart(
      orderId: 'demo-order',
      organizationId: 'demo-org',
      restaurantId: 'demo-restaurant',
      branchId: 'demo-branch',
      currencyCode: draft.currencyCode,
    );
    final nextModifiers = <String, List<SelectedModifier>>{};
    final nextNotes = <String, String>{};
    final nextDisplayOrders = <String, (int, int)>{};
    final nextPrep = <String, List<KitchenPrepComponent>>{};
    // A LOCAL sequence: a rejected draft must not advance the real one either,
    // or a failed restore would silently consume line ids.
    var nextSeq = _lineSeq;

    // A legacy line carries no id and is MINTED one. Scan the explicit ids
    // FIRST so a mint can never collide with an id that appears later in the
    // same draft — otherwise a legitimate mixed draft (some legacy lines, some
    // `line-N`) would self-collide and be refused for a reason of our own
    // making. Failing closed would still be safe; restoring it correctly is
    // better.
    final explicitIds = <String>{
      for (final l in draft.lines)
        if (l.lineId != null) l.lineId!,
    };
    for (final id in explicitIds) {
      final m = RegExp(r'^line-(\d+)$').firstMatch(id);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? -1;
        if (n >= nextSeq) nextSeq = n + 1;
      }
    }

    try {
      for (final l in draft.lines) {
        // MENU-ORDER-001 (Codex #2/#3): reuse the persisted STABLE line id so
        // edits/removals target the original line and a re-restore never
        // duplicates; a legacy record with no id mints a fresh one. Keep the
        // sequence AHEAD of any restored `line-N` so a later add cannot collide.
        final lineId = l.lineId ?? 'line-${nextSeq++}';
        final seqMatch = RegExp(r'^line-(\d+)$').firstMatch(lineId);
        if (seqMatch != null) {
          final n = int.tryParse(seqMatch.group(1)!) ?? -1;
          if (n >= nextSeq) nextSeq = n + 1;
        }
        // Throws DuplicateLineException / CurrencyMismatchException on a draft
        // that cannot become a cart — caught below, with nothing yet swapped.
        nextCart.addLine(
          CartLine.snapshot(
            lineId: lineId,
            menuItemId: l.menuItemId,
            itemNameSnapshot: l.name,
            basePriceMinorSnapshot: l.basePriceMinor,
            currencyCodeSnapshot: draft.currencyCode,
          ),
        );
        if (l.quantity > 1) nextCart.changeQuantity(lineId, l.quantity);
        if (l.modifiers.isNotEmpty) {
          nextModifiers[lineId] = List.unmodifiable(l.modifiers);
        }
        final note = l.note;
        if (note != null && note.isNotEmpty) nextNotes[lineId] = note;
        // MENU-ORDER-001 (Codex): restore the Dashboard menu ranks so the
        // corrected resubmit prints in the menu order the original would have.
        nextDisplayOrders[lineId] = (
          l.categoryDisplayOrder,
          l.itemDisplayOrder,
        );
        // PARKED-CARTS-001: repopulate the ORDER-TIME prep snapshot the draft
        // carries. It is deliberately NOT re-read from the live menu — a
        // restored cart must keep the configuration it was ordered against, and
        // a record written before the field existed honestly restores none.
        if (l.prepComponents.isNotEmpty) {
          nextPrep[lineId] = List.unmodifiable(l.prepComponents);
        }
      }
    } on CartException {
      // The draft cannot become a cart. Nothing was swapped, nothing emitted.
      return CartMutationResult.invalidDraft;
    }

    // ---- ONE committed swap ------------------------------------------------
    _cart = nextCart;
    _lineModifiers
      ..clear()
      ..addAll(nextModifiers);
    _lineNotes
      ..clear()
      ..addAll(nextNotes);
    _lineDisplayOrders
      ..clear()
      ..addAll(nextDisplayOrders);
    _linePrep
      ..clear()
      ..addAll(nextPrep);
    _lineSeq = nextSeq;
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
    // 017 (Codex HIGH #3): the AUTHORITATIVE prep snapshot of the operation that
    // was actually submitted — the very map the outbox payload was built from,
    // captured once before the first await.
    //
    // Without it this view fell back to `_linePrep`, captured when each line
    // ENTERED THE CART. A prep/classifier edit between add-to-cart and submit
    // therefore made the manual reprint disagree with the ticket the kitchen
    // and the server received. Null keeps the legacy in-memory/demo behaviour
    // (no submitted operation exists to be authoritative).
    Map<String, List<KitchenPrepComponent>>? submittedPrepByItemId,
  }) {
    if (_locked) return CartMutationResult.lockedByAddition;
    if (_cart.isEmpty) return CartMutationResult.applied;
    final order = LocalOrder.submitFromCart(_cart, orderType: orderType);
    _orderSeq++;
    // RF-115: the outbox controller is the numbering authority for the real
    // submit flow; fall back to a local number for the RF-101 in-memory path.
    final resolvedNumber =
        orderNumber ?? 'DEMO-${_orderSeq.toString().padLeft(4, '0')}';
    // Line totals mirror the server formula as CORRECTED in
    // MONEY-PRICING-FORMULA-002A: `qty × (unit + Σ(delta × modQty))`. The old
    // comment here said "once per line" — the pre-002A rule — directly above
    // code that had already been fixed to charge the surcharge per ITEM UNIT.
    var modifiersTotal = 0;
    var linePosition = 0;
    final lines = <SubmittedLineView>[];
    for (final item in order.items) {
      linePosition++;
      // LocalOrderItem.orderItemId carries the source cart line id.
      final mods =
          _lineModifiers[item.orderItemId] ?? const <SelectedModifier>[];
      // MONEY-PRICING-FORMULA-002A: the ONE formula. `lineTotalMinorPreview` is
      // the BARE base × quantity, so the configured total re-derives from the
      // per-unit base to keep the surcharge inside the multiplication.
      final lineTotal = configuredLineTotalMinor(
        basePriceMinor: item.basePriceMinorSnapshot,
        modifiers: mods,
        quantity: item.quantity,
      );
      modifiersTotal += lineTotal - item.lineTotalMinorPreview;
      // MENU-ORDER-001: carry the item's Dashboard ranks + its 1-based cart
      // position so every POS surface (receipt, kitchen ticket) orders items
      // into the SAME Dashboard-configured sequence the KDS + server reprint use.
      final dispOrder = _lineDisplayOrders[item.orderItemId];
      lines.add(
        SubmittedLineView(
          name: item.itemNameSnapshot,
          quantity: item.quantity,
          lineTotalMinor: lineTotal,
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
          // 016: the ORDER-TIME classification resolved from the SAME selected
          // options this line was submitted with, so a manual kitchen reprint
          // splits the resource exactly as the automatic ticket did.
          //
          // 017 (Codex HIGH #3): resolved against the SUBMITTED operation's
          // snapshot when one was supplied — never the older add-to-cart
          // capture, and never re-read from the live menu after submit. The
          // outbox payload, this confirmation view, the automatic ticket and
          // the manual reprint therefore all describe ONE accepted operation.
          prepComponents: classifiedPrepForLine(
            submittedPrepForItem(submittedPrepByItemId, item.menuItemId) ??
                _linePrep[item.orderItemId] ??
                const <KitchenPrepComponent>[],
            mods,
          ),
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
  /// mirrors [submitOrder] EXACTLY — integer minor units, and the ONE 002A formula
  /// `qty × (unit + Σ(delta × modQty))` (D-007) — so a recovered row shows the same
  /// figures it would have shown in its own session. (It read "base price × line
  /// quantity plus each modifier delta counted once per line", which is the
  /// superseded formula A; the code has used `configuredLineTotalMinor` since 002A.)
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
    // 018 (Codex HIGH #2): the AUTHORITATIVE prep snapshot of the operation that
    // was actually submitted — the same map the outbox payload and the automatic
    // ticket were built from.
    //
    // The draft is captured BEFORE the submit and carries each line's ADD-TIME
    // prep, so a departed worker's retained recent order (and every manual
    // reprint from it) described a different configuration than the order the
    // server accepted. A PIN handover mid-submit must not rewind the prep.
    // Null keeps the legacy behaviour for callers with no submitted operation.
    Map<String, List<KitchenPrepComponent>>? submittedPrepByItemId,
  }) {
    var subtotal = 0;
    var linePosition = 0;
    final lines = <SubmittedLineView>[];
    for (final l in draft.lines) {
      linePosition++;
      // MONEY-PRICING-FORMULA-002A: the SAME one formula, so a recovered draft
      // bills exactly what it displayed.
      final lineTotal = configuredLineTotalMinor(
        basePriceMinor: l.basePriceMinor,
        modifiers: l.modifiers,
        quantity: l.quantity,
      );
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
          //
          // 018 (Codex HIGH #2): when this view materializes a SUBMITTED
          // operation (the PIN-handover path), the submitted snapshot wins over
          // the draft's older add-time capture — resolved against THIS line's
          // own selected options, exactly as the submitting session would have.
          // A non-null map always answers, so a resource the owner deleted
          // before submit cannot reappear here.
          prepComponents: classifiedPrepForLine(
            submittedPrepForItem(submittedPrepByItemId, l.menuItemId) ??
                l.prepComponents,
            l.modifiers,
          ),
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
  /// clamp.
  ///
  /// MONEY-DISCOUNT-TARGET-INTEGRITY-002E — [orderId] IS THE POINT.
  ///
  /// This used to take the amount alone and write it onto whatever order the
  /// confirmation happened to be holding. The discount sheet is reachable per
  /// RECENT ORDER, so discounting order B wrote B's discount onto order A: A's
  /// confirmation showed a discount it never received, A's printed customer
  /// bill was built from that view, and A's payment sheet opened under-charged.
  /// The server was always told the right order — only the LOCAL write was
  /// blind. Passing the id to the RPC is therefore not enough; the identity
  /// has to be checked at THIS boundary, where the state actually changes.
  ///
  /// FAIL CLOSED. The mutation happens only on an EXACT id match against the
  /// currently held order. A stale response (the held confirmation moved on
  /// while the request was in flight), a response for a different order, a
  /// held order with no server identity yet, or a blank target are all a SAFE
  /// NO-OP: no discount, no subtotal, tax, grand-total or payment change, no
  /// confirmation change, no cart-line change, no substitution — and no
  /// cashier-facing crash, because a late response is normal, not exceptional.
  ///
  /// Comparison is EXACT, deliberately. Order ids are not canonically trimmed
  /// anywhere on the way in, so a whitespace-tolerant compare could match two
  /// orders that the rest of the system considers distinct.
  void applyOrderDiscount({
    required String orderId,
    required int discountTotalMinor,
  }) {
    final current = _submittedOrder;
    if (current == null) return; // nothing is being confirmed
    final heldOrderId = current.orderId;
    if (heldOrderId == null || heldOrderId.isEmpty) return;
    if (orderId.isEmpty) return;
    if (orderId != heldOrderId) return; // a DIFFERENT order — never ours
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
