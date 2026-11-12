// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F: the Edge exchange — the direct mapping
// of the 001C kinds, the closed answer parse and the exact request bodies
// (execution packet §4.1, §4.2, §6).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/provider_card_attempt.dart';
import 'package:restoflow_pos/src/data/provider_card_edge.dart';

import 'support/provider_card_fakes.dart';

ProviderCardAttempt _attempt({ProviderCardMode mode = ProviderCardMode.live}) =>
    ProviderCardAttempt.create(
      attemptId: cardV4(1),
      organizationId: kCardScope.organizationId,
      restaurantId: kCardScope.restaurantId,
      branchId: kCardScope.branchId,
      deviceId: kCardScope.deviceId,
      orderId: kCardOrder,
      orderNumber: '#A1',
      mode: mode,
      amountMinor: 1200,
      currencyCode: 'ILS',
      expectedRevision: 7,
      employeeProfileId: 'emp-cashier',
      now: kCardNow,
    );

Map<String, Object?> _envelope({
  String state = 'sent',
  String classification = 'in_progress',
  bool recorded = false,
  Map<String, Object?> extra = const <String, Object?>{},
  int amount = 1200,
  String currency = 'ILS',
}) => <String, Object?>{
  'ok': true,
  'attempt_id': cardV4(1),
  'state': state,
  'classification': classification,
  'recorded': recorded,
  ...extra,
  'amount_minor': amount,
  'currency_code': currency,
  'server_ts': '2026-10-30T12:00:00Z',
};

ProviderCardEdgeResult _through(
  int status,
  Object? body, {
  ProviderCardAttempt? a,
}) => mapProviderCardTransportResult(
  classifyCardChargeAnswer(status, body, attemptId: cardV4(1)),
  a ?? _attempt(),
);

