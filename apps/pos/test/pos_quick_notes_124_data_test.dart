import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/operational_snapshot_codec.dart';
import 'package:restoflow_pos/src/data/operational_snapshot_store.dart';
import 'package:restoflow_pos/src/format/quick_note_insertion.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// POS-QUICK-NOTES-124 — the DATA half: what the POS makes of the additive
/// `quick_note_presets` key, and what survives a reboot with no network.
///
/// The rules under test are deliberately the OPPOSITE of the money rules that
/// surround them. Everywhere else in this parse a record we cannot read fails
/// the whole menu, because a half-read menu is a silent under-charge. A quick
/// note carries no price at all: a bad one costs the cashier a chip, so it is
/// skipped, and a missing key simply means "no chips" — which is precisely the
/// behaviour a server that has not taken the migration must produce.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async =>
      _handler(function, params);
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

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

/// Sentinel: distinguishes "the server sent no key" from "the server sent null".
const Object _absent = Object();

ProviderContainer _container(Map<String, dynamic> envelope) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(
        _FakeTransport((fn, p) => envelope),
      ),
      posSyncSessionProvider.overrideWithValue(_session),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

PosMenuData _menuWith(List<PosQuickNotePreset> presets) => PosMenuData(
  categories: const [
    DemoCategory(
      id: 'sides',
      name: 'Sides',
      icon: Icons.lunch_dining,
      color: RestoflowCategoryPalette.terracotta,
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
  group('A. the pos_menu envelope', () {
    test(
      'A1. a server without the key yields NO chips, not an error',
      () async {
        final menu = await _container(_envelope()).read(posMenuProvider.future);
        expect(menu.quickNotePresets, isEmpty);
        // The rest of the menu is untouched — this is the pre-124 backend.
        expect(menu.items, hasLength(1));
        expect(menu.currencyCode, 'ILS');
      },
    );

    test('A2. presets are read in the order the server sent them', () async {
      final menu = await _container(
        _envelope(
          quickNotes: [
            {'id': 'q1', 'label': 'Well done', 'display_order': 0},
            {'id': 'q2', 'label': 'No onions', 'display_order': 1},
            {'id': 'q3', 'label': 'Extra crispy', 'display_order': 2},
          ],
        ),
      ).read(posMenuProvider.future);
      expect(menu.quickNotePresets.map((p) => p.label), [
        'Well done',
        'No onions',
        'Extra crispy',
      ]);
      expect(menu.quickNotePresets.map((p) => p.displayOrder), [0, 1, 2]);
      expect(menu.quickNotePresets.first.id, 'q1');
    });

    test('A3. tenant text is preserved byte-for-byte, in any script', () async {
      final menu = await _container(
        _envelope(
          quickNotes: [
            {'id': 'q1', 'label': '  بدون بصل  ', 'display_order': 0},
            {'id': 'q2', 'label': 'בלי בצל', 'display_order': 1},
          ],
        ),
      ).read(posMenuProvider.future);
      // Outer whitespace is normalized (the server stores it trimmed); the
      // Arabic and Hebrew content itself is never touched or transliterated.
      expect(menu.quickNotePresets.map((p) => p.label), [
        'بدون بصل',
        'בלי בצל',
      ]);
    });

    test('A4. a malformed record is SKIPPED — the menu still loads', () async {
      final menu = await _container(
        _envelope(
          quickNotes: [
            {'id': 'q1', 'label': 'Good'},
            'not a record',
            {'label': 'no id'},
            {'id': 'q4'},
            {'id': '', 'label': 'blank id'},
            {'id': 'q6', 'label': 42},
            {'id': 'q7', 'label': 'Also good'},
          ],
        ),
      ).read(posMenuProvider.future);
      expect(menu.quickNotePresets.map((p) => p.id), ['q1', 'q7']);
      // And, crucially, the SELLABLE menu came through untouched: a broken note
      // phrase must never take a till offline.
      expect(menu.items, hasLength(1));
    });

    test('A5. a non-list value degrades to no chips', () async {
      final menu = await _container(
        _envelope(quickNotes: 'nonsense'),
      ).read(posMenuProvider.future);
      expect(menu.quickNotePresets, isEmpty);
      expect(menu.items, hasLength(1));
    });

    test(
      'A6. a missing display_order falls back to 0, never to null',
      () async {
        final menu = await _container(
          _envelope(
            quickNotes: [
              {'id': 'q1', 'label': 'No order'},
            ],
          ),
        ).read(posMenuProvider.future);
        expect(menu.quickNotePresets.single.displayOrder, 0);
      },
    );
  });

  group('B. the offline snapshot', () {
    test('B1. the schema version is UNCHANGED — no cached menu is discarded', () {
      // The key is optional in both directions, so a bump would be gratuitous:
      // it would throw away every cached menu and strand any till that happened
      // to be offline across the upgrade.
      expect(PosOperationalSnapshot.schemaVersion, 1);
    });

    test('B2. presets round-trip with their labels and order intact', () {
      final menu = _menuWith(const [
        PosQuickNotePreset(id: 'q1', label: 'Well done', displayOrder: 0),
        PosQuickNotePreset(id: 'q2', label: 'بدون بصل', displayOrder: 1),
        PosQuickNotePreset(
          id: 'q3',
          label: 'Sauce on the side',
          displayOrder: 2,
        ),
      ]);
      final decoded = decodePosMenuData(encodePosMenuData(menu));
      expect(
        decoded.quickNotePresets.map(
          (p) => '${p.id}|${p.label}|${p.displayOrder}',
        ),
        ['q1|Well done|0', 'q2|بدون بصل|1', 'q3|Sauce on the side|2'],
      );
    });

    test('B3. an OLD snapshot without the key decodes to no chips', () {
      final encoded = encodePosMenuData(_menuWith(const []));
      // Written exactly as a pre-124 build would have written it.
      expect(encoded.containsKey('quick_note_presets'), isFalse);
      expect(decodePosMenuData(encoded).quickNotePresets, isEmpty);
    });

    test('B4. a malformed cached record is skipped, not fatal', () {
      final encoded = encodePosMenuData(
        _menuWith(const [
          PosQuickNotePreset(id: 'q1', label: 'Kept', displayOrder: 0),
        ]),
      );
      encoded['quick_note_presets'] = <Object?>[
        ...(encoded['quick_note_presets']! as List<Object?>),
        'garbage',
        <String, Object?>{'id': 'q2'},
      ];
      final decoded = decodePosMenuData(encoded);
      // The menu is still fully usable — the whole point of tolerating this.
      expect(decoded.items, hasLength(1));
      expect(decoded.quickNotePresets.map((p) => p.id), ['q1']);
    });

    test('B5. a non-list cached value degrades to no chips', () {
      final encoded = encodePosMenuData(
        _menuWith(const [
          PosQuickNotePreset(id: 'q1', label: 'Kept', displayOrder: 0),
        ]),
      );
      encoded['quick_note_presets'] = 'nonsense';
      expect(decodePosMenuData(encoded).quickNotePresets, isEmpty);
      expect(decodePosMenuData(encoded).items, hasLength(1));
    });
  });

  group('C. the insertion contract is shared, not re-stated', () {
    test('C1. the helper defaults to the note field\'s own limit', () {
      expect(kPosItemNoteMaxLength, 140);
    });
  });
}
