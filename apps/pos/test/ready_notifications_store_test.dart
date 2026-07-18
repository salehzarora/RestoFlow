import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/ready_feed_repository.dart';
import 'package:restoflow_pos/src/data/ready_notifications_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PSC-001A — the persisted per-scope notification envelope: atomic
/// cursor+records writes, the EXPLICIT initialized marker (cursor null is a
/// legitimate zero-row bootstrap), scope namespacing, and fail-safe reads.

const _scopeA = PosSyncScope(
  organizationId: 'org1',
  restaurantId: 'r1',
  branchId: 'branch-A',
  deviceId: 'dev1',
);
const _scopeB = PosSyncScope(
  organizationId: 'org1',
  restaurantId: 'r1',
  branchId: 'branch-B',
  deviceId: 'dev1',
);

PosReadyNotificationRecord _record({
  String type = 'initial_order',
  String id = '0a000000-0000-4000-8000-000000000001',
  bool read = false,
  bool alerted = false,
}) => PosReadyNotificationRecord(
  workUnitType: type,
  workUnitId: id,
  orderId: '0b000000-0000-4000-8000-000000000001',
  orderCode: '#A1B2C3',
  roundNumber: type == 'service_round' ? 2 : null,
  orderType: 'dine_in',
  tableLabel: 'T4',
  readyAt: '2026-07-23T10:00:00.123456+00:00',
  workUnitStatus: 'ready',
  parentOrderStatus: 'preparing',
  revision: 3,
  discoveredAt: '2026-07-23T10:00:06.000Z',
  read: read,
  alerted: alerted,
);

Future<SharedPrefsReadyNotificationsStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPrefsReadyNotificationsStore(
    await SharedPreferences.getInstance(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the envelope round-trips: initialized, bootstrap ts, VERBATIM cursor, '
      'records with sticky read/alerted', () async {
    final store = await _store();
    final env = PosReadyNotificationsEnvelope(
      initialized: true,
      bootstrapServerTs: '2026-07-23T10:00:05+00:00',
      cursor: const PosReadyCursor(
        readyAt: '2026-07-23T10:00:00.123456+00:00',
        workUnitType: 'initial_order',
        id: '0a000000-0000-4000-8000-000000000001',
      ),
      records: [
        _record(read: true, alerted: true),
        _record(
          type: 'service_round',
          id: '0a000000-0000-4000-8000-000000000002',
        ),
      ],
    );
    await store.persist(_scopeA, env);
    final loaded = await store.load(_scopeA);
    expect(loaded, isNotNull);
    expect(loaded!.initialized, isTrue);
    expect(loaded.bootstrapServerTs, '2026-07-23T10:00:05+00:00');
    expect(loaded.cursor!.readyAt, '2026-07-23T10:00:00.123456+00:00');
    expect(loaded.cursor!.workUnitType, 'initial_order');
    expect(loaded.records, hasLength(2));
    expect(loaded.records.first.read, isTrue);
    expect(loaded.records.first.alerted, isTrue);
    expect(loaded.records.last.read, isFalse);
    expect(loaded.records.last.roundNumber, 2);
  });

  test('initialized=true with cursor=null persists (a legitimate zero-row '
      'bootstrap — cursor presence is NEVER the first-run marker)', () async {
    final store = await _store();
    await store.persist(
      _scopeA,
      const PosReadyNotificationsEnvelope(
        initialized: true,
        bootstrapServerTs: '2026-07-23T10:00:05+00:00',
        records: [],
      ),
    );
    final loaded = await store.load(_scopeA);
    expect(loaded!.initialized, isTrue);
    expect(loaded.cursor, isNull);
    expect(loaded.records, isEmpty);
  });

  test('scopes are fully namespaced — branch B never sees branch A', () async {
    final store = await _store();
    await store.persist(
      _scopeA,
      PosReadyNotificationsEnvelope(initialized: true, records: [_record()]),
    );
    expect(await store.load(_scopeB), isNull);
    await store.clear(_scopeB); // clearing B never touches A
    final a = await store.load(_scopeA);
    expect(a!.records, hasLength(1));
  });

  test('a wrong-version or corrupt envelope reads as NULL (fresh bootstrap), '
      'never a throw and never partial state', () async {
    SharedPreferences.setMockInitialValues({
      'restoflow.pos.ready_notifications.v1.${_scopeA.key}': '{"version":99}',
      'restoflow.pos.ready_notifications.v1.${_scopeB.key}': 'not-json{{{',
    });
    final store = SharedPrefsReadyNotificationsStore(
      await SharedPreferences.getInstance(),
    );
    expect(await store.load(_scopeA), isNull);
    expect(await store.load(_scopeB), isNull);
  });

  test('one corrupt RECORD discards the whole envelope (atomic — partial '
      'local state is never trusted)', () async {
    final store = await _store();
    await store.persist(
      _scopeA,
      PosReadyNotificationsEnvelope(initialized: true, records: [_record()]),
    );
    final prefs = await SharedPreferences.getInstance();
    final key = 'restoflow.pos.ready_notifications.v1.${_scopeA.key}';
    final raw = prefs.getString(key)!;
    await prefs.setString(
      key,
      raw.replaceFirst(
        '"work_unit_type":"initial_order"',
        '"work_unit_type":"mystery"',
      ),
    );
    expect(await store.load(_scopeA), isNull);
  });

  test('a corrupt persisted CURSOR discards the envelope too', () async {
    final store = await _store();
    await store.persist(
      _scopeA,
      const PosReadyNotificationsEnvelope(
        initialized: true,
        cursor: PosReadyCursor(
          readyAt: '2026-07-23T10:00:00+00:00',
          workUnitType: 'initial_order',
          id: '0a000000-0000-4000-8000-000000000001',
        ),
        records: [],
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final key = 'restoflow.pos.ready_notifications.v1.${_scopeA.key}';
    final raw = prefs.getString(key)!;
    await prefs.setString(
      key,
      raw.replaceFirst('"work_unit_type":"initial_order"', '"id2":"x"'),
    );
    expect(await store.load(_scopeA), isNull);
  });

  test('the InMemory store honours the same contract', () async {
    final store = InMemoryReadyNotificationsStore();
    expect(await store.load(_scopeA), isNull);
    await store.persist(
      _scopeA,
      PosReadyNotificationsEnvelope(initialized: true, records: [_record()]),
    );
    expect((await store.load(_scopeA))!.records, hasLength(1));
    expect(await store.load(_scopeB), isNull);
    await store.clear(_scopeA);
    expect(await store.load(_scopeA), isNull);
  });
}
