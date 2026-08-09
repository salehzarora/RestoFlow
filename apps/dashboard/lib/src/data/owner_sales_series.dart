/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-A) — the typed `owner_sales_series`
/// response.
///
/// SERVER-A added a per-DAY sales series to sit beside the existing per-hour one.
/// The Overview already had a shape for a single window (`DashboardReport`) and a
/// shape for one day's hours (`HourlyNetSales`); it had nothing for "a window,
/// broken into its days". These models are that shape, and nothing more — they
/// hold no presentation, no formatting and no window arithmetic.
///
/// Two properties are load-bearing:
///
///  * **Money and counts are integers** (DECISION D-007). Nothing here is ever a
///    double, so no rounding can enter through the client.
///  * **A day is a branch-local CALENDAR LABEL, not an instant.** See
///    [BusinessDay] — this is the single most dangerous thing in the payload.
///
/// Parsing follows the convention `RealOwnerReportsRepository` already
/// established: be lenient with individual ROWS (drop what cannot be trusted,
/// never fabricate a value to fill a gap) and strict with the ENVELOPE (a
/// rejected body is an error the caller must see). Unknown payment methods and
/// order types are kept VERBATIM rather than dropped — F0.5's
/// `paymentMethodLabel` already degrades an unknown token to its raw string, and
/// silently dropping a tender would make a money breakdown stop summing to its
/// own total.
library;

/// A branch-local calendar day, as the server labelled it.
///
/// This type exists because the obvious implementation is wrong. `owner_sales_
/// series` computes its buckets in BRANCH-local time — `COALESCE(branch.timezone,
/// restaurant.timezone)` — and emits the resulting calendar label. The moment a
/// client does `DateTime.parse(day)` it has converted a label into an INSTANT,
/// and every later `.toLocal()`, `.day` or comparison is evaluated against the
/// DEVICE's timezone instead. An owner in Israel opening the dashboard from a
/// laptop still set to UTC-5 would see each bar shifted a day, and the totals
/// would no longer line up with the KPI above them.
///
/// So this holds the exact token and validated integer components, and never
/// constructs a [DateTime] at all. Ordering is lexicographic, which for
/// zero-padded `YYYY-MM-DD` is exactly chronological.
class BusinessDay implements Comparable<BusinessDay> {
  const BusinessDay._(this.label, this.year, this.month, this.dayOfMonth);

