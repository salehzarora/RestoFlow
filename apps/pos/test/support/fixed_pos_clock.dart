import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider;

/// POS-CI-TIME-TEST-STABILITY-011 — a fixed "now" for order/kitchen widget
/// tests whose fixtures are dated instants.
///
/// WHY THIS EXISTS. The POS recent-orders window keeps only orders at or after
/// `midnight(now) - 1 day`, and it reads the INJECTED [posSyncClockProvider]
/// precisely so tests can pin it (see `recent_orders_controller.dart`). A test
/// that leaves the provider at its `DateTime.now` default is not testing a
/// fixed scenario at all — it is testing "the fixture date versus today". Such
/// a test passes while its fixtures are fresh and then starts failing on a
/// calendar boundary, with symptoms that look nothing like a clock bug: every
/// list simply renders EMPTY, so unrelated visibility, completion and
/// rendering assertions fail together. That is exactly what happened when the
/// 2026-08-01 fixtures aged past the window and blocked the required CI check.
///
/// Pin the clock instead. The scenario then depends only on the fixtures.

/// The instant these suites run "at": the same calendar day as their
/// 2026-08-01 fixtures, after the latest of them (14:05Z).
final DateTime kPosTestNow = DateTime.utc(2026, 8, 1, 18);

/// Pins [posSyncClockProvider] so the recent-orders window is deterministic.
///
/// TIMEZONE-SAFE. The cutoff is `DateTime(now.year, now.month, now.day)` minus
/// one day — LOCAL midnight, so it moves with the runner's zone. With
/// [kPosTestNow] the cutoff lands on local midnight of 2026-07-31, which in
/// every zone from UTC-12 to UTC+14 is at least 21 hours before the earliest
/// 2026-08-01 fixture. The suites therefore behave identically on a UTC CI
/// runner and on a developer machine at any offset.
///
/// Pass an explicit [now] if a suite's fixtures are dated differently; keep it
/// on the fixtures' own day rather than reaching for the wall clock.
Override pinnedPosSyncClock([DateTime? now]) =>
    posSyncClockProvider.overrideWithValue(() => now ?? kPosTestNow);
