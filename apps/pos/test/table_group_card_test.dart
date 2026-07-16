import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/table_operations_repository.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/table_operations_controller.dart';
import 'package:restoflow_pos/src/widgets/table_picker_sheet.dart';

/// PSC-001B — the linked-table combined POS card.
///
/// A linked group renders as exactly ONE card (inside its area, or in the
/// dedicated Linked-tables section when it spans zones); starting a new order
/// requires an EXPLICIT physical-member choice in the group-detail sheet; the
/// aggregation stays fail-closed; unlink returns independent cards without
/// touching any order. All through the production seams (tablesProvider ->
/// withGroupAggregation -> TablePickerSheet).

DemoTable _t(
  String id,
  String label, {
  String area = 'Main',
  String effective = 'available',
  int active = 0,
  String? group,
}) => DemoTable(
  table: DiningTable(
    tableId: id,
    label: label,
    organizationId: 'o',
    restaurantId: 'r',
    branchId: 'b',
    area: area,
  ),
  status: tableStatusKindFor(effective),
  manualStatus: 'available',
  effectiveState: effective,
  activeOrderCount: active,
  groupId: group,
);

class _FakeTablesRepo implements TablesRepository {
  _FakeTablesRepo(this.rows);

  List<DemoTable> rows;

  @override
  Future<List<DemoTable>> loadTables() async => rows;
}

class _FakeOpsRepo implements TableOperationsRepository {
  _FakeOpsRepo({this.onUnlink});

  final Future<void> Function(String tableId)? onUnlink;
  final List<String> unlinked = <String>[];

  @override
  Future<void> setStatus({required String tableId, required String status}) =>
      throw UnimplementedError();

  @override
  Future<void> link({required String tableIdA, required String tableIdB}) =>
      throw UnimplementedError();

  @override
  Future<void> unlink({required String tableId}) async {
    unlinked.add(tableId);
    await onUnlink?.call(tableId);
  }
}

class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        key: const Key('open-picker'),
        onPressed: () => TablePickerSheet.show(context),
        child: const SizedBox.shrink(),
      ),
    ),
  );
}

Future<AppLocalizations> _l10n([String locale = 'en']) =>
    AppLocalizations.delegate.load(Locale(locale));

