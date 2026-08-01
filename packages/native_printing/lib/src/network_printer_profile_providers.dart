import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_printer_store.dart';
import 'network_printer_profiles.dart';
import 'printer_config.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — the saved network printer list for apps that
/// use the SHARED native printer store (the KDS today).
///
/// Namespaced exactly like the single-config store
/// (`<prefix>.<namespace>.<deviceSegment>`), so a KDS list can never be read by
/// the POS, by another device, or by another app on the same machine. The POS
/// has its own controller only because its keys are additionally slot-scoped by
/// `PosPrinterPurpose`; both sit on this same [NetworkPrinterProfileStore].

const String kNetworkProfilesKeyPrefix = 'restoflow.printer.network_profiles.';
const String kNetworkProfileActiveKeyPrefix =
    'restoflow.printer.network_profile_active.';

/// The saved profiles + active selection for this app's network printer.
class NetworkProfilesState {
  const NetworkProfilesState({
    this.profiles = const <NetworkPrinterProfile>[],
    this.activeId,
  });

  final List<NetworkPrinterProfile> profiles;

  /// Null = honestly unconfigured (never a silent fallback to some other row).
  final String? activeId;

  NetworkPrinterProfile? get active {
    for (final p in profiles) {
      if (p.id == activeId) return p;
    }
    return null;
  }
}

final networkPrinterProfilesProvider =
    AsyncNotifierProvider<
      NetworkPrinterProfilesController,
      NetworkProfilesState
    >(NetworkPrinterProfilesController.new);

class NetworkPrinterProfilesController
    extends AsyncNotifier<NetworkProfilesState> {
  Future<NetworkPrinterProfileStore> _store() async {
    final deviceId = ref.read(nativePrinterDeviceIdProvider);
    final namespace = ref.read(nativePrinterNamespaceProvider);
    final segment = (deviceId == null || deviceId.isEmpty)
        ? kNativePrinterLocalKey
        : deviceId;
    return NetworkPrinterProfileStore(
      prefs: await SharedPreferences.getInstance(),
      listKey: '$kNetworkProfilesKeyPrefix$namespace.$segment',
      activeKey: '$kNetworkProfileActiveKeyPrefix$namespace.$segment',
      legacyConfigKey: 'restoflow.printer.network.$namespace.$segment',
    );
  }

  Future<NetworkProfilesState> _load(NetworkPrinterProfileStore store) async =>
      NetworkProfilesState(
        profiles: await store.list(),
        activeId: await store.activeProfileId(),
      );

  @override
  Future<NetworkProfilesState> build() async {
    try {
      return await _load(await _store());
    } catch (_) {
      return const NetworkProfilesState();
    }
  }

  Future<NetworkPrinterProfile?> addProfile({
    required String name,
    required NetworkPrinterConfig config,
  }) async {
    final store = await _store();
    final added = await store.add(name: name, config: config);
    state = AsyncData(await _load(store));
    return added;
  }

  /// Editing the ACTIVE profile also re-writes the canonical single config so
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

  /// Deleting the ACTIVE profile leaves the slot honestly unconfigured — no
  /// unrelated profile is promoted.
  Future<void> removeProfile(String id) async {
    final store = await _store();
    await store.remove(id);
    state = AsyncData(await _load(store));
  }

  /// Makes [id] active and pushes its endpoint into the canonical config.
  /// Never prints anything.
  Future<void> selectProfile(String id) async {
    final store = await _store();
    await store.setActiveProfileId(id);
    final selected = await store.get(id);
    if (selected != null) await _applyToCanonicalConfig(selected);
    state = AsyncData(await _load(store));
  }

  /// One source of truth: the selection is applied through the EXISTING
  /// single-config controller the transports already read.
  ///
  /// The canonical controller's `build()` is async and its `save()` sets state
  /// immediately, so a save issued while the first load is still in flight
  /// would be overwritten by that load completing with the OLD value. Settle
  /// the load first, then write — the same ordering the POS controller already
  /// enforces internally.
  Future<void> _applyToCanonicalConfig(NetworkPrinterProfile profile) async {
    if (!isValidNetworkProfileConfig(profile.config)) return;
    try {
      await ref.read(networkPrinterConfigProvider.future);
    } catch (_) {
      // An unreadable existing config must not block applying the selection.
    }
    await ref.read(networkPrinterConfigProvider.notifier).save(profile.config);
  }
}
