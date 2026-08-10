/// DASHBOARD-VISUAL-RANGE-REFRESH-F2 — the custom-range UX contract.
///
/// F1 pinned the DOMAIN (tokens, windows, keys). This file pins the UX built on
/// top of it, directly rather than by accident: which choices the selector
/// offers, that a draft is not a request, what Apply/Cancel/Clear each mean, and
/// that the comparison sentence describes the window the owner actually picked.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_comparison_labels.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart';
import 'package:restoflow_dashboard/src/analytics/custom_range_draft.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_drilldown.dart';
import 'package:restoflow_dashboard/src/analytics/overview_range_choice.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Records exactly what each report request asked for, so "did editing a draft
/// cause a load?" is answered by a count rather than by a guess.
class _CountingRepository implements OwnerReportsRepository {
  final List<({ReportRange range, CustomAnalyticsWindow? window})> calls = [];

  int get callCount => calls.length;

  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
  }) async {
    calls.add((range: range, window: customWindow));
    return const DemoOwnerReportsRepository().loadReport(range: range);
  }
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ProviderContainer _container(_CountingRepository repo) => ProviderContainer(
  overrides: [ownerReportsRepositoryProvider.overrideWithValue(repo)],
);

Widget _app(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: const DashboardHomeScreen(),
  ),
);

CustomAnalyticsWindow _win(int y, int m, int d, int days) =>
    CustomAnalyticsWindow.tryCreate(
      DateTime.utc(y, m, d),
      DateTime.utc(y, m, d).add(Duration(days: days - 1)),
    )!;

