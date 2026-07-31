import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/draft_recovery_store.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MONEY-LOCAL-DECODE-INTEGRITY-002B — Codex Blocker 6.
///
/// Now that the decoders REFUSE a record they cannot read exactly, the stores
/// must not turn that refusal into a deletion. Both of them load by decoding
/// and persist by re-serializing ONLY what decoded, so the first ordinary write
/// after an unreadable record appears erases it permanently — the cashier's
/// rejected-order recovery or a whole day's order, gone, with a build that
/// simply did not understand one field.
///
/// A record we cannot read is not a record we are entitled to destroy. It is
/// preserved VERBATIM, exactly as `ParkedCartsSnapshot.unreadable` already
/// does, so a later build that CAN read it still finds it.
///
/// These tests exercise the REAL serialized payload through
/// `shared_preferences`, never an in-memory double.

// ---------------------------------------------------------------------------
// Draft recovery
// ---------------------------------------------------------------------------
const String _recoveryKey = 'restoflow.pos.draft_recovery.v1';

PosDraftRecovery _recovery(String entryId) => PosDraftRecovery(
  draft: const CartDraftSnapshot(
    currencyCode: 'ILS',
    lines: [
      CartDraftLine(
        menuItemId: 'burger-9',
        name: 'Burger',
        basePriceMinor: 4500,
        quantity: 2,
      ),
    ],
  ),
  orderType: OrderType.takeaway,
  outboxEntryId: entryId,
  binding: const PosRecoveryBinding(
    scopeKey: 'scope-1',
    employeeProfileId: 'worker-1',
  ),
);

/// A record whose LINE MONEY this build cannot read. It is not garbage — it is
/// a real recovery whose base price arrived in a shape we refuse to guess at.
Map<String, Object?> _unreadableRecovery(String entryId) {
  final json = _recovery(entryId).toJson();
  final draft = (json['draft']! as Map).cast<String, Object?>();
  final lines = (draft['lines']! as List).cast<Object?>();
  final line = (lines.first! as Map).cast<String, Object?>();
  line['base_price_minor'] = '4500'; // a string, not an integer
  return json;
}

Future<SharedPreferences> _seedRecoveries(Map<String, Object?> records) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _recoveryKey: jsonEncode(<String, Object?>{
      'version': SharedPrefsDraftRecoveryStore.schemaVersion,
      'recoveries': records,
    }),
  });
  return SharedPreferences.getInstance();
}

Map<String, Object?> _storedRecoveries(SharedPreferences prefs) {
  final raw = prefs.getString(_recoveryKey);
  expect(raw, isNotNull, reason: 'the envelope itself was removed');
  final decoded = (jsonDecode(raw!) as Map).cast<String, Object?>();
  return (decoded['recoveries']! as Map).cast<String, Object?>();
}

// ---------------------------------------------------------------------------
// Recent orders
// ---------------------------------------------------------------------------
const String _ordersKey = 'restoflow.pos.recent_orders.v1.till-1';

Map<String, Object?> _recentOrder(String number, {Object? subtotal = 9000}) =>
    <String, Object?>{
      'order': <String, Object?>{
        'order_number': number,
        'currency_code': 'ILS',
        'order_type': 'takeaway',
        'subtotal_minor': subtotal,
        'discount_total_minor': 0,
        'tax_total_minor': 0,
        'tax_rate_bp': 0,
        'lines': <Object?>[
          <String, Object?>{
            'name': 'Burger',
            'quantity': 2,
            'line_total_minor': 9000,
            'currency_code': 'ILS',
            'modifiers': <Object?>[],
          },
        ],
      },
      'submitted_at': '2026-08-05T09:00:00.000Z',
    };

Future<SharedPreferences> _seedOrders(List<Object?> entries) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _ordersKey: jsonEncode(<String, Object?>{
      'version': SharedPrefsRecentOrdersStore.schemaVersion,
      'orders': entries,
    }),
  });
  return SharedPreferences.getInstance();
}

List<Object?> _storedOrders(SharedPreferences prefs) {
  final raw = prefs.getString(_ordersKey);
  expect(raw, isNotNull, reason: 'the envelope itself was removed');
  final decoded = (jsonDecode(raw!) as Map).cast<String, Object?>();
  return (decoded['orders']! as List).cast<Object?>();
}

