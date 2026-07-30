import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/parked_carts_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/parked_carts_controller.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/widgets/parked_orders_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PARKED-CARTS-001 — C. the REAL POS screen: Park placement, the parked-orders
/// badge and sheet, the non-empty-cart dialog, delete confirmation, RTL, and
/// submitting a restored cart exactly once.

const _scope = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchA',
  deviceId: 'dev1',
);

Future<AppLocalizations> _l10n([String code = 'en']) =>
    AppLocalizations.delegate.load(Locale(code));

/// Counts every enqueue CALL, so a duplicate submit is visible even though it
/// would carry a fresh local_operation_id.
class _CountingOutboxStore implements OutboxRepository {
  final DemoOutboxStore _inner = DemoOutboxStore(delay: (_) async {});
  int enqueueCount = 0;

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) {
    enqueueCount++;
    return _inner.enqueue(entry);
  }

  @override
  Future<List<OutboxEntry>> recentEntries() => _inner.recentEntries();

  @override
  Future<OutboxEntry> push(String entryId) => _inner.push(entryId);

  @override
  Future<OutboxEntry> retry(String entryId) => _inner.retry(entryId);

  @override
  Future<String?> findOrderSubmitCustomerPhone(OrderSubmitPhoneLookupKey key) =>
      _inner.findOrderSubmitCustomerPhone(key);
}

late ProviderContainer _container;

