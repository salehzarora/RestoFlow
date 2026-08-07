@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        BluetoothDeviceInfo,
        BluetoothPairedResult,
        BluetoothPrinterConnector,
        bluetoothPrinterConnectorProvider,
        kBluetoothPrintTimeout,
        nativePrinterNamespaceProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/pos_cash_drawer_claim_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/print/native_print_bridges.dart';
import 'package:restoflow_pos/src/print/print_document.dart' as app_receipt;
import 'package:restoflow_pos/src/print/pos_cash_drawer_service.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_cash_drawer_setting.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/state/pos_receipt_logo.dart';
import 'package:restoflow_pos/src/state/pos_session.dart'
    show posSyncSessionProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildBillDocument;
import 'package:shared_preferences/shared_preferences.dart';

/// POS-CASH-DRAWER-AUTO-OPEN — the cash-drawer auto-open feature.
///
/// A. the per-device setting (default OFF, key convention, persistence);
/// B. the service gate chain over REAL providers (cash-only, demo, claim
///    durability across containers, refusals, no-retry);
/// C. the bridge seam bytes (exactly init + codepage + ESC p 0 25 25, no
///    raster, the shared per-destination send gate);
/// D. the ONE call site in [CashPaymentSheet] (kick fires only from the
///    authoritative payment edge; skips silent; the one sendFailed snackbar).
///
/// Fakes only — no command ever reaches a real printer or device.

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

/// The default drawer-kick pulse RF-070's builder emits (ESC p 0 25 25).
const List<int> _kickPulse = <int>[0x1B, 0x70, 0x00, 25, 25];

/// The full expected kick payload: ESC @ init, ESC t 0 (cp437), ESC p pulse.
const List<int> _kickBytes = <int>[
  0x1B, 0x40, // init
  0x1B, 0x74, 0x00, // select code page (cp437)
  0x1B, 0x70, 0x00, 25, 25, // drawer kick pulse
];

/// The GS v 0 raster header — a kick must NEVER contain raster bytes.
const List<int> _rasterHeader = <int>[0x1D, 0x76, 0x30];

bool _containsSequence(List<int> bytes, List<int> needle) {
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

int _pulseSendCount(Iterable<Uint8List> batches) =>
    batches.where((b) => _containsSequence(b, _kickPulse)).length;

class _RecordingConnector implements BluetoothPrinterConnector {
  _RecordingConnector({this.result = const pp.PrintResult.success()});

  final List<Uint8List> sent = <Uint8List>[];
  pp.PrintResult result;

  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<BluetoothPairedResult> pairedDevices() async =>
      const BluetoothPairedResult.ok(<BluetoothDeviceInfo>[]);

  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = kBluetoothPrintTimeout,
  }) async {
    sent.add(bytes);
    return result;
  }
}

const String _settingKey = 'restoflow.printer.cash_drawer_auto_open.pos.local';

Map<String, Object> _printerPrefs({bool settingOn = true}) => <String, Object>{
  'restoflow.printer.selected.pos.local': 'bluetooth',
  'restoflow.printer.bluetooth.pos.local': jsonEncode(<String, Object?>{
    'address': '66:32:1E:0A:BB:CD',
    'name': 'Counter',
  }),
  if (settingOn) _settingKey: true,
};

const PosSyncScope _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'br-1',
  deviceId: 'dev-1',
);

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

const String _claimsKey = 'restoflow.pos.cash_drawer_claims.v1.dev-1';

CashPayment _payment(String id, {PaymentMethod method = PaymentMethod.cash}) =>
    CashPayment(
      paymentId: id,
      orderNumber: '#DRW1',
      deviceId: 'dev-1',
      localOperationId: 'op-$id',
      method: method,
      status: PaymentStatus.completed,
      amountMinor: 4200,
      tenderedMinor: 4200,
      changeMinor: 0,
      currencyCode: 'ILS',
      receiptNumber: 'PROV-9',
      paidAt: DateTime.utc(2026, 8, 7, 12),
    );

