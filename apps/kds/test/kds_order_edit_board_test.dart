import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDER-EDIT-001D (design §7.2) — sent-order changes on the KDS BOARD:
/// a standalone change card sits in its former column, the change pulse is
/// keyed by (work unit, edit number) so a second edit pulses again, a
/// standalone card is never announced as a "New order", and the real
/// mapper's rows reach the card end to end (a void supersedes every edit).

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

// ---------------------------------------------------------------------------
// Hand-built cards (pulse + badge rules).
// ---------------------------------------------------------------------------
KdsOrderEdit _edit(int number) => KdsOrderEdit(
  id: 'o1-e$number',
  orderId: 'o1',
  editNumber: number,
  channel: KdsEditChannel.kds,
  ackRequired: true,
  createdAt: DateTime.utc(2026, 10, 8, 10, 20 + number),
  reasonCode: 'customer_changed_mind',
);

KdsTicketView _card({
  List<int>? edits,
  bool standalone = false,
  KitchenTicketStatus status = KitchenTicketStatus.inPreparation,
}) => KdsTicketView(
  kitchenTicketId: 'o1:unassigned',
  stationId: 'unassigned',
  orderId: 'o1',
  orderNumber: '#ABC123',
  orderType: 'dine_in',
  status: status,
  submittedAt: DateTime.utc(2026, 10, 8, 10),
  items: standalone
      ? const []
      : const [KdsItemView(name: 'Burger', quantity: 2)],
  change: edits == null
      ? null
      : KdsTicketChange(
          pendingEdits: [for (final n in edits) _edit(n)],
          removed: const [
            KdsRemovedLine(
              line: KdsItemView(name: 'Fries', quantity: 1),
              editNumber: 1,
            ),
          ],
          standalone: standalone,
          emptied: standalone,
          orderPendingEditNumbers: edits,
        ),
);

Widget _screen(
  List<KdsTicketView> tickets, {
  bool reduceMotion = false,
  void Function(KdsTicketView)? onGotIt,
  void Function(KdsTicketView)? onAckCancellation,
  bool enableAlert = true,
}) => MaterialApp(
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  theme: restoflowBaseTheme(brightness: Brightness.dark),
  builder: (context, child) => reduceMotion
      ? MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        )
      : child!,
  home: KdsScreen(
    tickets: tickets,
    allowRecall: false,
    enableNewArrivalAlert: enableAlert,
    newArrivalWindow: const Duration(milliseconds: 120),
    onAcknowledgeChange: onGotIt,
    onAcknowledgeCancellation: onAckCancellation,
  ),
);

/// The WIDE board (side-by-side columns) so every column is built.
void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _inColumn(String column, String ticketId) => find.descendant(
  of: find.byKey(Key('kds-col-$column')),
  matching: find.byKey(ValueKey('kds-card-$ticketId')),
);

// ---------------------------------------------------------------------------
// Server-shaped pull rows (the shared overlay test's builders, trimmed): the
// kitchen redaction strips every `*_minor` key; an `order_edits` row carries
// staff / session / device columns the KDS never plucks.
// ---------------------------------------------------------------------------
const _org = '00000000-0000-4000-8000-00000000000a';
const _o1 = '11111111-0000-4000-8000-0000000000a1';
const _e1 = '55555555-0000-4000-8000-0000000000e1';
const _t0 = '2026-10-08T10:00:00Z';
const _tEdit = '2026-10-08T10:20:00Z';
const _tAck = '2026-10-08T10:30:00Z';

String _oid(int n) => '1111111$n-0000-4000-8000-0000000000a$n';
String _eid(int n) => '5555555$n-0000-4000-8000-0000000000e$n';