void main() {
  group('D. an unreadable DRAFT RECOVERY survives an ordinary write', () {
    test('D0 the readable record still loads and the unreadable one does not '
        '— the premise of every case below', () async {
      final prefs = await _seedRecoveries(<String, Object?>{
        'ok': _recovery('ok').toJson(),
        'bad': _unreadableRecovery('bad'),
      });
      final loaded = await SharedPrefsDraftRecoveryStore(prefs).load();
      expect(loaded.keys, <String>['ok']);
    });

    test('D1 persisting the readable set PRESERVES the unreadable record '
        'VERBATIM', () async {
      final seeded = _unreadableRecovery('bad');
      final prefs = await _seedRecoveries(<String, Object?>{
        'ok': _recovery('ok').toJson(),
        'bad': seeded,
      });
      final store = SharedPrefsDraftRecoveryStore(prefs);
      final loaded = await store.load();

      await store.persist(loaded);

      final stored = _storedRecoveries(prefs);
      expect(
        stored.keys.toSet(),
        <String>{'ok', 'bad'},
        reason: 'the unreadable recovery was DELETED by an ordinary write',
      );
      expect(
        jsonEncode(stored['bad']),
        jsonEncode(seeded),
        reason: 'a preserved record must be byte-identical, never re-encoded',
      );
    });

    test('D2 preservation does not depend on this instance having LOADED '
        'first — a fresh store must not wipe what it never read', () async {
      final seeded = _unreadableRecovery('bad');
      final prefs = await _seedRecoveries(<String, Object?>{'bad': seeded});

      // A brand-new store instance, persisting straight away.
      await SharedPrefsDraftRecoveryStore(
        prefs,
      ).persist(<String, PosDraftRecovery>{'ok': _recovery('ok')});

      final stored = _storedRecoveries(prefs);
      expect(stored.keys.toSet(), <String>{'ok', 'bad'});
      expect(jsonEncode(stored['bad']), jsonEncode(seeded));
    });

    test('D3 a READABLE record REPLACES a quarantined one under the same key '
        '— no stale shadow, no duplicate', () async {
      final prefs = await _seedRecoveries(<String, Object?>{
        'e1': _unreadableRecovery('e1'),
      });
      final store = SharedPrefsDraftRecoveryStore(prefs);

      await store.persist(<String, PosDraftRecovery>{'e1': _recovery('e1')});

      final stored = _storedRecoveries(prefs);
      expect(stored.keys, <String>['e1']);
      final draft = (stored['e1']! as Map)['draft']! as Map;
      final line = ((draft['lines']! as List).first as Map);
      expect(
        line['base_price_minor'],
        4500,
        reason: 'the readable record must win, not the quarantined one',
      );
      // And it is genuinely readable again.
      expect((await store.load()).keys, <String>['e1']);
    });

    test('D4 an emptied recovery set still preserves the unreadable record — '
        'clearing what we CAN see never clears what we cannot', () async {
      final seeded = _unreadableRecovery('bad');
      final prefs = await _seedRecoveries(<String, Object?>{
        'ok': _recovery('ok').toJson(),
        'bad': seeded,
      });
      final store = SharedPrefsDraftRecoveryStore(prefs);

      await store.persist(const <String, PosDraftRecovery>{});

      final stored = _storedRecoveries(prefs);
      expect(stored.keys, <String>['bad']);
      expect(jsonEncode(stored['bad']), jsonEncode(seeded));
    });
  });

  group('E. an unreadable RECENT ORDER survives an ordinary write', () {
    test(
      'E0 the readable order still loads and the unreadable one does not',
      () async {
        final prefs = await _seedOrders(<Object?>[
          _recentOrder('A-1'),
          _recentOrder('A-2', subtotal: 'oops'),
        ]);
        final loaded = await SharedPrefsRecentOrdersStore(prefs).load('till-1');
        expect(loaded, hasLength(1));
        expect(loaded.single.orderNumber, 'A-1');
      },
    );

    test(
      'E1 persisting the readable set PRESERVES the unreadable order '
      'VERBATIM — a corrupt field must not cost the cashier the order',
      () async {
        final seeded = _recentOrder('A-2', subtotal: 'oops');
        final prefs = await _seedOrders(<Object?>[_recentOrder('A-1'), seeded]);
        final store = SharedPrefsRecentOrdersStore(prefs);
        final loaded = await store.load('till-1');

        await store.persist('till-1', loaded);

        final stored = _storedOrders(prefs);
        expect(
          stored,
          hasLength(2),
          reason: 'the unreadable order was DELETED by an ordinary write',
        );
        expect(
          stored.map((e) => jsonEncode(e)),
          contains(jsonEncode(seeded)),
          reason: 'a preserved order must be byte-identical, never re-encoded',
        );
      },
    );

    test('E2 a non-object entry is preserved too — we cannot read it, so we '
        'cannot judge it', () async {
      final prefs = await _seedOrders(<Object?>[
        _recentOrder('A-1'),
        'garbage',
      ]);
      final store = SharedPrefsRecentOrdersStore(prefs);

      await store.persist('till-1', await store.load('till-1'));

      expect(_storedOrders(prefs), contains('garbage'));
    });

    test(
      'E3 preservation is PER SCOPE — another till never inherits them',
      () async {
        final seeded = _recentOrder('A-2', subtotal: 'oops');
        final prefs = await _seedOrders(<Object?>[seeded]);
        final store = SharedPrefsRecentOrdersStore(prefs);

        await store.persist('till-2', const <PosRecentOrder>[]);

        expect(
          _storedOrders(prefs),
          hasLength(1),
          reason: "till-1's quarantined order must stay on till-1",
        );
        final other = prefs.getString('restoflow.pos.recent_orders.v1.till-2');
        expect(other, isNotNull);
        expect(
          (jsonDecode(other!) as Map)['orders'],
          isEmpty,
          reason: 'till-2 must not inherit another scope\'s quarantine',
        );
      },
    );

    test('E4 a fresh store that never LOADED still preserves', () async {
      final seeded = _recentOrder('A-2', subtotal: 'oops');
      final prefs = await _seedOrders(<Object?>[seeded]);

      await SharedPrefsRecentOrdersStore(
        prefs,
      ).persist('till-1', const <PosRecentOrder>[]);

      expect(_storedOrders(prefs).map((e) => jsonEncode(e)), <String>[
        jsonEncode(seeded),
      ]);
    });
  });
}
