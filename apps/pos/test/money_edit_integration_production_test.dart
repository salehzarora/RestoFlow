import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/order_submission.dart' show OutboxEntry;
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/format/money_format.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// MONEY-PRODUCTION-PATH-TESTS-002D [H] — the three corrections held TOGETHER.
///
/// One scenario exercises all of them at once, through the real POS screen, the
/// real cart controller, the real modifier sheet and the real outbox:
///
///   002A — the line is qty x (base + modifiers), at every quantity;
///   002B — the persisted draft decodes strictly, or not at all;
///   002C — the edit shows the FROZEN base, keeps an untouched selection's
///          stored price, takes the live price only on a deliberate re-pick,
///          and fails closed on a moved option — while the group id stays
///          LOCAL and never reaches the wire.
///
/// Every expected amount is an INDEPENDENT LITERAL.
///
/// Classification: REGRESSION PROOF — this is the combined final state the
/// corrective stack was built to reach.

const kFrozenBase = 4500;
const kLiveBase = 5000; // the Dashboard raised it AFTER the line existed
const k240 = 1500;
const k240Live = 2000; // ...and raised the surcharge too
const k360 = 2500;
// Independent literals.
const kConfiguredUnit = 6000; // 4500 + 1500
const kLineQty2 = 12000; // 6000 x 2

const _burgerAtAddTime = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kFrozenBase,
  categoryId: 'food',
  categoryName: 'Food',
);
const _burgerToday = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kLiveBase,
  categoryId: 'food',
  categoryName: 'Food',
);

const _meatRepriced = PosModifierGroup(
  id: 'grp-meat',
  menuItemId: 'burger-meat',
  name: 'Meat',
  singleSelect: true,
  isRequired: true,
  options: [
    PosModifierOption(id: 'opt-120', name: '120g', priceDeltaMinor: 0),
    PosModifierOption(id: 'opt-240', name: '240g', priceDeltaMinor: k240Live),
    PosModifierOption(id: 'opt-360', name: '360g', priceDeltaMinor: k360),
  ],
);

/// The same option, MOVED into another group and now free.
const _meatWithout240 = PosModifierGroup(
  id: 'grp-meat',
  menuItemId: 'burger-meat',
  name: 'Meat',
  maxSelect: 3,
  options: [PosModifierOption(id: 'opt-120', name: '120g', priceDeltaMinor: 0)],
);
const _chefsWith240 = PosModifierGroup(
  id: 'grp-chefs',
  menuItemId: 'burger-meat',
  name: "Chef's choice",
  maxSelect: 2,
  options: [
    PosModifierOption(id: 'opt-240', name: 'House cut', priceDeltaMinor: 0),
  ],
);

/// The STORED selection, expressed as the persisted record and decoded by the
/// real 002B/002C decoder — never hand-constructed.
final _stored240 = SelectedModifier.fromJson(const <String, Object?>{
  'option_id': 'opt-240',
  'modifier_group_id': 'grp-meat',
  'group_name': 'Meat',
  'option_name': '240g',
  'price_delta_minor': k240,
  'quantity': 1,
});

PosMenuData _menu(List<PosModifierGroup> groups, DemoMenuItem item) =>
    PosMenuData(
      categories: const [
        DemoCategory(
          id: 'food',
          name: 'Food',
          icon: Icons.lunch_dining,
          color: Colors.orange,
        ),
      ],
      items: [item],
      currencyCode: 'ILS',
      modifierGroups: groups,
    );

class _RecordingRepo implements OutboxRepository {
  final List<OutboxEntry> enqueued = <OutboxEntry>[];
  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    enqueued.add(entry);
    return entry;
  }

  @override
  Future<List<OutboxEntry>> recentEntries() async => List.of(enqueued);
  @override
  Future<OutboxEntry> push(String entryId) async =>
      enqueued.firstWhere((e) => e.id == entryId);
  @override
  Future<OutboxEntry> retry(String entryId) async =>
      enqueued.firstWhere((e) => e.id == entryId);
  @override
  Future<String?> findOrderSubmitCustomerPhone(
    OrderSubmitPhoneLookupKey key,
  ) async => null;
}

String money(int minor) => MoneyFormatter.formatMinor(minor, 'ILS');

Future<ProviderContainer> pumpConfigured(
  WidgetTester tester, {
  required List<PosModifierGroup> groups,
  DemoMenuItem liveItem = _burgerToday,
  _RecordingRepo? repo,
}) async {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      posMenuProvider.overrideWith((ref) async => _menu(groups, liveItem)),
      if (repo != null) outboxRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  // The line was added when the product cost 4500 — that is what freezes.
  c.read(cartControllerProvider.notifier).addItemWithModifiers(
    _burgerAtAddTime,
    [_stored240],
  );
  final lineId = c.read(cartControllerProvider).lines.single.lineId;
  c.read(cartControllerProvider.notifier).increaseQuantity(lineId);

  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return c;
}

Future<void> openEdit(WidgetTester tester, ProviderContainer c) async {
  final lineId = c.read(cartControllerProvider).lines.first.lineId;
  final edit = find.byKey(Key('cart-edit-$lineId'));
  await tester.ensureVisible(edit);
  await tester.tap(edit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(ModifierSelectionSheet), findsOneWidget);
}

Finder confirm() => find.byKey(const Key('modifier-add-button'));
bool saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(confirm()).onPressed != null;

