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
import 'package:restoflow_pos/src/data/parked_carts_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MONEY-EDIT-INTEGRITY-002C — the guarantees the two corrections buy, pinned
/// where they can regress: LEGACY records without a group id, the local
/// serialization contract, the wire isolation, and the 002A formula.
///
/// `modifierGroupId` is LOCAL edit-safety metadata. The tests below are as much
/// about where it must NOT appear as where it must.

const kBase = 4500;
const k240 = 1500;
const k360 = 2500;

const burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'food',
  categoryName: 'Food',
);

const meatGroup = PosModifierGroup(
  id: 'grp-meat',
  menuItemId: 'burger-meat',
  name: 'Meat',
  singleSelect: true,
  isRequired: true,
  options: [
    PosModifierOption(id: 'opt-120', name: '120g', priceDeltaMinor: 0),
    PosModifierOption(id: 'opt-240', name: '240g', priceDeltaMinor: k240),
    PosModifierOption(id: 'opt-360', name: '360g', priceDeltaMinor: k360),
  ],
);

/// The SAME group, renamed in the Dashboard. Its id is unchanged — which is
/// exactly the point: a current record survives a rename, a legacy one cannot.
const meatGroupRenamed = PosModifierGroup(
  id: 'grp-meat',
  menuItemId: 'burger-meat',
  name: 'Cut',
  singleSelect: true,
  isRequired: true,
  options: [
    PosModifierOption(id: 'opt-120', name: '120g', priceDeltaMinor: 0),
    PosModifierOption(id: 'opt-240', name: '240g', priceDeltaMinor: k240),
    PosModifierOption(id: 'opt-360', name: '360g', priceDeltaMinor: k360),
  ],
);

/// A SECOND group that also carries opt-240 — the ambiguous legacy case.
const rivalGroupWith240 = PosModifierGroup(
  id: 'grp-rival',
  menuItemId: 'burger-meat',
  name: 'Chef cut',
  options: [PosModifierOption(id: 'opt-240', name: '240g', priceDeltaMinor: 0)],
);

/// Two live groups sharing ONE display name — a legacy record naming that name
/// cannot be attributed to either without guessing.
const twinA = PosModifierGroup(
  id: 'grp-twin-a',
  menuItemId: 'burger-meat',
  name: 'Meat',
  options: [
    PosModifierOption(id: 'opt-240', name: '240g', priceDeltaMinor: k240),
  ],
);
const twinB = PosModifierGroup(
  id: 'grp-twin-b',
  menuItemId: 'burger-meat',
  name: 'Meat',
  options: [
    PosModifierOption(id: 'opt-999', name: 'Other', priceDeltaMinor: 100),
  ],
);

Map<String, Object?> storedModifier({
  Object? groupId = 'grp-meat',
  String groupName = 'Meat',
  bool omitGroupId = false,
}) => <String, Object?>{
  'option_id': 'opt-240',
  if (!omitGroupId) 'modifier_group_id': groupId,
  'group_name': groupName,
  'option_name': '240g',
  'price_delta_minor': k240,
  'quantity': 1,
};

/// A LEGACY selection: no group id at all, exactly as records were written
/// before this phase.
final legacy240 = SelectedModifier.fromJson(storedModifier(omitGroupId: true));

/// A CURRENT selection carrying its proven group id.
final current240 = SelectedModifier.fromJson(storedModifier());

PosMenuData menuWith(List<PosModifierGroup> groups) => PosMenuData(
  categories: const [
    DemoCategory(
      id: 'food',
      name: 'Food',
      icon: Icons.lunch_dining,
      color: Colors.orange,
    ),
  ],
  items: const [burger],
  currencyCode: 'ILS',
  modifierGroups: groups,
);