/// A REAL-mode container (demo would demoSkip by design): the real service,
/// the real setting/claim/bridge providers over mock prefs, and a recording
/// fake Bluetooth transport. No network, no hardware.
ProviderContainer _serviceContainer(
  _RecordingConnector connector, {
  bool demo = false,
  PosSyncScope? scope = _scope,
  SyncSession? session = _session,
  List<Override> extra = const <Override>[],
}) {
  final c = ProviderContainer(
    overrides: <Override>[
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: demo),
      ),
      posSyncScopeProvider.overrideWithValue(scope),
      posSyncSessionProvider.overrideWithValue(session),
      posNativePrintingAvailableProvider.overrideWithValue(true),
      nativePrinterNamespaceProvider.overrideWithValue('pos'),
      bluetoothPrinterConnectorProvider.overrideWithValue(connector),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  // -------------------------------------------------------------------------
  // A. The per-device setting
  // -------------------------------------------------------------------------
  group('A. per-device setting', () {
    test('defaults OFF with empty prefs', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(await c.read(posCashDrawerAutoOpenProvider.future), isFalse);
    });

    test('enable persists under the printer-key convention and survives a '
        'new container; disable persists too', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(posCashDrawerAutoOpenProvider.future);
      await c.read(posCashDrawerAutoOpenProvider.notifier).setEnabled(true);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(_settingKey),
        isTrue,
        reason:
            'the exact key follows restoflow.printer.<kind>.pos.<segment> '
            '(pos_printer_transport.dart convention)',
      );

      // Provider recreation (new process) reads the persisted value back.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      expect(await c2.read(posCashDrawerAutoOpenProvider.future), isTrue);

      await c2.read(posCashDrawerAutoOpenProvider.notifier).setEnabled(false);
      expect(prefs.getBool(_settingKey), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // B. Service gating over real providers
  // -------------------------------------------------------------------------
  group('B. service gating', () {
    test('setting OFF + cash => disabledSkip, zero sends', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs(settingOn: false));
      final connector = _RecordingConnector();
      final c = _serviceContainer(connector);

      final outcome = await c
          .read(posCashDrawerServiceProvider)
          .kickForPayment(_payment('pay-off'));

      expect(outcome, PosCashDrawerOutcome.disabledSkip);
      expect(connector.sent, isEmpty);
    });

    test('demo mode => demoSkip even with the setting ON', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final c = _serviceContainer(connector, demo: true);

      final outcome = await c
          .read(posCashDrawerServiceProvider)
          .kickForPayment(_payment('pay-demo'));

      expect(outcome, PosCashDrawerOutcome.demoSkip);
      expect(connector.sent, isEmpty);
    });

    test('ON + card/bit/external => nonCashSkip, zero sends (RF-074 '
        'cash-only)', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final c = _serviceContainer(connector);
      final service = c.read(posCashDrawerServiceProvider);

      for (final method in <PaymentMethod>[
        PaymentMethod.card,
        PaymentMethod.bit,
        PaymentMethod.externalTender,
      ]) {
        final outcome = await service.kickForPayment(
          _payment('pay-${method.wire}', method: method),
        );
        expect(outcome, PosCashDrawerOutcome.nonCashSkip);
      }
      expect(connector.sent, isEmpty);
    });

    test('ON + cash => sent: exactly one pulse with the exact byte '
        'sequence and no raster bytes', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final c = _serviceContainer(connector);

      final outcome = await c
          .read(posCashDrawerServiceProvider)
          .kickForPayment(_payment('pay-1'));

      expect(outcome, PosCashDrawerOutcome.sent);
      expect(connector.sent, hasLength(1));
      expect(connector.sent.single, orderedEquals(_kickBytes));
      expect(
        _containsSequence(connector.sent.single, _rasterHeader),
        isFalse,
        reason: 'a kick never passes through the rasterizer (GS v 0)',
      );
    });

    test(
      'same paymentId twice in one container => 1 send + duplicateSkip',
      () async {
        SharedPreferences.setMockInitialValues(_printerPrefs());
        final connector = _RecordingConnector();
        final c = _serviceContainer(connector);
        final service = c.read(posCashDrawerServiceProvider);

        expect(
          await service.kickForPayment(_payment('pay-dup')),
          PosCashDrawerOutcome.sent,
        );
        expect(
          await service.kickForPayment(_payment('pay-dup')),
          PosCashDrawerOutcome.duplicateSkip,
        );
        expect(connector.sent, hasLength(1));
      },
    );

    test('a NEW container over the SAME prefs never kicks the same payment '
        'again (durable claim, not memory dedupe)', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final c1 = _serviceContainer(connector);
      expect(
        await c1
            .read(posCashDrawerServiceProvider)
            .kickForPayment(_payment('pay-durable')),
        PosCashDrawerOutcome.sent,
      );

      // Provider recreation = process restart over the same durable store.
      final c2 = _serviceContainer(connector);
      expect(
        await c2
            .read(posCashDrawerServiceProvider)
            .kickForPayment(_payment('pay-durable')),
        PosCashDrawerOutcome.duplicateSkip,
      );
      expect(connector.sent, hasLength(1), reason: 'no second pulse, ever');
    });

    test(
      'no printer configured => noPrinterSkip and NO claim burned',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          _settingKey: true,
        });
        final connector = _RecordingConnector();
        final c = _serviceContainer(connector);

        final outcome = await c
            .read(posCashDrawerServiceProvider)
            .kickForPayment(_payment('pay-nop'));

        expect(outcome, PosCashDrawerOutcome.noPrinterSkip);
        expect(connector.sent, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_claimsKey), isNull);
      },
    );

    test('profile without drawer support => unsupportedSkip and zero pulse '
        'bytes', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final sends = <Uint8List>[];
      final unsupported = NativeTransportPrintBridge(
        profile: const pp.PrinterProfile(
          paperWidth: pp.PaperWidth.mm80,
          columns: 48,
          capabilities: pp.PrinterCapabilities(supportsDrawerKick: false),
        ),
        transportFactory: () => _RecordingTransport(sends),
      );
      final c = _serviceContainer(
        connector,
        extra: <Override>[
          posActivePrintBridgeReadyProvider.overrideWith(
            (ref) async => unsupported,
          ),
        ],
      );

      final outcome = await c
          .read(posCashDrawerServiceProvider)
          .kickForPayment(_payment('pay-unsup'));

      expect(outcome, PosCashDrawerOutcome.unsupportedSkip);
      expect(sends, isEmpty);
      expect(connector.sent, isEmpty);
    });

    test('missing scope => refused, nothing sent, nothing claimed', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final c = _serviceContainer(connector, scope: null);

      final outcome = await c
          .read(posCashDrawerServiceProvider)
          .kickForPayment(_payment('pay-noscope'));

      expect(outcome, PosCashDrawerOutcome.refused);
      expect(connector.sent, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_claimsKey), isNull);
    });

    test('no PIN session (unauthorized) => refused (R-007)', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final c = _serviceContainer(connector, session: null);

      final outcome = await c
          .read(posCashDrawerServiceProvider)
          .kickForPayment(_payment('pay-noauth'));

      expect(outcome, PosCashDrawerOutcome.refused);
      expect(connector.sent, isEmpty);
    });

    test('claim persist failure => claimPersistFailed and NO kick (missed '
        'open is safer than a double open)', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final c = _serviceContainer(
        connector,
        extra: <Override>[
          posCashDrawerClaimStoreProvider.overrideWithValue(
            PosCashDrawerClaimStore(
              prefs: () async => throw Exception('durable store down'),
            ),
          ),
        ],
      );

      final outcome = await c
          .read(posCashDrawerServiceProvider)
          .kickForPayment(_payment('pay-nostore'));

      expect(outcome, PosCashDrawerOutcome.claimPersistFailed);
      expect(connector.sent, isEmpty);
    });

    test('transport failure => sendFailed, ONE attempt, claim retained so '
        'no later path can re-pulse', () async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector(
        result: const pp.PrintResult.failure(
          pp.PrinterErrorCategory.unreachable,
        ),
      );
      final c = _serviceContainer(connector);
      final service = c.read(posCashDrawerServiceProvider);

      expect(
        await service.kickForPayment(_payment('pay-fail')),
        PosCashDrawerOutcome.sendFailed,
      );
      expect(connector.sent, hasLength(1), reason: 'no retry anywhere');

      // Even after the printer recovers, the SAME payment never re-pulses:
      // the claim was written before the send and is never removed.
      connector.result = const pp.PrintResult.success();
      expect(
        await service.kickForPayment(_payment('pay-fail')),
        PosCashDrawerOutcome.duplicateSkip,
      );
      expect(connector.sent, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  // Claim store unit behaviour
  // -------------------------------------------------------------------------
  group('claim store', () {
    test('envelope shape: v1, drawer:<paymentId> ids, newest first, bounded '
        'to 200', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final store = PosCashDrawerClaimStore();

      for (var i = 0; i < kPosCashDrawerClaimsLimit; i++) {
        expect(
          await store.claim(deviceSegment: 'dev-1', paymentId: 'p$i'),
          PosCashDrawerClaimResult.claimed,
        );
      }
      expect(
        await store.claim(deviceSegment: 'dev-1', paymentId: 'p-newest'),
        PosCashDrawerClaimResult.claimed,
      );

      final prefs = await SharedPreferences.getInstance();
      final envelope =
          jsonDecode(prefs.getString(_claimsKey)!) as Map<String, Object?>;
      expect(envelope['v'], kPosCashDrawerClaimsSchemaVersion);
      final claims = (envelope['claims'] as List).cast<Map>();
      expect(claims, hasLength(kPosCashDrawerClaimsLimit));
      expect(claims.first['id'], 'drawer:p-newest');
      expect(DateTime.tryParse('${claims.first['at']}'), isNotNull);
      // The OLDEST claim was pruned; the most recent ones are all retained —
      // a very recent payment can never be evicted (200 newer payments would
      // have to happen first).
      expect(claims.any((c) => c['id'] == 'drawer:p0'), isFalse);
      expect(claims.any((c) => c['id'] == 'drawer:p199'), isTrue);

      // Duplicates are still detected after the prune boundary.
      expect(
        await store.claim(deviceSegment: 'dev-1', paymentId: 'p-newest'),
        PosCashDrawerClaimResult.duplicate,
      );
    });

    test('an UNREADABLE envelope refuses to kick and preserves the bytes '
        'verbatim', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _claimsKey: 'not json {{{',
      });
      final store = PosCashDrawerClaimStore();

      expect(
        await store.claim(deviceSegment: 'dev-1', paymentId: 'p-x'),
        PosCashDrawerClaimResult.persistFailed,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(_claimsKey),
        'not json {{{',
        reason: 'dedupe evidence is never destroyed by a failed read',
      );
    });

    test('an unavailable durable store refuses to kick', () async {
      final store = PosCashDrawerClaimStore(
        prefs: () async => throw Exception('no store'),
      );
      expect(
        await store.claim(deviceSegment: 'dev-1', paymentId: 'p-y'),
        PosCashDrawerClaimResult.persistFailed,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Claim serialization (PR #205 review F1/N4): the store upholds its OWN
  // at-most-once invariant — no reliance on the payment sheet's latch.
  // -------------------------------------------------------------------------
  group('claim store serialization', () {
    test('concurrent SAME-id claims: exactly one claimed, one duplicate, '
        'envelope holds the claim once', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      // Gate the prefs resolution so BOTH claims are definitely in flight
      // before either can read — the exact interleaving that double-kicked
      // before serialization.
      final gate = Completer<void>();
      var calls = 0;
      final store = PosCashDrawerClaimStore(
        prefs: () async {
          calls++;
          await gate.future;
          return SharedPreferences.getInstance();
        },
      );

      final first = store.claim(deviceSegment: 'dev-1', paymentId: 'p-race');
      final second = store.claim(deviceSegment: 'dev-1', paymentId: 'p-race');
      gate.complete();
      final results = await Future.wait(<Future<PosCashDrawerClaimResult>>[
        first,
        second,
      ]);

      expect(
        results.where((r) => r == PosCashDrawerClaimResult.claimed),
        hasLength(1),
        reason: 'a cash drawer may open at most once per payment',
      );
      expect(
        results.where((r) => r == PosCashDrawerClaimResult.duplicate),
        hasLength(1),
      );
      final prefs = await SharedPreferences.getInstance();
      final claims =
          ((jsonDecode(prefs.getString(_claimsKey)!) as Map)['claims'] as List)
              .cast<Map>();
      expect(claims.where((c) => c['id'] == 'drawer:p-race'), hasLength(1));
      expect(calls, 2, reason: 'both operations genuinely ran');
    });

    test('concurrent DIFFERENT-id claims: both claimed, both survive '
        '(no lost update)', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final gate = Completer<void>();
      final store = PosCashDrawerClaimStore(
        prefs: () async {
          await gate.future;
          return SharedPreferences.getInstance();
        },
      );

      final a = store.claim(deviceSegment: 'dev-1', paymentId: 'p-a');
      final b = store.claim(deviceSegment: 'dev-1', paymentId: 'p-b');
      gate.complete();
      expect(await Future.wait(<Future<PosCashDrawerClaimResult>>[a, b]), [
        PosCashDrawerClaimResult.claimed,
        PosCashDrawerClaimResult.claimed,
      ]);

      // A FRESH store over the same prefs sees BOTH claims — the second
      // write did not clobber the first (last-writer-wins is impossible
      // under the serial chain).
      final reread = PosCashDrawerClaimStore();
      expect(
        await reread.claim(deviceSegment: 'dev-1', paymentId: 'p-a'),
        PosCashDrawerClaimResult.duplicate,
      );
      expect(
        await reread.claim(deviceSegment: 'dev-1', paymentId: 'p-b'),
        PosCashDrawerClaimResult.duplicate,
      );
    });

    test('a failed operation does NOT poison the serial chain', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      var shouldThrow = true;
      final store = PosCashDrawerClaimStore(
        prefs: () async {
          if (shouldThrow) throw Exception('store offline');
          return SharedPreferences.getInstance();
        },
      );

      expect(
        await store.claim(deviceSegment: 'dev-1', paymentId: 'p-fail'),
        PosCashDrawerClaimResult.persistFailed,
      );
      shouldThrow = false;
      expect(
        await store.claim(deviceSegment: 'dev-1', paymentId: 'p-after'),
        PosCashDrawerClaimResult.claimed,
        reason: 'the chain must keep serving after one failed operation',
      );
    });
  });

  // -------------------------------------------------------------------------
  // C. Bridge seam bytes + send gate
  // -------------------------------------------------------------------------
  group('C. bridge seam', () {
    test('submitDrawerKick emits exactly init + codepage + ESC p 0 25 25 '
        'through the transport', () async {
      final sends = <Uint8List>[];
      final bridge = NativeTransportPrintBridge(
        transportFactory: () => _RecordingTransport(sends),
      );

      final result = await bridge.submitDrawerKick();

      expect(result, isNotNull);
      expect(result!.ok, isTrue);
      expect(sends, hasLength(1));
      expect(sends.single, orderedEquals(_kickBytes));
      expect(_containsSequence(sends.single, _rasterHeader), isFalse);
    });

    test('supportsDrawerKick=false returns the typed null skip and never '
        'builds a transport', () async {
      var built = 0;
      final bridge = NativeTransportPrintBridge(
        profile: const pp.PrinterProfile(
          paperWidth: pp.PaperWidth.mm80,
          columns: 48,
          capabilities: pp.PrinterCapabilities(supportsDrawerKick: false),
        ),
        transportFactory: () {
          built++;
          return _RecordingTransport(<Uint8List>[]);
        },
      );

      expect(await bridge.submitDrawerKick(), isNull);
      expect(built, 0);
    });

    test('the kick serializes through the SAME per-destination send gate as '
        'a receipt send', () async {
      final gate = pp.PrinterDestinationSendGate();
      final events = <String>[];
      final firstSendGate = Completer<void>();
      var sendIndex = 0;
      final bridge = NativeTransportPrintBridge(
        sendGate: gate,
        destinationKey: pp.PrinterDestinationSendGate.bluetoothKey('AA:BB'),
        transportFactory: () => _GatedTransport(events, () async {
          // Only the FIRST physical send (the receipt) blocks.
          if (sendIndex++ == 0) await firstSendGate.future;
        }),
      );

      final receipt = bridge.submit(_receiptDocument());
      // Give the receipt send time to enter the gate.
      await Future<void>.delayed(Duration.zero);
      final kick = bridge.submitDrawerKick();
      await Future<void>.delayed(Duration.zero);

      expect(events, contains('start'));
      expect(
        events.where((e) => e == 'start'),
        hasLength(1),
        reason: 'the kick must WAIT behind the in-flight receipt send',
      );

      firstSendGate.complete();
      await receipt;
      await kick;
      expect(events, <String>['start', 'end', 'start', 'end']);
    });
  });

  // -------------------------------------------------------------------------
  // D. The ONE call site (CashPaymentSheet)
  // -------------------------------------------------------------------------
  group('D. payment call site', () {
    testWidgets('cash payment with the drawer ON pulses EXACTLY once through '
        'the single sanctioned entry (CashPaymentSheet)', (tester) async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final container = await _pumpRealModeSheet(tester, connector: connector);

      await _confirmSheet(tester);

      expect(_pulseSendCount(connector.sent), 1);
      expect(
        container
            .read(paymentControllerProvider.notifier)
            .paymentFor(_identity),
        isNotNull,
      );
      // Every skip/success is SILENT — no drawer snackbar on success.
      final l10n = await _en();
      expect(find.text(l10n.posCashDrawerOpenFailed), findsNothing);
    });

    testWidgets('re-opening the SAME order for payment (the Orders-surface '
        'retry shape) still yields exactly one pulse overall', (tester) async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      await _pumpRealModeSheet(tester, connector: connector);

      await _confirmSheet(tester);
      expect(_pulseSendCount(connector.sent), 1);

      // A cashier re-opening the sheet cannot double-pay in production (the
      // row shows paid) — but even if a payment for the SAME id were replayed
      // at the service, the durable claim holds the line (group B). Here we
      // re-open the ENTRY and close it: still one pulse.
      await tester.tap(find.byKey(const Key('open-pay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-payment-button')), findsOneWidget);
      await tester.tapAt(const Offset(600, 100)); // barrier-dismiss
      await tester.pumpAndSettle();

      expect(_pulseSendCount(connector.sent), 1);
    });

    testWidgets('setting OFF => zero pulses', (tester) async {
      SharedPreferences.setMockInitialValues(_printerPrefs(settingOn: false));
      final connector = _RecordingConnector();
      await _pumpRealModeSheet(tester, connector: connector);

      await _confirmSheet(tester);

      expect(_pulseSendCount(connector.sent), 0);
    });

    testWidgets('non-cash tender => zero pulses', (tester) async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      await _pumpRealModeSheet(tester, connector: connector);

      await tester.tap(find.byKey(const Key('tender-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-payment-button')));
      await tester.pumpAndSettle();

      expect(_pulseSendCount(connector.sent), 0);
    });

    testWidgets('a FAILED payment never kicks', (tester) async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      await _pumpRealModeSheet(
        tester,
        connector: connector,
        repo: _ThrowingRepo(),
      );

      await _confirmSheet(tester);

      expect(_pulseSendCount(connector.sent), 0);
      expect(find.byKey(const Key('payment-failed-banner')), findsOneWidget);
    });

    testWidgets('double-tapping Confirm records ONE payment and ONE kick', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final repo = _CountingRepo(DemoPaymentStore());
      final container = await _pumpRealModeSheet(
        tester,
        connector: connector,
        repo: repo,
      );

      await tester.enterText(find.byType(TextField).first, '54.00');
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm-payment-button')));
      await tester.tap(
        find.byKey(const Key('confirm-payment-button')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(repo.records, 1, reason: 'the submit guard holds');
      expect(_pulseSendCount(connector.sent), 1);
      expect(container.read(paymentControllerProvider).payments, hasLength(1));
    });

    testWidgets('payment success + kick sendFailed => payment kept, receipt '
        'untouched, and the ONE honest snackbar', (tester) async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector(
        result: const pp.PrintResult.failure(
          pp.PrinterErrorCategory.unreachable,
        ),
      );
      final container = await _pumpRealModeSheet(tester, connector: connector);

      await _confirmSheet(tester);

      final l10n = await _en();
      expect(find.text(l10n.posCashDrawerOpenFailed), findsOneWidget);
      expect(
        container
            .read(paymentControllerProvider.notifier)
            .paymentFor(_identity),
        isNotNull,
        reason: 'a drawer problem is never a payment problem',
      );
      expect(connector.sent, hasLength(1), reason: 'one attempt, no retry');
    });

    testWidgets('manual bill reprint after payment sends receipt bytes with '
        'NO pulse (reprint paths never kick)', (tester) async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final container = await _pumpRealModeSheet(tester, connector: connector);

      await _confirmSheet(tester);
      expect(_pulseSendCount(connector.sent), 1);

      // EXACTLY what the Orders reprint action runs.
      final l10n = await _en();
      await container
          .read(receiptPrintControllerProvider.notifier)
          .requestRepeatableDocument(
            orderKey: 'bill:${_identity.key}',
            resolveReadiness: container.read(
              posReceiptReadinessResolverProvider,
            ),
            awaitLogoReady: () => container
                .read(posReceiptLogoAssetProvider.notifier)
                .firstResolution,
            buildDocument: () => buildBillDocument(l10n, _order, isDemo: false),
            resolveBridge: () async => (await container.read(
              posActivePrintBridgeReadyProvider.future,
            ))?.submit,
          );
      await tester.pumpAndSettle();

      expect(connector.sent.length, greaterThan(1), reason: 'bill printed');
      expect(
        _pulseSendCount(connector.sent),
        1,
        reason: 'the reprint added receipt bytes but never a second pulse',
      );
    });

    testWidgets('rebuild/hydration after payment never re-kicks', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      final container = await _pumpRealModeSheet(tester, connector: connector);

      await _confirmSheet(tester);
      // Rebuild the tree and re-read the providers, as a refresh would.
      await tester.pump();
      container.read(receiptPrintControllerProvider);
      container.read(paymentControllerProvider);
      await tester.pumpAndSettle();

      expect(_pulseSendCount(connector.sent), 1);
    });

    testWidgets('the DEMO cart flow (PosMenuScreen) fires the call site once '
        'per cash payment and the real service demo-skips: no pulse bytes, '
        'no snackbar, receipt unchanged', (tester) async {
      SharedPreferences.setMockInitialValues(_printerPrefs());
      final connector = _RecordingConnector();
      late _RecordingDrawerService recorder;
      final container = ProviderContainer(
        overrides: <Override>[
          posNativePrintingAvailableProvider.overrideWithValue(true),
          nativePrinterNamespaceProvider.overrideWithValue('pos'),
          bluetoothPrinterConnectorProvider.overrideWithValue(connector),
          posCashDrawerServiceProvider.overrideWith((ref) {
            recorder = _RecordingDrawerService(ref);
            return recorder;
          }),
        ],
      );
      addTearDown(container.dispose);
      final l10n = await _en();
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const PosMenuScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Add an item, send the order, pay cash exactly — the full cart flow.
      await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.posSendOrder));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay-cash-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-cash-exact')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-payment-button')));
      await tester.pumpAndSettle();

      // The ONE call site fired once, with the recorded cash payment.
      // (That the REAL service answers demoSkip for a demo till is proven in
      // group B; here the recorder proves the EDGE fires exactly once.)
      expect(recorder.calls, hasLength(1));
      expect(recorder.calls.single.method, PaymentMethod.cash);
      expect(_pulseSendCount(connector.sent), 0);
      expect(find.text(l10n.posCashDrawerOpenFailed), findsNothing);
      expect(find.byKey(const Key('receipt-preview-card')), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// D fixtures
// ---------------------------------------------------------------------------

final PosOrderIdentity _identity = PosOrderIdentity.server('oid-DRW1');

const SubmittedOrderView _order = SubmittedOrderView(
  orderNumber: '#DRW1',
  orderType: OrderType.dineIn,
  tableLabel: 'T7',
  currencyCode: 'ILS',
  subtotalMinor: 5400,
  orderId: 'oid-DRW1',
  lines: <SubmittedLineView>[
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 1,
      lineTotalMinor: 5400,
      currencyCode: 'ILS',
    ),
  ],
);