void main() {
  // ==========================================================================
  // A. Selector structure
  // ==========================================================================
  group('F2.A the selector offers seven choices', () {
    test('six presets plus Custom, in an explicit display order', () {
      expect(kOverviewRangeChoices, const [
        OverviewRangeChoice.preset(ReportRange.today),
        OverviewRangeChoice.preset(ReportRange.yesterday),
        OverviewRangeChoice.preset(ReportRange.last7),
        OverviewRangeChoice.preset(ReportRange.last30),
        OverviewRangeChoice.preset(ReportRange.last60),
        OverviewRangeChoice.preset(ReportRange.last90),
        OverviewRangeChoice.custom(),
      ]);
      expect(kOverviewRangeChoices.length, 7);
    });

    testWidgets('all seven render, including the two F1 withheld', (
      tester,
    ) async {
      _size(tester, const Size(1280, 2400));
      final c = _container(_CountingRepository());
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();

      for (final id in const [
        'today',
        'yesterday',
        'last7',
        'last30',
        'last60',
        'last90',
        'custom',
      ]) {
        expect(
          find.byKey(Key('range-chip-$id')),
          findsOneWidget,
          reason: 'chip $id must be present',
        );
      }
    });
  });

  // ==========================================================================
  // B. Responsive wrap — every choice reachable, nothing off-screen
  // ==========================================================================
  group('F2.B the wrap keeps all seven reachable at every width', () {
    for (final width in const [1280.0, 834.0, 430.0, 390.0]) {
      testWidgets('${width.toInt()}px: no overflow, Custom not hidden', (
        tester,
      ) async {
        _size(tester, Size(width, 3000));
        final c = _container(_CountingRepository());
        addTearDown(c.dispose);
        await tester.pumpWidget(_app(c));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('reports-range-filter')), findsOneWidget);

        // Custom and the long presets are LAID OUT, not parked outside a
        // scroll viewport — this is the property the Wrap buys and a
        // horizontal scroll row would have lost at 390px.
        for (final id in const ['last60', 'last90', 'custom']) {
          final chip = find.byKey(Key('range-chip-$id'));
          expect(chip, findsOneWidget);
          final rect = tester.getRect(chip);
          expect(
            rect.left >= 0 && rect.right <= width,
            isTrue,
            reason:
                '$id must sit inside the viewport at ${width}px (was $rect)',
          );
        }
      });
    }
  });

  // ==========================================================================
  // C. RTL / LTR
  // ==========================================================================
  group('F2.C direction', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('he')]) {
      testWidgets('${locale.languageCode}: every choice renders, no overflow', (
        tester,
      ) async {
        _size(tester, const Size(430, 3000));
        final c = _container(_CountingRepository());
        addTearDown(c.dispose);
        await tester.pumpWidget(_app(c, locale: locale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        for (final id in const ['today', 'last60', 'last90', 'custom']) {
          expect(find.byKey(Key('range-chip-$id')), findsOneWidget);
        }
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('range-chip-custom'))),
          ),
          locale.languageCode == 'en' ? TextDirection.ltr : TextDirection.rtl,
        );
      });
    }
  });

  // ==========================================================================
  // D-G. Draft lifecycle — the core promise: a draft is not a request
  // ==========================================================================
  group('F2.D draft lifecycle', () {
    testWidgets('tapping Custom opens the sheet and commits NOTHING', (
      tester,
    ) async {
      _size(tester, const Size(1280, 2400));
      final repo = _CountingRepository();
      final c = _container(repo);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();

      final before = repo.callCount;
      final windowBefore = c.read(analyticsWindowProvider);

      await tester.tap(find.byKey(const Key('range-chip-custom')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom-range-dialog')), findsOneWidget);
      expect(c.read(analyticsWindowProvider), windowBefore);
      expect(repo.callCount, before, reason: 'opening the sheet loads nothing');
    });

    testWidgets('editing the draft changes no committed state and issues no '
        'load', (tester) async {
      _size(tester, const Size(1280, 2400));
      final repo = _CountingRepository();
      final c = _container(repo);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('range-chip-custom')));
      await tester.pumpAndSettle();

      final before = repo.callCount;
      c.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
        startDay: DateTime.utc(2026, 3, 1),
        endDay: DateTime.utc(2026, 3, 14),
      );
      await tester.pumpAndSettle();

      expect(c.read(customAnalyticsWindowProvider), isNull);
      expect(c.read(analyticsWindowProvider).isCustom, isFalse);
      expect(repo.callCount, before);
    });

    testWidgets('Cancel discards the draft and leaves the committed window', (
      tester,
    ) async {
      _size(tester, const Size(1280, 2400));
      final repo = _CountingRepository();
      final c = _container(repo);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('range-chip-custom')));
      await tester.pumpAndSettle();

      c.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
        startDay: DateTime.utc(2026, 3, 1),
        endDay: DateTime.utc(2026, 3, 14),
      );
      await tester.pumpAndSettle();
      final before = repo.callCount;

      await tester.tap(find.byKey(const Key('custom-range-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom-range-dialog')), findsNothing);
      expect(c.read(customAnalyticsWindowProvider), isNull);
      expect(repo.callCount, before, reason: 'Cancel invalidates nothing');
    });

    testWidgets('Clear empties the DRAFT only — it does not fall back to Today', (
      tester,
    ) async {
      _size(tester, const Size(1280, 2400));
      final repo = _CountingRepository();
      final c = _container(repo);
      addTearDown(c.dispose);
      // Start from a COMMITTED custom window, so "did Clear touch the committed
      // state?" is observable rather than vacuous.
      c.read(customAnalyticsWindowProvider.notifier).state = _win(
        2026,
        3,
        1,
        14,
      );
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('range-chip-custom')));
      await tester.pumpAndSettle();

      expect(c.read(customRangeDraftProvider).isEmpty, isFalse);
      final before = repo.callCount;

      await tester.tap(find.byKey(const Key('custom-range-clear')));
      await tester.pumpAndSettle();

      expect(c.read(customRangeDraftProvider).isEmpty, isTrue);
      // The committed window is untouched — still custom, NOT today.
      expect(c.read(analyticsWindowProvider).isCustom, isTrue);
      expect(c.read(customAnalyticsWindowProvider), _win(2026, 3, 1, 14));
      expect(repo.callCount, before);
    });

    testWidgets('Apply commits the drafted window exactly once', (
      tester,
    ) async {
      _size(tester, const Size(1280, 2400));
      final repo = _CountingRepository();
      final c = _container(repo);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('range-chip-custom')));
      await tester.pumpAndSettle();

      final before = repo.callCount;
      c.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
        startDay: DateTime.utc(2026, 3, 1),
        endDay: DateTime.utc(2026, 3, 14),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-range-apply')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom-range-dialog')), findsNothing);
      expect(c.read(customAnalyticsWindowProvider), _win(2026, 3, 1, 14));
      expect(c.read(analyticsWindowProvider).inclusiveDayCount, 14);
      expect(
        repo.callCount,
        before + 1,
        reason: 'Apply is ONE new request, not one per draft edit',
      );
      expect(repo.calls.last.window, _win(2026, 3, 1, 14));
    });

    testWidgets('a same-day custom window is valid and commits', (
      tester,
    ) async {
      _size(tester, const Size(1280, 2400));
      final c = _container(_CountingRepository());
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('range-chip-custom')));
      await tester.pumpAndSettle();

      c.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
        startDay: DateTime.utc(2026, 3, 5),
        endDay: DateTime.utc(2026, 3, 5),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-range-apply')));
      await tester.pumpAndSettle();

      expect(c.read(analyticsWindowProvider).inclusiveDayCount, 1);
    });
  });

  // ==========================================================================
  // H. Validation boundaries, as the sheet presents them
  // ==========================================================================
  group('F2.H validation gates Apply and explains itself', () {
    Future<ProviderContainer> openSheet(WidgetTester tester) async {
      _size(tester, const Size(1280, 2400));
      final c = _container(_CountingRepository());
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('range-chip-custom')));
      await tester.pumpAndSettle();
      return c;
    }

    bool applyEnabled(WidgetTester tester) =>
        tester
            .widget<FilledButton>(find.byKey(const Key('custom-range-apply')))
            .onPressed !=
        null;

    testWidgets('an empty draft cannot be applied and says why', (
      tester,
    ) async {
      await openSheet(tester);
      expect(applyEnabled(tester), isFalse);
      expect(find.byKey(const Key('custom-range-error')), findsOneWidget);
    });

    testWidgets('one endpoint only is incomplete, not a half-open range', (
      tester,
    ) async {
      final c = await openSheet(tester);
      c.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
        startDay: DateTime.utc(2026, 3, 1),
      );
      await tester.pumpAndSettle();
      expect(applyEnabled(tester), isFalse);
      expect(find.text('Pick a start and end date'), findsOneWidget);
    });

    testWidgets('a reversed range is refused and NEVER silently swapped', (
      tester,
    ) async {
      final c = await openSheet(tester);
      c.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
        startDay: DateTime.utc(2026, 3, 10),
        endDay: DateTime.utc(2026, 3, 1),
      );
      await tester.pumpAndSettle();
      expect(applyEnabled(tester), isFalse);
      expect(
        find.text('The end date cannot be before the start date'),
        findsOneWidget,
      );
      // The draft still holds what was picked — no quiet correction.
      expect(
        c.read(customRangeDraftProvider).startDay,
        DateTime.utc(2026, 3, 10),
      );
    });

    testWidgets('92 inclusive days is valid; 93 is refused and NOT truncated', (
      tester,
    ) async {
      final c = await openSheet(tester);
      final start = DateTime.utc(2026, 1, 1);

      c.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
        startDay: start,
        endDay: start.add(const Duration(days: 91)),
      );
      await tester.pumpAndSettle();
      expect(applyEnabled(tester), isTrue, reason: '92 days is the boundary');
      expect(find.byKey(const Key('custom-range-error')), findsNothing);

      c.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
        startDay: start,
        endDay: start.add(const Duration(days: 92)),
      );
      await tester.pumpAndSettle();
      expect(applyEnabled(tester), isFalse);
      expect(find.text('Choose at most 92 days'), findsOneWidget);
      expect(
        c.read(customRangeDraftProvider).endDay,
        start.add(const Duration(days: 92)),
        reason: 'the over-long selection is shown back, not trimmed to 92',
      );
    });
  });

  // ==========================================================================
  // I / J. Session restore, and returning to a preset
  // ==========================================================================
  group('F2.I custom and preset hand over cleanly', () {
    testWidgets('selecting a preset clears the committed custom window and '
        'sends a preset token with no dates', (tester) async {
      _size(tester, const Size(1280, 2400));
      final repo = _CountingRepository();
      final c = _container(repo);
      addTearDown(c.dispose);
      c.read(customAnalyticsWindowProvider.notifier).state = _win(
        2026,
        3,
        1,
        14,
      );
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      expect(c.read(analyticsWindowProvider).isCustom, isTrue);

      await tester.tap(find.byKey(const Key('range-chip-last60')));
      await tester.pumpAndSettle();

      expect(c.read(customAnalyticsWindowProvider), isNull);
      expect(
        c.read(analyticsWindowProvider),
        const AnalyticsWindow.preset(AnalyticsRange.last60),
      );
      expect(repo.calls.last.range, ReportRange.last60);
      expect(
        repo.calls.last.window,
        isNull,
        reason: 'a preset must never carry custom dates',
      );
    });

    testWidgets('reopening Custom after a preset detour restores the last '
        'valid dates as a DRAFT — the committed window stays the preset', (
      tester,
    ) async {
      _size(tester, const Size(1280, 2400));
      final c = _container(_CountingRepository());
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();

      // Commit a custom window through the real Apply path.
      await tester.tap(find.byKey(const Key('range-chip-custom')));
      await tester.pumpAndSettle();
      c.read(customRangeDraftProvider.notifier).state = CustomRangeDraft(
        startDay: DateTime.utc(2026, 3, 1),
        endDay: DateTime.utc(2026, 3, 14),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-range-apply')));
      await tester.pumpAndSettle();

      // Detour through a preset.
      await tester.tap(find.byKey(const Key('range-chip-last7')));
      await tester.pumpAndSettle();
      expect(c.read(customAnalyticsWindowProvider), isNull);

      // Reopen: the draft is seeded, but nothing is committed until Apply.
      await tester.tap(find.byKey(const Key('range-chip-custom')));
      await tester.pumpAndSettle();
      expect(
        c.read(customRangeDraftProvider).startDay,
        DateTime.utc(2026, 3, 1),
      );
      expect(
        c.read(customRangeDraftProvider).endDay,
        DateTime.utc(2026, 3, 14),
      );
      expect(
        c.read(analyticsWindowProvider),
        const AnalyticsWindow.preset(AnalyticsRange.last7),
        reason: 'reopening the sheet must not re-commit the old window',
      );
    });

    testWidgets('rapid preset switching yields one distinct request each, in '
        'order — no stale key reuse', (tester) async {
      _size(tester, const Size(1280, 2400));
      final repo = _CountingRepository();
      final c = _container(repo);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();

      for (final id in const ['last30', 'last60', 'last90']) {
        await tester.tap(find.byKey(Key('range-chip-$id')));
        await tester.pumpAndSettle();
      }
      final ranges = repo.calls.map((c) => c.range).toList();
      expect(
        ranges,
        containsAllInOrder(const [
          ReportRange.last30,
          ReportRange.last60,
          ReportRange.last90,
        ]),
      );
      expect(
        c.read(analyticsWindowProvider),
        const AnalyticsWindow.preset(AnalyticsRange.last90),
      );
    });
  });

  // ==========================================================================
  // K. Comparison labels — the F2.1 bug
  // ==========================================================================
  group('F2.K the comparison sentence describes the SELECTED window', () {
    late AppLocalizations en;

    setUpAll(() async {
      en = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('today keeps its partial-vs-complete honesty wording', () {
      const w = AnalyticsWindow.preset(AnalyticsRange.today);
      expect(
        analyticsComparisonKindOf(w),
        AnalyticsComparisonKind.partialVsCompletePriorDay,
      );
      expect(analyticsComparisonTitle(en, w), 'Compared with all of yesterday');
      expect(analyticsComparisonDeltaLabel(en, w, 12), contains('yesterday'));
    });

    test('every preset names its own prior window', () {
      for (final (range, expected) in const [
        (AnalyticsRange.yesterday, 'Compared with the day before'),
        (AnalyticsRange.last7, 'Compared with the previous 7 days'),
        (AnalyticsRange.last30, 'Compared with the previous 30 days'),
        (AnalyticsRange.last60, 'Compared with the previous 60 days'),
        (AnalyticsRange.last90, 'Compared with the previous 90 days'),
      ]) {
        expect(
          analyticsComparisonTitle(en, AnalyticsWindow.preset(range)),
          expected,
          reason: '${range.wire} heading',
        );
      }
    });

    test('THE BUG: a 14-day custom window says 14, never 30', () {
      final w = _win(2026, 3, 1, 14);
      expect(
        analyticsComparisonTitle(en, w),
        'Compared with the previous 14 days',
      );
      expect(
        analyticsComparisonTitle(en, w),
        isNot(contains('30')),
        reason: 'this is exactly the sentence that used to be wrong',
      );
      expect(analyticsComparisonDeltaLabel(en, w, 8), '8% vs previous 14 days');
    });

    test('a custom window that really IS 30 days may say 30 — the wording '
        'follows the length, not the preset-ness', () {
      expect(
        analyticsComparisonTitle(en, _win(2026, 3, 1, 30)),
        'Compared with the previous 30 days',
      );
    });

    test('a one-day custom window compares against the day before', () {
      expect(
        analyticsComparisonTitle(en, _win(2026, 3, 5, 1)),
        'Compared with the day before',
      );
    });

    test('every custom length has a sentence, and it always states that '
        'length', () {
      for (final days in const [2, 3, 13, 45, 61, 91, 92]) {
        final title = analyticsComparisonTitle(en, _win(2026, 1, 1, days));
        expect(title, contains('$days'), reason: '$days-day window');
      }
    });

    testWidgets('and the Overview renders it — a committed 14-day window shows '
        'the 14-day sentence', (tester) async {
      _size(tester, const Size(1280, 2600));
      final c = _container(_CountingRepository());
      addTearDown(c.dispose);
      c.read(customAnalyticsWindowProvider.notifier).state = _win(
        2026,
        3,
        1,
        14,
      );
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();

      expect(find.textContaining('previous 30 days'), findsNothing);
    });
  });

  // ==========================================================================
  // L. Orders-history drill-down carries the range
  // ==========================================================================
  group('F2.L drill-downs preserve the selected window', () {
    Future<void> drill(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => const OrdersHistoryDrillDown(
                  payment: PaymentFilter.unpaid,
                  status: OrderStatusFilter.completed,
                  orderType: OrderTypeFilter.dineIn,
                ).applyFilters(ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('a preset 60 arrives as last60, not today', (tester) async {
      final c = _container(_CountingRepository());
      addTearDown(c.dispose);
      c.read(reportRangeProvider.notifier).state = ReportRange.last60;
      await drill(tester, c);

      final q = c.read(orderHistoryQueryProvider);
      expect(q.range, OrderHistoryRange.last60);
      expect(q.customWindow, isNull);
    });

    testWidgets('a preset 90 arrives as last90', (tester) async {
      final c = _container(_CountingRepository());
      addTearDown(c.dispose);
      c.read(reportRangeProvider.notifier).state = ReportRange.last90;
      await drill(tester, c);
      expect(c.read(orderHistoryQueryProvider).range, OrderHistoryRange.last90);
    });

    testWidgets('a custom window arrives with its exact dates, and the other '
        'filters still apply', (tester) async {
      final c = _container(_CountingRepository());
      addTearDown(c.dispose);
      c.read(customAnalyticsWindowProvider.notifier).state = _win(
        2026,
        3,
        1,
        14,
      );
      await drill(tester, c);

      final q = c.read(orderHistoryQueryProvider);
      expect(q.customWindow, _win(2026, 3, 1, 14));
      expect(q.isCustomWindow, isTrue);
      expect(q.payment, PaymentFilter.unpaid);
      expect(q.status, OrderStatusFilter.completed);
      expect(q.orderType, OrderTypeFilter.dineIn);
    });
  });

  // ==========================================================================
  // M. Picker localization safety (source-level, not calendar internals)
  // ==========================================================================
  group('F2.M the platform picker is never handed English', () {
    test('no label override is passed to showDateRangePicker, so '
        'MaterialLocalizations supplies them per locale', () {
      // The test runner's cwd differs between `flutter test apps/dashboard` and
      // running from inside the package, so the source is located rather than
      // assumed — a wrong path here would make this guard pass vacuously.
      const rel = 'lib/src/analytics/custom_range_sheet.dart';
      final file = [
        File(rel),
        File('apps/dashboard/$rel'),
        File('../$rel'),
      ].firstWhere((f) => f.existsSync(), orElse: () => File(rel));
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'sheet source must be readable (cwd: ${Directory.current.path})',
      );
      final src = file.readAsStringSync();
      expect(src, contains('showDateRangePicker'));

      // The repo's hardcoded-string guard does NOT scan these parameters, so a
      // literal here would ship untranslated into an Arabic RTL sheet with CI
      // green. This assertion is the guard that does not exist elsewhere.
      for (final param in const [
        'helpText:',
        'confirmText:',
        'saveText:',
        'cancelText:',
        'errorFormatText:',
        'errorInvalidText:',
        'errorInvalidRangeText:',
        'fieldStartHintText:',
        'fieldEndHintText:',
        'fieldStartLabelText:',
        'fieldEndLabelText:',
      ]) {
        expect(
          src.contains(param),
          isFalse,
          reason: '$param must be left to MaterialLocalizations',
        );
      }
    });
  });
}
