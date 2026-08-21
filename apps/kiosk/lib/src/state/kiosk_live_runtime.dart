import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceImageUrlResolver;

import '../data/kiosk_fixtures.dart';
import '../data/kiosk_live_data.dart';
import '../data/kiosk_menu_data.dart';
import 'kiosk_flow_controller.dart';

/// KIOSK-001 Phase 3 — real-mode runtime state around the live reads.
///
/// The kiosk is ONLINE-REQUIRED (owner policy): no offline order queue, no
/// speculative table state, no persisted menu cache. The last good menu MAY
/// keep rendering through a transient reconnect (it is marked, never silently
/// re-priced — the cart goes stale instead), but table truth is always a
/// fresh read.
@immutable
class KioskLiveState {
  const KioskLiveState({
    this.menu,
    this.menuLoading = false,
    this.menuError,
    this.zones,
    this.tablesLoading = false,
    this.tablesError,
    this.tablesLoadedAt,
    this.sessionInvalid = false,
    this.imageUrls = const {},
  });

  /// Last good live menu (null until the first successful read).
  final KioskMenuData? menu;
  final bool menuLoading;
  final KioskReadFailureKind? menuError;

  /// KIOSK-001-PREREQ-083: object key → short-lived signed URL for the
  /// CURRENT menu's product photos, resolved in ONE batch through the shared
  /// device resolver after each successful menu read. In-memory only (URLs
  /// expire — nothing is persisted); a missing key simply renders the
  /// approved no-photo fallback.
  final Map<String, String> imageUrls;

  /// Latest live floor read (null until loaded; never cached across errors).
  final List<KioskFixtureZone>? zones;
  final bool tablesLoading;
  final KioskReadFailureKind? tablesError;
  final DateTime? tablesLoadedAt;

  /// Set when any read proves the device session dead — the pairing gate
  /// re-validates and returns the app to the activation state.
  final bool sessionInvalid;

  KioskLiveState copyWith({
    Object? menu = _sentinel,
    bool? menuLoading,
    Object? menuError = _sentinel,
    Object? zones = _sentinel,
    bool? tablesLoading,
    Object? tablesError = _sentinel,
    Object? tablesLoadedAt = _sentinel,
    bool? sessionInvalid,
    Map<String, String>? imageUrls,
  }) => KioskLiveState(
    menu: identical(menu, _sentinel) ? this.menu : menu as KioskMenuData?,
    menuLoading: menuLoading ?? this.menuLoading,
    menuError: identical(menuError, _sentinel)
        ? this.menuError
        : menuError as KioskReadFailureKind?,
    zones: identical(zones, _sentinel)
        ? this.zones
        : zones as List<KioskFixtureZone>?,
    tablesLoading: tablesLoading ?? this.tablesLoading,
    tablesError: identical(tablesError, _sentinel)
        ? this.tablesError
        : tablesError as KioskReadFailureKind?,
    tablesLoadedAt: identical(tablesLoadedAt, _sentinel)
        ? this.tablesLoadedAt
        : tablesLoadedAt as DateTime?,
    sessionInvalid: sessionInvalid ?? this.sessionInvalid,
    imageUrls: imageUrls ?? this.imageUrls,
  );

  static const _sentinel = Object();
}

/// The live reads client. Null in demo mode / tests; the real composition
/// root overrides it with the token-proven repository.
final kioskLiveReadsProvider = Provider<KioskLiveReads?>((ref) => null);

/// KIOSK-001-PREREQ-083: the device's ONLY media capability — the SHARED
/// abstract signed-URL resolver (server-gated per device session; read-only).
/// Null in demo mode / tests; the real composition root overrides it with the
/// egress-cached resolver from the device bootstrap. The kiosk never touches
/// a raw backend client or any bucket API directly.
final kioskImageResolverProvider = Provider<DeviceImageUrlResolver?>(
  (ref) => null,
);

/// How the table picker should present itself.
enum KioskTablesStatus { ready, loading, reconnect, unavailable }

typedef KioskTablesView = ({
  List<KioskFixtureZone> zones,
  KioskTablesStatus status,
  bool live,
});

/// The floor the picker renders. Demo mode serves the Phase-1 fixture floor
/// (busy-preset aware); the real root overrides this with the live
/// `kiosk_tables` read — fresh truth only, never a stale floor dressed as
/// current.
final kioskTablesViewProvider = Provider<KioskTablesView>((ref) {
  final busy = ref.watch(kioskFlowProvider.select((s) => s.busyFloor));
  return (
    zones: kioskFixtureZones(busy: busy),
    status: KioskTablesStatus.ready,
    live: false,
  );
});

