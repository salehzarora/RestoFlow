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
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_kitchen_workflow.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_network_printer_config.dart';
import 'package:restoflow_pos/src/state/pos_printer_purpose.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-PRINT-DUAL-001C — the FAIL-CLOSED submit handler guard, driven on the
/// REAL submitOrderFromCart seam DIRECTLY (not only the disabled button). An
/// unresolved / non-submittable kitchen-workflow decision must create NO order:
/// the exhaustive switch rejects loading / error / directPrintMissingPrinter
/// BEFORE any outbox op or printer send, never falling back to a KDS order.

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

class _SeedToggle extends PosAutoPrintKitchenTicketController {
  static bool? seed;
  @override
  Future<bool?> build() async => seed;
}

class _NetworkTransport extends PosSelectedPrinterTransportController {
  @override
  Future<PosPrinterTransportKind> build(PosPrinterPurpose arg) async =>
      PosPrinterTransportKind.network;
}

class _CtrlConfig extends PosNetworkPrinterConfigController {
  static bool throwOnBuild = false;
  static Completer<PosNetworkPrinterConfig?>? gate;
  static PosNetworkPrinterConfig? seed;
  @override
  Future<PosNetworkPrinterConfig?> build(PosPrinterPurpose arg) async {
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

class _Harness {
  _Harness(this.c, this.outbox, this.print, this.ref, this.context, this.l10n);
  final ProviderContainer c;
  final _RecordingOutbox outbox;
  final _CapturingTransport print;
  final WidgetRef ref;
  final BuildContext context;
  final AppLocalizations l10n;

  Future<void> submit() => submitOrderFromCart(
    ref: ref,
    context: context,
    cart: c.read(cartControllerProvider),
    setup: c.read(orderSetupControllerProvider),
    cartController: c.read(cartControllerProvider.notifier),
    setupController: c.read(orderSetupControllerProvider.notifier),
    l10n: l10n,
  );
}

/// Signs in a real session, pumps a bare Consumer (so the REAL handler can be
/// called directly), adds one cart line, and drives the workflow decision to
/// [target] via the underlying async providers — NEVER an override of
/// posHasKitchenNativePrinterProvider or the derived readiness/decision providers.
Future<_Harness> _bring(
  WidgetTester tester,
  PosKitchenWorkflowDecision target, {
  Completer<void>? outboxGate,
}) async {
  _SeedToggle.seed = null;
  _CtrlConfig.throwOnBuild = false;
  _CtrlConfig.gate = null;
  _CtrlConfig.seed = null;
  switch (target) {
    case PosKitchenWorkflowDecision.normalKdsReady:
      _SeedToggle.seed = false;
    case PosKitchenWorkflowDecision.loading:
      _SeedToggle.seed = true;
      _CtrlConfig.gate = Completer<PosNetworkPrinterConfig?>(); // held loading
    case PosKitchenWorkflowDecision.error:
      _SeedToggle.seed = true;
      _CtrlConfig.throwOnBuild = true;
    case PosKitchenWorkflowDecision.directPrintMissingPrinter:
      _SeedToggle.seed = true;
      _CtrlConfig.seed = null;
    case PosKitchenWorkflowDecision.directPrintReady:
      _SeedToggle.seed = true;
      _CtrlConfig.seed = _printer();
  }

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
      posNativePrintingAvailableProvider.overrideWithValue(true),
      posSelectedPrinterTransportFamily.overrideWith(_NetworkTransport.new),
      posNetworkPrinterConfigFamily.overrideWith(_CtrlConfig.new),
      posAutoPrintKitchenTicketProvider.overrideWith(_SeedToggle.new),
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
  // Resolve the toggle, then trigger + settle the decision chain (loading stays
  // loading — its config gate is never completed).
  await c.read(posAutoPrintKitchenTicketProvider.future);
  c.read(posKitchenWorkflowDecisionProvider);
  await _settle();
  expect(
    c.read(posKitchenWorkflowDecisionProvider),
    target,
    reason: 'harness drove the decision to $target',
  );

  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  late WidgetRef capturedRef;
  late BuildContext capturedContext;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            capturedContext = context;
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
  await tester.pump();
  return _Harness(c, outbox, capture, capturedRef, capturedContext, l10n);
}

void main() {
  // The three REJECTED states: a direct handler call must create NO order.
  for (final rejected in const [
    PosKitchenWorkflowDecision.loading,
    PosKitchenWorkflowDecision.error,
    PosKitchenWorkflowDecision.directPrintMissingPrinter,
  ]) {
    testWidgets('$rejected — a direct submit is REJECTED: zero orders, zero '
        'prints, zero KDS fallback, cart unchanged', (tester) async {
      final h = await _bring(tester, rejected);
      expect(h.c.read(cartControllerProvider).lines, hasLength(1));

      await h.submit();
      await tester.pumpAndSettle();

      expect(h.outbox.enqueued, isEmpty, reason: 'no order was submitted');
      expect(h.print.sends, isEmpty, reason: 'no kitchen print');
      // No KDS fallback + cart untouched + no success confirmation.
      final cart = h.c.read(cartControllerProvider);
      expect(cart.lines, hasLength(1), reason: 'the cart is unchanged');
      expect(cart.submittedOrder, isNull, reason: 'no success reported');
    });
  }

  testWidgets('normalKdsReady — a direct submit creates ONE normal KDS order '
      '(no dispatch_mode, no direct kitchen print)', (tester) async {
    final h = await _bring(tester, PosKitchenWorkflowDecision.normalKdsReady);
    await h.submit();
    await tester.pumpAndSettle();
    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains('dispatch_mode'),
      isFalse,
    );
    expect(h.print.sends, isEmpty);
  });

  testWidgets('directPrintReady — a direct submit creates ONE '
      'dispatch_mode=direct_print order + exactly one kitchen print', (
    tester,
  ) async {
    final h = await _bring(tester, PosKitchenWorkflowDecision.directPrintReady);
    await h.submit();
    await tester.pumpAndSettle();
    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains(
        '"dispatch_mode":"direct_print"',
      ),
      isTrue,
    );
    expect(h.print.sends, hasLength(1));
  });

  testWidgets(
    'in-flight immutability — a decision change to normalKdsReady '
    'DURING an in-flight submit does not override the captured directPrintReady',
    (tester) async {
      final gate = Completer<void>();
      final h = await _bring(
        tester,
        PosKitchenWorkflowDecision.directPrintReady,
        outboxGate: gate,
      );

      final pending = h.submit(); // captures directPrintReady synchronously
      await h.outbox.entered.future; // enqueue is blocked at the gate

      // Flip the toggle OFF mid-flight -> the live decision becomes normalKdsReady.
      h.c.read(posAutoPrintKitchenTicketProvider.notifier).setEnabled(false);
      await _settle();
      expect(
        h.c.read(posKitchenWorkflowDecisionProvider),
        PosKitchenWorkflowDecision.normalKdsReady,
        reason: 'the live decision changed mid-flight',
      );

      gate.complete();
      await pending;
      await tester.pumpAndSettle();

      // The captured directPrintReady still governs the dispatch + the print.
      expect(h.outbox.enqueued, hasLength(1));
      expect(
        h.outbox.enqueued.single.payloadJson.contains(
          '"dispatch_mode":"direct_print"',
        ),
        isTrue,
      );
      expect(h.print.sends, hasLength(1));
    },
  );
}
