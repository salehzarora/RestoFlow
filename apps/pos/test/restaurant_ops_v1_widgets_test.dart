import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show DiningTable;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/table_move_repository.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart'
    show tablesProvider;
import 'package:restoflow_pos/src/state/table_move_controller.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';
import 'package:restoflow_pos/src/widgets/move_table_sheet.dart';

/// RESTAURANT-OPERATIONS-V1-001 — POS widget coverage: the unavailable menu
/// tile (visible, explained, not sellable) and the move-table sheet (pick +
/// confirm, honest occupancy, conflict retirement).
void main() {
  group('A. the unavailable menu tile', () {
    Future<AppLocalizations> pump(
      WidgetTester tester,
      DemoMenuItem item, {
      required void Function() onAdd,
    }) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 220,
                    height: 280,
                    child: MenuItemCard(item: item, onAdd: onAdd),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      return l10n;
    }

    const soldOut = DemoMenuItem(
      id: 'x-soldout',
      name: 'Onion Rings',
      priceMinor: 1900,
      categoryId: 'sides',
      categoryName: 'Sides',
      availability: 'unavailable',
      availabilityReason: 'sold_out',
    );

    testWidgets('A1 sold out: visible, explained, takes NO tap', (
      tester,
    ) async {
      var added = 0;
      final l10n = await pump(tester, soldOut, onAdd: () => added++);

      // Visible with the reason — staff must see WHY it cannot be sold.
      expect(find.text('Onion Rings'), findsOneWidget);
      expect(find.text(l10n.posMenuItemSoldOut), findsOneWidget);
      // No add button, and the tile tap is dead.
      expect(find.byIcon(Icons.add_shopping_cart), findsNothing);
      await tester.tap(find.byKey(const Key('menu-item-x-soldout')));
      await tester.pump();
      expect(added, 0);
    });

    testWidgets('A2 paused wording is distinct', (tester) async {
      const paused = DemoMenuItem(
        id: 'x-paused',
        name: 'Lemonade',
        priceMinor: 1400,
        categoryId: 'drinks',
        categoryName: 'Drinks',
        availability: 'unavailable',
        availabilityReason: 'paused',
      );
      final l10n = await pump(tester, paused, onAdd: () {});
      expect(find.text(l10n.posMenuItemPaused), findsOneWidget);
      expect(find.text(l10n.posMenuItemSoldOut), findsNothing);
    });

    testWidgets('A3 an available item is untouched', (tester) async {
      const ok = DemoMenuItem(
        id: 'x-ok',
        name: 'Cola',
        priceMinor: 900,
        categoryId: 'drinks',
        categoryName: 'Drinks',
      );
      var added = 0;
      await pump(tester, ok, onAdd: () => added++);
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-item-x-ok')));
      expect(added, 1);
    });
  });

  group('B. the move-table sheet', () {
    PosRecentOrder order({String status = 'preparing', String? table = 'T1'}) =>
        PosRecentOrder.discovered(
          PosOrderSnapshot(
            orderId: 'o-1',
            orderCode: '#00O001',
            revision: 2,
            status: status,
            settlement: PosSettlement.unpaid,
            subtotalMinor: 2500,
            discountTotalMinor: 0,
            taxTotalMinor: 0,
            grandTotalMinor: 2500,
            createdAt: DateTime.utc(2026, 7, 14, 12),
            updatedAt: DateTime.utc(2026, 7, 14, 12),
            syncAt: DateTime.utc(2026, 7, 14, 12),
            orderType: 'dine_in',
            tableLabel: table,
            currencyCode: 'ILS',
          ),
        );

    Future<AppLocalizations> pump(
      WidgetTester tester, {
      required MoveTableRepository moves,
      required PosRecentOrder target,
    }) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posMoveTableRepositoryProvider.overrideWithValue(moves),
            // A small deterministic floor: T1 (current), T2 free, T3 hosting
            // one live order — honest occupancy, still pickable.
            tablesProvider.overrideWith(
              (ref) async => [
                for (final (id, label, count) in [
                  ('t1', 'T1', 1),
                  ('t2', 'T2', 0),
                  ('t3', 'T3', 1),
                ])
                  DemoTable(
                    table: DiningTable(
                      tableId: id,
                      label: label,
                      organizationId: 'org',
                      restaurantId: 'rest',
                      branchId: 'branch',
                    ),
                    status: TableStatusKind.available,
                    activeOrderCount: count,
                  ),
              ],
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Builder(
              builder: (context) {
                l10n = AppLocalizations.of(context);
                // Present the sheet EXACTLY as production does — as a modal
                // route — so its pop() closes the sheet and the snackbar lands
                // on the underlying Scaffold.
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      key: const Key('open-move-sheet'),
                      onPressed: () =>
                          MoveTableSheet.show(context, order: target),
                      child: const Text('open'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-move-sheet')));
      await tester.pumpAndSettle();
      return l10n;
    }

    testWidgets('B1 pick a target, confirm, snackbar names the new table', (
      tester,
    ) async {
      final moves = _ScriptedMoveRepo(
        result: const MoveTableResult(tableLabel: 'T2', revision: 3),
      );
      final l10n = await pump(tester, moves: moves, target: order());

      // The current table is shown, marked, and not pickable.
      expect(find.textContaining('T1'), findsWidgets);
      // Honest occupancy on T3.
      expect(find.text(l10n.posTableOpenOrders(1)), findsOneWidget);

      // Confirm is disabled until a target is picked.
      final confirm = find.byKey(const Key('move-table-confirm-button'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.tap(find.byKey(const Key('move-table-tile-t2')));
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(moves.calls, 1);
      expect(moves.lastTableId, 't2');
      expect(moves.lastExpectedRevision, 2);
      expect(find.text(l10n.posMoveTableMoved('T2')), findsOneWidget);
    });

    testWidgets('B2 a CONFLICT retires the sheet (Confirm becomes Close)', (
      tester,
    ) async {
      final moves = _ScriptedMoveRepo(
        error: const MoveTableException('conflict', conflict: true),
      );
      final l10n = await pump(tester, moves: moves, target: order());

      await tester.tap(find.byKey(const Key('move-table-tile-t2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('move-table-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.posMoveTableConflict), findsOneWidget);
      expect(find.byKey(const Key('move-table-close-button')), findsOneWidget);
      expect(find.byKey(const Key('move-table-confirm-button')), findsNothing);
    });

    testWidgets('B3 a VANISHED target keeps the sheet usable for a new pick', (
      tester,
    ) async {
      final moves = _ScriptedMoveRepo(
        error: const MoveTableException(
          'table_not_available',
          tableUnavailable: true,
        ),
      );
      final l10n = await pump(tester, moves: moves, target: order());

      await tester.tap(find.byKey(const Key('move-table-tile-t2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('move-table-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.posMoveTableTableUnavailable), findsOneWidget);
      // NOT retired: the cashier may deliberately pick another table.
      expect(
        find.byKey(const Key('move-table-confirm-button')),
        findsOneWidget,
      );
    });

    testWidgets('B4 a legacy TABLELESS dine-in order shows the honest '
        'no-table subtitle (move doubles as assign)', (tester) async {
      final moves = _ScriptedMoveRepo(
        result: const MoveTableResult(tableLabel: 'T2', revision: 3),
      );
      final l10n = await pump(tester, moves: moves, target: order(table: null));
      expect(find.textContaining(l10n.posMoveTableNoTable), findsOneWidget);
    });
  });
}

class _ScriptedMoveRepo implements MoveTableRepository {
  _ScriptedMoveRepo({this.result, this.error});

  final MoveTableResult? result;
  final MoveTableException? error;
  int calls = 0;
  String? lastTableId;
  int? lastExpectedRevision;

  @override
  Future<MoveTableResult> moveTable({
    required String orderId,
    required String tableId,
    required String tableLabel,
    int? expectedRevision,
  }) async {
    calls++;
    lastTableId = tableId;
    lastExpectedRevision = expectedRevision;
    if (error != null) throw error!;
    return result!;
  }
}