  /// Parses a `YYYY-MM-DD` token, or null if it is not one.
  ///
  /// Deliberately strict about SHAPE (fixed width, digits only, separators in
  /// place) and only sanity-checking about VALUE: the server owns calendar
  /// truth, so this rejects month 13 or day 32 but does not re-derive how many
  /// days February had. Digits are checked explicitly because `int.tryParse`
  /// accepts a leading sign, which would let `2026-+1-08` through.
  static BusinessDay? tryParse(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.length != 10 || s[4] != '-' || s[7] != '-') return null;
    if (!_digits(s, 0, 4) || !_digits(s, 5, 7) || !_digits(s, 8, 10)) {
      return null;
    }
    final year = int.parse(s.substring(0, 4));
    final month = int.parse(s.substring(5, 7));
    final day = int.parse(s.substring(8, 10));
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return BusinessDay._(s, year, month, day);
  }

  static bool _digits(String s, int start, int end) {
    for (var i = start; i < end; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  /// The server's exact token, e.g. `2026-08-08`. This is the value to show and
  /// to send back — never a re-rendered one.
  final String label;

  final int year;
  final int month;
  final int dayOfMonth;

  /// The compact axis label: the zero-padded day of month (`08`).
  ///
  /// Mirrors how the sales-by-hour chart labels its axis with just the hour
  /// (`h.hourLabel.split(':').first`) — a 30-point axis has no room for a full
  /// date, and the tooltip carries the unambiguous [label].
  String get dayOfMonthLabel => dayOfMonth.toString().padLeft(2, '0');

  @override
  int compareTo(BusinessDay other) => label.compareTo(other.label);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BusinessDay && other.label == label;

  @override
  int get hashCode => label.hashCode;

  @override
  String toString() => label;
}

/// One `{method, count, total_minor}` row of a day's tender breakdown.
///
/// [method] is the WIRE token (`cash` / `card` / `bit` / `external`), kept
/// verbatim so it stays the identity everywhere; display is resolved by F0.5's
/// `paymentMethodLabel`.
class OwnerSalesSeriesPaymentMethod {
  const OwnerSalesSeriesPaymentMethod({
    required this.method,
    required this.count,
    required this.totalMinor,
  });

  final String method;
  final int count;
  final int totalMinor;
}

/// One `{order_type, order_count, net_minor}` row of a day's order-type split.
///
/// [orderType] is the WIRE token (`dine_in` / `takeaway`), kept verbatim.
class OwnerSalesSeriesOrderType {
  const OwnerSalesSeriesOrderType({
    required this.orderType,
    required this.orderCount,
    required this.netMinor,
  });

  final String orderType;
  final int orderCount;
  final int netMinor;
}

/// One day of the series.
///
/// BILLED sales ([grossMinor] / [discountMinor] / [netMinor], [orderCount]) and
/// COLLECTED payments ([collectedMinor] / [cashMinor], [byMethod]) are separate
/// facts and are never equal by construction — the server computes them from
/// different tables. Voids are counted in their own day and are NOT folded into
/// the billed figures.
class OwnerSalesSeriesBucket {
  const OwnerSalesSeriesBucket({
    required this.day,
    required this.orderCount,
    required this.grossMinor,
    required this.discountMinor,
    required this.netMinor,
    required this.voidCount,
    required this.voidTotalMinor,
    required this.collectedMinor,
    required this.cashMinor,
    this.byMethod = const [],
    this.byOrderType = const [],
  });

  /// Parses one bucket, or null when it cannot be trusted on a time axis.
  ///
  /// A missing or malformed `day` drops the whole bucket: a value with no
  /// truthful position is worse than an absent one, because it would still be
  /// drawn somewhere. Every other field degrades to 0 exactly as
  /// `RealOwnerReportsRepository` already does.
  static OwnerSalesSeriesBucket? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final day = BusinessDay.tryParse(raw['day']);
    if (day == null) return null;
    return OwnerSalesSeriesBucket(
      day: day,
      orderCount: _int(raw['order_count']),
      grossMinor: _int(raw['gross_minor']),
      discountMinor: _int(raw['discount_minor']),
      netMinor: _int(raw['net_minor']),
      voidCount: _int(raw['void_count']),
      voidTotalMinor: _int(raw['void_total_minor']),
      collectedMinor: _int(raw['collected_minor']),
      cashMinor: _int(raw['cash_minor']),
      byMethod: _methods(raw['by_method']),
      byOrderType: _orderTypes(raw['by_order_type']),
    );
  }

  final BusinessDay day;
  final int orderCount;
  final int grossMinor;
  final int discountMinor;
  final int netMinor;
  final int voidCount;
  final int voidTotalMinor;
  final int collectedMinor;
  final int cashMinor;
  final List<OwnerSalesSeriesPaymentMethod> byMethod;
  final List<OwnerSalesSeriesOrderType> byOrderType;

  static List<OwnerSalesSeriesPaymentMethod> _methods(Object? raw) {
    if (raw is! List) return const [];
    final rows = <OwnerSalesSeriesPaymentMethod>[];
    for (final row in raw) {
      if (row is! Map) continue;
      rows.add(
        OwnerSalesSeriesPaymentMethod(
          method: (row['method'] ?? '').toString(),
          count: _int(row['count']),
          totalMinor: _int(row['total_minor']),
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  static List<OwnerSalesSeriesOrderType> _orderTypes(Object? raw) {
    if (raw is! List) return const [];
    final rows = <OwnerSalesSeriesOrderType>[];
    for (final row in raw) {
      if (row is! Map) continue;
      rows.add(
        OwnerSalesSeriesOrderType(
          orderType: (row['order_type'] ?? '').toString(),
          orderCount: _int(row['order_count']),
          netMinor: _int(row['net_minor']),
        ),
      );
    }
    return List.unmodifiable(rows);
  }
}

/// A window of daily sales buckets, ascending by branch-local day.
class OwnerSalesSeries {
  const OwnerSalesSeries({
    required this.currencyCode,
    required this.rangeWire,
    required this.buckets,
    this.supported = true,
  });

  /// The honest "this window is not available from the server yet" result.
  ///
  /// Distinct from an EMPTY series, which means "the server answered and this
  /// window genuinely had no sales". Conflating them would tell an owner they
  /// had a dead fortnight when the RPC simply is not deployed. Mirrors
  /// `DashboardReport.rangeSupported`.
  const OwnerSalesSeries.unavailable(String range)
    : currencyCode = '',
      rangeWire = range,
      buckets = const [],
      supported = false;

  /// Maps a VALIDATED payload body (the caller has already checked `ok`).
  ///
  /// Buckets keep the server's ascending order; malformed ones are dropped
  /// rather than repositioned or zero-filled.
  static OwnerSalesSeries fromPayload(Map raw) {
    final rawBuckets = raw['buckets'];
    final buckets = <OwnerSalesSeriesBucket>[];
    if (rawBuckets is List) {
      for (final row in rawBuckets) {
        final bucket = OwnerSalesSeriesBucket.tryParse(row);
        if (bucket != null) buckets.add(bucket);
      }
    }
    return OwnerSalesSeries(
      currencyCode: (raw['currency_code'] ?? '').toString(),
      rangeWire: (raw['range'] ?? '').toString(),
      buckets: List.unmodifiable(buckets),
    );
  }

  final String currencyCode;

  /// The range token the server ECHOED, kept as the raw string.
  ///
  /// Not narrowed to `AnalyticsRange`: the server can legitimately answer
  /// `custom`, which has no enum value, and `AnalyticsRange.fromWire` would
  /// silently report it as `today`. The request's range is already known to
  /// every caller from its query key, so this is only ever an echo to verify.
  final String rangeWire;

  final List<OwnerSalesSeriesBucket> buckets;

  /// False only for [OwnerSalesSeries.unavailable].
  final bool supported;

  bool get isEmpty => buckets.isEmpty;

  /// Total billed net across the window, integer minor.
  ///
  /// Exists so a caller can assert the series agrees with the window total the
  /// KPI shows — two surfaces reading the same server must not disagree.
  int get netSalesMinor => buckets.fold<int>(0, (sum, b) => sum + b.netMinor);

  /// Total orders across the window.
  int get orderCount => buckets.fold<int>(0, (sum, b) => sum + b.orderCount);

  /// The busiest day by billed net (first on ties), or null when empty.
  OwnerSalesSeriesBucket? get peakByNet {
    if (buckets.isEmpty) return null;
    var peak = buckets.first;
    for (final b in buckets) {
      if (b.netMinor > peak.netMinor) peak = b;
    }
    return peak;
  }
}

int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;
