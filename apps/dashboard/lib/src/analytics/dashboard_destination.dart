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
  printers(3),
  staff(4),
  tables(5),
  users(6),
  orders(7),
  activity(8),
  settings(9);

  const DashboardDestination(this.tabIndex);

  /// The shell tab index this destination renders as. Existing value — this
  /// enum records the mapping, it does not redefine it.
  final int tabIndex;

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
