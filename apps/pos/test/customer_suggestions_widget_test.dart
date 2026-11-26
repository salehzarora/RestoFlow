import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/pos_customer_suggestions.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_pos/src/widgets/order_setup_section.dart';

const _match = PosCustomerSuggestion(name: 'محمد مسعود', phone: '050-1234567');
final _name = find.byKey(const Key('customer-name-field'));
final _phone = find.byKey(const Key('customer-phone-field'));
final _scope = StateProvider<String?>((_) => 'branch-a/cashier-a');
const _delay = Duration(milliseconds: 300);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  PosCustomerSuggestionsLookup lookup, {
  Locale locale = const Locale('ar'),
  Widget body = const SingleChildScrollView(child: OrderSetupSection()),
}) async {
  final container = ProviderContainer(
    overrides: [
      posCustomerSuggestionsLookupProvider.overrideWithValue(lookup),
      posCustomerSuggestionsScopeProvider.overrideWith(
        (ref) => ref.watch(_scope),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        theme: restoflowBaseTheme(),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

String _value(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

void main() {
  testWidgets(
    'debounced name lookup; explicit choice fills both editable fields',
    (tester) async {
      final calls = <String>[];
      final container = await _pump(tester, (q, {required byPhone}) async {
        calls.add(q);
        expect(byPhone, isFalse);
        return const [
          PosCustomerSuggestion(name: 'محمد مسعود', phone: '050-1111111'),
          _match,
        ];
      });
      await tester.enterText(_phone, '05');
      await tester.enterText(_name, 'م');
      await tester.pump(_delay);
      expect(calls, isEmpty);
      await tester.enterText(_name, 'مح');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(_name, 'محمد');
      await tester.pump(const Duration(milliseconds: 299));
      expect(calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(calls, ['محمد']);
      expect(find.text('محمد مسعود'), findsNWidgets(2));
      expect(find.text(_match.phone), findsNothing);
      expect(_value(tester, _phone), '05');
      await tester.tap(find.text('•••• 4567'));
      await tester.pump();
      expect(_value(tester, _name), _match.name);
      expect(_value(tester, _phone), _match.phone);
      final draft = container.read(orderSetupControllerProvider);
      expect(draft.customerName, _match.name);
      expect(draft.customerPhone, _match.phone);
      expect(find.byType(ListTile), findsNothing);
      await tester.enterText(_phone, '050-9876543');
      expect(
        container.read(orderSetupControllerProvider).customerPhone,
        '050-9876543',
      );
      container.read(orderSetupControllerProvider.notifier).reset();
      await tester.pump(_delay);
      expect(calls, ['محمد']);
      expect(_value(tester, _name), isEmpty);
      expect(_value(tester, _phone), isEmpty);
    },
  );

  testWidgets(
    'phone prefix accepts Arabic digits and heals partial validation on selection',
    (tester) async {
      final calls = <String>[];
      final c = await _pump(tester, (q, {required byPhone}) async {
        expect(byPhone, isTrue);
        calls.add(q);
        return const [_match];
      }, locale: const Locale('he'));
      await tester.enterText(_phone, '٠٥٠');
      await tester.pump(_delay);
      expect(calls, isEmpty);
      await tester.enterText(_phone, '٠٥٠-١');
      await tester.pump(_delay);
      await tester.pump();
      expect(calls, ['0501']);
      await tester.tap(find.text(_match.name));
      await tester.pump();
      expect(_value(tester, _phone), _match.phone);
      expect(_value(tester, _name), _match.name);
      expect(
        c.read(orderSetupControllerProvider).hasBlockingCustomerPhone,
        isFalse,
      );
      await tester.pump(_delay);
      expect(calls, hasLength(1));
    },
  );

  testWidgets(
    'stale results cannot cross edits, a reset, or a cashier switch',
    (tester) async {
      final pending = <Completer<List<PosCustomerSuggestion>>>[];
      final c = await _pump(tester, (q, {required byPhone}) {
        final reply = Completer<List<PosCustomerSuggestion>>();
        pending.add(reply);
        return reply.future;
      });
      await tester.enterText(_name, 'ما');
      await tester.pump(_delay);
      await tester.enterText(_name, 'ماهر');
      await tester.pump(_delay);
      pending[0].complete(const [_match]);
      await tester.pump();
      expect(find.text(_match.name), findsNothing);
      c.read(_scope.notifier).state = 'branch-b/cashier-b';
      pending[1].complete(const [_match]);
      await tester.pump();
      expect(find.text(_match.name), findsNothing);
      await tester.enterText(_name, 'محمد');
      await tester.pump(_delay);
      c.read(orderSetupControllerProvider.notifier).reset();
      pending[2].complete(const [_match]);
      await tester.pump();
      expect(find.text(_match.name), findsNothing);
      expect(_value(tester, _name), isEmpty);
      await tester.enterText(_name, 'مح');
      await tester.pump(_delay);
      pending[3].complete(const [_match]);
      await tester.pump();
      final staleTap = tester.widget<ListTile>(find.byType(ListTile)).onTap!;
      c.read(_scope.notifier).state = 'branch-c/cashier-b';
      staleTap();
      await tester.pump();
      expect(find.text(_match.name), findsNothing);
      expect(c.read(orderSetupControllerProvider).customerPhone, isNull);
      expect(_value(tester, _name), 'مح');
    },
  );

  testWidgets(
    'cart restore replaces both fields without disturbing manual composition',
    (tester) async {
      final c = await _pump(
        tester,
        (q, {required byPhone}) async => const [_match],
      );
      final setup = c.read(orderSetupControllerProvider.notifier);
      await tester.enterText(_name, 'مح');
      await tester.pump(_delay);
      await tester.pump();
      await tester.tap(find.text(_match.name));
      await tester.pump();
      // Restore a different parked order via the same pair of setters as the till.
      setup.setCustomerName('Dan');
      setup.setCustomerPhone('050-7654321');
      await tester.pump();
      expect(_value(tester, _name), 'Dan');
      expect(_value(tester, _phone), '050-7654321');

      await tester.showKeyboard(_name);
      const typing = TextEditingValue(
        text: '  מרים  ',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 2, end: 6),
      );
      tester.testTextInput.updateEditingValue(typing);
      await tester.pump();
      expect(c.read(orderSetupControllerProvider).customerName, 'מרים');
      setup.setCustomerPhone('050-7654322');
      await tester.pump(_delay);
      expect(tester.widget<TextField>(_name).controller!.value, typing);
      expect(_value(tester, _phone), '050-7654322');
    },
  );

  testWidgets(
    'a cashier can tap a match in the narrow cart with the keyboard open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(340, 760);
      addTearDown(tester.view.reset);
      final c = await _pump(
        tester,
        (q, {required byPhone}) async => const [_match],
        body: const CartPanel(),
      );
      c
          .read(cartControllerProvider.notifier)
          .addItem(
            const DemoMenuItem(
              id: 'fixture-item',
              name: 'Sandwich',
              priceMinor: 2500,
              categoryId: 'fixture-meals',
              categoryName: 'Meals',
            ),
          );
      await tester.pump();
      await tester.ensureVisible(_name);
      await tester.enterText(_name, 'مح');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump(_delay);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      final match = find.text(_match.name);
      await tester.ensureVisible(match);
      await tester.pumpAndSettle();
      expect(match.hitTestable(), findsOneWidget);
      await tester.tap(match);
      await tester.pump();
      expect(c.read(orderSetupControllerProvider).customerPhone, _match.phone);
      expect(_value(tester, _name), _match.name);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offline or failed lookup leaves manual ordering available', (
    tester,
  ) async {
    var calls = 0;
    final c = await _pump(tester, (q, {required byPhone}) {
      calls++;
      throw Exception('unavailable');
    }, locale: const Locale('en'));
    await tester.enterText(_name, 'Dana');
    await tester.pump(_delay);
    expect(calls, 1);
    expect(find.byType(ListTile), findsNothing);
    c.read(_scope.notifier).state = null;
    await tester.pump();
    await tester.enterText(_phone, '5551234567');
    await tester.pump(_delay);
    expect(calls, 1);
    expect(_value(tester, _phone), '5551234567');
    final draft = c.read(orderSetupControllerProvider);
    expect(draft.customerName, 'Dana');
    expect(draft.customerPhone, '5551234567');
    expect(draft.isReadyToSubmit, isTrue);
    expect(tester.takeException(), isNull);
  });
}
