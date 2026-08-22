import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenMeat, resolveTrustedMeatClassifier;

import '../state/kiosk_flow_controller.dart';
import 'kiosk_fixtures.dart';
import 'kiosk_menu_data.dart';

/// KIOSK-001-REAL-SUBMIT-092 — the ONLINE-REQUIRED real submit seam around
/// the existing hardened `kiosk_submit_order` RPC.
///
/// Deliberately NOT the POS durable-queue model: a kiosk keeps no offline
/// order queue and no disk-persisted pending operations. One customer Place-Order
/// action mints exactly ONE frozen [KioskSubmitAttempt] (order id + D-022
/// operation identity + payload bytes) that lives in memory; a retry of an
/// UNCONFIRMED delivery re-sends the SAME attempt so the server's idempotency
/// ledger replays the terminal result instead of creating a duplicate order.
/// If the app closes during an uncertain submit, the attempt is lost by
/// design (documented limitation of the no-offline phase) — the server-side
/// outcome stands and staff surfaces show it.

// ---------------------------------------------------------------------------
// Branch tax (RF-117) — the kiosk-typed reader. Unlike the POS reader, a
// failed read NEVER silently means "tax off": the caller must block submit.
// ---------------------------------------------------------------------------

/// The owner's per-branch tax policy as the KIOSK needs it: enabled flag,
/// integer basis-point rate, and the MODE (`exclusive` adds tax on top;
/// `inclusive` extracts it from the shown total). No float anywhere (D-007).
@immutable
class KioskBranchTax {
  const KioskBranchTax({
    required this.enabled,
    required this.rateBp,
    required this.mode,
  });

  final bool enabled;
  final int rateBp;

  /// 'exclusive' | 'inclusive' (the server's `branches.tax_mode` values).
  final String mode;

  bool get addsTax => enabled && rateBp > 0;
  bool get isInclusive => mode == 'inclusive';

  @override
  bool operator ==(Object other) =>
      other is KioskBranchTax &&
      other.enabled == enabled &&
      other.rateBp == rateBp &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(enabled, rateBp, mode);
}

/// Integer round-HALF-AWAY-FROM-ZERO of `numerator / denominator` for
/// NON-NEGATIVE inputs — `(2n + d) ~/ 2d` — matching PostgreSQL's
/// `round(numeric)` the server uses in the tax gate. No float is constructed.
int _roundHalfAwayDiv(int numerator, int denominator) {
  assert(numerator >= 0 && denominator > 0);
  return (2 * numerator + denominator) ~/ (2 * denominator);
}

/// The EXACT server tax figure for [subtotalMinor] under [tax]
/// (HARDENING-FIX-073, byte-matching `kiosk_submit_order`):
///   exclusive: round(subtotal * bp / 10000)          — added on top
///   inclusive: round(subtotal * bp / (10000 + bp))   — extracted, not added
///   disabled/0bp: 0
int kioskTaxMinor(int subtotalMinor, KioskBranchTax tax) {
  if (!tax.addsTax || subtotalMinor <= 0) return 0;
  return tax.isInclusive
      ? _roundHalfAwayDiv(subtotalMinor * tax.rateBp, 10000 + tax.rateBp)
      : _roundHalfAwayDiv(subtotalMinor * tax.rateBp, 10000);
}

/// The grand total the server will derive: subtotal plus tax ONLY when the
/// mode ADDS it (inclusive keeps the shown total unchanged).
int kioskGrandMinor(int subtotalMinor, KioskBranchTax tax) =>
    (!tax.addsTax || tax.isInclusive)
    ? subtotalMinor
    : subtotalMinor + kioskTaxMinor(subtotalMinor, tax);

