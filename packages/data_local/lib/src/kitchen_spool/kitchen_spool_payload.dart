/// KITCHEN-MODE-001C2A — the versioned, CLOSED local encrypted-payload model
/// for the kitchen spool.
///
/// This is what the encrypted blob will hold once the 001C2B import path is
/// wired: the typed money-free server dispatch document, the locally pinned
/// printer destination, the fixed `kitchen_ticket` purpose and the transport
/// settings. In 001C2A the models and their closed serialization exist and
/// are fully tested, but nothing connects them to server RPCs.
///
/// Decoding is CLOSED at every level: unknown fields are rejected (never
/// silently persisted into an encrypted blob), and a defence-in-depth
/// recursive key validator additionally rejects money/PII vocabulary inside
/// the server-derived dispatch document (mirroring the server-side guard's
/// token rules). Endpoint data (host/port/Bluetooth address) exists ONLY in
/// the destination variants inside this encrypted model — never in plaintext
/// columns.
library;

import 'dart:convert' show json, utf8;
import 'dart:typed_data';

import 'kitchen_spool_status.dart';

/// Typed rejection for any malformed/unknown/hostile local payload input.
/// Messages may name an offending KEY (keys are non-secret) but never a
/// value.
final class KitchenSpoolPayloadFormatException implements Exception {
  const KitchenSpoolPayloadFormatException(this.message);

  final String message;

  @override
  String toString() => 'KitchenSpoolPayloadFormatException: $message';
}

/// The fixed printing purpose of every kitchen-spool job.
const String kKitchenSpoolPurpose = 'kitchen_ticket';

/// The v1 local payload envelope (the CLEARTEXT that gets encrypted).
final class KitchenSpoolLocalPayload {
  KitchenSpoolLocalPayload({
    required this.dispatch,
    required this.destination,
    this.paperWidth,
    required this.documentVersion,
    required this.rasterVersion,
    this.customerPhone,
  });

  static const int version = 1;

  final KitchenDispatchDocument dispatch;
  final KitchenSpoolDestination destination;

  /// `58mm` / `80mm`; null until a destination is pinned.
  final String? paperWidth;

  final int documentVersion;
  final int rasterVersion;

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap C): the OPTIONAL customer phone, a
  /// DEDICATED typed field of THIS encrypted local payload — a SIBLING of
  /// [dispatch], deliberately OUTSIDE the server-derived `dispatch` subtree that
  /// [rejectHostileKitchenKeys] guards, so the generic phone/PII redaction is
  /// UNCHANGED. Encrypted with the rest of the payload (AES-GCM, AAD-bound to the
  /// order/tenant/device) and purged with the row. A crash-recovery replay reads
  /// it so the printed ticket keeps the phone; legacy rows decode it as null
  /// (byte-identical when absent). Sourced ONLY from the local order at import —
  /// never from the redacted server payload. Not logged (no toString).
  final String? customerPhone;

  Map<String, Object?> toJson() => {
    'v': version,
    'purpose': kKitchenSpoolPurpose,
    'dispatch': dispatch.toJson(),
    'destination': destination.toJson(),
    if (paperWidth != null) 'paper_width': paperWidth,
    'document_version': documentVersion,
    'raster_version': rasterVersion,
    if (customerPhone != null) 'customer_phone': customerPhone,
  };

  /// Canonical plaintext bytes for the cipher.
  Uint8List toBytes() => Uint8List.fromList(utf8.encode(json.encode(toJson())));

  static KitchenSpoolLocalPayload fromBytes(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = json.decode(utf8.decode(bytes));
    } on FormatException {
      throw const KitchenSpoolPayloadFormatException('not valid JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const KitchenSpoolPayloadFormatException('root is not an object');
    }
    return fromJson(decoded);
  }

  static KitchenSpoolLocalPayload fromJson(Map<String, Object?> raw) {
    final r = _StrictReader(raw, 'payload');
    final v = r.requireInt('v');
    if (v != version) {
      throw const KitchenSpoolPayloadFormatException(
        'unknown local payload version',
      );
    }
    final purpose = r.requireString('purpose');
    if (purpose != kKitchenSpoolPurpose) {
      throw const KitchenSpoolPayloadFormatException(
        'purpose must be kitchen_ticket',
      );
    }
    final dispatchRaw = r.requireMap('dispatch');
    // Defence-in-depth BEFORE typed decoding: the server-derived subtree may
    // never carry money/PII vocabulary, even in fields we would reject as
    // unknown anyway.
    rejectHostileKitchenKeys(dispatchRaw, path: 'dispatch');
    final payload = KitchenSpoolLocalPayload(
      dispatch: KitchenDispatchDocument.fromJson(dispatchRaw),
      destination: KitchenSpoolDestination.fromJson(
        r.requireMap('destination'),
      ),
      paperWidth: r.optionalString('paper_width', allowed: {'58mm', '80mm'}),
      documentVersion: r.requirePositiveInt('document_version'),
      rasterVersion: r.requirePositiveInt('raster_version'),
      // Consumed here so the strict reader accepts it; absent on legacy rows
      // (decodes null). NOT part of the redaction-checked `dispatch` subtree.
      customerPhone: r.optionalString('customer_phone'),
    );
    r.finish();
    return payload;
  }
}

