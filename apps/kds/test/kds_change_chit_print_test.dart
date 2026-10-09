import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show OrderChangeRemoved, OrderChangeSlipView;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_change_chit.dart';
import 'package:restoflow_kds/src/print/kds_ticket_document.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_kds/src/state/kds_auto_print_prefs.dart';
import 'package:restoflow_kds/src/state/kds_kitchen_print_controller.dart';
import 'package:restoflow_kds/src/state/kds_printer_assignments.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show BridgeSubmitResult, PrinterErrorCategory;

/// ORDER-EDIT-001D — the CHANGE CHIT print policy on the kitchen print
/// controller: the same gating as print-on-Acknowledge, one chit per (order,
/// "Got it" number), a per-unit watermark so a second "Got it" before the pull
/// prints only the newer edit, failures recorded ONLY under the chit key, and
/// the card job recording the edits its paper already shows.

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

class _FakeReader implements DevicePrinterAssignmentsReader {
  _FakeReader({this.hasPrinter = true, this.fail = false});

  final bool hasPrinter;
  final bool fail;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => fail
      ? const Failure(DevicePrinterAssignmentsFailure.network)
      : Success(
          DevicePrinterAssignments(
            fetchedAt: DateTime(2026, 10, 8, 12, 30),
            printers: hasPrinter
                ? const [
                    AssignedPrinter(
                      id: 'prn-k1',
                      displayName: 'Kitchen printer',
                      role: 'kitchen',
                      connectionType: 'network',
                      paperWidth: '80mm',
                      isEnabled: true,
                    ),
                  ]
                : const [],
          ),
        );
}

class _OffAutoPrint extends KdsAutoPrintAcknowledgeController {
  @override
  Future<bool?> build() async => false;
}

Future<ProviderContainer> _container({
  bool hasPrinter = true,
  bool fail = false,
  bool autoPrintOff = false,
}) async {
  final c = ProviderContainer(
    overrides: [
      kdsPrinterAssignmentsReaderProvider.overrideWithValue(
        _FakeReader(hasPrinter: hasPrinter, fail: fail),
      ),
      if (autoPrintOff)
        kdsAutoPrintAcknowledgeProvider.overrideWith(_OffAutoPrint.new),
    ],
  );
  addTearDown(c.dispose);
  await c.read(kdsPrinterAssignmentsProvider.future);
  await c.read(kdsAutoPrintAcknowledgeProvider.future);
  return c;
}

KdsOrderEdit _edit(int number) => KdsOrderEdit(
  id: 'e$number',
  orderId: 'o1',
  editNumber: number,
  channel: KdsEditChannel.kds,
  ackRequired: true,
);

/// An acknowledged (printed) unit of order o1 at [station] whose pending
/// edits removed [removed] (name -> edit number).
KdsTicketView _unit(
  String station,
  Map<String, int> removed, {
  List<int> orderPending = const [1, 2],
  String? roundId,
}) {
  final numbers = removed.values.toSet().toList()..sort();
  return KdsTicketView(
    kitchenTicketId: roundId == null ? 'o1:$station' : 'o1:$station:r$roundId',
    stationId: station,
    orderId: 'o1',
    orderNumber: '#ABC123',
    orderType: 'takeaway',
    roundId: roundId,
    roundNumber: roundId == null ? null : 2,
    status: KitchenTicketStatus.acknowledged,
    items: const [KdsItemView(name: 'Burger', quantity: 1)],
    change: KdsTicketChange(
      pendingEdits: [for (final n in numbers) _edit(n)],
      removed: [
        for (final MapEntry(key: name, value: n) in removed.entries)
          KdsRemovedLine(
            line: KdsItemView(name: name, quantity: 1),
            editNumber: n,
            removedKitchenStage: 'accepted',
          ),
      ],
      orderPendingEditNumbers: orderPending,
    ),
  );
}

List<String> _removedNames(OrderChangeSlipView view) => [
  for (final c in view.changes) (c as OrderChangeRemoved).was.name,
];

