import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show
        OrderChangeAdded,
        OrderChangeModified,
        OrderChangeQuantity,
        OrderChangeRemoved,
        OrderChangeSlipView,
        formatKitchenTicketTimestamp,
        kitchenTicketToEscPosDocument;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/print/kds_change_chit.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_kds/src/state/kds_kitchen_print_controller.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show printDocumentNeedsRaster;

/// ORDER-EDIT-001D (design §7.2) — the KDS CHANGE CHIT a "Got it" prints on an
/// auto-printing display: order-wide over the units already on paper, only
/// the edits in (watermark, N], REMOVED / CHANGE / ADD and never REMAKE (a
/// round's dishes print on that round's own Acknowledge), with no ORDER NOW,
/// no footer and no staff line. Money-free (T-003).

const _moneyTokens = [
  'total:',
  'subtotal',
  'tax',
  'discount',
  'payment',
  'tender',
  'price',
  'amount',
  '₪',
  r'$',
  '€',
  '_minor',
];

final _editTime = DateTime.utc(2026, 10, 8, 10, 20);

KdsOrderEdit _edit(
  int number, {
  String? reasonCode = 'customer_changed_mind',
  String? reasonText,
}) => KdsOrderEdit(
  id: 'e$number',
  orderId: 'o1',
  editNumber: number,
  channel: KdsEditChannel.kds,
  ackRequired: true,
  createdAt: _editTime.add(Duration(minutes: number)),
  reasonCode: reasonCode,
  reasonText: reasonText,
);

KdsItemView _line(
  String name, {
  int qty = 1,
  List<String> mods = const [],
  int pos = 0,
  String? id,
  KdsEditLineMark? mark,
  KdsItemView? was,
  int? edit,
}) => KdsItemView(
  name: name,
  quantity: qty,
  modifiers: mods,
  linePosition: pos,
  orderItemId: id,
  editMark: mark,
  editWas: was,
  editNumber: edit,
);

KdsRemovedLine _removed(
  String name, {
  int qty = 1,
  required int edit,
  String? stage = 'accepted',
  int? remadeIn,
}) => KdsRemovedLine(
  line: _line(name, qty: qty),
  editNumber: edit,
  removedKitchenStage: stage,
  remadeInRoundNumber: remadeIn,
);

KdsTicketView _unit({
  String station = 'grill',
  String? roundId,
  KitchenTicketStatus status = KitchenTicketStatus.acknowledged,
  List<KdsItemView> items = const [],
  List<KdsRemovedLine> removed = const [],
  List<KdsOrderEdit>? edits,
  List<int>? orderPending,
  bool standalone = false,
  bool emptied = false,
  String? formerStage,
  String? orderNumber = '#ABC123',
  int? openedBy,
  bool withChange = true,
}) {
  final pending = edits ?? [_edit(2)];
  return KdsTicketView(
    kitchenTicketId: roundId == null ? 'o1:$station' : 'o1:$station:r$roundId',
    stationId: station,
    orderId: 'o1',
    orderNumber: orderNumber,
    orderType: 'takeaway',
    customerName: 'Dana',
    roundId: roundId,
    roundNumber: roundId == null ? null : 3,
    status: status,
    items: items,
    openedByEditNumber: openedBy,
    change: withChange
        ? KdsTicketChange(
            pendingEdits: pending,
            removed: removed,
            standalone: standalone,
            emptied: emptied,
            formerStage: formerStage,
            orderPendingEditNumbers:
                orderPending ?? [for (final e in pending) e.editNumber],
          )
        : null,
  );
}

/// This device printed every unit itself, through [through].
KdsUnitPrintFacts Function(KdsTicketView) _localJob({int through = 0}) =>
    (_) => (printed: true, fromLocalJob: true, through: through);

/// The REAL facts of a fresh print controller (no local job: the stage proxy).
KdsUnitPrintFacts Function(KdsTicketView) _proxy() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container
      .read(kdsKitchenPrintControllerProvider.notifier)
      .printFactsFor;
}

