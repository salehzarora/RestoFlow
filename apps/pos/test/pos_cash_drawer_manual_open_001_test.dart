@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/cash_drawer_manual_repository.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_submission.dart' show OutboxEntry;
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cash_drawer_manual_controller.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider;
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart'
    show posSyncSessionProvider;
import 'package:restoflow_pos/src/state/pos_shift_close_policy.dart'
    show posShiftCloseEnabledProvider;
import 'package:restoflow_pos/src/state/ready_notifications_controller.dart';
import 'package:restoflow_pos/src/widgets/cash_drawer_button.dart';
import 'package:restoflow_pos/src/widgets/device_settings_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// POS-CASH-DRAWER-MANUAL-OPEN-001 — the manual ("no-sale") cash-drawer open.
///
/// A. the server seam (unlock outcomes, no-sale push parsing, the record's
///    stable envelope);
/// B. the durable journal (append / pending / remove; unreadable never
///    overwritten);
/// C. the controller (locked by default, unlock binds one session, record
///    BEFORE pulse online, journal BEFORE pulse offline, the offline window in
///    SERVER time, refusals lock, one open at a time, cooldown from the pulse,
///    a journaled record leaves only on a server-traced verdict);
/// D. the widgets (hidden unless available, lock badge, PIN dialog that cannot
///    be dismissed mid-check, long-press lock, the ⋮ menu below
///    kPosDrawerInlineMinWidth, the controller alive while hidden);
/// E. the real POS bar with the drawer button (the BIZBOT symbol keeps its
///    room in en/ar/he).
///
/// Fakes only — no command ever reaches a real printer or server.

const _sessionA = SyncSession(pinSessionId: 'pin-a', deviceId: 'dev-1');
const _sessionB = SyncSession(pinSessionId: 'pin-b', deviceId: 'dev-1');

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.handler);

  final Future<Object?> Function(String fn, Map<String, dynamic> params)
  handler;
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    calls.add((function, params));
    return handler(function, params);
  }
}

class _FakeRepo implements CashDrawerManualRepository {
  DrawerUnlockOutcome unlockOutcome = DrawerUnlockOutcome(
    DrawerUnlockResult.unlocked,
    sessionExpiresAt: DateTime.utc(2026, 10, 6, 18),
  );
  NoSalePushResult pushResult = NoSalePushResult.recorded;
  Future<void>? pushGate;
  Future<void>? unlockGate;
  void Function()? onPush;
  final pins = <String>[];
  final pushed = <NoSaleRecord>[];
  final log = <String>[];

  @override
  Future<DrawerUnlockOutcome> verifyPin(String pin) async {
    pins.add(pin);
    if (unlockGate != null) await unlockGate;
    return unlockOutcome;
  }

  @override
  Future<NoSalePushResult> pushNoSale(NoSaleRecord record) async {
    pushed.add(record);
    log.add('push');
    if (pushGate != null) await pushGate;
    onPush?.call();
    return pushResult;
  }
}

class _FakeKicker implements ManualDrawerKicker {
  _FakeKicker(this.log);

  final List<String> log;
  bool available = true;
  bool succeed = true;
  int kicks = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> kick() async {
    kicks++;
    log.add('kick');
    return succeed;
  }
}

class _Ids implements ClientIdGenerator {
  int _n = 0;

  @override
  String newId() => 'op-${++_n}';
}

final _sessionState = StateProvider<SyncSession?>((ref) => _sessionA);
final _now = StateProvider<DateTime>((ref) => DateTime.utc(2026, 10, 6, 10));

({ProviderContainer c, _FakeRepo repo, _FakeKicker kicker}) _container({
  CashDrawerNoSaleJournal? journal,
}) {
  final repo = _FakeRepo();
  final kicker = _FakeKicker(repo.log);
  final c = ProviderContainer(
    overrides: [
      posSyncSessionProvider.overrideWith((ref) => ref.watch(_sessionState)),
      posCashDrawerManualRepositoryProvider.overrideWithValue(repo),
      posManualDrawerKickerProvider.overrideWithValue(kicker),
      posSyncClockProvider.overrideWith(
        (ref) =>
            () => ref.read(_now),
      ),
      clientIdGeneratorProvider.overrideWithValue(_Ids()),
      if (journal != null)
        posCashDrawerNoSaleJournalProvider.overrideWithValue(journal),
    ],
  );
  addTearDown(c.dispose);
  return (c: c, repo: repo, kicker: kicker);
}

