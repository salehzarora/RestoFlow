import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/online_order_inbox.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/widgets/online_order_inbox_sheet.dart';

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
