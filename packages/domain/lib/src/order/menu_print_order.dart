/// MENU-ORDER-001 — THE one canonical menu-configured print order, shared by
/// every print surface (customer receipt, POS + KDS kitchen tickets, and every
/// reprint) so they all agree.
///
/// Items print in the owner's Dashboard-configured order:
///   1. category display order (ascending),
///   2. item display order within that category (ascending),
///   3. the order line's original position (line_position) — a deterministic
///      tie-breaker,
///   4. the original collection index — the final, stable tie-breaker.
/// An item's modifiers follow the same shape with
///   (group display order, option display order, line_position, index).
///
/// The display-order values are IMMUTABLE order-time snapshots (server-derived
/// at submit, D-008) — never re-derived from the live menu at print time.
/// Legacy/default snapshots are 0, which ties the leading keys, so old rows fall
/// back deterministically to line_position + original input order (never
/// unstable). Callers sort WHOLE semantic item/modifier objects — never
/// individual text lines — so each block moves with its quantity, preparation
/// details, modifiers, note, and identifiers.
library;

/// Returns a NEW list of [items] stably ordered by the ascending integer key
/// tuple [keyOf] yields, with the original input index as the final tie-breaker
/// (so equal tuples — and all-zero legacy tuples — keep their input order). The
/// input list is not mutated. Tuples may differ in length; shorter compares as a
/// prefix and then defers to the input index.
List<T> sortByMenuPrintOrder<T>(List<T> items, List<int> Function(T) keyOf) {
  final indexed = <(int, List<int>, T)>[
    for (var i = 0; i < items.length; i++) (i, keyOf(items[i]), items[i]),
  ];
  indexed.sort((a, b) {
    final ka = a.$2;
    final kb = b.$2;
    final n = ka.length < kb.length ? ka.length : kb.length;
    for (var j = 0; j < n; j++) {
      final c = ka[j].compareTo(kb[j]);
      if (c != 0) return c;
    }
    // Equal on the shared prefix: shorter tuple first, then stable input order.
    final byLen = ka.length.compareTo(kb.length);
    if (byLen != 0) return byLen;
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$3];
}

/// Tolerant int-or-0 pluck for a snapshot/ordinal value off a wire/JSON map
/// (mirrors the KDS mapper convention): a missing/blank/non-numeric value — an
/// order or RPC that predates the snapshot columns — yields 0 (the legacy
/// sentinel, so that row keeps its input order).
int menuPrintOrderInt(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? 0;
