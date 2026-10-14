import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/online_order_inbox.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/design/pos_visual_tokens.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/ready_notifications_controller.dart';
import 'package:restoflow_pos/src/widgets/device_settings_menu.dart';
import 'package:restoflow_pos/src/widgets/language_selector.dart';
import 'package:restoflow_pos/src/widgets/online_order_inbox_sheet.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_indicator.dart';
import 'package:restoflow_pos/src/widgets/ready_notification_bell.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

import 'online_order_inbox_fixtures.dart';

class _Controller extends OnlineOrderInboxController {
  _Controller(this.fixed);
  final OnlineOrderInboxState fixed;
  final decisions = <OnlineOrderDecision>[];
  String? reason;
  int refreshes = 0;
  @override
  OnlineOrderInboxState build() => fixed;
  @override
  DateTime now() => inboxNow;
  @override
  Future<void> refresh({bool loadMore = false}) async {
    refreshes++;
  }

  @override
  void onResume() {}
  @override
  void onPaused() {}
  @override
  Future<void> decide(
    String requestId,
    OnlineOrderDecision decision, {
    String? reason,
  }) async {
    if (state.intent != null) return;
    decisions.add(decision);
    this.reason = reason;
    state = state.copyWith(
      deciding: true,
      intent: OnlineInboxIntent(
        requestId: requestId,
        decisionId: decisionId,
        decision: decision,
        reason: reason,
      ),
    );
  }
}

class _QuietReady extends PosReadyNotificationsController {
  @override
  PosReadyNotificationsState build() => const PosReadyNotificationsState();
}

class _QuietOutbox extends OutboxController {
  @override
  List<OutboxEntry> build() => const [];
}

