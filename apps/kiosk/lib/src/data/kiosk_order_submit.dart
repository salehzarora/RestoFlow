import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import '../state/kiosk_flow_controller.dart';
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

/// One frozen Place-Order attempt: the D-022 identity plus the exact RPC
/// parameter map. Retrying an unconfirmed delivery re-sends THIS object
/// unchanged; only a deliberate NEW attempt after a definitive rejection
/// builds a new one.
@immutable
class KioskSubmitAttempt {
  const KioskSubmitAttempt({
    required this.orderId,
    required this.localOperationId,
    required this.params,
  });

  final String orderId;
  final String localOperationId;

  /// The full, frozen `kiosk_submit_order` parameter map.
  final Map<String, dynamic> params;
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
          if (option.kitchenMeat != null)
            'meat_snapshot': option.kitchenMeat, // order-time frozen (021)
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
  final name = customerName.trim();
  final phone = customerPhone.trim();
  final id = orderId ?? generateKioskUuidV4();
  final opId = localOperationId ?? 'kiosk-${generateKioskUuidV4()}';
  return KioskSubmitAttempt(
    orderId: id,
    localOperationId: opId,
    params: <String, dynamic>{
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
    },
  );
}

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
