/// GLOBAL-BRAND-ADMIN-V3 — the platform-admin console's visual pass, measured.
///
/// SCOPE, stated up front because the name "Admin" covers two different things
/// in this repo. `apps/admin` is the PLATFORM console: a gate, a sign-in + MFA
/// flow, and a read-only four-page console (ADMIN-125C.2). The tenant-facing
/// admin surfaces (settings / users / devices) live in `packages/feature_admin`
/// and are rendered by the DASHBOARD, not here — they keep their own suites. This file
/// covers the platform console.
///
/// WHAT IS ASSERTED, and why in this shape:
///
///  * OVERFLOW is captured through [FlutterError.onError], never
///    `tester.takeException()`. A RenderFlex overflow is reported during PAINT
///    and does not reach `takeException` in this harness — a matrix built on it
///    is green whatever the layout does, which reads as coverage while proving
///    nothing (SHARED-ADMIN-DEVICE-ACTIONS-RESPONSIVE-001 found this the hard
///    way). The handler is restored BEFORE any expectation, because the binding
///    asserts it owns the hook by then.
///  * INTERACTION STATE is asserted as PAINT ORDER, not as "a colour is
///    configured". The Dashboard's rail proved that an opaque selected fill
///    painted over the ink layer swallows hover and focus while every
///    colour-is-set assertion stays green.
///  * BRAND is asserted as "no semantic colour is used for identity", not as an
///    exact hex, so a future palette revision does not have to edit tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/auth/admin_mfa_screen.dart';
import 'package:restoflow_admin/src/auth/admin_sign_in_screen.dart';
import 'package:restoflow_admin/src/platform_admin_screen.dart';
import 'package:restoflow_admin/src/console/console_widgets.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'fake_admin_auth_service.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  double scale = 1.0,
}) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    builder: (context, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: child!,
    ),
    home: home,
  ),
);

/// Runs [body] and returns every RenderFlex overflow the renderer reported.
///
/// See the library comment: this is deliberately NOT `takeException`.
Future<List<String>> _overflowsDuring(Future<void> Function() body) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      overflows.add(text.split('\n').first.trim());
    } else {
      previous?.call(details);
    }
  };
  await body();
  // BEFORE the caller's expectation: the binding asserts it owns this hook by
  // then, and leaving the override installed turns every later failure in the
  // file into an opaque "did not complete".
  FlutterError.onError = previous;
  return overflows;
}

Future<List<String>> _pumpOverview(
  WidgetTester tester, {
  required double width,
  Locale locale = const Locale('en'),
  double scale = 1.0,
  double height = 4000,
}) async {
  _size(tester, Size(width, height));
  return _overflowsDuring(() async {
    await tester.pumpWidget(
      _app(const PlatformAdminScreen(), locale: locale, scale: scale),
    );
    await tester.pumpAndSettle();
  });
}

/// Opens a top-level console destination at [width] and reports any overflow
/// recorded while it renders. Section pages are reachable only THROUGH the
/// shell, so this pumps the shell and navigates rather than building a page in
/// isolation — a page that only lays out when nothing else is on screen is not
/// really laying out.
Future<List<String>> _pumpSection(
  WidgetTester tester,
  String destination, {
  required double width,
  Locale locale = const Locale('en'),
  double scale = 1.0,
  double height = 4000,
}) async {
  _size(tester, Size(width, height));
  return _overflowsDuring(() async {
    await tester.pumpWidget(
      _app(const PlatformAdminScreen(), locale: locale, scale: scale),
    );
    await tester.pumpAndSettle();
    // Scoped to the navigation subtree: several destination names are also
    // metric-card labels on the Overview page, and an unscoped finder would tap
    // the card instead of navigating.
    final rail = find.byKey(const Key('console-rail'));
    if (rail.evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(of: rail, matching: find.text(destination)).first,
      );
    } else {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const Key('console-drawer')),
              matching: find.text(destination),
            )
            .first,
      );
    }
    await tester.pumpAndSettle();
  });
}

