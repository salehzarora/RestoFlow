import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenTicketStatus;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/state/kds_kitchen_print_controller.dart';

/// DEFERRED-ORDER-AMENDMENTS-001 — the KDS print-job IDENTITY.
///
/// A PSC-001C round ticket carries the PARENT order's id (that is the point — it
/// belongs to that order), while its `kitchenTicketId` is the real composite
/// `order:station[:rRound]`. The print guard keyed on `orderId` alone therefore
/// collapsed two distinct work units onto ONE key:
///
///   * every service round landed on the parent order's key, so once the initial
///     ticket had printed, every later ADDITION was silently reported as already
///     handled and the kitchen never received the added food;
///   * every station's ticket for one order landed on the same key too, so on a
///     station-routed board only the first station printed.
///
/// This suite pins the composite identity (order + station + round) and that a
/// round ticket really does get its own prepared job. It also pins that a KDS
/// round ticket PRINTS the addition marker through the shared builder.

KdsTicketView _ticket({
  String? orderId = 'o1',
  String station = 'unassigned',
  String? roundId,
  int? roundNumber,
}) => KdsTicketView(
  // The mapper's real key shape, so the fixture cannot drift from production.
  kitchenTicketId: roundId == null
      ? '${orderId ?? 'demo'}:$station'
      : '${orderId ?? 'demo'}:$station:r$roundId',
  stationId: station,
  orderId: orderId,
  orderNumber: '#ABC123',
  orderType: 'dine_in',
  tableLabel: 'T1',
  status: KitchenTicketStatus.newTicket,
  submittedAt: DateTime.utc(2026, 8, 4, 10),
  items: const [KdsItemView(name: 'Fries', quantity: 1)],
  roundId: roundId,
  roundNumber: roundNumber,
);

KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket preview',
  dineIn: 'Dine-in',
  takeaway: 'Takeaway',
  tableLabel: 'Table',
  customerLabel: 'Customer',
  customerPhoneLabel: 'Phone',
  stationLabel: 'Station',
  noteLabel: 'Note',
  kitchenTotal: (count, unit) => 'Kitchen total: $count $unit',
  additionLabel: 'Addition',
  roundLabel: (n) => 'Round $n',
);

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('A. the print-job key is a COMPOSITE work-unit identity', () {
    test('A1 a ROUND ticket does NOT share the parent order\'s key', () {
      final parent = KdsKitchenPrintController.keyFor(_ticket());
      final round = KdsKitchenPrintController.keyFor(
        _ticket(roundId: 'r2', roundNumber: 2),
      );
      expect(round, isNot(parent));
      expect(
        parent,
        isNot('o1'),
        reason: 'the bare order id is not an identity',
      );
    });

    test('A2 different ROUNDS of the same order get different keys', () {
      expect(
        KdsKitchenPrintController.keyFor(
          _ticket(roundId: 'r2', roundNumber: 2),
        ),
        isNot(
          KdsKitchenPrintController.keyFor(
            _ticket(roundId: 'r3', roundNumber: 3),
          ),
        ),
      );
    });

    test('A3 different STATIONS of the same order get different keys', () {
      expect(
        KdsKitchenPrintController.keyFor(_ticket(station: 'grill')),
        isNot(KdsKitchenPrintController.keyFor(_ticket(station: 'bar'))),
      );
    });

    test('A4 the same work unit keeps ONE stable key (a re-poll rebuilds the '
        'view but must not re-print)', () {
      expect(
        KdsKitchenPrintController.keyFor(
          _ticket(roundId: 'r2', roundNumber: 2),
        ),
        KdsKitchenPrintController.keyFor(
          _ticket(roundId: 'r2', roundNumber: 2),
        ),
      );
    });

    test('A5 a ticket with NO order id (demo fixtures) still falls back to its '
        'kitchen-ticket id', () {
      final ticket = _ticket(orderId: null);
      expect(KdsKitchenPrintController.keyFor(ticket), ticket.kitchenTicketId);
    });
  });

  group('B. a round ticket really gets its own prepared job', () {
    test('B1 preparing the parent then its ADDITION yields TWO jobs — the '
        'addition is no longer swallowed', () {
      final c = _container();
      final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
      final parent = _ticket();
      final round = _ticket(roundId: 'r2', roundNumber: 2);

      controller.prepareForTicket(
        parent,
        hasEnabledPrinter: true,
        buildDocument: () =>
            buildKdsTicketPrintDocument(ticket: parent, labels: _labels()),
      );
      controller.prepareForTicket(
        round,
        hasEnabledPrinter: true,
        buildDocument: () =>
            buildKdsTicketPrintDocument(ticket: round, labels: _labels()),
      );

      expect(c.read(kdsKitchenPrintControllerProvider), hasLength(2));
      expect(controller.jobFor(parent), isNotNull);
      expect(controller.jobFor(round), isNotNull);
      expect(
        controller.jobFor(round)!.status,
        KdsPrintJobStatus.prepared,
        reason: 'the added food has a real prepared ticket',
      );
    });

    test('B2 the SAME round is still idempotent across re-polls (exactly one '
        'prepared job, built once)', () {
      final c = _container();
      final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
      final round = _ticket(roundId: 'r2', roundNumber: 2);
      var builds = 0;
      for (var i = 0; i < 3; i++) {
        controller.prepareForTicket(
          round,
          hasEnabledPrinter: true,
          buildDocument: () {
            builds++;
            return buildKdsTicketPrintDocument(
              ticket: round,
              labels: _labels(),
            );
          },
        );
      }
      expect(builds, 1);
      expect(c.read(kdsKitchenPrintControllerProvider), hasLength(1));
    });

    test('B3 two rounds of the same order each get their own job', () {
      final c = _container();
      final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
      for (final r in [2, 3]) {
        final t = _ticket(roundId: 'r$r', roundNumber: r);
        controller.prepareForTicket(
          t,
          hasEnabledPrinter: true,
          buildDocument: () =>
              buildKdsTicketPrintDocument(ticket: t, labels: _labels()),
        );
      }
      expect(c.read(kdsKitchenPrintControllerProvider), hasLength(2));
    });
  });

  group('C. the KDS-printed round ticket is marked as an addition', () {
    test('C1 a round ticket prints "Addition · Round N" and the original order '
        'code; a normal ticket prints neither', () {
      final round = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r2', roundNumber: 4),
        labels: _labels(),
      );
      final texts = [for (final l in round.lines) l.left ?? ''];
      expect(texts, contains('Addition · Round 4'));
      expect(texts, contains('#ABC123'));

      final normal = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
      );
      final normalTexts = [for (final l in normal.lines) l.left ?? ''];
      expect(normalTexts.where((t) => t.contains('Addition')), isEmpty);
      expect(
        normalTexts,
        contains('#ABC123'),
        reason: 'a normal ticket keeps its layout',
      );
    });

    test('C2 the round ticket stays money-free and delta-only', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r2', roundNumber: 4),
        labels: _labels(),
      );
      final blob = [
        for (final l in doc.lines) l.left ?? '',
      ].join('\n').toLowerCase();
      for (final token in ['subtotal', 'tender', '₪', r'$']) {
        expect(blob, isNot(contains(token)), reason: 'money token: $token');
      }
      expect(
        [for (final l in doc.lines) l.right ?? ''].where((r) => r.isNotEmpty),
        isEmpty,
      );
    });
  });
}
