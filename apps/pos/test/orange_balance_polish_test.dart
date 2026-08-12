// UI-ORANGE-BALANCE-POLISH-001-B — the POS orange roles.
//
// The rule, same as the Dashboard's: navy is the STRUCTURE, orange marks the
// single next step and the active selection. Orange is never the only signal,
// never stands in for a payment or availability status, and always comes from
// the BRAND palette rather than `RestoflowSemanticColors.accent` — those two
// hold the same value today, which is exactly why the sourcing is pinned.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/menu_filter.dart';
import 'package:restoflow_pos/src/widgets/category_chips.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// Paint-time overflow never reaches [WidgetTester.takeException]; the handler
/// is restored BEFORE returning so the caller's `expect` runs with the
/// binding's own handler back in place.
Future<List<String>> overflowsDuring(Future<void> Function() body) async {
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
  FlutterError.onError = previous;
  return overflows;
}

/// The REAL demo categories the POS ships with — not invented rows.
final _categories = kDemoCategories.take(3).toList();
final _firstId = _categories.first.id;
final _firstName = _categories.first.name;
final _secondId = _categories[1].id;
final _secondName = _categories[1].name;

Widget _host({
  required String selected,
  String language = 'ar',
  double width = 1280,
  double scale = 1.0,
}) {
  return MaterialApp(
    locale: Locale(language),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowLightBrandTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: CategoryChips(categories: _categories),
      ),
    ),
  );
}

/// Wraps [_host] in a scope whose selected category is [selected] — the REAL
/// provider the rail reads, so selection is exercised the way the app does it.
Widget _scoped({
  required String selected,
  String language = 'ar',
  double width = 1280,
  double scale = 1.0,
}) => ProviderScope(
  overrides: [selectedCategoryProvider.overrideWith((ref) => selected)],
  child: _host(
    selected: selected,
    language: language,
    width: width,
    scale: scale,
  ),
);

const _marker = Key('category-chip-active-marker');

