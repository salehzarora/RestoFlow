import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_currency/restoflow_currency.dart';
import 'package:restoflow_dashboard/src/admin/currency_change_guard.dart';
import 'package:restoflow_dashboard/src/admin/real_admin_views.dart';
import 'package:restoflow_dashboard/src/admin/supabase_settings_repository.dart';
import 'package:restoflow_dashboard/src/admin/timezone_catalog.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// MENU-ADMIN-CURRENCY-SIMPLIFICATION-OPS-043 Phase 1 — the Settings authority.
///
/// D1: ONE operating currency per RESTAURANT, written to
/// `restaurants.currency_override` for the active restaurant only.
/// D3: no conversion, an explicit acknowledgment, and a safety gate that
/// refuses the change while orders or cash shifts are still open — and that
/// FAILS CLOSED when it cannot tell.
void main() {
  group('A. the row itself', () {
    testWidgets('A1. the ILS-only lock is gone and a real selector stands in '
        'its place', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(tester, repo: _Repo(prefill: _prefill()));

      expect(find.text(l10n.dashboardSettingsCurrencyLocked), findsNothing);
      expect(_selector, findsOneWidget);
      expect(
        find.text(l10n.dashboardSettingsOperatingCurrency),
        findsOneWidget,
      );
    });

    testWidgets('A2. an INHERITED currency says so — the coalesced value alone '
        'could never tell the owner where it came from', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(
        tester,
        repo: _Repo(prefill: _prefill(override: null, orgDefault: 'ILS')),
      );

      expect(
        find.text(l10n.dashboardSettingsCurrencyInherited),
        findsOneWidget,
      );
      expect(find.text(l10n.dashboardSettingsCurrencyOverridden), findsNothing);
    });

    testWidgets('A3. a restaurant-level OVERRIDE says that instead', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(
        tester,
        repo: _Repo(
          prefill: _prefill(override: 'EUR', orgDefault: 'ILS'),
        ),
      );

      expect(
        find.text(l10n.dashboardSettingsCurrencyOverridden),
        findsOneWidget,
      );
      expect(find.text(l10n.dashboardSettingsCurrencyInherited), findsNothing);
    });

    testWidgets('A4. the honest note that an override cannot be cleared back '
        'to inheritance — the server RPC coalesces', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(tester, repo: _Repo(prefill: _prefill()));

      expect(
        find.text(l10n.dashboardSettingsCurrencyOverrideNote),
        findsOneWidget,
      );
    });

    testWidgets('A5. D2 GATE (opened in Phase 2B): the picker now offers the '
        'full spendable ISO list, including 0- and 3-decimal currencies, '
        'because every exponent-sensitive path was made safe first', (
      tester,
    ) async {
      await _pump(tester, repo: _Repo(prefill: _prefill()));
      await tester.tap(_selector);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('currency-picker-dialog')), findsOneWidget);

      Future<void> search(String q) async {
        await tester.enterText(find.byKey(const Key('currency-search')), q);
        await tester.pumpAndSettle();
      }

      await search('EUR');
      expect(find.byKey(const Key('settings-currency-EUR')), findsOneWidget);
      await search('JPY');
      expect(find.byKey(const Key('settings-currency-JPY')), findsOneWidget);
      await search('KWD');
      expect(find.byKey(const Key('settings-currency-KWD')), findsOneWidget);
      // Fund and metal units are still NOT offerable: a restaurant cannot be
      // paid in gold, and opening the exponent gate never opened that one.
      await search('XAU');
      expect(find.byKey(const Key('settings-currency-XAU')), findsNothing);
      expect(find.byKey(const Key('currency-no-results')), findsOneWidget);
    });
  });

  group('B. the D3 safety gate runs BEFORE anything else', () {
    testWidgets('B1. open orders block the change: no dialog, no write', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final repo = _Repo(prefill: _prefill());
      await _pump(
        tester,
        repo: repo,
        guard: _Guard(const CurrencyChangeGate.blocked(openOrders: 3)),
      );
      await _pick(tester, 'EUR');

      expect(
        find.byKey(const Key('settings-currency-blocked')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.dashboardSettingsCurrencyBlockedOrders(3)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings-currency-confirm')), findsNothing);
      expect(repo.currencySaves, 0);
    });

    testWidgets('B2. an open cash shift blocks it too', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final repo = _Repo(prefill: _prefill());
      await _pump(
        tester,
        repo: repo,
        guard: _Guard(const CurrencyChangeGate.blocked(openShifts: 1)),
      );
      await _pick(tester, 'EUR');

      expect(
        find.text(l10n.dashboardSettingsCurrencyBlockedShifts(1)),
        findsOneWidget,
      );
      expect(repo.currencySaves, 0);
    });

    testWidgets('B3. FAIL CLOSED: a gate that cannot answer blocks, and says '
        'so — "I could not check" is never "all clear"', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final repo = _Repo(prefill: _prefill());
      await _pump(
        tester,
        repo: repo,
        guard: _Guard(const CurrencyChangeGate.unknown()),
      );
      await _pick(tester, 'EUR');

      expect(
        find.text(l10n.dashboardSettingsCurrencyBlockedUnknown),
        findsOneWidget,
      );
      expect(repo.currencySaves, 0);
    });

    testWidgets('B4. NO guard wired at all is treated exactly like a failed '
        'check', (tester) async {
      final repo = _Repo(prefill: _prefill());
      await _pump(tester, repo: repo, guard: null);
      await _pick(tester, 'EUR');

      expect(
        find.byKey(const Key('settings-currency-blocked')),
        findsOneWidget,
      );
      expect(repo.currencySaves, 0);
    });
  });

  group('C. the D3 confirmation', () {
    testWidgets('C1. it states plainly that amounts are NOT converted', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pump(
        tester,
        repo: _Repo(prefill: _prefill()),
        guard: _clear,
      );
      await _pick(tester, 'EUR');

      expect(
        find.byKey(const Key('settings-currency-confirm')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.dashboardSettingsCurrencyChangeBody),
        findsOneWidget,
      );
      // The labels are bidi-ISOLATED: without the isolates an RTL reader sees
      // the two labels swap their brackets and cannot tell which currency is
      // replacing which.
      expect(
        find.text(
          l10n.dashboardSettingsCurrencyChangeFromTo(
            currencySelectorLabelIsolated('ILS'),
            currencySelectorLabelIsolated('EUR'),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('C2. confirm is DISABLED until the owner acknowledges', (
      tester,
    ) async {
      final repo = _Repo(prefill: _prefill());
      await _pump(tester, repo: repo, guard: _clear);
      await _pick(tester, 'EUR');

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('settings-currency-apply')),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const Key('settings-currency-ack')));
      await _settleDialog(tester);
      final enabled = tester.widget<FilledButton>(
        find.byKey(const Key('settings-currency-apply')),
      );
      expect(enabled.onPressed, isNotNull);
      expect(repo.currencySaves, 0, reason: 'ticking a box writes nothing');
    });

    testWidgets('C3. cancelling writes nothing and leaves the old currency in '
        'place', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final repo = _Repo(prefill: _prefill());
      await _pump(tester, repo: repo, guard: _clear);
      await _pick(tester, 'EUR');
      await tester.tap(find.byKey(const Key('settings-currency-cancel')));
      await tester.pumpAndSettle();

      expect(repo.currencySaves, 0);
      expect(
        find.text(l10n.dashboardSettingsCurrencyInherited),
        findsOneWidget,
      );
    });
  });

  group('D. the write — D1 multi-restaurant correctness', () {
    testWidgets('D1. a confirmed change writes the picked code ONCE through '
        'saveOperatingCurrency', (tester) async {
      final repo = _Repo(prefill: _prefill());
      await _pump(tester, repo: repo, guard: _clear);
      await _confirm(tester, 'EUR');

      expect(repo.currencySaves, 1);
      expect(repo.lastCurrencyCode, 'EUR');
      // The restaurant NAME save is a separate intent and must not fire.
      expect(repo.restaurantSaves, 0);
    });

    testWidgets(
      'D2. after success the row flips to "set for this restaurant"',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(
          tester,
          repo: _Repo(prefill: _prefill()),
          guard: _clear,
        );
        await _confirm(tester, 'EUR');

        expect(
          find.text(l10n.dashboardSettingsCurrencyOverridden),
          findsOneWidget,
        );
      },
    );

    testWidgets('D3. a DENIED write changes nothing on screen — the display is '
        'the server\'s answer, never an optimistic guess', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final repo = _Repo(prefill: _prefill())
        ..currencyResult = SettingsWrite.denied;
      await _pump(tester, repo: repo, guard: _clear);
      await _confirm(tester, 'EUR');

      expect(repo.currencySaves, 1);
      expect(
        find.text(l10n.dashboardSettingsCurrencyInherited),
        findsOneWidget,
      );
      expect(find.text(l10n.dashboardShiftCloseDenied), findsOneWidget);
    });

    testWidgets('D4. picking the currency already in force does nothing at '
        'all — no gate call, no dialog, no write', (tester) async {
      final repo = _Repo(prefill: _prefill(override: 'EUR'));
      final guard = _Guard(const CurrencyChangeGate.clear());
      await _pump(tester, repo: repo, guard: guard);
      await _pick(tester, 'EUR');

      expect(guard.checks, 0);
      expect(find.byKey(const Key('settings-currency-confirm')), findsNothing);
      expect(repo.currencySaves, 0);
    });
  });

  group('E. locales', () {
    for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
      testWidgets('E1. ${locale.languageCode}: the row and the confirmation '
          'render localized, without overflow', (tester) async {
        final overflows = <String>[];
        final prior = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            overflows.add(details.toString());
          } else {
            prior?.call(details);
          }
        };
        final l10n = await AppLocalizations.delegate.load(locale);
        await _pump(
          tester,
          repo: _Repo(prefill: _prefill()),
          guard: _clear,
          locale: locale,
        );
        await _pick(tester, 'EUR');
        FlutterError.onError = prior;

        expect(
          find.text(l10n.dashboardSettingsCurrencyChangeTitle),
          findsOneWidget,
        );
        expect(
          find.text(l10n.dashboardSettingsCurrencyChangeAck),
          findsOneWidget,
        );
        expect(
          overflows.where((o) => o.contains('real_admin_views.dart')),
          isEmpty,
        );
      });
    }
  });

  group('F. the shared module backs the labels', () {
    test('F1. a code with an unambiguous glyph shows it; one without shows the '
        'bare code — D2 forbids inventing a glyph', () {
      expect(currencySelectorLabel('ILS'), 'ILS (₪)');
      expect(currencySelectorLabel('CHF'), 'CHF');
    });
  });
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Finder get _selector => find.byKey(const Key('settings-operating-currency'));

