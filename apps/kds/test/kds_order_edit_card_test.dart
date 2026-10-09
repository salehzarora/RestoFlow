import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_kds/src/widgets/kds_status_chip.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDER-EDIT-001D (design §7.2, API_CONTRACT §4.46) — a KDS card carrying an
/// unconfirmed sent-order change, through the production KdsScreen ->
/// KdsBoard -> KdsTicketCard path: the amber change header, the line badges
/// (NEW / +N / CHANGED was / REMAKE instead of), struck REMOVED lines, the
/// standalone and emptied card, the "Change N · Round M" pill, and "Got it"
/// replacing the advance / Acknowledge action with its pending / failed
/// states. A red cancellation card never shows change UI.

const _id = 'o1:unassigned';

Future<AppLocalizations> _l10n([String locale = 'en']) =>
    AppLocalizations.delegate.load(Locale(locale));

KdsOrderEdit _edit(
  int number, {
  String? reasonCode = 'customer_changed_mind',
  String? reasonText,
  DateTime? createdAt,
  bool withTime = true,
}) => KdsOrderEdit(
  id: 'o1-e$number',
  orderId: 'o1',
  editNumber: number,
  channel: KdsEditChannel.kds,
  ackRequired: true,
  createdAt: withTime
      ? (createdAt ?? DateTime.utc(2026, 10, 8, 10, 20 + number))
      : null,
  reasonCode: reasonCode,
  reasonText: reasonText,
);

KdsTicketChange _change({
  List<KdsOrderEdit>? edits,
  List<KdsRemovedLine> removed = const [],
  bool standalone = false,
  bool emptied = false,
  String? formerStage,
  List<int>? orderPending,
}) {
  final pending = edits ?? [_edit(1)];
  return KdsTicketChange(
    pendingEdits: pending,
    removed: removed,
    standalone: standalone,
    emptied: emptied,
    formerStage: formerStage,
    orderPendingEditNumbers:
        orderPending ?? [for (final e in pending) e.editNumber],
  );
}

KdsTicketView _card({
  KitchenTicketStatus status = KitchenTicketStatus.inPreparation,
  String orderType = 'dine_in',
  List<KdsItemView> items = const [KdsItemView(name: 'Burger', quantity: 2)],
  KdsTicketChange? change,
  String? roundId,
  int? roundNumber,
  int? openedByEditNumber,
  String? voidedFromStatus,
  List<KitchenCount> kitchenCounts = const [],
}) => KdsTicketView(
  kitchenTicketId: roundId == null ? _id : '$_id:r$roundId',
  stationId: 'unassigned',
  orderId: 'o1',
  orderNumber: '#ABC123',
  orderType: orderType,
  status: status,
  submittedAt: DateTime.utc(2026, 10, 8, 10),
  voidedAt: voidedFromStatus == null ? null : DateTime.utc(2026, 10, 8, 10, 40),
  voidedFromStatus: voidedFromStatus,
  roundId: roundId,
  roundNumber: roundNumber,
  openedByEditNumber: openedByEditNumber,
  kitchenCounts: kitchenCounts,
  items: items,
  change: change,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<KdsTicketView> tickets,
  void Function(KdsTicketView)? onGotIt,
  Set<String> pending = const <String>{},
  Set<String> failed = const <String>{},
  void Function(KdsTicketView)? onAckCancellation,
  KdsTicketPrintStatus? Function(KdsTicketView)? printStatusFor,
  void Function(KdsTicketView)? onReprint,
  Locale locale = const Locale('en'),
}) async {
  // A tall NARROW board: one stacked column list that builds every card.
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: KdsScreen(
        tickets: tickets,
        allowRecall: false,
        onAcknowledgeChange: onGotIt,
        changeAckPendingKeys: pending,
        changeAckFailedKeys: failed,
        onAcknowledgeCancellation: onAckCancellation,
        printStatusFor: printStatusFor,
        onReprint: onReprint,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _time(WidgetTester tester, DateTime at) => MaterialLocalizations.of(
  tester.element(find.byType(KdsScreen)),
).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));