Future<ProviderContainer> pump(
  WidgetTester tester, {
  required List<PosModifierGroup> groups,
  required List<SelectedModifier> selections,
}) async {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      posMenuProvider.overrideWith((ref) async => menuWith(groups)),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(cartControllerProvider.notifier)
      .addItemWithModifiers(burger, selections);

  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

CartViewState viewOf(ProviderContainer c) => c.read(cartControllerProvider);

Future<void> openEdit(WidgetTester tester, ProviderContainer c) async {
  final lineId = viewOf(c).lines.first.lineId;
  final edit = find.byKey(Key('cart-edit-$lineId'));
  await tester.ensureVisible(edit);
  await tester.tap(edit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(ModifierSelectionSheet), findsOneWidget);
}

/// Captures every enqueued entry so the persisted payload can be inspected.
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

Finder confirmButton() => find.byKey(const Key('modifier-add-button'));

bool saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(confirmButton()).onPressed != null;

Future<void> save(WidgetTester tester) async {
  await tester.tap(confirmButton());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // =========================================================================
  group(
    'B. removed groups and options stay blocked (MONEY-001 regression)',
    () {
      testWidgets('B1 the whole group is gone', (tester) async {
        final c = await pump(
          tester,
          groups: const [],
          selections: [current240],
        );
        await openEdit(tester, c);
        // No groups at all -> the note-only route, which cannot touch money.
        expect(
          find.byKey(const Key('modifier-options-unavailable')),
          findsOneWidget,
        );
        expect(viewOf(c).lines.single.lineTotalMinor, kBase + k240);
      });

      testWidgets('B2 the option is gone from the group that owns it', (
        tester,
      ) async {
        const without240 = PosModifierGroup(
          id: 'grp-meat',
          menuItemId: 'burger-meat',
          name: 'Meat',
          singleSelect: true,
          isRequired: true,
          options: [
            PosModifierOption(id: 'opt-120', name: '120g', priceDeltaMinor: 0),
          ],
        );
        final c = await pump(
          tester,
          groups: const [without240],
          selections: [current240],
        );
        await openEdit(tester, c);
        expect(saveEnabled(tester), isFalse);
        expect(viewOf(c).lines.single.modifiers.single.priceDeltaMinor, k240);
      });

      testWidgets('B3 no partial list is ever installed — every original '
          'selection is still on the line', (tester) async {
        final extras = SelectedModifier.fromJson(const <String, Object?>{
          'option_id': 'opt-gone',
          'modifier_group_id': 'grp-meat',
          'group_name': 'Meat',
          'option_name': 'Vanished',
          'price_delta_minor': 700,
          'quantity': 1,
        });
        final c = await pump(
          tester,
          groups: const [meatGroup],
          selections: [current240, extras],
        );
        await openEdit(tester, c);
        expect(saveEnabled(tester), isFalse);
        expect(viewOf(c).lines.single.modifiers, hasLength(2));
        expect(viewOf(c).lines.single.lineTotalMinor, kBase + k240 + 700);
      });
    },
  );

  // =========================================================================
  group('C. a healthy same-group edit still works end to end', () {
    testWidgets('C1 unchanged Save preserves the money exactly', (
      tester,
    ) async {
      final c = await pump(
        tester,
        groups: const [meatGroup],
        selections: [current240],
      );
      await openEdit(tester, c);
      expect(saveEnabled(tester), isTrue);
      await save(tester);
      final line = viewOf(c).lines.single;
      expect(line.modifiers.single.priceDeltaMinor, k240);
      expect(line.lineTotalMinor, kBase + k240);
    });

    testWidgets('C2 a RENAMED group still resolves for a CURRENT record — the '
        'id outlives the label', (tester) async {
      final c = await pump(
        tester,
        groups: const [meatGroupRenamed],
        selections: [current240],
      );
      await openEdit(tester, c);
      expect(
        saveEnabled(tester),
        isTrue,
        reason: 'grp-meat still owns opt-240; only its display name changed',
      );
      await save(tester);
      expect(viewOf(c).lines.single.lineTotalMinor, kBase + k240);
    });

    testWidgets('C3 changing the option reprices ONLY the edited line', (
      tester,
    ) async {
      final c = await pump(
        tester,
        groups: const [meatGroup],
        selections: [current240],
      );
      c.read(cartControllerProvider.notifier).addItemWithModifiers(burger, [
        current240,
      ]);
      await tester.pump();
      final siblingId = viewOf(c).lines.last.lineId;

      await openEdit(tester, c);
      await tester.tap(find.text('360g'));
      await tester.pump();
      await save(tester);

      final lines = viewOf(c).lines;
      expect(lines.first.lineTotalMinor, kBase + k360);
      expect(
        lines.firstWhere((l) => l.lineId == siblingId).lineTotalMinor,
        kBase + k240,
      );
    });
  });

  // =========================================================================
  group('D. LEGACY records without a group id', () {
    testWidgets('D1 a legacy record whose group NAME still agrees is editable, '
        'and a healthy Save persists the PROVEN group id', (tester) async {
      final c = await pump(
        tester,
        groups: const [meatGroup],
        selections: [legacy240],
      );
      expect(viewOf(c).lines.single.modifiers.single.modifierGroupId, isNull);

      await openEdit(tester, c);
      expect(saveEnabled(tester), isTrue);
      await save(tester);

      final saved = viewOf(c).lines.single.modifiers.single;
      expect(
        saved.modifierGroupId,
        'grp-meat',
        reason: 'the relationship was proven, so the identity is now recorded',
      );
      expect(
        saved.priceDeltaMinor,
        k240,
        reason: 'nothing was re-selected, so nothing is re-priced',
      );
      expect(viewOf(c).lines.single.lineTotalMinor, kBase + k240);
    });

    testWidgets('D2 a legacy record whose group was RENAMED is unresolved — '
        'no silent attachment, no reprice', (tester) async {
      final c = await pump(
        tester,
        groups: const [meatGroupRenamed],
        selections: [legacy240],
      );
      await openEdit(tester, c);
      expect(saveEnabled(tester), isFalse);
      expect(
        find.byKey(const Key('modifier-saved-options-changed')),
        findsOneWidget,
      );
      final stored = viewOf(c).lines.single.modifiers.single;
      expect(stored.modifierGroupId, isNull);
      expect(stored.priceDeltaMinor, k240);
    });

    testWidgets('D3 an AMBIGUOUS legacy option (two live groups carry it) is '
        'unresolved — never an arbitrary first match', (tester) async {
      final c = await pump(
        tester,
        groups: const [meatGroup, rivalGroupWith240],
        selections: [legacy240],
      );
      await openEdit(tester, c);
      expect(
        saveEnabled(tester),
        isFalse,
        reason: 'grp-rival prices opt-240 at 0; guessing would zero the line',
      );
      expect(viewOf(c).lines.single.lineTotalMinor, kBase + k240);
    });

    testWidgets('D4 two live groups SHARING a display name cannot attribute a '
        'legacy record, even when only one holds the option', (tester) async {
      final c = await pump(
        tester,
        groups: const [twinA, twinB],
        selections: [legacy240],
      );
      await openEdit(tester, c);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('D5 a legacy line that is never EDITED stays valid and keeps '
        'its money', (tester) async {
      final c = await pump(
        tester,
        groups: const [meatGroupRenamed],
        selections: [legacy240],
      );
      final line = viewOf(c).lines.single;
      expect(line.lineTotalMinor, kBase + k240);
      expect(line.modifiers.single.modifierGroupId, isNull);
      // And it round-trips through local persistence untouched.
      final json = line.modifiers.single.toJson();
      expect(json.containsKey('modifier_group_id'), isFalse);
    });

    test('D6 a MALFORMED present group id rejects the whole record — it is '
        'never downgraded to "legacy absence"', () {
      for (final bad in <Object?>[
        null,
        '',
        '   ',
        7,
        true,
        <Object?>[],
        <String, Object?>{},
      ]) {
        expect(
          () => SelectedModifier.fromJson(storedModifier(groupId: bad)),
          throwsA(isA<FormatException>()),
          reason: 'a ${bad.runtimeType} group id must not become null',
        );
      }
    });

    test(
      'D7 and it invalidates the containing DRAFT under the 002B contract',
      () {
        final draft = <String, Object?>{
          'currency_code': 'ILS',
          'lines': [
            <String, Object?>{
              'menu_item_id': 'burger-meat',
              'name': 'Burger',
              'base_price_minor': kBase,
              'quantity': 1,
              'modifiers': [storedModifier(groupId: 7)],
            },
          ],
        };
        expect(
          () => CartDraftSnapshot.fromJson(draft),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  // =========================================================================
  group('G. serialization: local yes, wire no', () {
    test('G1 a proven group id survives a draft JSON round-trip', () {
      final draft = CartDraftSnapshot(
        currencyCode: 'ILS',
        lines: [
          CartDraftLine(
            menuItemId: 'burger-meat',
            name: 'Burger',
            basePriceMinor: kBase,
            quantity: 2,
            modifiers: [current240],
          ),
        ],
      );
      final back = CartDraftSnapshot.fromJson(
        jsonDecode(jsonEncode(draft.toJson())) as Map<String, Object?>,
      );
      final m = back.lines.single.modifiers.single;
      expect(m.modifierGroupId, 'grp-meat');
      expect(m.priceDeltaMinor, k240);
    });

    test('G2 a LEGACY record is not rewritten merely by loading it', () {
      final draft = <String, Object?>{
        'currency_code': 'ILS',
        'lines': [
          <String, Object?>{
            'menu_item_id': 'burger-meat',
            'name': 'Burger',
            'base_price_minor': kBase,
            'quantity': 1,
            'modifiers': [storedModifier(omitGroupId: true)],
          },
        ],
      };
      final back = CartDraftSnapshot.fromJson(draft);
      expect(back.lines.single.modifiers.single.modifierGroupId, isNull);
      // Re-serializing keeps the key ABSENT — byte-identical to what was read.
      expect(
        back.lines.single.modifiers.single.toJson().containsKey(
          'modifier_group_id',
        ),
        isFalse,
      );
    });

    test(
      'G3 the group id rides through a real PARKED CART round-trip',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsParkedCartsStore(prefs);
        const scope = PosSyncScope(
          organizationId: 'orgA',
          restaurantId: 'restA',
          branchId: 'branchA',
          deviceId: 'dev1',
        );
        await store.add(
          scope,
          (id) => ParkedCart(
            id: id,
            createdAt: DateTime.utc(2026, 8, 5, 9),
            updatedAt: DateTime.utc(2026, 8, 5, 9),
            orderType: OrderType.takeaway,
            draft: CartDraftSnapshot(
              currencyCode: 'ILS',
              lines: [
                CartDraftLine(
                  menuItemId: 'burger-meat',
                  name: 'Burger',
                  basePriceMinor: kBase,
                  quantity: 2,
                  modifiers: [current240],
                ),
              ],
            ),
          ),
        );
        final reloaded = await store.load(scope);
        expect(reloaded.unreadable, isEmpty);
        final m = reloaded.carts.single.draft.lines.single.modifiers.single;
        expect(m.modifierGroupId, 'grp-meat');
        expect(
          reloaded.carts.single.subtotalMinor,
          2 * (kBase + k240),
          reason: 'the 002A per-unit rule survives the round-trip',
        );
      },
    );

    testWidgets('G4 a NOTE-only edit preserves the group id and the money', (
      tester,
    ) async {
      final c = await pump(tester, groups: const [], selections: [current240]);
      await openEdit(tester, c);
      await tester.enterText(find.byType(TextField).last, 'no pickles');
      await tester.pump();
      await save(tester);

      final line = viewOf(c).lines.single;
      expect(line.note, 'no pickles');
      expect(line.modifiers.single.modifierGroupId, 'grp-meat');
      expect(line.modifiers.single.priceDeltaMinor, k240);
      expect(line.lineTotalMinor, kBase + k240);
    });

    test('G5 the ORDER WIRE payload carries NO group id — the isolation this '
        'phase depends on', () async {
      // This is not cosmetic. The SERVER's operation content fingerprint is
      // payload-wide, so a local key that leaked onto the wire would change the
      // fingerprint of every configured order and make old and new clients
      // disagree about whether two submissions are the same operation.
      final repo = _RecordingRepo();
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          outboxRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      c.read(cartControllerProvider.notifier).addItemWithModifiers(burger, [
        current240,
      ]);
      final view = c.read(cartControllerProvider);
      // The LOCAL record does carry it...
      expect(view.lines.single.modifiers.single.modifierGroupId, 'grp-meat');

      await c
          .read(outboxControllerProvider.notifier)
          .submit(
            lines: view.lines,
            subtotalMinor: view.subtotalMinor,
            currencyCode: view.currencyCode,
            orderType: OrderType.takeaway,
          );

      // ...and the WIRE does not, anywhere in the serialized body.
      final raw = repo.enqueued.single.payloadJson;
      expect(
        raw.contains('modifier_group_id'),
        isFalse,
        reason: 'a local-only key reached the order payload',
      );
      expect(raw.contains('grp-meat'), isFalse);

      final items =
          ((jsonDecode(raw) as Map<String, Object?>)['order_items']! as List)
              .cast<Map<String, Object?>>();
      final mod = (items.single['modifiers']! as List)
          .cast<Map<String, Object?>>()
          .single;
      expect(
        mod.keys.toSet(),
        <String>{
          'modifier_option_id',
          'option_name_snapshot',
          'modifier_name_snapshot',
          'price_minor_snapshot',
          'quantity',
        },
        reason: 'the wire modifier key set must be unchanged by this phase',
      );
      expect(mod['price_minor_snapshot'], k240);
    });
  });

  // =========================================================================
  group('H. the corrected 002A formula survives every edit path', () {
    for (final qty in <int>[1, 2, 3]) {
      testWidgets('H1 quantity $qty: line = qty x (base + mods)', (
        tester,
      ) async {
        final c = await pump(
          tester,
          groups: const [meatGroup],
          selections: [current240],
        );
        final lineId = viewOf(c).lines.single.lineId;
        for (var i = 1; i < qty; i++) {
          c.read(cartControllerProvider.notifier).increaseQuantity(lineId);
        }
        await tester.pump();
        expect(viewOf(c).lines.single.lineTotalMinor, qty * (kBase + k240));

        await openEdit(tester, c);
        await save(tester);
        expect(
          viewOf(c).lines.single.lineTotalMinor,
          qty * (kBase + k240),
          reason: 'an unchanged Save must not move the money at any quantity',
        );
      });

      testWidgets('H2 quantity $qty: changing the option keeps the rule', (
        tester,
      ) async {
        final c = await pump(
          tester,
          groups: const [meatGroup],
          selections: [current240],
        );
        final lineId = viewOf(c).lines.single.lineId;
        for (var i = 1; i < qty; i++) {
          c.read(cartControllerProvider.notifier).increaseQuantity(lineId);
        }
        await tester.pump();

        await openEdit(tester, c);
        await tester.tap(find.text('360g'));
        await tester.pump();
        await save(tester);

        expect(viewOf(c).lines.single.lineTotalMinor, qty * (kBase + k360));
        expect(viewOf(c).subtotalMinor, qty * (kBase + k360));
      });
    }
  });
}
