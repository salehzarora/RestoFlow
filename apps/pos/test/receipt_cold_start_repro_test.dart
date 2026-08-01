import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/receipt_logo_raster_cache.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/pos_receipt_logo.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRINT-STARTUP-REPRINT-001 (Defect 1) — REPRODUCTION, through the real
/// `OrderConfirmation` + payment-listener path.
///
/// On a cold start the cashier's FIRST paid order produced no printed receipt
/// and no failure anywhere in the UI. The listener read every async printer
/// source with `.valueOrNull` and returned early while they were still
/// resolving, so no job was ever created — and the payment edge never fires
/// again for that order, so the receipt was gone for good. Separately, the
/// receipt logo was read synchronously, so the first receipt that DID get
/// through printed unbranded while the logo was still resolving.
///
/// Both tests below pay while the printer/logo sources are deliberately still
/// in flight. They compile against the pre-fix code and FAIL on behaviour:
/// no job at all (A), and a logo-less first receipt (B).

/// An assignments reader that stays in flight until the test releases it —
/// exactly the cold-start window between app launch and the first fetch.
class _GatedAssignmentsReader implements DevicePrinterAssignmentsReader {
  _GatedAssignmentsReader({this.withLogo = false});

  final bool withLogo;
  final Completer<void> gate = Completer<void>();

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async {
    await gate.future;
    return Success(
      DevicePrinterAssignments(
        fetchedAt: DateTime(2026, 7, 20, 9),
        organizationId: withLogo ? 'org-1' : null,
        restaurantId: withLogo ? 'rest-1' : null,
        receiptLogoPath: withLogo ? 'org-1/rest-1/logo.png' : null,
        receiptLogoEnabled: withLogo,
        receiptLogoVersion: withLogo ? 3 : 0,
        printers: const [
          AssignedPrinter(
            id: 'prn-1',
            displayName: 'Counter receipt',
            role: 'receipt',
            connectionType: 'network',
            paperWidth: '80mm',
            isEnabled: true,
          ),
        ],
      ),
    );
  }
}

/// A raster cache whose read stays in flight until released — the real
/// cache-first logo path, without needing a decodable image in a unit test.
class _GatedLogoCache implements ReceiptLogoRasterCache {
  final Completer<void> gate = Completer<void>();

  @override
  Future<ReceiptLogoCacheEntry?> read(ReceiptLogoCacheKey key) async {
    await gate.future;
    // Dimensionally valid for the requested profile: a full-width 1bpp canvas.
    final widthBytes = (key.widthDots + 7) ~/ 8;
    const heightDots = 8;
    return ReceiptLogoCacheEntry(
      rasterData: Uint8List.fromList(
        List<int>.filled(widthBytes * heightDots, 0xFF),
      ),
      widthBytes: widthBytes,
      heightDots: heightDots,
      sourceBytes: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
      sourceMime: 'image/png',
    );
  }

  @override
  Future<void> write(
    ReceiptLogoCacheKey key,
    ReceiptLogoCacheEntry entry,
  ) async {}
}

const _order = SubmittedOrderView(
  orderNumber: '#3F7A2C',
  orderType: OrderType.dineIn,
  tableLabel: 'T2',
  currencyCode: 'ILS',
  subtotalMinor: 5400,
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 1,
      lineTotalMinor: 5400,
      currencyCode: 'ILS',
    ),
  ],
);

Future<ProviderContainer> _pumpUnresolved(
  WidgetTester tester, {
  required DevicePrinterAssignmentsReader reader,
  ReceiptLogoRasterCache? logoCache,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      posPrinterAssignmentsReaderProvider.overrideWithValue(reader),
      paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
      if (logoCache != null)
        receiptLogoRasterCacheProvider.overrideWithValue(logoCache),
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
        home: Scaffold(
          body: OrderConfirmation(order: _order, onNewOrder: () {}),
        ),
      ),
    ),
  );
  // Deliberately NOT awaiting the printer sources: this is the cold-start
  // window in which the cashier can already take cash.
  await tester.pump();
  return container;
}

Future<void> _pay(WidgetTester tester, ProviderContainer container) async {
  await container
      .read(paymentControllerProvider.notifier)
      .payCash(
        identity: _order.identity,
        orderId: 'order-1',
        orderNumber: _order.orderNumber,
        amountMinor: _order.subtotalMinor,
        tenderedMinor: 6000,
        currencyCode: 'ILS',
      );
  await tester.pump();
}

bool _hasLogoLine(PrintDocument d) =>
    d.lines.any((l) => l.kind == PrintLineKind.headerImage && l.logo != null);

void main() {
  testWidgets(
    'A. cold start: paying while the printer assignments are still in flight '
    'must NOT silently drop the receipt — the job survives and prints once '
    'the printer resolves',
    (tester) async {
      final reader = _GatedAssignmentsReader();
      final container = await _pumpUnresolved(tester, reader: reader);
      final printer = container.read(receiptPrintControllerProvider.notifier);

      await _pay(tester, container);

      // THE DEFECT: pre-fix this is null — the paid receipt vanished with no
      // job, no status row and no way for the cashier to notice or retry.
      expect(
        printer.jobFor(_order.identity.key),
        isNotNull,
        reason: 'a paid receipt is never dropped while the printer resolves',
      );
      expect(
        find.byKey(const Key('receipt-print-status')),
        findsOneWidget,
        reason: 'the cashier can SEE that the receipt is still pending',
      );

      // The printer finishes resolving a moment later, as it does in the field.
      reader.gate.complete();
      await container.read(posPrinterAssignmentsProvider.future);
      await tester.pumpAndSettle();

      final job = printer.jobFor(_order.identity.key);
      expect(job, isNotNull);
      expect(
        job!.status,
        PrintJobStatus.prepared,
        reason: 'no bridge is wired in tests, so prepared is the honest end',
      );
      expect(job.document, isNotNull);
      expect(
        container.read(receiptPrintControllerProvider).length,
        1,
        reason: 'exactly one receipt for the order — no duplicate',
      );
    },
  );

  testWidgets(
    'B. cold start: the FIRST receipt waits for the first definitive logo '
    'outcome instead of printing unbranded',
    (tester) async {
      final logoCache = _GatedLogoCache();
      final container = await _pumpUnresolved(
        tester,
        reader: _GatedAssignmentsReader(withLogo: true)..gate.complete(),
        logoCache: logoCache,
      );
      final printer = container.read(receiptPrintControllerProvider.notifier);

      // The printer is known, but the branding raster is still being read.
      await container.read(posPrinterAssignmentsProvider.future);
      await tester.pump();
      await _pay(tester, container);

      logoCache.gate.complete();
      await tester.pumpAndSettle();

      final job = printer.jobFor(_order.identity.key);
      expect(job, isNotNull, reason: 'the receipt is not dropped');
      expect(
        _hasLogoLine(job!.document!),
        isTrue,
        reason:
            'THE DEFECT: pre-fix the first receipt printed unbranded '
            'because the logo was read synchronously while still resolving',
      );
    },
  );
}
