import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_kiosk/src/print/kiosk_printer_purpose.dart';
import 'package:restoflow_kiosk/src/state/kiosk_receipt_branding.dart';
import 'package:restoflow_kiosk/src/state/kiosk_staff_access.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-PRINT-114B.2 — the kiosk printer PURPOSE model.
///
/// * customer keys stay EXACTLY the shipped ones (zero migration);
/// * the kitchen role gets its own `kitchen_ticket.`-segment keys;
/// * kitchen auto-print defaults OFF;
/// * roles persist independently;
/// * ONE process-wide destination send gate;
/// * the submit claim decision is TRUE only when printer_only support +
///   auto-print + a usable destination all hold (fail-closed otherwise).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceId = 'dev-b2';

  ProviderContainer harness({List<Override> overrides = const []}) {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    container
        .read(kioskDeviceContextProvider.notifier)
        .state = const DeviceContext(
      organizationId: 'org',
      branchId: 'branch',
      restaurantId: 'rest',
      deviceId: deviceId,
      deviceType: 'kiosk',
      deviceSessionId: 'sess-b2',
    );
    return container;
  }

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
            configuredRole: kitchen ? 'both' : 'receipt',
            supportedPurposes: [
              'customer_receipt',
              if (kitchen) 'kitchen_ticket',
            ],
          ),
        ],
      );

  group('A. purpose enum + exact keys', () {
    test('key segments mirror the proven POS model', () {
      expect(KioskPrinterPurpose.customerReceipt.keySegment, '');
      expect(KioskPrinterPurpose.kitchenTicket.keySegment, 'kitchen_ticket.');
    });

    test('kitchen keys are exact; customer keys are the shipped ones', () {
      expect(
        kioskKitchenNetworkKey(deviceId),
        'restoflow.printer.network.kiosk.kitchen_ticket.$deviceId',
      );
      expect(
        kioskKitchenBluetoothKey(deviceId),
        'restoflow.printer.bluetooth.kiosk.kitchen_ticket.$deviceId',
      );
      expect(
        kioskKitchenSelectedKey(deviceId),
        'restoflow.printer.selected.kiosk.kitchen_ticket.$deviceId',
      );
      expect(
        kioskKitchenAutoPrintKey(deviceId),
        'restoflow.autoprint.kiosk.kitchen.$deviceId',
      );
    });
  });

  group('B. persistence — independent roles, zero receipt migration', () {
    test('an EXISTING receipt config loads untouched while the kitchen slot '
        'starts empty (zero-migration proof)', () async {
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.network.kiosk.$deviceId':
            '{"host":"10.0.0.9","port":9100,"name":"Kiosk"}',
        'restoflow.printer.selected.kiosk.$deviceId': 'network',
      });
      final c = harness();
      final kitchen = await c.read(kioskKitchenNetworkConfigProvider.future);
      expect(kitchen, isNull, reason: 'kitchen must NOT inherit the receipt');
      final enabled = await c.read(kioskKitchenAutoPrintEnabledProvider.future);
      expect(enabled, isFalse, reason: 'kitchen auto-print defaults OFF');
      // The receipt key was not rewritten by merely reading the kitchen slot.
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.printer.network.kiosk.$deviceId'),
        '{"host":"10.0.0.9","port":9100,"name":"Kiosk"}',
      );
    });

    test('kitchen network/bluetooth/transport/auto-print persist under the '
        'kitchen keys and reload', () async {
      SharedPreferences.setMockInitialValues({});
      final c = harness();
      await c
          .read(kioskKitchenNetworkConfigProvider.notifier)
          .save(const NetworkPrinterConfig(host: '10.0.0.7', port: 9100));
      await c
          .read(kioskKitchenBluetoothConfigProvider.notifier)
          .save(
            const BluetoothPrinterConfig(
              address: 'AA:BB:CC:DD:EE:01',
              name: 'BT-K',
            ),
          );
      await c
          .read(kioskKitchenSelectedTransportProvider.notifier)
          .select(PrinterTransportKind.bluetooth);
      await c
          .read(kioskKitchenAutoPrintEnabledProvider.notifier)
          .setEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kioskKitchenNetworkKey(deviceId)),
        contains('"10.0.0.7"'),
      );
      expect(
        prefs.getString(kioskKitchenBluetoothKey(deviceId)),
        contains('AA:BB:CC:DD:EE:01'),
      );
      expect(prefs.getString(kioskKitchenSelectedKey(deviceId)), 'bluetooth');
      expect(prefs.getBool(kioskKitchenAutoPrintKey(deviceId)), isTrue);
      // No customer key was created by kitchen writes.
      expect(
        prefs.getString('restoflow.printer.network.kiosk.$deviceId'),
        isNull,
      );

      // Reload in a FRESH container (cold start).
      final c2 = harness();
      final net = await c2.read(kioskKitchenNetworkConfigProvider.future);
      expect(net?.host, '10.0.0.7');
      final kind = await c2.read(kioskKitchenSelectedTransportProvider.future);
      expect(kind, PrinterTransportKind.bluetooth);
      expect(
        await c2.read(kioskKitchenAutoPrintEnabledProvider.future),
        isTrue,
      );
    });
  });

  group('C. one process-wide send gate', () {
    test('both reads return the SAME gate instance', () {
      SharedPreferences.setMockInitialValues({});
      final c = harness();
      final a = c.read(kioskPrinterDestinationSendGateProvider);
      final b = c.read(kioskPrinterDestinationSendGateProvider);
      expect(identical(a, b), isTrue);
    });
  });

  group('D. the submit claim decision (fail-closed)', () {
    Future<bool> decide(ProviderContainer c) =>
        c.read(kioskKitchenClaimDecisionProvider.future);

    Override supported(bool kitchen) => kioskPrinterAssignmentsProvider
        .overrideWith((ref) async => Success(assignments(kitchen: kitchen)));

    test(
      'TRUE only with printer_only support + auto-print + usable config',
      () async {
        SharedPreferences.setMockInitialValues({
          kioskKitchenNetworkKey(deviceId):
              '{"host":"10.0.0.7","port":9100,"name":"K"}',
          kioskKitchenSelectedKey(deviceId): 'network',
          kioskKitchenAutoPrintKey(deviceId): true,
        });
        final c = harness(overrides: [supported(true)]);
        expect(await decide(c), isTrue);
      },
    );

    test(
      'FALSE when auto-print is off even with a saved destination',
      () async {
        SharedPreferences.setMockInitialValues({
          kioskKitchenNetworkKey(deviceId):
              '{"host":"10.0.0.7","port":9100,"name":"K"}',
          kioskKitchenSelectedKey(deviceId): 'network',
        });
        final c = harness(overrides: [supported(true)]);
        expect(await decide(c), isFalse);
      },
    );

    test(
      'FALSE when the branch is KDS-governed (no kitchen purpose)',
      () async {
        SharedPreferences.setMockInitialValues({
          kioskKitchenNetworkKey(deviceId):
              '{"host":"10.0.0.7","port":9100,"name":"K"}',
          kioskKitchenSelectedKey(deviceId): 'network',
          kioskKitchenAutoPrintKey(deviceId): true,
        });
        final c = harness(overrides: [supported(false)]);
        expect(await decide(c), isFalse);
      },
    );

    test('FALSE when the selected transport has no usable config', () async {
      SharedPreferences.setMockInitialValues({
        kioskKitchenSelectedKey(deviceId): 'network',
        kioskKitchenAutoPrintKey(deviceId): true,
      });
      final c = harness(overrides: [supported(true)]);
      expect(await decide(c), isFalse);
    });

    test('FALSE when assignments are unavailable (fail closed)', () async {
      SharedPreferences.setMockInitialValues({
        kioskKitchenNetworkKey(deviceId):
            '{"host":"10.0.0.7","port":9100,"name":"K"}',
        kioskKitchenSelectedKey(deviceId): 'network',
        kioskKitchenAutoPrintKey(deviceId): true,
      });
      final c = harness(
        overrides: [
          kioskPrinterAssignmentsProvider.overrideWith((ref) async => null),
        ],
      );
      expect(await decide(c), isFalse);
    });
  });
}
