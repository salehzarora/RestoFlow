import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart' show PosMenuScreen;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/open_orders_strip.dart';
import 'package:restoflow_pos/src/widgets/order_detail_preview.dart';

/// POS-OPEN-ORDERS-STRIP-011 — the open-orders strip on the POS main screen:
/// membership (the canonical Open predicate), newest-first order, card
/// content/fallbacks, soft status tones, tap-to-preview action parity,
/// elapsed-time rendering + injectable ticker, and responsive/RTL safety.
///
/// Clock: pinned per RF-CI-POS-RECENT-ORDERS-CLOCK-ROT — fixtures anchor to
/// [_pinnedNow] and the controller prunes with the SAME injected clock, so
/// nothing ages out on a calendar boundary.
final DateTime _pinnedNow = DateTime.utc(2026, 8, 13, 12);
DateTime _clock() => _pinnedNow;

Future<AppLocalizations> _l10n([String code = 'en']) =>
    AppLocalizations.delegate.load(Locale(code));

SubmittedOrderView _view(
  String number, {
  String? customerName,
  String? tableLabel,
  OrderType orderType = OrderType.takeaway,
}) => SubmittedOrderView(
  orderNumber: number,
  orderType: orderType,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  orderId: 'oid-$number',
  customerName: customerName,
  tableLabel: tableLabel,
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: 4200,
      currencyCode: 'ILS',
    ),
  ],
);

PosRecentOrder _order(
  String number, {
  String? status,
  Duration age = const Duration(minutes: 7),
  String? customerName,
  String? tableLabel,
  OrderType orderType = OrderType.takeaway,
  DateTime? voidedAt,
  PosOrderOrigin origin = PosOrderOrigin.deviceOwned,
}) => PosRecentOrder(
  order: _view(
    number,
    customerName: customerName,
    tableLabel: tableLabel,
    orderType: orderType,
  ),
  origin: origin,
  status: status,
  submittedAt: _pinnedNow.subtract(age),
  voidedAt: voidedAt,
  voidReason: voidedAt == null ? null : 'test',
);

Future<InMemoryRecentOrdersStore> _seeded(List<PosRecentOrder> orders) async {
  final store = InMemoryRecentOrdersStore();
  await store.persist(kDemoSyncScope.key, orders);
  return store;
}

Widget _app(
  InMemoryRecentOrdersStore store, {
  Locale locale = const Locale('en'),
  Duration? elapsedTick,
  DateTime Function()? clock,
}) => ProviderScope(
  overrides: [
    posRecentOrdersStoreProvider.overrideWithValue(store),
    // The demo snapshot feed adopts the whole branch; emptied so membership
    // assertions cover exactly the seeded fixtures.
    orderSnapshotRepositoryProvider.overrideWithValue(
      DemoOrderSnapshotRepository(),
    ),
    posSyncPollIntervalProvider.overrideWithValue(null),
    posSyncClockProvider.overrideWithValue(clock ?? _clock),
    if (elapsedTick != null)
      posOpenOrdersElapsedTickProvider.overrideWithValue(elapsedTick),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const PosMenuScreen(),
  ),
);

