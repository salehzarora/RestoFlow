import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/widgets/kds_ticket_card.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DESIGN-001: the live ticket card's elapsed-time/urgency signal.
///
/// Elapsed is computed at BUILD from an injected clock — deliberately no
/// timer (the KDS test corpus pumpAndSettles; the live board rebuilds on
/// every sync poll, which refreshes the value). Urgency escalates through
/// the shared [RestoflowUrgency] thresholds. Money-free stays money-free.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

final DateTime _now = DateTime(2026, 7, 5, 12, 0);

KdsTicketView _ticket({DateTime? submittedAt, KitchenTicketStatus? status}) =>
    KdsTicketView(
      kitchenTicketId: 'o1:grill',
      stationId: 'grill',
      status: status ?? KitchenTicketStatus.inPreparation,
      orderId: 'o1',
      orderNumber: '#ABC123',
      items: [const KdsItemView(name: 'Burger', quantity: 2)],
      submittedAt: submittedAt,
    );

Widget _harness(AppLocalizations l10n, KdsTicketView ticket) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  theme: restoflowBaseTheme(brightness: Brightness.dark),
  home: Scaffold(
    body: SizedBox(
      width: 420,
      child: KdsTicketCard(
        ticket: ticket,
        l10n: l10n,
        now: _now,
        onAdvance: (_) {},
        onRecall: null,
      ),
    ),
  ),
);

void main() {
  testWidgets('elapsed pill renders with the shared urgency tones', (
    tester,
  ) async {
    final l10n = await _en();
    const cases = <(int, RestoflowTone)>[
      (2, RestoflowTone.info),
      (12, RestoflowTone.warning),
      (25, RestoflowTone.danger),
    ];
    for (final (minutesAgo, expectedTone) in cases) {
      await tester.pumpWidget(
        _harness(
          l10n,
          _ticket(submittedAt: _now.subtract(Duration(minutes: minutesAgo))),
        ),
      );
      await tester.pumpAndSettle();

      final pillFinder = find.byKey(const Key('elapsed-o1:grill'));
      expect(pillFinder, findsOneWidget);
      final pill = tester.widget<RestoflowStatusPill>(pillFinder);
      expect(pill.tone, expectedTone);
      expect(pill.label, l10n.kdsElapsedMinutes(minutesAgo));
    }
  });

  testWidgets('no submittedAt -> no elapsed pill (never a fabricated age)', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(_harness(l10n, _ticket()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('elapsed-o1:grill')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clock skew (future submittedAt) clamps to 0m and stays calm', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(
      _harness(
        l10n,
        _ticket(submittedAt: _now.add(const Duration(minutes: 5))),
      ),
    );
    await tester.pumpAndSettle();

    final pill = tester.widget<RestoflowStatusPill>(
      find.byKey(const Key('elapsed-o1:grill')),
    );
    expect(pill.tone, RestoflowTone.info);
    expect(pill.label, l10n.kdsElapsedMinutes(0));
  });

  testWidgets('the card stays money-free with the elapsed pill shown', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(
      _harness(
        l10n,
        _ticket(submittedAt: _now.subtract(const Duration(minutes: 25))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('₪'), findsNothing);
    expect(find.textContaining('\$'), findsNothing);
    expect(find.textContaining('minor'), findsNothing);
  });

  testWidgets('a bumped (cleared) ticket dims; active tickets do not', (
    tester,
  ) async {
    final l10n = await _en();
    bool dimmedCardPresent() => tester
        .widgetList<Opacity>(find.byType(Opacity))
        .any((w) => w.opacity == 0.62);

    await tester.pumpWidget(
      _harness(l10n, _ticket(status: KitchenTicketStatus.bumped)),
    );
    await tester.pumpAndSettle();
    expect(dimmedCardPresent(), isTrue);

    await tester.pumpWidget(
      _harness(l10n, _ticket(status: KitchenTicketStatus.ready)),
    );
    await tester.pumpAndSettle();
    expect(dimmedCardPresent(), isFalse);
  });

  testWidgets('a failed print job renders in the danger tone with retry', (
    tester,
  ) async {
    final l10n = await _en();
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        theme: restoflowBaseTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: KdsTicketCard(
              ticket: _ticket(),
              l10n: l10n,
              now: _now,
              onAdvance: (_) {},
              onRecall: null,
              printStatus: KdsTicketPrintStatus(
                label: l10n.printStatusFailed,
                isError: true,
                onRetry: () => retried++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statusRow = find.byKey(const Key('ticket-print-status'));
    expect(statusRow, findsOneWidget);

    final context = tester.element(statusRow);
    final danger = RestoflowTone.danger.styleOf(Theme.of(context)).accent;
    final label = tester.widget<Text>(
      find.descendant(
        of: statusRow,
        matching: find.textContaining(l10n.printStatusFailed),
      ),
    );
    expect(label.style?.color, danger);
    expect(label.style?.fontWeight, FontWeight.w600);

    await tester.tap(find.byKey(const Key('ticket-print-retry')));
    await tester.pumpAndSettle();
    expect(retried, 1);
  });
}