void main() {
  test('toggle OFF -> nothing is built, stored or sent', () async {
    final c = await _container(autoPrintOff: true);
    var builds = 0;
    var submits = 0;
    await c
        .read(kdsKitchenPrintControllerProvider.notifier)
        .printChangeChit(
          orderId: 'o1',
          upToEditNumber: 1,
          board: [
            _unit('grill', {'Fries': 1}),
          ],
          buildDocument: (_) {
            builds++;
            return PrintDocument(title: 't', lines: const []);
          },
          submitToBridge: (_) async {
            submits++;
            return const BridgeSubmitResult.sentToPrinter();
          },
        );
    expect((builds, submits), (0, 0));
    expect(c.read(kdsKitchenPrintControllerProvider), isEmpty);
  });

  test('no enabled printer -> nothing and NO marker (no card would show '
      'it once the change clears)', () async {
    final c = await _container(hasPrinter: false);
    await c
        .read(kdsKitchenPrintControllerProvider.notifier)
        .printChangeChit(
          orderId: 'o1',
          upToEditNumber: 1,
          board: [
            _unit('grill', {'Fries': 1}),
          ],
          buildDocument: (_) => throw 'never built',
        );
    expect(c.read(kdsKitchenPrintControllerProvider), isEmpty);
  });

  test('a FAILED assignment read -> nothing; a device-local printer still '
      'prints', () async {
    final l10n = await _en();
    final c = await _container(fail: true);
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    await controller.printChangeChit(
      orderId: 'o1',
      upToEditNumber: 1,
      board: [
        _unit('grill', {'Fries': 1}),
      ],
      buildDocument: (_) => throw 'never built',
    );
    expect(c.read(kdsKitchenPrintControllerProvider), isEmpty);

    await controller.printChangeChit(
      orderId: 'o1',
      upToEditNumber: 1,
      board: [
        _unit('grill', {'Fries': 1}),
      ],
      buildDocument: (v) => buildKdsChangeChitDocument(l10n, v),
      nativePrinterConfigured: true,
    );
    expect(
      c
          .read(
            kdsKitchenPrintControllerProvider,
          )[KdsKitchenPrintController.chitKeyFor('o1', 1)]
          ?.status,
      KdsPrintJobStatus.prepared,
    );
  });

  test('the same (order, N) twice -> ONE build and ONE submit; the chit '
      'reaches the printer', () async {
    final l10n = await _en();
    final c = await _container();
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    var builds = 0;
    final submitted = <PrintDocument>[];
    for (var i = 0; i < 2; i++) {
      await controller.printChangeChit(
        orderId: 'o1',
        upToEditNumber: 1,
        board: [
          _unit('grill', {'Fries': 1}),
        ],
        buildDocument: (v) {
          builds++;
          return buildKdsChangeChitDocument(l10n, v);
        },
        submitToBridge: (doc) async {
          submitted.add(doc);
          return const BridgeSubmitResult.sentToPrinter();
        },
      );
    }
    expect(builds, 1);
    expect(submitted, hasLength(1));
    final texts = [for (final l in submitted.single.lines) l.left ?? ''];
    expect(texts, containsAllInOrder(['REMOVED', '1 × Fries']));
    expect(
      c
          .read(
            kdsKitchenPrintControllerProvider,
          )[KdsKitchenPrintController.chitKeyFor('o1', 1)]!
          .status,
      KdsPrintJobStatus.sentToPrinter,
    );
  });

  test('"Got it" N=2 after N=1, before the pull clears change 1, prints '
      'change 2 lines only', () async {
    final c = await _container();
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    final board = [
      _unit('grill', {'Fries': 1}),
      _unit('bar', {'Cola': 2}),
    ];
    final views = <OrderChangeSlipView>[];
    PrintDocument capture(OrderChangeSlipView v) {
      views.add(v);
      return PrintDocument(title: 'chit', lines: const []);
    }

    await controller.printChangeChit(
      orderId: 'o1',
      upToEditNumber: 1,
      board: board,
      buildDocument: capture,
    );
    await controller.printChangeChit(
      orderId: 'o1',
      upToEditNumber: 2,
      board: board,
      buildDocument: capture,
    );
    expect(views, hasLength(2));
    expect(_removedNames(views[0]), ['Fries']);
    expect(_removedNames(views[1]), ['Cola']);
    expect(controller.printFactsFor(board[0]).through, 2);
    expect(controller.printFactsFor(board[1]).through, 2);
  });

  test('a builder throw is recorded ONLY under the chit key; the card job is '
      'unchanged', () async {
    final l10n = await _en();
    final c = await _container();
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    final unit = _unit('grill', {'Fries': 1});
    controller.prepareForTicket(
      unit,
      hasEnabledPrinter: true,
      buildDocument: () => buildKdsTicketDocument(l10n, unit),
    );
    final cardJob = controller.jobFor(unit);
    await controller.printChangeChit(
      orderId: 'o1',
      upToEditNumber: 2,
      board: [
        _unit('grill', {'Fries': 2}),
      ],
      buildDocument: (_) => throw StateError('layout'),
    );
    final jobs = c.read(kdsKitchenPrintControllerProvider);
    expect(
      jobs[KdsKitchenPrintController.chitKeyFor('o1', 2)]!.status,
      KdsPrintJobStatus.failed,
    );
    expect(identical(controller.jobFor(unit), cardJob), isTrue);
    expect(jobs, hasLength(2));
  });

  test('a bridge failure is recorded ONLY under the chit key', () async {
    final l10n = await _en();
    final c = await _container();
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    final unit = _unit('grill', {'Fries': 1});
    controller.prepareForTicket(
      unit,
      hasEnabledPrinter: true,
      buildDocument: () => buildKdsTicketDocument(l10n, unit),
    );
    final cardJob = controller.jobFor(unit);
    await controller.printChangeChit(
      orderId: 'o1',
      upToEditNumber: 2,
      board: [
        _unit('grill', {'Fries': 2}),
      ],
      buildDocument: (v) => buildKdsChangeChitDocument(l10n, v),
      submitToBridge: (_) async =>
          const BridgeSubmitResult.failed(PrinterErrorCategory.paperOut),
    );
    final chit = c.read(
      kdsKitchenPrintControllerProvider,
    )[KdsKitchenPrintController.chitKeyFor('o1', 2)]!;
    expect(chit.status, KdsPrintJobStatus.failed);
    expect(chit.failureCategory, PrinterErrorCategory.paperOut);
    expect(identical(controller.jobFor(unit), cardJob), isTrue);
  });

  test('nothing already on paper changed -> no chit and no job', () async {
    final c = await _container();
    final unprinted = KdsTicketView(
      kitchenTicketId: 'o1:grill:rr2',
      stationId: 'grill',
      orderId: 'o1',
      orderNumber: '#ABC123',
      roundId: 'r2',
      roundNumber: 2,
      status: KitchenTicketStatus.newTicket,
      items: const [
        KdsItemView(
          name: 'Salad',
          quantity: 1,
          editMark: KdsEditLineMark.added,
          editNumber: 1,
        ),
      ],
      change: KdsTicketChange(pendingEdits: [_edit(1)]),
    );
    await c
        .read(kdsKitchenPrintControllerProvider.notifier)
        .printChangeChit(
          orderId: 'o1',
          upToEditNumber: 1,
          board: [unprinted],
          buildDocument: (_) => throw 'never built',
        );
    expect(c.read(kdsKitchenPrintControllerProvider), isEmpty);
  });

  test('chitKeyFor never equals any work-unit keyFor', () {
    final tickets = [
      _unit('grill', {'Fries': 1}),
      _unit('grill', {'Fries': 1}, roundId: 'r2'),
      _unit('unassigned', {'Fries': 1}),
      KdsTicketView(
        kitchenTicketId: 'o1|chit:e1-demo',
        stationId: 'grill',
        items: const [],
      ),
    ];
    for (final n in [1, 2, 10]) {
      final chit = KdsKitchenPrintController.chitKeyFor('o1', n);
      expect(chit, isNot(contains('|station:')));
      for (final t in tickets) {
        expect(chit, isNot(KdsKitchenPrintController.keyFor(t)));
      }
    }
  });

  test('prepareForTicket records the edits the paper already shows, and a '
      'status flip keeps it', () async {
    final l10n = await _en();
    final c = await _container();
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    final edited = _unit('grill', {'Fries': 1, 'Cola': 2});
    controller.prepareForTicket(
      edited,
      hasEnabledPrinter: true,
      buildDocument: () => buildKdsTicketDocument(l10n, edited),
    );
    final key = KdsKitchenPrintController.keyFor(edited);
    expect(controller.jobFor(edited)!.printedThroughEdit, 2);
    controller.markSentToPrinter(key);
    expect(controller.jobFor(edited)!.printedThroughEdit, 2);
    expect(controller.printFactsFor(edited), (
      printed: true,
      fromLocalJob: true,
      through: 2,
    ));

    final plain = KdsTicketView(
      kitchenTicketId: 'o2:grill',
      stationId: 'grill',
      orderId: 'o2',
      items: const [KdsItemView(name: 'Soup', quantity: 1)],
      status: KitchenTicketStatus.acknowledged,
    );
    controller.prepareForTicket(
      plain,
      hasEnabledPrinter: true,
      buildDocument: () => buildKdsTicketDocument(l10n, plain),
    );
    expect(controller.jobFor(plain)!.printedThroughEdit, isNull);
  });

  test('printFactsFor: a failed local job is not paper; without a job the '
      'stage decides', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final controller = c.read(kdsKitchenPrintControllerProvider.notifier);
    final unit = _unit('grill', {'Fries': 1});
    expect(controller.printFactsFor(unit), (
      printed: true,
      fromLocalJob: false,
      through: 0,
    ));
    unit.status = KitchenTicketStatus.newTicket;
    expect(controller.printFactsFor(unit).printed, isFalse);
    controller.prepareForTicket(
      unit,
      hasEnabledPrinter: true,
      buildDocument: () => throw StateError('layout'),
    );
    expect(controller.printFactsFor(unit), (
      printed: false,
      fromLocalJob: true,
      through: 0,
    ));
  });
}
