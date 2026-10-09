/// ORDER-EDIT-001G — the Overview "Order edits" card.
///
/// The claims defended here: the block shows only when there is something to
/// say; the GROSS removed value is always beside the derived net change
/// (MONEY §12.2); reasons are labelled, never raw codes; staff rows follow
/// `staff_visible`; "Load more" follows the keyset cursor without duplicates;
/// money is never relabelled across currencies; support mode never asks; the
/// Overview refresh re-reads the block; nothing overflows at phone width, in
/// RTL or at 2x text; and a signed net change keeps its sign on the left of
/// the amount in Arabic and Hebrew.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/analytics/owner_order_edits_query_key.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/owner_order_edits.dart';
import 'package:restoflow_dashboard/src/data/owner_order_edits_repository.dart';
import 'package:restoflow_dashboard/src/format/money_format.dart';
import 'package:restoflow_dashboard/src/overview/order_edits_card.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/support/support_mode_scope.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _key = OwnerOrderEditsQueryKey(
  organizationId: 'org-1',
  restaurantId: null,
  branchId: null,
  range: AnalyticsRange.today,
  isDemoMode: true,
);

OrderEditFigures _f({
  int edits = 1,
  int orders = 1,
  int removed = 0,
  int out = 0,
  int inn = 0,
  int added = 0,
}) => OrderEditFigures(
  editCount: edits,
  editedOrderCount: orders,
  removedMinor: removed,
  replacedOutMinor: out,
  replacedInMinor: inn,
  addedMinor: added,
  netChangeMinor: inn + added - removed - out,
  grossRetiredMinor: removed + out,
);

OrderEditReportRow _row(int i, {String status = 'preparing'}) =>
    OrderEditReportRow(
      orderEditId: 'e-$i',
      orderId: 'o-$i',
      orderCode: '#ORD${i.toString().padLeft(3, '0')}',
      editNumber: 1,
      orderStatus: status,
      orderType: 'dine_in',
      createdAtLabel: '2026-10-09 12:${(10 + i).toString().padLeft(2, '0')}',
      currencyCode: 'ILS',
      figures: _f(removed: 1500, out: 4000, inn: 4000, added: 900),
      staffName: 'Amira',
      reasonCode: 'customer_changed_mind',
    );

/// A scriptable repository: page one, then the keyset pages, recording calls.
class _FakeRepo implements OwnerOrderEditsRepository {
  _FakeRepo({
    this.enabled = true,
    this.supported = true,
    this.staffVisible = true,
    this.currencyCodes = const ['ILS'],
    this.total = 3,
    this.firstPageSize = 2,
    this.summary,
    this.failure,
  });

  final bool enabled;
  final bool supported;
  final bool staffVisible;
  final List<String> currencyCodes;
  final int total;
  final int firstPageSize;
  final OrderEditFigures? summary;
  final Object? failure;

  final List<String?> cursors = <String?>[];
  int get calls => cursors.length;