class _ThrowingRepo implements PaymentRepository {
  final DemoPaymentStore _inner = DemoPaymentStore();

  @override
  ShiftContext shiftContext() => _inner.shiftContext();

  @override
  CashPayment? paymentFor(PosOrderIdentity identity) => null;

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async => throw const PaymentException('network down');
}

class _CountingRepo implements PaymentRepository {
  _CountingRepo(this._inner);

  final PaymentRepository _inner;
  int records = 0;

  @override
  ShiftContext shiftContext() => _inner.shiftContext();

  @override
  CashPayment? paymentFor(PosOrderIdentity identity) =>
      _inner.paymentFor(identity);

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) {
    records++;
    return _inner.recordCashPayment(
      orderId: orderId,
      orderNumber: orderNumber,
      amountMinor: amountMinor,
      tenderedMinor: tenderedMinor,
      currencyCode: currencyCode,
      method: method,
      expectedRevision: expectedRevision,
    );
  }
}

/// Records the call-site invocations without touching any gate/hardware —
/// used ONLY to prove the [CashPaymentSheet] edge fires exactly once per
/// successful payment; all gating behaviour is tested on the REAL service.
class _RecordingDrawerService extends PosCashDrawerService {
  _RecordingDrawerService(super.ref);

  final List<CashPayment> calls = <CashPayment>[];