void main() {
  group('the 001C kinds, mapped directly (packet §6)', () {
    test('notSent / unauthenticated / notApplied / uncertain', () {
      final a = _attempt();
      expect(
        mapProviderCardTransportResult(
          const CardChargeTransportFailure.notSent(
            CardChargeFailureReason.deviceSessionUnverified,
          ),
          a,
        ),
        isA<ProviderCardEdgeNotSent>(),
      );
      expect(
        _through(401, {'ok': false, 'error': 'invalid_session'}),
        isA<ProviderCardEdgeUnauthenticated>(),
      );
      for (final s in <int>[400, 403, 404, 405]) {
        final r = _through(s, {'ok': false, 'error': 'invalid_request'});
        expect(r, isA<ProviderCardEdgeNotApplied>(), reason: '$s');
        expect((r as ProviderCardEdgeNotApplied).httpStatus, s);
      }
      expect(
        mapProviderCardTransportResult(
          const CardChargeTransportFailure.uncertain(
            CardChargeFailureReason.timeout,
          ),
          a,
        ),
        isA<ProviderCardEdgeUncertain>(),
      );
    });

    test('409 / 413 / 415 / 422 stay uncertain through the POS layer, whatever '
        'the body says', () {
      for (final s in <int>[409, 413, 415, 422, 407, 429, 503]) {
        expect(
          _through(s, {'ok': false, 'error': 'invalid_request'}),
          isA<ProviderCardEdgeUncertain>(),
          reason: 'HTTP $s',
        );
      }
    });

    test('the generic payment transport classifier is never used for a card '
        'result', () {
      for (final f in <String>[
        'lib/src/data/provider_card_attempt.dart',
        'lib/src/data/provider_card_edge.dart',
        'lib/src/data/provider_card_recording.dart',
        'lib/src/data/provider_card_store.dart',
        'lib/src/data/provider_card_capability.dart',
        'lib/src/state/provider_card_controller.dart',
        'lib/src/widgets/provider_card_payment_view.dart',
        'lib/src/format/provider_card_presentation.dart',
      ]) {
        final source = File(f).readAsStringSync();
        // Prose may name it; no code may call it.
        final code = source
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains('classifyTransportFailure('), isFalse, reason: f);
      }
    });
  });

  group('the closed envelope (packet §4.2)', () {
    test('every state and classification is read, and the provider return code '
        'is dropped', () {
      final cases = <Map<String, Object?>>[
        _envelope(),
        _envelope(state: 'unknown'),
        _envelope(state: 'released'),
        _envelope(state: 'declined', classification: 'declined'),
        _envelope(state: 'approved', classification: 'approved_unrecorded'),
        _envelope(
          state: 'approved',
          classification: 'approved_unrecorded',
          extra: {
            'refusal_code': 'precondition_failed',
            'recoverable': true,
            'resume_count': 0,
          },
        ),
        _envelope(
          state: 'approved',
          classification: 'recorded',
          recorded: true,
          extra: {'payment_id': 'f0f0f0f0-0000-4000-8000-000000000001'},
        ),
        _envelope(
          state: 'unknown',
          classification: 'provider_anomaly',
          extra: {'anomaly_code': 'amount_mismatch'},
        ),
        _envelope(
          state: 'approved',
          classification: 'orphan_approved',
          extra: {
            'refusal_code': 'revoked_device',
            'recoverable': false,
            'resume_count': 0,
          },
        ),
        _envelope(state: 'unknown', classification: 'freed'),
        _envelope(
          state: 'approved',
          classification: 'resolved',
          extra: {'resolution': 'provider_refunded'},
        ),
        _envelope(extra: {'provider_return_code': 3}),
        _envelope(extra: {'refusal_code': 'release_failed'}),
      ];
      for (final e in cases) {
        final r = _through(200, e);
        expect(r, isA<ProviderCardEdgeEnvelope>(), reason: jsonEncode(e));
        final facts = (r as ProviderCardEdgeEnvelope).facts;
        expect(facts.classification, e['classification']);
        expect(
          jsonEncode(facts.toJson()).contains('provider_return_code'),
          isFalse,
        );
      }
      final test = _attempt(mode: ProviderCardMode.test);
      for (final s in <String>[
        'sent',
        'unknown',
        'released',
        'approved',
        'declined',
      ]) {
        final r = _through(
          200,
          _envelope(state: s, classification: 'test_$s'),
          a: test,
        );
        expect(r, isA<ProviderCardEdgeEnvelope>(), reason: s);
      }
      final closed = _through(
        200,
        _envelope(
          state: 'approved',
          classification: 'test_approved',
          extra: {'resolution': 'test_closed'},
        ),
        a: test,
      );
      expect(closed, isA<ProviderCardEdgeEnvelope>());
    });

    test('malformed or inconsistent answers fail closed (unreadable)', () {
      final bad = <Map<String, Object?>>[
        {..._envelope(), 'surprise': 1},
        Map.of(_envelope())..remove('recorded'),
        {..._envelope(), 'recorded': 'no'},
        {..._envelope(), 'refusal_code': null},
        _envelope(
          state: 'approved',
          classification: 'approved_unrecorded',
          extra: {'recoverable': true},
        ),
        _envelope(
          extra: {'payment_id': 'f0f0f0f0-0000-4000-8000-000000000001'},
        ),
        _envelope(state: 'sent', classification: 'declined'),
        _envelope(extra: {'provider_return_code': 'x'}),
        _envelope(classification: 'nonsense'),
      ];
      for (final e in bad) {
        expect(
          _through(200, e),
          isA<ProviderCardEdgeUnreadable>(),
          reason: jsonEncode(e),
        );
      }
      // Another attempt's echo never reaches the POS as an answer (001C).
      expect(
        _through(200, {..._envelope(), 'attempt_id': cardV4(9)}),
        isA<ProviderCardEdgeUncertain>(),
      );
    });

    test('a well-formed envelope that contradicts the frozen attempt is a '
        'safety stop', () {
      expect(
        (_through(200, _envelope(amount: 1300))
                as ProviderCardEdgeContradiction)
            .stop,
        ProviderCardSafetyStop.amountMismatch,
      );
      expect(
        (_through(200, _envelope(currency: 'USD'))
                as ProviderCardEdgeContradiction)
            .stop,
        ProviderCardSafetyStop.amountMismatch,
      );
      expect(
        (_through(200, _envelope(classification: 'test_sent'))
                as ProviderCardEdgeContradiction)
            .stop,
        ProviderCardSafetyStop.modeMismatch,
      );
    });

    test('closed refusals; unknown tokens and foreign attempt facts are '
        'unreadable', () {
      final r = _through(200, {
        'ok': false,
        'error': 'precondition_failed',
        'detail': 'no_open_shift',
        'server_ts': '2026-10-30T12:00:00Z',
      });
      expect(r, isA<ProviderCardEdgeRefusal>());
      expect((r as ProviderCardEdgeRefusal).detail, 'no_open_shift');
      final withFacts = _through(200, {
        'ok': false,
        'error': 'poll_limit',
        'attempt_id': cardV4(1),
        'attempt_state': 'sent',
      });
      expect((withFacts as ProviderCardEdgeRefusal).attemptState, 'sent');
      expect(
        _through(200, {'ok': false, 'error': 'rate_limited'}),
        isA<ProviderCardEdgeUnreadable>(),
      );
      expect(
        _through(200, {
          'ok': false,
          'error': 'poll_limit',
          'attempt_id': cardV4(1),
        }),
        isA<ProviderCardEdgeUnreadable>(),
      );
      // A 200 carrying a non-200 token is not the function's answer (001C).
      expect(
        _through(200, {'ok': false, 'error': 'invalid_request'}),
        isA<ProviderCardEdgeUncertain>(),
      );
    });
  });

  group('the exact bodies (packet §4.1)', () {
    late CardServerFake server;
    late InMemoryDeviceSessionSecretStore store;

    setUp(() async {
      server = CardServerFake();
      store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(
          deviceId: kCardDevice,
          sessionToken: kCardToken,
        ),
      );
    });

    ProviderCardEdgeClient client() => ProviderCardEdgeClient(
      transport: server,
      session: kCardSession,
      secretStore: store,
    );

    test(
      'LIVE start: the frozen inputs after the fresh session proof, in order',
      () async {
        final a = _attempt();
        await client().start(a);
        expect(server.edgeBodies.single.keys.toList(), <String>[
          'action',
          'pin_session_id',
          'device_id',
          'device_session_token',
          'attempt_id',
          'mode',
          'amount_minor',
          'currency_code',
          'order_id',
          'expected_revision',
        ]);
        expect(server.edgeBodies.single, <String, Object?>{
          'action': 'start',
          'pin_session_id': kCardPin,
          'device_id': kCardDevice,
          'device_session_token': kCardToken,
          'attempt_id': cardV4(1),
          'mode': 'live',
          'amount_minor': 1200,
          'currency_code': 'ILS',
          'order_id': kCardOrder,
          'expected_revision': 7,
        });
      },
    );

    test('TEST start carries no order and no revision', () async {
      await client().start(_attempt(mode: ProviderCardMode.test));
      final b = server.edgeBodies.single;
      expect(b.containsKey('order_id'), isFalse);
      expect(b.containsKey('expected_revision'), isFalse);
      expect(b['mode'], 'test');
    });

    test('status, the refusal report and release', () async {
      final a = _attempt();
      final c = client();
      await c.status(a, operator: false);
      await c.status(a, operator: true);
      await c.status(
        a,
        operator: true,
        recordingRefusedHint: 'precondition_failed',
      );
      await c.release(a);
      final common = <String, Object?>{
        'pin_session_id': kCardPin,
        'device_id': kCardDevice,
        'device_session_token': kCardToken,
        'attempt_id': cardV4(1),
      };
      expect(server.edgeBodies, <Map<String, Object?>>[
        {'action': 'status', ...common, 'source': 'auto'},
        {'action': 'status', ...common, 'source': 'operator'},
        {
          'action': 'status',
          ...common,
          'source': 'operator',
          'recording_refused': true,
          'refusal_code': 'precondition_failed',
        },
        {'action': 'release', ...common},
      ]);
    });

    test(
      'the same attempt and session give the same bytes on every send',
      () async {
        final a = _attempt();
        await client().start(a);
        await client().start(a);
        expect(server.edgeBytes, hasLength(2));
        expect(server.edgeBytes.first, server.edgeBytes.last);
      },
    );

    test('a failed session or device check sends nothing', () async {
      await store.write(
        const DeviceSessionCredential(
          deviceId: 'd0d0d0d0-0000-4000-8000-000000000009',
          sessionToken: kCardToken,
        ),
      );
      final r = await client().start(_attempt());
      expect(r, isA<ProviderCardEdgeNotSent>());
      expect(server.edgeBodies, isEmpty);
      await store.clear();
      expect(await client().start(_attempt()), isA<ProviderCardEdgeNotSent>());
      expect(server.edgeBodies, isEmpty);
      // A valid credential again: now only the world check can refuse.
      await store.write(
        const DeviceSessionCredential(
          deviceId: kCardDevice,
          sessionToken: kCardToken,
        ),
      );
      final notCurrent = ProviderCardEdgeClient(
        transport: server,
        session: kCardSession,
        secretStore: store,
        isCurrent: () => false,
      );
      expect(
        await notCurrent.start(_attempt()),
        isA<ProviderCardEdgeNotSent>(),
      );
      expect(server.edgeBodies, isEmpty);
      // Current before the exchange but not at the handoff: nothing is sent.
      var asked = 0;
      final lateChange = ProviderCardEdgeClient(
        transport: server,
        session: kCardSession,
        secretStore: store,
        isCurrent: () => ++asked == 1,
      );
      expect(
        await lateChange.start(_attempt()),
        isA<ProviderCardEdgeNotSent>(),
      );
      expect(asked, 2, reason: 'asked again at the handoff');
      expect(server.edgeBodies, isEmpty);
      // The control: the same credential in a current world sends.
      await client().start(_attempt());
      expect(server.edgeBodies, hasLength(1));
    });
  });
}