Future<ProviderContainer> _pumpPicker(
  WidgetTester tester, {
  required TablesRepository repo,
  TableOperationsRepository? ops,
  PosStaffCapabilities? caps,
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      tablesRepositoryProvider.overrideWithValue(repo),
      if (ops != null) tableOperationsRepositoryProvider.overrideWithValue(ops),
      if (caps != null) staffCapabilitiesProvider.overrideWith((ref) => caps),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const _Launcher(),
      ),
    ),
  );
  // Dine-in: the only mode in which a table can be assigned at all.
  container
      .read(orderSetupControllerProvider.notifier)
      .setOrderType(OrderType.dineIn);
  await tester.tap(find.byKey(const Key('open-picker')));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('combined group card (placement + dedup + state)', () {
    testWidgets(
      '1/2/3. two linked same-area tables render exactly ONE card in that '
      'area; the members never appear as top-level tiles',
      (tester) async {
        await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t4', 'T4', group: 'g1'),
            _t('t5', 'T5', group: 'g1'),
            _t('t1', 'T1'),
          ]),
        );
        expect(find.byKey(const Key('table-group-tile-g1')), findsOneWidget);
        expect(find.byKey(const Key('table-tile-t4')), findsNothing);
        expect(find.byKey(const Key('table-tile-t5')), findsNothing);
        expect(find.byKey(const Key('table-tile-t1')), findsOneWidget);
        // Same-area group: NO dedicated Linked-tables section appears.
        expect(find.byKey(const Key('table-groups-section')), findsNothing);
      },
    );

    testWidgets(
      '6. member labels are deterministic (label order, never arrival order)',
      (tester) async {
        await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t5', 'T5', group: 'g1'), // arrives FIRST
            _t('t4', 'T4', group: 'g1'),
          ]),
        );
        expect(find.text('T4 + T5'), findsOneWidget);
        expect(find.text('T5 + T4'), findsNothing);
      },
    );

    testWidgets(
      '4/5. a cross-zone group renders exactly once, inside the localized '
      'Linked tables section and in neither original area',
      (tester) async {
        final l10n = await _l10n();
        await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t4', 'T4', group: 'g1'),
            _t('t7', 'T7', area: 'Patio', group: 'g1'),
            _t('t1', 'T1'),
            _t('t8', 'T8', area: 'Patio'),
          ]),
        );
        final section = find.byKey(const Key('table-groups-section'));
        expect(section, findsOneWidget);
        final title = tester.widget<Text>(
          find.byKey(const Key('table-groups-section-title')),
        );
        expect(title.data, l10n.posTableGroupSectionTitle);
        // Exactly one card, and it lives INSIDE the section.
        final groupTile = find.byKey(const Key('table-group-tile-g1'));
        expect(groupTile, findsOneWidget);
        expect(
          find.descendant(of: section, matching: groupTile),
          findsOneWidget,
        );
        // The members are not rendered as tiles in any area.
        expect(find.byKey(const Key('table-tile-t4')), findsNothing);
        expect(find.byKey(const Key('table-tile-t7')), findsNothing);
        // Unlinked tables keep their areas.
        expect(find.byKey(const Key('table-tile-t1')), findsOneWidget);
        expect(find.byKey(const Key('table-tile-t8')), findsOneWidget);
      },
    );

    testWidgets(
      '7. duplicate backend rows never duplicate the card, the member labels, '
      'or the active-order count',
      (tester) async {
        final l10n = await _l10n();
        await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t4', 'T4', effective: 'occupied', active: 1, group: 'g1'),
            _t('t4', 'T4', effective: 'occupied', active: 1, group: 'g1'),
            _t('t5', 'T5', group: 'g1'),
          ]),
        );
        expect(find.byKey(const Key('table-group-tile-g1')), findsOneWidget);
        expect(find.text('T4 + T5'), findsOneWidget);
        // Deduplicated group count: 1, never 2.
        final count = tester.widget<Text>(
          find.byKey(const Key('group-open-orders-g1')),
        );
        expect(count.data, l10n.posTableOpenOrders(1));
      },
    );

    testWidgets('8. the card shows the most restrictive aggregate state', (
      tester,
    ) async {
      final l10n = await _l10n();
      await _pumpPicker(
        tester,
        repo: _FakeTablesRepo([
          _t('t4', 'T4', effective: 'occupied', active: 1, group: 'g1'),
          _t('t5', 'T5', group: 'g1'),
        ]),
      );
      final groupTile = find.byKey(const Key('table-group-tile-g1'));
      expect(
        find.descendant(
          of: groupTile,
          matching: find.text(l10n.posTableStatusOccupied),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      '9/10. an unknown member state fails closed to Blocked, and the card '
      'still opens the detail sheet for inspection',
      (tester) async {
        final l10n = await _l10n();
        final container = await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t4', 'T4', effective: 'mystery-state', group: 'g1'),
            _t('t5', 'T5', group: 'g1'),
          ]),
        );
        final groupTile = find.byKey(const Key('table-group-tile-g1'));
        expect(
          find.descendant(
            of: groupTile,
            matching: find.text(l10n.posTableStatusBlocked),
          ),
          findsOneWidget,
        );
        await tester.tap(groupTile);
        await tester.pumpAndSettle();
        // The detail sheet opened; with no assignable member it says so
        // honestly, and nothing was auto-assigned.
        expect(find.byKey(const Key('group-no-assignable')), findsOneWidget);
        expect(
          container.read(orderSetupControllerProvider).assignedTable,
          isNull,
        );
      },
    );

    testWidgets(
      'fail-safe: a single-member group stays a plain tile with its linked '
      'badge (no combined card, no lost table)',
      (tester) async {
        await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([_t('t4', 'T4', group: 'g1'), _t('t1', 'T1')]),
        );
        expect(find.byKey(const Key('table-group-tile-g1')), findsNothing);
        expect(find.byKey(const Key('table-tile-t4')), findsOneWidget);
        expect(find.byKey(const Key('table-linked-t4')), findsOneWidget);
      },
    );
  });

  group('group detail: explicit physical selection', () {
    testWidgets(
      '11/12/13. tapping the card assigns NOTHING; selecting T5 passes '
      'T5\'s physical table id into the existing order setup and closes '
      'both sheets',
      (tester) async {
        final container = await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t4', 'T4', group: 'g1'),
            _t('t5', 'T5', group: 'g1'),
          ]),
        );
        await tester.tap(find.byKey(const Key('table-group-tile-g1')));
        await tester.pumpAndSettle();
        // Detail is open; no automatic first-member (or any) assignment.
        expect(find.byKey(const Key('group-member-t4')), findsOneWidget);
        expect(find.byKey(const Key('group-member-t5')), findsOneWidget);
        expect(find.byKey(const Key('group-choose-prompt')), findsOneWidget);
        expect(
          container.read(orderSetupControllerProvider).assignedTable,
          isNull,
        );
        await tester.tap(find.byKey(const Key('group-member-select-t5')));
        await tester.pumpAndSettle();
        final assigned = container
            .read(orderSetupControllerProvider)
            .assignedTable;
        expect(assigned?.tableId, 't5');
        // Both the detail sheet and the picker closed.
        expect(find.byKey(const Key('group-member-t5')), findsNothing);
        expect(find.byKey(const Key('table-group-tile-g1')), findsNothing);
      },
    );

    testWidgets(
      '14. blocked members offer no selection affordance and a row tap is '
      'inert',
      (tester) async {
        final container = await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t4', 'T4', effective: 'occupied', active: 1, group: 'g1'),
            _t('t5', 'T5', group: 'g1'),
          ]),
        );
        await tester.tap(find.byKey(const Key('table-group-tile-g1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('group-member-select-t4')), findsNothing);
        expect(find.byKey(const Key('group-member-select-t5')), findsNothing);
        expect(find.byKey(const Key('group-no-assignable')), findsOneWidget);
        await tester.tap(find.byKey(const Key('group-member-t5')));
        await tester.pumpAndSettle();
        expect(
          container.read(orderSetupControllerProvider).assignedTable,
          isNull,
        );
      },
    );

    testWidgets(
      '15. the card shows the group total while member rows keep their OWN '
      'state and order count',
      (tester) async {
        final l10n = await _l10n();
        await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t4', 'T4', effective: 'occupied', active: 2, group: 'g1'),
            _t('t5', 'T5', effective: 'occupied', active: 1, group: 'g1'),
          ]),
        );
        // Card: the aggregate 3.
        final count = tester.widget<Text>(
          find.byKey(const Key('group-open-orders-g1')),
        );
        expect(count.data, l10n.posTableOpenOrders(3));
        await tester.tap(find.byKey(const Key('table-group-tile-g1')));
        await tester.pumpAndSettle();
        // Detail: which physical table owns which activity.
        final t4Sub = tester.widget<Text>(
          find.byKey(const Key('group-member-state-t4')),
        );
        expect(t4Sub.data, contains(l10n.posTableOpenOrders(2)));
        final t5Sub = tester.widget<Text>(
          find.byKey(const Key('group-member-state-t5')),
        );
        expect(t5Sub.data, contains(l10n.posTableOpenOrders(1)));
        // The group aggregate row is also honest (the row's value text).
        final agg = tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(const Key('group-detail-active-orders')),
                matching: find.byType(Text),
              )
              .last,
        );
        expect(agg.data, l10n.posTableOpenOrders(3));
      },
    );
  });

  group('unlink from the group detail', () {
    testWidgets(
      '16/17. authoritative unlink returns independent member cards and '
      'never mutates the members\' orders',
      (tester) async {
        final l10n = await _l10n();
        final repo = _FakeTablesRepo([
          _t('t4', 'T4', effective: 'occupied', active: 1, group: 'g1'),
          _t('t5', 'T5', group: 'g1'),
        ]);
        final ops = _FakeOpsRepo(
          onUnlink: (_) async {
            // The authoritative read model after a server unlink: same physical
            // tables, same orders, no group.
            repo.rows = [
              _t('t4', 'T4', effective: 'occupied', active: 1),
              _t('t5', 'T5'),
            ];
          },
        );
        await _pumpPicker(
          tester,
          repo: repo,
          ops: ops,
          caps: const PosStaffCapabilities(
            applyDiscount: false,
            applyFullComp: false,
            manageTableOperations: true,
          ),
        );
        await tester.tap(find.byKey(const Key('table-group-tile-g1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('group-unlink')));
        await tester.pumpAndSettle();
        // Confirm the existing dialog.
        await tester.tap(
          find.widgetWithText(FilledButton, l10n.posTableUnlink),
        );
        await tester.pumpAndSettle();
        // The write went through the existing seam, keyed by a real member id.
        expect(ops.unlinked, ['t4']);
        // The group card is gone; both physical tables are independent again.
        expect(find.byKey(const Key('table-group-tile-g1')), findsNothing);
        expect(find.byKey(const Key('table-tile-t4')), findsOneWidget);
        expect(find.byKey(const Key('table-tile-t5')), findsOneWidget);
        // T4's order survived untouched (count still 1, still occupied).
        final t4Count = tester.widget<Text>(
          find.byKey(const Key('table-open-orders-t4')),
        );
        expect(t4Count.data, l10n.posTableOpenOrders(1));
      },
    );

    testWidgets(
      'without manage_table_operations the unlink action is not offered',
      (tester) async {
        await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t4', 'T4', group: 'g1'),
            _t('t5', 'T5', group: 'g1'),
          ]),
          caps: PosStaffCapabilities.none,
        );
        await tester.tap(find.byKey(const Key('table-group-tile-g1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('group-unlink')), findsNothing);
        // The sheet still works for inspection + selection.
        expect(find.byKey(const Key('group-member-select-t4')), findsOneWidget);
      },
    );
  });

  group('localization / RTL', () {
    testWidgets(
      '18. Arabic renders the Linked tables section title under RTL',
      (tester) async {
        final ar = await _l10n('ar');
        await _pumpPicker(
          tester,
          repo: _FakeTablesRepo([
            _t('t4', 'T4', group: 'g1'),
            _t('t7', 'T7', area: 'Patio', group: 'g1'),
          ]),
          locale: const Locale('ar'),
        );
        final section = find.byKey(const Key('table-groups-section'));
        expect(section, findsOneWidget);
        final title = tester.widget<Text>(
          find.byKey(const Key('table-groups-section-title')),
        );
        expect(title.data, ar.posTableGroupSectionTitle);
        expect(Directionality.of(tester.element(section)), TextDirection.rtl);
      },
    );
  });
}