final _clear = _Guard(const CurrencyChangeGate.clear());

SettingsPrefill _prefill({String? override, String orgDefault = 'ILS'}) =>
    SettingsPrefill(
      branchName: 'Main hall',
      branchStatus: 'active',
      restaurantName: 'Olive North',
      restaurantStatus: 'active',
      restaurantCurrencyOverride: override,
      organizationDefaultCurrency: orgDefault,
    );

MembershipContext _membership() => const MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Olive Group',
  restaurantId: 'rest-1',
  restaurantName: 'Olive North',
  branchId: 'branch-1',
  branchName: 'Main hall',
  role: MembershipRole.orgOwner,
  status: 'active',
);

class _Guard implements CurrencyChangeGuard {
  _Guard(this.result);

  final CurrencyChangeGate result;
  int checks = 0;

  @override
  Future<CurrencyChangeGate> check() async {
    checks++;
    return result;
  }
}

class _Repo implements SettingsRepository {
  _Repo({this.prefill});

  final SettingsPrefill? prefill;
  SettingsWrite currencyResult = SettingsWrite.ok;
  int currencySaves = 0;
  int restaurantSaves = 0;
  int branchSaves = 0;
  String? lastCurrencyCode;

  @override
  Future<SettingsPrefill?> readPrefill() async => prefill;