/// The typed, money-free server dispatch document (closed mirror of the
/// server payload builders' output — initial order / round delta / void).
final class KitchenDispatchDocument {
  KitchenDispatchDocument({
    required this.serverPayloadVersion,
    required this.kind,
    required this.orderCode,
    required this.orderType,
    this.tableLabel,
    this.customerDisplayName,
    this.customerPhone,
    this.orderNote,
    this.createdAt,
    this.items = const [],
    this.roundId,
    this.roundNumber,
    this.reason,
    this.voidMarker = false,
    this.voidedAt,
    this.affectedItemCount,
  });

  final int serverPayloadVersion;
  final KitchenSpoolDispatchType kind;
  final String orderCode;
  final String orderType;
  final String? tableLabel;
  final String? customerDisplayName;

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL customer phone, a TYPED
  /// field of THIS encrypted, backup-excluded spool document — so a crash-recovery
  /// reprint of a doc that carries a phone still prints it. It is NOT part of the
  /// untyped server payload that `rejectHostileKitchenKeys` guards (that generic
  /// redaction is unchanged and still forbids untyped phone/PII keys); legacy rows
  /// simply decode this as null. Money-free display text.
  final String? customerPhone;
  final String? orderNote;
  final String? createdAt;
  final List<KitchenDispatchItem> items;
  final String? roundId;
  final int? roundNumber;
  final String? reason;
  final bool voidMarker;
  final String? voidedAt;
  final int? affectedItemCount;

  Map<String, Object?> toJson() => {
    'v': serverPayloadVersion,
    'kind': kind.wireName,
    'order_code': orderCode,
    'order_type': orderType,
    if (tableLabel != null) 'table_label': tableLabel,
    if (customerDisplayName != null)
      'customer_display_name': customerDisplayName,
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: customerPhone is DELIBERATELY NOT
    // serialized here — it is a TRANSIENT render-time field for the locally-built
    // direct-print document only. Persisting it would (a) place a phone token in a
    // spool blob whose decrypt re-runs rejectHostileKitchenKeys (which forbids
    // phone keys) and (b) require weakening that generic redaction. So a
    // server-imported spool doc never carries it; a crash-recovery reprint of such
    // a doc degrades to name-only (privacy-preserving), while the direct-print +
    // POS/KDS reprints render it from the live order/cart.
    if (orderNote != null) 'order_note': orderNote,
    if (createdAt != null) 'created_at': createdAt,
    if (items.isNotEmpty) 'items': [for (final i in items) i.toJson()],
    if (roundId != null) 'round_id': roundId,
    if (roundNumber != null) 'round_number': roundNumber,
    if (reason != null) 'reason': reason,
    if (voidMarker) 'void': true,
    if (voidedAt != null) 'voided_at': voidedAt,
    if (affectedItemCount != null) 'affected_item_count': affectedItemCount,
  };

