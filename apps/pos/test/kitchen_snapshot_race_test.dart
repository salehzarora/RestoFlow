import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenPrepComponent, OrderType;
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

/// KITCHEN-PRINT-DUAL-001B (snapshot-race fix) — the POS kitchen ticket and the
/// authoritative submitted order must consume the SAME immutable kitchen-relevant
/// snapshot, captured BEFORE the first await. A menu/preparation edit while the
/// submit is in flight must appear in NEITHER surface. ASCII prep names ("buns" /
/// "rolls") keep the printed count on the decodable ESC/POS text path.

// A live-menu source we can MUTATE mid-flight; posMenuProvider is overridden to
// read it, so flipping it is a real "the live menu changed while submit waited".
final _menuSource = StateProvider<PosMenuData>(
  (_) => _menu(prep: 'buns', qty: 1),
);

PosMenuData _menu({required String prep, required num qty}) => PosMenuData(
  categories: const [],
  currencyCode: 'ILS',
  items: [
    DemoMenuItem(
      id: 'm1',
      name: 'Burger',
      priceMinor: 4000,
      categoryId: 'cat',
      categoryName: 'Mains',
      // KITCHEN-PREP-001: per-unit prep read from the item attributes bag.
      attributes: {
        'prep_components': [
          {'name': prep, 'quantity': qty},
        ],
      },
    ),
  ],
);

class _StubAutoKitchen extends PosAutoPrintKitchenTicketController {
  @override
  Future<bool?> build() async => true;
}

/// Records the kitchen bytes it was handed (no real socket).
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