  @override
  Future<List<TimezoneOption>> loadTimezones() async => const [];

  @override
  Future<SettingsWrite> saveBranch({
    required String name,
    String? receiptPrefix,
    required String status,
    String? timezone,
  }) async {
    branchSaves++;
    return SettingsWrite.ok;
  }

  @override
  Future<SettingsWrite> saveRestaurant({
    required String name,
    required String status,
  }) async {
    restaurantSaves++;
    return SettingsWrite.ok;
  }

  @override
  Future<SettingsWrite> saveOperatingCurrency({
    required String currencyCode,
  }) async {
    currencySaves++;
    lastCurrencyCode = currencyCode;
    return currencyResult;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required SettingsRepository repo,
  CurrencyChangeGuard? guard,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: RealSettingsView(
            membership: _membership(),
            currencyCode: 'ILS',
            settingsRepository: repo,
            currencyChangeGuard: guard,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the searchable picker, narrows to one code and taps it.
///
/// The search step is not decoration: the catalog is ~120 codes long and the
/// list is lazily built, so an off-screen row genuinely does not exist yet.
Future<void> _pick(WidgetTester tester, String code) async {
  await tester.tap(_selector);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('currency-search')), code);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('settings-currency-$code')));
  // NOT pumpAndSettle: the field shows a progress spinner while the gate check
  // and the write are in flight, and an indeterminate spinner never settles.
  await _settleDialog(tester);
}

/// Pumps far enough for a dialog to finish opening, without waiting for
/// animations that are designed never to stop.
Future<void> _settleDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Picks, acknowledges and applies.
Future<void> _confirm(WidgetTester tester, String code) async {
  await _pick(tester, code);
  await tester.tap(find.byKey(const Key('settings-currency-ack')));
  await _settleDialog(tester);
  await tester.tap(find.byKey(const Key('settings-currency-apply')));
  await _settleDialog(tester);
  await _settleDialog(tester);
}