  static KitchenDispatchDocument fromJson(Map<String, Object?> raw) {
    final r = _StrictReader(raw, 'dispatch');
    final doc = KitchenDispatchDocument(
      serverPayloadVersion: r.requirePositiveInt('v'),
      kind: _dispatchKind(r.requireString('kind')),
      orderCode: r.requireString('order_code'),
      orderType: r.requireString('order_type'),
      tableLabel: r.optionalString('table_label'),
      customerDisplayName: r.optionalString('customer_display_name'),
      orderNote: r.optionalString('order_note'),
      createdAt: r.optionalString('created_at'),
      items: [
        for (final item in r.optionalList('items'))
          KitchenDispatchItem.fromJson(_requireObject(item, 'dispatch.items')),
      ],
      roundId: r.optionalString('round_id'),
      roundNumber: r.optionalInt('round_number'),
      reason: r.optionalString('reason'),
      voidMarker: r.optionalBool('void') ?? false,
      voidedAt: r.optionalString('voided_at'),
      affectedItemCount: r.optionalInt('affected_item_count'),
    );
    r.finish();
    return doc;
  }
}

/// CLEANUP 3: every malformed/unknown dispatch kind is the module's TYPED
/// payload exception — never a raw [ArgumentError] escaping the closed decode
/// boundary, and never echoing the unknown content.
KitchenSpoolDispatchType _dispatchKind(String wire) {
  try {
    return KitchenSpoolDispatchType.fromWire(wire);
  } on ArgumentError {
    throw const KitchenSpoolPayloadFormatException(
      'dispatch.kind is not a supported dispatch type',
    );
  }
}

/// One dispatched item line (qty/name/note/prep/modifiers — never money).
final class KitchenDispatchItem {
  KitchenDispatchItem({
    required this.qty,
    required this.name,
    this.note,
    this.prep = const [],
    this.modifiers = const [],
  });

  final int qty;
  final String name;
  final String? note;
  final List<KitchenDispatchPrepComponent> prep;
  final List<KitchenDispatchModifier> modifiers;

  Map<String, Object?> toJson() => {
    'qty': qty,
    'name': name,
    if (note != null) 'note': note,
    if (prep.isNotEmpty) 'prep': [for (final p in prep) p.toJson()],
    'modifiers': [for (final m in modifiers) m.toJson()],
  };

  static KitchenDispatchItem fromJson(Map<String, Object?> raw) {
    final r = _StrictReader(raw, 'item');
    final item = KitchenDispatchItem(
      // CLEANUP 7D: a dispatched line always has a POSITIVE quantity (matches
      // the server's order contract); no arbitrary upper cap — large real
      // restaurant quantities stay legal.
      qty: r.requirePositiveInt('qty'),
      name: r.requireString('name'),
      note: r.optionalString('note'),
      prep: [
        for (final p in r.optionalList('prep'))
          KitchenDispatchPrepComponent.fromJson(_requireObject(p, 'item.prep')),
      ],
      modifiers: [
        for (final m in r.optionalList('modifiers'))
          KitchenDispatchModifier.fromJson(_requireObject(m, 'item.modifiers')),
      ],
    );
    r.finish();
    return item;
  }
}

/// One allowlisted prep component ({name, quantity, unit} — KITCHEN-PREP-001),
/// plus the optional KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 classifier triple.
final class KitchenDispatchPrepComponent {
  KitchenDispatchPrepComponent({
    this.name,
    this.quantity,
    this.unit,
    this.classifierOptionId,
    this.classifierOptionName,
    this.classifierSelected,
  });

  final String? name;
  final num? quantity;
  final String? unit;