Future<void> pumpNavbar(
  WidgetTester tester, {
  required String locale,
  required double width,
  required double scale,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onlineOrderInboxControllerProvider.overrideWith(
          () => _Controller(
            OnlineOrderInboxState(
              requests: [inboxRequest()],
              serverTime: inboxNow,
            ),
          ),
        ),
        onlineOrderInboxIdentityProvider.overrideWithValue('test-authority'),
        posReadyNotificationsControllerProvider.overrideWith(_QuietReady.new),
        outboxControllerProvider.overrideWith(_QuietOutbox.new),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        // Use the real POS appbar; keep this regression focused on its geometry
        // instead of unrelated cart/menu text scaling.
        home: Builder(
          builder: (context) {
            final screen = const PosMenuScreen().build(context) as Scaffold;
            return Scaffold(appBar: screen.appBar);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<_Controller> pumpInbox(
  WidgetTester tester, {
  String locale = 'en',
  Size size = const Size(390, 844),
  double scale = 1,
  OnlineOrderInboxState? state,
  bool button = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = _Controller(
    state ??
        OnlineOrderInboxState(requests: [inboxRequest()], serverTime: inboxNow),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onlineOrderInboxControllerProvider.overrideWith(() => controller),
        onlineOrderInboxIdentityProvider.overrideWithValue('test-authority'),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: button
              ? const OnlineOrderInboxButton()
              : const OnlineOrderInboxSheet(),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  for (final locale in ['en', 'ar', 'he']) {
    testWidgets('$locale displays each item note beside its own line', (
      tester,
    ) async {
      final json = requestJson();
      json['items'][0]['notes'] = 'بدون بصل\nבלי בצל 🍽';
      json['items'] = [
        json['items'][0],
        {...json['items'][0], 'notes': 'Extra onion'},
      ];
      json['totals']['subtotal_minor'] = 5600;
      json['totals']['tax_total_minor'] = 280;
      json['totals']['grand_total_minor'] = 5880;
      await pumpInbox(
        tester,
        locale: locale,
        state: OnlineOrderInboxState(
          requests: [OnlineOrderRequest.fromJson(json)],
          serverTime: inboxNow,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
      await tester.pump();
      expect(find.text('بدون بصل\nבלי בצל 🍽'), findsOneWidget);
      expect(find.text('Extra onion'), findsOneWidget);
      expect(find.text('بدون بصل / בלי בצל'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final locale in ['en', 'ar', 'he']) {
    for (final width in [
      320.0,
      360.0,
      390.0,
      430.0,
      480.0,
      520.0,
      900.0,
      1280.0,
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$locale ${width}px ${scale}x inbox shares approved navbar height',
          (tester) async {
            await pumpNavbar(
              tester,
              locale: locale,
              width: width,
              scale: scale,
            );
            expect(tester.takeException(), isNull);
            expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
            expect(
              tester.getSize(find.byType(AppBar)).height,
              posTopBarMetricsFor(width).height,
            );
            expect(
              tester.getSize(find.byKey(const Key('pos-brand-tile'))).width,
              width == 520 ? greaterThanOrEqualTo(40) : greaterThan(0),
            );
            final inbox = find.byKey(const Key('online-inbox-button'));
            expect(inbox.hitTestable(), findsOneWidget);
            expect(tester.getSize(inbox).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(inbox).height, greaterThanOrEqualTo(44));
            final inboxWidget = tester.widget<IconButton>(inbox);
            expect(inboxWidget.tooltip, isNotEmpty);
            final badge = tester.widget<Badge>(
              find.descendant(of: inbox, matching: find.byType(Badge)),
            );
            expect(badge.isLabelVisible, isTrue);
            final existingActions = [
              find.byType(ReadyNotificationBell),
              find.byType(RecentOrdersButton),
              find.byType(OutboxStatusIndicator),
              find.byType(LanguageSelector),
              find.byType(DeviceSettingsMenu),
            ];
            for (final action in existingActions) {
              expect(action.hitTestable(), findsOneWidget);
            }
            final coordinates = [
              tester.getCenter(existingActions.first).dx,
              tester.getCenter(inbox).dx,
              ...existingActions.skip(1).map((f) => tester.getCenter(f).dx),
            ];
            for (var i = 1; i < coordinates.length; i++) {
              expect(
                coordinates[i],
                locale == 'en'
                    ? greaterThan(coordinates[i - 1])
                    : lessThan(coordinates[i - 1]),
              );
            }
            await tester.tap(inbox);
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('online-inbox-sheet')), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final locale in ['en', 'ar', 'he']) {
    for (final size in [
      const Size(390, 844),
      const Size(1024, 768),
      const Size(1440, 900),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$locale ${size.width}px ${scale}x details and actions fit',
          (tester) async {
            await pumpInbox(tester, locale: locale, size: size, scale: scale);
            await tester.tap(
              find.byKey(const ValueKey('online-request-$requestId')),
            );
            await tester.pump();
            expect(find.text('+972501234567'), findsOneWidget);
            expect(find.text('2 × وجبة / ארוחה'), findsOneWidget);
            expect(find.text('2 × جبنة / גבינה · ₪2.00'), findsOneWidget);
            expect(find.text('بدون بصل / בלי בצל'), findsOneWidget);
            final detail = find.byKey(const Key('online-inbox-details'));
            expect(
              Directionality.of(tester.element(detail)),
              locale == 'en' ? TextDirection.ltr : TextDirection.rtl,
            );
            await tester.ensureVisible(
              find.byKey(const Key('online-inbox-accept')),
            );
            await tester.pump();
            expect(
              tester
                  .getSize(find.byKey(const Key('online-inbox-accept')))
                  .height,
              greaterThanOrEqualTo(40),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets('badge opens one sheet on double tap', (tester) async {
    await pumpInbox(tester, button: true);
    expect(find.byType(Badge), findsOneWidget);
    await tester.tap(find.byKey(const Key('online-inbox-button')));
    await tester.tap(
      find.byKey(const Key('online-inbox-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-inbox-sheet')), findsOneWidget);
  });
  testWidgets('accept is single flight and rejection requires a reason', (
    tester,
  ) async {
    final controller = await pumpInbox(tester);
    await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('online-inbox-reject')));
    await tester.tap(find.byKey(const Key('online-inbox-reject')));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('online-inbox-reject')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('online-inbox-rejection-reason')),
      'Sold out',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('online-inbox-reject')));
    await tester.tap(find.byKey(const Key('online-inbox-reject')));
    await tester.pump();
    expect(controller.decisions, [OnlineOrderDecision.reject]);
    expect(controller.reason, 'Sold out');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('online-inbox-accept')))
          .onPressed,
      isNull,
    );
  });
  testWidgets('loading empty expired unavailable and error are honest', (
    tester,
  ) async {
    for (final state in [
      const OnlineOrderInboxState(loading: true),
      const OnlineOrderInboxState(),
      const OnlineOrderInboxState(failure: OnlineInboxFailure.unavailable),
      const OnlineOrderInboxState(failure: OnlineInboxFailure.malformed),
      const OnlineOrderInboxState(failure: OnlineInboxFailure.requestExpired),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await pumpInbox(tester, state: state);
      expect(find.byKey(const Key('online-inbox-empty')), findsOneWidget);
      if (state.loading)
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('uncertain decisions disable both actions and expose recovery', (
    tester,
  ) async {
    await pumpInbox(
      tester,
      state: OnlineOrderInboxState(
        requests: [inboxRequest()],
        uncertain: true,
        intent: const OnlineInboxIntent(
          requestId: requestId,
          decisionId: decisionId,
          decision: OnlineOrderDecision.accept,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
    await tester.pump();
    expect(find.byKey(const Key('online-inbox-recover')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('online-inbox-accept')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('online-inbox-reject')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
