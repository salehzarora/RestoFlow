import 'dart:async';
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
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_printer_purpose.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-PRINT-DUAL-001C (cold start) — the CartPanel Send GATE driven through
/// the REAL async provider graph (the toggle AND the printer-config providers),
/// NOT a final derived readiness boolean. The decisive proof: Send cannot enable
/// while the toggle is ON and the printer configuration is still unresolved.
///
///   A. Persisted ON — Send disabled while EITHER the toggle OR (once ON) the
///      printer config is loading; enables only when a valid printer resolves,
///      then submits dispatch_mode='direct_print' + one kitchen print.
///   B. Persisted OFF — Send enables as soon as the toggle resolves false, WITHOUT
///      waiting for printer config; submits normal kds (no dispatch_mode, no print).
///   C. ON + no configured printer — Send disabled + a localized configure/disable
///      message; nothing submitted, no KDS fallback.
///   D. ON + printer-config read error — Send disabled + localized retry; retry
///      re-reads the provider; after a valid printer, Send enables.
///   E. Toggle/printer change DURING an in-flight submit — the captured
///      directPrintReady decision governs dispatch + print.

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

PosNetworkPrinterConfig _printer() =>
    PosNetworkPrinterConfig.fromJson(const {'host': '10.0.0.9', 'port': 9100})!;

/// Toggle controller the test drives: [gate] (held loading until completed), else [seed].
class _GateKitchen extends PosAutoPrintKitchenTicketController {
  static Completer<bool?>? gate;
  static bool? seed;
  @override
  Future<bool?> build() async => gate != null ? gate!.future : seed;
}

/// Kitchen-transport controller pinned to network (resolves immediately) — so the
/// ONLY thing that can hold the printer-config chain loading is the config below.
class _NetworkTransport extends PosSelectedPrinterTransportController {
  @override
  Future<PosPrinterTransportKind> build(PosPrinterPurpose arg) async =>
      PosPrinterTransportKind.network;
}

/// Kitchen network-config controller the test drives: throws (read error), or
/// awaits [gate] (held loading), or returns [seed] (a printer, or null = none).
class _CtrlNetworkConfig extends PosNetworkPrinterConfigController {
  static bool throwOnBuild = false;
  static Completer<PosNetworkPrinterConfig?>? gate;
  static PosNetworkPrinterConfig? seed;
  @override
  Future<PosNetworkPrinterConfig?> build(PosPrinterPurpose arg) async {
    // Only the KITCHEN slot is under test; the receipt slot keeps its default.
    if (arg != PosPrinterPurpose.kitchenTicket) return null;
    if (throwOnBuild) throw Exception('printer config read failed');
    return gate != null ? gate!.future : seed;
  }
}

class _CapturingTransport implements pp.PrintTransport {
  final List<Uint8List> sends = [];
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sends.add(bytes);
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

class _RecordingOutbox implements OutboxRepository {
  _RecordingOutbox({this.gate});
  final Completer<void>? gate;
  final Completer<void> entered = Completer<void>();
  final List<OutboxEntry> enqueued = <OutboxEntry>[];
  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    if (!entered.isCompleted) entered.complete();
    if (gate != null) await gate!.future;
    enqueued.add(entry);
    return entry;
  }

  @override
  Future<List<OutboxEntry>> recentEntries() async => List.of(enqueued);
  @override
  Future<OutboxEntry> push(String id) async =>
      enqueued.firstWhere((e) => e.id == id);
  @override
  Future<OutboxEntry> retry(String id) async =>
      enqueued.firstWhere((e) => e.id == id);
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

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
}

Future<
  ({ProviderContainer c, _RecordingOutbox outbox, _CapturingTransport print})
>
_bring(WidgetTester tester, {Completer<void>? outboxGate}) async {
  final outbox = _RecordingOutbox(gate: outboxGate);
  final capture = _CapturingTransport();
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(_FakeAuthTransport()),
      posRealSessionConfigProvider.overrideWithValue(null),
      outboxRepositoryProvider.overrideWithValue(outbox),
      posMenuProvider.overrideWith((ref) => ref.watch(_menuSource)),
      // Control the REAL underlying async graph — NOT posHasKitchenNativePrinter
      // and NOT the derived readiness/decision providers.
      posNativePrintingAvailableProvider.overrideWithValue(true),
      posSelectedPrinterTransportFamily.overrideWith(_NetworkTransport.new),
      posNetworkPrinterConfigFamily.overrideWith(_CtrlNetworkConfig.new),
      posAutoPrintKitchenTicketProvider.overrideWith(_GateKitchen.new),
      kitchenPrintTransportOverrideProvider.overrideWithValue((_) => capture),
    ],
  );
  addTearDown(c.dispose);
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
  return (c: c, outbox: outbox, print: capture);
}

Future<AppLocalizations> _pumpCart(
  WidgetTester tester,
  ProviderContainer c,
) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: CartPanelContent()),
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
  await tester.pump();
  return l10n;
}

bool _sendEnabled(WidgetTester tester, String label) {
  final btn = tester.widget<FilledButton>(
    find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
  );
  return btn.onPressed != null;
}

Future<void> _pumpN(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump();
  }
}