  /// 017 (Codex BLOCKER #1): the classifier link + its order-time answer,
  /// carried through the durable spool so a crash-recovery reprint shows the
  /// SAME with/without split the direct print and the KDS show. Before this the
  /// closed decoder had no field for them at all — the server projection
  /// dropped them, and had it not, `finish()` would have rejected the whole
  /// otherwise-valid ticket.
  ///
  /// All three are optional and only ever meaningful together; see
  /// [isClassified].
  final String? classifierOptionId;
  final String? classifierOptionName;
  final bool? classifierSelected;

  /// True only when the triple is complete — a partial/degraded set is treated
  /// as an ordinary unsplit resource.
  bool get isClassified =>
      classifierOptionId != null &&
      classifierOptionName != null &&
      classifierSelected != null;

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (quantity != null) 'quantity': quantity,
    if (unit != null) 'unit': unit,
    if (classifierOptionId != null) 'classifier_option_id': classifierOptionId,
    if (classifierOptionName != null)
      'classifier_option_name': classifierOptionName,
    if (classifierSelected != null) 'classifier_selected': classifierSelected,
  };

  static KitchenDispatchPrepComponent fromJson(Map<String, Object?> raw) {
    final r = _StrictReader(raw, 'prep');
    final prep = KitchenDispatchPrepComponent(
      name: r.optionalString('name'),
      // CLEANUP 7D: prep components follow the KITCHEN-PREP-001 contract —
      // a count/measure that may be fractional but never zero/negative.
      quantity: r.optionalPositiveNum('quantity'),
      unit: r.optionalString('unit'),
      // 017: DEGRADING reads — a wrong-typed or empty classifier field yields
      // null instead of throwing, so a malformed classifier costs the split and
      // nothing else. Rejecting here would discard an otherwise valid ticket and
      // leave the kitchen with NO paper, which is far worse than an unsplit
      // resource. Every other field keeps its strict, throwing decode.
      classifierOptionId: r.degradingString('classifier_option_id'),
      classifierOptionName: r.degradingString('classifier_option_name'),
      classifierSelected: r.degradingBool('classifier_selected'),
    );
    r.finish();
    // A half-present triple is not a classification: drop it to unsplit rather
    // than print a bucket the operator never configured.
    if (prep.isClassified) return prep;
    return KitchenDispatchPrepComponent(
      name: prep.name,
      quantity: prep.quantity,
      unit: prep.unit,
    );
  }
}

/// One modifier line ({qty, name}) plus — KITCHEN-MODIFIER-PREP-CLASSIFIER-019
/// — its OWN optional kitchen preparation contribution.
final class KitchenDispatchModifier {
  KitchenDispatchModifier({required this.qty, required this.name, this.prep});

  final int qty;
  final String name;

  /// 019: the option's own preparation contribution — where Saleh's meat
  /// actually lives (a 240g size option contributes 2 Meat pieces) — together
  /// with the classifier that re-buckets it. Null when the option has no
  /// "count in preparation total" contribution, which is every option today,
  /// so an existing payload encodes byte-identically.
  ///
  /// Before 019 the server projected each modifier as {qty, name} only, so this
  /// contribution never reached the durable spool at all: the direct print and
  /// the KDS showed it, the crash-recovery ticket did not.
  final KitchenDispatchModifierPrep? prep;

  Map<String, Object?> toJson() => {
    'qty': qty,
    'name': name,
    if (prep != null) 'prep': prep!.toJson(),
  };

  static KitchenDispatchModifier fromJson(Map<String, Object?> raw) {
    final r = _StrictReader(raw, 'modifier');
    final prepRaw = r.optionalMap('prep');
    final m = KitchenDispatchModifier(
      qty: r.requirePositiveInt('qty'),
      name: r.requireString('name'),
      prep: prepRaw == null
          ? null
          : KitchenDispatchModifierPrep.fromJson(prepRaw),
    );
    r.finish();
    return m;
  }
}

/// One modifier option's preparation contribution ({quantity, unit}) plus the
/// optional 019 classifier triple. Mirrors the server's
/// `app.kitchen_modifier_prep_projection` allowlist exactly.
final class KitchenDispatchModifierPrep {
  KitchenDispatchModifierPrep({
    this.quantity,
    this.unit,
    this.classifierOptionId,
    this.classifierOptionName,
    this.classifierSelected,
  });