  @override
  Future<PosCashDrawerOutcome> kickForPayment(CashPayment payment) async {
    calls.add(payment);
    return PosCashDrawerOutcome.sent;
  }
}

/// REAL mode (demo would demoSkip by design) with the real drawer service and
/// scope/session overrides; payment goes through an in-memory repository. The
/// automatic paid RECEIPT deliberately cannot print in this fixture (the real
/// order-detail repository has no transport and fails soft), so every pulse
/// assertion is crisp — and it doubles as proof the drawer is INDEPENDENT of
/// the receipt outcome.
ProviderContainer _realModeContainer(
  _RecordingConnector connector, {
  PaymentRepository? repo,
}) {
  final container = ProviderContainer(
    overrides: <Override>[
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posSyncScopeProvider.overrideWithValue(_scope),
      posSyncSessionProvider.overrideWithValue(_session),
      posNativePrintingAvailableProvider.overrideWithValue(true),
      nativePrinterNamespaceProvider.overrideWithValue('pos'),
      bluetoothPrinterConnectorProvider.overrideWithValue(connector),
      paymentRepositoryProvider.overrideWithValue(repo ?? DemoPaymentStore()),
    ],
  );
  container
      .read(posRecentOrdersControllerProvider.notifier)
      .recordSubmitted(_order);
  return container;
}

