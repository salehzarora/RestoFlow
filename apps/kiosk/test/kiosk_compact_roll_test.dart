import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_kiosk/src/data/kiosk_order_submit.dart'
    show KioskClaimedKitchenDispatch;
import 'package:restoflow_kiosk/src/print/kiosk_kitchen_auto_print.dart';
import 'package:restoflow_kiosk/src/print/kiosk_printer_purpose.dart';
import 'package:restoflow_kiosk/src/print/kiosk_receipt_auto_print.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_receipt_branding.dart';
import 'package:restoflow_kiosk/src/state/kiosk_staff_access.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

class _Printer extends Fake implements BluetoothPrintApi {
  final jobs = <({int size, int chunk, Duration pause})>[];
  bool shortWrite = false;

  @override
  Future<bool> permissionsGranted() async => true;

  @override
  Future<BluetoothJobResult> printBytes({
    required String address,
    required Uint8List bytes,
    required Duration timeout,
    int chunkBytes = kBluetoothChunkBytes,
    Duration chunkDelay = kBluetoothChunkDelay,
    Duration drainDelay = kBluetoothDrainDelay,
  }) async {
    jobs.add((size: bytes.length, chunk: chunkBytes, pause: chunkDelay));
    return BluetoothJobResult(
      code: BluetoothJobCode.ok,
      bytesSent: shortWrite ? bytes.length - 1 : bytes.length,
      chunks: (bytes.length + chunkBytes - 1) ~/ chunkBytes,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = 'kiosk-trial';
  const address = '02:00:00:00:00:03';
  const order = KioskOrderSnapshot(
    number: 1,
    orderId: 'kiosk-test',
    code: 'T1',
    lines: [],
    totalMinor: 0,
    service: KioskServiceType.takeaway,
    table: null,
    customerName: '',
  );
  KioskClaimedKitchenDispatch dispatch(String id) =>
      KioskClaimedKitchenDispatch(
        id: id,
        claimExpiresAt: null,
        payload: {
          'v': 1,
          'created_at': '2026-08-25T11:07:00Z',
          'order_code': 'T1',
          'order_type': 'takeaway',
          'kind': 'initial_order',
          'items': [
            for (var i = 0; i < 24; i++)
              {'qty': 1, 'name': 'برجر · כריך $i', 'prep': [], 'modifiers': []},
          ],
        },
      );

  test(
    'cold kiosk receipt and claimed kitchen ticket each use one full write; ambiguous kitchen send stays held',
    () async {
      final config = jsonEncode({'address': address});
      SharedPreferences.setMockInitialValues({
        'restoflow.printer.bluetooth.kiosk.$scope': config,
        'restoflow.printer.selected.kiosk.$scope': 'bluetooth',
        kioskKitchenBluetoothKey(scope): config,
        kioskKitchenSelectedKey(scope): 'bluetooth',
        kioskAutoPrintPrefKey(scope): true,
      });
      final api = _Printer();
      final c = ProviderContainer(
        overrides: [
          nativePrintingAvailableProvider.overrideWithValue(true),
          nativePrinterNamespaceProvider.overrideWithValue('kiosk'),
          nativePrinterDeviceIdProvider.overrideWithValue(scope),
          kioskDeviceContextProvider.overrideWith(
            (r) => const DeviceContext(
              organizationId: 'trial',
              branchId: 'trial',
              deviceId: scope,
              deviceType: 'kiosk',
            ),
          ),
          bluetoothPrinterConnectorProvider.overrideWithValue(
            ChannelBluetoothConnector(api: api),
          ),
          nativePrintRasterizerProvider.overrideWithValue(
            const FlutterReceiptRasterizer(),
          ),
          kioskReceiptBrandingProvider.overrideWith(
            (r) async =>
                const KioskReceiptBranding(restaurantName: 'مطعم الاختبار'),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c
          .read(kioskReceiptAutoPrintProvider)
          .onOrderAccepted(order: order, lang: 'ar');
      expect(
        c.read(kioskReceiptPrintStatusProvider)?.outcome,
        KioskReceiptPrintOutcome.sent,
      );
      final kitchen = c.read(kioskKitchenTicketPrinterProvider);
      await kitchen.onOrderAccepted(
        order: order,
        lang: 'he',
        dispatch: dispatch('initial'),
      );
      expect(
        c.read(kioskKitchenPrintStatusProvider)?.outcome,
        KioskKitchenPrintOutcome.sent,
      );
      expect(api.jobs, hasLength(2));
      for (final job in api.jobs) {
        expect(job.chunk, job.size);
        expect(job.pause, Duration.zero);
      }
      api.shortWrite = true;
      await kitchen.onOrderAccepted(
        order: order,
        lang: 'ar',
        dispatch: dispatch('uncertain'),
      );
      expect(
        c.read(kioskKitchenPrintStatusProvider)?.outcome,
        KioskKitchenPrintOutcome.possiblyPrinted,
      );
      await kitchen.retry();
      expect(api.jobs, hasLength(3));

      api.shortWrite = false;
      final pref = nativeCompactRollProvider(
        pp.PrinterDestinationSendGate.bluetoothKey(address),
      );
      expect(await c.read(pref.notifier).setEnabled(false), isTrue);
      await kitchen.onOrderAccepted(
        order: order,
        lang: 'en',
        dispatch: dispatch('compatibility'),
      );
      expect(
        c.read(kioskKitchenPrintStatusProvider)?.outcome,
        KioskKitchenPrintOutcome.sent,
      );
      expect(api.jobs.last.chunk, kBluetoothChunkBytes);
      expect(api.jobs.last.pause, kBluetoothChunkDelay);
    },
  );
}
