/// DASHBOARD-OWNER-ANALYTICS-F0.3 — named shell destinations.
///
/// The shell selects tabs by bare `int`, and that integer ordering is written
/// down TWICE — once in the `switch (_index)` that builds the surface and once
/// in the navigation-destination list — with nothing keeping them in step. A
/// caller that wanted the Orders tab had to know that Orders is 7, and a future
/// analytics card wiring `_select(7)` would silently land on Users the day a
/// destination is inserted above it.
///
/// This enum is the single name for each surface. It deliberately does NOT
/// change the visible order or the index values: it records the existing
/// mapping so call sites can stop repeating magic numbers, not renumber
/// anything.
///
/// Settings is a special case worth stating plainly. The shell's switch has no
/// `9 =>` arm; Settings is reached through the `_ =>` DEFAULT arm. That means
/// any out-of-range index silently renders Settings. [DashboardDestination]
/// keeps `settings` at index 9 so the destination list still resolves it, while
/// the shell keeps its default arm unchanged — the fragility is preserved
/// deliberately rather than "fixed" in a navigation-only task, because turning
/// the default into an explicit arm would change what an unexpected index does.
library;

/// A named Dashboard surface.
///
/// Order matches the shell's existing tab order exactly, and [tabIndex] is the
/// value the shell already uses.
///
/// The mapping is written out EXPLICITLY rather than leaning on the enum's
/// built-in declaration-order `index`. Those two happen to coincide today, and
/// that coincidence is exactly the trap: inserting a destination would silently
/// re-point every existing name at the wrong surface. An explicit field makes
/// such a change a visible edit.
enum DashboardDestination {
  overview(0),
  menu(1),
  devices(2),
  // DASHBOARD-PRINTING-UI-HIDE-037: printer management left the normal
  // Dashboard. The destination, its index and the screen behind it all stay —
  // only the visible nav tile is gone — so nothing here is renumbered.
  printers(3, hiddenFromNavigation: true),
  // ADMIN-126B: the four destinations below have NO approved support read.
  // `list_staff`, `list_members`, the order-history reads and the tenant audit
  // reads were deliberately withheld from support sessions because they carry
  // staff and customer identity. A tab whose every read is refused is worse
  // than an absent one, so support mode drops them from the navigation.
  staff(4, readableInSupportMode: false),
  tables(5),
  users(6, readableInSupportMode: false),
  orders(7, readableInSupportMode: false),
  activity(8, readableInSupportMode: false),
  settings(9);

  const DashboardDestination(
    this.tabIndex, {
    this.hiddenFromNavigation = false,
    this.readableInSupportMode = true,
  });

  /// The shell tab index this destination renders as. Existing value — this
  /// enum records the mapping, it does not redefine it.
  final int tabIndex;

  /// 037: omitted from the visible rail/bar. Still routable internally by
  /// [tabIndex]; the shell's destination switch is unchanged.
  final bool hiddenFromNavigation;

  /// ADMIN-126B: whether a PLATFORM SUPPORT session can read this surface at
  /// all — i.e. whether its reads are among the fifteen the server approved.
  ///
  /// This mirrors a server decision; it does not make one. Flipping a false to
  /// true here would not grant a support session anything, it would only put
  /// back a tab that errors.
  final bool readableInSupportMode;

  /// Every destination the navigation actually SHOWS, in order.
  static List<DashboardDestination> get visible => visibleFor();

  /// The visible set for a given mode. ADMIN-126B: a support session also drops
  /// every destination it has no approved read for.
  static List<DashboardDestination> visibleFor({bool supportMode = false}) => [
    for (final d in DashboardDestination.values)
      if (!d.hiddenFromNavigation && (!supportMode || d.readableInSupportMode))
        d,
  ];

  /// This destination's position in the visible index space FOR A MODE, or null
  /// when it is not shown there.
  int? visibleIndexIn({bool supportMode = false}) {
    final at = visibleFor(supportMode: supportMode).indexOf(this);
    return at < 0 ? null : at;
  }

  /// This destination's position in the VISIBLE index space, or null when it
  /// is hidden.
  ///
  /// The rail walks the canonical space and skips hidden rows, but Material's
  /// `NavigationBar` has no notion of a hidden destination — its indices are
  /// necessarily compacted. This is the single mapping both the shell and its
  /// tests use, so the two can never drift.
  int? get visibleIndex {
    final at = visible.indexOf(this);
    return at < 0 ? null : at;
  }

  /// Resolves a shell index back to a destination.
  ///
  /// Any index without an explicit arm resolves to [settings], mirroring the
  /// shell's `_ =>` default arm exactly. Keeping the two in agreement is the
  /// point: a test can now assert that behaviour instead of it living only in a
  /// switch nobody reads.
  static DashboardDestination fromIndex(int index) {
    for (final d in DashboardDestination.values) {
      if (d.tabIndex == index) return d;
    }
    return DashboardDestination.settings;
  }
}
