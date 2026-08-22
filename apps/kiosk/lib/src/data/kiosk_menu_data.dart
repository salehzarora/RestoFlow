import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kiosk_fixtures.dart';

/// KIOSK-001 Phase 3 — the ONE menu snapshot every screen and the flow
/// controller read. Demo mode publishes [KioskMenuData.fixtures] (the Phase-1
/// dataset, byte-identical behavior); real mode publishes the mapped live
/// `kiosk_menu` envelope. The approved V2 UI renders whichever is current —
/// it never knows which mode it is in.
@immutable
class KioskMenuData {
  const KioskMenuData({
    required this.categories,
    required this.groups,
    required this.currencyCode,
    required this.live,
  });

  /// The Phase-1 fixture dataset (demo mode and every existing test).
  factory KioskMenuData.fixtures() => KioskMenuData(
    categories: kioskFixtureMenu,
    groups: kioskFixtureGroups,
    currencyCode: 'ILS',
    live: false,
  );

  /// Real mode before the first successful live read: nothing to sell yet —
  /// the menu screen shows its honest loading/unavailable state instead of
  /// ever letting fixture data masquerade as the tenant's menu.
  const KioskMenuData.empty()
    : categories = const [],
      groups = const {},
      currencyCode = 'ILS',
      live = true;

  final List<KioskFixtureCategory> categories;

  /// group id → group (an item references groups by [KioskFixtureItem.groupIds]).
  final Map<String, KioskFixtureGroup> groups;

  /// The tenant currency from the live envelope ('ILS' for fixtures).
  final String currencyCode;

  /// True when this snapshot came from the live `kiosk_menu` read.
  final bool live;

  bool get isEmpty => categories.isEmpty;

  KioskFixtureItem? tryItem(String id) {
    for (final c in categories) {
      for (final it in c.items) {
        if (it.id == id) return it;
      }
    }
    return null;
  }

  KioskFixtureItem itemById(String id) {
    final item = tryItem(id);
    if (item == null) {
      throw ArgumentError.value(id, 'id', 'unknown menu item');
    }
    return item;
  }

  KioskFixtureGroup? group(String id) => groups[id];

  /// unit price of [item] with [selected] option ids per group — integer
  /// minor units only (D-007): base + Σ selected deltas. Ids that no longer
  /// resolve contribute nothing (staleness is surfaced separately; a price is
  /// never invented).
  int unitPriceMinor(
    KioskFixtureItem item,
    Map<String, List<String>> selected,
  ) {
    var minor = item.basePriceMinor;
    for (final gid in item.groupIds) {
      final group = groups[gid];
      if (group == null) continue;
      for (final oid in selected[gid] ?? const <String>[]) {
        for (final o in group.options) {
          if (o.id == oid) minor += o.priceDeltaMinor;
        }
      }
    }
    return minor;
  }

  /// Required groups of [item] not yet satisfied (the V2 CTA blocks and names
  /// them). Mirrors the server's effective rules: single ⇒ exactly one pick;
  /// a required multiple ⇒ at least max(minSelect, 1) picks.
  List<String> unmetRequiredGroups(
    KioskFixtureItem item,
    Map<String, List<String>> selected,
  ) => [
    for (final gid in item.groupIds)
      if (_unmet(groups[gid], selected[gid] ?? const [])) gid,
  ];

  bool _unmet(KioskFixtureGroup? group, List<String> picked) {
    if (group == null) return false;
    final min = group.type == KioskGroupType.single
        ? (group.isRequired ? 1 : 0)
        : (group.isRequired
              ? (group.minSelect > 0 ? group.minSelect : 1)
              : group.minSelect);
    return picked.length < min;
  }

  /// The default selection the item sheet opens with. Fixtures preselect the
  /// included weight option (the artifact's rule); LIVE menus preselect
  /// NOTHING — the server defines no defaults and the client never invents
  /// one (§HARDENING: a hidden option the server did not provide is a forgery).
  Map<String, List<String>> defaultSelectionFor(KioskFixtureItem item) {
    final selected = <String, List<String>>{
      for (final g in item.groupIds) g: [],
    };
    if (!live && item.groupIds.contains('weight')) {
      selected['weight'] = [kioskIncludedWeightOptionId];
    }
    return selected;
  }
}

/// The menu snapshot the whole kiosk reads. Defaults to the Phase-1 fixtures
/// (demo mode + every existing test); the real-mode composition root
/// overrides this with the live-published snapshot.
final kioskMenuDataProvider = Provider<KioskMenuData>(
  (ref) => KioskMenuData.fixtures(),
);

/// How the menu surface should present itself. Demo mode is always [ready];
/// the real root maps the live load state (loading spinner before the first
/// read, reconnect on transport trouble, unavailable on an unusable payload,
/// empty when the tenant has nothing to sell).
enum KioskMenuStatus { ready, loading, reconnect, unavailable, empty }

final kioskMenuStatusProvider = Provider<KioskMenuStatus>(
  (ref) => KioskMenuStatus.ready,
);

/// Whether "Place order" is allowed to proceed at all. True in demo mode
/// (the Phase-1 fixture confirmation). The real-mode root ALSO sets it true
/// since KIOSK-001-REAL-SUBMIT-092 (real submits through the hardened RPC);
/// it remains a testable safety seam — overriding it FALSE anywhere shows
/// the honest "ordering unavailable" notice instead of any submit path.
final kioskOrderingEnabledProvider = Provider<bool>((ref) => true);
