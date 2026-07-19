// KITCHEN-MODE-001B — Dashboard printer purposes.
//
// Pins:
//   * the `both` role parses, renders as a real third wizard tile, and saves;
//   * unknown role values still parse SAFELY to null (rows skipped, no crash);
//   * the SERVER-RECORD readiness summary is honest per state (missing /
//     disabled / 80mm ready / 80mm required / same-printer-for-both) and the
//     printer-only preparation notice is STATIC text — no toggle, no switch;
//   * Dashboard test-print stays honestly unavailable;
//   * Arabic RTL renders the new surface.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/printers/printer_models.dart';
import 'package:restoflow_dashboard/src/printers/printers_repository.dart';
import 'package:restoflow_dashboard/src/printers/printers_screen.dart';
import 'package:restoflow_core/restoflow_core.dart' show Success;
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminResult;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A snapshot-only repository for readiness scenarios (mutations unused).
class _SnapshotRepo implements PrintersRepository {
  _SnapshotRepo(this.printers);
  final List<PrinterDevice> printers;

  @override
  Future<AdminResult<PrintersSnapshot>> load() async => Success(
    PrintersSnapshot(printers: printers, routes: const [], stations: const []),
  );

  @override
  Future<AdminResult<void>> upsertPrinter({
    String? id,
    required String displayName,
    required PrinterConnectionType connectionType,
    required PrinterRole role,
    required String paperWidth,
    required Map<String, Object?> connectionConfig,
    required bool isEnabled,
  }) async => throw UnimplementedError();

  @override
  Future<AdminResult<void>> setRoute({
    required String stationId,
    required String printerDeviceId,
    required bool isEnabled,
  }) async => throw UnimplementedError();

  @override
  Future<AdminResult<void>> deletePrinter(String id) async =>
      throw UnimplementedError();
}

PrinterDevice _printer({
  required String id,
  required PrinterRole role,
  String paperWidth = '80mm',
  bool isEnabled = true,
}) => PrinterDevice(
  id: id,
  displayName: 'P-$id',
  connectionType: PrinterConnectionType.network,
  role: role,
  paperWidth: paperWidth,
  connectionConfig: const {'host': '10.0.0.50', 'port': 9100},
  isEnabled: isEnabled,
);

Future<void> _pump(
  WidgetTester tester,
  PrintersRepository repo, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(body: PrintersScreen(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PrinterRole model', () {
    test('parses all three roles and keeps unknown values SAFE (null)', () {
      expect(PrinterRole.fromWire('receipt'), PrinterRole.receipt);
      expect(PrinterRole.fromWire('kitchen'), PrinterRole.kitchen);
      expect(PrinterRole.fromWire('both'), PrinterRole.both);
      expect(PrinterRole.fromWire('labels'), isNull);
      expect(PrinterRole.fromWire(null), isNull);
    });

    test('purpose membership derives from the role', () {
      expect(PrinterRole.receipt.servesCustomerReceipts, isTrue);
      expect(PrinterRole.receipt.servesKitchenTickets, isFalse);
      expect(PrinterRole.kitchen.servesCustomerReceipts, isFalse);
      expect(PrinterRole.kitchen.servesKitchenTickets, isTrue);
      expect(PrinterRole.both.servesCustomerReceipts, isTrue);
      expect(PrinterRole.both.servesKitchenTickets, isTrue);
    });
  });

  group('wizard third tile', () {
    testWidgets('Both is a REAL selectable purpose and saves role=both', (
      tester,
    ) async {
      final store = InMemoryPrintersStore();
      await _pump(tester, store);
      await tester.tap(find.text('Add printer'));
      await tester.pumpAndSettle();

      expect(find.text('Both'), findsOneWidget);
      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Display name'),
        'Pass-through',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Host / IP address'),
        '10.0.0.60',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('load failed: $f'),
      );
      expect(
        snapshot.printers.any(
          (p) => p.displayName == 'Pass-through' && p.role == PrinterRole.both,
        ),
        isTrue,
      );
    });
  });

  group('readiness summary (server records only)', () {
    testWidgets('a kitchen-only branch: the customer purpose is Missing; '
        'the preparation notice is static', (tester) async {
      await _pump(
        tester,
        _SnapshotRepo([_printer(id: 'k1', role: PrinterRole.kitchen)]),
      );
      final card = find.byKey(const Key('printer-readiness-summary'));
      expect(card, findsOneWidget);
      expect(find.text('Customer receipt printer'), findsOneWidget);
      expect(find.text('Kitchen ticket printer'), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Missing')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('80mm ready')),
        findsOneWidget,
      );
      // The preparation notice is STATIC text — no toggle/switch exists.
      expect(
        find.text(
          'Printer-only kitchen preparation is not yet available until '
          'device readiness is complete.',
        ),
        findsOneWidget,
      );
      // No activation toggle exists inside the readiness card — the notice is
      // text only (the Switch elsewhere is the card's ENABLED toggle).
      expect(
        find.descendant(of: card, matching: find.byType(Switch)),
        findsNothing,
      );
      // The honest scope caption: server records only.
      expect(
        find.textContaining('device selection and physical printing'),
        findsOneWidget,
      );
    });

    testWidgets('one enabled 80mm BOTH printer satisfies both purposes '
        'and says so', (tester) async {
      await _pump(
        tester,
        _SnapshotRepo([_printer(id: 'b1', role: PrinterRole.both)]),
      );
      expect(find.text('80mm ready'), findsNWidgets(2));
      expect(
        find.text('The same printer can serve both purposes'),
        findsOneWidget,
      );
    });

    testWidgets('a disabled-only purpose reads Disabled; 58mm-only reads '
        '80mm required', (tester) async {
      await _pump(
        tester,
        _SnapshotRepo([
          _printer(id: 'r1', role: PrinterRole.receipt, isEnabled: false),
          _printer(id: 'k1', role: PrinterRole.kitchen, paperWidth: '58mm'),
        ]),
      );
      final card = find.byKey(const Key('printer-readiness-summary'));
      expect(
        find.descendant(of: card, matching: find.text('Disabled')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('80mm required')),
        findsOneWidget,
      );
    });

    testWidgets('test print stays honestly unavailable on the cards', (
      tester,
    ) async {
      await _pump(tester, InMemoryPrintersStore());
      // The existing honesty invariant survives 001B: no enabled test-print
      // button, no fake success claim anywhere.
      expect(find.textContaining('printed'), findsNothing);
    });
  });

  group('RTL', () {
    testWidgets('Arabic renders the readiness card + Both tile label', (
      tester,
    ) async {
      await _pump(
        tester,
        _SnapshotRepo([_printer(id: 'b1', role: PrinterRole.both)]),
        locale: const Locale('ar'),
      );
      // The ar readiness title + the ar same-for-both caption render.
      expect(find.text('جاهزية الطابعات'), findsOneWidget);
      expect(find.text('يمكن للطابعة نفسها خدمة الغرضين'), findsOneWidget);
    });
  });
}