  final num? quantity;
  final String? unit;
  final String? classifierOptionId;
  final String? classifierOptionName;
  final bool? classifierSelected;

  /// True only when the triple is complete — a partial/degraded set is treated
  /// as an ordinary unsplit contribution.
  bool get isClassified =>
      classifierOptionId != null &&
      classifierOptionName != null &&
      classifierSelected != null;

  Map<String, Object?> toJson() => {
    if (quantity != null) 'quantity': quantity,
    if (unit != null) 'unit': unit,
    if (classifierOptionId != null) 'classifier_option_id': classifierOptionId,
    if (classifierOptionName != null)
      'classifier_option_name': classifierOptionName,
    if (classifierSelected != null) 'classifier_selected': classifierSelected,
  };

  static KitchenDispatchModifierPrep fromJson(Map<String, Object?> raw) {
    final r = _StrictReader(raw, 'modifier.prep');
    final prep = KitchenDispatchModifierPrep(
      // The contribution itself keeps the strict KITCHEN-MEAT-001 contract —
      // a count that may be fractional but never zero/negative.
      quantity: r.optionalPositiveNum('quantity'),
      unit: r.optionalString('unit'),
      // 019: DEGRADING reads — a wrong-typed or empty classifier field yields
      // null instead of throwing, so a malformed classifier costs the split and
      // nothing else. Rejecting here would discard an otherwise valid ticket and
      // leave the kitchen with NO paper, which is far worse than an unsplit
      // contribution.
      classifierOptionId: r.degradingString('classifier_option_id'),
      classifierOptionName: r.degradingString('classifier_option_name'),
      classifierSelected: r.degradingBool('classifier_selected'),
    );
    r.finish();
    // A half-present triple is not a classification: drop it to unsplit rather
    // than print a bucket the operator never configured.
    if (prep.isClassified) return prep;
    return KitchenDispatchModifierPrep(
      quantity: prep.quantity,
      unit: prep.unit,
    );
  }

  /// 020 (Codex HIGH #3) — the DEFENSIVE client mirror of the server gate.
  ///
  /// A contribution is only real when it has BOTH a strictly-positive finite
  /// quantity AND a usable unit. The server projection now refuses to emit
  /// anything else, but a payload written by an older server (or a corrupted
  /// row) could still carry a unit with no count — and the renderer would have
  /// printed a bullet naming a resource with no number, which reads to the
  /// kitchen as an instruction it cannot follow.
  ///
  /// A malformed CLASSIFIER never reaches this: it degrades to unsplit above,
  /// and the contribution survives.
  bool get isRenderable {
    final q = quantity;
    return q != null &&
        q > 0 &&
        q.isFinite &&
        (unit?.trim().isNotEmpty ?? false);
  }
}

/// The pinned printer destination — endpoint data lives ONLY here, inside
/// the encrypted model, never in plaintext columns.
sealed class KitchenSpoolDestination {
  const KitchenSpoolDestination();

  Map<String, Object?> toJson();

  static KitchenSpoolDestination fromJson(Map<String, Object?> raw) {
    final r = _StrictReader(raw, 'destination');
    final kind = r.requireString('kind');
    switch (kind) {
      case 'network':
        final d = NetworkKitchenDestination(
          host: r.requireString('host'),
          port: r.requireInt('port'),
        );
        r.finish();
        if (d.port < 1 || d.port > 65535) {
          throw const KitchenSpoolPayloadFormatException(
            'network port out of range',
          );
        }
        return d;
      case 'bluetooth':
        final d = BluetoothKitchenDestination(
          address: r.requireString('address'),
        );
        r.finish();
        return d;
      case 'none':
        r.finish();
        return const MissingKitchenDestination();
      default:
        throw const KitchenSpoolPayloadFormatException(
          'unknown destination kind',
        );
    }
  }
}