CashDrawerManualController _ctrl(ProviderContainer c) =>
    c.read(posCashDrawerManualControllerProvider.notifier);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // -------------------------------------------------------------------------
  group('A. server seam', () {
    test('unlock maps every server token to a closed result', () async {
      final cases = <Object?, DrawerUnlockResult>{
        {'ok': false, 'error': 'invalid_pin'}: DrawerUnlockResult.wrongPin,
        {'ok': false, 'error': 'pin_locked'}: DrawerUnlockResult.pinLocked,
        {'ok': false, 'error': 'permission_denied'}:
            DrawerUnlockResult.permissionDenied,
        {'ok': false, 'error': 'invalid_device_type'}:
            DrawerUnlockResult.permissionDenied,
        {'ok': false, 'error': 'invalid_session'}:
            DrawerUnlockResult.sessionInvalid,
        {'ok': false, 'error': 'something_new'}: DrawerUnlockResult.unavailable,
        'not a map': DrawerUnlockResult.unavailable,
      };
      for (final entry in cases.entries) {
        final t = _FakeTransport((_, _) async => entry.key);
        final repo = RealCashDrawerManualRepository(t, _sessionA);
        expect((await repo.verifyPin('1234')).result, entry.value);
        expect(t.calls.single.$1, 'pos_verify_drawer_pin');
        expect(t.calls.single.$2, {
          'p_pin_session_id': 'pin-a',
          'p_device_id': 'dev-1',
          'p_pin': '1234',
        });
      }
    });

    test('unlock success returns the server session expiry', () async {
      final t = _FakeTransport(
        (_, _) async => {
          'ok': true,
          'session_expires_at': '2026-10-06T18:00:00Z',
          'server_now': '2026-10-06T10:00:30Z',
        },
      );
      final out = await RealCashDrawerManualRepository(
        t,
        _sessionA,
      ).verifyPin('1234');
      expect(out.result, DrawerUnlockResult.unlocked);
      expect(out.sessionExpiresAt, DateTime.utc(2026, 10, 6, 18));
      expect(out.serverNow, DateTime.utc(2026, 10, 6, 10, 0, 30));
    });

    test(
      'unlock: a transient failure is offline, anything else unavailable',
      () async {
        Future<DrawerUnlockResult> run(SyncTransportErrorKind kind) async =>
            (await RealCashDrawerManualRepository(
              _FakeTransport(
                (_, _) async => throw SyncTransportException(kind),
              ),
              _sessionA,
            ).verifyPin('1234')).result;
        expect(
          await run(SyncTransportErrorKind.transient),
          DrawerUnlockResult.offline,
        );
        expect(
          await run(SyncTransportErrorKind.server),
          DrawerUnlockResult.unavailable,
        );
        expect(
          await run(SyncTransportErrorKind.auth),
          DrawerUnlockResult.unavailable,
        );
      },
    );

    test('no-sale push parsing', () {
      Map<String, Object?> env(Map<String, Object?> r) => {
        'ok': true,
        'results': [
          {'local_operation_id': 'op-1', ...r},
        ],
      };
      final parse = RealCashDrawerManualRepository.parseNoSalePush;
      expect(
        parse(env({'status': 'applied', 'ok': true}), 'op-1'),
        NoSalePushResult.recorded,
      );
      expect(
        parse(env({'status': 'applied', 'idempotency_replay': true}), 'op-1'),
        NoSalePushResult.recorded,
      );
      expect(
        parse(
          env({
            'status': 'rejected',
            'ok': false,
            'error': 'permission_denied',
          }),
          'op-1',
        ),
        NoSalePushResult.denied,
      );
      expect(
        parse(
          env({
            'status': 'rejected',
            'error': 'rejected',
            'detail': 'revoked_employee',
          }),
          'op-1',
        ),
        NoSalePushResult.denied,
      );
      expect(
        parse(
          env({'status': 'rejected', 'error': 'unknown_operation_type'}),
          'op-1',
        ),
        NoSalePushResult.rejected,
      );
      expect(
        parse(
          env({'status': 'rejected', 'error': 'invalid_origin_session'}),
          'op-1',
        ),
        NoSalePushResult.rejected,
      );
      expect(
        parse(env({'status': 'conflict'}), 'op-1'),
        NoSalePushResult.rejected,
      );
      // No verdict about THIS record: kept and retried, never an online open.
      expect(
        parse(env({'status': 'applied'}), 'op-OTHER'),
        NoSalePushResult.unconfirmed,
      );
      expect(parse({'ok': true}, 'op-1'), NoSalePushResult.unconfirmed);
      expect(parse('garbage', 'op-1'), NoSalePushResult.unconfirmed);
    });

    test('push sends under the CURRENT session; the payload names the '
        'session that made the open; byte-stable', () async {
      final t = _FakeTransport(
        (_, p) async => {
          'results': [
            {'local_operation_id': 'op-9', 'status': 'applied', 'ok': true},
          ],
        },
      );
      // The CURRENT session is B; the record belongs to A.
      final repo = RealCashDrawerManualRepository(t, _sessionB);
      final record = NoSaleRecord(
        localOperationId: 'op-9',
        pinSessionId: 'pin-a',
        deviceId: 'dev-1',
        occurredAt: DateTime.utc(2026, 10, 6, 9, 30),
      );
      expect(await repo.pushNoSale(record), NoSalePushResult.recorded);
      final (fn, params) = t.calls.single;
      expect(fn, 'sync_push');
      expect(params['p_pin_session_id'], 'pin-b');
      expect(params['p_device_id'], 'dev-1');
      expect(params['p_operations'], [
        {
          'local_operation_id': 'op-9',
          'operation_type': 'cash_drawer.no_sale_open',
          'target_entity': 'cash_drawer',
          'payload': {
            'client_occurred_at': '2026-10-06T09:30:00.000Z',
            'origin_pin_session_id': 'pin-a',
          },
        },
      ]);
      expect(record.toOperation(), params['p_operations'][0]);
    });

    test('push: auth is sessionInvalid, transient/timeout offline', () async {
      Future<NoSalePushResult> run(Object Function() thrower) =>
          RealCashDrawerManualRepository(
            _FakeTransport((_, _) async => throw thrower()),
            _sessionA,
          ).pushNoSale(
            NoSaleRecord(
              localOperationId: 'x',
              pinSessionId: 'pin-a',
              deviceId: 'dev-1',
              occurredAt: DateTime.utc(2026),
            ),
          );
      expect(
        await run(
          () => const SyncTransportException(SyncTransportErrorKind.auth),
        ),
        NoSalePushResult.sessionInvalid,
      );
      expect(
        await run(
          () => const SyncTransportException(SyncTransportErrorKind.transient),
        ),
        NoSalePushResult.offline,
      );
      expect(await run(() => TimeoutException('t')), NoSalePushResult.offline);
      // A server that ANSWERED, an unproven device session (the request never
      // left the till) or an unexpected error is NOT "offline": no online open.
      expect(
        await run(
          () => const SyncTransportException(SyncTransportErrorKind.server),
        ),
        NoSalePushResult.unconfirmed,
      );
      expect(
        await run(
          () => const SyncTransportException(SyncTransportErrorKind.unknown),
        ),
        NoSalePushResult.unconfirmed,
      );
      expect(
        await run(
          () => const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: 'device_session_unverified',
          ),
        ),
        NoSalePushResult.unconfirmed,
      );
      expect(await run(() => StateError('x')), NoSalePushResult.unconfirmed);
      expect(
        await const RealCashDrawerManualRepository(null, null).pushNoSale(
          NoSaleRecord(
            localOperationId: 'x',
            pinSessionId: 'pin-a',
            deviceId: 'dev-1',
            occurredAt: DateTime.utc(2026),
          ),
        ),
        NoSalePushResult.offline,
      );
      final slow = RealCashDrawerManualRepository(
        _FakeTransport((_, _) => Completer<Object?>().future),
        _sessionA,
        pushTimeout: const Duration(milliseconds: 10),
      );
      expect(
        await slow.pushNoSale(
          NoSaleRecord(
            localOperationId: 'x',
            pinSessionId: 'pin-a',
            deviceId: 'dev-1',
            occurredAt: DateTime.utc(2026),
          ),
        ),
        NoSalePushResult.offline,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('B. journal', () {
    NoSaleRecord rec(String id) => NoSaleRecord(
      localOperationId: id,
      pinSessionId: 'pin-a',
      deviceId: 'dev-1',
      occurredAt: DateTime.utc(2026, 10, 6, 10),
    );

    test('append / pending / remove round-trip, oldest first', () async {
      final j = CashDrawerNoSaleJournal();
      expect(await j.append('dev-1', rec('a')), isTrue);
      expect(await j.append('dev-1', rec('b')), isTrue);
      expect(await j.append('dev-1', rec('a')), isTrue); // idempotent
      expect((await j.pending('dev-1')).map((r) => r.localOperationId), [
        'a',
        'b',
      ]);
      expect(await j.pending('dev-2'), isEmpty);
      await j.remove('dev-1', 'a');
      expect((await j.pending('dev-1')).map((r) => r.localOperationId), ['b']);
      await j.remove('dev-1', 'b');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(posNoSaleJournalStorageKey('dev-1')), isNull);
    });

    test(
      'a malformed RECORD survives every rewrite (never silently dropped)',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          posNoSaleJournalStorageKey(
            'dev-1',
          ): '{"v":1,"records":[{"id":"bad"},{"id":"a","pin_session_id":"pin-a",'
              '"device_id":"dev-1","at":"2026-10-06T10:00:00.000Z"}]}',
        });
        final j = CashDrawerNoSaleJournal();
        expect((await j.pending('dev-1')).map((r) => r.localOperationId), [
          'a',
        ]);
        expect(await j.append('dev-1', rec('b')), isTrue);
        await j.remove('dev-1', 'a');
        await j.remove('dev-1', 'b');
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(posNoSaleJournalStorageKey('dev-1')),
          contains('"id":"bad"'),
        );
      },
    );

    test('the journal is bounded: past the cap an append is refused', () async {
      final j = CashDrawerNoSaleJournal();
      for (var i = 0; i < kPosNoSaleJournalLimit; i++) {
        expect(await j.append('dev-1', rec('r$i')), isTrue);
      }
      expect(await j.append('dev-1', rec('one-too-many')), isFalse);
      expect(await j.pending('dev-1'), hasLength(kPosNoSaleJournalLimit));
    });

    test('an unreadable envelope is never overwritten', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        posNoSaleJournalStorageKey('dev-1'): '{not json',
      });
      final j = CashDrawerNoSaleJournal();
      expect(await j.append('dev-1', rec('a')), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(posNoSaleJournalStorageKey('dev-1')), '{not json');
    });
  });

  // -------------------------------------------------------------------------
  group('C. controller', () {
    test('locked by default: an open does nothing at all', () async {
      final t = _container();
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.needsUnlock);
      expect(t.repo.pushed, isEmpty);
      expect(t.kicker.kicks, 0);
    });

    test('a wrong PIN keeps it locked', () async {
      final t = _container();
      t.repo.unlockOutcome = const DrawerUnlockOutcome(
        DrawerUnlockResult.wrongPin,
      );
      expect(await _ctrl(t.c).unlock('9999'), DrawerUnlockResult.wrongPin);
      expect(_ctrl(t.c).isUnlocked, isFalse);
    });

    test(
      'unlock, then ONE tap: record FIRST, then pulse; cooldown de-bounces',
      () async {
        final t = _container();
        expect(await _ctrl(t.c).unlock('1234'), DrawerUnlockResult.unlocked);
        expect(_ctrl(t.c).isUnlocked, isTrue);
        expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.opened);
        expect(t.repo.log, ['push', 'kick']);
        expect(t.repo.pushed.single.pinSessionId, 'pin-a');

        // within 3s: ignored, nothing sent
        t.c.read(_now.notifier).state = DateTime.utc(2026, 10, 6, 10, 0, 2);
        expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.ignored);
        expect(t.kicker.kicks, 1);

        t.c.read(_now.notifier).state = DateTime.utc(2026, 10, 6, 10, 0, 4);
        expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.opened);
        expect(t.kicker.kicks, 2);
        expect(
          t.repo.pushed.map((r) => r.localOperationId).toSet().length,
          2,
          reason: 'every open is its own operation',
        );
      },
    );

    test('a refusal never pulses and LOCKS the button', () async {
      for (final (push, outcome) in [
        (NoSalePushResult.denied, ManualDrawerOpenOutcome.denied),
        (NoSalePushResult.sessionInvalid, ManualDrawerOpenOutcome.sessionEnded),
      ]) {
        final t = _container();
        await _ctrl(t.c).unlock('1234');
        t.repo.pushResult = push;
        expect(await _ctrl(t.c).open(), outcome);
        expect(t.kicker.kicks, 0);
        expect(_ctrl(t.c).isUnlocked, isFalse);
      }
    });

    test('a ledgered rejection or a server answer without a verdict never '
        'pulses (and journals nothing)', () async {
      for (final push in [
        NoSalePushResult.rejected,
        NoSalePushResult.unconfirmed,
      ]) {
        final journal = CashDrawerNoSaleJournal();
        final t = _container(journal: journal);
        await _ctrl(t.c).unlock('1234');
        t.repo.pushResult = push;
        expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.cannotRecord);
        expect(t.kicker.kicks, 0, reason: '$push');
        expect(await journal.pending('dev-1'), isEmpty, reason: '$push');
      }
    });

    test(
      'ONE open at a time: a second tap while one is in flight is ignored',
      () async {
        final t = _container();
        await _ctrl(t.c).unlock('1234');
        final gate = Completer<void>();
        t.repo.pushGate = gate.future;
        final first = _ctrl(t.c).open();
        expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.ignored);
        expect(await _ctrl(t.c).unlock('1234'), DrawerUnlockResult.unavailable);
        gate.complete();
        expect(await first, ManualDrawerOpenOutcome.opened);
        expect(t.repo.pushed, hasLength(1));
        expect(t.kicker.kicks, 1);
      },
    );

    test('the cooldown runs from the PULSE, not from the tap', () async {
      final t = _container();
      await _ctrl(t.c).unlock('1234');
      // A slow record: tapped at 10:00:00, recorded (and pulsed) at 10:00:05.
      t.repo.onPush = () =>
          t.c.read(_now.notifier).state = DateTime.utc(2026, 10, 6, 10, 0, 5);
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.opened);
      t.repo.onPush = null;
      t.c.read(_now.notifier).state = DateTime.utc(2026, 10, 6, 10, 0, 6);
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.ignored);
      expect(t.kicker.kicks, 1);
    });

    test('a session switch during an open keeps the in-flight guard', () async {
      final t = _container();
      final sub = t.c.listen(posCashDrawerManualControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await _ctrl(t.c).unlock('1234');
      final gate = Completer<void>();
      t.repo.pushGate = gate.future;
      t.repo.pushResult = NoSalePushResult.denied;
      final first = _ctrl(t.c).open();
      t.c.read(_sessionState.notifier).state = _sessionB;
      await Future<void>.delayed(Duration.zero);
      expect(t.c.read(posCashDrawerManualControllerProvider).busy, isTrue);
      expect(await _ctrl(t.c).unlock('5555'), DrawerUnlockResult.unavailable);
      gate.complete();
      expect(await first, ManualDrawerOpenOutcome.denied);
      expect(t.kicker.kicks, 0);
      expect(t.c.read(posCashDrawerManualControllerProvider).busy, isFalse);
    });

    test(
      'locked while an offline push was in flight: no offline open',
      () async {
        final journal = CashDrawerNoSaleJournal();
        final t = _container(journal: journal);
        await _ctrl(t.c).unlock('1234');
        final gate = Completer<void>();
        t.repo.pushGate = gate.future;
        t.repo.pushResult = NoSalePushResult.offline;
        final first = _ctrl(t.c).open();
        _ctrl(t.c).lock();
        gate.complete();
        expect(await first, ManualDrawerOpenOutcome.cannotRecord);
        expect(t.kicker.kicks, 0);
        expect(await journal.pending('dev-1'), isEmpty);
      },
    );

    test('the offline window and the record time are SERVER time', () async {
      final journal = CashDrawerNoSaleJournal();
      final t = _container(journal: journal);
      // The till's clock is 2h BEHIND: server 12:00 while the device says
      // 10:00. The session expires at 12:05 server time.
      t.repo.unlockOutcome = DrawerUnlockOutcome(
        DrawerUnlockResult.unlocked,
        sessionExpiresAt: DateTime.utc(2026, 10, 6, 12, 5),
        serverNow: DateTime.utc(2026, 10, 6, 12),
      );
      await _ctrl(t.c).unlock('1234');
      // Online: the record carries server time.
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.opened);
      expect(t.repo.pushed.single.occurredAt, DateTime.utc(2026, 10, 6, 12));
      // Offline: 5 minutes left in SERVER time is inside the 10-minute margin,
      // even though the device clock "sees" 2h05 left.
      t.c.read(_now.notifier).state = DateTime.utc(2026, 10, 6, 10, 0, 10);
      t.repo.pushResult = NoSalePushResult.offline;
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.cannotRecord);
      expect(t.kicker.kicks, 1);
      expect(await journal.pending('dev-1'), isEmpty);
    });

    test(
      'offline: journal FIRST, then pulse; the flush records it later',
      () async {
        final journal = CashDrawerNoSaleJournal();
        final t = _container(journal: journal);
        await _ctrl(t.c).unlock('1234');
        t.repo.pushResult = NoSalePushResult.offline;
        expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.opened);
        expect(t.kicker.kicks, 1);
        final pending = await journal.pending('dev-1');
        expect(pending.single.pinSessionId, 'pin-a');

        // connection back: the flush records it under its own session
        t.repo.pushResult = NoSalePushResult.recorded;
        await _ctrl(t.c).flushJournal();
        expect(await journal.pending('dev-1'), isEmpty);
        expect(
          t.repo.pushed.last.localOperationId,
          pending.single.localOperationId,
        );
      },
    );

    test('a journaled record leaves ONLY on a server-traced verdict', () async {
      final expectations = <NoSalePushResult, bool>{
        NoSalePushResult.recorded: true,
        NoSalePushResult.denied: true,
        NoSalePushResult.rejected: true,
        // The current session refused / no answer / no verdict: KEPT.
        NoSalePushResult.sessionInvalid: false,
        NoSalePushResult.offline: false,
        NoSalePushResult.unconfirmed: false,
      };
      for (final entry in expectations.entries) {
        final journal = CashDrawerNoSaleJournal();
        final t = _container(journal: journal);
        await _ctrl(t.c).unlock('1234');
        t.repo.pushResult = NoSalePushResult.offline;
        expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.opened);
        t.repo.pushResult = entry.key;
        await _ctrl(t.c).flushJournal();
        expect(
          (await journal.pending('dev-1')).isEmpty,
          entry.value,
          reason: '${entry.key}',
        );
        SharedPreferences.setMockInitialValues(<String, Object>{});
      }
    });

    test('an expired session keeps the record; the NEXT sign-in sends it, '
        'still naming the session that opened the drawer', () async {
      final journal = CashDrawerNoSaleJournal();
      final t = _container(journal: journal);
      final sub = t.c.listen(posCashDrawerManualControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await _ctrl(t.c).unlock('1234');
      t.repo.pushResult = NoSalePushResult.offline;
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.opened);
      // Back online, but A's session has expired meanwhile.
      t.repo.pushResult = NoSalePushResult.sessionInvalid;
      await _ctrl(t.c).flushJournal();
      expect(await journal.pending('dev-1'), hasLength(1));
      // B signs in: the session change flushes, and the record lands.
      t.repo.pushResult = NoSalePushResult.recorded;
      t.c.read(_sessionState.notifier).state = _sessionB;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(await journal.pending('dev-1'), isEmpty);
      expect(t.repo.pushed.last.pinSessionId, 'pin-a');
    });

    test('a disposed controller never schedules work', () async {
      final repo = _FakeRepo()..pushResult = NoSalePushResult.offline;
      final c = ProviderContainer(
        overrides: [
          posSyncSessionProvider.overrideWithValue(_sessionA),
          posCashDrawerManualRepositoryProvider.overrideWithValue(repo),
        ],
      );
      final ctrl = c.read(posCashDrawerManualControllerProvider.notifier);
      c.dispose();
      await ctrl.flushJournal();
      expect(repo.pushed, isEmpty);
    });

    test('offline near the session expiry: the drawer does NOT open', () async {
      final journal = CashDrawerNoSaleJournal();
      final t = _container(journal: journal);
      t.repo.unlockOutcome = DrawerUnlockOutcome(
        DrawerUnlockResult.unlocked,
        sessionExpiresAt: DateTime.utc(2026, 10, 6, 10, 5),
      );
      await _ctrl(t.c).unlock('1234');
      t.repo.pushResult = NoSalePushResult.offline;
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.cannotRecord);
      expect(t.kicker.kicks, 0);
      expect(await journal.pending('dev-1'), isEmpty);
    });

    test('offline with an unknown server expiry fails closed', () async {
      final t = _container();
      t.repo.unlockOutcome = const DrawerUnlockOutcome(
        DrawerUnlockResult.unlocked,
      );
      await _ctrl(t.c).unlock('1234');
      t.repo.pushResult = NoSalePushResult.offline;
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.cannotRecord);
      expect(t.kicker.kicks, 0);
    });

    test('offline with an unwritable journal does NOT open', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        posNoSaleJournalStorageKey('dev-1'): '{broken',
      });
      final t = _container(journal: CashDrawerNoSaleJournal());
      await _ctrl(t.c).unlock('1234');
      t.repo.pushResult = NoSalePushResult.offline;
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.cannotRecord);
      expect(t.kicker.kicks, 0);
    });

    test(
      'a printer send failure is reported (the open stays recorded)',
      () async {
        final t = _container();
        await _ctrl(t.c).unlock('1234');
        t.kicker.succeed = false;
        expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.sendFailed);
        expect(t.repo.pushed, hasLength(1));
      },
    );

    test('no drawer port: nothing is recorded or sent', () async {
      final t = _container();
      await _ctrl(t.c).unlock('1234');
      t.kicker.available = false;
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.noPrinter);
      expect(t.repo.pushed, isEmpty);
    });

    test('a different PIN session re-locks; lock() locks', () async {
      final t = _container();
      // keep the controller alive
      final sub = t.c.listen(posCashDrawerManualControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await _ctrl(t.c).unlock('1234');
      expect(_ctrl(t.c).isUnlocked, isTrue);
      t.c.read(_sessionState.notifier).state = _sessionB;
      await Future<void>.delayed(Duration.zero);
      expect(_ctrl(t.c).isUnlocked, isFalse);
      expect(await _ctrl(t.c).open(), ManualDrawerOpenOutcome.needsUnlock);

      await _ctrl(t.c).unlock('5555');
      expect(_ctrl(t.c).isUnlocked, isTrue);
      _ctrl(t.c).lock();
      expect(_ctrl(t.c).isUnlocked, isFalse);
    });

    test(
      'an unlock answered after the session changed unlocks nothing',
      () async {
        final t = _container();
        final sub = t.c.listen(
          posCashDrawerManualControllerProvider,
          (_, _) {},
        );
        addTearDown(sub.close);
        final gate = Completer<void>();
        t.repo.unlockOutcome = DrawerUnlockOutcome(
          DrawerUnlockResult.unlocked,
          sessionExpiresAt: DateTime.utc(2026, 10, 6, 18),
        );
        final slowRepo = _GatedRepo(t.repo, gate.future);
        final c2 = ProviderContainer(
          parent: t.c,
          overrides: [
            posCashDrawerManualRepositoryProvider.overrideWithValue(slowRepo),
            posCashDrawerManualControllerProvider.overrideWith(
              CashDrawerManualController.new,
            ),
          ],
        );
        addTearDown(c2.dispose);
        final ctrl = c2.read(posCashDrawerManualControllerProvider.notifier);
        final pending = ctrl.unlock('1234');
        t.c.read(_sessionState.notifier).state = _sessionB;
        gate.complete();
        expect(await pending, DrawerUnlockResult.sessionInvalid);
        expect(ctrl.isUnlocked, isFalse);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('D. widgets', () {
    Future<_FakeRepo> pump(
      WidgetTester tester, {
      required bool visible,
      double width = 1280,
      Locale locale = const Locale('en'),
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _FakeRepo();
      final kicker = _FakeKicker(repo.log);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posSyncSessionProvider.overrideWithValue(_sessionA),
            posCashDrawerManualRepositoryProvider.overrideWithValue(repo),
            posManualDrawerKickerProvider.overrideWithValue(kicker),
            posManualDrawerHardwareAvailableProvider.overrideWith(
              (ref) async => visible,
            ),
            staffCapabilitiesProvider.overrideWith(
              (ref) async => const PosStaffCapabilities(
                applyDiscount: true,
                applyFullComp: false,
                openCashDrawer: true,
              ),
            ),
            posShiftCloseEnabledProvider.overrideWith((ref) async => true),
            clientIdGeneratorProvider.overrideWithValue(_Ids()),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              appBar: AppBar(
                actions: const [CashDrawerButton(), DeviceSettingsMenu()],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('hidden when this till cannot pulse a drawer', (tester) async {
      await pump(tester, visible: false);
      expect(find.byKey(const Key('cash-drawer-button')), findsNothing);
      // ...but the controller (and the journal it re-sends) is alive anyway.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      expect(container.exists(posCashDrawerManualControllerProvider), isTrue);
      await tester.tap(find.byKey(const Key('device-settings-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cash-drawer-menu-item')), findsNothing);
    });

    testWidgets('the PIN dialog cannot be dismissed while the server checks', (
      tester,
    ) async {
      final repo = await pump(tester, visible: true);
      final gate = Completer<void>();
      repo.unlockGate = gate.future;
      await tester.tap(find.byKey(const Key('cash-drawer-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cash-drawer-pin-input')),
        '1234',
      );
      await tester.tap(find.byKey(const Key('cash-drawer-unlock-submit')));
      await tester.pump();
      await tester.tapAt(const Offset(5, 795)); // the barrier
      await tester.pump();
      expect(find.text('Unlock the cash drawer'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Unlock the cash drawer'), findsNothing);
      expect(repo.log, ['push', 'kick']);
    });

    for (final locale in const [Locale('ar'), Locale('he')]) {
      testWidgets('${locale.languageCode}: button, PIN dialog and menu render '
          'localized (RTL)', (tester) async {
        await pump(tester, visible: true, locale: locale);
        final l10n = await AppLocalizations.delegate.load(locale);
        await tester.tap(find.byKey(const Key('cash-drawer-button')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.posCashDrawerUnlockTitle), findsOneWidget);
        expect(
          Directionality.of(
            tester.element(find.text(l10n.posCashDrawerUnlockTitle)),
          ),
          TextDirection.rtl,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('cash-drawer-unlock-cancel')));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(390, 800);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('device-settings-menu')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.posCashDrawerManualOpen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the app-bar button needs kPosDrawerInlineMinWidth; below it '
        'the ⋮ menu carries the action', (tester) async {
      await pump(tester, visible: true, width: kPosDrawerInlineMinWidth - 40);
      expect(find.byKey(const Key('cash-drawer-button')), findsNothing);
      await tester.tap(find.byKey(const Key('device-settings-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cash-drawer-menu-item')), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(kPosDrawerInlineMinWidth, 800);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cash-drawer-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('device-settings-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cash-drawer-menu-item')), findsNothing);
    });

    testWidgets('selecting the ⋮ entry runs the same unlock-then-open path', (
      tester,
    ) async {
      final repo = await pump(tester, visible: true, width: 390);
      await tester.tap(find.byKey(const Key('device-settings-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cash-drawer-menu-item')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cash-drawer-pin-input')),
        '1234',
      );
      await tester.tap(find.byKey(const Key('cash-drawer-unlock-submit')));
      await tester.pumpAndSettle();
      expect(repo.log, ['push', 'kick']);
      // Let the "opened" snackbar clear before the next one.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      // Unlocked now: the menu offers the lock entry, and it locks.
      await tester.tap(find.byKey(const Key('device-settings-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cash-drawer-lock-menu-item')));
      await tester.pumpAndSettle();
      expect(find.text('Cash drawer button locked'), findsOneWidget);
    });

    testWidgets(
      'locked badge -> PIN dialog -> unlock opens the drawer at once',
      (tester) async {
        final repo = await pump(tester, visible: true);
        expect(find.byKey(const Key('cash-drawer-button')), findsOneWidget);
        expect(find.byKey(const Key('cash-drawer-lock-badge')), findsOneWidget);

        await tester.tap(find.byKey(const Key('cash-drawer-button')));
        await tester.pumpAndSettle();
        expect(find.text('Unlock the cash drawer'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('cash-drawer-pin-input')),
          '1234',
        );
        await tester.tap(find.byKey(const Key('cash-drawer-unlock-submit')));
        await tester.pumpAndSettle();

        expect(repo.pins, ['1234']);
        expect(repo.log, ['push', 'kick']);
        expect(find.text('Cash drawer opened'), findsOneWidget);
        expect(find.byKey(const Key('cash-drawer-lock-badge')), findsNothing);

        // long press locks it again
        await tester.pump(const Duration(seconds: 5));
        await tester.longPress(find.byKey(const Key('cash-drawer-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cash-drawer-lock-badge')), findsOneWidget);
        expect(find.text('Cash drawer button locked'), findsOneWidget);
      },
    );

    testWidgets('a wrong PIN stays in the dialog with the error', (
      tester,
    ) async {
      final repo = await pump(tester, visible: true);
      repo.unlockOutcome = const DrawerUnlockOutcome(
        DrawerUnlockResult.wrongPin,
      );
      await tester.tap(find.byKey(const Key('cash-drawer-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cash-drawer-pin-input')),
        '9999',
      );
      await tester.tap(find.byKey(const Key('cash-drawer-unlock-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Unlock the cash drawer'), findsOneWidget);
      expect(find.text('Wrong PIN — try again.'), findsOneWidget);
      expect(repo.log, isEmpty);
    });

    testWidgets(
      'compact bar: no app-bar button; the ⋮ menu carries the action',
      (tester) async {
        await pump(tester, visible: true, width: 390);
        expect(find.byKey(const Key('cash-drawer-button')), findsNothing);
        await tester.tap(find.byKey(const Key('device-settings-menu')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cash-drawer-menu-item')), findsOneWidget);
        expect(find.text('Open cash drawer'), findsOneWidget);
        expect(
          find.byKey(const Key('cash-drawer-lock-menu-item')),
          findsNothing,
          reason: 'nothing to lock while locked',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  group('E. the real POS bar with the drawer button', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('he')]) {
      for (final width in const [
        520.0,
        kPosDrawerInlineMinWidth,
        820.0,
        1280.0,
      ]) {
        testWidgets('${locale.languageCode} @ ${width.toInt()}px: the button '
            'placement and the BIZBOT symbol keeps its room', (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                posReadyNotificationsControllerProvider.overrideWith(
                  _QuietReady.new,
                ),
                outboxControllerProvider.overrideWith(_QuietOutbox.new),
                posManualDrawerVisibleProvider.overrideWithValue(true),
              ],
              child: MaterialApp(
                locale: locale,
                localizationsDelegates: restoflowLocalizationsDelegates,
                supportedLocales: kSupportedLocales,
                home: const PosMenuScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final inline = width >= kPosDrawerInlineMinWidth;
          expect(
            find.byKey(const Key('cash-drawer-button')),
            inline ? findsOneWidget : findsNothing,
            reason: 'below the threshold the ⋮ menu carries the action',
          );
          final plate = tester.getRect(find.byKey(const Key('pos-brand-tile')));
          expect(
            plate.width,
            greaterThanOrEqualTo(40),
            reason: 'the symbol plate is never squeezed out by the button',
          );
          if (inline) {
            expect(
              plate.overlaps(
                tester.getRect(find.byKey(const Key('cash-drawer-button'))),
              ),
              isFalse,
            );
          }
        });
      }
    }
  });
}

class _QuietReady extends PosReadyNotificationsController {
  @override
  PosReadyNotificationsState build() =>
      const PosReadyNotificationsState(initialized: true, records: []);
}

class _QuietOutbox extends OutboxController {
  @override
  List<OutboxEntry> build() => const [];
}

class _GatedRepo implements CashDrawerManualRepository {
  _GatedRepo(this._inner, this._gate);

  final CashDrawerManualRepository _inner;
  final Future<void> _gate;

  @override
  Future<DrawerUnlockOutcome> verifyPin(String pin) async {
    await _gate;
    return _inner.verifyPin(pin);
  }

  @override
  Future<NoSalePushResult> pushNoSale(NoSaleRecord record) =>
      _inner.pushNoSale(record);
}
