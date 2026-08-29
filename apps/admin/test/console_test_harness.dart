/// Shared harness for the ADMIN-125C.2 platform-console widget tests.
///
/// Every console test pumps the SHELL (not a page in isolation), because the
/// shell is what decides which page is visible, what the refresh button
/// refreshes, and whether the operator can get from a list to a detail and back.
/// Testing pages standalone would prove they render and nothing about whether
/// the console works.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/console_models.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';
import 'package:restoflow_admin/src/state/platform_admin_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Widths the console must survive. 390 is a phone (drawer), 768 a small tablet
/// (drawer), 1024 a tablet (icon rail), 1440 a desktop (extended rail).
const Size kPhone = Size(390, 1400);
const Size kTablet = Size(768, 1400);
const Size kLaptop = Size(1024, 1400);
const Size kDesktop = Size(1440, 1600);

/// Sizes the test view and restores it afterwards.
void useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the console shell with [repo] behind the data seam.
///
/// The override list is a FIXED LENGTH on purpose. Riverpod forbids adding or
/// removing overrides on an existing ProviderScope ("overrides cannot be
/// removed/added, they can only be updated"), so a conditional entry crashes any
/// test that pumps twice with different arguments. Omitting [repo] therefore
/// substitutes the demo repository explicitly — which is what the provider would
/// have resolved to in demo mode anyway.
Widget consoleApp({
  PlatformAdminRepository? repo,
  Locale locale = const Locale('en'),
  bool isDemoMode = true,
  String? operatorEmail,
  VoidCallback? onSignOut,
}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: isDemoMode),
    ),
    platformAdminRepositoryProvider.overrideWithValue(
      repo ?? const DemoPlatformAdminRepository(),
    ),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: PlatformAdminScreen(
      operatorEmail: operatorEmail,
      onSignOut: onSignOut,
    ),
  ),
);

/// Reads the console's live subscriber query.
///
/// Needed because the page providers are FAMILIES keyed by the query: revisiting
/// a page that was already fetched is served from cache and performs no new
/// read, so "what did the repository last see" is the wrong question — the right
/// one is "what is the console asking for now".
SubscriberQuery readSubscriberQuery(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
      listen: false,
    ).read(subscriberQueryProvider);

/// Loads the English strings for exact-text assertions.
Future<AppLocalizations> englishStrings() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Opens a top-level console destination by its rail/drawer label.
///
/// The finder is SCOPED to the navigation subtree on purpose. Several
/// destination names are also metric-card labels on the Overview page
/// ("Subscribers", "Restaurants"), so an unscoped `find.text` matches the card
/// and a tap lands on a metric instead of navigating — which reads as a passing
/// navigation test that never navigated.
Future<void> goToSection(WidgetTester tester, String label) async {
  final rail = find.byKey(const Key('console-rail'));
  if (rail.evaluate().isNotEmpty) {
    await tester.tap(
      find.descendant(of: rail, matching: find.text(label)).first,
    );
    await tester.pumpAndSettle();
    return;
  }
  // Below the rail breakpoint the destinations live in a drawer.
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(
          of: find.byKey(const Key('console-drawer')),
          matching: find.text(label),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// A repository that resolves after a delay, so a test can observe the loading
/// state before the data arrives.
class DelayedConsoleRepository implements PlatformAdminRepository {
  DelayedConsoleRepository({
    this.delay = const Duration(milliseconds: 50),
    PlatformDataset? dataset,
  }) : _inner = DemoPlatformAdminRepository(dataset: dataset);

  final Duration delay;
  final DemoPlatformAdminRepository _inner;

  Future<T> _after<T>(Future<T> Function() body) =>
      Future<void>.delayed(delay).then((_) => body());

  @override
  Future<ConsoleOverview> loadConsoleOverview() =>
      _after(_inner.loadConsoleOverview);

  @override
  Future<SubscriberPage> loadSubscribers(SubscriberQuery query) =>
      _after(() => _inner.loadSubscribers(query));

  @override
  Future<SubscriberDetail> loadSubscriberDetail(String organizationId) =>
      _after(() => _inner.loadSubscriberDetail(organizationId));

  @override
  Future<RestaurantPage> loadRestaurants(RestaurantQuery query) =>
      _after(() => _inner.loadRestaurants(query));

  @override
  Future<AuditPage> loadAuditPage(AuditQuery query) =>
      _after(() => _inner.loadAuditPage(query));
}

/// A repository that RECORDS every call, so a test can prove which reads a page
/// actually performed (and, just as importantly, which it did not).
class RecordingConsoleRepository implements PlatformAdminRepository {
  RecordingConsoleRepository({PlatformDataset? dataset})
    : _inner = DemoPlatformAdminRepository(dataset: dataset);

  final DemoPlatformAdminRepository _inner;

  final List<String> calls = <String>[];
  final List<SubscriberQuery> subscriberQueries = <SubscriberQuery>[];
  final List<RestaurantQuery> restaurantQueries = <RestaurantQuery>[];
  final List<AuditQuery> auditQueries = <AuditQuery>[];
  final List<String> detailIds = <String>[];

  @override
  Future<ConsoleOverview> loadConsoleOverview() {
    calls.add('overview');
    return _inner.loadConsoleOverview();
  }

  @override
  Future<SubscriberPage> loadSubscribers(SubscriberQuery query) {
    calls.add('subscribers');
    subscriberQueries.add(query);
    return _inner.loadSubscribers(query);
  }

  @override
  Future<SubscriberDetail> loadSubscriberDetail(String organizationId) {
    calls.add('detail');
    detailIds.add(organizationId);
    return _inner.loadSubscriberDetail(organizationId);
  }

  @override
  Future<RestaurantPage> loadRestaurants(RestaurantQuery query) {
    calls.add('restaurants');
    restaurantQueries.add(query);
    return _inner.loadRestaurants(query);
  }

  @override
  Future<AuditPage> loadAuditPage(AuditQuery query) {
    calls.add('audit');
    auditQueries.add(query);
    return _inner.loadAuditPage(query);
  }
}
