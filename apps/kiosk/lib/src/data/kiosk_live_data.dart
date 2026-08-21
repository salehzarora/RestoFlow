import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import 'kiosk_fixtures.dart';
import 'kiosk_menu_data.dart';

/// KIOSK-001 Phase 3 — the live `kiosk_menu` / `kiosk_tables` read layer.
///
/// Both RPCs are token-proven device reads (the exact
/// `get_device_printer_assignments` convention): params are always
/// `{p_device_id, p_session_token}` from the stored credential — never
/// client-asserted identity — and every failure maps to a TYPED kind so no
/// PostgREST text ever reaches a customer surface. The kiosk is
/// ONLINE-REQUIRED: there is no offline cache of table truth and no offline
/// order capability of any kind.
enum KioskReadFailureKind {
  /// The stored session no longer opens the server (missing credential,
  /// revoked/expired session, wrong device type). The gate returns the app
  /// to the activation state.
  invalidSession,

  /// Transient transport trouble — show the reconnect state and retry.
  network,

  /// The server answered but the read is unusable (unexpected envelope,
  /// unreadable payload, server error). Shown as the honest unavailable state.
  unavailable,
}

sealed class KioskReadResult<T> {
  const KioskReadResult();
}

final class KioskReadOk<T> extends KioskReadResult<T> {
  const KioskReadOk(this.value);
  final T value;
}

final class KioskReadError<T> extends KioskReadResult<T> {
  const KioskReadError(this.kind);
  final KioskReadFailureKind kind;
}

/// The one client of the two live kiosk reads.
class KioskLiveReads {
  KioskLiveReads({
    required this._transport,
    required DeviceSessionSecretStore secretStore,
  }) : _store = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _store;

  Future<KioskReadResult<KioskMenuData>> fetchMenu() =>
      _invoke('kiosk_menu', mapKioskMenuEnvelope);

  Future<KioskReadResult<List<KioskFixtureZone>>> fetchTables() =>
      _invoke('kiosk_tables', mapKioskTablesEnvelope);

  Future<KioskReadResult<T>> _invoke<T>(
    String rpc,
    T? Function(Map<dynamic, dynamic> raw) parse,
  ) async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      return const KioskReadError(KioskReadFailureKind.invalidSession);
    }
    if (cred == null) {
      return const KioskReadError(KioskReadFailureKind.invalidSession);
    }
    final Object? raw;
    try {
      raw = await _transport.invoke(rpc, <String, dynamic>{
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
      });
    } on SyncTransportException catch (e) {
      return KioskReadError(switch (e.kind) {
        SyncTransportErrorKind.auth => KioskReadFailureKind.invalidSession,
        SyncTransportErrorKind.transient => KioskReadFailureKind.network,
        _ => KioskReadFailureKind.unavailable,
      });
    } catch (_) {
      return const KioskReadError(KioskReadFailureKind.network);
    }
    if (raw is! Map || raw['ok'] != true) {
      final error = raw is Map ? raw['error'] : null;
      return KioskReadError(
        error == 'invalid_session'
            ? KioskReadFailureKind.invalidSession
            : KioskReadFailureKind.unavailable,
      );
    }
    final T? parsed;
    try {
      parsed = parse(raw);
    } catch (_) {
      return const KioskReadError(KioskReadFailureKind.unavailable);
    }
    if (parsed == null) {
      return const KioskReadError(KioskReadFailureKind.unavailable);
    }
    return KioskReadOk(parsed);
  }
}

// ---------------------------------------------------------------------------
// kiosk_menu envelope → KioskMenuData
//
// Tolerance mirrors the POS pos_menu parser's money boundary: a missing or
// non-integer money value is NEVER defaulted — a broken item price skips the
// item, a broken modifier configuration keeps the item VISIBLE but
// unavailable (configuration unreadable), so a customer can never build a
// cart the server would refuse for reasons the screen hid.
// ---------------------------------------------------------------------------

