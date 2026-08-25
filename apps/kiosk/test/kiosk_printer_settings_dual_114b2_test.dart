import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_kiosk/src/print/kiosk_printer_purpose.dart';
import 'package:restoflow_kiosk/src/screens/printer_settings.dart';
import 'package:restoflow_kiosk/src/state/kiosk_receipt_branding.dart';
import 'package:restoflow_kiosk/src/state/kiosk_staff_access.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-PRINT-114B.2 — the DUAL-ROLE kiosk printer settings.
///
/// CUSTOMER RECEIPT keeps its shipped block/keys byte-for-byte; the KITCHEN
/// TICKET block appears only when the server-reported branch capability
/// includes kitchen_ticket (printer_only). On a KDS-governed branch the
/// kitchen block is INERT: a localized governance note replaces the config
/// controls. Kitchen saves write ONLY kitchen-segment keys.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceId = 'dev-ui2';

  DevicePrinterAssignments assignments({required bool kitchen}) =>
      DevicePrinterAssignments(
        fetchedAt: DateTime.utc(2026, 8, 25),
        deviceType: 'kiosk',
        printers: [
          AssignedPrinter(
            id: 'p1',
            displayName: 'P1',
            role: 'receipt',
            connectionType: 'network',
            paperWidth: '80mm',
            isEnabled: true,
            supportedPurposes: [
              'customer_receipt',
              if (kitchen) 'kitchen_ticket',
            ],
          ),
        ],
      );

  Future<ProviderContainer> pumpSection(
    WidgetTester tester, {
    required bool kitchenSupported,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        kioskPrinterAssignmentsProvider.overrideWith(
          (ref) async => Success(assignments(kitchen: kitchenSupported)),
        ),
        // The real root's shared-store binding: kiosk namespace + device id.
        nativePrinterNamespaceProvider.overrideWithValue('kiosk'),
        nativePrinterDeviceIdProvider.overrideWith(
          (ref) => ref.watch(kioskDeviceContextProvider)?.deviceId,
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(kioskDeviceContextProvider.notifier)
        .state = const DeviceContext(
      organizationId: 'org',
      branchId: 'branch',
      restaurantId: 'rest',
      deviceId: deviceId,
      deviceType: 'kiosk',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: KioskPrinterSection()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('printer_only: BOTH role blocks render — customer keys '
      'unchanged, kitchen keys present', (tester) async {
    await pumpSection(tester, kitchenSupported: true);
    // Customer block: the shipped keys, byte-for-byte.
    expect(find.byKey(const Key('kiosk-printer-autoprint')), findsOneWidget);
    expect(
      find.byKey(const Key('kiosk-printer-transport-network')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kiosk-printer-save')), findsOneWidget);
    expect(find.byKey(const Key('kiosk-printer-test')), findsOneWidget);
    // Kitchen block.
    expect(find.byKey(const Key('kiosk-kitchen-autoprint')), findsOneWidget);
    expect(
      find.byKey(const Key('kiosk-kitchen-transport-network')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('kiosk-kitchen-transport-bluetooth')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kiosk-kitchen-save')), findsOneWidget);
    expect(find.byKey(const Key('kiosk-kitchen-test')), findsOneWidget);
    expect(find.byKey(const Key('kiosk-kitchen-governed-note')), findsNothing);
  });

  testWidgets('KDS-governed: the kitchen block is INERT — a governance note, '
      'no kitchen config controls', (tester) async {
    await pumpSection(tester, kitchenSupported: false);
    expect(
      find.byKey(const Key('kiosk-kitchen-governed-note')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kiosk-kitchen-save')), findsNothing);
    expect(find.byKey(const Key('kiosk-kitchen-autoprint')), findsNothing);
    // Customer block untouched by governance.
    expect(find.byKey(const Key('kiosk-printer-save')), findsOneWidget);
  });

  testWidgets('a kitchen network save writes ONLY the kitchen-segment keys', (
    tester,
  ) async {
    await pumpSection(tester, kitchenSupported: true);
    await tester.enterText(
      find.byKey(const Key('kiosk-kitchen-host')),
      '10.0.0.77',
    );
    await tester.enterText(find.byKey(const Key('kiosk-kitchen-port')), '9100');
    await tester.ensureVisible(find.byKey(const Key('kiosk-kitchen-save')));
    await tester.tap(find.byKey(const Key('kiosk-kitchen-save')));
    await tester.pump(const Duration(milliseconds: 300));
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(kioskKitchenNetworkKey(deviceId)),
      contains('"10.0.0.77"'),
    );
    expect(prefs.getString(kioskKitchenSelectedKey(deviceId)), 'network');
    expect(
      prefs.getString('restoflow.printer.network.kiosk.$deviceId'),
      isNull,
      reason: 'a kitchen save must never touch the customer slot',
    );
  });

  testWidgets('the copy-customer action clones the saved customer printer '
      'into the kitchen slot', (tester) async {
    SharedPreferences.setMockInitialValues({
      'restoflow.printer.network.kiosk.$deviceId':
          '{"host":"10.0.0.9","port":9100,"name":"Kiosk"}',
      'restoflow.printer.selected.kiosk.$deviceId': 'network',
    });
    await pumpSection(tester, kitchenSupported: true);
    await tester.ensureVisible(
      find.byKey(const Key('kiosk-kitchen-copy-customer')),
    );
    await tester.tap(find.byKey(const Key('kiosk-kitchen-copy-customer')));
    await tester.pump(const Duration(milliseconds: 300));
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(kioskKitchenNetworkKey(deviceId)),
      contains('"10.0.0.9"'),
    );
    expect(prefs.getString(kioskKitchenSelectedKey(deviceId)), 'network');
  });
}