/// Token-proven read of the branch tax policy through the SHARED RPC
/// `get_device_branch_tax` (device-type-agnostic server-side). Returns null
/// on ANY failure — missing credential, transport trouble, refused session,
/// malformed envelope, unknown mode. The kiosk BLOCKS submit on null instead
/// of guessing "tax off" (a wrong guess would be a guaranteed tax_mismatch
/// or, worse, a silent under-display).
class KioskBranchTaxReader {
  KioskBranchTaxReader({
    required this._transport,
    required DeviceSessionSecretStore secretStore,
  }) : _store = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _store;

  Future<KioskBranchTax?> load() async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      return null;
    }
    if (cred == null) return null;
    final Object? raw;
    try {
      raw = await _transport.invoke('get_device_branch_tax', <String, dynamic>{
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
      });
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) return null;
    final enabled = raw['tax_enabled'];
    final rateBp = raw['tax_rate_bp'];
    final mode = raw['tax_mode'];
    if (enabled is! bool) return null;
    if (rateBp is! int || rateBp < 0) return null;
    if (mode != 'exclusive' && mode != 'inclusive') return null;
    return KioskBranchTax(enabled: enabled, rateBp: rateBp, mode: mode);
  }
}

// ---------------------------------------------------------------------------
// Submit attempt (frozen identity + payload) and typed results.
// ---------------------------------------------------------------------------

/// KIOSK-001-094: the DISPLAY strings of one ordered line, captured from the
/// same refreshed menu snapshot the payload was built from. The accepted
/// confirmation renders THESE — never the current menu, which may have been
/// renamed, repriced, or had the item removed after the order was accepted.
@immutable
class KioskFrozenLineDisplay {
  const KioskFrozenLineDisplay({
    required this.lineId,
    required this.itemName,
    required this.modifierNames,
  });

  final int lineId;

  /// The item's display name (live tenant menus carry one string shown in
  /// every UI language; fixtures are per-language — [KioskText3] covers both).
  final KioskText3 itemName;

  /// Selected modifier option labels in the exact order the slip summary
  /// shows them (the item's group order, the customer's pick order within a
  /// group, the fixture included-weight option skipped).
  final List<KioskText3> modifierNames;
}

/// KIOSK-001-093: the complete CUSTOMER-VISIBLE order content frozen at
/// submit time — deep-copied, never aliasing mutable flow state. The
/// accepted confirmation renders from THIS (plus the accepted order id),
/// never from whatever the live state holds when the response lands.
@immutable
class KioskFrozenOrderView {
  const KioskFrozenOrderView({
    required this.lines,
    required this.lineDisplays,
    required this.service,
    required this.tableId,
    required this.tableLabel,
    required this.customerName,
    required this.customerPhone,
    required this.subtotalMinor,
    required this.taxMinor,
    required this.grandMinor,
    required this.taxInclusive,
    required this.currencyCode,
  });

  final List<KioskCartLine> lines;

  /// 094: submit-time display strings per line (item + modifier names), so
  /// the confirmation never consults the live menu for accepted content.
  final List<KioskFrozenLineDisplay> lineDisplays;
  final KioskServiceType service;
  final String? tableId;
  final String? tableLabel;
  final String customerName;
  final String customerPhone;
  final int subtotalMinor;
  final int taxMinor;
  final int grandMinor;
  final bool taxInclusive;
  final String currencyCode;
}

/// One frozen Place-Order attempt: the D-022 identity, the exact RPC
/// parameter map, and the frozen customer-visible [view]. Retrying an
/// unconfirmed delivery re-sends THIS object unchanged; only a deliberate
/// NEW attempt after a definitive rejection builds a new one.
@immutable
class KioskSubmitAttempt {
  const KioskSubmitAttempt({
    required this.orderId,
    required this.localOperationId,
    required this.params,
    this.view,
  });

  final String orderId;
  final String localOperationId;

  /// The full, frozen `kiosk_submit_order` parameter map.
  final Map<String, dynamic> params;

  /// The frozen customer-visible snapshot (093). Null only in low-level
  /// tests that exercise the wire alone.
  final KioskFrozenOrderView? view;
}

