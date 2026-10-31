/// STOREFRONT-PUBLISH-001 — DASH-V-1: the REAL dashboard shell hands the
/// Settings Storefront editor the REAL membership identity.
///
/// The editor keeps its draft, its same-request "Try again" handle and its
/// remembered refusals in a State keyed by
/// `StorefrontEditorSeams.scopeIdentity` (DASH-1): a different membership /
/// organization / restaurant / role must be a different editor. The section
/// tests inject that string by hand, so they cannot notice a shell that builds
/// the seams with a CONSTANT (or partial) identity — every tenant would then
/// share one editor key. Here the real `DashboardShell` is pumped the way
/// `main.dart` pumps it (keyed by `dashboardShellIdentity`), and what it
/// actually passed down is read back: the seams handed to the Settings view
/// and the key of the editor it renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_section.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Every read answers "transient": the surfaces show their honest failure
/// states, which is all this test needs — the question is only WHICH identity
/// the shell built the Storefront seams for, never what the server says.
class _OfflineTransport implements SyncRpcTransport {
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, Map.of(params)));
    throw const SyncTransportException(
      SyncTransportErrorKind.transient,
      code: '503',
      message: 'not under test',
    );
  }
}

class _MenuSource implements MenuReadSource {
  final List<MenuScope> calls = [];
  @override
  Future<MenuSnapshot> load(MenuScope scope) async {
    calls.add(scope);
    return const MenuSnapshot();
  }
}

class _ProfileTransport extends _OfflineTransport {
  _ProfileTransport(this.restaurant, this.savedBranch);
  final String restaurant;
  final String savedBranch;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != SupabaseStorefrontProfileRepository.readFunction) {
      return super.invoke(function, params);
    }
    calls.add((function, Map.of(params)));
    return {
      'ok': true,
      'entity': 'restaurant_storefront_profile',
      'restaurant_id': restaurant,
      'exists': true,
      'version': 1,
      'profile': {
        'restaurant_id': restaurant,
        'storefront_branch_id': savedBranch,
        'slug': 'synthetic-featured',
        'display_name': 'Synthetic Storefront',
        'tagline': null,
        'public_city': null,
        'public_address': null,
        'public_phone': null,
        'primary_color': '#13322a',
        'accent_color': '#e07b2c',
        'visual_preset': 'dark',
        'locale_default': 'en',
        'card_mode': 'list',
        'motion': 'full',
        'pickup_enabled': true,
        'delivery_enabled': false,
        'ordering_enabled': false,
        'paused_until': null,
        'pause_reason': null,
        'opening_hours': {'weekly': <Object>[], 'exceptions': <Object>[]},
        'logo_media_id': null,
        'hero_media_id': null,
        'is_published': false,
        'version': 1,
        'featured_item_ids': <String>[],
      },
      'derived': {
        'timezone': 'UTC',
        'currency_code': 'ILS',
        'tax': null,
        'publish_ready': true,
        'publish_blockers': <String>[],
        'media_prefix': 'prefix0',
      },
    };
  }
}

MembershipContext _membership({
  required String id,
  required String organizationId,
  required String restaurantId,
  required String branchId,
  required MembershipRole role,
}) => MembershipContext(
  id: id,
  organizationId: organizationId,
  organizationName: 'Org $organizationId',
  restaurantId: restaurantId,
  restaurantName: 'Restaurant $restaurantId',
  branchId: branchId,
  branchName: 'Branch $branchId',
  role: role,
  status: 'active',
);

/// Mirrors `main.dart`: the shell carries the membership-derived key, so a
/// membership change disposes it (and its `late final` seams).
Widget _app(
  MembershipContext membership,
  String currencyCode,
  SyncRpcTransport transport, {
  MenuReadSource? menuReadSource,
}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: false),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: DashboardShell(
      key: ValueKey(
        dashboardShellIdentity(membership, currencyCode: currencyCode),
      ),
      membership: membership,
      currencyCode: currencyCode,
      reportsTransport: transport,
      menuReadSource: menuReadSource,
      // STOREFRONT-INTEGRATE-001: the editor is DARK by default; this test
      // proves the WIRED editor's identity, so it opens the gate.
      storefrontEditorEnabled: true,
    ),
  ),
);

Future<void> _openSettings(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('dashboard-side-rail')),
      matching: find.text(l10n.dashboardNavSettings),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(RealSettingsView), findsOneWidget);
}