/// The accepted unit of the canonical mix: a removal, a modify group, a
/// reduction, an in-place "+1" and an addition — all by edit 2.
KdsTicketView _acceptedMix() {
  final steakWas = _line('Steak', qty: 2, mods: ['Tomato'], id: 'i-steak');
  final colaWas = _line('Cola', qty: 3, id: 'i-cola');
  return _unit(
    items: [
      _line('Burger', qty: 2, pos: 1, id: 'i-burger'),
      _line(
        'Burger',
        pos: 1,
        id: 'i-burger-plus',
        mark: KdsEditLineMark.increased,
        edit: 2,
      ),
      _line(
        'Steak',
        mods: ['Tomato'],
        pos: 2,
        id: 'i-steak-a',
        mark: KdsEditLineMark.changed,
        was: steakWas,
        edit: 2,
      ),
      _line(
        'Steak',
        mods: ['Cheese'],
        pos: 2,
        id: 'i-steak-b',
        mark: KdsEditLineMark.changed,
        was: steakWas,
        edit: 2,
      ),
      _line(
        'Cola',
        pos: 3,
        id: 'i-cola-now',
        mark: KdsEditLineMark.changed,
        was: colaWas,
        edit: 2,
      ),
      _line(
        'Salad',
        pos: 4,
        id: 'i-salad',
        mark: KdsEditLineMark.added,
        edit: 2,
      ),
    ],
    removed: [_removed('Fries', edit: 2)],
  );
}

List<String> _texts(PrintDocument doc) => [
  for (final l in doc.lines) l.left ?? '',
];

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

