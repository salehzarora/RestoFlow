import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Sprint: the Menu tab in REAL mode manages the BACKEND menu — the injected
/// `list_menu` read source + `menu_upsert_*` writer, scoped through the
/// tenant-context resolver (an org-wide owner resolves to the org's first
/// restaurant/branch + real currency) — with NO demo banner and NO
/// "Menu not available for this access" blocked state.

const _orgWideOwner = MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Olive Group',
  restaurantId: null,
  restaurantName: null,
  branchId: null,
  branchName: null,
  role: MembershipRole.orgOwner,
  status: 'active',
);

MyContext _ctx() => const MyContext(
  appUser: AppUserContext(
    id: 'u',
    email: 'owner@x.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: false,
  memberships: [_orgWideOwner],
);

/// Serves ONLY `list_org_structure` (the resolver); every other RPC fails —
/// this test isolates the menu wiring from the reports/devices surfaces.
class _StructureTransport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'list_org_structure') {
      return {
        'ok': true,
        'entity': 'org_structure',
        'organization': {
          'id': 'org-1',
          'name': 'Olive Group',
          'default_currency': 'ILS',
        },
        'restaurants': [
          {
            'id': 'rest-1',
            'name': 'Olive North',
            'currency_override': null,
            'timezone': 'UTC',
            'status': 'active',
            'branches': [
              {
                'id': 'branch-1',
                'name': 'Main hall',
                'timezone': 'UTC',
                'status': 'active',
              },
            ],
          },
        ],
        'server_ts': 't',
      };
    }
    throw const SyncTransportException(
      SyncTransportErrorKind.transient,
      code: '503',
      message: 'not under test',
    );
  }
}

class _RecordingReadSource implements MenuReadSource {
  MenuScope? lastScope;
  MenuSnapshot snapshot = const MenuSnapshot();

  @override
  Future<MenuSnapshot> load(MenuScope scope) async {
    lastScope = scope;
    return snapshot;
  }
}

/// An empty writer stand-in — most tests never write; the RpcMenuWriter has
/// its own unit suite.
class _NeverWriter extends InMemoryMenuStore {
  _NeverWriter();
}

/// Records the scope each category write received (the add-category dialog
/// regression: the REAL resolved scope must reach the writer).
class _RecordingWriter extends InMemoryMenuStore {
  MenuScope? lastScope;

  @override
  Future<MenuWriteOutcome> upsertCategory({
    required MenuScope scope,
    String? id,
    required String name,
    int displayOrder = 0,
    bool isActive = true,
  }) {
    lastScope = scope;
    return super.upsertCategory(
      scope: scope,
      id: id,
      name: name,
      displayOrder: displayOrder,
      isActive: isActive,
    );
  }
}

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pumpToMenu(
  WidgetTester tester,
  MenuReadSource source, {
  MenuWriter? writer,
}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final l10n = await en();
  await tester.pumpWidget(
    ProviderScope(
      child: DashboardApp(
        demoMode: false,
        fetchContext: fetcherForContext(_ctx()),
        reportsTransport: _StructureTransport(),
        menuReadSource: source,
        menuWriter: writer ?? _NeverWriter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.dashboardNavMenu));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an org-wide owner reaches REAL menu management: resolved '
      'scope + real currency, no blocked state, no demo banner', (
    tester,
  ) async {
    final l10n = await en();
    final source = _RecordingReadSource();
    await _pumpToMenu(tester, source);

    // The blocked state and the demo banner are both gone.
    expect(find.text(l10n.menuScopeUnavailableTitle), findsNothing);
    expect(find.text(l10n.menuDemoBanner), findsNothing);
    expect(find.byType(MenuManagementScreen), findsOneWidget);

    // The REAL read source got the RESOLVED scope — first restaurant/branch,
    // the org's real currency (never the USD placeholder).
    expect(source.lastScope, isNotNull);
    expect(source.lastScope!.organizationId, 'org-1');
    expect(source.lastScope!.restaurantId, 'rest-1');
    expect(source.lastScope!.branchId, 'branch-1');
    expect(source.lastScope!.currencyCode, 'ILS');

    // An empty backend menu shows the honest visible empty state with the
    // add-category affordance (the first step of building a menu).
    expect(find.text(l10n.menuEmptyCategories), findsOneWidget);
    expect(find.text(l10n.menuAddCategory), findsWidgets);
  });

  testWidgets('the header context label shows the RESOLVED restaurant/branch', (
    tester,
  ) async {
    await _pumpToMenu(tester, _RecordingReadSource());
    expect(find.textContaining('Main hall'), findsOneWidget);
  });

  testWidgets('Add category through the REAL shell wiring saves with the '
      'resolved branch scope and closes the dialog (hang regression)', (
    tester,
  ) async {
    final l10n = await en();
    final writer = _RecordingWriter();
    await _pumpToMenu(tester, _RecordingReadSource(), writer: writer);

    await tester.tap(find.text(l10n.menuAddCategory).first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('menu-category-name')),
      'drinks',
    );
    await tester.tap(find.text(l10n.menuSaveAction));
    await tester.pumpAndSettle();

    // The dialog closed (no stuck submitting state) and the write carried the
    // RESOLVED real scope — org, first restaurant/branch, real currency.
    expect(find.byKey(const ValueKey('menu-category-name')), findsNothing);
    final scope = writer.lastScope;
    expect(scope, isNotNull);
    expect(scope!.organizationId, 'org-1');
    expect(scope.restaurantId, 'rest-1');
    expect(scope.branchId, 'branch-1');
    expect(scope.currencyCode, 'ILS');
  });

  testWidgets('backend menu rows render — including a disabled item the '
      'management view must still show', (tester) async {
    final l10n = await en();
    final source = _RecordingReadSource()
      ..snapshot = const MenuSnapshot(
        categories: [
          MenuCategory(
            id: 'cat-1',
            organizationId: 'org-1',
            restaurantId: 'rest-1',
            branchId: null,
            name: 'Mains',
            displayOrder: 0,
            isActive: true,
          ),
        ],
        items: [
          MenuItem(
            id: 'item-1',
            organizationId: 'org-1',
            restaurantId: 'rest-1',
            branchId: null,
            menuCategoryId: 'cat-1',
            name: 'Shakshuka',
            description: null,
            basePriceMinor: 4200,
            currencyCode: 'ILS',
            defaultStationId: null,
            displayOrder: 0,
            isActive: true,
          ),
          MenuItem(
            id: 'item-2',
            organizationId: 'org-1',
            restaurantId: 'rest-1',
            branchId: null,
            menuCategoryId: 'cat-1',
            name: 'Retired special',
            description: null,
            basePriceMinor: 990,
            currencyCode: 'ILS',
            defaultStationId: null,
            displayOrder: 1,
            isActive: false,
          ),
        ],
      );
    await _pumpToMenu(tester, source);

    expect(find.text('Mains'), findsWidgets);
    expect(find.text('Shakshuka'), findsOneWidget);
    expect(find.text('Retired special'), findsOneWidget);
    expect(find.text(l10n.menuEmptyCategories), findsNothing);
  });
}
