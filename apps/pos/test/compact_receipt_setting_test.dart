import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        BluetoothPairedResult,
        BluetoothPrinterConnector,
        bluetoothPrinterConnectorProvider;
import 'package:restoflow_pos/src/state/pos_bluetooth_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_compact_receipt.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/widgets/printer_settings_section.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineBluetooth extends Fake implements BluetoothPrinterConnector {
  @override
  Future<BluetoothPairedResult> pairedDevices() async =>
      const BluetoothPairedResult.ok([]);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved opt-in belongs to the physical endpoint and the till', () async {
    ProviderContainer openTill(String id) {
      final container = ProviderContainer(
        overrides: [
          posPrinterScopeSegmentProvider.overrideWith((ref) async => id),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    final first = posCompactReceiptProvider(
      pp.PrinterDestinationSendGate.networkKey('192.0.2.1', 9100),
    );
    final otherPort = posCompactReceiptProvider(
      pp.PrinterDestinationSendGate.networkKey('192.0.2.1', 9101),
    );
    final otherConnection = posCompactReceiptProvider(
      pp.PrinterDestinationSendGate.bluetoothKey('02:00:00:00:00:01'),
    );
    final a = openTill('A');
    expect(await a.read(first.future), isFalse);
    expect(await a.read(first.notifier).setEnabled(true), isTrue);
    expect(await a.read(otherPort.future), isFalse);
    expect(await a.read(otherConnection.future), isFalse);
    expect(await openTill('B').read(first.future), isFalse);
    final reopened = openTill('A');
    expect(await reopened.read(first.future), isTrue);
    expect(await reopened.read(first.notifier).setEnabled(false), isTrue);
    expect(await openTill('A').read(first.future), isFalse);
  });

  testWidgets(
    'customer roll toggle saves and reloads separately for Wi-Fi and Bluetooth',
    (tester) async {
      final toggle = find.byKey(const Key('compact-app-font-receipt'));
      final labels = await AppLocalizations.delegate.load(const Locale('en'));
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<ProviderContainer> open() async {
        final container = ProviderContainer(
          overrides: [
            bluetoothPrinterConnectorProvider.overrideWithValue(
              _OfflineBluetooth(),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: const Scaffold(
                body: SingleChildScrollView(child: PrinterSettingsSection()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return container;
      }

      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      bool value() => tester.widget<SwitchListTile>(toggle).value;
      final c = await open();
      expect(toggle, findsNothing); // No saved destination.
      const roll = PosNetworkPrinterConfig(host: '192.0.2.1', port: 9100);
      await c.read(posNetworkPrinterConfigProvider.notifier).save(roll);
      await tester.pumpAndSettle();
      expect(value(), isFalse);
      await tap(toggle);
      expect(value(), isTrue);
      await tap(find.text(labels.posPrinterTransportBluetooth));
      expect(toggle, findsNothing);
      const bt = '02:00:00:00:00:01';
      await c
          .read(posBluetoothPrinterConfigProvider.notifier)
          .save(const PosBluetoothPrinterConfig(address: bt));
      await tester.pumpAndSettle();
      expect(value(), isFalse);
      await tap(toggle);
      expect(value(), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final fresh = await open();
      expect(value(), isTrue); // Persisted Bluetooth selection and setting.
      await tap(toggle);
      expect(value(), isFalse);
      await tap(find.text(labels.posPrinterTransportNetwork));
      expect(value(), isTrue); // Bluetooth edit did not change Wi-Fi.
      await fresh
          .read(posKitchenNetworkPrinterConfigProvider.notifier)
          .save(roll);
      await tap(find.text(labels.posPrinterPurposeKitchen));
      expect(toggle, findsNothing);
      await tap(find.text(labels.posPrinterPurposeCustomer));
      expect(value(), isTrue);
      await fresh
          .read(posNetworkPrinterConfigProvider.notifier)
          .save(
            const PosNetworkPrinterConfig(
              host: '192.0.2.1',
              port: 9100,
              mediaProfileId: 'label80x80',
            ),
          );
      await tester.pumpAndSettle();
      expect(toggle, findsNothing);
      await fresh
          .read(posBluetoothPrinterConfigProvider.notifier)
          .save(
            const PosBluetoothPrinterConfig(
              address: bt,
              mediaProfileId: 'label50x50',
            ),
          );
      await tap(find.text(labels.posPrinterTransportBluetooth));
      expect(toggle, findsNothing);
    },
  );
}
