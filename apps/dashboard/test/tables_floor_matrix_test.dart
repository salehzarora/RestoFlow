import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show
        RestoflowFloorClusterSeam,
        RestoflowFloorFixture,
        kRestoflowFloorSectionAspect;
import 'package:restoflow_domain/restoflow_domain.dart'
    show floorElementRoomRect, floorTableRoomRect;
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminResult, AdminTransient;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_core/restoflow_core.dart';

/// TABLE-FLOOR-LAYOUT-021 §I — the Dashboard floor editor responsive matrix:
/// arrange mode with two sections and eight tables (all four statuses, a
/// linked pair, an unassigned table) lays out with ZERO overflow across
/// widths and locales, and the canvas geometry stays PHYSICAL under RTL.
DashboardTable _t(
  String id,
  String label, {
  DiningTableStatus status = DiningTableStatus.available,
  String? effective,
  int active = 0,
  String? group,
  String? sectionId,
  String? sectionName,
  int? sectionOrder,
  int? x,
  int? y,
}) => DashboardTable(
  id: id,
  label: label,
  seats: 4,
  status: status,
  isActive: true,
  branchId: 'b',
  activeOrderCount: active,
  effectiveState: effective,
  groupId: group,
  sectionId: sectionId,
  sectionName: sectionName,
  sectionDisplayOrder: sectionOrder,
  layoutX: x,
  layoutY: y,
);

/// 027: the default matrix fixture — one wall high on the s1 canvas, clear of
/// every table rect (so the overlap notice stays OFF in the base scenes).
const _wallX1 = DashboardFloorElement(
  id: 'x1',
  sectionId: 's1',
  kind: 'wall',
  layoutX: 5000,
  layoutY: 30,
  widthNorm: 3000,
  heightNorm: 150,
);

class _MatrixRepo extends InMemoryTablesStore {
  _MatrixRepo({this.elements = const [_wallX1], this.failDelete = false});

  /// 027: this run's fixture catalog + write recorders (the matrix asserts
  /// WHAT was persisted, not the in-memory demo store's internals).
  final List<DashboardFloorElement> elements;

  /// 028: force the delete RPC seam to fail (the failed-confirm test).
  final bool failDelete;
  final saved = <DashboardFloorElement>[];
  final deletedIds = <String>[];

  @override
  Future<AdminResult<void>> upsertFloorElement(
    DashboardFloorElement element,
  ) async {
    saved.add(element);
    return const Success(null);
  }

  @override
  Future<AdminResult<void>> deleteFloorElement(String id) async {
    deletedIds.add(id);
    return failDelete ? const Failure(AdminTransient()) : const Success(null);
  }

  @override
  Future<AdminResult<TablesFloorSnapshot>> load() async => Success(
    TablesFloorSnapshot(
      floorElements: elements,
      sections: const [
        DashboardTableSection(
          id: 's1',
          name: 'الصالة الرئيسية',
          displayOrder: 0,
          isActive: true,
          branchId: 'b',
        ),
        DashboardTableSection(
          id: 's2',
          name: 'Terrace',
          displayOrder: 1,
          isActive: true,
          branchId: 'b',
        ),
      ],
      tables: [
        _t(
          't1',
          'طاولة ١',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 500,
          y: 500,
        ),
        _t(
          't2',
          'T2',
          status: DiningTableStatus.occupied,
          effective: 'occupied',
          active: 2,
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 5000,
          y: 500,
        ),
        _t(
          't3',
          'T3',
          status: DiningTableStatus.reserved,
          effective: 'reserved',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 9500,
          y: 500,
        ),
        _t(
          't4',
          'T4',
          status: DiningTableStatus.outOfService,
          effective: 'out_of_service',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 500,
          y: 9500,
        ),
        _t(
          't5',
          'T5',
          group: 'g1',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 5000,
          y: 9500,
        ),
        _t(
          't6',
          'T6',
          group: 'g1',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 9500,
          y: 9500,
        ),
        _t(
          't7',
          'P1',
          sectionId: 's2',
          sectionName: 'Terrace',
          sectionOrder: 1,
          x: 2500,
          y: 5000,
        ),
        _t(
          't8',
          'P2',
          sectionId: 's2',
          sectionName: 'Terrace',
          sectionOrder: 1,
        ),
        _t('t9', 'U1'), // unassigned fallback zone
      ],
    ),
  );
}

