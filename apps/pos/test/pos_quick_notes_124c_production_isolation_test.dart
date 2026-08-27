import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/operational_snapshot_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// POS-QUICK-NOTES-124C — the owner's binding release requirement, as tests.
///
/// **Production POS must never show a Quick Note the owner did not create.**
/// The ONLY authoritative source in real/authenticated mode is
/// `pos_menu.quick_note_presets`. Zero configured presets must mean zero chips
/// — not a default, not a suggestion, not the demo list.
///
/// `kDemoQuickNotePresets` exists so the feature is demonstrable without a
/// backend. This file is what keeps it on its side of the fence: it pins the
/// demo list to the demo branch, and pins every real-mode path — success,
/// empty, malformed, offline-with-snapshot and offline-without-snapshot — to
/// server data or to nothing at all.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    final out = _handler(function, params);
    if (out is Exception) throw out;
    return out;
  }
}

/// Records every load/save so a test can assert a path NEVER touched the store.
class _SpyStore implements PosOperationalSnapshotStore {
  _SpyStore({this.result = const PosOperationalSnapshotAbsent()});

  PosOperationalSnapshotReadResult result;
  final loads = <PosSyncScope>[];
  final saves = <PosOperationalSnapshot>[];

  @override
  Future<PosOperationalSnapshotReadResult> load(PosSyncScope scope) async {
    loads.add(scope);
    return result;
  }

  @override
  Future<void> save(PosSyncScope scope, PosOperationalSnapshot snapshot) async {
    saves.add(snapshot);
  }
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');
const _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);

/// Sentinel so a test can send NO key, an empty list, or a populated one.
const Object _absent = Object();

Map<String, dynamic> _envelope({Object? quickNotes = _absent}) => {
  'ok': true,
  'currency_code': 'ILS',
  'categories': [
    {'id': 'sides', 'name': 'Sides'},
  ],
  'items': [
    {
      'id': 'fries',
      'name': 'Fries',
      'base_price_minor': 1600,
      'menu_category_id': 'sides',
    },
  ],
  if (!identical(quickNotes, _absent)) 'quick_note_presets': quickNotes,
};

ProviderContainer _real({
  Object? Function(String fn, Map<String, dynamic> p)? handler,
  Map<String, dynamic>? envelope,
  _SpyStore? store,
}) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(
        _FakeTransport(handler ?? (fn, p) => envelope ?? _envelope()),
      ),
      posSyncSessionProvider.overrideWithValue(_session),
      posSyncScopeProvider.overrideWithValue(_scope),
      if (store != null)
        posOperationalSnapshotStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

ProviderContainer _demo({_SpyStore? store}) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      if (store != null)
        posOperationalSnapshotStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

PosMenuData _menuWithPresets(List<PosQuickNotePreset> presets) => PosMenuData(
  categories: const [
    DemoCategory(
      id: 'sides',
      name: 'Sides',
      icon: Icons.lunch_dining,
      color: Colors.orange,
    ),
  ],
  items: const [
    DemoMenuItem(
      id: 'fries',
      name: 'Fries',
      priceMinor: 1600,
      categoryId: 'sides',
      categoryName: 'Sides',
    ),
  ],
  currencyCode: 'ILS',
  quickNotePresets: presets,
);