/// A network (ESC/POS over TCP) kitchen printer.
final class NetworkKitchenDestination extends KitchenSpoolDestination {
  const NetworkKitchenDestination({required this.host, required this.port});

  final String host;
  final int port;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'network',
    'host': host,
    'port': port,
  };
}

/// A Bluetooth (SPP) kitchen printer.
final class BluetoothKitchenDestination extends KitchenSpoolDestination {
  const BluetoothKitchenDestination({required this.address});

  final String address;

  @override
  Map<String, Object?> toJson() => {'kind': 'bluetooth', 'address': address};
}

/// No runnable destination: the job imports as `blockedConfiguration`, the
/// authoritative dispatch document is still encrypted and preserved.
final class MissingKitchenDestination extends KitchenSpoolDestination {
  const MissingKitchenDestination();

  @override
  Map<String, Object?> toJson() => {'kind': 'none'};
}

// ---------------------------------------------------------------------------
// Defence-in-depth hostile-key validator (server-derived subtree only —
// mirrors the server guard's token-boundary rules).
// ---------------------------------------------------------------------------

const Set<String> _hostileTokens = {
  'price',
  'prices',
  'subtotal',
  'subtotals',
  'total',
  'totals',
  'paid',
  'amount',
  'amounts',
  'change',
  'currency',
  'currencies',
  'payment',
  'payments',
  'tender',
  'tendered',
  'tax',
  'taxes',
  'discount',
  'discounts',
  'tip',
  'tips',
  'fee',
  'fees',
  'phone',
  'phones',
  'address',
  'addresses',
  'email',
  'emails',
  'host',
  'hosts',
  'port',
  'ports',
  'token',
  'tokens',
  'credential',
  'credentials',
  'secret',
  'secrets',
  'password',
  'passwords',
  'minor',
};

final RegExp _boundary = RegExp('[^A-Za-z0-9]+');
final RegExp _acronym = RegExp('([A-Z]+)([A-Z][a-z])');
final RegExp _camel = RegExp('([a-z0-9])([A-Z])');

String _normalizeKey(String key) {
  var k = key.replaceAllMapped(_acronym, (m) => '${m[1]}_${m[2]}');
  k = k.replaceAllMapped(_camel, (m) => '${m[1]}_${m[2]}');
  k = k.replaceAll(_boundary, '_').toLowerCase();
  k = k.replaceAll(RegExp('_+'), '_');
  if (k.startsWith('_')) k = k.substring(1);
  if (k.endsWith('_')) k = k.substring(0, k.length - 1);
  return k;
}

/// Recursively rejects money/PII/endpoint vocabulary at every nesting level
/// of a server-derived JSON subtree. Keys only; values are never judged.
void rejectHostileKitchenKeys(Object? node, {required String path}) {
  if (node is Map<String, Object?>) {
    for (final entry in node.entries) {
      final norm = _normalizeKey(entry.key);
      final tokens = norm.split('_');
      final hostile =
          tokens.any(_hostileTokens.contains) ||
          RegExp('(^|_)api_keys?(_|\$)').hasMatch(norm) ||
          RegExp('(^|_)connection_configs?(_|\$)').hasMatch(norm);
      if (hostile) {
        throw KitchenSpoolPayloadFormatException(
          'hostile key "${entry.key}" at $path',
        );
      }
      rejectHostileKitchenKeys(entry.value, path: '$path.${entry.key}');
    }
  } else if (node is List) {
    for (final child in node) {
      rejectHostileKitchenKeys(child, path: '$path[]');
    }
  }
}

// ---------------------------------------------------------------------------
// Strict reader: every decode level consumes exactly its known keys.
// ---------------------------------------------------------------------------

Map<String, Object?> _requireObject(Object? value, String path) {
  if (value is Map<String, Object?>) return value;
  throw KitchenSpoolPayloadFormatException('$path element is not an object');
}

final class _StrictReader {
  _StrictReader(this._map, this._context);