/// Typed outcome of one submit call. UI never sees a raw envelope.
sealed class KioskSubmitResult {
  const KioskSubmitResult();
}

class KioskSubmitAccepted extends KioskSubmitResult {
  const KioskSubmitAccepted({
    required this.orderId,
    required this.revision,
    required this.orderStatus,
    required this.idempotencyReplay,
    required this.autoCompleted,
  });
  final String orderId;
  final int revision;
  final String orderStatus;
  final bool idempotencyReplay;
  final bool autoCompleted;
}

/// A DEFINITIVE server refusal: the operation ledger recorded a terminal
/// rejection for this identity, so a later deliberate re-order must mint a
/// NEW identity. [code] is the stable server error code (recovery policy
/// only — customer copy is localized elsewhere).
class KioskSubmitRejected extends KioskSubmitResult {
  const KioskSubmitRejected(this.code, {this.invalidField});
  final String code;

  /// For `invalid_payload`: the offending field name when the server names one.
  final String? invalidField;
}

/// Delivery is UNKNOWN (timeout / transport trouble / unreadable response).
/// The server may or may not have committed — keep the attempt and retry the
/// SAME identity; D-022 makes that safe.
class KioskSubmitUnconfirmed extends KioskSubmitResult {
  const KioskSubmitUnconfirmed();
}

/// The device session is dead — the pairing gate must re-validate.
class KioskSubmitInvalidSession extends KioskSubmitResult {
  const KioskSubmitInvalidSession();
}

/// The real submitter: stored kiosk credential + the shared RPC transport.
/// No raw backend client, no persistence, no logging of the token.
class KioskOrderSubmitter {
  KioskOrderSubmitter({
    required this._transport,
    required DeviceSessionSecretStore secretStore,
  }) : _store = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _store;