/// Pumps a host Scaffold and opens the payment sheet through
/// [CashPaymentSheet.show] — PRODUCTION-FAITHFUL: `show` is the single
/// sanctioned entry BOTH surfaces converge on (the checkout confirmation at
/// order_confirmation.dart and the Orders "Receive payment" action at
/// order_action_row.dart), and presenting it modally keeps the host Scaffold
/// alive after the sheet pops, exactly like the real POS — which is what lets
/// the sendFailed snackbar actually render.
Future<ProviderContainer> _pumpRealModeSheet(
  WidgetTester tester, {
  required _RecordingConnector connector,
  PaymentRepository? repo,
}) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = _realModeContainer(connector, repo: repo);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const Key('open-pay'),
                onPressed: () => CashPaymentSheet.show(
                  context,
                  identity: _identity,
                  orderNumber: '#DRW1',
                  amountMinor: 5400,
                  currencyCode: 'ILS',
                  orderId: 'oid-DRW1',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-pay')));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _confirmSheet(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '54.00');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-payment-button')));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// C fixtures
// ---------------------------------------------------------------------------

class _RecordingTransport implements pp.PrintTransport {
  _RecordingTransport(this.sends);

  final List<Uint8List> sends;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sends.add(bytes);
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

class _GatedTransport implements pp.PrintTransport {
  _GatedTransport(this.events, this.beforeFinish);

  final List<String> events;
  final Future<void> Function() beforeFinish;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    events.add('start');
    await beforeFinish();
    events.add('end');
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

app_receipt.PrintDocument _receiptDocument() => app_receipt.PrintDocument(
  title: 'r',
  lines: <app_receipt.PrintLine>[app_receipt.PrintLine.kv('Total', '42.00')],
);
