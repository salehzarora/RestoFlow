@TestOn('vm')
library;

import 'dart:convert' show jsonEncode, utf8;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show KitchenAckAccepted, KitchenImportAckStatus;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show
        KitchenChangeSlipLabels,
        OrderChangeAdded,
        OrderChangeQuantity,
        OrderChangeSlipView,
        kitchenChangeSlipLabelsForLanguageCode,
        kitchenTicketPrintLabelsForLanguageCode;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView;
import 'package:restoflow_pos/main.dart' show PosBootCoordinator;
import 'package:restoflow_pos/src/print/kitchen_ticket_render.dart'
    show renderOrderChangeSlipBytes;
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_kitchen_dispatch_ack.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart'
    show posRestaurantNameProvider;
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show nativePrintRasterizerProvider;
import 'package:shared_preferences/shared_preferences.dart';

/// ORDER-EDIT-001F — the seams the direct change-slip print rests on:
///  * [PosKitchenTicketPrinter.printChangeSlip] sends the SAME bytes
///    `renderOrderChangeSlipBytes` encodes (the spool's encoder too) through
///    the kitchen slot, its media profile, the restaurant name and the shared
///    gate, with the ticket path's honest outcomes;
///  * the printer is drivable through any provider reader — a controller's
///    `ref.read` as well as a container's `read`;
///  * the device's AUTOMATIC kitchen-print toggle never gates a slip (D12);
///  * the typed acknowledgement client is a device seam (null by default).

