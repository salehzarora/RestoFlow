import 'dart:async';
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
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// KITCHEN-PRINT-DUAL-001C (cold start) — the CartPanel Send GATE.
///
/// The direct-print decision is captured SYNCHRONOUSLY at submit time from the
/// persisted toggle. So in REAL mode Send must WAIT until that toggle resolves:
///   A. persisted ON  — Send is DISABLED while AsyncLoading; once it resolves it
///      ENABLES, and the submitted op then carries dispatch_mode='direct_print'.
///   B. persisted OFF — Send waits for resolution too, then submits the NORMAL
///      kds workflow (no dispatch_mode).
///   C. read FAILURE  — Send stays unavailable + an honest localized error/retry
///      is shown; no order is submitted.
/// (D — a toggle change DURING an in-flight submit not splitting the workflow —
///  is proven on the real Send handler in kitchen_direct_print_dispatch_test C.)

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

/// A toggle controller whose resolution the test drives: [gate] (if set) is
/// awaited (held AsyncLoading until completed); otherwise it returns [seed].
class _GateKitchen extends PosAutoPrintKitchenTicketController {
  static Completer<bool?>? gate;
  static bool? seed;
  @override
  Future<bool?> build() async {
    final g = gate;
    if (g != null) return g.future;
    return seed;
  }
}

/// A toggle controller whose read FAILS (AsyncError) — a genuine prefs failure.
class _ThrowKitchen extends PosAutoPrintKitchenTicketController {
  @override
  Future<bool?> build() async => throw Exception('prefs read failed');
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
_bring(WidgetTester tester, {required List<Override> toggleOverride}) async {
  SharedPreferences.setMockInitialValues({
    'restoflow.printer.selected.pos.kitchen_ticket.device-1': 'network',
    'restoflow.printer.network.pos.kitchen_ticket.device-1': jsonEncode({
      'host': '10.0.0.9',
      'port': 9100,
    }),
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
      // A kitchen printer IS configured, so the direct-print decision can be ON.
      posHasKitchenNativePrinterProvider.overrideWithValue(true),
      kitchenPrintTransportOverrideProvider.overrideWithValue((_) => capture),
      ...toggleOverride,
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
  // A ready-to-submit cart (the default takeaway setup + one line) so ONLY the
  // toggle-readiness gate governs whether Send is enabled.
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

void main() {
  tearDown(() {
    _GateKitchen.gate = null;
    _GateKitchen.seed = null;
  });

  testWidgets('A: persisted ON — Send is DISABLED while the toggle loads, then '
      'ENABLES and submits dispatch_mode=direct_print', (tester) async {
    _GateKitchen.gate = Completer<bool?>();
    final h = await _bring(
      tester,
      toggleOverride: [
        posAutoPrintKitchenTicketProvider.overrideWith(_GateKitchen.new),
      ],
    );
    final l10n = await _pumpCart(tester, h.c);

    // Loading: Send is held disabled.
    expect(_sendEnabled(tester, l10n.posSendOrder), isFalse);

    // The persisted setting resolves ON.
    _GateKitchen.gate!.complete(true);
    await tester.pump();
    await tester.pump();
    expect(_sendEnabled(tester, l10n.posSendOrder), isTrue);

    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();
    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains(
        '"dispatch_mode":"direct_print"',
      ),
      isTrue,
      reason: 'the resolved ON setting drives a direct_print dispatch',
    );
  });

  testWidgets('B: persisted OFF — Send waits for resolution, then submits the '
      'normal kds workflow (no dispatch_mode)', (tester) async {
    _GateKitchen.gate = Completer<bool?>();
    final h = await _bring(
      tester,
      toggleOverride: [
        posAutoPrintKitchenTicketProvider.overrideWith(_GateKitchen.new),
      ],
    );
    final l10n = await _pumpCart(tester, h.c);

    expect(_sendEnabled(tester, l10n.posSendOrder), isFalse);
    _GateKitchen.gate!.complete(false); // never chosen / off
    await tester.pump();
    await tester.pump();
    expect(_sendEnabled(tester, l10n.posSendOrder), isTrue);

    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();
    expect(h.outbox.enqueued, hasLength(1));
    expect(
      h.outbox.enqueued.single.payloadJson.contains('dispatch_mode'),
      isFalse,
      reason: 'OFF is the normal kds workflow — no dispatch_mode',
    );
    expect(
      h.print.sends,
      isEmpty,
      reason: 'no direct POS kitchen send when OFF',
    );
  });

  testWidgets('C: a read FAILURE keeps Send unavailable, shows a localized '
      'error + retry, and submits nothing', (tester) async {
    final h = await _bring(
      tester,
      toggleOverride: [
        posAutoPrintKitchenTicketProvider.overrideWith(_ThrowKitchen.new),
      ],
    );
    final l10n = await _pumpCart(tester, h.c);
    await tester.pump();

    expect(_sendEnabled(tester, l10n.posSendOrder), isFalse);
    // Honest localized error + a retry affordance.
    expect(find.text(l10n.posKitchenSettingLoadError), findsOneWidget);
    expect(find.text(l10n.authTryAgain), findsOneWidget);
    // Nothing was (or could be) submitted.
    expect(h.outbox.enqueued, isEmpty);
  });
}