  Future<KioskSubmitResult> submit(KioskSubmitAttempt attempt) async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      return const KioskSubmitInvalidSession();
    }
    if (cred == null) return const KioskSubmitInvalidSession();

    final Object? raw;
    try {
      raw = await _transport.invoke('kiosk_submit_order', <String, dynamic>{
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
        ...attempt.params,
      });
    } on SyncTransportException catch (e) {
      return e.kind == SyncTransportErrorKind.auth
          ? const KioskSubmitInvalidSession()
          : const KioskSubmitUnconfirmed();
    } catch (_) {
      return const KioskSubmitUnconfirmed();
    }

    if (raw is! Map) return const KioskSubmitUnconfirmed();
    if (raw['ok'] == true) {
      final orderId = raw['order_id'];
      if (orderId is! String || orderId.isEmpty) {
        return const KioskSubmitUnconfirmed();
      }
      return KioskSubmitAccepted(
        orderId: orderId,
        revision: raw['revision'] is int ? raw['revision'] as int : 1,
        orderStatus: raw['order_status'] is String
            ? raw['order_status'] as String
            : 'submitted',
        idempotencyReplay: raw['idempotency_replay'] == true,
        autoCompleted: raw['auto_completed'] == true,
      );
    }
    final code = raw['error'];
    if (code is! String || code.isEmpty) return const KioskSubmitUnconfirmed();
    if (code == 'invalid_session') return const KioskSubmitInvalidSession();
    final field = raw['field'];
    return KioskSubmitRejected(
      code,
      invalidField: field is String ? field : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Payload construction — frozen order-time snapshots from the CURRENT live
// menu (the caller has already refreshed + revalidated the cart, so every
// captured price still reprices identically; the server re-proves all of it).
// ---------------------------------------------------------------------------

/// Thrown when a cart line no longer reproduces its captured price/selection
/// against the menu snapshot — the pre-submit freshness gate should have
/// caught this; callers treat it as "cart stale, reconfirm".
class KioskCartOutOfSyncError extends StateError {
  KioskCartOutOfSyncError(super.message);
}

/// Builds the frozen attempt for ONE Place-Order action. Money is integer
/// minor units only; the item's `unit_price_minor_snapshot` is the BASE menu
/// price and every modifier delta rides separately (never pre-summed — the
/// server recomputes `qty × (base + Σ delta × modQty)` itself).
KioskSubmitAttempt buildKioskSubmitAttempt({
  required KioskMenuData menu,
  required List<KioskCartLine> cart,
  required KioskServiceType service,
  required String? tableId,
  required KioskBranchTax tax,
  required String customerName,
  required String customerPhone,
  required DateTime clientCreatedAt,
  String? orderId,
  String? localOperationId,
  String? tableLabel,
}) {
  if (cart.isEmpty) {
    throw KioskCartOutOfSyncError('cart is empty');
  }
  final items = <Map<String, dynamic>>[];
  var subtotal = 0;
  for (final line in cart) {
    final item = menu.tryItem(line.itemId);
    if (item == null || !item.available) {
      throw KioskCartOutOfSyncError('item ${line.itemId} is not sellable');
    }
    // 096: the ORDER-TIME kitchen-classifier inputs for this line — the
    // complete selected-option-id set across ALL of the line's groups
    // (presence-based answer), and the SAME-ITEM id→current-name map the
    // trusted classifier boundary validates a configured link against.
    // Never a cross-item lookup; ids and same-item scope are authoritative.
    final selectedOptionIds = <String>{
      for (final e in line.selected.entries) ...e.value,
    };
    final sameItemOptionNamesById = <String, String>{
      for (final gid in item.groupIds)
        if (menu.group(gid) case final g?)
          for (final o in g.options) o.id: o.name.of('en'),
    };
    final modifiers = <Map<String, dynamic>>[];
    var deltaSum = 0;
    for (final entry in line.selected.entries) {
      final group = menu.group(entry.key);
      if (entry.value.isEmpty) continue;
      if (group == null) {
        throw KioskCartOutOfSyncError('group ${entry.key} vanished');
      }
      for (final optionId in entry.value) {
        final option = group.options.where((o) => o.id == optionId).firstOrNull;
        if (option == null) {
          throw KioskCartOutOfSyncError('option $optionId vanished');
        }
        deltaSum += option.priceDeltaMinor;
        modifiers.add(<String, dynamic>{
          'modifier_option_id': option.id,
          'option_name_snapshot': option.name.of('en'),
          'modifier_name_snapshot': group.displayName?.of('en'),
          'price_minor_snapshot': option.priceDeltaMinor,
          // The V2 kiosk UI selects options without per-option quantity;
          // quantity is ALWAYS 1 here (never fabricated, never duplicated).
          'quantity': 1,
          // 096: the ORDER-TIME trusted snapshot (021), never the raw owner
          // config — a classifier link is proven against the item's own
          // options and answered from THIS line's selections, like the POS.
          'meat_snapshot': ?_resolvedKioskMeatSnapshot(
            option,
            sameItemOptionNamesById: sameItemOptionNamesById,
            selectedOptionIds: selectedOptionIds,
          ),
        });
      }
    }
    final unit = item.basePriceMinor + deltaSum;
    if (unit != line.capturedUnitMinor) {
      throw KioskCartOutOfSyncError(
        'line ${line.lineId} captured ${line.capturedUnitMinor} '
        'but reprices to $unit',
      );
    }
    final lineTotal = line.quantity * unit;
    subtotal += lineTotal;
    items.add(<String, dynamic>{
      'menu_item_id': item.id,
      'menu_item_name_snapshot': item.name.of('en'),
      'quantity': line.quantity,
      'unit_price_minor_snapshot': item.basePriceMinor,
      'line_total_minor': lineTotal,
      if (line.note.trim().isNotEmpty) 'notes': line.note.trim(),
      if (modifiers.isNotEmpty) 'modifiers': modifiers,
    });
  }

  final taxMinor = kioskTaxMinor(subtotal, tax);
  final grand = kioskGrandMinor(subtotal, tax);
  // 094: normalize the customer name ONCE — trim, then cap to the server's
  // 80-char column. The SAME canonical value goes on the wire AND into the
  // frozen customer-visible view, so what the server stores and what the
  // confirmation prints can never disagree.
  final trimmedName = customerName.trim();
  final name = trimmedName.length > 80
      ? trimmedName.substring(0, 80)
      : trimmedName;
  final phone = customerPhone.trim();
  final id = orderId ?? generateKioskUuidV4();
  final opId = localOperationId ?? 'kiosk-${generateKioskUuidV4()}';
  final effectiveTableId = service == KioskServiceType.dineIn ? tableId : null;
  // 093: DEEP-copy the customer-visible order (lines + their selection maps)
  // so no later flow-state mutation can alias into this frozen attempt.
  final frozenLines = List<KioskCartLine>.unmodifiable([
    for (final l in cart)
      KioskCartLine(
        lineId: l.lineId,
        itemId: l.itemId,
        quantity: l.quantity,
        selected: Map<String, List<String>>.unmodifiable({
          for (final e in l.selected.entries)
            e.key: List<String>.unmodifiable(e.value),
        }),
        note: l.note,
        capturedUnitMinor: l.capturedUnitMinor,
      ),
  ]);
  // 094: freeze the DISPLAY strings too (item + modifier names, in slip
  // order) from the SAME menu snapshot the payload used — the confirmation
  // must never consult the live menu for accepted order content.
  final frozenDisplays = List<KioskFrozenLineDisplay>.unmodifiable([
    for (final l in cart)
      KioskFrozenLineDisplay(
        lineId: l.lineId,
        itemName: menu.itemById(l.itemId).name,
        modifierNames: _slipModifierNames(menu, menu.itemById(l.itemId), l),
      ),
  ]);
  return KioskSubmitAttempt(
    orderId: id,
    localOperationId: opId,
    view: KioskFrozenOrderView(
      lines: frozenLines,
      lineDisplays: frozenDisplays,
      service: service,
      tableId: effectiveTableId,
      tableLabel: effectiveTableId == null ? null : tableLabel,
      customerName: name,
      customerPhone: phone,
      subtotalMinor: subtotal,
      taxMinor: taxMinor,
      grandMinor: grand,
      taxInclusive: tax.isInclusive,
      currencyCode: menu.currencyCode,
    ),
    // 094: the D-022 retry payload is structurally immutable — the whole
    // parameter graph (map, item list, item maps, modifier lists/maps and
    // any nested prep snapshot) is recursively frozen, wire-equivalent.
    params: _deepFreezeWire(<String, dynamic>{
      'p_order_id': id,
      'p_local_operation_id': opId,
      'p_order_type': service == KioskServiceType.dineIn
          ? 'dine_in'
          : 'takeaway',
      'p_table_id': service == KioskServiceType.dineIn ? tableId : null,
      'p_currency_code': menu.currencyCode,
      'p_notes': null,
      'p_customer_name': name.isEmpty
          ? null
          : (name.length > 80 ? name.substring(0, 80) : name),
      'p_customer_phone': phone.isEmpty ? null : phone,
      'p_order_items': items,
      'p_client_subtotal_minor': subtotal,
      'p_client_discount_total_minor': 0,
      'p_client_tax_total_minor': taxMinor,
      'p_client_grand_total_minor': grand,
      'p_client_created_at': clientCreatedAt.toUtc().toIso8601String(),
    }),
  );
}

/// 094: recursively freezes a JSON-shaped wire value. Maps become
/// unmodifiable views over FRESH insertion-ordered copies (every write
/// throws; nobody holds the inner map), lists become unmodifiable copies,
/// scalars pass through untouched — wire-equivalent by construction, no
/// serialization roundtrip, no numeric conversion anywhere.
Map<String, dynamic> _deepFreezeWire(Map<String, dynamic> map) =>
    UnmodifiableMapView<String, dynamic>({
      for (final e in map.entries) e.key: _deepFreezeWireValue(e.value),
    });

Object? _deepFreezeWireValue(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<String, dynamic>({
      for (final e in value.entries)
        e.key as String: _deepFreezeWireValue(e.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepFreezeWireValue));
  }
  return value;
}

/// 096: the ORDER-TIME trusted `meat_snapshot` for ONE selected modifier
/// option — semantically the POS wire contract, built on the shared domain
/// boundary instead of the raw owner config:
///
///  1. [KitchenMeat.tryFromJson] — a non-object / non-positive contribution
///     yields NO snapshot (never fabricated).
///  2. [resolveTrustedMeatClassifier] — a configured classifier link survives
///     ONLY when it names a DIFFERENT option of the SAME item (via
///     [sameItemOptionNamesById]); the display name is the trusted CURRENT
///     menu name, never the stored one; an invalid/self/cross-item/deleted
///     link strips to the ordinary unsplit {quantity, unit} contribution.
///  3. A surviving link gets the PRESENCE-based order-time answer:
///     `classifier_selected = selectedOptionIds.contains(id)` — boolean
///     presence over THIS line's complete selection, never multiplied by any
///     modifier/item quantity (the wire carries per-selection contribution;
///     quantities apply exactly once downstream).
Map<String, Object?>? _resolvedKioskMeatSnapshot(
  KioskFixtureOption option, {
  required Map<String, String> sameItemOptionNamesById,
  required Set<String> selectedOptionIds,
}) {
  final trusted = resolveTrustedMeatClassifier(
    KitchenMeat.tryFromJson(option.kitchenMeat),
    optionNamesById: sameItemOptionNamesById,
    selfOptionId: option.id,
  );
  if (trusted == null) return null;
  if (trusted.classifierOptionId.isEmpty) return trusted.toJson();
  return trusted
      .withClassifierSelected(
        selectedOptionIds.contains(trusted.classifierOptionId),
      )
      .toJson();
}

/// 094: the frozen modifier labels of one line, in EXACTLY the order the
/// slip summary renders them (the item's group order, then the customer's
/// pick order within each group; the fixture included-weight option is
/// skipped, matching the demo slip rule — live group ids are UUIDs, so the
/// rule is inert there).
List<KioskText3> _slipModifierNames(
  KioskMenuData menu,
  KioskFixtureItem item,
  KioskCartLine line,
) => List<KioskText3>.unmodifiable([
  for (final gid in item.groupIds)
    if (menu.group(gid) case final group?)
      for (final oid in line.selected[gid] ?? const <String>[])
        if (!(gid == 'weight' && oid == kioskIncludedWeightOptionId))
          for (final o in group.options)
            if (o.id == oid) o.name,
]);

/// RFC-4122 v4 UUID from a cryptographically secure source — no extra
/// dependency, used only for the order id + D-022 operation identity.
String generateKioskUuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex[0]}${hex[1]}${hex[2]}${hex[3]}-'
      '${hex[4]}${hex[5]}-${hex[6]}${hex[7]}-'
      '${hex[8]}${hex[9]}-${hex[10]}${hex[11]}${hex[12]}${hex[13]}${hex[14]}${hex[15]}';
}

// ---------------------------------------------------------------------------
// Provider seams (null in demo mode; the real composition root overrides).
// ---------------------------------------------------------------------------

final kioskOrderSubmitterProvider = Provider<KioskOrderSubmitter?>(
  (ref) => null,
);

final kioskBranchTaxReaderProvider = Provider<KioskBranchTaxReader?>(
  (ref) => null,
);

/// Whether the discreet staff triple-tap → fixture-PIN settings unlock is
/// available. TRUE in demo (the Phase-1 design surface); the REAL composition
/// root overrides it FALSE — a hardcoded demo PIN must never gate a live
/// production kiosk (REAL STAFF SETTINGS/PIN AUTH REMAINS A SEPARATE PHASE).
final kioskStaffSettingsEnabledProvider = Provider<bool>((ref) => true);