class _FakeTransport implements pp.PrintTransport {
  _FakeTransport(this._result);
  final pp.PrintResult _result;
  final List<Uint8List> sent = [];
  bool disposed = false;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return _result;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _StubAutoKitchen extends PosAutoPrintKitchenTicketController {
  _StubAutoKitchen(this._value);
  final bool? _value;
  @override
  Future<bool?> build() async => _value;
}

final _slip = OrderChangeSlipView(
  orderCode: '#00A001',
  editNumber: 1,
  orderType: 'dine_in',
  tableLabel: 'T4',
  staffFirstName: 'Dana',
  reasonCode: 'entry_mistake',
  editedAt: DateTime.utc(2026, 10, 9, 11, 58).toLocal(),
  changes: const [
    OrderChangeQuantity(
      was: KdsItemView(name: 'Cola', quantity: 3),
      nowQuantity: 1,
    ),
    OrderChangeAdded([KdsItemView(name: 'Water', quantity: 1, note: 'no ice')]),
  ],
  orderNow: const [
    KdsItemView(name: 'Cola', quantity: 1, linePosition: 1),
    KdsItemView(name: 'Water', quantity: 1, note: 'no ice', linePosition: 2),
  ],
);

final _labels = kitchenTicketPrintLabelsForLanguageCode('en');
final KitchenChangeSlipLabels _changeLabels =
    kitchenChangeSlipLabelsForLanguageCode('en');

ProviderContainer _container({
  bool nativeAvailable = true,
  List<Override> overrides = const [],
}) {
  final c = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(nativeAvailable),
      // The brand header the slip shares with the ticket.
      posRestaurantNameProvider.overrideWithValue('Slip Parity'),
      ...overrides,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

ResolvedKitchenPrinter _target(pp.PrintTransport transport) =>
    ResolvedKitchenPrinter(
      destinationKey: 'k',
      transportFactory: () => transport,
    );

/// The bytes the shared encoder produces for [_slip] with the reads the
/// printer makes from [c].
Future<Uint8List> _expectedBytes(
  ProviderContainer c, {
  pp.MediaProfile media = pp.MediaProfile.continuous80,
}) => renderOrderChangeSlipBytes(
  slip: _slip,
  labels: _labels,
  changeLabels: _changeLabels,
  rasterizer: c.read(nativePrintRasterizerProvider),
  mediaProfile: media,
  restaurantName: c.read(posRestaurantNameProvider),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('printChangeSlip', () {
    test('sends exactly the shared encoder\'s bytes for the kitchen slot\'s '
        'media, once, and disposes the socket', () async {
      final c = _container();
      final fake = _FakeTransport(const pp.PrintResult.success());
      final outcome =
          await PosKitchenTicketPrinter(
            c,
            targetOverride: _target(fake),
          ).printChangeSlip(
            slip: _slip,
            labels: _labels,
            changeLabels: _changeLabels,
          );
      expect(outcome, PosKitchenPrintOutcome.printed);
      expect(fake.sent, hasLength(1));
      expect(fake.sent.single, await _expectedBytes(c));
      expect(fake.disposed, isTrue);
      final text = utf8.decode(fake.sent.single, allowMalformed: true);
      expect(text, contains('#00A001'));
      expect(text, contains('Slip Parity'));
      for (final token in ['price', 'subtotal', 'tax', 'payment', '₪']) {
        expect(text.toLowerCase(), isNot(contains(token)));
      }
    });

    test(
      'drivable through a provider REF (a controller passes ref.read)',
      () async {
        final fake = _FakeTransport(const pp.PrintResult.success());
        final viaRef = Provider<Future<PosKitchenPrintOutcome>>(
          (ref) =>
              PosKitchenTicketPrinter.withReader(
                ref.read,
                targetOverride: _target(fake),
              ).printChangeSlip(
                slip: _slip,
                labels: _labels,
                changeLabels: _changeLabels,
              ),
        );
        final c = _container();
        expect(await c.read(viaRef), PosKitchenPrintOutcome.printed);
        expect(fake.sent.single, await _expectedBytes(c));
      },
    );

    test(
      'resolves the KITCHEN slot through the reader (network config)',
      () async {
        SharedPreferences.setMockInitialValues({
          'restoflow.printer.selected.pos.kitchen_ticket.local': 'network',
          'restoflow.printer.network.pos.kitchen_ticket.local': jsonEncode({
            'host': '10.0.0.9',
            'port': 9100,
          }),
        });
        final fake = _FakeTransport(const pp.PrintResult.success());
        ResolvedKitchenPrinter? routed;
        final c = _container(
          overrides: [
            kitchenPrintTransportOverrideProvider.overrideWithValue((target) {
              routed = target;
              return fake;
            }),
          ],
        );
        final outcome = await c.read(posOrderEditSlipPrintProvider)(
          read: c.read,
          slip: _slip,
          labels: _labels,
          changeLabels: _changeLabels,
        );
        expect(outcome, PosKitchenPrintOutcome.printed);
        expect(
          routed!.destinationKey,
          pp.PrinterDestinationSendGate.networkKey('10.0.0.9', 9100),
        );
        expect(
          fake.sent.single,
          await _expectedBytes(c, media: routed!.mediaProfile),
        );
      },
    );

    test(
      'the automatic kitchen-print toggle never gates a slip (D12)',
      () async {
        final fake = _FakeTransport(const pp.PrintResult.success());
        final c = _container(
          overrides: [
            posAutoPrintKitchenTicketProvider.overrideWith(
              () => _StubAutoKitchen(false),
            ),
          ],
        );
        expect(
          await PosKitchenTicketPrinter(
            c,
            targetOverride: _target(fake),
          ).printChangeSlip(
            slip: _slip,
            labels: _labels,
            changeLabels: _changeLabels,
          ),
          PosKitchenPrintOutcome.printed,
        );
        expect(fake.sent, hasLength(1));
      },
    );

    test('honest outcomes: unavailable, no printer, render failure, refused '
        'send — and nothing is sent unless it can be', () async {
      final fake = _FakeTransport(const pp.PrintResult.success());
      expect(
        await PosKitchenTicketPrinter(
          _container(nativeAvailable: false),
          targetOverride: _target(fake),
        ).printChangeSlip(
          slip: _slip,
          labels: _labels,
          changeLabels: _changeLabels,
        ),
        PosKitchenPrintOutcome.unavailable,
      );
      expect(
        await PosKitchenTicketPrinter(_container()).printChangeSlip(
          slip: _slip,
          labels: _labels,
          changeLabels: _changeLabels,
        ),
        PosKitchenPrintOutcome.noPrinterConfigured,
      );
      expect(
        await PosKitchenTicketPrinter(
          _container(),
          targetOverride: _target(fake),
          buildSlipBytes:
              ({
                required slip,
                required labels,
                required changeLabels,
                rasterizer,
                mediaProfile,
                restaurantName,
              }) async => throw StateError('render'),
        ).printChangeSlip(
          slip: _slip,
          labels: _labels,
          changeLabels: _changeLabels,
        ),
        PosKitchenPrintOutcome.failed,
      );
      expect(fake.sent, isEmpty);

      final refused = _FakeTransport(
        const pp.PrintResult.failure(pp.PrinterErrorCategory.unreachable),
      );
      expect(
        await PosKitchenTicketPrinter(
          _container(),
          targetOverride: _target(refused),
        ).printChangeSlip(
          slip: _slip,
          labels: _labels,
          changeLabels: _changeLabels,
        ),
        PosKitchenPrintOutcome.failed,
      );
      expect(refused.sent, hasLength(1));
      expect(refused.disposed, isTrue);
    });

    test('the ticket path is unchanged by the shared send', () async {
      final c = _container();
      final fake = _FakeTransport(const pp.PrintResult.success());
      final printer = PosKitchenTicketPrinter(c, targetOverride: _target(fake));
      expect(
        await printer.printChangeSlip(
          slip: _slip,
          labels: _labels,
          changeLabels: _changeLabels,
        ),
        PosKitchenPrintOutcome.printed,
      );
      // A slip builder is never used for a ticket and vice versa.
      var slipBuilds = 0;
      final counting = PosKitchenTicketPrinter(
        c,
        targetOverride: _target(fake),
        buildSlipBytes:
            ({
              required slip,
              required labels,
              required changeLabels,
              rasterizer,
              mediaProfile,
              restaurantName,
            }) async {
              slipBuilds++;
              return Uint8List(0);
            },
      );
      await counting.printChangeSlip(
        slip: _slip,
        labels: _labels,
        changeLabels: _changeLabels,
      );
      expect(slipBuilds, 1);
    });
  });

  group('the acknowledgement seam', () {
    test('null by default: demo mode and tests acknowledge nothing', () {
      expect(_container().read(posKitchenDispatchAckProvider), isNull);
    });

    test(
      'the device seams carry a typed client on the boot transport',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final calls = <Map<String, dynamic>>[];
        final transport = _RecordingTransport(calls);
        final store = InMemoryDeviceSessionSecretStore();
        await store.write(
          const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'tok'),
        );
        final boot = await PosBootCoordinator(
          prefs: prefs,
          demoMode: false,
          secretStore: store,
          createSession: () async => (
            transport: transport,
            imageUrlResolver: FakeDeviceImageUrlResolver(),
            receiptLogoReader: const _NoLogo(),
            invalidationSourceFactory: (_) =>
                const DisabledInvalidationSource(),
          ),
        ).bootstrap();
        final ack = boot.seams!.kitchenDispatchAck!;
        final result = await ack.acknowledge(
          dispatchId: 'dispatch-1',
          status: KitchenImportAckStatus.transportAccepted,
        );
        expect(result, isA<KitchenAckAccepted>());
        expect(calls.single['p_dispatch_id'], 'dispatch-1');
        expect(calls.single['p_client_status'], 'transport_accepted');
        expect(calls.single['p_device_id'], 'dev-1');
      },
    );
  });
}

class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this.calls);
  final List<Map<String, dynamic>> calls;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add(params);
    return {'ok': true, 'idempotency_replay': false, 'completed': true};
  }
}

class _NoLogo implements DeviceReceiptLogoReader {
  const _NoLogo();
  @override
  Future<ReceiptLogoBytes?> load(String objectPath) async => null;
}
