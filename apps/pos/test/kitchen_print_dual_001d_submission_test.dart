import 'dart:convert' show jsonEncode;
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
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart'
    show submitOrderFromCart;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/verified_kitchen_mode_readiness.dart';

/// KITCHEN-PRINT-DUAL-001D — every real order ALWAYS uses the normal KDS workflow.
/// The "Automatically print kitchen ticket" toggle no longer selects a workflow:
///   A. OFF     -> normal submit, NO dispatch_mode, zero automatic prints.
///   B. ON      -> the SAME normal submit (NO dispatch_mode) + exactly one print.
///   C. printer missing (ON, no configured printer) -> the order STILL submits
///      normally (Send is never gated); the print is best-effort and prints nothing.

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

class _StubAutoKitchen extends PosAutoPrintKitchenTicketController {
  _StubAutoKitchen(this._value);
  final bool _value;
  @override
  Future<bool?> build() async => _value;
}

class _CapturingTransport implements pp.PrintTransport {
  final List<Uint8List> sent = [];
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

class _RecordingOutbox implements OutboxRepository {
  final List<OutboxEntry> enqueued = <OutboxEntry>[];
  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
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

  @override
  Future<String?> findOrderSubmitCustomerPhone(
    OrderSubmitPhoneLookupKey key,
  ) async => null;
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

Future<({_RecordingOutbox outbox, _CapturingTransport print})> _submit(
  WidgetTester tester, {
  required bool toggleOn,
  required bool printerConfigured,
}) async {
  SharedPreferences.setMockInitialValues({
    if (printerConfigured) ...{
      'restoflow.printer.selected.pos.kitchen_ticket.device-1': 'network',
      'restoflow.printer.network.pos.kitchen_ticket.device-1': jsonEncode({
        'host': '10.0.0.9',
        'port': 9100,
      }),
    },
  });
  final outbox = _RecordingOutbox();
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
      posAutoPrintKitchenTicketProvider.overrideWith(
        () => _StubAutoKitchen(toggleOn),
      ),
      kitchenPrintTransportOverrideProvider.overrideWithValue((_) => capture),
      // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): the branch mode is the
      // normal KDS workflow (the auto-print toggle is orthogonal) — simulate
      // the verified mode so Send is enabled and no dispatch_mode is emitted.
      verifiedKdsReadinessOverride(),
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

  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  late WidgetRef ref;
  late BuildContext ctx;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
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
  await tester.pump();
  await submitOrderFromCart(
    ref: ref,
    context: ctx,
    cart: c.read(cartControllerProvider),
    setup: c.read(orderSetupControllerProvider),
    cartController: c.read(cartControllerProvider.notifier),
    setupController: c.read(orderSetupControllerProvider.notifier),
    l10n: l10n,
  );
  await tester.pumpAndSettle();
  return (outbox: outbox, print: capture);
}

void main() {
  testWidgets('A: toggle OFF — normal submit, NO dispatch_mode, zero prints', (
    tester,
  ) async {
    final h = await _submit(tester, toggleOn: false, printerConfigured: true);
    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains('dispatch_mode'),
      isFalse,
    );
    expect(h.print.sent, isEmpty);
  });

  testWidgets('B: a stale local toggle ON does NOT print on a KDS branch — the '
      'submit is unchanged and the KDS owns the ticket', (tester) async {
    final h = await _submit(tester, toggleOn: true, printerConfigured: true);
    // The ORDER path is untouched: same normal submit, no dispatch_mode.
    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains('dispatch_mode'),
      isFalse,
      reason: 'no direct_print workflow — always normal KDS',
    );
    // POS-KITCHEN-WORKFLOW-REGRESSION-001 — DELIBERATE BEHAVIOUR CHANGE.
    // KITCHEN-PRINT-DUAL-001 let a device toggle add a POS-side kitchen print
    // on top of a KDS branch. Where the Dashboard workflow governs, that is no
    // longer the device's call: a branch that moved from printer_only to a KDS
    // would otherwise keep printing tickets from the till forever, because the
    // stale local `true` was never revisited. The stored value is untouched and
    // still governs on surfaces the central workflow does not reach.
    expect(h.print.sent, isEmpty);
  });

  testWidgets('C: ON but no configured printer — the order STILL submits '
      'normally; the print is best-effort (nothing sent), never a fallback', (
    tester,
  ) async {
    final h = await _submit(tester, toggleOn: true, printerConfigured: false);
    // Send is never gated on the printer — the order is enqueued regardless.
    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains('dispatch_mode'),
      isFalse,
    );
    expect(h.print.sent, isEmpty);
  });
}