Map<String, dynamic> _order(
  String id, {
  String status = 'preparing',
  int editCount = 1,
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'organization_id': _org,
  'status': status,
  'order_type': 'dine_in',
  'table_id': null,
  'notes': null,
  'customer_name': null,
  'dispatch_mode': 'kds',
  'kitchen_ack_required': false,
  'kitchen_ack_at': null,
  'voided_at': null,
  'voided_from_status': null,
  'edit_count': editCount,
  'client_created_at': _t0,
  'created_at': _t0,
  'updated_at': _t0,
  'deleted_at': null,
  ...extra,
};

Map<String, dynamic> _item(
  String id,
  String orderId, {
  required String name,
  int qty = 1,
  String status = 'pending',
  int linePosition = 1,
}) => {
  'id': id,
  'organization_id': _org,
  'order_id': orderId,
  'station_id': null,
  'status': status,
  'quantity': qty,
  'menu_item_name_snapshot': name,
  'notes': null,
  'service_round_id': null,
  'line_position': linePosition,
  'category_display_order_snapshot': 1,
  'item_display_order_snapshot': linePosition,
  'edit_id': null,
  'removed_by_edit_id': null,
  'replaces_order_item_id': null,
  'removed_kitchen_stage': null,
  'created_at': _t0,
  'updated_at': _t0,
  'deleted_at': null,
};

/// The row as `app.edit_order` leaves it after retiring it.
Map<String, dynamic> _retired(
  Map<String, dynamic> row, {
  required String by,
  required String? stage,
}) => {
  ...row,
  'status': stage == 'submitted' ? 'cancelled' : 'voided',
  'removed_by_edit_id': by,
  'removed_kitchen_stage': stage,
  'updated_at': _tEdit,
};

Map<String, dynamic> _editRow(String id, String orderId, {String? ackAt}) => {
  'id': id,
  'organization_id': _org,
  'order_id': orderId,
  'edit_number': 1,
  'device_id': 'pos-device-1',
  'pin_session_id': 'pin-session-cashier',
  'employee_profile_id': 'emp-cashier',
  'reason_code': 'customer_changed_mind',
  'reason_text': null,
  'kitchen_channel': 'kds',
  'kitchen_ack_required': true,
  'kitchen_ack_at': ackAt,
  'client_created_at': _tEdit,
  'created_at': _tEdit,
  'updated_at': ackAt ?? _tEdit,
  'deleted_at': null,
};

List<KdsTicketView> _map({
  required List<Map<String, dynamic>> orders,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> edits,
}) => KdsTicketMapper.map(
  orders: orders,
  orderItems: items,
  modifiers: const [],
  tables: const [],
  serviceRounds: const [],
  orderEdits: edits,
);

void main() {
  testWidgets('a STANDALONE change card sits in its former column: submitted '
      '-> New, accepted / preparing -> Preparing, ready -> Ready, unknown -> '
      'New (real mapper rows: completed orders whose removal is unconfirmed)', (
    tester,
  ) async {
    _wide(tester);
    const stages = <String?>['submitted', 'accepted', 'preparing', 'ready'];
    final orders = <Map<String, dynamic>>[];
    final items = <Map<String, dynamic>>[];
    final edits = <Map<String, dynamic>>[];
    for (var n = 1; n <= 5; n++) {
      final stage = n <= stages.length ? stages[n - 1] : null;
      orders.add(_order(_oid(n), status: 'completed'));
      items
        ..add(
          _retired(
            _item('a$n', _oid(n), name: 'Burger'),
            by: _eid(n),
            stage: stage,
          ),
        )
        ..add(_item('b$n', _oid(n), name: 'Fries', linePosition: 2));
      edits.add(_editRow(_eid(n), _oid(n)));
    }
    final board = _map(orders: orders, items: items, edits: edits);
    expect(board, hasLength(5));
    expect(board.every((t) => t.change?.standalone ?? false), isTrue);

    await tester.pumpWidget(_screen(board, onGotIt: (_) {}));
    await tester.pumpAndSettle();
    expect(_inColumn('new', '${_oid(1)}:unassigned'), findsOneWidget);
    expect(_inColumn('preparing', '${_oid(2)}:unassigned'), findsOneWidget);
    expect(_inColumn('preparing', '${_oid(3)}:unassigned'), findsOneWidget);
    expect(_inColumn('ready', '${_oid(4)}:unassigned'), findsOneWidget);
    expect(_inColumn('new', '${_oid(5)}:unassigned'), findsOneWidget);
  });

  group('the change pulse is keyed by (work unit, edit number)', () {
    testWidgets('a change present on the FIRST build does not pulse', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _screen([
          _card(edits: [1]),
        ]),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('kds-change-arrival-o1:unassigned|e1')),
        findsNothing,
      );
    });

    testWidgets('a change ARRIVING later pulses; a second edit pulses AGAIN '
        'under its new key; the acknowledgement removes it', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_screen([_card()]));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _screen([
          _card(edits: [1]),
        ]),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('kds-change-arrival-o1:unassigned|e1')),
        findsOneWidget,
      );
      await tester.pumpAndSettle(); // the finite pulse self-terminates

      // The board's first-seen clock is the WALL clock: let the e1 window
      // elapse for real, so the same card can only pulse again under a NEW
      // key (a ticket-id key would stay silent here).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpWidget(
        _screen([
          _card(edits: [1]),
        ]),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('kds-change-arrival-o1:unassigned|e1')),
        findsNothing,
        reason: 'the same change never pulses twice',
      );

      await tester.pumpWidget(
        _screen([
          _card(edits: [1, 2]),
        ]),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('kds-change-arrival-o1:unassigned|e2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('kds-change-arrival-o1:unassigned|e1')),
        findsNothing,
      );
      await tester.pumpAndSettle();

      // "Got it" confirmed on the server: the pull drops the change.
      await tester.pumpWidget(_screen([_card()]));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'kds-change-arrival-',
              ),
        ),
        findsNothing,
      );
    });

    testWidgets('no pulse at all when the board alert is off (demo)', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(_screen([_card()], enableAlert: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _screen([
          _card(edits: [1]),
        ], enableAlert: false),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('kds-change-arrival-o1:unassigned|e1')),
        findsNothing,
      );
    });

    testWidgets('reduce-motion: a STATIC amber ring stays visible, with no '
        'animation exception', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_screen([_card()], reduceMotion: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _screen([
          _card(edits: [1]),
        ], reduceMotion: true),
      );
      await tester.pumpAndSettle();
      final pulse = find.byKey(
        const Key('kds-change-arrival-o1:unassigned|e1'),
      );
      expect(pulse, findsOneWidget);
      final ring = tester.widget<DecoratedBox>(
        find.descendant(of: pulse, matching: find.byType(DecoratedBox)).first,
      );
      final shadows = (ring.decoration as BoxDecoration).boxShadow!;
      expect(shadows, isNotEmpty);
      final warning = RestoflowSemanticColors.of(Brightness.dark).warning;
      expect(
        shadows.first.color.toARGB32() & 0xFFFFFF,
        warning.toARGB32() & 0xFFFFFF,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('a standalone change card is never a "New order"', () {
    testWidgets('arriving in New, it gets the amber change pulse — never the '
        'New-order badge or glow', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_screen(const []));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _screen([
          _card(
            edits: [1],
            standalone: true,
            status: KitchenTicketStatus.newTicket,
          ),
        ]),
      );
      await tester.pump();
      expect(_inColumn('new', 'o1:unassigned'), findsOneWidget);
      expect(
        find.byKey(const Key('kds-new-badge-o1:unassigned')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('kds-new-arrival-o1:unassigned')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('kds-change-arrival-o1:unassigned|e1')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a NON-standalone changed ticket arriving in New is a new '
        'order: the New-order glow wins over the change pulse', (tester) async {
      _wide(tester);
      await tester.pumpWidget(_screen(const []));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _screen([
          _card(edits: [1], status: KitchenTicketStatus.newTicket),
        ]),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('kds-new-badge-o1:unassigned')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('kds-new-arrival-o1:unassigned')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('kds-change-arrival-o1:unassigned|e1')),
        findsNothing,
      );
      await tester.pumpAndSettle();
    });
  });

  group('end to end through the real mapper', () {
    List<KdsTicketView> preparingWithRemoval({String? ackAt}) => _map(
      orders: [_order(_o1)],
      items: [
        _retired(
          _item('a1', _o1, name: 'Burger'),
          by: _e1,
          stage: 'preparing',
        ),
        _item('b1', _o1, name: 'Fries', linePosition: 2),
      ],
      edits: [_editRow(_e1, _o1, ackAt: ackAt)],
    );

    testWidgets('a pending removal on a preparing order: REMOVED + "Got it", '
        'no Ready', (tester) async {
      _wide(tester);
      final l10n = await _l10n();
      await tester.pumpWidget(_screen(preparingWithRemoval(), onGotIt: (_) {}));
      await tester.pumpAndSettle();
      expect(find.text(l10n.kdsEditChangedLabel), findsOneWidget);
      expect(find.text(l10n.kitchenEditRemovedLabel), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Burger ×1')).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.text('Fries ×1'), findsOneWidget);
      expect(
        find.byKey(const Key('kds-edit-ack-$_o1:unassigned')),
        findsOneWidget,
      );
      expect(find.text(l10n.kdsReadyAction), findsNothing);
    });

    testWidgets('the SAME rows once the edit is confirmed (kitchen_ack_at): '
        'the normal card with its Ready action', (tester) async {
      _wide(tester);
      final l10n = await _l10n();
      await tester.pumpWidget(
        _screen(preparingWithRemoval(ackAt: _tAck), onGotIt: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.kdsReadyAction), findsOneWidget);
      expect(find.text(l10n.kdsEditGotIt), findsNothing);
      expect(find.text(l10n.kitchenEditRemovedLabel), findsNothing);
      expect(find.text('Burger ×1'), findsNothing);
      expect(find.text('Fries ×1'), findsOneWidget);
    });

    testWidgets('a VOIDED order with a pending edit and an edit-retired line: '
        'the red card ONLY — no change header, no "Got it", the retired line '
        'absent', (tester) async {
      _wide(tester);
      final l10n = await _l10n();
      final board = _map(
        orders: [
          _order(
            _o1,
            status: 'voided',
            extra: {
              'kitchen_ack_required': true,
              'voided_at': '2026-10-08T10:40:00Z',
              'voided_from_status': 'preparing',
            },
          ),
        ],
        items: [
          _retired(
            _item('a1', _o1, name: 'Burger', status: 'voided'),
            by: _e1,
            stage: 'preparing',
          ),
          _item('b1', _o1, name: 'Fries', linePosition: 2, status: 'voided'),
        ],
        edits: [_editRow(_e1, _o1)],
      );
      await tester.pumpWidget(
        _screen(board, onGotIt: (_) {}, onAckCancellation: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.kdsCancelledCardTitle), findsOneWidget);
      expect(find.byKey(const Key('kds-ack-$_o1:unassigned')), findsOneWidget);
      expect(
        find.byKey(const Key('kds-change-header-$_o1:unassigned')),
        findsNothing,
      );
      expect(find.text(l10n.kdsEditGotIt), findsNothing);
      expect(find.text(l10n.kitchenEditRemovedLabel), findsNothing);
      expect(find.text('Burger ×1'), findsNothing);
      expect(find.text('Fries ×1'), findsOneWidget);
    });
  });
}
