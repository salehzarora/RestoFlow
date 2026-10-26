import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/online_order_inbox.dart';
import 'package:restoflow_pos/src/media/background_order_alert_bridge.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/design/pos_visual_tokens.dart';
import 'package:restoflow_pos/src/media/pos_media_image.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/state/background_order_alerts.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/ready_notifications_controller.dart';
import 'package:restoflow_pos/src/widgets/device_settings_menu.dart';
import 'package:restoflow_pos/src/widgets/language_selector.dart';
import 'package:restoflow_pos/src/widgets/online_order_inbox_sheet.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_indicator.dart';
import 'package:restoflow_pos/src/widgets/ready_notification_bell.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:restoflow_pos/src/spool/online_order_print_hooks.dart';

import 'online_order_inbox_fixtures.dart';

class _Controller extends OnlineOrderInboxController {
  _Controller(this.fixed);
  final OnlineOrderInboxState fixed;
  final decisions = <OnlineOrderDecision>[];
  String? reason;
  int? preparationMinutes;
  bool get hasIntent => state.intent != null;
  int refreshes = 0;
  void replace(OnlineOrderInboxState next) => state = next;
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
    int? preparationMinutes,
  }) async {
    if (state.intent != null) return;
    decisions.add(decision);
    this.reason = reason;
    this.preparationMinutes = preparationMinutes;
    state = state.copyWith(
      deciding: true,
      intent: OnlineInboxIntent(
        requestId: requestId,
        decisionId: decisionId,
        decision: decision,
        reason: reason,
        preparationMinutes: preparationMinutes,
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

class _BackgroundAlerts extends BackgroundOrderAlerts {
  _BackgroundAlerts({this.authorizationExpired = false});
  final bool authorizationExpired;
  final choices = <bool>[];
  @override
  BackgroundOrderAlertState build() => BackgroundOrderAlertState(
    available: true,
    failed: authorizationExpired,
    authorizationExpired: authorizationExpired,
  );
  @override
  Future<void> setEnabled(bool value) async {
    choices.add(value);
    state = BackgroundOrderAlertState(available: true, enabled: value);
  }
}

class _AlertBridge implements BackgroundOrderAlertBridge {
  int permissionRequests = 0;
  int bindings = 0;
  int disables = 0;
  bool refuse = false;
  Completer<void>? permission;
  Completer<bool>? binding;
  @override
  Future<Map<String, dynamic>> prepare({bool requestPermission = false}) async {
    if (requestPermission) {
      permissionRequests++;
      await permission?.future;
    }
    return {
      'available': true,
      'enabled': requestPermission && !refuse,
      'installation_id': '11111111-1111-4111-8111-111111111111',
      'fcm_token': 'synthetic-token',
      'status_secret': '0' * 64,
      'generation': 1,
    };
  }

  @override
  Future<bool> bind(Map<String, dynamic> _) async {
    bindings++;
    return binding?.future ?? true;
  }

  @override
  Future<void> pending(Map<String, dynamic> _) async {}
  @override
  Future<void> suspend({bool retainOptIn = false}) async {}
  @override
  Future<void> disable() async {
    disables++;
  }

  @override
  Future<bool> consumeInboxTap() async => false;
  @override
  void setHints({
    required void Function() tokenChanged,
    required void Function() pendingHint,
  }) {}
  @override
  Future<void> dispose() async {}
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
  PosMenuData? menu,
  bool menuUnavailable = false,
  WebOrderPrintOutcome? recovery,
  Future<WebOrderPrintOutcome?> Function()? readRecovery,
  BackgroundOrderAlerts? backgroundAlerts,
  _AlertBridge? backgroundBridge,
  BackgroundOrderAlertRegistration? register,
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
        if (backgroundBridge != null) ...[
          backgroundOrderAlertsBuildEnabledProvider.overrideWithValue(true),
          backgroundOrderAlertBridgeProvider.overrideWithValue(
            backgroundBridge,
          ),
          backgroundOrderAlertEndpointProvider.overrideWithValue(
            'https://synthetic.invalid/functions/v1/pos-order-alert-status',
          ),
          backgroundOrderAlertRegisterProvider.overrideWithValue(
            register ??
                (params, {authorize, isCurrent}) async => {
                  'ok': true,
                  'registration_id': '22222222-2222-4222-8222-222222222222',
                  'generation': '33333333-3333-4333-8333-333333333333',
                  'authority_expires_at': DateTime.now()
                      .toUtc()
                      .add(const Duration(minutes: 15))
                      .toIso8601String(),
                },
          ),
        ],
        if (backgroundAlerts != null)
          backgroundOrderAlertsProvider.overrideWith(() => backgroundAlerts),
        onlineInboxPrintRecoveryProvider.overrideWith(
          (ref) async => readRecovery == null ? recovery : readRecovery(),
        ),
        onlineOrderInboxControllerProvider.overrideWith(() => controller),
        onlineOrderInboxIdentityProvider.overrideWithValue('test-authority'),
        posMenuProvider.overrideWith((_) async {
          if (menuUnavailable) throw const PosMenuUnavailable();
          return menu ??
              const PosMenuData(categories: [], items: [], currencyCode: 'ILS');
        }),
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
  Future<void> openAcceptance(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('online-inbox-accept')));
    await tester.tap(find.byKey(const Key('online-inbox-accept')));
    await tester.pumpAndSettle();
  }

  for (final minutes in [10, 15, 20, 30, 45, 60]) {
    testWidgets('explicit quick choice $minutes accepts once, never defaults', (
      tester,
    ) async {
      final controller = await pumpInbox(tester);
      await openAcceptance(tester);
      final confirm = find.byKey(const Key('online-inbox-accept-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(controller.decisions, isEmpty);
      for (final chip in tester.widgetList<ChoiceChip>(
        find.byType(ChoiceChip),
      )) {
        expect(chip.selected, false);
      }
      final quick = find.byKey(Key('online-inbox-preparation-$minutes'));
      await tester.ensureVisible(quick);
      expect(tester.getSize(quick).height, greaterThanOrEqualTo(44));
      await tester.tap(quick);
      await tester.pump();
      await tester.ensureVisible(confirm);
      final callback = tester.widget<FilledButton>(confirm).onPressed!;
      await tester.tap(confirm);
      callback(); // a retained callback must still be single-flight
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.decisions, [OnlineOrderDecision.accept]);
      expect(controller.preparationMinutes, minutes);
    });
  }

  for (final cancel in ['cancel', 'dismiss', 'escape']) {
    testWidgets(
      'accept chooser $cancel creates no intent even after selection',
      (tester) async {
        final controller = await pumpInbox(tester);
        await openAcceptance(tester);
        await tester.tap(find.byKey(const Key('online-inbox-preparation-20')));
        await tester.pump();
        if (cancel == 'cancel') {
          await tester.ensureVisible(
            find.byKey(const Key('online-inbox-accept-cancel')),
          );
          await tester.tap(find.byKey(const Key('online-inbox-accept-cancel')));
        } else if (cancel == 'escape') {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('online-inbox-accept-dialog')),
          findsNothing,
        );
        expect(controller.decisions, isEmpty);
        expect(controller.hasIntent, false);
      },
    );
  }

  testWidgets('custom preparation time requires a strict integer in 1..240', (
    tester,
  ) async {
    final controller = await pumpInbox(tester);
    await openAcceptance(tester);
    final field = find.byKey(const Key('online-inbox-preparation-custom'));
    final confirm = find.byKey(const Key('online-inbox-accept-confirm'));
    for (final invalid in ['0', '241', '-1', '1.5', ' 1', 'abc']) {
      await tester.enterText(field, invalid);
      await tester.pump();
      expect(
        tester.widget<FilledButton>(confirm).onPressed,
        isNull,
        reason: invalid,
      );
    }
    await tester.enterText(field, '1');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    expect(controller.decisions, isEmpty);
  });

  testWidgets('another device resolves while chooser is open: no acceptance', (
    tester,
  ) async {
    final controller = await pumpInbox(tester);
    await openAcceptance(tester);
    await tester.tap(find.byKey(const Key('online-inbox-preparation-15')));
    controller.replace(
      OnlineOrderInboxState(
        requests: [inboxRequest(status: 'accepted')],
        serverTime: inboxNow,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('online-inbox-accept-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(controller.decisions, isEmpty);
  });

  for (final locale in ['ar', 'he', 'en']) {
    for (final size in [const Size(390, 844), const Size(1024, 768)]) {
      testWidgets(
        '$locale ${size.width}px preparation chooser stays keyboard-safe at 2x',
        (tester) async {
          final controller = await pumpInbox(
            tester,
            locale: locale,
            size: size,
            scale: 2,
          );
          await openAcceptance(tester);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pump();
          final field = find.byKey(
            const Key('online-inbox-preparation-custom'),
          );
          await tester.ensureVisible(field);
          await tester.enterText(field, '240');
          await tester.pump();
          final dialog = find.byKey(const Key('online-inbox-accept-dialog'));
          expect(
            Directionality.of(tester.element(dialog)),
            locale == 'en' ? TextDirection.ltr : TextDirection.rtl,
          );
          final confirm = find.byKey(const Key('online-inbox-accept-confirm'));
          await tester.ensureVisible(confirm);
          expect(confirm.hitTestable(), findsOneWidget);
          expect(tester.getSize(confirm).height, greaterThanOrEqualTo(44));
          await tester.tap(confirm);
          await tester.pump(const Duration(milliseconds: 300));
          expect(controller.preparationMinutes, 240);
          expect(controller.decisions, [OnlineOrderDecision.accept]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final language in ['ar', 'he', 'en']) {
    for (final size in [const Size(800, 1100), const Size(1100, 700)]) {
      testWidgets(
        '$language rejection keyboard, rotation and large text $size',
        (tester) async {
          final controller = await pumpInbox(
            tester,
            locale: language,
            size: size,
            scale: 1.8,
          );
          await tester.tap(
            find.byKey(const ValueKey('online-request-$requestId')),
          );
          await tester.pump();
          await tester.ensureVisible(
            find.byKey(const Key('online-inbox-reject')),
          );
          await tester.tap(find.byKey(const Key('online-inbox-reject')));
          await tester.pumpAndSettle();
          final field = find.byKey(const Key('online-inbox-rejection-reason'));
          final confirm = find.byKey(const Key('online-inbox-reject-confirm'));
          final cancel = find.byKey(const Key('online-inbox-reject-cancel'));
          final l10n = AppLocalizations.of(tester.element(field));
          expect(
            tester.widget<TextField>(field).decoration!.labelText,
            l10n.posOnlineInboxReason,
          );
          expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
          await tester.enterText(field, '  نفد المخزون / אזל / sold out  ');
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(confirm);
          expect(
            tester.getRect(confirm).bottom,
            lessThanOrEqualTo(size.height - 300),
          );
          await tester.ensureVisible(cancel);
          expect(
            tester.getRect(cancel).bottom,
            lessThanOrEqualTo(size.height - 300),
          );
          tester.view.physicalSize = Size(size.height, size.width);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(field).controller!.text,
            '  نفد المخزون / אזל / sold out  ',
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(confirm);
          await tester.tap(confirm);
          await tester.pump(const Duration(milliseconds: 300));
          expect(controller.decisions, [OnlineOrderDecision.reject]);
          expect(controller.reason, 'نفد المخزون / אזל / sold out');
        },
      );
    }
  }
  for (final action in ['cancel', 'dismiss', 'resolved', 'auth']) {
    testWidgets('rejection $action cannot submit a stale decision', (
      tester,
    ) async {
      final controller = await pumpInbox(tester);
      await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('online-inbox-reject')));
      await tester.tap(find.byKey(const Key('online-inbox-reject')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('online-inbox-rejection-reason'));
      await tester.enterText(field, 'Sold out');
      await tester.pump();
      if (action == 'cancel') {
        await tester.tap(find.byKey(const Key('online-inbox-reject-cancel')));
      } else if (action == 'dismiss') {
        await tester.tapAt(const Offset(2, 2));
      } else {
        controller.replace(
          OnlineOrderInboxState(
            requests: action == 'resolved' ? [] : [inboxRequest()],
            failure: action == 'auth'
                ? OnlineInboxFailure.invalidSession
                : null,
            serverTime: inboxNow,
          ),
        );
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('online-inbox-reject-confirm')),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.pumpAndSettle();
      expect(controller.decisions, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('reason enforces trimmed Unicode length and controls', (
    tester,
  ) async {
    final controller = await pumpInbox(tester);
    await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('online-inbox-reject')));
    await tester.tap(find.byKey(const Key('online-inbox-reject')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('online-inbox-rejection-reason'));
    final confirm = find.byKey(const Key('online-inbox-reject-confirm'));
    for (final invalid in ['   ', '🙂' * 241, 'reason\nprivate']) {
      await tester.enterText(field, invalid);
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    }
    await tester.enterText(field, '🙂' * 240);
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    expect(controller.decisions, isEmpty);
  });
  for (final language in ['ar', 'he', 'en']) {
    for (final cancel in ['cancel', 'dismiss']) {
      testWidgets(
        '$language real callback $cancel never prompts or registers',
        (tester) async {
          final bridge = _AlertBridge();
          var registrations = 0;
          final inbox = await pumpInbox(
            tester,
            locale: language,
            backgroundBridge: bridge,
            register: (params, {authorize, isCurrent}) async {
              registrations++;
              return {};
            },
          );
          final toggle = find.byKey(const Key('background-order-alert-switch'));
          final callback = tester.widget<SwitchListTile>(toggle).onChanged!;
          callback(true);
          callback(
            true,
          ); // one confirmation, even using the original callback twice
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          if (cancel == 'cancel') {
            final label = MaterialLocalizations.of(
              tester.element(find.byType(AlertDialog)),
            ).cancelButtonLabel;
            await tester.tap(find.text(label));
          } else {
            await tester.binding.handlePopRoute();
          }
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(bridge.permissionRequests, 0);
          expect(registrations, 0);
          expect(inbox.decisions, isEmpty);
        },
      );
    }
    testWidgets(
      '$language real confirmation shows pending then ON only after bind',
      (tester) async {
        final bridge = _AlertBridge()
          ..permission = Completer<void>()
          ..binding = Completer<bool>();
        final inbox = await pumpInbox(
          tester,
          locale: language,
          backgroundBridge: bridge,
        );
        final toggle = find.byKey(const Key('background-order-alert-switch'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AlertDialog)),
        );
        await tester.tap(find.text(l10n.posBackgroundOrderAlertsEnable));
        await tester.pump();
        await tester.pump(
          const Duration(milliseconds: 250),
        ); // dialog animation only
        expect(bridge.permissionRequests, 1);
        expect(
          find.byKey(const Key('background-order-alert-pending')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('background-order-alert-cancel')),
          findsOneWidget,
        );
        expect(tester.widget<SwitchListTile>(toggle).value, false);
        bridge.permission!.complete();
        await tester.pump();
        expect(bridge.bindings, 1);
        expect(tester.widget<SwitchListTile>(toggle).value, false);
        bridge.binding!.complete(true);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, true);
        expect(
          find.byKey(const Key('background-order-alert-pending')),
          findsNothing,
        );
        expect(inbox.decisions, isEmpty);
      },
    );
    testWidgets('$language real refusal is visible with usable OFF control', (
      tester,
    ) async {
      final bridge = _AlertBridge()..refuse = true;
      await pumpInbox(tester, locale: language, backgroundBridge: bridge);
      final toggle = find.byKey(const Key('background-order-alert-switch'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)),
      );
      await tester.tap(find.text(l10n.posBackgroundOrderAlertsEnable));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.posBackgroundOrderAlertsUnavailable),
        findsOneWidget,
      );
      expect(tester.widget<SwitchListTile>(toggle).value, false);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
      expect(bridge.bindings, 0);
    });
  }
  testWidgets(
    'Cancel pending permission rejects late result and restores usable OFF',
    (tester) async {
      final bridge = _AlertBridge()..permission = Completer<void>();
      var registrations = 0;
      await pumpInbox(
        tester,
        backgroundBridge: bridge,
        register: (params, {authorize, isCurrent}) async {
          registrations++;
          return {};
        },
      );
      final toggle = find.byKey(const Key('background-order-alert-switch'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)),
      );
      await tester.tap(find.text(l10n.posBackgroundOrderAlertsEnable));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(const Key('background-order-alert-cancel')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, false);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
      bridge.permission!.complete();
      await tester.pumpAndSettle();
      expect(registrations, 0);
      expect(bridge.bindings, 0);
      expect(bridge.disables, greaterThan(0));
    },
  );
  testWidgets('OFF invalidates already displayed confirmation', (tester) async {
    final bridge = _AlertBridge();
    await pumpInbox(tester, backgroundBridge: bridge);
    final toggle = find.byKey(const Key('background-order-alert-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnlineOrderInboxSheet)),
    );
    await container
        .read(backgroundOrderAlertsProvider.notifier)
        .setEnabled(false);
    final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)));
    await tester.tap(find.text(l10n.posBackgroundOrderAlertsEnable));
    await tester.pumpAndSettle();
    expect(bridge.permissionRequests, 0);
    expect(bridge.bindings, 0);
    expect(tester.widget<SwitchListTile>(toggle).value, false);
  });
  testWidgets(
    'real notification lifecycle resumes permission from inactive once',
    (tester) async {
      final bridge = _AlertBridge()..permission = Completer<void>();
      await pumpInbox(tester, button: true, backgroundBridge: bridge);
      await tester.tap(find.byKey(const Key('online-inbox-button')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('background-order-alert-switch'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)),
      );
      await tester.tap(find.text(l10n.posBackgroundOrderAlertsEnable));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      bridge.permission!.complete();
      await tester.pump();
      expect(bridge.bindings, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(bridge.permissionRequests, 1);
      expect(bridge.bindings, 1);
      expect(tester.widget<SwitchListTile>(toggle).value, true);
    },
  );
  for (final language in ['ar', 'he', 'en']) {
    testWidgets(
      '$language expired alert authority asks for sign-in without authorizing orders',
      (tester) async {
        final alerts = _BackgroundAlerts(authorizationExpired: true);
        final inbox = await pumpInbox(
          tester,
          locale: language,
          backgroundAlerts: alerts,
        );
        final toggle = find.byKey(const Key('background-order-alert-switch'));
        final l10n = AppLocalizations.of(tester.element(toggle));
        expect(find.text(l10n.posBackgroundOrderAlertsSignIn), findsOneWidget);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(alerts.choices, isEmpty);
        expect(inbox.decisions, isEmpty);
      },
    );
    for (final width in [390.0, 1024.0]) {
      testWidgets(
        '$language $width background opt-in explanation precedes enabling',
        (tester) async {
          final alerts = _BackgroundAlerts();
          final inbox = await pumpInbox(
            tester,
            locale: language,
            size: Size(width, 844),
            scale: 2,
            backgroundAlerts: alerts,
          );
          final toggle = find.descendant(
            of: find.byKey(const Key('background-order-alert-switch')),
            matching: find.byType(Switch),
          );
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(alerts.choices, isEmpty);
          final context = tester.element(find.byType(AlertDialog));
          final l10n = AppLocalizations.of(context);
          expect(
            find.text(l10n.posBackgroundOrderAlertsExplanation),
            findsOneWidget,
          );
          await tester.tap(find.text(l10n.posBackgroundOrderAlertsEnable));
          await tester.pumpAndSettle();
          expect(alerts.choices, [true]);
          expect(inbox.decisions, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'new equal print failures surface once each and dismissal changes no outcome',
    (tester) async {
      final controller = await pumpInbox(
        tester,
        button: true,
        state: const OnlineOrderInboxState(),
        recovery: WebOrderPrintOutcome.failed,
      );
      final button = find.byKey(const Key('online-inbox-button'));
      final container = ProviderScope.containerOf(tester.element(button));
      await tester.pumpAndSettle();
      final first = const OnlineOrderInboxState(
        printOutcome: WebOrderPrintOutcome.failed,
        printResultSequence: 1,
      );
      controller.replace(first);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      final messenger = ScaffoldMessenger.of(tester.element(button));
      messenger.removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(controller.decisions, isEmpty);
      expect(
        container.read(onlineOrderInboxControllerProvider).printOutcome,
        WebOrderPrintOutcome.failed,
      );

      // Refreshing either projection is not a new attempt, including after a
      // staff member dismisses the transient message.
      controller.replace(first.copyWith(loading: true));
      container.invalidate(onlineInboxPrintRecoveryProvider);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      controller.replace(first.copyWith(printResultSequence: 2));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      messenger.removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(controller.decisions, isEmpty);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('online-inbox-earlier-print-issue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('online-inbox-earlier-print-status')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'unchanged durable print recovery stays quiet across refresh and reopen',
    (tester) async {
      var reads = 0;
      final controller = await pumpInbox(
        tester,
        button: true,
        state: const OnlineOrderInboxState(),
        readRecovery: () async {
          reads++;
          return WebOrderPrintOutcome.failed;
        },
      );
      final button = find.byKey(const Key('online-inbox-button'));
      final container = ProviderScope.containerOf(tester.element(button));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      for (var refresh = 0; refresh < 3; refresh++) {
        container.invalidate(onlineInboxPrintRecoveryProvider);
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      }
      for (var opening = 0; opening < 2; opening++) {
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('online-inbox-print-status')),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(reads, greaterThan(1));
      expect(controller.decisions, isEmpty);
    },
  );
  testWidgets(
    'restart recovery projects durable hold without a retry control',
    (tester) async {
      await pumpInbox(
        tester,
        state: const OnlineOrderInboxState(),
        recovery: WebOrderPrintOutcome.reconciliationRequired,
      );
      final status = find.byKey(const Key('online-inbox-print-status'));
      final l10n = AppLocalizations.of(tester.element(status));
      expect(tester.widget<Text>(status).data, l10n.kioskKitchenLastPossibly);
      expect(find.text(l10n.kioskKitchenRetry), findsNothing);
    },
  );
  for (final locale in ['ar', 'he', 'en']) {
    testWidgets(
      '$locale a new success does not conceal an earlier unresolved ticket',
      (tester) async {
        await pumpInbox(
          tester,
          locale: locale,
          state: const OnlineOrderInboxState(
            printOutcome: WebOrderPrintOutcome.sent,
            printResultSequence: 1,
          ),
          recovery: WebOrderPrintOutcome.reconciliationRequired,
        );
        await tester.pumpAndSettle();
        final status = find.byKey(const Key('online-inbox-print-status'));
        final earlier = find.byKey(
          const Key('online-inbox-earlier-print-status'),
        );
        final heading = find.byKey(
          const Key('online-inbox-earlier-print-issue'),
        );
        final l10n = AppLocalizations.of(tester.element(status));
        expect(
          tester.widget<Text>(status).data,
          l10n.posKitchenTicketPrintedSnack,
        );
        expect(
          tester.widget<Text>(earlier).data,
          l10n.kioskKitchenLastPossibly,
        );
        expect(
          tester.widget<Text>(heading).data,
          l10n.posOnlineInboxEarlierPrintIssue,
        );
        expect(find.text(l10n.kioskKitchenRetry), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '$locale targeted print status is honest and has no automatic retry action',
      (tester) async {
        await pumpInbox(
          tester,
          locale: locale,
          state: const OnlineOrderInboxState(
            printOutcome: WebOrderPrintOutcome.reconciliationRequired,
          ),
        );
        final status = find.byKey(const Key('online-inbox-print-status'));
        final l10n = AppLocalizations.of(tester.element(status));
        expect(tester.widget<Text>(status).data, l10n.kioskKitchenLastPossibly);
        expect(find.text(l10n.kioskKitchenRetry), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '$locale known no-write failure does not claim possible printing',
      (tester) async {
        await pumpInbox(
          tester,
          locale: locale,
          state: const OnlineOrderInboxState(
            printOutcome: WebOrderPrintOutcome.failed,
          ),
        );
        final status = find.byKey(const Key('online-inbox-print-status'));
        final l10n = AppLocalizations.of(tester.element(status));
        expect(tester.widget<Text>(status).data, l10n.kioskKitchenLastFailed);
        expect(find.text(l10n.kioskKitchenLastPossibly), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  const menuId = '60000000-0000-4000-8000-000000000001';
  const correctUrl = 'https://example.invalid/exact-id.png';
  const wrongUrl = 'https://example.invalid/same-name-wrong-id.png';
  const menu = PosMenuData(
    categories: [],
    currencyCode: 'ILS',
    items: [
      DemoMenuItem(
        id: '60000000-0000-4000-8000-000000000002',
        name: 'وجبة / ארוחה',
        priceMinor: 5,
        categoryId: 'category',
        categoryName: 'Food',
        imageUrl: wrongUrl,
      ),
      DemoMenuItem(
        id: menuId,
        name: 'Current renamed menu item',
        priceMinor: 999999,
        categoryId: 'category',
        categoryName: 'Food',
        imageUrl: correctUrl,
      ),
    ],
  );
  testWidgets(
    'list shows pending arrival summary quantity total and exact-ID photos',
    (tester) async {
      final requested = <String>[];
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4AWMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      );
      debugPosMediaImageProviderOverride = (url) {
        requested.add(url);
        return MemoryImage(png);
      };
      addTearDown(() => debugPosMediaImageProviderOverride = NetworkImage.new);
      final json = requestJson();
      json['items'][0]['notes'] = 'Item snapshot note';
      await pumpInbox(
        tester,
        menu: menu,
        state: OnlineOrderInboxState(
          requests: [OnlineOrderRequest.fromJson(json)],
          serverTime: inboxNow,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Order pending'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('online-inbox-arrival-$requestId')),
        findsOneWidget,
      );
      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('2 × وجبة / ארוחה'), findsOneWidget);
      expect(find.text('₪29.40'), findsOneWidget);
      expect(requested, isNotEmpty);
      expect(requested.every((url) => url == correctUrl), isTrue);
      await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
      await tester.pumpAndSettle();
      expect(find.text('Current renamed menu item'), findsNothing);
      expect(find.text('2 × وجبة / ארוחה'), findsOneWidget);
      expect(find.text('2 × جبنة / גבינה · ₪2.00'), findsOneWidget);
      expect(find.text('Item snapshot note'), findsOneWidget);
      expect(find.text('بدون بصل / בלי בצל'), findsOneWidget);
      expect(find.text('Item note'), findsOneWidget);
      expect(find.text('Customer notes'), findsOneWidget);
      expect(find.text('₪28.00'), findsWidgets);
      expect(
        find.byKey(const ValueKey('online-inbox-image-$menuId')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('missing ID and unavailable menu never use name-based photos', (
    tester,
  ) async {
    final requested = <String>[];
    debugPosMediaImageProviderOverride = (url) {
      requested.add(url);
      return MemoryImage(Uint8List(0));
    };
    addTearDown(() => debugPosMediaImageProviderOverride = NetworkImage.new);
    for (final unavailable in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await pumpInbox(
        tester,
        menu: PosMenuData(
          categories: [],
          items: [menu.items.first],
          currencyCode: 'ILS',
        ),
        menuUnavailable: unavailable,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('online-inbox-image-fallback-$menuId')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
      await tester.pumpAndSettle();
      expect(find.text('2 × وجبة / ארוחה'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('online-inbox-image-fallback-$menuId')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    expect(requested, isEmpty);
  });
  testWidgets(
    'broken authenticated photo falls back without blocking actions',
    (tester) async {
      debugPosMediaImageProviderOverride = (_) => MemoryImage(Uint8List(0));
      addTearDown(() => debugPosMediaImageProviderOverride = NetworkImage.new);
      await pumpInbox(tester, menu: menu);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('online-inbox-image-fallback-$menuId')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('online-inbox-image-fallback-$menuId')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('online-inbox-accept')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
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
            final detail = find.byKey(const Key('online-inbox-details'));
            expect(find.text('+972501234567'), findsOneWidget);
            expect(
              find.descendant(
                of: detail,
                matching: find.text('2 × وجبة / ארוחה'),
              ),
              findsOneWidget,
            );
            expect(find.text('2 × جبنة / גבינה · ₪2.00'), findsOneWidget);
            expect(find.text('بدون بصل / בלי בצל'), findsOneWidget);
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
              greaterThanOrEqualTo(56),
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
          .widget<FilledButton>(
            find.byKey(const Key('online-inbox-reject-confirm')),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('online-inbox-rejection-reason')),
      'Sold out',
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('online-inbox-reject-confirm')),
    );
    await tester.tap(find.byKey(const Key('online-inbox-reject-confirm')));
    await tester.pump(const Duration(milliseconds: 300));
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
  testWidgets('expired and unauthorized requests retain disabled actions', (
    tester,
  ) async {
    final expired = requestJson();
    expired['expires_at'] = inboxNow
        .subtract(const Duration(minutes: 1))
        .toIso8601String();
    for (final state in [
      OnlineOrderInboxState(requests: [OnlineOrderRequest.fromJson(expired)]),
      OnlineOrderInboxState(
        requests: [inboxRequest()],
        failure: OnlineInboxFailure.invalidSession,
      ),
      OnlineOrderInboxState(
        requests: [inboxRequest()],
        failure: OnlineInboxFailure.permissionDenied,
      ),
    ]) {
      await tester.pumpWidget(const SizedBox());
      final controller = await pumpInbox(tester, state: state);
      await tester.tap(find.byKey(const ValueKey('online-request-$requestId')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('online-inbox-accept')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('online-inbox-reject')),
            )
            .onPressed,
        isNull,
      );
      expect(controller.decisions, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });
}