String? _textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data;

FilledButton _gotItButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('kds-edit-ack-$_id')));

void main() {
  group('the amber change header', () {
    testWidgets('CHANGED, then "Change 2 · time · reason" for the edit', (
      tester,
    ) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        tickets: [
          _card(change: _change(edits: [_edit(2)])),
        ],
        onGotIt: (_) {},
      );
      expect(find.byKey(const Key('kds-change-header-$_id')), findsOneWidget);
      expect(find.text(l10n.kdsEditChangedLabel), findsOneWidget);
      final time = _time(tester, DateTime.utc(2026, 10, 8, 10, 22));
      expect(
        _textOf(tester, const Key('kds-change-edit-$_id|e2')),
        '${l10n.kitchenEditChangeNumber(2)} · $time · '
        '${l10n.orderEditReasonCustomerChangedMind}',
      );
    });

    testWidgets('the reason follows the change-slip rule: "other" shows its '
        'free text (else its label); a known code with text shows both; an '
        'unknown code NEVER shows its wire value', (tester) async {
      final l10n = await _l10n();
      Future<String?> row(KdsOrderEdit edit) async {
        await _pump(
          tester,
          tickets: [
            _card(change: _change(edits: [edit])),
          ],
        );
        return _textOf(tester, const Key('kds-change-edit-$_id|e1'));
      }

      final change1 = l10n.kitchenEditChangeNumber(1);
      final other = await row(
        _edit(1, reasonCode: 'other', reasonText: 'Guest allergic'),
      );
      final time = _time(tester, DateTime.utc(2026, 10, 8, 10, 21));
      expect(other, '$change1 · $time · Guest allergic');
      expect(
        await row(_edit(1, reasonCode: 'other')),
        '$change1 · $time · ${l10n.orderEditReasonOther}',
      );
      expect(
        await row(_edit(1, reasonCode: 'item_unavailable', reasonText: 'x')),
        '$change1 · $time · ${l10n.orderEditReasonItemUnavailable} · x',
      );
      expect(
        await row(_edit(1, reasonCode: 'comped_by_manager')),
        '$change1 · $time',
      );
      expect(find.textContaining('comped_by_manager'), findsNothing);
      expect(
        await row(_edit(1, reasonCode: 'comped_by_manager', reasonText: 'y')),
        '$change1 · $time · y',
      );
      expect(find.textContaining('comped_by_manager'), findsNothing);
      // No honest time on the wire => no time, never a fabricated one.
      expect(
        await row(_edit(1, withTime: false)),
        '$change1 · ${l10n.orderEditReasonCustomerChangedMind}',
      );
    });

    testWidgets('two pending edits render two rows, oldest first', (
      tester,
    ) async {
      await _pump(
        tester,
        tickets: [
          _card(change: _change(edits: [_edit(1), _edit(3)])),
        ],
      );
      final e1 = find.byKey(const Key('kds-change-edit-$_id|e1'));
      final e3 = find.byKey(const Key('kds-change-edit-$_id|e3'));
      expect(e1, findsOneWidget);
      expect(e3, findsOneWidget);
      expect(tester.getTopLeft(e1).dy, lessThan(tester.getTopLeft(e3).dy));
    });
  });

  group('line marks', () {
    testWidgets('NEW leads an added line; "+1" leads a name-only delta row '
        'next to the kept line', (tester) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        tickets: [
          _card(
            items: const [
              KdsItemView(name: 'Burger', quantity: 2, linePosition: 1),
              KdsItemView(
                name: 'Burger',
                quantity: 1,
                linePosition: 1,
                editMark: KdsEditLineMark.increased,
                editNumber: 1,
              ),
              KdsItemView(
                name: 'Soup',
                quantity: 1,
                linePosition: 2,
                editMark: KdsEditLineMark.added,
                editNumber: 1,
              ),
            ],
            change: _change(),
          ),
        ],
      );
      expect(find.text(l10n.kdsEditNewBadge), findsOneWidget);
      expect(find.text('Soup ×1'), findsOneWidget);
      expect(find.text(l10n.kdsEditQuantityIncrease(1)), findsOneWidget);
      // The delta row's quantity IS the increase: the line names the dish.
      expect(find.text('Burger'), findsOneWidget);
      expect(find.text('Burger ×1'), findsNothing);
      expect(find.text('Burger ×2'), findsOneWidget);
    });

    testWidgets('CHANGED shows "was: 3× Burger +Tomato" ONCE for a two-line '
        'group sharing one old line', (tester) async {
      final l10n = await _l10n();
      const was = KdsItemView(
        name: 'Burger',
        quantity: 3,
        modifiers: ['Tomato'],
        orderItemId: 'x1',
      );
      await _pump(
        tester,
        tickets: [
          _card(
            items: const [
              KdsItemView(
                name: 'Burger',
                quantity: 2,
                modifiers: ['Tomato'],
                orderItemId: 'x2',
                editMark: KdsEditLineMark.changed,
                editWas: was,
                editNumber: 1,
              ),
              KdsItemView(
                name: 'Burger',
                quantity: 1,
                orderItemId: 'x3',
                editMark: KdsEditLineMark.changed,
                editWas: was,
                editNumber: 1,
              ),
            ],
            change: _change(),
          ),
        ],
      );
      expect(find.text(l10n.kdsEditWas('3× Burger +Tomato')), findsOneWidget);
      expect(find.text('was: 3× Burger +Tomato'), findsOneWidget);
      // The header word + one badge per changed line.
      expect(find.text(l10n.kdsEditChangedLabel), findsNWidgets(3));
      expect(find.text('Burger ×2'), findsOneWidget);
      expect(find.text('Burger ×1'), findsOneWidget);
    });

    testWidgets('REMAKE + "instead of" is PERMANENT: still shown with no '
        'pending change (and the normal action is back)', (tester) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        tickets: [
          _card(
            status: KitchenTicketStatus.newTicket,
            roundId: 'r2',
            roundNumber: 2,
            openedByEditNumber: 1,
            items: const [
              KdsItemView(
                name: 'Burger',
                quantity: 1,
                editMark: KdsEditLineMark.remake,
                editWas: KdsItemView(
                  name: 'Burger',
                  quantity: 1,
                  modifiers: ['Tomato'],
                ),
                editNumber: 1,
              ),
            ],
          ),
        ],
        onGotIt: (_) {},
      );
      expect(find.text(l10n.kdsEditRemake), findsOneWidget);
      expect(
        find.text(l10n.kdsEditInsteadOf('1× Burger +Tomato')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('kds-change-header-$_id:rr2')), findsNothing);
      expect(find.text(l10n.kdsEditGotIt), findsNothing);
      expect(find.text(l10n.kdsAcknowledgeAction), findsOneWidget);
    });

    testWidgets('a REMOVED line is struck through in words: the REMOVED pill, '
        'the old line and its modifiers, and "Remade in Round 3"', (
      tester,
    ) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        tickets: [
          _card(
            change: _change(
              removed: const [
                KdsRemovedLine(
                  line: KdsItemView(
                    name: 'Fries',
                    quantity: 1,
                    modifiers: ['Salt'],
                  ),
                  editNumber: 1,
                  removedKitchenStage: 'preparing',
                  remadeInRoundNumber: 3,
                ),
              ],
            ),
          ),
        ],
      );
      expect(find.text(l10n.kitchenEditRemovedLabel), findsOneWidget);
      final struck = tester.widget<Text>(find.text('Fries ×1')).style!;
      expect(struck.decoration, TextDecoration.lineThrough);
      expect(
        tester.widget<Text>(find.text('+ Salt')).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.text(l10n.kdsEditRemadeInRound(3)), findsOneWidget);
      // The live line stays a plain line.
      expect(
        tester.widget<Text>(find.text('Burger ×2')).style!.decoration,
        isNot(TextDecoration.lineThrough),
      );
    });
  });

  group('"Got it" replaces the advance action', () {
    final cases =
        <
          (
            String,
            KitchenTicketStatus,
            String,
            String Function(AppLocalizations),
          )
        >[
          (
            'New (no Acknowledge)',
            KitchenTicketStatus.newTicket,
            'dine_in',
            (l) => l.kdsAcknowledgeAction,
          ),
          (
            'acknowledged (no Start)',
            KitchenTicketStatus.acknowledged,
            'dine_in',
            (l) => l.kdsStartAction,
          ),
          (
            'in preparation (no Ready)',
            KitchenTicketStatus.inPreparation,
            'dine_in',
            (l) => l.kdsReadyAction,
          ),
          (
            'ready takeaway (no Picked up)',
            KitchenTicketStatus.ready,
            'takeaway',
            (l) => l.kdsPickedUpAction,
          ),
          (
            'ready dine-in (no Served)',
            KitchenTicketStatus.ready,
            'dine_in',
            (l) => l.kdsServedAction,
          ),
        ];
    for (final (name, status, orderType, advanceLabel) in cases) {
      testWidgets(name, (tester) async {
        final l10n = await _l10n();
        await _pump(
          tester,
          tickets: [
            _card(status: status, orderType: orderType, change: _change()),
          ],
          onGotIt: (_) {},
        );
        expect(find.byKey(const Key('kds-edit-ack-$_id')), findsOneWidget);
        expect(find.text(l10n.kdsEditGotIt), findsOneWidget);
        expect(find.text(advanceLabel(l10n)), findsNothing);
        // The same card WITHOUT a change shows the advance action again.
        await _pump(
          tester,
          tickets: [_card(status: status, orderType: orderType)],
          onGotIt: (_) {},
        );
        expect(find.text(advanceLabel(l10n)), findsOneWidget);
        expect(find.text(l10n.kdsEditGotIt), findsNothing);
      });
    }
  });

  group('"Got it" states', () {
    testWidgets('a tap calls the callback ONCE with the card', (tester) async {
      final taps = <KdsTicketView>[];
      final card = _card(change: _change());
      await _pump(tester, tickets: [card], onGotIt: taps.add);
      await tester.tap(find.byKey(const Key('kds-edit-ack-$_id')));
      await tester.pumpAndSettle();
      expect(taps, [same(card)]);
    });

    testWidgets('pending: disabled, the localized pending label, a static '
        'glyph, and no tap reaches the callback', (tester) async {
      final l10n = await _l10n();
      final taps = <KdsTicketView>[];
      await _pump(
        tester,
        tickets: [_card(change: _change())],
        onGotIt: taps.add,
        pending: {'$_id|e1'},
      );
      expect(_gotItButton(tester).onPressed, isNull);
      expect(find.text(l10n.kdsAckPending), findsOneWidget);
      expect(find.text(l10n.kdsEditGotIt), findsNothing);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('kds-edit-ack-$_id')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(taps, isEmpty);
    });

    testWidgets('failed: the failure line shows and "Got it" stays enabled', (
      tester,
    ) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        tickets: [_card(change: _change())],
        onGotIt: (_) {},
        failed: {'$_id|e1'},
      );
      expect(find.byKey(const Key('kds-edit-ack-failed-$_id')), findsOneWidget);
      expect(find.text(l10n.kdsAckFailed), findsOneWidget);
      expect(_gotItButton(tester).onPressed, isNotNull);
      expect(find.text(l10n.kdsEditGotIt), findsOneWidget);
    });

    testWidgets('the caption names the older pending edits this tap also '
        'confirms', (tester) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        tickets: [
          _card(
            change: _change(edits: [_edit(2)], orderPending: [1, 2]),
          ),
        ],
        onGotIt: (_) {},
      );
      expect(find.text(l10n.kdsEditAlsoConfirms('1')), findsOneWidget);
      expect(find.text('Also confirms change 1'), findsOneWidget);
      // No older pending edit => no caption.
      await _pump(
        tester,
        tickets: [_card(change: _change())],
        onGotIt: (_) {},
      );
      expect(find.byKey(const Key('kds-edit-also-$_id')), findsNothing);
    });

    testWidgets('a null callback renders NEITHER "Got it" NOR an advance '
        'button — never a dead or refused control', (tester) async {
      final l10n = await _l10n();
      await _pump(
        tester,
        tickets: [
          _card(status: KitchenTicketStatus.newTicket, change: _change()),
        ],
      );
      expect(find.byKey(const Key('kds-change-header-$_id')), findsOneWidget);
      expect(find.text(l10n.kdsEditGotIt), findsNothing);
      expect(find.text(l10n.kdsAcknowledgeAction), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  testWidgets('a standalone EMPTIED card: the title and stop body, no live '
      'items, no counts, no status chip, no print status and no Reprint — '
      'but the REMOVED lines and "Got it"', (tester) async {
    final l10n = await _l10n();
    await _pump(
      tester,
      tickets: [
        _card(
          items: const [],
          kitchenCounts: const [KitchenCount(label: 'Patty', quantity: 2)],
          change: _change(
            standalone: true,
            emptied: true,
            formerStage: 'preparing',
            removed: const [
              KdsRemovedLine(
                line: KdsItemView(name: 'Burger', quantity: 2),
                editNumber: 1,
                removedKitchenStage: 'preparing',
              ),
            ],
          ),
        ),
      ],
      onGotIt: (_) {},
      printStatusFor: (_) => const KdsTicketPrintStatus(label: 'sent'),
      onReprint: (_) {},
    );
    expect(find.text(l10n.kdsEditAllItemsRemovedTitle), findsOneWidget);
    expect(find.text(l10n.kdsEditAllItemsRemovedBody), findsOneWidget);
    expect(find.text(l10n.kdsEditChangedLabel), findsNothing);
    expect(find.text(l10n.kitchenEditRemovedLabel), findsOneWidget);
    expect(find.text('Burger ×2'), findsOneWidget);
    expect(find.byKey(const Key('kds-kitchen-counts')), findsNothing);
    expect(find.byKey(const Key('kds-reprint-$_id')), findsNothing);
    expect(find.byKey(const Key('ticket-print-status')), findsNothing);
    expect(find.byType(KdsStatusChip), findsNothing);
    expect(find.text(l10n.kdsEditGotIt), findsOneWidget);
    // The full-card amber treatment (words carry the signal; colour adds).
    final theme = Theme.of(tester.element(find.byType(KdsScreen)));
    final card = tester.widget<Card>(
      find.descendant(
        of: find.byKey(const ValueKey('kds-card-$_id')),
        matching: find.byType(Card),
      ),
    );
    expect(card.color, RestoflowTone.warning.styleOf(theme).container);
  });

  testWidgets('a NON-standalone changed card keeps its counts, status chip, '
      'print status and Reprint', (tester) async {
    await _pump(
      tester,
      tickets: [
        _card(
          kitchenCounts: const [KitchenCount(label: 'Patty', quantity: 2)],
          change: _change(),
        ),
      ],
      onGotIt: (_) {},
      printStatusFor: (_) => const KdsTicketPrintStatus(label: 'sent'),
      onReprint: (_) {},
    );
    expect(find.byKey(const Key('kds-kitchen-counts')), findsOneWidget);
    expect(find.byKey(const Key('kds-reprint-$_id')), findsOneWidget);
    expect(find.byKey(const Key('ticket-print-status')), findsOneWidget);
    expect(find.byType(KdsStatusChip), findsOneWidget);
  });

  testWidgets('the round pill reads "Change 2 · Round 3" for a round opened '
      'by an edit, "Addition · Round 3" otherwise', (tester) async {
    final l10n = await _l10n();
    await _pump(
      tester,
      tickets: [
        _card(roundId: 'r3', roundNumber: 3, openedByEditNumber: 2),
        _card(roundId: 'r4', roundNumber: 3),
      ],
    );
    expect(
      tester
          .widget<RestoflowStatusPill>(
            find.byKey(const Key('kds-round-$_id:rr3')),
          )
          .label,
      '${l10n.kitchenEditChangeNumber(2)} · ${l10n.kdsRoundLabel(3)}',
    );
    expect(find.text('Change 2 · Round 3'), findsOneWidget);
    expect(
      tester
          .widget<RestoflowStatusPill>(
            find.byKey(const Key('kds-round-$_id:rr4')),
          )
          .label,
      '${l10n.kdsAdditionLabel} · ${l10n.kdsRoundLabel(3)}',
    );
  });

  testWidgets('a red cancellation card NEVER shows change UI (a void '
      'supersedes every pending edit)', (tester) async {
    final l10n = await _l10n();
    await _pump(
      tester,
      tickets: [
        _card(
          status: KitchenTicketStatus.cancelled,
          voidedFromStatus: 'preparing',
          items: const [
            KdsItemView(
              name: 'Soup',
              quantity: 1,
              editMark: KdsEditLineMark.added,
              editNumber: 1,
            ),
          ],
          change: _change(
            removed: const [
              KdsRemovedLine(
                line: KdsItemView(name: 'Fries', quantity: 1),
                editNumber: 1,
              ),
            ],
          ),
        ),
      ],
      onGotIt: (_) {},
      onAckCancellation: (_) {},
    );
    expect(find.text(l10n.kdsCancelledCardTitle), findsOneWidget);
    expect(find.byKey(const Key('kds-ack-$_id')), findsOneWidget);
    expect(find.byKey(const Key('kds-change-header-$_id')), findsNothing);
    expect(find.text(l10n.kdsEditGotIt), findsNothing);
    expect(find.text(l10n.kitchenEditRemovedLabel), findsNothing);
    expect(find.text(l10n.kdsEditNewBadge), findsNothing);
    expect(find.text('Fries ×1'), findsNothing);
    expect(find.text('Soup ×1'), findsOneWidget);
  });

  for (final code in ['ar', 'he']) {
    testWidgets('$code: RTL, localized "Got it" / REMOVED / CHANGED chrome, no '
        'English chrome', (tester) async {
      final l10n = await _l10n(code);
      final en = await _l10n();
      await _pump(
        tester,
        locale: Locale(code),
        tickets: [
          _card(
            items: const [
              KdsItemView(
                name: 'Burger',
                quantity: 1,
                editMark: KdsEditLineMark.added,
                editNumber: 2,
              ),
            ],
            change: _change(
              edits: [_edit(2)],
              orderPending: [1, 2],
              removed: const [
                KdsRemovedLine(
                  line: KdsItemView(name: 'Fries', quantity: 1),
                  editNumber: 2,
                  remadeInRoundNumber: 3,
                ),
              ],
            ),
          ),
        ],
        onGotIt: (_) {},
      );
      expect(
        Directionality.of(tester.element(find.byType(KdsTicketCard))),
        TextDirection.rtl,
      );
      // Scoped to the card: in he the NEW badge reads like the New column.
      Finder onCard(String text) => find.descendant(
        of: find.byType(KdsTicketCard),
        matching: find.text(text),
      );
      expect(onCard(l10n.kdsEditGotIt), findsOneWidget);
      expect(onCard(l10n.kitchenEditRemovedLabel), findsOneWidget);
      expect(onCard(l10n.kdsEditChangedLabel), findsOneWidget);
      expect(onCard(l10n.kdsEditNewBadge), findsOneWidget);
      expect(onCard(l10n.kdsEditAlsoConfirms('1')), findsOneWidget);
      expect(onCard(l10n.kdsEditRemadeInRound(3)), findsOneWidget);
      for (final english in [
        en.kdsEditGotIt,
        en.kitchenEditRemovedLabel,
        en.kdsEditChangedLabel,
        en.kdsEditNewBadge,
        en.kdsEditAlsoConfirms('1'),
        en.kdsEditRemadeInRound(3),
        en.orderEditReasonCustomerChangedMind,
      ]) {
        expect(find.textContaining(english), findsNothing, reason: english);
      }
      expect(find.textContaining('Change 2'), findsNothing);
    });
  }
}