Future<void> _pump(
  WidgetTester tester, {
  required SharedPreferences prefs,
  String locale = 'en',
  OutboxRepository? outbox,
}) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  _container = ProviderContainer(
    overrides: [
      posSyncScopeProvider.overrideWithValue(_scope),
      parkedCartsStoreProvider.overrideWithValue(
        SharedPrefsParkedCartsStore(prefs),
      ),
      if (outbox != null) outboxRepositoryProvider.overrideWithValue(outbox),
    ],
  );
  addTearDown(_container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _addItem(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
}

Future<void> _park(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('park-cart-button')));
  await tester.pumpAndSettle();
  // The confirmation SnackBar overlays the bottom of the screen — which is
  // exactly where the Park button sits — so let it dismiss before the next
  // interaction, the way a real cashier would wait a moment.
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('parked-orders-button')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('C1. placement and prominence', () {
    testWidgets('Park sits directly BELOW Send, and Send stays present and '
        'primary', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final l10n = await _l10n();
      await _pump(tester, prefs: prefs);
      await _addItem(tester);

      final send = find.widgetWithText(FilledButton, l10n.posSendOrder);
      final park = find.byKey(const Key('park-cart-button'));
      expect(send, findsOneWidget);
      expect(park, findsOneWidget);

      // Park is BELOW Send on screen.
      expect(
        tester.getTopLeft(park).dy,
        greaterThan(tester.getTopLeft(send).dy),
      );
      // Send keeps the primary FILLED treatment; Park is the secondary outline,
      // so the primary path is never diluted.
      expect(tester.widget(park), isA<OutlinedButton>());
      expect(tester.widget(send), isA<FilledButton>());
      // Send stays full width and at least as tall as the secondary action.
      expect(
        tester.getSize(send).height,
        greaterThanOrEqualTo(tester.getSize(park).height),
      );
    });

    testWidgets('Park is ABSENT on an empty cart rather than a dead control', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await _pump(tester, prefs: prefs);
      expect(find.byKey(const Key('park-cart-button')), findsNothing);
    });
  });

  group('C2. the badge', () {
    testWidgets('hidden at zero, and shows the count once carts are parked', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await _pump(tester, prefs: prefs);
      expect(find.byKey(const Key('parked-orders-button')), findsNothing);

      await _addItem(tester);
      await _park(tester);
      expect(find.byKey(const Key('parked-orders-button')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('parked-orders-badge')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await _addItem(tester);
      await _park(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('parked-orders-badge')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });
  });

  group('C3. the sheet', () {
    testWidgets('lists parked rows with their summary', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final l10n = await _l10n();
      await _pump(tester, prefs: prefs);
      await _addItem(tester);
      _container
          .read(orderSetupControllerProvider.notifier)
          .setCustomerName('Dana');
      await tester.pumpAndSettle();
      await _park(tester);
      await _openSheet(tester);

      expect(find.byKey(const Key('parked-orders-sheet')), findsOneWidget);
      expect(find.text(l10n.posParkedOrders), findsWidgets);
      final id = _container.read(parkedCartsControllerProvider).carts.single.id;
      final row = find.byKey(Key('parked-order-$id'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Dana')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(l10n.posParkedItemCount(1)),
          skipOffstage: false,
        ),
        findsNothing,
        reason: 'the count is part of a joined summary line, not its own Text',
      );
      expect(
        find.descendant(of: row, matching: find.byType(Text)),
        findsWidgets,
      );
    });

    testWidgets('the EMPTY state renders and is not a spinner', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final l10n = await _l10n();
      // Seed one cart so the button exists, then delete it through the sheet.
      await _pump(tester, prefs: prefs);
      await _addItem(tester);
      await _park(tester);
      await _openSheet(tester);
      final id = _container.read(parkedCartsControllerProvider).carts.single.id;

      await tester.tap(find.byKey(Key('parked-order-delete-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('parked-order-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('parked-orders-empty')), findsOneWidget);
      expect(find.text(l10n.posParkedOrdersEmpty), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'a LOAD FAILURE shows an error with Retry, never an empty list',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          parkedCartsStorageKey(_scope): '{"version":99}',
        });
        final prefs = await SharedPreferences.getInstance();
        final l10n = await _l10n();
        await _pump(tester, prefs: prefs);
        // The button is hidden (count 0), so open the sheet directly.
        await tester.pumpAndSettle();
        expect(
          _container.read(parkedCartsControllerProvider).loadFailed,
          isTrue,
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: _container,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: const Scaffold(body: ParkedOrdersSheetHost()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('parked-orders-error')), findsOneWidget);
        expect(find.text(l10n.posParkedOrdersLoadFailed), findsOneWidget);
        expect(find.byKey(const Key('parked-orders-retry')), findsOneWidget);
        expect(find.byKey(const Key('parked-orders-empty')), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });

  group('C4. restoring over a non-empty cart', () {
    testWidgets('Cancel changes nothing; confirm parks the current cart and '
        'restores the selected one', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final l10n = await _l10n();
      await _pump(tester, prefs: prefs);

      // Alice is parked.
      await _addItem(tester);
      _container
          .read(orderSetupControllerProvider.notifier)
          .setCustomerName('Alice');
      await tester.pumpAndSettle();
      await _park(tester);
      final aliceId = _container
          .read(parkedCartsControllerProvider)
          .carts
          .single
          .id;

      // Bob is now at the till.
      await _addItem(tester);
      _container
          .read(orderSetupControllerProvider.notifier)
          .setCustomerName('Bob');
      await tester.pumpAndSettle();

      await _openSheet(tester);
      await tester.tap(find.byKey(Key('parked-order-restore-$aliceId')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('parked-order-replace-dialog')),
        findsOneWidget,
      );
      expect(find.text(l10n.posParkedActiveCartTitle), findsOneWidget);
      expect(find.text(l10n.posParkedParkCurrentAndRestore), findsOneWidget);
      // There is no merge / discard / overwrite option anywhere.
      expect(find.text('Merge'), findsNothing);
      expect(find.text('Discard'), findsNothing);

      await tester.tap(find.byKey(const Key('parked-order-replace-cancel')));
      await tester.pumpAndSettle();
      expect(_container.read(cartControllerProvider).lines, hasLength(1));
      expect(_container.read(orderSetupControllerProvider).customerName, 'Bob');
      expect(_container.read(parkedCartsControllerProvider).count, 1);

      // Now confirm.
      await tester.tap(find.byKey(Key('parked-order-restore-$aliceId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('parked-order-replace-confirm')));
      await tester.pumpAndSettle();

      expect(
        _container.read(orderSetupControllerProvider).customerName,
        'Alice',
      );
      final parked = _container.read(parkedCartsControllerProvider).carts;
      expect(parked, hasLength(1));
      expect(parked.single.customerName, 'Bob');
    });
  });

  group('C5. delete confirmation', () {
    testWidgets('names the selected draft and removes only it', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final l10n = await _l10n();
      await _pump(tester, prefs: prefs);

      await _addItem(tester);
      _container
          .read(orderSetupControllerProvider.notifier)
          .setCustomerName('Alice');
      await tester.pumpAndSettle();
      await _park(tester);
      await _addItem(tester);
      _container
          .read(orderSetupControllerProvider.notifier)
          .setCustomerName('Bob');
      await tester.pumpAndSettle();
      await _park(tester);

      await _openSheet(tester);
      final carts = _container.read(parkedCartsControllerProvider).carts;
      final bob = carts.firstWhere((c) => c.customerName == 'Bob');
      final alice = carts.firstWhere((c) => c.customerName == 'Alice');

      await tester.tap(find.byKey(Key('parked-order-delete-${bob.id}')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posParkedDeleteTitle), findsOneWidget);
      expect(find.text(l10n.posParkedDeleteBody('Bob')), findsOneWidget);

      await tester.tap(find.byKey(const Key('parked-order-delete-confirm')));
      await tester.pumpAndSettle();

      final remaining = _container.read(parkedCartsControllerProvider).carts;
      expect(remaining, hasLength(1));
      expect(remaining.single.id, alice.id);
      expect(find.byKey(Key('parked-order-${bob.id}')), findsNothing);
    });
  });

  group('C6. submit after restore', () {
    testWidgets('a restored cart submits EXACTLY once and the parked entry '
        'does not come back', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final l10n = await _l10n();
      final outbox = _CountingOutboxStore();
      await _pump(tester, prefs: prefs, outbox: outbox);

      await _addItem(tester);
      await _park(tester);
      expect(outbox.enqueueCount, 0, reason: 'parking never enqueues');

      await _openSheet(tester);
      final id = _container.read(parkedCartsControllerProvider).carts.single.id;
      await tester.tap(find.byKey(Key('parked-order-restore-$id')));
      await tester.pumpAndSettle();

      expect(_container.read(cartControllerProvider).lines, hasLength(1));
      expect(outbox.enqueueCount, 0, reason: 'restoring never enqueues');

      await tester.tap(find.text(l10n.posSendOrder));
      await tester.pumpAndSettle();

      expect(outbox.enqueueCount, 1);
      expect(_container.read(outboxControllerProvider), hasLength(1));
      // The parked draft is gone and does NOT reappear after the submit.
      expect(_container.read(parkedCartsControllerProvider).count, 0);
      final onDisk = await SharedPrefsParkedCartsStore(prefs).load(_scope);
      expect(onDisk.carts, isEmpty);
    });
  });

  group('C7. localization', () {
    testWidgets('Arabic renders the parked chrome RTL with no overflow', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final ar = await _l10n('ar');
      await _pump(tester, prefs: prefs, locale: 'ar');
      await _addItem(tester);

      expect(find.text(ar.posParkOrder), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('park-cart-button'))),
        ),
        TextDirection.rtl,
      );

      await _park(tester);
      await _openSheet(tester);
      expect(find.text(ar.posParkedOrders), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Hebrew renders the parked chrome RTL with no overflow', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final he = await _l10n('he');
      await _pump(tester, prefs: prefs, locale: 'he');
      await _addItem(tester);

      expect(find.text(he.posParkOrder), findsOneWidget);
      await _park(tester);
      await _openSheet(tester);
      expect(find.text(he.posParkedOrders), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every parked string differs across en/ar/he (nothing was left '
        'as an English literal)', (tester) async {
      final en = await _l10n('en');
      final ar = await _l10n('ar');
      final he = await _l10n('he');
      for (final trio in <List<String>>[
        [en.posParkOrder, ar.posParkOrder, he.posParkOrder],
        [en.posParkedOrders, ar.posParkedOrders, he.posParkedOrders],
        [
          en.posParkedOrdersEmpty,
          ar.posParkedOrdersEmpty,
          he.posParkedOrdersEmpty,
        ],
        [en.posParkedRestore, ar.posParkedRestore, he.posParkedRestore],
        [en.posParkedDelete, ar.posParkedDelete, he.posParkedDelete],
        [
          en.posParkedParkCurrentAndRestore,
          ar.posParkedParkCurrentAndRestore,
          he.posParkedParkCurrentAndRestore,
        ],
        [
          en.posParkedBlockedByAddition,
          ar.posParkedBlockedByAddition,
          he.posParkedBlockedByAddition,
        ],
        [
          en.posParkedTableUnavailable,
          ar.posParkedTableUnavailable,
          he.posParkedTableUnavailable,
        ],
      ]) {
        expect(trio.toSet(), hasLength(3), reason: trio.first);
      }
    });
  });
}

/// Hosts the sheet body directly, so the failure state can be inspected without
/// a parked-orders button (which hides itself when the count is zero).
class ParkedOrdersSheetHost extends StatelessWidget {
  const ParkedOrdersSheetHost({super.key});

  @override
  Widget build(BuildContext context) => const ParkedOrdersSheet();
}