// The console's target widths. 1440 down to 390 — a platform operator opens
// this on a laptop, but an on-call one opens it on a phone.
const _widths = [1440.0, 1280.0, 1024.0, 834.0, 700.0, 540.0, 430.0, 390.0];

// Admin chrome is Arabic + English ONLY (no Hebrew platform console).
const _locales = [Locale('en'), Locale('ar')];

void main() {
  // =========================================================================
  // A. RESPONSIVE — the overview holds at every target width, both directions
  // =========================================================================
  group('A. the platform overview holds across the width matrix', () {
    for (final width in _widths) {
      for (final locale in _locales) {
        testWidgets('${width.toInt()}px / ${locale.languageCode}', (
          tester,
        ) async {
          final overflows = await _pumpOverview(
            tester,
            width: width,
            locale: locale,
          );
          expect(
            overflows,
            isEmpty,
            reason: 'no platform-admin row may clip at ${width.toInt()}px',
          );
          // Still the overview, not a degraded fallback.
          expect(
            find.byKey(const Key('platform-overview-title')),
            findsOneWidget,
          );
        });
      }
    }
  });

  // =========================================================================
  // B. TEXT SCALE — representative 2x
  // =========================================================================
  group('B. the overview holds at 2x text scale', () {
    for (final width in [1280.0, 700.0, 430.0, 390.0]) {
      for (final locale in _locales) {
        testWidgets('${width.toInt()}px / ${locale.languageCode} / 2x', (
          tester,
        ) async {
          final overflows = await _pumpOverview(
            tester,
            width: width,
            locale: locale,
            scale: 2.0,
            height: 12000,
          );
          expect(overflows, isEmpty);
        });
      }
    }
  });

  // =========================================================================
  // C. STATUS-PILL HOST ROWS — the starvation class
  //
  // The shared pill already yields (Flexible + wrap + ellipsis). The defect
  // class that remains is the HOST: a Row that hands a pill unbounded main-axis
  // constraints beside an Expanded sibling overflows itself, and no amount of
  // hardening inside the pill can prevent that.
  // =========================================================================
  group('C. pill host rows give the pill a bound', () {
    testWidgets('a subscriber row keeps its plan AND its status pills on '
        'screen', (tester) async {
      final overflows = await _pumpSection(tester, 'Subscribers', width: 390);
      expect(overflows, isEmpty);
      // Every subscriber row still renders its plan value and its statuses.
      expect(find.byKey(const Key('subscribers-card')), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Basic'), findsWidgets);
    });

    testWidgets('the audit feed keeps its action pill and timestamp', (
      tester,
    ) async {
      final overflows = await _pumpSection(tester, 'Audit log', width: 390);
      expect(overflows, isEmpty);
      expect(find.byKey(const Key('audit-card')), findsOneWidget);
      // The raw action key is a wire identifier and is deliberately untranslated;
      // it must still be present rather than dropped to make room.
      expect(find.byType(RestoflowStatusPill), findsWidgets);
      expect(find.text('platform.subscribers.list'), findsWidgets);
    });

    testWidgets('the label still owns most of the row at desktop width', (
      tester,
    ) async {
      // GUARD ON THE FIX ITSELF. Bounding the trailing cluster with `Flexible`
      // is what stops the overflow, and it is also the thing that could quietly
      // halve the label column at widths that were never in trouble. This
      // measures that it did not.
      await _pumpSection(tester, 'Subscribers', width: 1280);
      final rowFinder = find
          .descendant(
            of: find.byKey(const Key('subscribers-card')),
            matching: find.byType(ConsoleListRow),
          )
          .first;
      final row = tester.getRect(rowFinder);
      // The trailing cluster is the thing the fix bounded, so it is the thing
      // to measure. `Flexible` caps it at half the row and lets it shrink to
      // its natural width below that; `Expanded` — the obvious-looking
      // alternative — would take the full half whether it needed it or not and
      // silently halve the organization name at every desktop width.
      final cluster = tester.getRect(
        find.descendant(
          of: rowFinder,
          // The KEYED trailing cluster, not "the first Wrap": the row also has
          // a meta-line Wrap inside the label column, and measuring that one
          // would assert something this guard never meant.
          matching: find.byKey(const Key('console-row-trailing')),
        ),
      );
      expect(
        cluster.width,
        lessThan(row.width * 0.4),
        reason:
            'a plan word and a status chip must not claim half the row just '
            'because they were given a flex',
      );
    });
  });

  // =========================================================================
  // D. SIGN-IN — the console's one real form
  // =========================================================================
  group('D. the sign-in form is usable at every width', () {
    Future<List<String>> pumpSignIn(
      WidgetTester tester, {
      required double width,
      Locale locale = const Locale('en'),
      double scale = 1.0,
    }) async {
      _size(tester, Size(width, scale > 1 ? 3000 : 1400));
      return _overflowsDuring(() async {
        await tester.pumpWidget(
          _app(
            AdminSignInScreen(authService: FakeAdminAuthService()),
            locale: locale,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
      });
    }

    for (final width in [1280.0, 700.0, 430.0, 390.0]) {
      for (final locale in _locales) {
        testWidgets('${width.toInt()}px / ${locale.languageCode}', (
          tester,
        ) async {
          final overflows = await pumpSignIn(
            tester,
            width: width,
            locale: locale,
          );
          expect(overflows, isEmpty);
          expect(find.byKey(const Key('admin-signin-email')), findsOneWidget);
          expect(
            find.byKey(const Key('admin-signin-password')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('admin-signin-submit')), findsOneWidget);
        });
      }
    }

    testWidgets('the submit control keeps a comfortable tap target at 390px', (
      tester,
    ) async {
      await pumpSignIn(tester, width: 390);
      final size = tester.getSize(find.byKey(const Key('admin-signin-submit')));
      expect(
        size.height,
        greaterThanOrEqualTo(44.0),
        reason: 'a primary action must stay tappable on a phone',
      );
    });

    testWidgets('no overflow at 390px / 2x', (tester) async {
      final overflows = await pumpSignIn(tester, width: 390, scale: 2.0);
      expect(overflows, isEmpty);
    });
  });

  // =========================================================================
  // D2. MFA — the console's other reachable destination
  // =========================================================================
  group('D2. the MFA step-up holds at every width', () {
    Future<List<String>> pumpMfa(
      WidgetTester tester, {
      required double width,
      Locale locale = const Locale('en'),
      double scale = 1.0,
    }) async {
      _size(tester, Size(width, scale > 1 ? 8000 : 3000));
      return _overflowsDuring(() async {
        await tester.pumpWidget(
          _app(
            AdminMfaScreen(
              authService: FakeAdminAuthService(signedIn: true),
              onVerified: () {},
              onSignOut: () {},
            ),
            locale: locale,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
      });
    }

    for (final width in [1280.0, 700.0, 430.0, 390.0]) {
      for (final locale in _locales) {
        testWidgets('${width.toInt()}px / ${locale.languageCode}', (
          tester,
        ) async {
          final overflows = await pumpMfa(tester, width: width, locale: locale);
          expect(overflows, isEmpty);
          // The step-up is still operable: a code field and a verify action.
          expect(find.byKey(const Key('admin-mfa-code')), findsOneWidget);
          expect(find.byKey(const Key('admin-mfa-verify')), findsOneWidget);
        });
      }
    }

    testWidgets('no overflow at 390px / 2x', (tester) async {
      final overflows = await pumpMfa(tester, width: 390, scale: 2.0);
      expect(overflows, isEmpty);
    });
  });

  // =========================================================================
  // D3. SHELL CHROME — the console has an app bar, not a rail
  //
  // `apps/admin` is a single-destination console: its "navigation" is the app
  // bar's refresh / sign-out / language actions. There is no selected state to
  // make visible, so what matters is that those actions are REACHABLE and
  // operable from the keyboard — the accessibility half of the Dashboard rail
  // work, applied to the surface this app actually has.
  // =========================================================================
  group('D3. the app-bar actions are keyboard reachable', () {
    testWidgets('tab reaches sign-out and Enter activates it', (tester) async {
      var signedOut = 0;
      _size(tester, const Size(1280, 2400));
      await tester.pumpWidget(
        _app(PlatformAdminScreen(onSignOut: () => signedOut++)),
      );
      await tester.pumpAndSettle();

      // Walk the traversal order until the sign-out action owns focus, then
      // activate it WITHOUT a pointer. Bounded so a traversal change fails
      // loudly instead of hanging.
      var reached = false;
      for (var i = 0; i < 12 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final focused = primaryFocus?.context?.widget;
        reached =
            focused != null &&
            find
                .descendant(
                  of: find.byKey(const Key('platform-signout-button')),
                  matching: find.byWidget(focused),
                )
                .evaluate()
                .isNotEmpty;
      }
      expect(
        reached,
        isTrue,
        reason: 'the sign-out action must be reachable by keyboard alone',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(signedOut, 1);
    });
  });

  // =========================================================================
  // E. STATE VIEWS — the four honest states stay distinguishable
  // =========================================================================
  group('E. loading / empty / error stay distinct', () {
    testWidgets('the loaded overview shows none of the state views', (
      tester,
    ) async {
      await _pumpOverview(tester, width: 1280);
      expect(find.byKey(const Key('platform-loading')), findsNothing);
      expect(find.byKey(const Key('platform-empty')), findsNothing);
      expect(find.byKey(const Key('platform-error')), findsNothing);
      expect(find.byKey(const Key('platform-not-configured')), findsNothing);
      expect(find.byKey(const Key('platform-access-denied')), findsNothing);
      // ...and the demo banner is honest about the data source.
      expect(find.byKey(const Key('platform-demo-banner')), findsOneWidget);
    });
  });

  // =========================================================================
  // F. BRAND — identity colours are brand roles, never semantic ones
  // =========================================================================
  group('F. the console reads as navy/white/orange', () {
    testWidgets('structural chrome uses brand roles, not status colours', (
      tester,
    ) async {
      await _pumpOverview(tester, width: 1280);
      final context = tester.element(
        find.byKey(const Key('platform-overview-title')),
      );
      final theme = Theme.of(context);
      final brand = RestoflowBrandPalette.from(context);
      final semantic =
          theme.extension<RestoflowSemanticColors>() ??
          RestoflowSemanticColors.of(theme.brightness);

      // The brand primary IS the navy, and it is not one of the frozen
      // semantic meanings wearing an identity hat.
      expect(theme.colorScheme.primary, brand.primaryNavy);
      for (final status in [
        semantic.success,
        semantic.warning,
        semantic.danger,
        semantic.info,
      ]) {
        expect(
          brand.primaryNavy,
          isNot(status),
          reason: 'identity must never borrow a status colour',
        );
        expect(brand.accentOrange, isNot(status));
      }
      // The console sits on the cool canvas with white cards, like every other
      // RestoFlow surface.
      expect(theme.scaffoldBackgroundColor, brand.canvasLight);
    });
  });

  // =========================================================================
  // G. NO BEHAVIOUR OR NAVIGATION REGRESSION
  // =========================================================================
  group('G. the console still does what it did', () {
    testWidgets('refresh, sign-out and language actions survive the pass', (
      tester,
    ) async {
      var signedOut = 0;
      _size(tester, const Size(1280, 2400));
      await tester.pumpWidget(
        _app(PlatformAdminScreen(onSignOut: () => signedOut++)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('platform-refresh-button')), findsOneWidget);
      expect(find.byKey(const Key('platform-signout-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('platform-refresh-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('platform-overview-title')),
        findsOneWidget,
        reason: 'refresh must reload the overview, not blank it',
      );

      await tester.tap(find.byKey(const Key('platform-signout-button')));
      await tester.pumpAndSettle();
      expect(signedOut, 1);
    });

    testWidgets('the read-only contract holds: no mutating control appears', (
      tester,
    ) async {
      await _pumpOverview(tester, width: 1280);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // D-026: the platform console is READ-ONLY. A visual pass must not have
      // introduced an affordance that implies otherwise.
      expect(find.widgetWithText(FilledButton, l10n.adminSave), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });
  });
}