/// Wall clock seam so staleness rules stay deterministic in tests.
final kioskClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Table data older than this must be re-read before a selection proceeds —
/// a stale floor must never look guaranteed (owner §14).
const Duration kKioskTablesFreshFor = Duration(seconds: 20);

final kioskLiveProvider = NotifierProvider<KioskLiveController, KioskLiveState>(
  KioskLiveController.new,
);

class KioskLiveController extends Notifier<KioskLiveState> {
  int _menuRequest = 0;
  int _tablesRequest = 0;

  @override
  KioskLiveState build() => const KioskLiveState();

  /// Loads (or reloads) the live menu. Keeps the last good menu rendering
  /// during a transient failure; on success the cart is revalidated against
  /// the fresh snapshot (stale prices surface, they never silently change).
  Future<void> loadMenu() async {
    final reads = ref.read(kioskLiveReadsProvider);
    if (reads == null) return;
    final request = ++_menuRequest;
    state = state.copyWith(menuLoading: true, menuError: null);
    final result = await reads.fetchMenu();
    if (request != _menuRequest) return; // superseded
    switch (result) {
      case KioskReadOk(:final value):
        state = state.copyWith(
          menu: value,
          menuLoading: false,
          menuError: null,
        );
        ref.read(kioskFlowProvider.notifier).revalidateCart(value);
        await _resolveMenuImages(value, request);
      case KioskReadError(:final kind):
        if (kind == KioskReadFailureKind.invalidSession) {
          _markSessionInvalid();
          return;
        }
        state = state.copyWith(menuLoading: false, menuError: kind);
    }
  }

  /// KIOSK-001-PREREQ-083: one batch signed-URL resolution per successful
  /// menu read, strictly fail-soft — the menu is already published and stays
  /// fully usable whether or not any photo resolves. Per-key denials are
  /// simply absent from the resolver's result (the card renders the approved
  /// fallback); a transport-level failure degrades to "no photos this load".
  Future<void> _resolveMenuImages(KioskMenuData menu, int request) async {
    final resolver = ref.read(kioskImageResolverProvider);
    final keys = <String>{
      for (final category in menu.categories)
        for (final item in category.items)
          if (item.imagePath case final String path when path.isNotEmpty) path,
    }.toList();
    if (resolver == null || keys.isEmpty) {
      if (request == _menuRequest) state = state.copyWith(imageUrls: const {});
      return;
    }
    Map<String, String> urls;
    try {
      urls = await resolver.signedUrlsFor(keys);
    } catch (_) {
      urls = const {};
    }
    if (request != _menuRequest) return; // superseded
    state = state.copyWith(imageUrls: urls);
  }

  /// Fresh floor read (entering the picker, the refresh affordance, and the
  /// pre-confirm staleness re-check).
  Future<void> refreshTables() async {
    final reads = ref.read(kioskLiveReadsProvider);
    if (reads == null) return;
    final request = ++_tablesRequest;
    state = state.copyWith(tablesLoading: true, tablesError: null);
    final result = await reads.fetchTables();
    if (request != _tablesRequest) return;
    switch (result) {
      case KioskReadOk(:final value):
        state = state.copyWith(
          zones: value,
          tablesLoading: false,
          tablesError: null,
          tablesLoadedAt: ref.read(kioskClockProvider)(),
        );
      case KioskReadError(:final kind):
        if (kind == KioskReadFailureKind.invalidSession) {
          _markSessionInvalid();
          return;
        }
        // No stale floor masquerading as live truth: an errored read drops
        // the previous zones instead of letting them look current.
        state = state.copyWith(
          zones: null,
          tablesLoading: false,
          tablesError: kind,
        );
    }
  }

  bool get tablesStale {
    final at = state.tablesLoadedAt;
    if (at == null) return true;
    return ref.read(kioskClockProvider)().difference(at) > kKioskTablesFreshFor;
  }

  void _markSessionInvalid() {
    state = state.copyWith(
      sessionInvalid: true,
      menuLoading: false,
      tablesLoading: false,
      zones: null,
    );
  }

  /// The pairing gate consumed the signal (re-validated the session).
  void acknowledgeSessionInvalid() =>
      state = state.copyWith(sessionInvalid: false);
}