String? _optionalText(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

KioskMenuData? mapKioskMenuEnvelope(Map<dynamic, dynamic> raw) {
  final currency = raw['currency_code'];
  final currencyCode = currency is String && currency.length == 3
      ? currency
      : 'ILS';

  final rawCategories = raw['categories'];
  final rawItems = raw['items'];
  final rawGroups = raw['modifiers'];
  final rawOptions = raw['modifier_options'];
  if (rawCategories is! List || rawItems is! List) return null;

  // options per group id, in server (display_order, name) order.
  final optionsByGroup = <String, List<KioskFixtureOption>>{};
  final brokenOptionGroups = <String>{};
  if (rawOptions is List) {
    for (final row in rawOptions) {
      if (row is! Map) continue;
      final groupId = _optionalText(row['modifier_id']);
      final id = _optionalText(row['id']);
      if (groupId == null || id == null) continue;
      final name = _optionalText(row['name']);
      final delta = row['price_delta_minor'];
      if (name == null || delta is! int) {
        // A broken option poisons its whole group (money boundary).
        brokenOptionGroups.add(groupId);
        continue;
      }
      final meat = row['kitchen_meat'];
      (optionsByGroup[groupId] ??= []).add(
        KioskFixtureOption(
          id: id,
          name: KioskText3.same(name),
          priceDeltaMinor: delta,
          kitchenMeat: meat is Map ? Map<String, dynamic>.from(meat) : null,
        ),
      );
    }
  }

  // groups per item id; a broken group marks the item configuration-unreadable.
  final groups = <String, KioskFixtureGroup>{};
  final groupIdsByItem = <String, List<String>>{};
  final brokenConfigItems = <String>{};
  if (rawGroups is List) {
    for (final row in rawGroups) {
      if (row is! Map) continue;
      final id = _optionalText(row['id']);
      final itemId = _optionalText(row['menu_item_id']);
      if (id == null || itemId == null) continue;
      final name = _optionalText(row['name']);
      final options = optionsByGroup[id] ?? const [];
      if (name == null || options.isEmpty || brokenOptionGroups.contains(id)) {
        brokenConfigItems.add(itemId);
        continue;
      }
      final minSelect = row['min_select'];
      final maxSelect = row['max_select'];
      final maxQuantity = row['max_quantity'];
      groups[id] = KioskFixtureGroup(
        id: id,
        type: row['selection_type'] == 'single'
            ? KioskGroupType.single
            : KioskGroupType.multi,
        isRequired: row['is_required'] == true,
        minSelect: minSelect is int && minSelect > 0 ? minSelect : 0,
        maxSelect: maxSelect is int && maxSelect > 0 ? maxSelect : null,
        allowQuantity: row['allow_quantity'] == true,
        maxQuantity: maxQuantity is int && maxQuantity > 0 ? maxQuantity : null,
        displayName: KioskText3.same(name),
        options: options,
      );
      (groupIdsByItem[itemId] ??= []).add(id);
    }
  }

  // items per category, keeping server order.
  final itemsByCategory = <String, List<KioskFixtureItem>>{};
  for (final row in rawItems) {
    if (row is! Map) continue;
    final id = _optionalText(row['id']);
    final categoryId = _optionalText(row['menu_category_id']);
    final name = _optionalText(row['name']);
    final price = row['base_price_minor'];
    // The money boundary: a non-integer price is never defaulted — skip.
    if (id == null || categoryId == null || name == null || price is! int) {
      continue;
    }
    final broken = brokenConfigItems.contains(id);
    final unavailable = row['availability'] == 'unavailable';
    (itemsByCategory[categoryId] ??= []).add(
      KioskFixtureItem(
        id: id,
        name: KioskText3.same(name),
        description: KioskText3.same(_optionalText(row['description']) ?? ''),
        basePriceMinor: price,
        groupIds: broken ? const [] : (groupIdsByItem[id] ?? const []),
        imagePath: _optionalText(row['image_path']),
        available: !unavailable && !broken,
        availabilityReason: broken
            ? 'configuration_unreadable'
            : _optionalText(row['availability_reason']),
      ),
    );
  }

  final categories = <KioskFixtureCategory>[];
  for (final row in rawCategories) {
    if (row is! Map) continue;
    final id = _optionalText(row['id']);
    final name = _optionalText(row['name']);
    if (id == null || name == null) continue;
    categories.add(
      KioskFixtureCategory(
        id: id,
        name: KioskText3.same(name),
        items: itemsByCategory[id] ?? const [],
        iconData: MenuCategoryIcons.iconForCategoryKey(
          _optionalText(row['icon_key']),
        ),
      ),
    );
  }

  return KioskMenuData(
    categories: categories,
    groups: groups,
    currencyCode: currencyCode,
    live: true,
  );
}

// ---------------------------------------------------------------------------
// kiosk_tables envelope → zones
// ---------------------------------------------------------------------------

KioskTableState _tableState(Object? v) => switch (v) {
  'available' => KioskTableState.available,
  'occupied' => KioskTableState.occupied,
  'reserved' => KioskTableState.reserved,
  'out_of_service' => KioskTableState.outOfService,
  // Fail safe: a state this client does not understand is NEVER selectable.
  _ => KioskTableState.outOfService,
};

List<KioskFixtureZone>? mapKioskTablesEnvelope(Map<dynamic, dynamic> raw) {
  final rows = raw['tables'];
  if (rows is! List) return null;
  final tablesBySection = <String, List<KioskFixtureTable>>{};
  final sectionNames = <String, String?>{};
  final sectionOrder = <String, int>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final id = _optionalText(row['id']);
    final label = _optionalText(row['label']);
    if (id == null || label == null) continue;
    final seats = row['seats'];
    final sectionId = _optionalText(row['section_id']) ?? '';
    sectionNames[sectionId] ??= _optionalText(row['section_name']);
    final order = row['section_display_order'];
    if (order is int) sectionOrder[sectionId] = order;
    (tablesBySection[sectionId] ??= []).add(
      KioskFixtureTable(
        id: id,
        label: label,
        seats: seats is int && seats > 0 ? seats : 0,
        state: _tableState(row['effective_state']),
      ),
    );
  }
  final sectionIds = tablesBySection.keys.toList()
    ..sort((a, b) {
      final oa = sectionOrder[a] ?? 1 << 30;
      final ob = sectionOrder[b] ?? 1 << 30;
      if (oa != ob) return oa.compareTo(ob);
      return a.compareTo(b);
    });
  return [
    for (final sid in sectionIds)
      KioskFixtureZone(
        id: sid.isEmpty ? 'hall' : sid,
        displayName: sectionNames[sid],
        tables: tablesBySection[sid]!,
      ),
  ];
}