/// Scrolls the lazy Settings list until the Storefront card is built.
Future<void> _revealStorefront(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('storefront-section')),
    300,
    scrollable: find
        .descendant(
          of: find.byType(RealSettingsView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'real shell supplies complete catalog loaded for saved storefront branch, not membership branch',
    (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = _MenuSource();
      final membership = _membership(
        id: 'member',
        organizationId: 'org',
        restaurantId: 'restaurant',
        branchId: '11111111-1111-1111-1111-111111111111',
        role: MembershipRole.manager,
      );
      const saved = '22222222-2222-2222-2222-222222222222';
      final transport = _ProfileTransport(membership.restaurantId!, saved);
      await tester.pumpWidget(
        _app(membership, 'ILS', transport, menuReadSource: source),
      );
      await tester.pumpAndSettle();
      await _openSettings(tester, l10n);
      await _revealStorefront(tester);
      expect(find.byType(StorefrontSection), findsOneWidget);
      expect(
        transport.calls.where(
          (call) => call.$1 == SupabaseStorefrontProfileRepository.readFunction,
        ),
        hasLength(1),
      );
      expect(source.calls, hasLength(1));
      expect(source.calls.single.branchId, saved);
      expect(source.calls.single.branchId, isNot(membership.branchId));
      expect(source.calls.single.organizationId, membership.organizationId);
      expect(source.calls.single.restaurantId, membership.restaurantId);
    },
  );
  testWidgets('DASH-V-1: the shell builds the Storefront seams for exactly its '
      'own membership identity, and the editor is keyed by it', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const currency = 'ILS';
    final memberships = [
      _membership(
        id: 'm-a',
        organizationId: 'org-a',
        restaurantId: 'rest-a',
        branchId: 'branch-a',
        role: MembershipRole.orgOwner,
      ),
      // Another tenant, another restaurant.
      _membership(
        id: 'm-b',
        organizationId: 'org-b',
        restaurantId: 'rest-b',
        branchId: 'branch-b',
        role: MembershipRole.manager,
      ),
      // The SAME organization and restaurant as the first, through another
      // membership with another role: still another editor.
      _membership(
        id: 'm-c',
        organizationId: 'org-a',
        restaurantId: 'rest-a',
        branchId: 'branch-a',
        role: MembershipRole.manager,
      ),
    ];

    final seen = <String>[];
    for (final membership in memberships) {
      final transport = _OfflineTransport();
      await tester.pumpWidget(_app(membership, currency, transport));
      await tester.pumpAndSettle();
      await _openSettings(tester, l10n);

      final expected = dashboardShellIdentity(
        membership,
        currencyCode: currency,
      );
      final reason = 'membership ${membership.id}';

      // What the shell handed the Settings view.
      final seams = tester
          .widget<RealSettingsView>(find.byType(RealSettingsView))
          .storefrontSeams;
      expect(seams, isNotNull, reason: reason);
      expect(seams!.scopeIdentity, expected, reason: reason);
      // Never the demo identity, never a constant: it names this membership,
      // its organization and its restaurant.
      expect(seams.scopeIdentity, isNot(dashboardShellIdentity(null)));
      for (final part in [
        membership.id,
        membership.organizationId,
        membership.restaurantId!,
        membership.role.name,
      ]) {
        expect(
          seams.scopeIdentity.split('|'),
          contains(part),
          reason: '$reason: $part',
        );
      }

      // What the card actually renders: the editor keyed by that identity.
      await _revealStorefront(tester);
      expect(
        tester
            .widget<StorefrontSection>(find.byType(StorefrontSection))
            .seams
            ?.scopeIdentity,
        expected,
        reason: reason,
      );
      expect(
        find.byKey(ValueKey<String>('storefront-editor|$expected')),
        findsOneWidget,
        reason: reason,
      );
      for (final previous in seen) {
        expect(
          find.byKey(
            ValueKey<String>('storefront-editor|$previous'),
            skipOffstage: false,
          ),
          findsNothing,
          reason: '$reason must not reuse the editor of $previous',
        );
      }
      // ...and it reads the storefront of exactly that organization and
      // restaurant, through this shell's transport.
      final reads = [
        for (final (function, params) in transport.calls)
          if (function == SupabaseStorefrontProfileRepository.readFunction)
            params,
      ];
      expect(reads, isNotEmpty, reason: reason);
      for (final params in reads) {
        expect(params, {
          'p_organization_id': membership.organizationId,
          'p_restaurant_id': membership.restaurantId,
        }, reason: reason);
      }
      seen.add(expected);
    }

    // Three memberships, three editors.
    expect(seen.toSet(), hasLength(memberships.length));
  });
}