/// An outbox whose enqueue BLOCKS until released, and which signals the instant
/// it is entered (so the test synchronizes on the real in-flight state, never a
/// sleep). Captures the enqueued entry so its authoritative payload can be read.
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
  List<Override> extra = const [],
}) {
  final c = ProviderContainer(
    overrides: [
      // REAL mode: the order gets a real uuid id (kitchen-print-eligible).
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(_FakeAuthTransport()),
      posRealSessionConfigProvider.overrideWithValue(null),
      outboxRepositoryProvider.overrideWithValue(outbox),
      // The mutable live menu.
      posMenuProvider.overrideWith((ref) => ref.watch(_menuSource)),
      // A configured KITCHEN printer + the auto-print toggle ON. The
      // SharedPreferences kitchen config (setUp) drives the real target
      // resolution for the send; this override makes "a kitchen printer is
      // configured" true SYNCHRONOUSLY for the direct-print decision (whose
      // pre-submit read is sync — see KITCHEN-PRINT-DUAL-001C in cart_panel).
      posNativePrintingAvailableProvider.overrideWithValue(true),
      posHasKitchenNativePrinterProvider.overrideWithValue(true),
      posAutoPrintKitchenTicketProvider.overrideWith(_StubAutoKitchen.new),
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

Future<void> _signIn(ProviderContainer c) async {
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
  // KITCHEN-PRINT-DUAL-001C: warm the toggle so its valueOrNull is settled (true)
  // when submitOrderFromCart reads it SYNCHRONOUSLY — this harness drives the Send
  // handler directly, without painting the CartPanel that normally warms it.
  await c.read(posAutoPrintKitchenTicketProvider.future);
  await _settle();
}

void main() {
  setUp(() {
    // The kitchen-printer config key segment is the PAIRED deviceId (here
    // 'device-1'), not the '.local' fallback — this harness signs in a device.
    SharedPreferences.setMockInitialValues({
      'restoflow.printer.selected.pos.kitchen_ticket.device-1': 'network',
      'restoflow.printer.network.pos.kitchen_ticket.device-1': jsonEncode({
        'host': '10.0.0.9',
        'port': 9100,
      }),
    });
  });

  test('the authoritative payload uses the PASSED prep snapshot, never a live '
      're-read (menu differs at submit time)', () async {
    final outbox = _GatedOutbox();
    final c = _harness(outbox);
    // The LIVE menu says "rolls x9" — but the caller passes the "buns x1"
    // snapshot it captured before the await. The payload must be "buns x1".
    c.read(_menuSource.notifier).state = _menu(prep: 'rolls', qty: 9);
    await _signIn(c);

    final pending = c
        .read(outboxControllerProvider.notifier)
        .submit(
          lines: const [
            CartLineView(
              lineId: 'l1',
              menuItemId: 'm1',
              name: 'Burger',
              quantity: 1,
              unitPriceMinor: 4000,
              lineTotalMinor: 4000,
              currencyCode: 'ILS',
            ),
          ],
          subtotalMinor: 4000,
          currencyCode: 'ILS',
          orderType: OrderType.takeaway,
          prepByItemId: const {
            'm1': [KitchenPrepComponent(name: 'buns', quantity: 1)],
          },
        );
    await outbox.entered.future; // enqueue reached (no sleep)
    outbox.gate.complete();
    await pending;
    await _settle();

    final payload = outbox.enqueued.single.payloadJson;
    expect(payload.contains('buns'), isTrue, reason: 'passed snapshot wins');
    expect(
      payload.contains('rolls'),
      isFalse,
      reason: 'the live menu (rolls) must never enter the payload',
    );
  });

  testWidgets(
    'RACE: a menu/prep edit WHILE the submit is in flight appears in NEITHER '
    'the authoritative payload NOR the POS kitchen ticket',
    (tester) async {
      final captured = _CapturingTransport();
      final outbox = _GatedOutbox();
      final c = _harness(
        outbox,
        extra: [
          kitchenPrintTransportOverrideProvider.overrideWithValue(
            (_) => captured,
          ),
        ],
      );
      // Reset the menu to the "buns x1" default for this test.
      c.read(_menuSource.notifier).state = _menu(prep: 'buns', qty: 1);
      await _signIn(c);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      late WidgetRef capturedRef;
      late BuildContext capturedContext;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
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

      // The live menu is "buns x1". Add the item + submit through the REAL Send
      // handler — it captures the prep snapshot BEFORE the await from this menu.
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
      final pending = submitOrderFromCart(
        ref: capturedRef,
        context: capturedContext,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: c.read(cartControllerProvider.notifier),
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await tester.pump();
      await outbox.entered.future; // the submit is genuinely in flight

      // THE EDIT: the live menu/prep changes to "rolls x9" while submit waits.
      c.read(_menuSource.notifier).state = _menu(prep: 'rolls', qty: 9);
      await tester.pump();
      // Prove the LIVE menu really changed (so the assertions are not vacuous).
      expect(
        c
            .read(posMenuProvider)
            .valueOrNull!
            .items
            .single
            .prepComponents
            .single
            .name,
        'rolls',
      );

      // Release the submit; let the (unawaited, best-effort) kitchen print run.
      outbox.gate.complete();
      await pending;
      await tester.pumpAndSettle();

      // 1) The authoritative payload kept the pre-await snapshot ("buns"),
      //    never the mutated live menu ("rolls").
      final payload = outbox.enqueued.single.payloadJson;
      expect(payload.contains('buns'), isTrue);
      expect(payload.contains('rolls'), isFalse);

      // 2) The POS kitchen ticket kept the SAME pre-await snapshot: its rendered
      //    bytes carry the "buns" count, never the mutated "rolls".
      expect(captured.sent, hasLength(1), reason: 'exactly one kitchen send');
      final text = utf8
          .decode(captured.sent.single, allowMalformed: true)
          .toLowerCase();
      expect(text.contains('buns'), isTrue);
      expect(
        text.contains('rolls'),
        isFalse,
        reason: 'the mutated live menu must never reach the printed ticket',
      );
      // 3) POS and KDS therefore agree: both derive from ONE immutable snapshot.
    },
  );
}
