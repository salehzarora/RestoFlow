import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/order_submission.dart' show OutboxEntry;
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart'
    show posKitchenNetworkPrinterConfigProvider;
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show
        posKitchenSelectedPrinterTransportProvider,
        posNativePrintingAvailableProvider;
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// KITCHEN-PRINT-DUAL-001C — the POS direct_print DISPATCH wiring (cases A/B/C/D).
///
/// The per-device "Automatically print kitchen ticket" toggle now defines TWO
/// workflows. This drives the REAL Send handler and asserts, from the enqueued
/// authoritative payload + the captured kitchen send:
///   A. OFF -> the order.submit op carries NO dispatch_mode (normal KDS) + no print.
///   B. ON  -> the op carries dispatch_mode='direct_print' + the ticket prints.
///   C. The decision is IMMUTABLE: flipping the toggle while the submit is in
///      flight changes NEITHER the dispatched order NOR the print.
///   D. A PRINT failure does NOT undo the authoritative dispatch (the op still
///      carries direct_print); the order stays finalized server-side.

final _menuSource = StateProvider<PosMenuData>(
  (_) => const PosMenuData(
    categories: [],
    currencyCode: 'ILS',
    items: [
      DemoMenuItem(
        id: 'm1',
        name: 'Burger',
        priceMinor: 4000,
        categoryId: 'cat',
        categoryName: 'Mains',
      ),
    ],
  ),
);

class _CapturingTransport implements pp.PrintTransport {
  _CapturingTransport({this.ok = true});
  final bool ok;
  final List<Uint8List> sent = [];
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return ok
        ? const pp.PrintResult.success()
        : const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable);
  }

  @override
  Future<void> dispose() async {}
}

class _GatedOutbox implements OutboxRepository {
  final Completer<void> gate = Completer<void>();
  final Completer<void> entered = Completer<void>();
  final List<OutboxEntry> enqueued = <OutboxEntry>[];
  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    enqueued.add(entry);
    return entry;
  }

  @override
  Future<List<OutboxEntry>> recentEntries() async => List.of(enqueued);
  @override
  Future<OutboxEntry> push(String entryId) async =>
      enqueued.firstWhere((e) => e.id == entryId);
  @override
  Future<OutboxEntry> retry(String entryId) async =>
      enqueued.firstWhere((e) => e.id == entryId);
}

class _FakeAuthTransport implements SyncRpcTransport {
  int _pin = 0;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') return 'pin-session-${++_pin}';
    if (function == 'sync_push') {
      return <String, dynamic>{'ok': true, 'results': <dynamic>[]};
    }
    return null;
  }
}

const _ctx = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-A',
);

ProviderContainer _harness(
  OutboxRepository outbox, {
  required bool toggleOn,
  bool printerConfigured = true,
  List<Override> extra = const [],
}) {
  SharedPreferences.setMockInitialValues({
    if (toggleOn) 'restoflow.autoprint.pos.kitchenTicket.device-1': true,
    if (printerConfigured) ...{
      'restoflow.printer.selected.pos.kitchen_ticket.device-1': 'network',
      'restoflow.printer.network.pos.kitchen_ticket.device-1': jsonEncode({
        'host': '10.0.0.9',
        'port': 9100,
      }),
    },
  });
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(_FakeAuthTransport()),
      posRealSessionConfigProvider.overrideWithValue(null),
      outboxRepositoryProvider.overrideWithValue(outbox),
      posMenuProvider.overrideWith((ref) => ref.watch(_menuSource)),
      posNativePrintingAvailableProvider.overrideWithValue(true),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
}

Future<void> _signInAndWarm(ProviderContainer c) async {
  c.read(posDeviceContextProvider.notifier).set(_ctx);
  await _settle();
  final err = await c
      .read(posSessionControllerProvider.notifier)
      .signInWithPin(
        device: _ctx,
        deviceId: _ctx.deviceId!,
        deviceSessionId: _ctx.deviceSessionId!,
        employeeProfileId: 'emp-1',
        pin: '1234',
      );
  expect(err, isNull);
  await _settle();
  // Warm the async decision inputs so the pre-await read sees them resolved
  // (the toggle + the kitchen-printer config that posHasKitchenNativePrinterProvider
  // reads via valueOrNull).
  await c.read(posAutoPrintKitchenTicketProvider.future);
  await c.read(posKitchenSelectedPrinterTransportProvider.future);
  await c.read(posKitchenNetworkPrinterConfigProvider.future);
  await _settle();
}

Future<
  ({
    ProviderContainer container,
    _GatedOutbox outbox,
    _CapturingTransport captured,
    WidgetRef ref,
    BuildContext context,
    AppLocalizations l10n,
  })