void main() {
  group('A. brand orange never collides with a POS status colour', () {
    test('semantic states stay independent of the brand accent', () {
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final semantic = RestoflowSemanticColors.of(Brightness.light);
      // Approved, declined and pending all live on this surface. If any of
      // them equalled the brand mark, a cashier could not tell a payment
      // outcome from a brand highlight.
      expect(semantic.success, isNot(brand.accentOrange));
      expect(semantic.danger, isNot(brand.accentOrange));
      expect(semantic.info, isNot(brand.accentOrange));
      expect(semantic.warning, isNot(brand.accentOrange));
      // And navy remains the structure.
      expect(brand.primaryNavy, isNot(brand.accentOrange));
    });
  });

  group('B. the selected category is navy + an orange mark', () {
    testWidgets('the selected chip carries exactly one orange marker', (
      tester,
    ) async {
      await tester.pumpWidget(_scoped(selected: _firstId));
      await tester.pumpAndSettle();
      expect(find.byKey(_marker), findsOneWidget);
      final container = tester.widget<Container>(find.byKey(_marker));
      expect(
        (container.decoration! as BoxDecoration).color,
        RestoflowBrandPalette.of(Brightness.light).accentOrange,
        reason: 'The marker must be the BRAND accent, not a semantic colour.',
      );
    });

    testWidgets('the chip BODY stays navy — orange never becomes the fill', (
      tester,
    ) async {
      await tester.pumpWidget(_scoped(selected: _firstId));
      await tester.pumpAndSettle();
      final brand = RestoflowBrandPalette.of(Brightness.light);
      // Every orange box on this rail must BE the marker. A Container with a
      // decoration builds a DecoratedBox of its own, so the marker shows up
      // here too — counting is what separates "the mark is orange" from "the
      // chip turned orange".
      final orangeBoxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color == brand.accentOrange)
          .length;
      expect(
        orangeBoxes,
        1,
        reason:
            'Exactly one orange box: the 2px marker. Anything more means the '
            'chip body itself went orange, and navy is the structure.',
      );

      // And the chip body is the theme primary — navy.
      final scheme = restoflowLightBrandTheme().colorScheme;
      final bodyFills = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.boxShadow != null)
          .map((d) => d.color);
      expect(bodyFills, contains(scheme.primary));
    });

    testWidgets('selection does not change the chip geometry', (tester) async {
      await tester.pumpWidget(_scoped(selected: _secondId));
      await tester.pumpAndSettle();
      final unselected = tester.getRect(find.text(_firstName));

      await tester.pumpWidget(_scoped(selected: _firstId));
      await tester.pumpAndSettle();
      final selected = tester.getRect(find.text(_firstName));

      expect(
        selected.size.width,
        closeTo(unselected.size.width, 0.5),
        reason:
            'The rail is a horizontally scrolling set — a chip that grew on '
            'selection would shove its neighbours under the cashier mid-tap.',
      );
      expect(selected.size.height, closeTo(unselected.size.height, 0.5));
    });

    testWidgets('only the selected chip is marked', (tester) async {
      await tester.pumpWidget(_scoped(selected: _firstId));
      await tester.pumpAndSettle();
      expect(
        find.byKey(_marker),
        findsOneWidget,
        reason: 'Two active markers would mean two active filters.',
      );
    });

    testWidgets('the marker tracks the chip in RTL and LTR', (tester) async {
      for (final language in ['ar', 'he', 'en']) {
        await tester.pumpWidget(
          _scoped(selected: _firstId, language: language),
        );
        await tester.pumpAndSettle();
        final label = tester.getRect(find.text(_firstName));
        final marker = tester.getRect(find.byKey(_marker));
        expect(
          marker.width,
          greaterThan(0),
          reason: 'The marker must render in $language.',
        );
        expect(
          marker.top >= label.top - 40 && marker.bottom <= label.bottom + 40,
          isTrue,
          reason: 'The marker must stay with its chip in $language.',
        );
      }
    });
  });

  group('C. the rail survives every width, locale and text scale', () {
    for (final width in [1280.0, 834.0, 700.0, 430.0, 390.0]) {
      for (final language in ['ar', 'he', 'en']) {
        testWidgets('${width.toInt()} $language is overflow-free', (
          tester,
        ) async {
          final overflows = await overflowsDuring(() async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              _scoped(selected: _firstId, language: language, width: width),
            );
            await tester.pumpAndSettle();
          });
          expect(overflows, isEmpty);
        });
      }
    }

    for (final width in [1280.0, 700.0, 430.0]) {
      testWidgets('${width.toInt()} @2x is overflow-free', (tester) async {
        final overflows = await overflowsDuring(() async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            _scoped(selected: _firstId, width: width, scale: 2.0),
          );
          await tester.pumpAndSettle();
        });
        expect(overflows, isEmpty);
      });
    }
  });

  group('D. selecting a category still filters', () {
    testWidgets('tapping a chip moves the real selection provider', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _host(selected: kAllCategoriesId),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(selectedCategoryProvider), kAllCategoriesId);

      await tester.tap(find.text(_secondName));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedCategoryProvider),
        _secondId,
        reason: 'The marker is decoration; it must not swallow or alter taps.',
      );
    });
  });

  group('E. Add stays navy and earns orange only on interaction', () {
    // Sixteen cards fit a full menu. The card file records what happened the
    // last time this surface repeated one accent nineteen times — the colour
    // stopped meaning anything — and Send Order already holds the single
    // orange primary for this view. So Add keeps the structural fill and gains
    // the tactile layer instead.
    Widget cardHost({required bool unavailable, VoidCallback? onAdd}) {
      final item = kDemoMenu.first;
      return MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        theme: restoflowLightBrandTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 260,
              height: 300,
              child: MenuItemCard(
                item: unavailable
                    ? item.copyWith(availability: 'unavailable')
                    : item,
                currencyCode: 'ILS',
                onAdd: onAdd ?? () {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the Add fill is the structural navy, never the accent', (
      tester,
    ) async {
      await tester.pumpWidget(cardHost(unavailable: false));
      await tester.pumpAndSettle();
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add_shopping_cart),
      );
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final scheme = restoflowLightBrandTheme().colorScheme;
      final fill = button.style?.backgroundColor?.resolve(const {});
      expect(fill, scheme.primary);
      expect(
        fill,
        isNot(brand.accentOrange),
        reason:
            'A grid of orange Adds would compete with Send Order, the one '
            'control that is actually the next step.',
      );
    });

    testWidgets('Add gains an orange hover, press and focus edge', (
      tester,
    ) async {
      await tester.pumpWidget(cardHost(unavailable: false));
      await tester.pumpAndSettle();
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add_shopping_cart),
      );
      final style = button.style!;
      expect(style.overlayColor?.resolve(const {}), isNull);
      expect(style.overlayColor?.resolve({WidgetState.hovered}), isNotNull);
      expect(style.overlayColor?.resolve({WidgetState.pressed}), isNotNull);
      expect(
        style.overlayColor?.resolve({WidgetState.hovered}),
        isNot(style.overlayColor?.resolve({WidgetState.pressed})),
      );
      expect(
        style.side?.resolve({WidgetState.focused})?.color,
        RestoflowBrandPalette.of(Brightness.light).accentOrange,
      );
      expect(style.side?.resolve(const {}), isNull);
    });

    testWidgets('an unavailable item is never orange-actionable', (
      tester,
    ) async {
      var added = 0;
      await tester.pumpWidget(
        cardHost(unavailable: true, onAdd: () => added++),
      );
      await tester.pumpAndSettle();

      // The card does not merely DISABLE the action when an item is
      // unavailable — it withholds it. Either shape is acceptable here; what
      // must never happen is an enabled control, and certainly not one wearing
      // the action colour.
      final addFinder = find.widgetWithIcon(
        IconButton,
        Icons.add_shopping_cart,
      );
      if (addFinder.evaluate().isNotEmpty) {
        final button = tester.widget<IconButton>(addFinder);
        expect(button.onPressed, isNull);
        expect(
          button.style?.backgroundColor?.resolve({WidgetState.disabled}),
          isNot(RestoflowBrandPalette.of(Brightness.light).accentOrange),
          reason: 'A disabled control must never wear the action colour.',
        );
        await tester.tap(addFinder, warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      expect(
        added,
        0,
        reason: 'A sold-out item must never reach the add callback.',
      );
    });

    testWidgets('the add callback still fires exactly once', (tester) async {
      var added = 0;
      await tester.pumpWidget(
        cardHost(unavailable: false, onAdd: () => added++),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.add_shopping_cart),
      );
      await tester.pumpAndSettle();
      expect(added, 1);
    });

    testWidgets('the interaction styling changes no geometry', (tester) async {
      await tester.pumpWidget(cardHost(unavailable: false));
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find.widgetWithIcon(IconButton, Icons.add_shopping_cart),
      );
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
    });
  });

  group('F. the chosen tender is marked in orange AND without colour', () {
    Widget tenderHost({
      required PaymentMethod selected,
      ValueChanged<PaymentMethod>? onSelect,
      String language = 'ar',
      double width = 430,
      double scale = 1.0,
    }) => MaterialApp(
      locale: Locale(language),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      theme: restoflowLightBrandTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: PosTenderSelectorProbe(selected: selected, onSelect: onSelect),
        ),
      ),
    );

    ChoiceChip chipFor(WidgetTester tester, String key) =>
        tester.widget<ChoiceChip>(find.byKey(Key(key)));

    testWidgets('only the selected tender carries the orange edge', (
      tester,
    ) async {
      await tester.pumpWidget(tenderHost(selected: PaymentMethod.card));
      await tester.pumpAndSettle();
      final accent = RestoflowBrandPalette.of(Brightness.light).accentOrange;

      expect(chipFor(tester, 'tender-card').side?.color, accent);
      for (final other in ['tender-cash', 'tender-bit', 'tender-external']) {
        expect(
          chipFor(tester, other).side,
          isNull,
          reason: '$other is not chosen and must stay neutral.',
        );
      }
    });

    testWidgets('the selected tender also has a NON-COLOUR cue', (
      tester,
    ) async {
      await tester.pumpWidget(tenderHost(selected: PaymentMethod.cash));
      await tester.pumpAndSettle();
      expect(
        chipFor(tester, 'tender-cash').showCheckmark,
        isTrue,
        reason:
            'The app theme turns the chip checkmark off, which left the chosen '
            'tender distinguished by colour alone — on the one surface where '
            'getting it wrong means taking money the wrong way.',
      );
    });

    testWidgets('choosing a tender fires the existing callback once', (
      tester,
    ) async {
      final picked = <PaymentMethod>[];
      await tester.pumpWidget(
        tenderHost(selected: PaymentMethod.cash, onSelect: picked.add),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tender-card')));
      await tester.pumpAndSettle();
      expect(picked, [PaymentMethod.card]);
    });

    testWidgets('selecting does not change the chip HEIGHT', (tester) async {
      await tester.pumpWidget(tenderHost(selected: PaymentMethod.cash));
      await tester.pumpAndSettle();
      final unselected = tester.getRect(find.byKey(const Key('tender-card')));

      await tester.pumpWidget(tenderHost(selected: PaymentMethod.card));
      await tester.pumpAndSettle();
      final selected = tester.getRect(find.byKey(const Key('tender-card')));

      expect(
        selected.height,
        closeTo(unselected.height, 0.5),
        reason:
            'The edge is a colour change at the theme border width, not a '
            'thicker one, so a tender cannot grow taller when chosen.',
      );
    });

    testWidgets('orange never stands in for a payment OUTCOME', (tester) async {
      final brand = RestoflowBrandPalette.of(Brightness.light);
      final semantic = RestoflowSemanticColors.of(Brightness.light);
      // Approved, declined and pending are what tell a cashier whether money
      // actually moved. None of them may be confusable with the brand mark
      // that merely says which tender is chosen.
      expect(semantic.success, isNot(brand.accentOrange));
      expect(semantic.danger, isNot(brand.accentOrange));
      expect(semantic.info, isNot(brand.accentOrange));
      expect(semantic.warning, isNot(brand.accentOrange));
    });

    for (final width in [430.0, 390.0]) {
      for (final language in ['ar', 'he', 'en']) {
        testWidgets('${width.toInt()} $language tenders are overflow-free', (
          tester,
        ) async {
          final overflows = await overflowsDuring(() async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              tenderHost(
                selected: PaymentMethod.card,
                language: language,
                width: width,
              ),
            );
            await tester.pumpAndSettle();
          });
          expect(overflows, isEmpty);
        });
      }
    }

    testWidgets('430 @2x tenders are overflow-free', (tester) async {
      final overflows = await overflowsDuring(() async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          tenderHost(selected: PaymentMethod.card, scale: 2.0),
        );
        await tester.pumpAndSettle();
      });
      expect(overflows, isEmpty);
    });
  });
}