Future<List<FlutterErrorDetails>> _pump(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  bool arrange = false,
  _MatrixRepo? repo,
}) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = previous);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(body: TablesScreen(repository: repo ?? _MatrixRepo())),
    ),
  );
  await tester.pumpAndSettle();
  if (arrange) {
    await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
    await tester.pumpAndSettle();
  }
  FlutterError.onError = previous;
  return errors;
}

void _expectClean(List<FlutterErrorDetails> errors, String scene) {
  expect(
    errors.where((e) => '${e.exception}'.contains('overflowed')),
    isEmpty,
    reason: 'overflow in $scene',
  );
  expect(errors, isEmpty, reason: 'unexpected errors in $scene');
}

void main() {
  const sizes = [Size(800, 5200), Size(1100, 5200), Size(1500, 5200)];
  const locales = [Locale('en'), Locale('ar'), Locale('he')];

  for (final size in sizes) {
    for (final locale in locales) {
      testWidgets(
        'floor editor (arrange ON) lays out clean at ${size.width.toInt()} '
        '${locale.languageCode}',
        (tester) async {
          final errors = await _pump(
            tester,
            size: size,
            locale: locale,
            arrange: true,
          );
          _expectClean(errors, '$size $locale');
          expect(find.byKey(const Key('floor-canvas-s1')), findsOneWidget);
          expect(find.byKey(const Key('floor-canvas-s2')), findsOneWidget);
          // Drag handles exist in arrange mode; the unassigned zone survives.
          expect(find.byKey(const Key('floor-drag-t1')), findsOneWidget);
          expect(find.byKey(const Key('floor-table-t9')), findsOneWidget);
        },
      );
    }
  }

  final parity = <String, List<Offset>>{};
  Future<List<Offset>> offsets(WidgetTester tester, Locale locale) async {
    final errors = await _pump(
      tester,
      size: const Size(1500, 5200),
      locale: locale,
    );
    _expectClean(errors, 'parity $locale');
    final origin = tester.getTopLeft(find.byKey(const Key('floor-canvas-s1')));
    return [
      for (final id in ['t1', 't2', 't3', 't4', 't5', 't6'])
        tester.getTopLeft(find.byKey(Key('floor-table-$id'))) - origin,
    ];
  }

  testWidgets('parity: record the LTR (en) canvas geometry', (tester) async {
    parity['en'] = await offsets(tester, const Locale('en'));
    expect(parity['en'], hasLength(6));
  });

  testWidgets('parity: the RTL (ar) canvas geometry is IDENTICAL', (
    tester,
  ) async {
    final ar = await offsets(tester, const Locale('ar'));
    expect(ar, parity['en'], reason: 'the room must not mirror under RTL');
  });

  testWidgets('027 LINKED (Dashboard, read-only): grouped members render as a '
      'seamed cluster and are NOT draggable while linked', (tester) async {
    final errors = await _pump(
      tester,
      size: const Size(1500, 5200),
      locale: const Locale('en'),
      arrange: true,
    );
    _expectClean(errors, 'dashboard linked');
    // t5+t6 share group g1 in the fixture: one seam behind them.
    expect(find.byType(RestoflowFloorClusterSeam), findsOneWidget);
    // Unlinked tables keep their drag handles; linked members do not (base
    // coordinates are preserved for the unlink restore).
    expect(find.byKey(const Key('floor-drag-t1')), findsOneWidget);
    expect(find.byKey(const Key('floor-drag-t5')), findsNothing);
    expect(find.byKey(const Key('floor-drag-t6')), findsNothing);
    // Both members still render (derived positions, same section).
    expect(find.byKey(const Key('floor-table-t5')), findsOneWidget);
    expect(find.byKey(const Key('floor-table-t6')), findsOneWidget);
    // Physically joined: the derived rects sit one seam apart.
    final r5 = tester.getRect(find.byKey(const Key('floor-table-t5')));
    final r6 = tester.getRect(find.byKey(const Key('floor-table-t6')));
    expect((r6.left - r5.right).abs(), lessThan(r5.width));
    expect((r6.top - r5.top).abs(), lessThan(1.0));
  });

  testWidgets('027 CONTRACT PARITY: the rendered tile rect equals the shared '
      'room-unit contract to <=0.5px (transitively equal to POS/Move)', (
    tester,
  ) async {
    final errors = await _pump(
      tester,
      size: const Size(1500, 5200),
      locale: const Locale('en'),
    );
    _expectClean(errors, 'contract parity');
    final canvasRect = tester.getRect(find.byKey(const Key('floor-canvas-s1')));
    // t1 is stored at (500, 500).
    final room = floorTableRoomRect(500, 500);
    final expected = Rect.fromLTWH(
      canvasRect.left + room.left * canvasRect.width / 10000,
      canvasRect.top + room.top * canvasRect.height / 10000,
      room.width * canvasRect.width / 10000,
      room.height * canvasRect.height / 10000,
    );
    final actual = tester.getRect(find.byKey(const Key('floor-table-t1')));
    expect((actual.left - expected.left).abs(), lessThanOrEqualTo(0.5));
    expect((actual.top - expected.top).abs(), lessThanOrEqualTo(0.5));
    expect((actual.width - expected.width).abs(), lessThanOrEqualTo(0.5));
    expect((actual.height - expected.height).abs(), lessThanOrEqualTo(0.5));
    // The compact aspect token holds.
    expect(
      canvasRect.width / canvasRect.height,
      closeTo(kRestoflowFloorSectionAspect, 0.01),
    );
  });

  group('027 FIXTURES (Dashboard editor)', () {
    testWidgets('read-only outside Elements submode + contract parity rect', (
      tester,
    ) async {
      final errors = await _pump(
        tester,
        size: const Size(1500, 5200),
        locale: const Locale('en'),
        arrange: true,
      );
      _expectClean(errors, 'fixtures read-only');
      // Tables submode (the default): the wall renders but is NOT drag-armed;
      // tables keep their drag handles.
      expect(find.byKey(const Key('floor-element-x1')), findsOneWidget);
      // 119A: the AUTHORITATIVE orientation reaches the fixture widget.
      expect(
        tester
            .widget<RestoflowFloorFixture>(
              find.byKey(const Key('floor-element-x1')),
            )
            .quarterTurns,
        _wallX1.orientationQuarterTurns,
      );
      expect(find.byKey(const Key('floor-element-drag-x1')), findsNothing);
      expect(find.byKey(const Key('floor-drag-t1')), findsOneWidget);
      // The fixture sits at the SHARED room-unit contract rect (<=0.5px).
      final canvas = tester.getRect(find.byKey(const Key('floor-canvas-s1')));
      final room = floorElementRoomRect(
        _wallX1.layoutX,
        _wallX1.layoutY,
        width: _wallX1.widthNorm,
        height: _wallX1.heightNorm,
      );
      final actual = tester.getRect(find.byKey(const Key('floor-element-x1')));
      expect(
        (actual.left - (canvas.left + room.left * canvas.width / 10000)).abs(),
        lessThanOrEqualTo(0.5),
      );
      expect(
        (actual.top - (canvas.top + room.top * canvas.height / 10000)).abs(),
        lessThanOrEqualTo(0.5),
      );
      expect(
        (actual.width - room.width * canvas.width / 10000).abs(),
        lessThanOrEqualTo(0.5),
      );
    });

    testWidgets('Elements submode locks tables, arms fixtures, and a drag '
        'saves NEW coordinates on END only', (tester) async {
      final repo = _MatrixRepo();
      final errors = await _pump(
        tester,
        size: const Size(1500, 5200),
        locale: const Locale('en'),
        arrange: true,
        repo: repo,
      );
      _expectClean(errors, 'elements submode');
      await tester.tap(find.byKey(const Key('floor-submode-elements')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floor-element-drag-x1')), findsOneWidget);
      expect(find.byKey(const Key('floor-drag-t1')), findsNothing);
      expect(find.byKey(const Key('floor-add-element-s1')), findsOneWidget);
      expect(repo.saved, isEmpty);
      await tester.drag(
        find.byKey(const Key('floor-element-drag-x1')),
        const Offset(80, 40),
      );
      await tester.pumpAndSettle();
      expect(repo.saved, hasLength(1));
      expect(repo.saved.single.id, 'x1');
      expect(repo.saved.single.layoutX, greaterThan(_wallX1.layoutX));
      expect(repo.saved.single.layoutY, greaterThan(_wallX1.layoutY));
    });

    testWidgets('the element menu offers kind-appropriate actions and delete '
        'reaches the repository', (tester) async {
      final repo = _MatrixRepo();
      final errors = await _pump(
        tester,
        size: const Size(1500, 5200),
        locale: const Locale('en'),
        arrange: true,
        repo: repo,
      );
      _expectClean(errors, 'element menu');
      await tester.tap(find.byKey(const Key('floor-submode-elements')));
      await tester.pumpAndSettle();
      // A movement-free press on the fixture opens the menu.
      await tester.tap(find.byKey(const Key('floor-element-drag-x1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floor-element-menu')), findsOneWidget);
      expect(find.byKey(const Key('floor-element-rotate')), findsOneWidget);
      // A wall resizes but carries no label.
      expect(find.byKey(const Key('floor-element-resize')), findsOneWidget);
      expect(find.byKey(const Key('floor-element-label')), findsNothing);
      await tester.tap(find.byKey(const Key('floor-element-delete')));
      await tester.pumpAndSettle();
      // 028: delete is CONFIRMED, never one-tap — the write happens only
      // after the dialog's explicit confirm.
      expect(repo.deletedIds, isEmpty);
      await tester.tap(
        find.byKey(const Key('floor-element-delete-confirm-action')),
      );
      await tester.pumpAndSettle();
      expect(repo.deletedIds, ['x1']);
    });

    testWidgets('palette creation persists a defaulted fixture in the chosen '
        'section', (tester) async {
      final repo = _MatrixRepo();
      final errors = await _pump(
        tester,
        size: const Size(1500, 5200),
        locale: const Locale('en'),
        arrange: true,
        repo: repo,
      );
      _expectClean(errors, 'palette');
      await tester.tap(find.byKey(const Key('floor-submode-elements')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-add-element-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-add-kind-plant-s1')));
      await tester.pumpAndSettle();
      expect(repo.saved, hasLength(1));
      final created = repo.saved.single;
      expect(created.id, isEmpty); // the store mints the id
      expect(created.sectionId, 's1');
      expect(created.kind, 'plant');
      expect((created.widthNorm, created.heightNorm), (900, 900));
    });

    testWidgets('fixture/table intersection raises the NON-blocking notice '
        'and never locks the floor', (tester) async {
      final repo = _MatrixRepo(
        elements: const [
          _wallX1,
          // A cashier stand straight on top of t1 (500,500).
          DashboardFloorElement(
            id: 'x2',
            sectionId: 's1',
            kind: 'cashier',
            layoutX: 500,
            layoutY: 500,
            widthNorm: 900,
            heightNorm: 900,
            label: 'POS',
          ),
        ],
      );
      final errors = await _pump(
        tester,
        size: const Size(1500, 5200),
        locale: const Locale('en'),
        arrange: true,
        repo: repo,
      );
      _expectClean(errors, 'element overlap');
      expect(find.byKey(const Key('floor-element-overlap-s1')), findsOneWidget);
      // NON-blocking (owner decision 6): tables stay draggable, nothing is
      // auto-moved, no dialog interrupts.
      expect(find.byKey(const Key('floor-drag-t1')), findsOneWidget);
      expect(find.byKey(const Key('floor-element-x2')), findsOneWidget);
    });
  });

  group('028 fixture delete confirmation', () {
    /// Arrange -> Elements submode -> tap the fixture -> tap Delete: the
    /// confirmation dialog is now open (and nothing was written).
    Future<void> openDeleteDialog(
      WidgetTester tester,
      _MatrixRepo repo, {
      String elementId = 'x1',
      Locale locale = const Locale('en'),
    }) async {
      final errors = await _pump(
        tester,
        size: const Size(1500, 5200),
        locale: locale,
        arrange: true,
        repo: repo,
      );
      _expectClean(errors, 'delete confirm setup');
      await tester.tap(find.byKey(const Key('floor-submode-elements')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('floor-element-drag-$elementId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-element-delete')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('floor-element-delete-confirm')),
        findsOneWidget,
      );
      expect(repo.deletedIds, isEmpty);
    }

    testWidgets('cancel keeps the fixture and writes NOTHING; the AR-rendered '
        'body names the kind', (tester) async {
      final repo = _MatrixRepo();
      // Rendered in ARABIC: the dialog itself (not just the ARB) is localized.
      await openDeleteDialog(tester, repo, locale: const Locale('ar'));
      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(
        find.text(l10n.floorElementDeleteConfirmBody(l10n.floorElementWall)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('floor-element-delete-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('floor-element-delete-confirm')),
        findsNothing,
      );
      expect(find.byKey(const Key('floor-element-x1')), findsOneWidget);
      expect(repo.deletedIds, isEmpty);
    });

    testWidgets('the BARRIER and system BACK both dismiss with zero write', (
      tester,
    ) async {
      final repo = _MatrixRepo();
      await openDeleteDialog(tester, repo);
      // Barrier tap (far outside the dialog).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('floor-element-delete-confirm')),
        findsNothing,
      );
      expect(repo.deletedIds, isEmpty);
      // Re-open, then the system back button.
      await tester.tap(find.byKey(const Key('floor-element-drag-x1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('floor-element-delete')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('floor-element-delete-confirm')),
        findsOneWidget,
      );
      // The system back reaches the root navigator as a maybePop.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('floor-element-delete-confirm')),
        findsNothing,
      );
      expect(find.byKey(const Key('floor-element-x1')), findsOneWidget);
      expect(repo.deletedIds, isEmpty);
    });

    testWidgets('confirm performs exactly ONE delete through the existing '
        'flow', (tester) async {
      final repo = _MatrixRepo();
      await openDeleteDialog(tester, repo);
      await tester.tap(
        find.byKey(const Key('floor-element-delete-confirm-action')),
      );
      await tester.pumpAndSettle();
      expect(repo.deletedIds, ['x1']);
      // The existing _run flow: success snackbar + reload (the reloaded
      // snapshot still lists x1 because the recorder repo never mutates).
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a FAILED confirmed delete surfaces the failure and keeps the '
        'fixture; the labeled body names kind AND label', (tester) async {
      final repo = _MatrixRepo(
        failDelete: true,
        elements: const [
          DashboardFloorElement(
            id: 'x2',
            sectionId: 's1',
            kind: 'cashier',
            layoutX: 9500,
            layoutY: 9500,
            widthNorm: 900,
            heightNorm: 900,
            label: 'POS',
          ),
        ],
      );
      await openDeleteDialog(tester, repo, elementId: 'x2');
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(
          l10n.floorElementDeleteConfirmBodyLabeled(
            l10n.floorElementCashier,
            'POS',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('floor-element-delete-confirm-action')),
      );
      await tester.pumpAndSettle();
      // The write was attempted once, failed, and the existing error path
      // showed its snackbar; the fixture stays on the canvas.
      expect(repo.deletedIds, ['x2']);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byKey(const Key('floor-element-x2')), findsOneWidget);
    });

    test('the confirmation copy exists and differs across AR/HE/EN', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      final he = await AppLocalizations.delegate.load(const Locale('he'));
      for (final l in [en, ar, he]) {
        expect(l.floorElementDeleteConfirmTitle, isNotEmpty);
        expect(l.floorElementDeleteConfirmBody('x'), isNotEmpty);
        expect(l.floorElementDeleteConfirmBodyLabeled('x', 'y'), isNotEmpty);
      }
      expect({
        en.floorElementDeleteConfirmTitle,
        ar.floorElementDeleteConfirmTitle,
        he.floorElementDeleteConfirmTitle,
      }, hasLength(3));
    });
  });
}