  @override
  Future<OwnerOrderEdits> loadOrderEdits({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    String? reasonCode,
    int limit = kOrderEditsPageSize,
    String? cursor,
  }) async {
    cursors.add(cursor);
    final f = failure;
    if (f != null) throw f;
    if (!supported) return OwnerOrderEdits.unavailable(range.wire);
    final all = [for (var i = 1; i <= total; i++) _row(i)];
    // Page one is the first [firstPageSize]; a continuation re-sends the LAST
    // row of page one too, to prove the client dedupes by edit id.
    final page = cursor == null
        ? all.take(firstPageSize).toList()
        : all.skip(firstPageSize - 1).toList();
    final hasMore = cursor == null && total > firstPageSize;
    return OwnerOrderEdits(
      currencyCode: 'ILS',
      currencyCodes: total == 0 ? const [] : currencyCodes,
      rangeWire: range.wire,
      enabledInScope: enabled,
      staffVisible: staffVisible,
      summary:
          summary ??
          (total == 0
              ? OrderEditFigures.zero
              : _f(
                  edits: total,
                  orders: total,
                  removed: 1500 * total,
                  out: 4000 * total,
                  inn: 4000 * total,
                  added: 900 * total,
                )),
      byReason: total == 0
          ? const []
          : [
              OrderEditReasonRow(
                reasonCode: 'customer_changed_mind',
                figures: _f(removed: 1500, out: 4000, inn: 4000),
              ),
              OrderEditReasonRow(reasonCode: null, figures: _f(added: 900)),
            ],
      byStaff: staffVisible && total > 0
          ? [
              OrderEditStaffRow(
                staffName: 'Amira',
                figures: _f(edits: total),
              ),
            ]
          : const [],
      edits: page,
      count: page.length,
      matching: total,
      hasMore: hasMore,
      nextCursor: hasMore ? 'cursor-1' : null,
    );
  }
}

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The card alone, at the given width, locale and text scale.
Future<void> _pumpCard(
  WidgetTester tester,
  _FakeRepo repo, {
  String currency = 'ILS',
  String locale = 'en',
  double scale = 1,
  Size size = const Size(1320, 2400),
}) async {
  _size(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ownerOrderEditsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: OrderEditsCard(queryKey: _key, currencyCode: currency),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The whole Overview (demo report), with the block's repository swapped.
Future<void> _pumpOverview(
  WidgetTester tester,
  _FakeRepo repo, {
  bool supportMode = false,
}) async {
  _size(tester, const Size(1320, 3600));
  Widget home = const DashboardHomeScreen();
  if (supportMode) home = SupportModeScope(active: true, child: home);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ownerOrderEditsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The rendered paragraph inside [rowKey] whose text contains [needle].
RenderParagraph _paragraphIn(
  WidgetTester tester,
  String rowKey,
  String needle,
) => tester.renderObject<RenderParagraph>(
  find.descendant(
    of: find.byKey(Key(rowKey)),
    matching: find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(needle),
    ),
  ),
);

/// Where the sign of [minor] and its amount are DRAWN in [para]: the sign's
/// box and the left edge of the amount's boxes, in the paragraph's own space.
({TextBox sign, double figureLeft}) _signAndAmount(
  RenderParagraph para,
  int minor,
) {
  final text = para.text.toPlainText();
  final sign = minor < 0 ? '−' : '+';
  final amount = MoneyFormatter.formatMinor(minor.abs(), 'ILS');
  final signAt = text.lastIndexOf(sign);
  final amountAt = text.indexOf(amount, signAt);
  expect(signAt, greaterThanOrEqualTo(0), reason: 'sign in "$text"');
  expect(amountAt, signAt + 1, reason: 'amount follows the sign in "$text"');
  final signBoxes = para.getBoxesForSelection(
    TextSelection(baseOffset: signAt, extentOffset: signAt + 1),
  );
  final amountBoxes = para.getBoxesForSelection(
    TextSelection(baseOffset: amountAt, extentOffset: amountAt + amount.length),
  );
  return (
    sign: signBoxes.single,
    figureLeft: amountBoxes.map((b) => b.left).reduce(math.min),
  );
}

void main() {
  group('visibility on the Overview', () {
    testWidgets('shown for an enabled scope with edits', (tester) async {
      await _pumpOverview(tester, _FakeRepo());
      expect(find.byKey(const Key('order-edits-card')), findsOneWidget);
    });

    testWidgets('hidden when the reader is not deployed', (tester) async {
      await _pumpOverview(tester, _FakeRepo(supported: false));
      expect(find.byKey(const Key('order-edits-card')), findsNothing);
    });

    testWidgets('hidden when editing was never enabled and nothing was '
        'edited', (tester) async {
      await _pumpOverview(tester, _FakeRepo(enabled: false, total: 0));
      expect(find.byKey(const Key('order-edits-card')), findsNothing);
    });

    testWidgets('shown when switched off but edits exist', (tester) async {
      await _pumpOverview(tester, _FakeRepo(enabled: false));
      expect(find.byKey(const Key('order-edits-card')), findsOneWidget);
    });

    testWidgets('an error is shown, not hidden', (tester) async {
      await _pumpOverview(tester, _FakeRepo(failure: StateError('boom')));
      final l10n = await _l10n('en');
      expect(find.byKey(const Key('order-edits-error')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('order-edits-card')),
          matching: find.text(l10n.dashboardReportsError),
        ),
        findsOneWidget,
      );
    });

    testWidgets('support mode: no card and no request at all', (tester) async {
      final repo = _FakeRepo();
      await _pumpOverview(tester, repo, supportMode: true);
      expect(find.byKey(const Key('order-edits-card')), findsNothing);
      expect(repo.calls, 0);
    });

    testWidgets('the Overview refresh re-reads the block', (tester) async {
      final repo = _FakeRepo();
      await _pumpOverview(tester, repo);
      expect(repo.calls, 1);
      await tester.tap(find.byKey(const Key('reports-refresh-button')));
      await tester.pumpAndSettle();
      expect(repo.calls, 2);
      expect(repo.cursors.last, isNull, reason: 'a refresh is page one');
    });
  });

  group('the card body', () {
    testWidgets('empty state when enabled with no edits', (tester) async {
      await _pumpCard(tester, _FakeRepo(total: 0));
      final l10n = await _l10n('en');
      expect(find.byKey(const Key('order-edits-empty')), findsOneWidget);
      expect(find.text(l10n.dashboardOrderEditsEmpty), findsOneWidget);
      expect(find.byKey(const Key('order-edits-gross')), findsNothing);
    });

    testWidgets('gross removed value is always beside the net change', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _FakeRepo(
          total: 1,
          firstPageSize: 1,
          summary: _f(removed: 1500, out: 4000, inn: 4000, added: 900),
        ),
      );
      final l10n = await _l10n('en');
      expect(find.text(l10n.dashboardOrderEditsGrossRemoved), findsOneWidget);
      expect(find.text(l10n.dashboardOrderEditsNetChange), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('order-edits-gross')),
          matching: find.text(MoneyFormatter.formatMinor(5500, 'ILS')),
        ),
        findsOneWidget,
      );
      // −600, signed with the typographic minus, neutral.
      expect(
        find.descendant(
          of: find.byKey(const Key('order-edits-net')),
          matching: find.text('−${MoneyFormatter.formatMinor(600, 'ILS')}'),
        ),
        findsOneWidget,
      );
      for (final k in [
        'order-edits-removed',
        'order-edits-replaced-out',
        'order-edits-replaced-in',
        'order-edits-added',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('reasons are labelled; the null reason reads "Added"; no raw '
        'codes on screen', (tester) async {
      await _pumpCard(tester, _FakeRepo());
      final l10n = await _l10n('en');
      expect(
        find.descendant(
          of: find.byKey(const Key('order-edits-reason-customer_changed_mind')),
          matching: find.text(l10n.orderEditReasonCustomerChangedMind),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('order-edits-reason-none')),
          matching: find.text(l10n.dashboardOrderEditsAdded),
        ),
        findsOneWidget,
      );
      for (final raw in [
        'customer_changed_mind',
        'dine_in',
        'preparing',
        'kds',
      ]) {
        expect(find.textContaining(raw), findsNothing, reason: raw);
      }
    });

    testWidgets('staff rows follow staff_visible', (tester) async {
      await _pumpCard(tester, _FakeRepo());
      expect(find.byKey(const Key('order-edits-by-staff')), findsOneWidget);
      expect(find.byKey(const Key('order-edits-staff-0')), findsOneWidget);

      await _pumpCard(tester, _FakeRepo(staffVisible: false));
      expect(find.byKey(const Key('order-edits-by-staff')), findsNothing);
      expect(find.byKey(const Key('order-edits-staff-0')), findsNothing);
    });

    testWidgets('Load more appends page two without duplicates and the '
        'range text follows', (tester) async {
      final repo = _FakeRepo(total: 3, firstPageSize: 2);
      await _pumpCard(tester, repo);
      final l10n = await _l10n('en');
      expect(find.text(l10n.adminShowingRange(1, 2, 3)), findsOneWidget);
      expect(find.byKey(const Key('order-edits-row-e-3')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('order-edits-load-more')),
      );
      await tester.tap(find.byKey(const Key('order-edits-load-more')));
      await tester.pumpAndSettle();

      expect(repo.cursors, [null, 'cursor-1']);
      for (final id in ['e-1', 'e-2', 'e-3']) {
        expect(
          find.byKey(Key('order-edits-row-$id')),
          findsOneWidget,
          reason: '$id exactly once',
        );
      }
      expect(find.text(l10n.adminShowingRange(1, 3, 3)), findsOneWidget);
      expect(find.byKey(const Key('order-edits-load-more')), findsNothing);
    });

    testWidgets('a voided order is tagged', (tester) async {
      await _pumpCard(tester, _VoidedRepo());
      final l10n = await _l10n('en');
      expect(
        find.descendant(
          of: find.byKey(const Key('order-edits-row-e-9')),
          matching: find.textContaining(l10n.ordersStatusVoided),
        ),
        findsOneWidget,
      );
    });

    testWidgets('another currency: counts only, never relabelled money', (
      tester,
    ) async {
      await _pumpCard(tester, _FakeRepo(currencyCodes: const ['USD']));
      final l10n = await _l10n('en');
      expect(
        find.byKey(const Key('order-edits-currency-mixed')),
        findsOneWidget,
      );
      expect(find.text(l10n.dashboardCurrencyMixedTitle), findsOneWidget);
      expect(find.byKey(const Key('order-edits-gross')), findsNothing);
      expect(find.byKey(const Key('order-edits-net')), findsNothing);
      expect(find.byKey(const Key('order-edits-edit-count')), findsOneWidget);
      expect(find.textContaining('₪'), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('mixed currencies: counts only', (tester) async {
      await _pumpCard(tester, _FakeRepo(currencyCodes: const ['ILS', 'USD']));
      expect(
        find.byKey(const Key('order-edits-currency-mixed')),
        findsOneWidget,
      );
      expect(find.textContaining('₪'), findsNothing);
    });
  });

  group('layout', () {
    for (final locale in ['en', 'ar', 'he']) {
      for (final width in [390.0, 1320.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('no overflow: $locale, ${width.toInt()}px, ${scale}x', (
            tester,
          ) async {
            await _pumpCard(
              tester,
              _FakeRepo(),
              locale: locale,
              scale: scale,
              size: Size(width, 4000),
            );
            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('order-edits-card')), findsOneWidget);
            final card = tester.getRect(
              find.byKey(const Key('order-edits-card')),
            );
            expect(card.right, lessThanOrEqualTo(width));
          });
        }
      }
    }

    // A breakdown row's second line is a sentence in the ambient direction
    // with the signed net change at its end. In Arabic and Hebrew the sign
    // must still be DRAWN on the left of the amount, as the forced-LTR value
    // column draws it — never "₪15.00−".
    for (final code in ['ar', 'he']) {
      testWidgets('RTL $code: a breakdown net change keeps its sign on the '
          'left of the amount', (tester) async {
        await _pumpCard(tester, _FakeRepo(), locale: code);
        final l10n = await _l10n(code);
        for (final (rowKey, minor) in [
          ('order-edits-reason-customer_changed_mind', -1500),
          ('order-edits-reason-none', 900),
        ]) {
          final para = _paragraphIn(
            tester,
            rowKey,
            l10n.dashboardOrderEditsNetChange,
          );
          expect(para.textDirection, TextDirection.rtl);
          final at = _signAndAmount(para, minor);
          expect(
            at.sign.right,
            lessThanOrEqualTo(at.figureLeft + 0.01),
            reason: '$rowKey: the sign is drawn left of the amount',
          );
        }
      });
    }

    testWidgets('RTL: the Arabic and Hebrew titles render', (tester) async {
      for (final code in ['ar', 'he']) {
        await _pumpCard(tester, _FakeRepo(), locale: code);
        final l10n = await _l10n(code);
        expect(find.text(l10n.dashboardOrderEditsTitle), findsOneWidget);
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('order-edits-card'))),
          ),
          TextDirection.rtl,
        );
      }
    });
  });
}

/// One edit on an order voided after the edit.
class _VoidedRepo extends _FakeRepo {
  _VoidedRepo() : super(total: 1, firstPageSize: 1);

  @override
  Future<OwnerOrderEdits> loadOrderEdits({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    String? reasonCode,
    int limit = kOrderEditsPageSize,
    String? cursor,
  }) async {
    final base = await super.loadOrderEdits(range: range, cursor: cursor);
    return OwnerOrderEdits(
      currencyCode: base.currencyCode,
      currencyCodes: base.currencyCodes,
      rangeWire: base.rangeWire,
      enabledInScope: true,
      staffVisible: true,
      summary: base.summary,
      byReason: base.byReason,
      edits: [_row(9, status: 'voided')],
      count: 1,
      matching: 1,
    );
  }
}
