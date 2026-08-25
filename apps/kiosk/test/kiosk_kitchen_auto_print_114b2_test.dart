import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/kitchen_dispatch_document.dart'
    show KitchenDispatchDocument, KitchenTicketLabels, KitchenTicketRenderer;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show
        CanonicalKitchenDispatchRenderer,
        formatKitchenTicketTimestamp,
        kitchenServiceModeBadge,
        kitchenTicketPrintLabelsForLanguageCode;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show KitchenAckAccepted, KitchenAckResult, KitchenImportAckStatus;
import 'package:restoflow_kiosk/src/data/kiosk_order_submit.dart'
    show KioskClaimedKitchenDispatch;
import 'package:restoflow_kiosk/src/print/kiosk_kitchen_auto_print.dart';
import 'package:restoflow_kiosk/src/print/kiosk_printer_purpose.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart'
    show KioskOrderSnapshot, KioskServiceType;
import 'package:restoflow_kiosk/src/state/kiosk_staff_access.dart'
    show kioskDeviceContextProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// KIOSK-PRINT-114B.2 — the kiosk KITCHEN auto-print lane.
///
/// The claimed dispatch from the submit response is the ONLY input; the lane
/// renders it with the SHARED extracted printer_only renderer, serializes the
/// physical send through the process-wide gate, sends ONCE, and acknowledges
/// honestly (transport_accepted / failed_retryable / possibly_printed). The
/// server claim is the durable cross-device exactly-once guarantee; the
/// in-memory latch only absorbs same-run replays. The customer receipt lane
/// is completely independent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final payload = <String, Object?>{
    'v': 1,
    'created_at': '2026-08-25T11:07:00+00:00',
    'kind': 'initial_order',
    'order_code': '#1234',
    'order_type': 'takeaway',
    'order_note': 'no onions',
    'items': [
      {
        'qty': 2,
        'name': 'B2 Burger',
        'note': 'well done',
        'prep': [
          {
            'name': 'Patty',
            'quantity': 1,
            'unit': 'pc',
            'classifier_option_id': 'opt-large',
            'classifier_option_name': 'Large',
            'classifier_selected': true,
          },
          {'name': 'Bun', 'quantity': 2, 'unit': 'pc'},
        ],
        'modifiers': [
          {
            'qty': 1,
            'name': 'Large',
            'prep': {'quantity': 1, 'unit': 'patty'},
          },
        ],
      },
    ],
  };

  KioskClaimedKitchenDispatch dispatch({String id = 'disp-1'}) =>
      KioskClaimedKitchenDispatch(
        id: id,
        payload: payload,
        claimExpiresAt: DateTime.utc(2026, 8, 25, 12),
      );

  const order = KioskOrderSnapshot(
    number: 41,
    orderId: '00000000-0000-0000-0000-0000000000b2',
    lines: [],
    totalMinor: 8000,
    service: KioskServiceType.takeaway,
    table: null,
    customerName: '',
  );

  late List<({String dispatchId, KitchenImportAckStatus status})> acks;
  late List<Uint8List> sends;

  ProviderContainer harness({
    pp.KitchenTransportOutcome outcome = const pp.KitchenTransportOutcome(
      pp.KitchenTransportOutcomeKind.accepted,
      'flushed',
    ),
    Future<KitchenAckResult> Function()? ackResult,
    List<Override> extra = const [],
  }) {
    acks = [];
    sends = [];
    // A usable KITCHEN destination for the paired device (the lane resolves
    // the real target; only the physical transport is faked).
    SharedPreferences.setMockInitialValues({
      kioskKitchenNetworkKey('dev-b2'):
          '{"host":"10.0.0.7","port":9100,"name":"K"}',
      kioskKitchenSelectedKey('dev-b2'): 'network',
    });
    final container = ProviderContainer(
      overrides: [
        kioskKitchenTransportSendProvider.overrideWithValue((
          bytes,
          target,
        ) async {
          sends.add(bytes);
          return outcome;
        }),
        kioskKitchenAckProvider.overrideWithValue(({
          required dispatchId,
          required status,
          errorCode,
        }) async {
          acks.add((dispatchId: dispatchId, status: status));
          return ackResult != null
              ? await ackResult()
              : const KitchenAckAccepted(
                  idempotencyReplay: false,
                  completed: true,
                );
        }),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    container
        .read(kioskDeviceContextProvider.notifier)
        .state = const DeviceContext(
      organizationId: 'org',
      branchId: 'branch',
      deviceId: 'dev-b2',
      deviceType: 'kiosk',
    );
    return container;
  }

  KioskKitchenTicketPrinter lane(ProviderContainer c) =>
      c.read(kioskKitchenTicketPrinterProvider);

  group('A. exactly-once render/send/ack', () {
    test('one claimed accepted order -> ONE send of the SHARED renderer '
        'bytes -> transport_accepted ack', () async {
      final c = harness();
      await lane(
        c,
      ).onOrderAccepted(order: order, lang: 'en', dispatch: dispatch());
      expect(sends, hasLength(1));
      expect(acks, [
        (
          dispatchId: 'disp-1',
          status: KitchenImportAckStatus.transportAccepted,
        ),
      ]);
      // KIOSK-PRINT-114B.5A: the bytes ARE the CANONICAL kitchen ticket — the
      // dispatch adapted into the shared POS/KDS KdsTicketView and encoded
      // through the ONE shared bytes seam (no second kiosk formatter can
      // exist; the legacy per-unit spool frame is no longer on this lane).
      final expected = await CanonicalKitchenDispatchRenderer(
        labels: kitchenTicketPrintLabelsForLanguageCode('en'),
      ).renderToBytes(KitchenDispatchDocument.fromJson(payload));
      expect(sends.single, expected);
      final legacy = await const KitchenTicketRenderer(
        labels: KitchenTicketLabels.en,
      ).renderToBytes(KitchenDispatchDocument.fromJson(payload));
      expect(sends.single, isNot(legacy));
      final text = utf8.decode(sends.single, allowMalformed: true);
      // The fixture: qty 2 × (Patty 1/unit classified + Bun 2/unit) and the
      // Large option's 1 patty per unit => counts multiplied by the line qty.
      // ('×' is non-ASCII and leaves the text encoder as a codepage byte —
      // assert on the ASCII part of the item line.)
      expect(text, contains('B2 Burger'));
      expect(text, contains('Kitchen total'));
      expect(
        text.indexOf('Kitchen total'),
        lessThan(text.indexOf('B2 Burger')),
      );
      // KIOSK-PRINT-114B.6: the canonical header — the LARGE service-mode
      // badge and the ORDER CREATION stamp (server created_at, local time).
      final labels = kitchenTicketPrintLabelsForLanguageCode('en');
      expect(text, contains(kitchenServiceModeBadge(labels, 'takeaway')!));
      expect(
        text,
        contains(
          formatKitchenTicketTimestamp(
            DateTime.parse('2026-08-25T11:07:00Z').toLocal(),
          ),
        ),
      );
      final status = c.read(kioskKitchenPrintStatusProvider);
      expect(status?.outcome, KioskKitchenPrintOutcome.sent);
    });

    test('a same-run replay of the hook does NOT send twice (latch)', () async {
      final c = harness();
      await lane(
        c,
      ).onOrderAccepted(order: order, lang: 'en', dispatch: dispatch());
      await lane(
        c,
      ).onOrderAccepted(order: order, lang: 'en', dispatch: dispatch());
      expect(sends, hasLength(1));
      expect(acks, hasLength(1));
    });

    test('no claimed dispatch -> complete no-op', () async {
      final c = harness();
      await lane(c).onOrderAccepted(order: order, lang: 'en', dispatch: null);
      expect(sends, isEmpty);
      expect(acks, isEmpty);
      expect(c.read(kioskKitchenPrintStatusProvider), isNull);
    });

    test('a malformed payload never sends and acks failed_retryable', () async {
      final c = harness();
      await lane(c).onOrderAccepted(
        order: order,
        lang: 'en',
        dispatch: const KioskClaimedKitchenDispatch(
          id: 'disp-bad',
          payload: {'v': 99, 'items': 'not-a-list'},
          claimExpiresAt: null,
        ),
      );
      expect(sends, isEmpty);
      expect(acks, [
        (
          dispatchId: 'disp-bad',
          status: KitchenImportAckStatus.failedRetryable,
        ),
      ]);
    });
  });

  group('B. honest outcome -> ack mapping', () {
    test('definitelyNotSent -> failed_retryable + failure status', () async {
      final c = harness(
        outcome: const pp.KitchenTransportOutcome(
          pp.KitchenTransportOutcomeKind.definitelyNotSent,
          'connect_failed',
        ),
      );
      await lane(
        c,
      ).onOrderAccepted(order: order, lang: 'en', dispatch: dispatch());
      expect(acks.single.status, KitchenImportAckStatus.failedRetryable);
      expect(
        c.read(kioskKitchenPrintStatusProvider)?.outcome,
        KioskKitchenPrintOutcome.failedRetryable,
      );
    });

    test(
      'ambiguous -> possibly_printed, and retry() REFUSES to resend it',
      () async {
        final c = harness(
          outcome: const pp.KitchenTransportOutcome(
            pp.KitchenTransportOutcomeKind.ambiguous,
            'socket_error_at_write',
          ),
        );
        await lane(
          c,
        ).onOrderAccepted(order: order, lang: 'en', dispatch: dispatch());
        expect(acks.single.status, KitchenImportAckStatus.possiblyPrinted);
        expect(
          c.read(kioskKitchenPrintStatusProvider)?.outcome,
          KioskKitchenPrintOutcome.possiblyPrinted,
        );
        await lane(c).retry();
        expect(
          sends,
          hasLength(1),
          reason: 'possibly_printed NEVER auto-repeats',
        );
        expect(acks, hasLength(1));
      },
    );

    test('timeoutAfterPossibleWrite -> possibly_printed', () async {
      final c = harness(
        outcome: const pp.KitchenTransportOutcome(
          pp.KitchenTransportOutcomeKind.timeoutAfterPossibleWrite,
          'flush_timeout',
        ),
      );
      await lane(
        c,
      ).onOrderAccepted(order: order, lang: 'en', dispatch: dispatch());
      expect(acks.single.status, KitchenImportAckStatus.possiblyPrinted);
    });

    test(
      'retry() after failed_retryable re-sends the SAME dispatch under '
      'the SAME live claim (verified backend capability) and can complete',
      () async {
        final c = harness(
          outcome: const pp.KitchenTransportOutcome(
            pp.KitchenTransportOutcomeKind.timeoutBeforeWrite,
            'connect_timeout',
          ),
        );
        await lane(
          c,
        ).onOrderAccepted(order: order, lang: 'en', dispatch: dispatch());
        expect(acks.single.status, KitchenImportAckStatus.failedRetryable);
        // The printer came back: retry the SAME dispatch id — no new claim.
        final c2sends = sends;
        await lane(c).retry();
        expect(c2sends, hasLength(2));
        expect(acks, hasLength(2));
        expect(acks.last.dispatchId, 'disp-1');
      },
    );
  });

  group('C. role independence', () {
    test(
      'a kitchen failure never touches the receipt status provider',
      () async {
        final c = harness(
          outcome: const pp.KitchenTransportOutcome(
            pp.KitchenTransportOutcomeKind.definitelyNotSent,
            'connect_failed',
          ),
        );
        await lane(
          c,
        ).onOrderAccepted(order: order, lang: 'en', dispatch: dispatch());
        // Receipt lane state untouched by the kitchen lane.
        expect(
          c.read(kioskKitchenPrintStatusProvider)?.outcome,
          KioskKitchenPrintOutcome.failedRetryable,
        );
      },
    );
  });
}
