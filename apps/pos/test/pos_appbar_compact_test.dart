import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/ready_notifications_store.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/ready_notifications_controller.dart';
import 'package:restoflow_pos/src/widgets/device_settings_menu.dart';
import 'package:restoflow_pos/src/widgets/language_selector.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_indicator.dart';
import 'package:restoflow_pos/src/widgets/ready_notification_bell.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// PSC-001A correction (Fix 7) — the COMPACT POS app bar: at narrow phone
/// widths the five operational actions (ready bell FIRST, orders, outbox,
/// language, device menu) all fit with the brand tile visible, ZERO layout
/// overflow, the text title yielded, and the outbox collapsed to its
/// tooltip'd icon — across Arabic/Hebrew RTL and English LTR.

class _StubReadyController extends PosReadyNotificationsController {
  @override
  PosReadyNotificationsState build() => PosReadyNotificationsState(
    initialized: true,
    records: [
      PosReadyNotificationRecord(
        workUnitType: 'initial_order',
        workUnitId: '0a000000-0000-4000-8000-000000000001',
        orderId: '0b000000-0000-4000-8000-000000000001',
        orderCode: '#A1B2C3',
        orderType: 'dine_in',
        tableLabel: 'T1',
        readyAt: DateTime.utc(2026, 7, 23, 10).toIso8601String(),
        workUnitStatus: 'ready',
        parentOrderStatus: 'preparing',
        revision: 3,
        discoveredAt: DateTime.utc(2026, 7, 23, 10, 1).toIso8601String(),
        read: false,
        alerted: true,
      ),
    ],
  );
}

class _StubOutbox extends OutboxController {
  @override
  List<OutboxEntry> build() => [
    OutboxEntry(
      id: 'e1',
      deviceId: 'dev1',
      localOperationId: 'op1',
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: 'o1',
      payloadJson: '{}',
      summary: const OrderSummary(
        orderNumber: 'DEMO-0001',
        orderType: OrderType.dineIn,
        tableLabel: 'T1',
        itemCount: 1,
        subtotalMinor: 2500,
        currencyCode: 'ILS',
      ),
      syncState: OutboxSyncState.pending,
      clientCreatedAt: DateTime.utc(2026, 7, 23, 10),
    ),
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required Locale locale,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        posReadyNotificationsControllerProvider.overrideWith(
          _StubReadyController.new,
        ),
        outboxControllerProvider.overrideWith(_StubOutbox.new),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
    for (final width in const [320.0, 360.0, 390.0]) {
      testWidgets(
        'compact app bar at ${width.toInt()}px (${locale.languageCode}): '
        'no overflow, bell FIRST, five actions + brand tile + badges + '
        'tooltip\'d compact outbox',
        (tester) async {
          await _pump(tester, width: width, locale: locale);
          // ZERO layout exceptions (a RenderFlex overflow throws in tests).
          expect(tester.takeException(), isNull);

          // All five operational actions are present and reachable.
          expect(find.byType(ReadyNotificationBell), findsOneWidget);
          expect(find.byType(RecentOrdersButton), findsOneWidget);
          expect(find.byType(OutboxStatusIndicator), findsOneWidget);
          expect(find.byType(LanguageSelector), findsOneWidget);
          expect(find.byType(DeviceSettingsMenu), findsOneWidget);

          // The brand tile stays; the TEXT title yielded in compact mode.
          expect(find.byKey(const Key('pos-brand-tile')), findsOneWidget);

          // The unread ready badge is visible on the bell.
          expect(find.byType(Badge), findsWidgets);
          expect(find.text('1'), findsWidgets);

          // The bell is the FIRST action: strictly closest to the title side
          // (start edge in LTR, end edge flipped automatically in RTL — so
          // compare against the recent-orders button along the text
          // direction).
          final direction = Directionality.of(
            tester.element(find.byType(ReadyNotificationBell)),
          );
          final bellX = tester.getCenter(find.byType(ReadyNotificationBell)).dx;
          final ordersX = tester.getCenter(find.byType(RecentOrdersButton)).dx;
          if (direction == TextDirection.ltr) {
            expect(bellX, lessThan(ordersX));
          } else {
            expect(bellX, greaterThan(ordersX));
          }

          // COMPACT outbox: icon-only with the full label via tooltip (and
          // the unchanged Semantics wrapper).
          expect(
            find.byKey(const Key('outbox-status-compact')),
            findsOneWidget,
          );
          final tooltip = tester.widget<Tooltip>(
            find.byKey(const Key('outbox-status-compact')),
          );
          expect(tooltip.message, isNotEmpty);
        },
      );
    }
  }

  testWidgets('a WIDE bar keeps the text title and the full outbox label', (
    tester,
  ) async {
    await _pump(tester, width: 1280, locale: const Locale('en'));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('outbox-status-compact')), findsNothing);
    // The pending label text is visible in normal mode.
    expect(find.textContaining('pending'), findsOneWidget);
  });
}