void _size(WidgetTester tester, [Size size = const Size(1400, 1000)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _card(String number) => find.byKey(Key('open-strip-order-$number'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M. Membership — the canonical Open predicate owns the strip', () {
    testWidgets('M1. every open status (and the not-yet-confirmed order) '
        'shows; terminal and draft rows never do', (tester) async {
      _size(tester);
      final store = await _seeded([
        _order('#S1', status: 'submitted'),
        _order('#A1', status: 'accepted', age: const Duration(minutes: 9)),
        _order('#PR1', status: 'preparing', age: const Duration(minutes: 11)),
        _order('#R1', status: 'ready', age: const Duration(minutes: 13)),
        _order('#SV1', status: 'served', age: const Duration(minutes: 15)),
        _order('#NULL1', age: const Duration(minutes: 17)),
        _order('#C1', status: 'completed', age: const Duration(minutes: 19)),
        _order('#X1', status: 'cancelled', age: const Duration(minutes: 21)),
        _order(
          '#V1',
          status: 'voided',
          age: const Duration(minutes: 23),
          voidedAt: _pinnedNow.subtract(const Duration(minutes: 1)),
        ),
        _order(
          '#D1',
          age: const Duration(minutes: 25),
          origin: PosOrderOrigin.localDraft,
        ),
      ]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open-orders-strip')), findsOneWidget);
      for (final open in ['#S1', '#A1', '#PR1', '#R1', '#SV1', '#NULL1']) {
        // The strip is a horizontal viewport — membership means the card is
        // reachable, so scroll it into view before asserting.
        await tester.scrollUntilVisible(
          _card(open),
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('open-orders-strip')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(_card(open), findsOneWidget, reason: '$open must be open');
      }
      for (final gone in ['#C1', '#X1', '#V1', '#D1']) {
        expect(_card(gone), findsNothing, reason: '$gone must be excluded');
      }
    });

    testWidgets('M2. newest-first: the controller order is preserved, at the '
        'inline START in both directions', (tester) async {
      _size(tester);
      final store = await _seeded([
        _order('#OLD', status: 'submitted', age: const Duration(minutes: 40)),
        _order('#NEW', status: 'submitted', age: const Duration(minutes: 2)),
      ]);
      // LTR: newest at the left.
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(_card('#NEW')).dx,
        lessThan(tester.getTopLeft(_card('#OLD')).dx),
      );
      // RTL: newest at the right (inline-start).
      await tester.pumpWidget(
        _app(
          await _seeded([
            _order(
              '#OLD',
              status: 'submitted',
              age: const Duration(minutes: 40),
            ),
            _order(
              '#NEW',
              status: 'submitted',
              age: const Duration(minutes: 2),
            ),
          ]),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(_card('#NEW')).dx,
        greaterThan(tester.getTopLeft(_card('#OLD')).dx),
      );
    });

    testWidgets('M3. zero open orders hide the strip COMPLETELY — the grid '
        'gets every pixel back', (tester) async {
      _size(tester);
      final store = await _seeded([_order('#C1', status: 'completed')]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-orders-strip')), findsNothing);
      expect(find.byType(GridView), findsWidgets);
    });

    testWidgets('M4. an order leaving the open state disappears on the SAME '
        'authoritative controller update — no UI callback removes cards', (
      tester,
    ) async {
      _size(tester);
      final store = await _seeded([_order('#U1', status: 'submitted')]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(_card('#U1'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PosMenuScreen)),
      );
      container
          .read(posRecentOrdersControllerProvider.notifier)
          .markVoided(PosOrderIdentity.server('oid-#U1'), 'wrong order');
      await tester.pumpAndSettle();
      expect(_card('#U1'), findsNothing);
    });
  });

  group('C. Card content', () {
    testWidgets('C1. customer + table TOGETHER when both are known; each '
        'alone otherwise; order type when neither', (tester) async {
      _size(tester);
      final l10n = await _l10n();
      final store = await _seeded([
        _order('#B1', status: 'ready', customerName: 'Ahmed', tableLabel: '7'),
        _order(
          '#T1',
          status: 'ready',
          tableLabel: '8',
          age: const Duration(minutes: 9),
        ),
        _order(
          '#N1',
          status: 'ready',
          customerName: 'Dana',
          age: const Duration(minutes: 11),
        ),
        _order(
          '#E1',
          status: 'ready',
          orderType: OrderType.dineIn,
          age: const Duration(minutes: 13),
        ),
      ]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: _card('#B1'),
          matching: find.text('Ahmed · ${l10n.posTableLabel} 7'),
        ),
        findsOneWidget,
        reason: 'both known -> BOTH shown on one line',
      );
      expect(
        find.descendant(
          of: _card('#T1'),
          matching: find.text('${l10n.posTableLabel} 8'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _card('#N1'), matching: find.text('Dana')),
        findsOneWidget,
      );
      // The cart's own order-type segmented also says "Dine-in" — scope to
      // the card.
      expect(
        find.descendant(
          of: _card('#E1'),
          matching: find.text(l10n.posOrderTypeDineIn),
        ),
        findsOneWidget,
      );
    });

    testWidgets('C2. elapsed labels: now / minutes / hours+minutes, from the '
        'injected clock', (tester) async {
      _size(tester);
      final l10n = await _l10n();
      final store = await _seeded([
        _order('#NOW', status: 'submitted', age: const Duration(seconds: 20)),
        _order('#M7', status: 'submitted', age: const Duration(minutes: 7)),
        _order(
          '#H1',
          status: 'submitted',
          age: const Duration(hours: 1, minutes: 5),
        ),
      ]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posOpenOrdersElapsedNow), findsOneWidget);
      expect(find.text(l10n.posOpenOrdersElapsedMinutes(7)), findsOneWidget);
      expect(
        find.text(l10n.posOpenOrdersElapsedHoursMinutes(1, 5)),
        findsOneWidget,
      );
    });

    testWidgets('C3. every card carries the localized status TEXT + icon — '
        'never color alone; the unconfirmed order says so in words', (
      tester,
    ) async {
      _size(tester);
      final l10n = await _l10n();
      final store = await _seeded([
        _order('#PR1', status: 'preparing'),
        _order('#NULL1', age: const Duration(minutes: 9)),
      ]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posOrdersStatusPreparing), findsOneWidget);
      expect(
        find.descendant(
          of: _card('#PR1'),
          matching: find.byIcon(Icons.local_fire_department_outlined),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.posOfflineAwaitingSync), findsOneWidget);
      expect(
        find.descendant(of: _card('#NULL1'), matching: find.byIcon(Icons.sync)),
        findsOneWidget,
      );
    });
  });

  group('T. Soft status tones (strip-local urgency mapping)', () {
    test('T1. the mapping is exactly the owner-approved table', () {
      expect(posOpenOrderStripTone('submitted'), RestoflowTone.danger);
      expect(posOpenOrderStripTone('accepted'), RestoflowTone.warning);
      expect(posOpenOrderStripTone('preparing'), RestoflowTone.warning);
      expect(posOpenOrderStripTone('ready'), RestoflowTone.success);
      expect(posOpenOrderStripTone('served'), RestoflowTone.success);
      expect(posOpenOrderStripTone(null), RestoflowTone.neutral);
      expect(posOpenOrderStripTone('weird-token'), RestoflowTone.neutral);
    });

    testWidgets('T2. the card bed is the SOFT semantic container, never the '
        'saturated accent', (tester) async {
      _size(tester);
      final store = await _seeded([
        _order('#S1', status: 'submitted'),
        _order('#PR1', status: 'preparing', age: const Duration(minutes: 9)),
        _order('#R1', status: 'ready', age: const Duration(minutes: 11)),
      ]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.byType(PosMenuScreen)));
      for (final (code, tone) in [
        ('#S1', RestoflowTone.danger),
        ('#PR1', RestoflowTone.warning),
        ('#R1', RestoflowTone.success),
      ]) {
        final material = tester.widget<Material>(
          find.ancestor(of: _card(code), matching: find.byType(Material)).first,
        );
        expect(
          material.color,
          tone.styleOf(theme).container,
          reason: '$code bed must be the soft $tone container',
        );
        expect(
          material.color,
          isNot(tone.styleOf(theme).accent),
          reason: '$code must never use the saturated accent as a bed',
        );
      }
    });
  });

  group('I. Interaction — the existing preview, the existing actions', () {
    testWidgets('I1. tapping a card opens OrderDetailPreview and the shared '
        'assembly offers the SAME payment action the Orders sheet would', (
      tester,
    ) async {
      _size(tester);
      final store = await _seeded([_order('#U1', status: 'submitted')]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();

      await tester.tap(_card('#U1'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderDetailPreview), findsOneWidget);
      // Unpaid, no pending work -> the preview's action row offers payment
      // (the exact keyPrefix contract of the existing preview surface).
      expect(find.byKey(const Key('preview-pay-#U1')), findsOneWidget);
    });

    testWidgets('I3. the preview HEADER now reads type · table · customer '
        'together when both are known (existing-surface enhancement)', (
      tester,
    ) async {
      _size(tester);
      final l10n = await _l10n();
      final store = await _seeded([
        _order(
          '#B1',
          status: 'ready',
          customerName: 'Ahmed',
          tableLabel: '7',
          orderType: OrderType.dineIn,
        ),
      ]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      await tester.tap(_card('#B1'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(OrderDetailPreview),
          matching: find.text(
            '${l10n.posOrderTypeDineIn} · ${l10n.posTableLabel} 7 · Ahmed',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('I2. the whole card is one >=44dp tap target', (tester) async {
      _size(tester);
      final store = await _seeded([_order('#U1', status: 'submitted')]);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      final size = tester.getSize(_card('#U1'));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    });
  });

  group('E. Elapsed ticker', () {
    testWidgets('E1. the minute tick repaints the elapsed TEXT with no order '
        'refresh — and is disposed with the strip', (tester) async {
      _size(tester);
      final l10n = await _l10n();
      var now = _pinnedNow;
      final store = await _seeded([
        _order('#M7', status: 'submitted', age: const Duration(minutes: 7)),
      ]);
      await tester.pumpWidget(
        _app(store, elapsedTick: const Duration(seconds: 1), clock: () => now),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(l10n.posOpenOrdersElapsedMinutes(7)), findsOneWidget);

      // Time advances; the NEXT tick repaints the label without any provider
      // update or network pull.
      now = _pinnedNow.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1, milliseconds: 100));
      expect(find.text(l10n.posOpenOrdersElapsedMinutes(12)), findsOneWidget);

      // Tear the tree down: a leaked periodic timer would fail the test
      // binding here.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('R. Responsive / RTL / text scale', () {
    for (final (locale, size) in const [
      (Locale('ar'), Size(1280, 800)),
      (Locale('he'), Size(1280, 800)),
      (Locale('en'), Size(1440, 900)),
      (Locale('ar'), Size(1024, 600)),
      (Locale('en'), Size(1024, 600)),
      (Locale('ar'), Size(834, 1112)),
      (Locale('ar'), Size(430, 932)),
      (Locale('he'), Size(390, 844)),
      (Locale('en'), Size(390, 844)),
    ]) {
      testWidgets('R1. no strip overflow at ${size.width.toInt()}x'
          '${size.height.toInt()} in ${locale.languageCode}', (tester) async {
        _size(tester, size);
        final overflows = <String>[];
        final prior = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) {
            overflows.add(details.toString());
          } else {
            prior?.call(details);
          }
        };
        final store = await _seeded([
          _order(
            '#B1',
            status: 'submitted',
            customerName: 'Ahmed Houshan',
            tableLabel: '4',
          ),
          _order(
            '#PR1',
            status: 'preparing',
            age: const Duration(minutes: 9),
            tableLabel: '8',
          ),
          _order(
            '#R1',
            status: 'ready',
            age: const Duration(hours: 1, minutes: 5),
            customerName: 'Dana',
          ),
        ]);
        await tester.pumpWidget(_app(store, locale: locale));
        await tester.pumpAndSettle();
        FlutterError.onError = prior;
        expect(find.byKey(const Key('open-orders-strip')), findsOneWidget);
        expect(
          overflows.where((d) => d.contains('open_orders_strip.dart')),
          isEmpty,
          reason: '${locale.languageCode}@${size.width}: strip overflow',
        );
      });
    }

    testWidgets('R2. at 2x text scale the number and status survive; the '
        'metadata line is shed on the compact band', (tester) async {
      _size(tester, const Size(1024, 600));
      final l10n = await _l10n();
      final overflows = <String>[];
      final prior = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) {
          overflows.add(details.toString());
        } else {
          prior?.call(details);
        }
      };
      final store = await _seeded([
        _order(
          '#B1',
          status: 'preparing',
          customerName: 'Ahmed Houshan',
          tableLabel: '4',
        ),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posRecentOrdersStoreProvider.overrideWithValue(store),
            orderSnapshotRepositoryProvider.overrideWithValue(
              DemoOrderSnapshotRepository(),
            ),
            posSyncPollIntervalProvider.overrideWithValue(null),
            posSyncClockProvider.overrideWithValue(_clock),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            builder: (context, app) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: app!,
            ),
            home: const PosMenuScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      FlutterError.onError = prior;
      expect(find.text('#B1'), findsOneWidget);
      expect(find.text(l10n.posOrdersStatusPreparing), findsOneWidget);
      // The metadata line yields at 2x on the compact band.
      expect(
        find.text('Ahmed Houshan · ${l10n.posTableLabel} 4'),
        findsNothing,
      );
      expect(
        overflows.where((d) => d.contains('open_orders_strip.dart')),
        isEmpty,
        reason: '2x scale: strip overflow',
      );
    });
  });
}
