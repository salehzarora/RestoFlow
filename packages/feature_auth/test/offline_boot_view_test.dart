import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// PILOT-OFFLINE-BOOT-001: the friendly offline screen speaks the staff's
/// language, offers a working Retry, and never shows developer text.
Widget _host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  home: child,
);

void main() {
  testWidgets('renders title/message/retry (en) and Retry calls back', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(_host(OfflineBootView(onRetry: () => retries++)));
    await tester.pumpAndSettle();

    expect(find.text('No connection'), findsOneWidget);
    expect(find.text('Check Wi-Fi and try again'), findsOneWidget);
    expect(find.byKey(const Key('offline-boot-retry')), findsOneWidget);
    // No scary developer text for the cashier/chef.
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('config.toml'), findsNothing);

    await tester.tap(find.byKey(const Key('offline-boot-retry')));
    expect(retries, 1);
  });

  testWidgets('renders the Arabic title in RTL', (tester) async {
    await tester.pumpWidget(
      _host(OfflineBootView(onRetry: () {}), locale: const Locale('ar')),
    );
    await tester.pumpAndSettle();

    expect(find.text('لا يوجد اتصال'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('لا يوجد اتصال'))),
      TextDirection.rtl,
    );
  });

  testWidgets('hides the Retry button when onRetry is null', (tester) async {
    await tester.pumpWidget(_host(const OfflineBootView()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline-boot-retry')), findsNothing);
    expect(find.text('No connection'), findsOneWidget);
  });

  testWidgets('shows the auto-reconnect line when autoReconnecting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const OfflineBootView(onRetry: null, autoReconnecting: true)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('reconnect'), findsOneWidget);
  });
}
