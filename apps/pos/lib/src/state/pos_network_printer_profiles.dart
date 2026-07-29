import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        NetworkPrinterProfile,
        NetworkPrinterProfileStore,
        isValidNetworkProfileConfig;
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart' show posPrinterScopeSegmentProvider;
import 'pos_network_printer_config.dart';
import 'pos_printer_purpose.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — the POS saved Wi-Fi/Ethernet printer list.
///
/// One list PER printer slot ([PosPrinterPurpose]) and PER paired device, keyed
/// off the same authoritative `PosPrinterScope` segment the single-config store
/// already waits for — so a list can never be read from, or written into, the
/// wrong device namespace during a cold start.
///
/// The selected profile DRIVES the existing canonical
/// [posNetworkPrinterConfigFamily] rather than becoming a second source of
/// truth: selecting writes the profile's endpoint through the existing
/// `save()`, so Test Print, the receipt bridge, the kitchen bridge and the
/// cold-start resolution all keep reading exactly the provider they already do.

/// The profile LIST key for a slot + device: mirrors the single-config key
/// shape (`restoflow.printer.network.pos.<slot><segment>`) in its own space.
const String kPosNetworkProfilesKeyPrefix =
    'restoflow.printer.network_profiles.pos.';

/// The ACTIVE profile id key for a slot + device.
const String kPosNetworkProfileActiveKeyPrefix =
    'restoflow.printer.network_profile_active.pos.';

/// The saved profiles + active selection for ONE POS printer slot.
class PosNetworkProfilesState {
  const PosNetworkProfilesState({
    this.profiles = const <NetworkPrinterProfile>[],
    this.activeId,
  });

  final List<NetworkPrinterProfile> profiles;

  /// Null = this slot is honestly unconfigured (never a silent fallback).
  final String? activeId;

  NetworkPrinterProfile? get active {
    for (final p in profiles) {
      if (p.id == activeId) return p;
    }
    return null;
  }
}

final posNetworkPrinterProfilesFamily =
    AsyncNotifierProvider.family<
      PosNetworkPrinterProfilesController,
      PosNetworkProfilesState,
      PosPrinterPurpose
    >(PosNetworkPrinterProfilesController.new);

/// The CUSTOMER-RECEIPT slot's saved printers.
final posNetworkPrinterProfilesProvider = posNetworkPrinterProfilesFamily(
  PosPrinterPurpose.customerReceipt,
);

/// The KITCHEN-TICKET slot's saved printers — fully independent of the receipt
/// slot: selecting here never changes the receipt endpoint, and vice versa.
final posKitchenNetworkPrinterProfilesProvider =
    posNetworkPrinterProfilesFamily(PosPrinterPurpose.kitchenTicket);

class PosNetworkPrinterProfilesController
    extends FamilyAsyncNotifier<PosNetworkProfilesState, PosPrinterPurpose> {
  Future<NetworkPrinterProfileStore> _store() async {
    // Wait for the AUTHORITATIVE device scope before touching any key.
    final segment = await ref.read(posPrinterScopeSegmentProvider.future);
    final slot = arg.keySegment;
    return NetworkPrinterProfileStore(
      prefs: await SharedPreferences.getInstance(),
      listKey: '$kPosNetworkProfilesKeyPrefix$slot$segment',
      activeKey: '$kPosNetworkProfileActiveKeyPrefix$slot$segment',
      legacyConfigKey: '$kPosNetworkPrinterKeyPrefix$slot$segment',
    );
  }

  Future<PosNetworkProfilesState> _load(
    NetworkPrinterProfileStore store,
  ) async {
    final profiles = await store.list();
    return PosNetworkProfilesState(
      profiles: profiles,
      activeId: await store.activeProfileId(),
    );
  }

  @override
  Future<PosNetworkProfilesState> build(PosPrinterPurpose arg) async {
    try {
      return await _load(await _store());
    } catch (_) {
      // Unreadable prefs degrade to "no saved printers", never a crash.
      return const PosNetworkProfilesState();
    }
  }

  /// Saves a new profile. Returns it, or the EXISTING profile for the same
  /// normalized endpoint; null when the input is invalid (nothing is stored).
  Future<NetworkPrinterProfile?> addProfile({
    required String name,
    required PosNetworkPrinterConfig config,
  }) async {
    final store = await _store();
    final added = await store.add(name: name, config: config);
    state = AsyncData(await _load(store));
    return added;
  }

  /// Renames / re-points an existing profile, preserving its id. Returns false
  /// (changing nothing) on invalid input or an endpoint collision.
  ///
  /// Editing the ACTIVE profile also re-writes the canonical single config, so
  /// production printing follows the edit immediately.
  Future<bool> updateProfile(NetworkPrinterProfile profile) async {
    final store = await _store();
    final ok = await store.update(profile);
    if (ok && await store.activeProfileId() == profile.id) {
      await _applyToCanonicalConfig(profile);
    }
    state = AsyncData(await _load(store));
    return ok;
  }

  /// Deletes a profile. Deleting the ACTIVE one leaves the slot honestly
  /// unconfigured — no unrelated profile is promoted, and the canonical config
  /// is deliberately left as-is rather than silently repointed.
  Future<void> removeProfile(String id) async {
    final store = await _store();
    await store.remove(id);
    state = AsyncData(await _load(store));
  }

  /// Makes [id] the active printer for this slot and pushes its endpoint into
  /// the canonical config. Never prints anything.
  Future<void> selectProfile(String id) async {
    final store = await _store();
    await store.setActiveProfileId(id);
    final selected = await store.get(id);
    if (selected != null) await _applyToCanonicalConfig(selected);
    state = AsyncData(await _load(store));
  }

  /// The single place a profile becomes the slot's live endpoint. Writing
  /// through the EXISTING controller keeps one source of truth.
  Future<void> _applyToCanonicalConfig(NetworkPrinterProfile profile) async {
    if (!isValidNetworkProfileConfig(profile.config)) return;
    await ref
        .read(posNetworkPrinterConfigFamily(arg).notifier)
        .save(profile.config);
  }
}