  final Map<String, Object?> _map;
  final String _context;
  final Set<String> _consumed = {};

  Object? _take(String key) {
    _consumed.add(key);
    return _map[key];
  }

  String requireString(String key) {
    final v = _take(key);
    if (v is String && v.isNotEmpty) return v;
    throw KitchenSpoolPayloadFormatException(
      '$_context.$key must be a non-empty string',
    );
  }

  String? optionalString(String key, {Set<String>? allowed}) {
    final v = _take(key);
    if (v == null) return null;
    if (v is! String || v.isEmpty) {
      throw KitchenSpoolPayloadFormatException(
        '$_context.$key must be a non-empty string when present',
      );
    }
    if (allowed != null && !allowed.contains(v)) {
      throw KitchenSpoolPayloadFormatException(
        '$_context.$key has an unsupported value',
      );
    }
    return v;
  }

  int requireInt(String key) {
    final v = _take(key);
    if (v is int) return v;
    throw KitchenSpoolPayloadFormatException(
      '$_context.$key must be an integer',
    );
  }

  int requirePositiveInt(String key) {
    final v = requireInt(key);
    if (v <= 0) {
      throw KitchenSpoolPayloadFormatException(
        '$_context.$key must be a positive integer',
      );
    }
    return v;
  }

  num? optionalPositiveNum(String key) {
    final v = optionalNum(key);
    if (v == null) return null;
    if (v <= 0 || !v.isFinite) {
      throw KitchenSpoolPayloadFormatException(
        '$_context.$key must be a positive finite number when present',
      );
    }
    return v;
  }

  int? optionalInt(String key) {
    final v = _take(key);
    if (v == null) return null;
    if (v is int) return v;
    throw KitchenSpoolPayloadFormatException(
      '$_context.$key must be an integer when present',
    );
  }

  num? optionalNum(String key) {
    final v = _take(key);
    if (v == null) return null;
    if (v is num) return v;
    throw KitchenSpoolPayloadFormatException(
      '$_context.$key must be a number when present',
    );
  }

  /// 017: a DEGRADING optional string — consumed (so `finish()` still closes
  /// the object) but a wrong type or an empty value yields null instead of
  /// throwing. Reserved for fields whose loss costs a display refinement, never
  /// correctness; every identity/quantity field keeps [requireString] /
  /// [optionalString].
  String? degradingString(String key) {
    final v = _take(key);
    if (v is! String) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 017: a DEGRADING optional boolean — see [degradingString].
  bool? degradingBool(String key) {
    final v = _take(key);
    return v is bool ? v : null;
  }

  bool? optionalBool(String key) {
    final v = _take(key);
    if (v == null) return null;
    if (v is bool) return v;
    throw KitchenSpoolPayloadFormatException(
      '$_context.$key must be a boolean when present',
    );
  }

  Map<String, Object?> requireMap(String key) {
    final v = _take(key);
    if (v is Map<String, Object?>) return v;
    throw KitchenSpoolPayloadFormatException(
      '$_context.$key must be an object',
    );
  }

  /// 019: an OPTIONAL nested object — absent yields null (every payload written
  /// before this feature), a present non-object is still corruption and throws.
  Map<String, Object?>? optionalMap(String key) {
    final v = _take(key);
    if (v == null) return null;
    if (v is Map<String, Object?>) return v;
    throw KitchenSpoolPayloadFormatException(
      '$_context.$key must be an object when present',
    );
  }

  List<Object?> optionalList(String key) {
    final v = _take(key);
    if (v == null) return const [];
    if (v is List) return v;
    throw KitchenSpoolPayloadFormatException(
      '$_context.$key must be an array when present',
    );
  }

  /// CLOSED decoding: any key not consumed by the typed reader is rejected —
  /// unknown server fields never silently persist inside an encrypted blob.
  void finish() {
    for (final key in _map.keys) {
      if (!_consumed.contains(key)) {
        throw KitchenSpoolPayloadFormatException(
          'unknown key "$key" in $_context',
        );
      }
    }
  }
}