void main() {
  testWidgets('H1 an UNCHANGED edit after a Dashboard price rise keeps the '
      'frozen base AND the stored surcharge, and the sheet shows what it '
      'will save', (tester) async {
    final c = await pumpConfigured(tester, groups: const [_meatRepriced]);
    expect(
      c.read(cartControllerProvider).lines.single.lineTotalMinor,
      kLineQty2,
    );

    await openEdit(tester, c);
    // 002C: frozen 4500 base, stored 1500 surcharge -> 6000 per unit.
    expect(find.text(money(kConfiguredUnit)), findsWidgets);
    expect(
      find.text(money(kLiveBase + k240Live)),
      findsNothing,
      reason: 'neither the live base nor the live delta may appear',
    );

    await tester.tap(confirm());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final line = c.read(cartControllerProvider).lines.single;
    expect(line.unitPriceMinor, kFrozenBase);
    expect(line.modifiers.single.priceDeltaMinor, k240);
    expect(line.lineTotalMinor, kLineQty2, reason: '002A: qty x configured');
    expect(c.read(cartControllerProvider).subtotalMinor, kLineQty2);
  });

  testWidgets('H2 an INTENTIONAL replacement takes the live price, keeps the '
      'frozen base, and leaves a sibling line alone', (tester) async {
    final c = await pumpConfigured(tester, groups: const [_meatRepriced]);
    c.read(cartControllerProvider.notifier).addItemWithModifiers(
      _burgerAtAddTime,
      [_stored240],
    );
    await tester.pump();
    final siblingId = c.read(cartControllerProvider).lines.last.lineId;

    await openEdit(tester, c);
    await tester.tap(find.text('360g'));
    await tester.pump();
    // 2 x (4500 + 2500) = 14000 — displayed BEFORE saving.
    expect(find.text(money(kFrozenBase + k360)), findsWidgets);
    await tester.tap(confirm());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final lines = c.read(cartControllerProvider).lines;
    final edited = lines.first;
    expect(edited.unitPriceMinor, kFrozenBase, reason: 'base stays frozen');
    expect(edited.modifiers.single.priceDeltaMinor, k360);
    expect(edited.lineTotalMinor, 14000);

    final sibling = lines.firstWhere((l) => l.lineId == siblingId);
    expect(sibling.modifiers.single.priceDeltaMinor, k240);
    expect(sibling.lineTotalMinor, kFrozenBase + k240);
  });

  testWidgets('H3 a MOVED option blocks Save and leaves the original group id, '
      'option and money untouched', (tester) async {
    final c = await pumpConfigured(
      tester,
      groups: const [_meatWithout240, _chefsWith240],
    );
    await openEdit(tester, c);
    expect(saveEnabled(tester), isFalse);
    expect(
      find.byKey(const Key('modifier-saved-options-changed')),
      findsOneWidget,
    );

    // Dismiss; nothing moved.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final m = c.read(cartControllerProvider).lines.single.modifiers.single;
    expect(m.modifierGroupId, 'grp-meat');
    expect(m.optionId, 'opt-240');
    expect(m.priceDeltaMinor, k240);
    expect(
      c.read(cartControllerProvider).lines.single.lineTotalMinor,
      kLineQty2,
    );
  });

  testWidgets('H4 submitting AFTER a healthy unchanged edit puts the frozen '
      'money on the wire and the local group id nowhere', (tester) async {
    final repo = _RecordingRepo();
    final c = await pumpConfigured(
      tester,
      groups: const [_meatRepriced],
      repo: repo,
    );

    await openEdit(tester, c);
    await tester.tap(confirm());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final view = c.read(cartControllerProvider);
    await c
        .read(outboxControllerProvider.notifier)
        .submit(
          lines: view.lines,
          subtotalMinor: view.subtotalMinor,
          currencyCode: view.currencyCode,
          orderType: OrderType.takeaway,
        );

    expect(repo.enqueued, hasLength(1));
    final raw = repo.enqueued.single.payloadJson;
    final payload = jsonDecode(raw) as Map<String, Object?>;
    final item = ((payload['order_items']! as List).first as Map)
        .cast<String, Object?>();
    final mod = ((item['modifiers']! as List).first as Map)
        .cast<String, Object?>();

    expect(item['unit_price_minor_snapshot'], kFrozenBase);
    expect(item['quantity'], 2);
    expect(item['line_total_minor'], kLineQty2);
    expect(mod['price_minor_snapshot'], k240);
    expect(mod['quantity'], 1);
    expect(payload['subtotal_minor'], kLineQty2);
    // 002C: local-only metadata, and the idempotency fingerprint contract is
    // therefore unchanged for every configured order.
    expect(raw.contains('modifier_group_id'), isFalse);
    expect(raw.contains('grp-meat'), isFalse);
  });

  testWidgets('H5 the corrected formula holds at quantity 1, 2 and 3 through '
      'the same edit path', (tester) async {
    for (final qty in <int>[1, 2, 3]) {
      final c = await pumpConfigured(tester, groups: const [_meatRepriced]);
      final lineId = c.read(cartControllerProvider).lines.single.lineId;
      // pumpConfigured already stepped it to 2.
      if (qty == 1) {
        c.read(cartControllerProvider.notifier).decreaseQuantity(lineId);
      } else if (qty == 3) {
        c.read(cartControllerProvider.notifier).increaseQuantity(lineId);
      }
      await tester.pump();

      await openEdit(tester, c);
      // The sheet always configures ONE unit.
      expect(find.text(money(kConfiguredUnit)), findsWidgets);
      await tester.tap(confirm());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        c.read(cartControllerProvider).lines.single.lineTotalMinor,
        qty * kConfiguredUnit,
        reason: 'qty $qty x 6000',
      );
    }
  });
}