void main() {
  group('A. real mode serves ONLY what the Dashboard configured', () {
    test('A1. no key in the envelope => ZERO chips', () async {
      final menu = await _real().read(posMenuProvider.future);
      expect(menu.quickNotePresets, isEmpty);
    });

    test('A2. an EMPTY server list => ZERO chips', () async {
      final menu = await _real(
        envelope: _envelope(quickNotes: const <Object?>[]),
      ).read(posMenuProvider.future);
      expect(menu.quickNotePresets, isEmpty);
    });

    test('A3. ONE configured preset => exactly that one', () async {
      final menu = await _real(
        envelope: _envelope(
          quickNotes: [
            {'id': 'q1', 'label': 'No pickles', 'display_order': 0},
          ],
        ),
      ).read(posMenuProvider.future);
      expect(menu.quickNotePresets.map((p) => p.label), ['No pickles']);
    });

    test(
      'A4. THREE configured presets => exactly those three, in order',
      () async {
        final menu = await _real(
          envelope: _envelope(
            quickNotes: [
              {'id': 'q1', 'label': 'Well done', 'display_order': 0},
              {'id': 'q2', 'label': 'No pickles', 'display_order': 1},
              {'id': 'q3', 'label': 'Sauce on the side', 'display_order': 2},
            ],
          ),
        ).read(posMenuProvider.future);
        expect(menu.quickNotePresets.map((p) => p.label), [
          'Well done',
          'No pickles',
          'Sauce on the side',
        ]);
      },
    );

    test(
      'A5. a disabled/deleted preset the server withholds simply is not there',
      () async {
        // The server serves only live + enabled rows, so from the POS side a
        // disabled or deleted preset is indistinguishable from one that never
        // existed — and must not be resurrected from anywhere on the client.
        final menu = await _real(
          envelope: _envelope(
            quickNotes: [
              {'id': 'q1', 'label': 'Still active', 'display_order': 0},
            ],
          ),
        ).read(posMenuProvider.future);
        expect(menu.quickNotePresets.map((p) => p.id), ['q1']);
        expect(
          menu.quickNotePresets.any((p) => p.label == 'No onions'),
          isFalse,
        );
      },
    );

    test('A6. NO demo label ever reaches a real-mode menu', () async {
      final demoLabels = kDemoQuickNotePresets.map((p) => p.label).toSet();
      for (final envelope in [
        _envelope(),
        _envelope(quickNotes: const <Object?>[]),
        _envelope(quickNotes: 'nonsense'),
        _envelope(
          quickNotes: [
            {'id': 'q1', 'label': 'Owner note', 'display_order': 0},
          ],
        ),
      ]) {
        final menu = await _real(
          envelope: envelope,
        ).read(posMenuProvider.future);
        for (final p in menu.quickNotePresets) {
          expect(
            demoLabels.contains(p.label),
            isFalse,
            reason: 'demo label "${p.label}" leaked into real mode',
          );
        }
      }
    });
  });

  group('B. the demo list stays on the demo side of the fence', () {
    test(
      'B1. demo mode DOES serve the demo presets (the list is reachable there)',
      () async {
        final menu = await _demo().read(posMenuProvider.future);
        expect(menu.quickNotePresets, isNotEmpty);
        expect(
          menu.quickNotePresets.map((p) => p.id),
          kDemoQuickNotePresets.map((p) => p.id),
        );
      },
    );

    test('B2. demo mode NEVER writes an operational snapshot', () async {
      // This is what makes a demo preset unserializable into production: the
      // demo branch returns before the snapshot writer is ever reached, so no
      // demo menu can be persisted and later served to a real till.
      final store = _SpyStore();
      await _demo(store: store).read(posMenuProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(store.saves, isEmpty);
      expect(store.loads, isEmpty);
    });

    test(
      'B3. offline real mode with NO snapshot FAILS CLOSED, never to demo',
      () async {
        final store = _SpyStore();
        final c = _real(
          handler: (fn, p) => const SyncTransportException(
            SyncTransportErrorKind.transient,
            message: 'offline',
          ),
          store: store,
        );
        await expectLater(
          c.read(posMenuProvider.future),
          throwsA(isA<PosMenuUnavailable>()),
        );
        // It looked for a snapshot and found none — and did NOT substitute demo.
        expect(store.loads, isNotEmpty);
      },
    );

    test(
      'B4. offline real mode serves the SNAPSHOT presets, not demo',
      () async {
        final store = _SpyStore(
          result: PosOperationalSnapshotLoaded(
            PosOperationalSnapshot(
              organizationId: _scope.organizationId,
              restaurantId: _scope.restaurantId,
              branchId: _scope.branchId,
              deviceId: _scope.deviceId,
              menu: _menuWithPresets(const [
                PosQuickNotePreset(
                  id: 'srv-1',
                  label: 'Owner configured',
                  displayOrder: 0,
                ),
              ]),
              fetchedAt: DateTime.utc(2026, 9, 1),
            ),
          ),
        );
        final menu = await _real(
          handler: (fn, p) => const SyncTransportException(
            SyncTransportErrorKind.transient,
            message: 'offline',
          ),
          store: store,
        ).read(posMenuProvider.future);
        expect(menu.quickNotePresets.map((p) => p.label), ['Owner configured']);
      },
    );

    test(
      'B5. an offline snapshot that carried NO presets stays empty',
      () async {
        final store = _SpyStore(
          result: PosOperationalSnapshotLoaded(
            PosOperationalSnapshot(
              organizationId: _scope.organizationId,
              restaurantId: _scope.restaurantId,
              branchId: _scope.branchId,
              deviceId: _scope.deviceId,
              menu: _menuWithPresets(const []),
              fetchedAt: DateTime.utc(2026, 9, 1),
            ),
          ),
        );
        final menu = await _real(
          handler: (fn, p) => const SyncTransportException(
            SyncTransportErrorKind.transient,
            message: 'offline',
          ),
          store: store,
        ).read(posMenuProvider.future);
        expect(menu.quickNotePresets, isEmpty);
      },
    );

    test(
      'B6. a real-mode success persists the SERVER presets verbatim',
      () async {
        final store = _SpyStore();
        await _real(
          envelope: _envelope(
            quickNotes: [
              {'id': 'q1', 'label': 'Owner note', 'display_order': 0},
            ],
          ),
          store: store,
        ).read(posMenuProvider.future);
        await Future<void>.delayed(Duration.zero);
        // Whatever was written came from the wire, never from the demo list.
        for (final s in store.saves) {
          expect(s.menu.quickNotePresets.map((p) => p.label), ['Owner note']);
        }
      },
    );
  });

  group('C. zero presets leaves the note field exactly as it was', () {
    testWidgets('C1. no chips, no band, and the note still works', (
      tester,
    ) async {
      String? captured;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () => ModifierSelectionSheet.show(
                    context,
                    item: const DemoMenuItem(
                      id: 'item-a',
                      name: 'Burger',
                      priceMinor: 4000,
                      categoryId: 'b',
                      categoryName: 'B',
                    ),
                    groups: const [
                      PosModifierGroup(
                        id: 'g',
                        menuItemId: 'item-a',
                        name: 'Extras',
                        options: [
                          PosModifierOption(
                            id: 'o',
                            name: 'Cheese',
                            priceDeltaMinor: 300,
                          ),
                        ],
                      ),
                    ],
                    currencyCode: 'ILS',
                    // The production default before the owner configures
                    // anything.
                    quickNotes: const <PosQuickNotePreset>[],
                    onConfirm: (_, note, _) => captured = note,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modifier-quick-notes')), findsNothing);
      expect(find.byKey(const Key('modifier-quick-notes-row')), findsNothing);
      expect(find.byKey(const Key('quick-note-more')), findsNothing);

      // And the manual field is untouched: typing still produces the note.
      final note = find.byKey(const Key('modifier-item-note'));
      await tester.ensureVisible(note);
      await tester.pumpAndSettle();
      await tester.enterText(note, 'typed by hand');
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('modifier-add-button'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(captured, 'typed by hand');
    });
  });
}
