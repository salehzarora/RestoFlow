// KITCHEN-MODE-001B — the purpose-aware POS printer store.
//
// Pins the load-bearing guarantees:
//   * LEGACY MIGRATION (identity): a pre-001B installation's saved printer IS
//     the customerReceipt slot — the legacy keys are read unchanged, kept
//     intact, and the mapping is trivially idempotent (nothing is copied).
//   * kitchenTicket starts UNSET and lives under its own purpose-suffixed keys.
//   * The two slots are fully INDEPENDENT: saving/clearing one never touches
//     the other; the SAME endpoint may live in both.
//   * Per-purpose selected transport.
//   * Device-id isolation: selections never leak across device segments.
//   * The explicit copy action ("use the customer printer for kitchen").
//   * The kitchen TEST document is STRUCTURALLY money-free.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_pos/src/state/pos_bluetooth_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_kitchen_printer_copy.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_printer_purpose.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('purpose key scheme', () {
    test(
      'customerReceipt keeps the LEGACY key segment (identity migration)',
      () {
        expect(PosPrinterPurpose.customerReceipt.keySegment, '');
        expect(PosPrinterPurpose.kitchenTicket.keySegment, 'kitchen_ticket.');
        expect(PosPrinterPurpose.customerReceipt.wire, 'customer_receipt');
        expect(PosPrinterPurpose.kitchenTicket.wire, 'kitchen_ticket');
      },
    );
  });

  group('legacy migration + slot independence (network)', () {
    test('a LEGACY saved printer is read as the customerReceipt slot; '
        'kitchenTicket starts unset', () async {
      SharedPreferences.setMockInitialValues({
        // Written by a PRE-001B build (no purpose segment).
        'restoflow.printer.network.pos.local': jsonEncode(
          const NetworkPrinterConfig(host: '10.0.0.5', port: 9100).toJson(),
        ),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final customer = await container.read(
        posNetworkPrinterConfigProvider.future,
      );
      final kitchen = await container.read(
        posKitchenNetworkPrinterConfigProvider.future,
      );
      expect(customer?.host, '10.0.0.5');
      expect(kitchen, isNull);
      // The legacy key is INTACT (nothing was moved or rewritten).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('restoflow.printer.network.pos.local'), isNotNull);
    });

    test('saving the kitchen slot never touches the customer slot '
        '(and vice versa); the SAME endpoint may live in both', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const shared = NetworkPrinterConfig(host: '10.0.0.9', port: 9100);
      await container
          .read(posNetworkPrinterConfigProvider.notifier)
          .save(shared);
      await container
          .read(posKitchenNetworkPrinterConfigProvider.notifier)
          .save(shared);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('restoflow.printer.network.pos.local'), isNotNull);
      expect(
        prefs.getString('restoflow.printer.network.pos.kitchen_ticket.local'),
        isNotNull,
      );

      // Changing the KITCHEN endpoint leaves the customer endpoint alone.
      await container
          .read(posKitchenNetworkPrinterConfigProvider.notifier)
          .save(const NetworkPrinterConfig(host: '10.0.0.77', port: 9100));
      expect(
        (await container.read(posNetworkPrinterConfigProvider.future))?.host,
        '10.0.0.9',
      );
      // Changing the CUSTOMER endpoint leaves the kitchen endpoint alone.
      await container
          .read(posNetworkPrinterConfigProvider.notifier)
          .save(const NetworkPrinterConfig(host: '10.0.0.11', port: 9100));
      expect(
        (await container.read(
          posKitchenNetworkPrinterConfigProvider.future,
        ))?.host,
        '10.0.0.77',
      );
      // Clearing the kitchen slot does NOT clear the customer slot.
      await container
          .read(posKitchenNetworkPrinterConfigProvider.notifier)
          .clear();
      expect(
        await container.read(posKitchenNetworkPrinterConfigProvider.future),
        isNull,
      );
      expect(
        (await container.read(posNetworkPrinterConfigProvider.future))?.host,
        '10.0.0.11',
      );
    });
  });

  group('per-purpose transport + bluetooth independence', () {
    test('each purpose keeps its OWN selected transport', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(posKitchenSelectedPrinterTransportProvider.notifier)
          .select(PosPrinterTransportKind.bluetooth);
      expect(
        await container.read(posSelectedPrinterTransportProvider.future),
        PosPrinterTransportKind.network,
      );
      expect(
        await container.read(posKitchenSelectedPrinterTransportProvider.future),
        PosPrinterTransportKind.bluetooth,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('restoflow.printer.selected.pos.kitchen_ticket.local'),
        'bluetooth',
      );
      expect(prefs.getString('restoflow.printer.selected.pos.local'), isNull);
    });

    test('bluetooth slots are independent per purpose', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(posBluetoothPrinterConfigProvider.notifier)
          .save(const BluetoothPrinterConfig(address: 'AA:BB', name: 'Front'));
      expect(
        await container.read(posKitchenBluetoothPrinterConfigProvider.future),
        isNull,
      );
      await container
          .read(posKitchenBluetoothPrinterConfigProvider.notifier)
          .save(const BluetoothPrinterConfig(address: 'AA:BB', name: 'Front'));
      await container.read(posBluetoothPrinterConfigProvider.notifier).clear();
      expect(
        (await container.read(
          posKitchenBluetoothPrinterConfigProvider.future,
        ))?.address,
        'AA:BB',
      );
    });
  });

  group('device-id isolation', () {
    test('purpose slots are keyed per device — no cross-device leak', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org',
              branchId: 'branch',
              deviceId: 'device-a',
            ),
          );
      await container
          .read(posKitchenNetworkPrinterConfigProvider.notifier)
          .save(const NetworkPrinterConfig(host: '10.1.1.1', port: 9100));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(
          'restoflow.printer.network.pos.kitchen_ticket.device-a',
        ),
        isNotNull,
      );

      // Switching the paired device re-reads the OTHER device's (empty) slot.
      container
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org',
              branchId: 'branch',
              deviceId: 'device-b',
            ),
          );
      expect(
        await container.read(posKitchenNetworkPrinterConfigProvider.future),
        isNull,
      );
    });
  });

  group('use customer printer for kitchen (explicit copy)', () {
    test(
      'copies configs + transport once; slots stay independent after',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(posNetworkPrinterConfigProvider.notifier)
            .save(const NetworkPrinterConfig(host: '10.2.2.2', port: 9100));
        await container
            .read(posSelectedPrinterTransportProvider.notifier)
            .select(PosPrinterTransportKind.network);

        final copied = await container.read(
          useCustomerPrinterForKitchenProvider,
        )();
        expect(copied, isTrue);
        expect(
          (await container.read(
            posKitchenNetworkPrinterConfigProvider.future,
          ))?.host,
          '10.2.2.2',
        );
        // A copy is a COPY: changing the kitchen slot afterwards never writes
        // back to the customer slot.
        await container
            .read(posKitchenNetworkPrinterConfigProvider.notifier)
            .save(const NetworkPrinterConfig(host: '10.3.3.3', port: 9100));
        expect(
          (await container.read(posNetworkPrinterConfigProvider.future))?.host,
          '10.2.2.2',
        );
      },
    );

    test('reports false when the customer slot has nothing to copy', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        await container.read(useCustomerPrinterForKitchenProvider)(),
        isFalse,
      );
      expect(
        await container.read(posKitchenNetworkPrinterConfigProvider.future),
        isNull,
      );
    });
  });

  group('kitchen TEST document (money-free by construction)', () {
    test('contains the TEST banner + sample lines and NO money content', () {
      final doc = escPosKitchenTestDocument(
        testBanner: '*** TEST ***',
        title: 'Kitchen ticket test',
        sampleLines: const [
          '1 x Sample item',
          '+ Sample modifier',
          'Note: sample note',
        ],
        printerName: 'Kitchen P1',
      );
      final texts = doc.lines.whereType<PrintTextLine>().map((l) => l.text);
      expect(texts, contains('*** TEST ***'));
      expect(texts, contains('Kitchen ticket test'));
      expect(texts, contains('1 x Sample item'));
      // STRUCTURAL money-free proof: no currency, total, paid or change token
      // can appear — the builder has no money input at all; assert the output
      // too (a money value here is a P0 failure).
      final joined = texts.join('\n').toLowerCase();
      for (final forbidden in [
        '₪',
        'total',
        'paid',
        'change',
        'subtotal',
        'ils',
        'usd',
        'eur',
        'price',
        'amount',
      ]) {
        expect(
          joined.contains(forbidden.toLowerCase()),
          isFalse,
          reason: 'kitchen TEST document must never contain "$forbidden"',
        );
      }
    });
  });
}