void main() {
  tearDown(() {
    _GateKitchen.gate = null;
    _GateKitchen.seed = null;
    _CtrlNetworkConfig.throwOnBuild = false;
    _CtrlNetworkConfig.gate = null;
    _CtrlNetworkConfig.seed = null;
  });

  testWidgets('A: ON — Send stays DISABLED while the toggle loads AND (once ON) '
      'while printer config loads; enables only when a valid printer resolves, '
      'then submits direct_print', (tester) async {
    _GateKitchen.gate = Completer<bool?>();
    _CtrlNetworkConfig.gate = Completer<PosNetworkPrinterConfig?>();
    final h = await _bring(tester);
    final l10n = await _pumpCart(tester, h.c);

    // Toggle loading -> disabled.
    expect(_sendEnabled(tester, l10n.posSendOrder), isFalse);

    // Toggle resolves ON, but the printer config is STILL loading -> the decisive
    // case: Send must REMAIN disabled (loading is never read as "no printer").
    _GateKitchen.gate!.complete(true);
    await _pumpN(tester);
    expect(
      _sendEnabled(tester, l10n.posSendOrder),
      isFalse,
      reason: 'toggle ON + printer config unresolved must not enable Send',
    );

    // The printer config resolves with a valid kitchen printer -> enabled.
    _CtrlNetworkConfig.gate!.complete(_printer());
    await _pumpN(tester);
    expect(_sendEnabled(tester, l10n.posSendOrder), isTrue);

    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();
    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains(
        '"dispatch_mode":"direct_print"',
      ),
      isTrue,
    );
    expect(h.print.sends, hasLength(1), reason: 'exactly one kitchen print');
  });

  testWidgets('B: OFF — Send enables as soon as the toggle resolves false, '
      'WITHOUT waiting for printer config; submits normal kds', (tester) async {
    _GateKitchen.gate = Completer<bool?>();
    _CtrlNetworkConfig.gate =
        Completer<PosNetworkPrinterConfig?>(); // never done
    final h = await _bring(tester);
    final l10n = await _pumpCart(tester, h.c);

    expect(_sendEnabled(tester, l10n.posSendOrder), isFalse);
    _GateKitchen.gate!.complete(false); // OFF
    await _pumpN(tester);
    // Enabled even though the printer config gate is STILL pending — OFF does not
    // wait for irrelevant printer configuration.
    expect(_sendEnabled(tester, l10n.posSendOrder), isTrue);

    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();
    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains('dispatch_mode'),
      isFalse,
    );
    expect(h.print.sends, isEmpty);
  });

  testWidgets(
    'C: ON + no configured printer — Send disabled + configure/disable '
    'message; nothing submitted',
    (tester) async {
      _GateKitchen.seed = true;
      _CtrlNetworkConfig.seed = null; // resolves: NO printer
      final h = await _bring(tester);
      final l10n = await _pumpCart(tester, h.c);
      await _pumpN(tester);

      expect(_sendEnabled(tester, l10n.posSendOrder), isFalse);
      expect(find.text(l10n.posKitchenNoPrinterConfigured), findsOneWidget);
      expect(h.outbox.enqueued, isEmpty);
    },
  );

  testWidgets('D: ON + printer-config read error — Send disabled + localized '
      'retry; retry re-reads and, with a valid printer, enables', (
    tester,
  ) async {
    _GateKitchen.seed = true;
    _CtrlNetworkConfig.throwOnBuild = true; // read error
    final h = await _bring(tester);
    final l10n = await _pumpCart(tester, h.c);
    await _pumpN(tester);

    expect(_sendEnabled(tester, l10n.posSendOrder), isFalse);
    expect(find.text(l10n.posKitchenPrinterConfigLoadError), findsOneWidget);
    expect(find.text(l10n.authTryAgain), findsOneWidget);
    expect(h.outbox.enqueued, isEmpty);

    // The next read will succeed with a valid printer; retry re-reads it.
    _CtrlNetworkConfig.throwOnBuild = false;
    _CtrlNetworkConfig.seed = _printer();
    await tester.tap(find.text(l10n.authTryAgain));
    await _pumpN(tester, 8);
    expect(_sendEnabled(tester, l10n.posSendOrder), isTrue);
  });

  testWidgets('E: a toggle/printer change DURING an in-flight submit does not '
      'split the workflow — the captured direct_print decision governs', (
    tester,
  ) async {
    final gate = Completer<void>();
    _GateKitchen.seed = true;
    _CtrlNetworkConfig.seed = _printer();
    final h = await _bring(tester, outboxGate: gate);
    final l10n = await _pumpCart(tester, h.c);
    await _pumpN(tester);
    expect(_sendEnabled(tester, l10n.posSendOrder), isTrue);

    await tester.tap(find.text(l10n.posSendOrder)); // decision captured now
    await tester.pump();
    await h.outbox.entered.future; // submit is in flight (enqueue blocked)

    // Flip the toggle OFF mid-flight: the captured directPrintReady decision must
    // still govern BOTH the dispatch AND the print (which reuses the immutable
    // decision, not a re-read). The printer stays configured so the print can run.
    h.c.read(posAutoPrintKitchenTicketProvider.notifier).setEnabled(false);
    await _pumpN(tester);

    gate.complete();
    await tester.pumpAndSettle();

    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains(
        '"dispatch_mode":"direct_print"',
      ),
      isTrue,
      reason: 'the pre-submit directPrintReady decision is immutable',
    );
    expect(h.print.sends, hasLength(1));
  });
}