void main() {
  test('an accepted unit\'s remove, modify group, reduction, in-place +1 and '
      'add print under REMOVED, CHANGE (Was:/Now:) and ADD', () async {
    final en = await _l10n('en');
    final view = kdsChangeChitView(
      orderId: 'o1',
      upToEditNumber: 2,
      board: [_acceptedMix()],
      facts: _localJob(),
    )!;

    // Removed lines first, then the live lines in render order.
    expect(
      [for (final c in view.changes) c.runtimeType],
      [
        OrderChangeRemoved,
        OrderChangeQuantity,
        OrderChangeModified,
        OrderChangeModified,
        OrderChangeAdded,
      ],
    );
    final plus = view.changes[1] as OrderChangeQuantity;
    expect((plus.was.quantity, plus.nowQuantity, plus.delta), (2, 3, 1));
    expect(plus.was.editMark, isNull, reason: 'the kept line it extends');
    // The two lines of ONE modify group under ONE "was".
    final steak = view.changes[2] as OrderChangeModified;
    expect(steak.was.quantity, 2);
    expect(
      [for (final l in steak.now) l.modifiers.single],
      ['Tomato', 'Cheese'],
    );
    final cola = view.changes[3] as OrderChangeModified;
    expect((cola.was.quantity, cola.now.single.quantity), (3, 1));

    final texts = _texts(buildKdsChangeChitDocument(en, view));
    expect(texts, contains('*** ORDER CHANGED · Change 2 ***'));
    expect(texts, contains('#ABC123'));
    expect(texts, containsAllInOrder(['REMOVED', '1 × Fries']));
    expect(
      texts,
      containsAllInOrder([
        'CHANGE',
        'Was: 2 × Steak',
        'Now: 1 × Steak',
        'Now: 1 × Steak',
        'Was: 3 × Cola',
        'Now: 1 × Cola',
      ]),
    );
    expect(texts, containsAllInOrder(['ADD', '+1 × Burger', '1 × Salad']));
    // The chit path: no ORDER NOW, no "replaces" footer, no staff line.
    expect(texts, isNot(contains('ORDER NOW')));
    expect(texts.where((t) => t.startsWith('Replaces earlier')), isEmpty);
    expect(texts.where((t) => t.startsWith('Staff')), isEmpty);
    expect(view.staffFirstName, isNull);
    expect(view.orderNow, isEmpty);
    expect(view.orderNote, isNull);
  });

  test('the header names the newest covered edit: its time (local) and its '
      'reason; an `other` reason prints its text', () async {
    final en = await _l10n('en');
    final view = kdsChangeChitView(
      orderId: 'o1',
      upToEditNumber: 2,
      board: [
        _unit(
          edits: [
            _edit(1),
            _edit(2, reasonCode: 'other', reasonText: 'Allergy'),
            _edit(3),
          ],
          removed: [_removed('Fries', edit: 1), _removed('Cola', edit: 2)],
        ),
      ],
      facts: _localJob(),
    )!;
    expect(view.editNumber, 2);
    expect(view.editedAt, _editTime.add(const Duration(minutes: 2)).toLocal());
    expect(view.editedAt!.isUtc, isFalse);
    expect(view.reasonCode, 'other');
    final texts = _texts(buildKdsChangeChitDocument(en, view));
    expect(texts, contains(formatKitchenTicketTimestamp(view.editedAt!)));
    expect(texts, contains('» Reason: Allergy'));
    expect(view.orderType, 'takeaway');
    expect(view.customerName, 'Dana');
  });

  test('a unit in New (an edit\'s own round) adds nothing; REMAKE never '
      'prints — that dish prints on its round\'s Acknowledge', () async {
    final en = await _l10n('en');
    final original = _unit(
      status: KitchenTicketStatus.ready,
      removed: [_removed('Burger', edit: 2, stage: 'ready', remadeIn: 3)],
    );
    final newRound = _unit(
      roundId: 'r3',
      status: KitchenTicketStatus.newTicket,
      openedBy: 2,
      items: [
        _line(
          'Burger',
          mods: ['Cheese'],
          pos: 5,
          id: 'i-remake',
          mark: KdsEditLineMark.remake,
          was: _line('Burger', mods: ['Tomato'], id: 'i-old'),
          edit: 2,
        ),
        _line(
          'Salad',
          pos: 6,
          id: 'i-salad',
          mark: KdsEditLineMark.added,
          edit: 2,
        ),
      ],
    );
    final view = kdsChangeChitView(
      orderId: 'o1',
      upToEditNumber: 2,
      board: [original, newRound],
      facts: _proxy(),
    )!;
    expect(view.changes, hasLength(1));
    final texts = _texts(buildKdsChangeChitDocument(en, view));
    expect(texts, containsAllInOrder(['REMOVED', '1 × Burger']));
    expect(texts.where((t) => t.contains('Salad')), isEmpty);
    expect(texts.where((t) => t.contains(en.kdsEditRemake)), isEmpty);
    expect(texts.where((t) => t.contains('Cheese')), isEmpty);

    // The new round alone: nothing at all to print.
    expect(
      kdsChangeChitView(
        orderId: 'o1',
        upToEditNumber: 2,
        board: [newRound],
        facts: _proxy(),
      ),
      isNull,
    );
    // Even a PRINTED round never prints a REMAKE line.
    final printedRound = _unit(
      roundId: 'r3',
      items: newRound.items
          .where((i) => i.editMark == KdsEditLineMark.remake)
          .toList(),
    );
    expect(
      kdsChangeChitView(
        orderId: 'o1',
        upToEditNumber: 2,
        board: [printedRound],
        facts: _localJob(),
      ),
      isNull,
    );
  });

  test('order-wide: "Got it" on the round card (also confirms change 1) '
      'covers the original unit\'s change 1', () {
    final original = _unit(
      edits: [_edit(1)],
      orderPending: [1, 2],
      removed: [_removed('Fries', edit: 1)],
    );
    final round = _unit(
      roundId: 'r3',
      status: KitchenTicketStatus.newTicket,
      openedBy: 2,
      edits: [_edit(2)],
      orderPending: [1, 2],
      items: [_line('Salad', pos: 3, mark: KdsEditLineMark.added, edit: 2)],
    );
    expect(round.change!.alsoAcknowledges, [1]);
    final view = kdsChangeChitView(
      orderId: 'o1',
      upToEditNumber: round.change!.upToEditNumber,
      board: [
        round,
        original,
        _unit(station: 'other-order', withChange: false),
      ],
      facts: _proxy(),
    )!;
    expect(view.editNumber, 2);
    expect(
      [for (final c in view.changes) (c as OrderChangeRemoved).was.name],
      ['Fries'],
    );
  });

  test('another order\'s units never join the chit', () {
    final other = KdsTicketView(
      kitchenTicketId: 'o2:grill',
      stationId: 'grill',
      orderId: 'o2',
      orderNumber: '#FFF000',
      status: KitchenTicketStatus.acknowledged,
      items: const [],
      change: KdsTicketChange(
        pendingEdits: [_edit(1)],
        removed: [_removed('Soup', edit: 1)],
      ),
    );
    final view = kdsChangeChitView(
      orderId: 'o1',
      upToEditNumber: 1,
      board: [
        other,
        _unit(edits: [_edit(1)], removed: [_removed('Fries', edit: 1)]),
      ],
      facts: _localJob(),
    )!;
    expect(view.orderCode, '#ABC123');
    expect(
      [for (final c in view.changes) (c as OrderChangeRemoved).was.name],
      ['Fries'],
    );
  });

  test('N filter: with changes 1 and 3 pending, "Got it" up to 2 prints '
      'change 1 only', () {
    final view = kdsChangeChitView(
      orderId: 'o1',
      upToEditNumber: 2,
      board: [
        _unit(
          edits: [_edit(1), _edit(3)],
          removed: [_removed('Fries', edit: 1), _removed('Cola', edit: 3)],
          items: [_line('Salad', pos: 2, mark: KdsEditLineMark.added, edit: 3)],
        ),
      ],
      facts: _localJob(),
    )!;
    expect(view.changes, hasLength(1));
    expect((view.changes.single as OrderChangeRemoved).was.name, 'Fries');
  });

  test('watermark: a paper that already shows change 1 gets no chit for '
      'N = 1', () {
    final board = [
      _unit(edits: [_edit(1)], removed: [_removed('Fries', edit: 1)]),
    ];
    expect(
      kdsChangeChitView(
        orderId: 'o1',
        upToEditNumber: 1,
        board: board,
        facts: _localJob(through: 1),
      ),
      isNull,
    );
    expect(
      kdsChangeChitView(
        orderId: 'o1',
        upToEditNumber: 1,
        board: board,
        facts: _localJob(),
      ),
      isNotNull,
    );
  });

  test('no local job (restart / printed elsewhere): a line removed from a '
      '`submitted` unit is excluded, one removed while `preparing` prints; '
      'a unit still in New prints nothing', () {
    final view = kdsChangeChitView(
      orderId: 'o1',
      upToEditNumber: 2,
      board: [
        _unit(
          status: KitchenTicketStatus.inPreparation,
          edits: [_edit(1), _edit(2)],
          removed: [
            _removed('Fries', edit: 1, stage: 'submitted'),
            _removed('Cola', edit: 2, stage: 'preparing'),
          ],
        ),
      ],
      facts: _proxy(),
    )!;
    expect(
      [for (final c in view.changes) (c as OrderChangeRemoved).was.name],
      ['Cola'],
    );
    expect(
      kdsChangeChitView(
        orderId: 'o1',
        upToEditNumber: 2,
        board: [
          _unit(
            status: KitchenTicketStatus.newTicket,
            removed: [_removed('Cola', edit: 2, stage: 'preparing')],
          ),
        ],
        facts: _proxy(),
      ),
      isNull,
    );
  });

  test('a standalone emptied unit (former stage preparing) prints every '
      'removed line under REMOVED', () async {
    final en = await _l10n('en');
    final view = kdsChangeChitView(
      orderId: 'o1',
      upToEditNumber: 2,
      board: [
        _unit(
          status: KitchenTicketStatus.inPreparation,
          standalone: true,
          emptied: true,
          formerStage: 'preparing',
          removed: [
            _removed('Burger', qty: 2, edit: 2, stage: 'preparing'),
            _removed('Fries', edit: 2, stage: 'preparing'),
          ],
        ),
      ],
      facts: _proxy(),
    )!;
    final texts = _texts(buildKdsChangeChitDocument(en, view));
    expect(texts, containsAllInOrder(['REMOVED', '2 × Burger', '1 × Fries']));
    expect(texts, isNot(contains('CHANGE')));
    expect(texts, isNot(contains('ADD')));
  });

  test('no order code -> no chit', () {
    expect(
      kdsChangeChitView(
        orderId: 'o1',
        upToEditNumber: 2,
        board: [
          _unit(orderNumber: null, removed: [_removed('Fries', edit: 2)]),
        ],
        facts: _localJob(),
      ),
      isNull,
    );
  });

  test('MONEY-FREE: no money token on the chit and an empty right column; '
      'the chit and "Got it" sources read no money, staff or session '
      'field', () async {
    final en = await _l10n('en');
    final doc = buildKdsChangeChitDocument(
      en,
      kdsChangeChitView(
        orderId: 'o1',
        upToEditNumber: 2,
        board: [_acceptedMix()],
        facts: _localJob(),
      )!,
      restaurantName: 'Dana Grill',
    );
    final blob = _texts(doc).join('\n').toLowerCase();
    for (final token in _moneyTokens) {
      expect(blob, isNot(contains(token)), reason: 'money token: $token');
    }
    expect(
      [for (final l in doc.lines) l.right ?? ''].where((r) => r.isNotEmpty),
      isEmpty,
    );

    final forbidden = [
      RegExp('_minor'),
      RegExp('employee', caseSensitive: false),
      RegExp('staff', caseSensitive: false),
      RegExp(r"\[\s*'(pin_session_id|membership_id|device_id)'\s*\]"),
    ];
    for (final path in const [
      'lib/src/print/kds_change_chit.dart',
      'lib/src/state/kds_edit_ack_controller.dart',
    ]) {
      final code = [
        for (final line in File(path).readAsLinesSync())
          if (!line.trimLeft().startsWith('//')) line,
      ].join('\n');
      for (final pattern in forbidden) {
        expect(
          pattern.hasMatch(code),
          isFalse,
          reason: '$path must not read ${pattern.pattern}',
        );
      }
    }
  });

  for (final code in const ['ar', 'he']) {
    test('$code: the chit carries only localized chrome and takes the raster '
        'path (Q-015)', () async {
      final l10n = await _l10n(code);
      final en = await _l10n('en');
      final view = kdsChangeChitView(
        orderId: 'o1',
        upToEditNumber: 2,
        board: [_acceptedMix()],
        facts: _localJob(),
      )!;
      final doc = buildKdsChangeChitDocument(l10n, view);
      final texts = _texts(doc);
      expect(
        texts,
        contains(
          '*** ${l10n.kitchenChangeSlipTitle} · '
          '${l10n.kitchenEditChangeNumber(2)} ***',
        ),
      );
      expect(texts, contains(l10n.kitchenEditRemovedLabel));
      expect(texts, contains(l10n.kitchenChangeSlipChangeLabel));
      expect(texts, contains(l10n.kitchenChangeSlipAddLabel));
      final blob = texts.join('\n');
      for (final english in [
        en.kitchenChangeSlipTitle,
        en.kitchenEditRemovedLabel,
        en.kitchenChangeSlipChangeLabel,
        en.kitchenChangeSlipAddLabel,
        '${en.kitchenChangeSlipWasLabel}:',
        '${en.kitchenChangeSlipNowLabel}:',
        en.kitchenEditChangeNumber(2),
        en.kitchenChangeSlipReasonLabel,
        en.orderEditReasonCustomerChangedMind,
      ]) {
        expect(blob, isNot(contains(english)), reason: 'English: $english');
      }
      expect(
        printDocumentNeedsRaster(kitchenTicketToEscPosDocument(doc)),
        isTrue,
      );
    });
  }

  test('an empty board -> no chit', () {
    final OrderChangeSlipView? view = kdsChangeChitView(
      orderId: 'o1',
      upToEditNumber: 2,
      board: const [],
      facts: _localJob(),
    );
    expect(view, isNull);
  });
}