>
_pump(
  WidgetTester tester, {
  required bool toggleOn,
  bool printerConfigured = true,
  bool printOk = true,
}) async {
  final outbox = _GatedOutbox();
  final captured = _CapturingTransport(ok: printOk);
  final c = _harness(
    outbox,
    toggleOn: toggleOn,
    printerConfigured: printerConfigured,
    extra: [
      kitchenPrintTransportOverrideProvider.overrideWithValue((_) => captured),
    ],
  );
  await _signInAndWarm(c);
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  late WidgetRef ref;
  late BuildContext ctx;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            ctx = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    ),
  );
  c
      .read(cartControllerProvider.notifier)
      .addItem(
        const DemoMenuItem(
          id: 'm1',
          name: 'Burger',
          priceMinor: 4000,
          categoryId: 'cat',
          categoryName: 'Mains',
        ),
      );
  return (
    container: c,
    outbox: outbox,
    captured: captured,
    ref: ref,
    context: ctx,
    l10n: l10n,
  );
}

Future<void> _fireSubmit(
  ({
    ProviderContainer container,
    _GatedOutbox outbox,
    _CapturingTransport captured,
    WidgetRef ref,
    BuildContext context,
    AppLocalizations l10n,
  })
  h,
) => submitOrderFromCart(
  ref: h.ref,
  context: h.context,
  cart: h.container.read(cartControllerProvider),
  setup: h.container.read(orderSetupControllerProvider),
  cartController: h.container.read(cartControllerProvider.notifier),
  setupController: h.container.read(orderSetupControllerProvider.notifier),
  l10n: h.l10n,
);

void main() {
  testWidgets('A: toggle OFF -> normal KDS (no dispatch_mode) + no print', (
    tester,
  ) async {
    final h = await _pump(tester, toggleOn: false);
    final pending = _fireSubmit(h);
    await tester.pump();
    await h.outbox.entered.future;
    h.outbox.gate.complete();
    await pending;
    await tester.pumpAndSettle();

    expect(
      h.outbox.enqueued.single.payloadJson.contains('dispatch_mode'),
      isFalse,
      reason: 'a kds order carries NO dispatch_mode (byte-identical payload)',
    );
    expect(h.captured.sent, isEmpty, reason: 'no direct kitchen print');
  });

  testWidgets(
    'B: toggle ON + printer -> dispatch_mode=direct_print + one print',
    (tester) async {
      final h = await _pump(tester, toggleOn: true);
      final pending = _fireSubmit(h);
      await tester.pump();
      await h.outbox.entered.future;
      h.outbox.gate.complete();
      await pending;
      await tester.pumpAndSettle();

      expect(
        h.outbox.enqueued.single.payloadJson,
        contains('"dispatch_mode":"direct_print"'),
      );
      expect(
        h.captured.sent,
        hasLength(1),
        reason: 'the money-free ticket printed once',
      );
      final text = utf8
          .decode(h.captured.sent.single, allowMalformed: true)
          .toLowerCase();
      expect(text.contains('burger'), isTrue);
    },
  );

  testWidgets(
    'C: flipping the toggle mid-submit changes NEITHER dispatch NOR print',
    (tester) async {
      final h = await _pump(tester, toggleOn: true);
      final pending = _fireSubmit(h);
      await tester.pump();
      await h
          .outbox
          .entered
          .future; // submit in flight; decision already captured

      // THE FLIP: the cashier turns the toggle OFF while the submit is in flight.
      await h.container
          .read(posAutoPrintKitchenTicketProvider.notifier)
          .setEnabled(false);
      await tester.pump();

      h.outbox.gate.complete();
      await pending;
      await tester.pumpAndSettle();

      // The PRE-await decision (ON) still governs BOTH surfaces.
      expect(
        h.outbox.enqueued.single.payloadJson,
        contains('"dispatch_mode":"direct_print"'),
      );
      expect(h.captured.sent, hasLength(1));
    },
  );

  testWidgets('D: a PRINT failure does NOT undo the authoritative dispatch', (
    tester,
  ) async {
    final h = await _pump(tester, toggleOn: true, printOk: false);
    final pending = _fireSubmit(h);
    await tester.pump();
    await h.outbox.entered.future;
    h.outbox.gate.complete();
    await pending;
    await tester.pumpAndSettle();

    // The order was dispatched direct_print server-side REGARDLESS of the print.
    expect(
      h.outbox.enqueued.single.payloadJson,
      contains('"dispatch_mode":"direct_print"'),
    );
    // The failing transport was still attempted (honest best-effort) — and the
    // submit itself never threw (a print failure can't fail the order).
    expect(h.captured.sent, hasLength(1));
  });
}
